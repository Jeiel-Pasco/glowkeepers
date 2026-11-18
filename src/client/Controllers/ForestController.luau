--!strict
-- Wild Glowlings on the client (GAME_SYSTEMS §12). Draws each wild from WildSpawned /
-- WildGone as a placeholder orb with its species name (the species is visible; the rarity
-- isn't rolled until the catch), and offers "Catch" on the context button at night next to
-- one, while the player is alive and has catches left (Player attribute `CatchesLeft`).
-- A tap sends Catch; the server checks the range, the catches left and the rest again.
--
-- Placeholders for GS: the orb and the name tag (GlowlingRenderer builds the real models).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local economy = require(Config:WaitForChild("economy")) :: any
local speciesConfig = require(Config:WaitForChild("species")) :: any
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local InputController = require(script.Parent:WaitForChild("InputController"))
local CycleFXController = require(script.Parent:WaitForChild("CycleFXController"))

local CATCH = "Catch"
local PRIORITY = 30 -- above Feed and Pick up, below Revive
local CHECK_SECONDS = 0.15
local MARGIN = 1 -- studs inside the server's range, so the button never shows where the server says no
local ORB_COLOR = Color3.fromRGB(210, 235, 255)
local BOB_STUDS = 0.4

type Wild = { id: string, sp: string, area: string, x: number, y: number, z: number }

local ForestController = {}

local folder: Folder? = nil
local orbs: { [string]: { wild: Wild, part: BasePart } } = {}
local target: string? = nil

local speciesNames: { [string]: string } = {}
for _, species in speciesConfig.species do
	speciesNames[species.id] = species.name
end

local function remove(id: string)
	local orb = orbs[id]
	if orb ~= nil then
		orb.part:Destroy()
		orbs[id] = nil
	end
end

local function add(wild: Wild)
	local parent = folder
	if parent == nil then
		return
	end
	remove(wild.id) -- a snapshot may repeat a wild we already have
	local part = Instance.new("Part")
	part.Name = `Wild{wild.id}`
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * 1.4
	part.Position = Vector3.new(wild.x, wild.y + 0.5, wild.z)
	part.Color = ORB_COLOR
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false

	local tag = Instance.new("BillboardGui")
	tag.Name = "Name"
	tag.Size = UDim2.fromOffset(160, 24)
	tag.StudsOffset = Vector3.new(0, 1.6, 0)
	tag.MaxDistance = 45
	tag.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = ORB_COLOR
	label.TextStrokeTransparency = 0.3
	label.Text = speciesNames[wild.sp] or wild.sp
	label.Parent = tag

	part.Parent = parent
	orbs[wild.id] = { wild = wild, part = part }
end

local function nearestWild(position: Vector3): string?
	local best: string?, bestDistance = nil, economy.night.catchRange - MARGIN
	for id, orb in orbs do
		local wild = orb.wild
		local distance = (Vector3.new(wild.x, wild.y, wild.z) - position).Magnitude
		if distance <= bestDistance then
			best, bestDistance = id, distance
		end
	end
	return best
end

local function updateContext()
	target = nil
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local state = CycleFXController.state()
	local left = Players.LocalPlayer:GetAttribute("CatchesLeft")
	if
		character ~= nil
		and root ~= nil
		and root:IsA("BasePart")
		and state ~= nil
		and state.phase == "Night"
		and character:GetAttribute("Life") == nil
		and type(left) == "number"
		and left > 0
	then
		target = nearestWild(root.Position)
	end
	InputController.offer("Forest", if target ~= nil then CATCH else nil, PRIORITY)
end

local function bob(now: number)
	for id, orb in orbs do
		local wild = orb.wild
		local phase = (tonumber(id) or 0) * 1.7
		orb.part.Position = Vector3.new(wild.x, wild.y + 0.5 + BOB_STUDS * math.sin(now * 2 + phase), wild.z)
	end
end

function ForestController.Init()
	NetClient.on("WildSpawned", function(list: { Wild })
		for _, wild in list do
			add(wild)
		end
	end)
	NetClient.on("WildGone", function(ids: { string })
		for _, id in ids do
			remove(id)
		end
	end)
end

function ForestController.Start()
	local wildFolder = Instance.new("Folder")
	wildFolder.Name = "Wilds"
	wildFolder.Parent = workspace
	folder = wildFolder

	InputController.Action:Connect(function(label: string, began: boolean)
		local id = target
		if label == CATCH and began and id ~= nil then
			NetClient.send("Catch", id)
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= CHECK_SECONDS then
			elapsed = 0
			updateContext()
			bob(os.clock())
		end
	end)
end

return ForestController
