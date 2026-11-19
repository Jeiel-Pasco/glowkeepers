--!strict
-- Every plot's replicated state (TECH_SPEC §6): PlotSnapshot once, then PlotDelta patches,
-- applied with Shared.Plots so client and server share one shape. Each placed Glowling gets a
-- GlowlingRenderer model (rebuilt only when it changes; the rarest 8 get a light) that wanders
-- the yard by Shared.Roam (vault ones sleep by the den; a grabbed one stands still), the
-- owner's plot sign shows the base name and their name, a shielded plot
-- gets a bubble, BaseDresser dresses the plot for its size (home, fence, lamps) and draws
-- each placed decoration on the DecorZone. The place streams, so a
-- plot is drawn again when its floor or sign streams in.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Plots = require(Shared:WaitForChild("Plots"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local RarityLook = require(Shared:WaitForChild("RarityLook"))
local Roam = require(Shared:WaitForChild("Roam"))
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local GlowlingRenderer = require(script.Parent:WaitForChild("GlowlingRenderer"))
local BaseDresser = require(script.Parent:WaitForChild("BaseDresser"))

local LIGHT_CAP = 8 -- PointLights per plot (Design & Asset Bible §8)
local CULL_DISTANCE = 220 -- Glowlings farther than this from the camera stop walking
local HOP_RATE = 9
local HOP_HEIGHT = 0.35

local SHIELD_COLOR = Color3.fromRGB(150, 220, 255)

local PlotController = {}
PlotController.Changed = Signal.new() -- (plotId, view)

local plots: { [number]: Plots.View } = {}
local placeholders: Folder? = nil
local renderQueued: { [number]: boolean } = {}
-- Drawn Glowlings per plot and pad: rebuilt only when what is on the pad changes.
local padModels: { [number]: { [string]: { key: string, model: Model, at: CFrame } } } = {}

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

local function floorOf(plotId: number): BasePart?
	local model = plotModel(plotId)
	local floor = if model ~= nil then model:FindFirstChild("Floor") else nil
	return if floor ~= nil and floor:IsA("BasePart") then floor else nil
end

-- Where the Glowling on `pad` stands now (Shared.Roam), with its heading and whether it walks;
-- the same spot the server measures a grab from. nil when the plot hasn't streamed in.
function PlotController.spot(plotId: number, pad: number): (CFrame?, boolean)
	local view = plots[plotId]
	local floor = floorOf(plotId)
	local glowling = if view ~= nil then view.pads[tostring(pad)] else nil
	if view == nil or floor == nil or glowling == nil then
		return nil, false
	end
	local area = { halfW = floor.Size.X / 2, halfD = floor.Size.Z / 2 }
	local x, z, heading, walking = Roam.spot(area, plotId, pad, view.vault, workspace:GetServerTimeNow(), glowling.f)
	return floor.CFrame * CFrame.new(x, floor.Size.Y / 2, z) * CFrame.Angles(0, heading, 0), walking
end

-- The drawn model of the Glowling on a pad (TraitFXController hangs its rings on it).
function PlotController.model(plotId: number, pad: number): Model?
	local drawn = padModels[plotId]
	local entry = if drawn ~= nil then drawn[tostring(pad)] else nil
	return if entry ~= nil then entry.model else nil
end

local function renderPads(plotId: number, view: Plots.View)
	local folder = placeholders
	if folder == nil then
		return
	end
	local drawn = padModels[plotId] or {}
	padModels[plotId] = drawn
	local lights = RarityLook.lightPicks(view.pads, LIGHT_CAP)
	local seen: { [string]: boolean } = {}
	for slot, glowling in view.pads do
		local pad = tonumber(slot)
		local spot = if pad ~= nil then PlotController.spot(plotId, pad) else nil
		if spot == nil then
			continue
		end
		seen[slot] = true
		local light = lights[slot] == true
		local over = glowling.o == true
		local key = `{glowling.sp}|{glowling.r}|{glowling.m}|{glowling.s}|{light}|{over}`
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
				overcharged = over,
			})
			model.Name = `Plot{plotId}Pad{slot}`
			GlowlingRenderer.place(model, spot)
			model.Parent = folder
			drawn[slot] = { key = key, model = model, at = spot }
		end
	end
	for slot, old in drawn do
		if not seen[slot] then
			old.model:Destroy()
			drawn[slot] = nil
		end
	end
end

-- Every frame: walk each nearby drawn Glowling toward its Roam spot, with a little hop.
local function stepGlowlings(dt: number)
	local camera = workspace.CurrentCamera
	local eye = if camera ~= nil then camera.CFrame.Position else Vector3.zero
	local now = os.clock()
	for plotId, drawn in padModels do
		for slot, entry in drawn do
			local pad = tonumber(slot)
			if pad == nil then
				continue
			end
			local spot, walking = PlotController.spot(plotId, pad)
			if spot == nil or (spot.Position - eye).Magnitude > CULL_DISTANCE then
				continue
			end
			-- Ease toward the spot (a cancelled grab or a late patch walks over, never teleports).
			local alpha = math.min(1, dt * 8)
			local at = entry.at:Lerp(spot, alpha)
			entry.at = at
			local hop = if walking then math.abs(math.sin(now * HOP_RATE + pad)) * HOP_HEIGHT else 0
			GlowlingRenderer.place(entry.model, at + Vector3.new(0, hop, 0))
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
	BaseDresser.dress(model, view.slots, view.owner ~= 0, group)
	local zone = model:FindFirstChild("DecorZone")
	if zone ~= nil and zone:IsA("BasePart") then
		BaseDresser.decor(zone, view.decor, group)
	end
	renderPads(plotId, view)
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
		local relevant = added:IsA("BasePart") and (added.Name == "Floor" or added.Name == "DecorZone")
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
	RunService.RenderStepped:Connect(stepGlowlings)
end

return PlotController
