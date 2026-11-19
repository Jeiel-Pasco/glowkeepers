--!strict
-- Lighting for dawn, day, dusk and night (TECH_SPEC §4), and the client's cycle clock.
--
-- Reads the cycle from workspace attributes (CycleEpoch, DayLen, NightLen, NightModifier) and
-- Shared.Cycle, so it needs no remotes. Every frame it blends between the keyframes below:
-- sun and ambient light, Atmosphere (density, colour, decay, glare, haze), Bloom, SunRays and a
-- ColorCorrection grade (Design & Asset Bible §1: golden-hour day, red dusk, deep blue-black
-- night lit by cyan and gold pools; the fire is always the warmest light). It creates the
-- effects it needs (client-side) if the place lacks them, and a Sky with stars. The place
-- should use Lighting.Technology = Future (tools/BuildGreybox.luau sets it). Tune LOOKS at the
-- G1 mood test (open decision OD-1).
--
-- Other controllers read CycleFXController.state() and listen to PhaseChanged.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cycle = require(Shared:WaitForChild("Cycle"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any

type Look = {
	clock: number, -- ClockTime; values above 24 wrap, so the list stays increasing
	brightness: number,
	ambient: Color3,
	outdoor: Color3,
	tint: Color3,
	haze: number, -- Atmosphere.Density
	air: Color3, -- Atmosphere.Color
	decay: Color3, -- Atmosphere.Decay
	glare: number, -- Atmosphere.Glare
	mist: number, -- Atmosphere.Haze
	saturation: number, -- ColorCorrection
	contrast: number,
	bloom: number, -- Bloom.Intensity
	rays: number, -- SunRays.Intensity
}
type Key = { at: number, look: Look }

local FOG_NIGHT_HAZE = 0.15 -- extra density on Fog nights

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- stylua: ignore
local LOOKS: { [string]: Look } = {
	dawn      = { clock = 6.4,  brightness = 1.6,  ambient = rgb(100, 85, 110), outdoor = rgb(160, 125, 140), tint = rgb(255, 228, 214), haze = 0.38, air = rgb(232, 178, 170), decay = rgb(125, 92, 122), glare = 0.3, mist = 1.6, saturation = 0.05, contrast = 0.05, bloom = 0.6, rays = 0.15 },
	day       = { clock = 9.0,  brightness = 2.6,  ambient = rgb(122, 116, 104), outdoor = rgb(150, 145, 132), tint = rgb(255, 248, 232), haze = 0.30, air = rgb(205, 218, 232), decay = rgb(130, 150, 165), glare = 0.2, mist = 1.0, saturation = 0.18, contrast = 0.08, bloom = 0.45, rays = 0.1 },
	afternoon = { clock = 15.8, brightness = 2.4,  ambient = rgb(128, 110, 92),  outdoor = rgb(165, 140, 118), tint = rgb(255, 236, 208), haze = 0.32, air = rgb(238, 206, 168), decay = rgb(155, 122, 100), glare = 0.4, mist = 1.5, saturation = 0.2,  contrast = 0.1,  bloom = 0.5,  rays = 0.2 },
	dusk      = { clock = 17.8, brightness = 1.6,  ambient = rgb(132, 70, 60),   outdoor = rgb(188, 90, 70),   tint = rgb(255, 188, 162), haze = 0.42, air = rgb(242, 138, 108), decay = rgb(112, 50, 72),  glare = 0.8, mist = 2.2, saturation = 0.15, contrast = 0.12, bloom = 0.7,  rays = 0.3 },
	nightfall = { clock = 19.0, brightness = 0.6,  ambient = rgb(40, 38, 76),    outdoor = rgb(46, 46, 92),    tint = rgb(214, 218, 255), haze = 0.45, air = rgb(70, 80, 132),   decay = rgb(30, 30, 62),   glare = 0,   mist = 1.5, saturation = 0.05, contrast = 0.12, bloom = 0.9,  rays = 0 },
	night     = { clock = 21.0, brightness = 0.2,  ambient = rgb(24, 30, 66),    outdoor = rgb(30, 38, 84),    tint = rgb(205, 212, 255), haze = 0.50, air = rgb(24, 34, 70),    decay = rgb(10, 12, 30),   glare = 0,   mist = 1.2, saturation = 0.1,  contrast = 0.18, bloom = 0.9,  rays = 0 },
	predawn   = { clock = 28.8, brightness = 0.25, ambient = rgb(30, 28, 56),    outdoor = rgb(40, 36, 72),    tint = rgb(218, 212, 245), haze = 0.45, air = rgb(62, 56, 102),   decay = rgb(30, 25, 56),   glare = 0,   mist = 1.4, saturation = 0.05, contrast = 0.12, bloom = 1.0,  rays = 0 },
}
local NEXT_DAWN: Look = table.clone(LOOKS.dawn)
NEXT_DAWN.clock += 24

local CycleFXController = {}
CycleFXController.PhaseChanged = Signal.new() -- (phase: Cycle.Phase, state: Cycle.State, initial: boolean)

local cycleConfig = { cycle = table.clone(economy.cycle) }
local epoch: number? = nil
local keys: { Key } = {}
local current: Cycle.State? = nil
local lastPhase: string? = nil
local lastIndex = -1
local tintEffect: ColorCorrectionEffect? = nil
local bloomEffect: BloomEffect? = nil
local raysEffect: SunRaysEffect? = nil
local atmosphereEffect: Atmosphere? = nil

local function buildKeys(): { Key }
	local c = cycleConfig.cycle
	local length = c.daySeconds + c.nightSeconds
	return {
		{ at = 0, look = LOOKS.dawn },
		{ at = math.min(30, c.duskWarningAt * 0.15), look = LOOKS.day },
		{ at = c.duskWarningAt * 0.85, look = LOOKS.afternoon },
		{ at = c.duskWarningAt, look = LOOKS.dusk },
		{ at = c.daySeconds, look = LOOKS.nightfall },
		{ at = c.daySeconds + math.min(15, c.nightSeconds * 0.15), look = LOOKS.night },
		{ at = length - math.min(15, c.nightSeconds * 0.15), look = LOOKS.predawn },
		{ at = length, look = NEXT_DAWN },
	}
end

local function readAttributes()
	local value = workspace:GetAttribute("CycleEpoch")
	epoch = if type(value) == "number" then value else nil
	local day = workspace:GetAttribute("DayLen")
	local night = workspace:GetAttribute("NightLen")
	local c = cycleConfig.cycle
	c.daySeconds = if type(day) == "number" then day else economy.cycle.daySeconds
	c.nightSeconds = if type(night) == "number" then night else economy.cycle.nightSeconds
	c.duskWarningAt = math.min(economy.cycle.duskWarningAt, c.daySeconds)
	keys = buildKeys()
end

local function smooth(alpha: number): number
	return alpha * alpha * (3 - 2 * alpha)
end

local function apply(t: number)
	local a, b, alpha = keys[#keys].look, keys[#keys].look, 0
	for i = 1, #keys - 1 do
		local k0, k1 = keys[i], keys[i + 1]
		if t <= k1.at then
			local span = k1.at - k0.at
			a, b = k0.look, k1.look
			alpha = smooth(if span > 0 then math.clamp((t - k0.at) / span, 0, 1) else 1)
			break
		end
	end

	Lighting.ClockTime = (a.clock + (b.clock - a.clock) * alpha) % 24
	Lighting.Brightness = a.brightness + (b.brightness - a.brightness) * alpha
	Lighting.Ambient = a.ambient:Lerp(b.ambient, alpha)
	Lighting.OutdoorAmbient = a.outdoor:Lerp(b.outdoor, alpha)
	local function mix(key: string): number
		local x, y = (a :: any)[key], (b :: any)[key]
		return x + (y - x) * alpha
	end
	if tintEffect ~= nil then
		tintEffect.TintColor = a.tint:Lerp(b.tint, alpha)
		tintEffect.Saturation = mix("saturation")
		tintEffect.Contrast = mix("contrast")
	end
	if bloomEffect ~= nil then
		bloomEffect.Intensity = mix("bloom")
	end
	if raysEffect ~= nil then
		raysEffect.Intensity = mix("rays")
	end

	local atmosphere = atmosphereEffect
	if atmosphere ~= nil then
		local haze = mix("haze")
		if current ~= nil and current.phase == "Night" and workspace:GetAttribute("NightModifier") == "Fog" then
			haze += FOG_NIGHT_HAZE
		end
		atmosphere.Density = math.clamp(haze, 0, 1)
		atmosphere.Color = a.air:Lerp(b.air, alpha)
		atmosphere.Decay = a.decay:Lerp(b.decay, alpha)
		atmosphere.Glare = mix("glare")
		atmosphere.Haze = mix("mist")
	end
end

local function ensureTint(): ColorCorrectionEffect
	local existing = Lighting:FindFirstChild("CycleTint")
	if existing ~= nil and existing:IsA("ColorCorrectionEffect") then
		return existing
	end
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "CycleTint"
	effect.Parent = Lighting
	return effect
end

-- The place's effect of this class, or a new one (client-side); either way set up with `props`.
local function ensure(className: string, props: { [string]: any }): any
	local effect: any = Lighting:FindFirstChildOfClass(className :: any)
	if effect == nil then
		effect = Instance.new(className :: any)
		effect.Parent = Lighting
	end
	for key, value in props do
		effect[key] = value
	end
	return effect
end

local function ensureEffects()
	tintEffect = ensureTint()
	atmosphereEffect = ensure("Atmosphere", { Offset = 0.15 })
	bloomEffect = ensure("BloomEffect", { Size = 24, Threshold = 1.2 })
	raysEffect = ensure("SunRaysEffect", { Spread = 0.6 })
	ensure("Sky", { StarCount = 3500, MoonAngularSize = 14, SunAngularSize = 18, CelestialBodiesShown = true })
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
end

-- The current cycle state, or nil before the server's epoch has replicated.
function CycleFXController.state(): Cycle.State?
	return current
end

-- The cycle timings in use (config, overridden by the server's DayLen/NightLen attributes).
function CycleFXController.cycleConfig(): any
	return cycleConfig.cycle
end

function CycleFXController.Start()
	ensureEffects()
	readAttributes()
	for _, name in { "CycleEpoch", "DayLen", "NightLen" } do
		workspace:GetAttributeChangedSignal(name):Connect(readAttributes)
	end

	RunService.RenderStepped:Connect(function()
		if epoch == nil then
			return
		end
		local state = Cycle.at(cycleConfig, epoch, workspace:GetServerTimeNow())
		current = state
		if state.phase ~= lastPhase or state.index ~= lastIndex then
			local initial = lastPhase == nil
			lastPhase = state.phase
			lastIndex = state.index
			CycleFXController.PhaseChanged:Fire(state.phase, state, initial)
		end
		apply(state.t)
	end)
end

return CycleFXController
