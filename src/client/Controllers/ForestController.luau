--!strict
-- Wild Glowlings on the client (GAME_SYSTEMS §12). Draws each wild from WildSpawned /
-- WildGone as a GlowlingRenderer model with its species name (the species is visible; the rarity
-- isn't rolled until the catch), and offers "Catch" on the context button at night next to
-- one, while the player is alive and has catches left (Player attribute `CatchesLeft`).
-- A tap sends Catch; the server checks the range, the catches left and the rest again.
-- Wilds use the Form I look in their family colour, since the rarity is still hidden.

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
local GlowlingRenderer = require(script.Parent:WaitForChild("GlowlingRenderer"))

local CATCH = "Catch"
local PRIORITY = 30 -- above Feed and Pick up, below Revive
local CHECK_SECONDS = 0.15
local MARGIN = 1 -- studs inside the server's range, so the button never shows where the server says no
local TAG_COLOR = Color3.fromRGB(210, 235, 255)

type Wild = { id: string, sp: string, area: string, x: number, y: number, z: number }

local ForestController = {}

local folder: Folder? = nil
local orbs: { [string]: { wild: Wild, model: Model } } = {}
local target: string? = nil

local speciesNames: { [string]: string } = {}
for _, species in speciesConfig.species do
	speciesNames[species.id] = species.name
end

local function remove(id: string)
	local orb = orbs[id]
	if orb ~= nil then
		orb.model:Destroy()
		orbs[id] = nil
	end
end

local function add(wild: Wild)
	local parent = folder
	if parent == nil then
		return
	end
	remove(wild.id) -- a snapshot may repeat a wild we already have
	local model = GlowlingRenderer.build({ sp = wild.sp, r = 1, m = 0, s = 1, wild = true })
	model.Name = `Wild{wild.id}`
	local facing = (tonumber(wild.id) or 0) * 1.7
	GlowlingRenderer.place(model, CFrame.new(wild.x, wild.y - 0.2, wild.z) * CFrame.Angles(0, facing, 0))
	local part = model.PrimaryPart :: BasePart

	local tag = Instance.new("BillboardGui")
	tag.Name = "Name"
	tag.Size = UDim2.fromOffset(160, 24)
	tag.StudsOffset = Vector3.new(0, 2, 0)
	tag.MaxDistance = 45
	tag.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = TAG_COLOR
	label.TextStrokeTransparency = 0.3
	label.Text = speciesNames[wild.sp] or wild.sp
	label.Parent = tag

	model.Parent = parent
	orbs[wild.id] = { wild = wild, model = model }
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

-- The wilds on this client, with their models (for the Wayfinder companion).
function ForestController.wilds(): { { wild: Wild, model: Model } }
	local list = {}
	for _, orb in orbs do
		table.insert(list, orb)
	end
	return list
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
		end
	end)
end

return ForestController
