--!strict
-- Every plot's replicated state (TECH_SPEC §6): PlotSnapshot once, then PlotDelta patches,
-- applied with Shared.Plots so client and server share one shape. Each occupied pad gets a
-- GlowlingRenderer model (rebuilt only when the pad changes; the rarest 8 get a light), the
-- owner's plot sign shows the base name and their name, a shielded plot
-- gets a bubble, and each placed decoration is a placeholder block on the DecorZone. The place streams, so a
-- plot is drawn again when its pads or sign stream in.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Decor = require(Shared:WaitForChild("Decor"))
local Plots = require(Shared:WaitForChild("Plots"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local RarityLook = require(Shared:WaitForChild("RarityLook"))
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local GlowlingRenderer = require(script.Parent:WaitForChild("GlowlingRenderer"))

local LIGHT_CAP = 8 -- PointLights per plot (Design & Asset Bible §8)

local SHIELD_COLOR = Color3.fromRGB(150, 220, 255)
local DECOR_COLOR = Color3.fromRGB(170, 140, 100)

local PlotController = {}
PlotController.Changed = Signal.new() -- (plotId, view)

local plots: { [number]: Plots.View } = {}
local placeholders: Folder? = nil
local renderQueued: { [number]: boolean } = {}
-- Drawn Glowlings per plot and pad: rebuilt only when what is on the pad changes.
local padModels: { [number]: { [string]: { key: string, model: Model } } } = {}

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

local function clearPads(plotId: number)
	for _, drawn in padModels[plotId] or {} do
		drawn.model:Destroy()
	end
	padModels[plotId] = nil
end

local function renderPads(plotId: number, view: Plots.View, slots: Instance)
	local folder = placeholders
	if folder == nil then
		return
	end
	local drawn = padModels[plotId] or {}
	padModels[plotId] = drawn
	local lights = RarityLook.lightPicks(view.pads, LIGHT_CAP)
	local seen: { [string]: boolean } = {}
	for _, pad in slots:GetChildren() do
		local n = pad:GetAttribute("Slot")
		local slot = if type(n) == "number" then tostring(n) else nil
		local glowling = if slot ~= nil then view.pads[slot] else nil
		if slot ~= nil and glowling ~= nil and pad:IsA("BasePart") then
			seen[slot] = true
			local light = lights[slot] == true
			local key = `{glowling.sp}|{glowling.r}|{glowling.m}|{glowling.s}|{light}|{pad.Position}`
			local old = drawn[slot]
			if old == nil or old.key ~= key then
				if old ~= nil then
					old.model:Destroy()
				end
				local model = GlowlingRenderer.build({
					sp = glowling.sp,
					r = glowling.r,
					m = glowling.m,
					s = glowling.s,
					light = light,
				})
				model.Name = `Plot{plotId}Pad{slot}`
				GlowlingRenderer.place(model, pad.CFrame * CFrame.new(0, pad.Size.Y / 2, 0))
				model.Parent = folder
				drawn[slot] = { key = key, model = model }
			end
		end
	end
	for slot, old in drawn do
		if not seen[slot] then
			old.model:Destroy()
			drawn[slot] = nil
		end
	end
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
		clearPads(plotId)
		return -- streamed out; rendered again when it streams in
	end

	local sign = model:FindFirstChild("Sign")
	local label = if sign ~= nil then sign:FindFirstChildWhichIsA("TextLabel", true) else nil
	if label ~= nil then
		local owner = Players:GetPlayerByUserId(view.owner)
		local who = if owner ~= nil then owner.DisplayName else `Plot {plotId}`
		label.Text = if view.name ~= "" and owner ~= nil then `{view.name}\n{who}` else who
	end

	local slots = model:FindFirstChild("Slots")
	if slots == nil then
		clearPads(plotId)
		return
	end
	local group = Instance.new("Folder")
	group.Name = `Plot{plotId}`
	local floor = model:FindFirstChild("Floor")
	if view.shield and floor ~= nil and floor:IsA("BasePart") then
		-- The new-player shield: a soft bubble over the plot (placeholder).
		local bubble = Instance.new("Part")
		bubble.Name = "Shield"
		bubble.Shape = Enum.PartType.Ball
		bubble.Size = Vector3.one * 50
		bubble.CFrame = floor.CFrame
		bubble.Color = SHIELD_COLOR
		bubble.Material = Enum.Material.ForceField
		bubble.Anchored = true
		bubble.CanCollide = false
		bubble.CanTouch = false
		bubble.CanQuery = false
		bubble.CastShadow = false
		bubble.Parent = group
	end
	local zone = model:FindFirstChild("DecorZone")
	if zone ~= nil and zone:IsA("BasePart") then
		for i, d in view.decor do
			local item = Decor.item(economy, d.id)
			if item ~= nil then
				local block = Instance.new("Part")
				block.Name = `Decor{i}`
				block.Size = Vector3.new(item.w - 0.2, 1, item.d - 0.2)
				block.CFrame = zone.CFrame * CFrame.new(d.x, 0.5, d.z) * CFrame.Angles(0, d.rot * math.pi / 2, 0)
				block.Color = DECOR_COLOR
				block.Material = Enum.Material.SmoothPlastic
				block.Anchored = true
				block.CanCollide = false
				block.CanTouch = false
				block.CanQuery = false
				block.Parent = group
			end
		end
	end
	renderPads(plotId, view, slots)
	group.Parent = folder
end

-- Many pads stream in at once; draw the plot once after they land.
local function renderSoon(plotId: number)
	if renderQueued[plotId] then
		return
	end
	renderQueued[plotId] = true
	task.delay(0.2, function()
		renderQueued[plotId] = nil
		render(plotId)
	end)
end

local function watchPlot(model: Instance)
	local id = model:GetAttribute("PlotId")
	if type(id) ~= "number" then
		return
	end
	model.DescendantAdded:Connect(function(added: Instance)
		local relevant = added:IsA("BasePart") and (added:GetAttribute("Slot") ~= nil or added.Name == "DecorZone")
		if relevant or added:IsA("TextLabel") then
			renderSoon(id)
		end
	end)
	renderSoon(id)
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
	for _, model in CollectionService:GetTagged("Plot") do
		watchPlot(model)
	end
	CollectionService:GetInstanceAddedSignal("Plot"):Connect(watchPlot)
end

return PlotController
