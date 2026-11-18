--!strict
-- Every plot's replicated state (TECH_SPEC §6): PlotSnapshot once, then PlotDelta patches,
-- applied with Shared.Plots so client and server share one shape. GlowlingRenderer (GS) will
-- build the real models from this; until then each occupied pad gets a placeholder orb,
-- coloured by rarity, and the owner's plot sign shows their name.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Plots = require(Shared:WaitForChild("Plots"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))

-- Placeholder colours, Common → Secret.
local RARITY_COLORS = {
	Color3.fromRGB(220, 220, 210),
	Color3.fromRGB(120, 230, 120),
	Color3.fromRGB(90, 160, 255),
	Color3.fromRGB(190, 110, 255),
	Color3.fromRGB(255, 190, 60),
	Color3.fromRGB(255, 80, 140),
	Color3.fromRGB(120, 255, 255),
}

local PlotController = {}
PlotController.Changed = Signal.new() -- (plotId, view)

local plots: { [number]: Plots.View } = {}
local placeholders: Folder? = nil

function PlotController.get(plotId: number): Plots.View?
	return plots[plotId]
end

-- The local player's plot id, or nil.
function PlotController.mine(): number?
	local userId = Players.LocalPlayer.UserId
	for id, view in plots do
		if view.owner == userId then
			return id
		end
	end
	return nil
end

local function plotModel(plotId: number): Instance?
	for _, model in CollectionService:GetTagged("Plot") do
		if model:GetAttribute("PlotId") == plotId then
			return model
		end
	end
	return nil
end

local function render(plotId: number)
	local folder = placeholders
	local view = plots[plotId]
	if folder == nil or view == nil then
		return
	end
	local old = folder:FindFirstChild(`Plot{plotId}`)
	if old ~= nil then
		old:Destroy()
	end
	local model = plotModel(plotId)
	if model == nil then
		return -- streamed out; rendered again when it streams in
	end

	local sign = model:FindFirstChild("Sign")
	local label = if sign ~= nil then sign:FindFirstChildWhichIsA("TextLabel", true) else nil
	if label ~= nil then
		local owner = Players:GetPlayerByUserId(view.owner)
		label.Text = if owner ~= nil then owner.DisplayName else `Plot {plotId}`
	end

	local slots = model:FindFirstChild("Slots")
	if slots == nil then
		return
	end
	local group = Instance.new("Folder")
	group.Name = `Plot{plotId}`
	for _, pad in slots:GetChildren() do
		local n = pad:GetAttribute("Slot")
		local glowling = if type(n) == "number" then view.pads[tostring(n)] else nil
		if glowling ~= nil and pad:IsA("BasePart") then
			local orb = Instance.new("Part")
			orb.Name = `Pad{n}`
			orb.Shape = Enum.PartType.Ball
			orb.Size = Vector3.one * 1.6 * glowling.s
			orb.CFrame = pad.CFrame + Vector3.new(0, 1.5, 0)
			orb.Color = RARITY_COLORS[glowling.r] or RARITY_COLORS[1]
			orb.Material = Enum.Material.Neon
			orb.Anchored = true
			orb.CanCollide = false
			orb.CanTouch = false
			orb.CanQuery = false
			orb.Parent = group
		end
	end
	group.Parent = folder
end

function PlotController.Init()
	NetClient.on("PlotSnapshot", function(views: { [string]: Plots.View })
		table.clear(plots)
		for key, view in views do
			local id = tonumber(key)
			if id ~= nil then
				plots[id] = view
			end
		end
		for id, view in plots do
			render(id)
			PlotController.Changed:Fire(id, view)
		end
	end)
	NetClient.on("PlotDelta", function(plotId: number, patch: Plots.Patch)
		local view = plots[plotId]
		if view == nil then
			return -- no snapshot yet; the snapshot will be newer than this patch
		end
		Plots.apply(view, patch)
		render(plotId)
		PlotController.Changed:Fire(plotId, view)
	end)
end

function PlotController.Start()
	local folder = Instance.new("Folder")
	folder.Name = "PlotPlaceholders"
	folder.Parent = workspace
	placeholders = folder
	for id in plots do
		render(id)
	end
	CollectionService:GetInstanceAddedSignal("Plot"):Connect(function(model: Instance)
		local id = model:GetAttribute("PlotId")
		if type(id) == "number" then
			render(id)
		end
	end)
end

return PlotController
