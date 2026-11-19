--!strict
-- The Night Companion on the client (GAME_SYSTEMS §31, D23).
--
-- A "Companion" button opens a list of vault Glowlings; tapping one sends SetCompanion (tap the
-- chosen one again to clear it; the server only allows it by day). At night every player whose
-- `Companion` attribute is set ("sp|r|m") gets a small copy floating at their shoulder. If the
-- local player's companion is a Wayfinder, every 10 s a beam points from it to the nearest
-- Rare-floor wild within 60 studs (Shared.Companion.wayfind).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Companion = require(Shared:WaitForChild("Companion"))
local economy = require(Config:WaitForChild("economy")) :: any
local speciesConfig = require(Config:WaitForChild("species")) :: any
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local StateController = require(script.Parent:WaitForChild("StateController"))
local CycleFXController = require(script.Parent:WaitForChild("CycleFXController"))
local GlowlingRenderer = require(script.Parent:WaitForChild("GlowlingRenderer"))
local ForestController = require(script.Parent:WaitForChild("ForestController"))

local PANEL = Color3.fromRGB(24, 26, 38)
local PICK = Color3.fromRGB(90, 150, 230)
local CHOSEN = Color3.fromRGB(230, 180, 70)
local SHOULDER = CFrame.new(2.6, 1.6, 0.8)
local POINT_SECONDS = 4

local HudLayout = require(script.Parent:WaitForChild("HudLayout"))

local CompanionController = {}

local speciesById: { [string]: any } = {}
for _, entry in speciesConfig.species do
	speciesById[entry.id] = entry
end

local list: ScrollingFrame? = nil
local panel: Frame? = nil
local floating: { [Player]: Model } = {}

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function isNight(): boolean
	local state = CycleFXController.state()
	return state ~= nil and state.phase == "Night"
end

-- Panel ----------------------------------------------------------------------------------------

local function refreshList()
	local scroll, frame = list, panel
	local data = StateController.get()
	if scroll == nil or frame == nil or not frame.Visible or data == nil then
		return
	end
	for _, child in scroll:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local pads = {}
	for key, id in data.vault or {} do
		table.insert(pads, { pad = tonumber(key) or 0, id = id })
	end
	table.sort(pads, function(a, b)
		return a.pad < b.pad
	end)
	for i, entry in pads do
		local record = data.glowlings[entry.id]
		local s = if record ~= nil then speciesById[record.sp] else nil
		if s ~= nil then
			local chosen = data.companion == entry.id
			local row = Instance.new("TextButton")
			row.Name = entry.id
			row.Size = UDim2.new(1, -8, 0, 40)
			row.Position = UDim2.fromOffset(4, (i - 1) * 44)
			row.BackgroundColor3 = if chosen then CHOSEN else PICK
			row.Font = Enum.Font.GothamBold
			row.TextSize = 14
			row.TextColor3 = Color3.new(1, 1, 1)
			row.TextWrapped = true
			local rarity = economy.rarities[record.r]
			row.Text = `{if chosen then "★ " else ""}{rarity and rarity.id or ""} {s.name} · {s.trait}`
			corner(row, 8)
			row.Parent = scroll
			row.Activated:Connect(function()
				if isNight() then
					return -- the server says no too; don't spam it
				end
				NetClient.send("SetCompanion", entry.id)
			end)
		end
	end
	scroll.CanvasSize = UDim2.fromOffset(0, #pads * 44)
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "CompanionGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local toggle = Instance.new("TextButton")
	toggle.Name = "CompanionButton"
	toggle.Size = UDim2.fromOffset(150, 38)
	toggle.BackgroundColor3 = PANEL
	toggle.BackgroundTransparency = 0.15
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 17
	toggle.TextColor3 = CHOSEN
	toggle.Text = "Companion"
	corner(toggle, 10)
	HudLayout.dock("right", toggle, 6)

	local frame = Instance.new("Frame")
	frame.Name = "Companion"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -172, 0, 282)
	frame.Size = UDim2.fromOffset(300, 300)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.1
	frame.Visible = false
	corner(frame, 12)
	frame.Parent = gui
	panel = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -24, 0, 44)
	title.Position = UDim2.fromOffset(12, 6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.Gotham
	title.TextSize = 13
	title.TextWrapped = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(220, 220, 235)
	title.Text = "Night Companion: a vault Glowling that goes with you at night. Change it by day."
	title.Parent = frame

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -16, 1, -60)
	scroll.Position = UDim2.fromOffset(8, 54)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 4
	scroll.BorderSizePixel = 0
	scroll.Parent = frame
	list = scroll

	toggle.Activated:Connect(function()
		frame.Visible = not frame.Visible
		refreshList()
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- Floating copies -------------------------------------------------------------------------------

local function refreshFloat(player: Player)
	local old = floating[player]
	if old ~= nil then
		old:Destroy()
		floating[player] = nil
	end
	local value = player:GetAttribute("Companion")
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if type(value) ~= "string" or not isNight() or root == nil or not root:IsA("BasePart") then
		return
	end
	local sp, r, m = string.match(value, "^([^|]+)|(%d+)|(%d+)$")
	if sp == nil then
		return
	end
	local model = GlowlingRenderer.build({
		sp = sp,
		r = tonumber(r) or 1,
		m = tonumber(m) or 0,
		s = 0.6,
		carried = true,
		light = true, -- one per player: it lights the way at night
	})
	model.Name = "Companion"
	GlowlingRenderer.attach(model, root, SHOULDER)
	model.Parent = character
	floating[player] = model
end

local function refreshAll()
	for _, player in Players:GetPlayers() do
		refreshFloat(player)
	end
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("Companion"):Connect(function()
		refreshFloat(player)
	end)
	player.CharacterAdded:Connect(function()
		task.defer(refreshFloat, player)
	end)
	refreshFloat(player)
end

-- Wayfinder -------------------------------------------------------------------------------------

local function point()
	local me = Players.LocalPlayer
	local model = floating[me]
	local data = StateController.get()
	local character = me.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if model == nil or data == nil or root == nil or not root:IsA("BasePart") then
		return
	end
	local s = Companion.species(data, speciesById)
	if s == nil or s.trait ~= "Wayfinder" then
		return
	end
	local entries = ForestController.wilds()
	local wilds = {}
	for _, entry in entries do
		table.insert(wilds, entry.wild)
	end
	local target = Companion.wayfind(economy, speciesById, root.Position, wilds)
	if target == nil then
		return
	end
	local targetModel: Model? = nil
	for _, entry in entries do
		if entry.wild.id == target.id then
			targetModel = entry.model
		end
	end
	local from, to = model.PrimaryPart, if targetModel ~= nil then targetModel.PrimaryPart else nil
	if from == nil or to == nil then
		return
	end
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Parent, a1.Parent = from, to
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.Width0, beam.Width1 = 0.25, 0.6
	beam.Color = ColorSequence.new(Color3.fromRGB(180, 220, 255))
	beam.Transparency = NumberSequence.new(0.3, 0.8)
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Parent = from
	task.delay(POINT_SECONDS, function()
		beam:Destroy()
		a0:Destroy()
		a1:Destroy()
	end)
end

function CompanionController.Start()
	build()
	StateController.Changed:Connect(function(key: string)
		if key == "companion" or key == "vault" or key == "glowlings" then
			refreshList()
		end
	end)
	CycleFXController.PhaseChanged:Connect(refreshAll)
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	task.spawn(function()
		while true do
			task.wait(economy.traits.companion.wayfinderEvery)
			if isNight() then
				point()
			end
		end
	end)
end

return CompanionController
