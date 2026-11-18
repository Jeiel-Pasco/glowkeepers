--!strict
-- The night fire loop on the client (GAME_SYSTEMS §12). Sets the context button to "Pick up"
-- next to an available wood pile and to "Feed" next to the fire while carrying, and sends the
-- intents. Hides piles while they respawn, and dims the fire light with workspace `Fire`.
-- The server checks every range again; nothing here is trusted.
--
-- The light and pile visuals are placeholders for GS to replace; tune LIGHT_* at the G1 test.
-- The place streams (StreamingEnabled), so the campfire is looked up again whenever its parts
-- are missing, and pile logs are hidden as they stream in.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local InputController = require(script.Parent:WaitForChild("InputController"))

local PICK_UP = "Pick up"
local FEED = "Feed"
local REVIVE = "Revive" -- DownedController's label
local CHECK_SECONDS = 0.15
local MARGIN = 1 -- studs inside the server's ranges, so the button never shows where the server says no

-- Fire light at night: base brightness × (LIGHT_MIN + LIGHT_PER_LEVEL × level); off at 0.
local LIGHT_MIN = 0.4
local LIGHT_PER_LEVEL = 0.8

local CampfireController = {}

local pit: BasePart? = nil
local feedRadius = 10
local light: PointLight? = nil
local baseBrightness: number? = nil -- read once: the light may stream out and back in
local flames: Fire? = nil
local baseFlameSize: number? = nil
local targetPile: string? = nil

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
	if light ~= nil and baseBrightness == nil then
		baseBrightness = light.Brightness
	end
	flames = campfire:FindFirstChildWhichIsA("Fire", true)
	if flames ~= nil and baseFlameSize == nil then
		baseFlameSize = flames.Size
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

local function updateLight()
	local level = fireLevel()
	local lit = level == nil or level > 0
	local fireLight, brightness = light, baseBrightness
	if fireLight ~= nil and brightness ~= nil then
		fireLight.Enabled = lit
		fireLight.Brightness = if level == nil then brightness else brightness * (LIGHT_MIN + LIGHT_PER_LEVEL * level)
	end
	local fireFlames, size = flames, baseFlameSize
	if fireFlames ~= nil and size ~= nil then
		fireFlames.Enabled = lit
		fireFlames.Size = if level == nil then size else size * (0.5 + level)
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
	local current = InputController.context()
	if label ~= nil and current ~= REVIVE then -- reviving a teammate comes first
		InputController.setContext(label)
	elseif label == nil and (current == PICK_UP or current == FEED) then
		InputController.setContext(nil) -- leave other controllers' labels alone
	end
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
			updateLight() -- every check, so a light that streams back in is dimmed again
			updateContext()
		end
	end)
end

return CampfireController
