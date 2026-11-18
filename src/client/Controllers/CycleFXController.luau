--!strict
-- Lighting for dawn, day, dusk and night (TECH_SPEC §4), and the client's cycle clock.
--
-- Reads the cycle from workspace attributes (CycleEpoch, DayLen, NightLen, NightModifier) and
-- Shared.Cycle, so it needs no remotes. Every frame it blends between the keyframes below.
-- The map's Lighting in the place sets the overall look; this moves it through the day. Tune
-- the LOOKS table with artists during the G1 mood test.
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
	haze: number, -- Atmosphere.Density, when the place has an Atmosphere
}
type Key = { at: number, look: Look }

local FOG_NIGHT_HAZE = 0.15 -- extra density on Fog nights

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- stylua: ignore
local LOOKS: { [string]: Look } = {
	dawn      = { clock = 6.4,  brightness = 1.4,  ambient = rgb(95, 85, 105),  outdoor = rgb(150, 125, 140), tint = rgb(255, 232, 215), haze = 0.35 },
	day       = { clock = 8.5,  brightness = 2.4,  ambient = rgb(110, 110, 115), outdoor = rgb(140, 140, 145), tint = rgb(255, 255, 255), haze = 0.25 },
	afternoon = { clock = 15.5, brightness = 2.2,  ambient = rgb(115, 105, 100), outdoor = rgb(145, 130, 120), tint = rgb(255, 245, 235), haze = 0.28 },
	dusk      = { clock = 17.7, brightness = 1.5,  ambient = rgb(125, 70, 60),   outdoor = rgb(175, 90, 70),   tint = rgb(255, 195, 175), haze = 0.40 },
	nightfall = { clock = 19.0, brightness = 0.5,  ambient = rgb(35, 35, 65),    outdoor = rgb(40, 40, 80),    tint = rgb(185, 190, 255), haze = 0.45 },
	night     = { clock = 21.0, brightness = 0.15, ambient = rgb(14, 16, 38),    outdoor = rgb(18, 20, 48),    tint = rgb(150, 160, 255), haze = 0.50 },
	predawn   = { clock = 28.8, brightness = 0.25, ambient = rgb(30, 30, 55),    outdoor = rgb(40, 38, 70),    tint = rgb(175, 175, 235), haze = 0.45 },
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
	if tintEffect ~= nil then
		tintEffect.TintColor = a.tint:Lerp(b.tint, alpha)
	end

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere ~= nil then
		local haze = a.haze + (b.haze - a.haze) * alpha
		if current ~= nil and current.phase == "Night" and workspace:GetAttribute("NightModifier") == "Fog" then
			haze += FOG_NIGHT_HAZE
		end
		atmosphere.Density = math.clamp(haze, 0, 1)
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

-- The current cycle state, or nil before the server's epoch has replicated.
function CycleFXController.state(): Cycle.State?
	return current
end

-- The cycle timings in use (config, overridden by the server's DayLen/NightLen attributes).
function CycleFXController.cycleConfig(): any
	return cycleConfig.cycle
end

function CycleFXController.Start()
	tintEffect = ensureTint()
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
