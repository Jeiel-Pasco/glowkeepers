--!strict
-- Shows pet traits on every plot (GAME_SYSTEMS §31), from the replicated plot views:
--   family link   a soft beam between same-family neighbours (brighter if one is a Harmonizer)
--   Harmonizer    a family-coloured ring under its pad
--   Guardian      a pale blue ring under its pad
--   Overcharge    when a pad becomes Overcharged: a gold beam from its Infuser (a neighbour) or the
--                 plot's Aurora Lynx, and a burst of sparks
--   Forager       TraitPouch (plotId, pad, amount): "+3.9K" rises from the pad
-- Links and rings are rebuilt only when a plot's pads change.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Traits = require(Shared:WaitForChild("Traits"))
local RarityLook = require(Shared:WaitForChild("RarityLook"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local speciesConfig = require(Config:WaitForChild("species")) :: any
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local PlotController = require(script.Parent:WaitForChild("PlotController"))

local GOLD = Color3.fromRGB(255, 200, 70)
local GUARD = Color3.fromRGB(150, 200, 255)
local POUCH = Color3.fromRGB(150, 255, 150)
local LINK_HEIGHT = 0.6
local ZAP_SECONDS = 1.5

local TraitFXController = {}

local speciesById: { [string]: any } = {}
for _, entry in speciesConfig.species do
	speciesById[entry.id] = entry
end

local root: Folder? = nil
local drawn: { [number]: { key: string, folder: Folder } } = {}
local wasOver: { [number]: { [string]: boolean } } = {}

local function c3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- Pad number → pad part, for a plot that has streamed in.
local function padParts(plotId: number): { [number]: BasePart }
	local parts = {}
	for _, model in CollectionService:GetTagged("Plot") do
		if model:GetAttribute("PlotId") == plotId then
			local slots = model:FindFirstChild("Slots")
			for _, pad in if slots ~= nil then slots:GetChildren() else {} do
				local n = pad:GetAttribute("Slot")
				if type(n) == "number" and pad:IsA("BasePart") then
					parts[n] = pad
				end
			end
		end
	end
	return parts
end

local function attachment(part: BasePart, parent: Instance): Attachment
	local a = Instance.new("Attachment")
	a.Position = Vector3.new(0, part.Size.Y / 2 + LINK_HEIGHT, 0)
	a.Parent = part
	parent.Destroying:Connect(function()
		a:Destroy()
	end)
	return a
end

local function beam(from: BasePart, to: BasePart, color: Color3, width: number, parent: Instance): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = attachment(from, parent)
	b.Attachment1 = attachment(to, parent)
	b.Color = ColorSequence.new(color)
	b.Width0, b.Width1 = width, width
	b.Transparency = NumberSequence.new(0.45)
	b.LightEmission = 1
	b.FaceCamera = true
	b.Segments = 1
	b.Parent = parent
	return b
end

local function ring(pad: BasePart, color: Color3, parent: Instance)
	local p = Instance.new("Part")
	p.Name = "TraitRing"
	p.Shape = Enum.PartType.Cylinder
	-- A disc just under the pad's top, a little wider than the pad: only a halo shows round it.
	local across = math.max(pad.Size.X, pad.Size.Z) + 0.9
	p.Size = Vector3.new(0.1, across, across)
	p.CFrame = pad.CFrame * CFrame.new(0, pad.Size.Y / 2 - 0.08, 0) * CFrame.Angles(0, 0, math.pi / 2)
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.3
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Parent = parent
end

local function sparks(pad: BasePart, color: Color3, count: number)
	local a = Instance.new("Attachment")
	a.Position = Vector3.new(0, pad.Size.Y / 2 + 1, 0)
	a.Parent = pad
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Size = NumberSequence.new(0.35, 0)
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(4, 8)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = a
	e:Emit(count)
	task.delay(1.2, function()
		a:Destroy()
	end)
end

local function speciesOn(view: any, pad: number): any
	local glowling = view.pads[tostring(pad)]
	return if glowling ~= nil then speciesById[glowling.sp] else nil
end

-- Links and rings for one plot.
local function drawStatic(plotId: number, view: any)
	local folderRoot = root
	if folderRoot == nil then
		return
	end
	local parts = padParts(plotId)
	local keyParts = {}
	for pad = 1, 30 do
		local s = speciesOn(view, pad)
		table.insert(keyParts, if s ~= nil and parts[pad] ~= nil then s.id else "")
	end
	local key = table.concat(keyParts, ",")
	local old = drawn[plotId]
	if old ~= nil and old.key == key then
		return
	end
	if old ~= nil then
		old.folder:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = `Plot{plotId}`
	folder.Parent = folderRoot
	drawn[plotId] = { key = key, folder = folder }

	for pad, part in parts do
		local s = speciesOn(view, pad)
		if s ~= nil then
			if s.trait == "Harmonizer" then
				ring(part, c3(RarityLook.glow(s.family)), folder)
			elseif s.trait == "Guardian" then
				ring(part, GUARD, folder)
			end
			for _, n in Traits.neighbours(pad) do
				local other = speciesOn(view, n)
				if n > pad and other ~= nil and parts[n] ~= nil and other.family == s.family then
					local harmony = s.trait == "Harmonizer" or other.trait == "Harmonizer"
					beam(part, parts[n], c3(RarityLook.glow(s.family)), if harmony then 0.35 else 0.18, folder)
				end
			end
		end
	end
end

-- The pad an Overcharge on `pad` most likely came from: a neighbouring Infuser, else an Aurora Lynx.
local function sourceOf(view: any, pad: number): number?
	for _, n in Traits.neighbours(pad) do
		local s = speciesOn(view, n)
		if s ~= nil and s.trait == "Infuser" then
			return n
		end
	end
	for key, glowling in view.pads do
		if glowling.sp == "auroralynx" then
			return tonumber(key)
		end
	end
	return nil
end

local function drawOvercharges(plotId: number, view: any)
	local before = wasOver[plotId] or {}
	local now: { [string]: boolean } = {}
	local parts: { [number]: BasePart }? = nil
	for key, glowling in view.pads do
		if glowling.o == true then
			now[key] = true
			if not before[key] then
				parts = parts or padParts(plotId)
				local pad = tonumber(key) or 0
				local target = (parts :: any)[pad]
				if target ~= nil then
					sparks(target, GOLD, 24)
					local from = sourceOf(view, pad)
					local source = if from ~= nil then (parts :: any)[from] else nil
					if source ~= nil and root ~= nil then
						local holder = Instance.new("Folder")
						holder.Name = "Zap"
						holder.Parent = root
						beam(source, target, GOLD, 0.4, holder)
						task.delay(ZAP_SECONDS, function()
							holder:Destroy()
						end)
					end
				end
			end
		end
	end
	wasOver[plotId] = now
end

local function pouch(plotId: number, pad: number, amount: number)
	local part = padParts(plotId)[pad]
	if part == nil then
		return
	end
	sparks(part, POUCH, 16)
	local a = Instance.new("Attachment")
	a.Position = Vector3.new(0, part.Size.Y / 2 + 2.5, 0)
	a.Parent = part
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 40)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	gui.Parent = a
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = POUCH
	label.TextStrokeTransparency = 0.4
	label.Text = `+{EconomyMath.formatNumber(amount)} Glow`
	label.Parent = gui
	local info = TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(a, info, { Position = a.Position + Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.7, function()
		a:Destroy()
	end)
end

function TraitFXController.Init()
	NetClient.on("TraitPouch", pouch)
end

function TraitFXController.Start()
	local folder = Instance.new("Folder")
	folder.Name = "TraitFX"
	folder.Parent = workspace
	root = folder
	PlotController.Changed:Connect(function(plotId: number, view: any)
		drawStatic(plotId, view)
		drawOvercharges(plotId, view)
	end)
	-- Plots stream in after their views arrive: catch up now and then.
	task.spawn(function()
		while true do
			task.wait(3)
			for _, model in CollectionService:GetTagged("Plot") do
				local id = model:GetAttribute("PlotId")
				local view = if type(id) == "number" then PlotController.get(id) else nil
				if view ~= nil and type(id) == "number" then
					drawStatic(id, view)
				end
			end
		end
	end)
end

return TraitFXController
