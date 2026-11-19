--!strict
-- The night fire loop on the client (GAME_SYSTEMS §12). Sets the context button to "Pick up"
-- next to an available wood pile and to "Feed" next to the fire while carrying, and sends the
-- intents. Hides piles while they respawn. The fire's look follows workspace `Fire` through
-- the five states of Shared.FireLook (Roaring … Cold, Bible §5B): flame size and colour, the
-- light's range, ember sparks, smoke, and the safe-circle runes (tag SafeRune), all eased so
-- changes never pop.
-- The server checks every range again; nothing here is trusted.
--
-- Tune the looks in Shared.FireLook at the G1 mood test.
-- The place streams (StreamingEnabled), so the campfire is looked up again whenever its parts
-- are missing, and pile logs are hidden as they stream in.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local FireLook = require(Shared:WaitForChild("FireLook"))
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local InputController = require(script.Parent:WaitForChild("InputController"))

local PICK_UP = "Pick up"
local FEED = "Feed"
local PRIORITY = 10 -- below Revive, Catch and Grab
local CHECK_SECONDS = 0.15
local MARGIN = 1 -- studs inside the server's ranges, so the button never shows where the server says no

local EASE = 2.5 -- per second: how fast the look catches up with a new state

local CampfireController = {}

local pit: BasePart? = nil
local feedRadius = 10
local light: PointLight? = nil
local flames: Fire? = nil
local core: BasePart? = nil -- the Neon flame ball
local coreSize: Vector3? = nil -- read once: it may stream out and back in
local embers: ParticleEmitter? = nil
local smoke: Smoke? = nil
local targetPile: string? = nil

-- The eased look: numbers and colours move toward FireLook.look(level) every frame.
local shown: any = nil
local clock = 0

local function fireLevel(): number?
	local level = workspace:GetAttribute("Fire")
	return if type(level) == "number" then level else nil
end

local function streamedIn(instance: Instance?): boolean
	return instance ~= nil and instance:IsDescendantOf(workspace)
end

-- Finds the pit, light and flames again if any of them hasn't streamed in (or streamed out).
local function bindCampfire()
	if streamedIn(pit) and streamedIn(light) and streamedIn(flames) then
		return
	end
	local campfire = CollectionService:GetTagged("Campfire")[1]
	if campfire == nil or not campfire:IsA("Model") then
		return
	end
	local primary = campfire.PrimaryPart or campfire:FindFirstChild("Pit")
	pit = if primary ~= nil and primary:IsA("BasePart") then primary else nil
	local radius = campfire:GetAttribute("FeedRadius")
	feedRadius = if type(radius) == "number" then radius else feedRadius
	light = campfire:FindFirstChildWhichIsA("PointLight", true)
	flames = campfire:FindFirstChildWhichIsA("Fire", true)
	local ball = campfire:FindFirstChild("Flame")
	core = if ball ~= nil and ball:IsA("BasePart") then ball else nil
	if core ~= nil then
		coreSize = coreSize or core.Size
		-- Embers and smoke are client-only effects on the flame ball.
		local emitter = core:FindFirstChild("Embers")
		if emitter == nil then
			local e = Instance.new("ParticleEmitter")
			e.Name = "Embers"
			e.LightEmission = 1
			e.Brightness = 3
			e.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 90, 30))
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
			e.Transparency = NumberSequence.new(0, 1)
			e.Lifetime = NumberRange.new(1.2, 2.6)
			e.Speed = NumberRange.new(4, 9)
			e.SpreadAngle = Vector2.new(25, 25)
			e.Acceleration = Vector3.new(0, 2, 0)
			e.RotSpeed = NumberRange.new(-90, 90)
			e.Rate = 0
			e.Parent = core
			emitter = e
		end
		embers = emitter :: ParticleEmitter
		local puff = core:FindFirstChild("Smoke")
		if puff == nil then
			local s = Instance.new("Smoke")
			s.Color = Color3.fromRGB(70, 70, 80)
			s.RiseVelocity = 4
			s.Size = 4
			s.Opacity = 0
			s.Enabled = false
			s.Parent = core
			puff = s
		end
		smoke = puff :: Smoke
	end
end

local function showPile(pile: Instance)
	local hidden = if pile:GetAttribute("Available") == false then 1 else 0
	for _, part in pile:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = hidden
		end
	end
end

local function bindPile(pile: Instance)
	showPile(pile)
	pile:GetAttributeChangedSignal("Available"):Connect(function()
		showPile(pile)
	end)
	pile.DescendantAdded:Connect(function(part: Instance)
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = if pile:GetAttribute("Available") == false then 1 else 0
		end
	end)
end

local NUMBERS =
	{ "flameSize", "heat", "coreScale", "lightRange", "lightBrightness", "embers", "smoke", "runeGlow", "flicker" }
local COLORS = { "flameColor", "flameSecondary", "coreColor", "lightColor", "runeColor" }

-- Eases `shown` toward the target look and applies it.
local function applyLook(dt: number)
	clock += dt
	local target = FireLook.look(fireLevel())
	if shown == nil then
		shown = table.clone(target)
	end
	local k = 1 - math.exp(-EASE * dt)
	for _, key in NUMBERS do
		shown[key] += (target[key] - shown[key]) * k
	end
	for _, key in COLORS do
		shown[key] = shown[key]:Lerp(target[key], k)
	end
	shown.runePulse = target.runePulse

	local wobble = 1 + shown.flicker * (math.noise(clock * 3.1, 0.5) + 0.4 * math.sin(clock * 17))
	local fireLight = light
	if fireLight ~= nil then
		fireLight.Enabled = shown.lightBrightness > 0.05
		fireLight.Brightness = shown.lightBrightness * wobble
		fireLight.Range = shown.lightRange
		fireLight.Color = shown.lightColor
	end
	local fireFlames = flames
	if fireFlames ~= nil then
		fireFlames.Enabled = shown.flameSize > 0.3
		fireFlames.Size = math.max(shown.flameSize, 2)
		fireFlames.Heat = shown.heat
		fireFlames.Color = shown.flameColor
		fireFlames.SecondaryColor = shown.flameSecondary
	end
	local ball, size = core, coreSize
	if ball ~= nil and size ~= nil then
		local scale = shown.coreScale * (1 + 0.06 * math.sin(clock * 9))
		ball.Size = size * math.max(scale, 0.05)
		ball.Color = shown.coreColor
		ball.LocalTransparencyModifier = if shown.coreScale < 0.05 then 1 else 0
	end
	if embers ~= nil then
		embers.Rate = shown.embers
	end
	local puff = smoke
	if puff ~= nil then
		puff.Enabled = shown.smoke > 0.02
		puff.Opacity = shown.smoke
	end

	local glow = FireLook.runeGlow(shown, clock)
	for _, rune in CollectionService:GetTagged("SafeRune") do
		if rune:IsA("BasePart") then
			rune.Color = Color3.fromRGB(40, 36, 32):Lerp(shown.runeColor, glow)
			rune.Transparency = 0.85 - 0.85 * glow
		end
	end
end

local function nearestPile(position: Vector3): string?
	local best: string?, bestDistance = nil, economy.fire.pickupRange - MARGIN
	for _, pile in CollectionService:GetTagged("WoodPile") do
		local id = pile:GetAttribute("PileId")
		if pile:IsA("Model") and type(id) == "string" and pile:GetAttribute("Available") ~= false then
			local distance = (pile:GetPivot().Position - position).Magnitude
			if distance <= bestDistance then
				best, bestDistance = id, distance
			end
		end
	end
	return best
end

local function updateContext()
	local label: string? = nil
	targetPile = nil
	local level = fireLevel()
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local living = character ~= nil and character:GetAttribute("Life") == nil -- not downed or a wisp
	if level ~= nil and living and character ~= nil and root ~= nil and root:IsA("BasePart") then
		if character:GetAttribute("CarryFuel") ~= nil then
			local firePit = pit
			if level > 0 and firePit ~= nil and (firePit.Position - root.Position).Magnitude <= feedRadius - MARGIN then
				label = FEED
			end
		else
			targetPile = nearestPile(root.Position)
			if targetPile ~= nil then
				label = PICK_UP
			end
		end
	end
	InputController.offer("Campfire", label, PRIORITY)
end

function CampfireController.Start()
	for _, pile in CollectionService:GetTagged("WoodPile") do
		bindPile(pile)
	end
	CollectionService:GetInstanceAddedSignal("WoodPile"):Connect(bindPile)

	InputController.Action:Connect(function(label: string, began: boolean)
		if not began then
			return
		end
		if label == PICK_UP and targetPile ~= nil then
			NetClient.send("PickupFuel", targetPile)
		elseif label == FEED then
			NetClient.send("FeedFire")
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= CHECK_SECONDS then
			elapsed = 0
			bindCampfire()
			updateContext()
		end
	end)
	RunService.RenderStepped:Connect(applyLook)
end

return CampfireController
