--!strict
-- The Glowdex panel (GAME_SYSTEMS §16). A "Glowdex" button under "Rebirth" opens one row per
-- species: which of the 7 rarities it has (● or ○), its Golden and Rainbow stamps, and a Claim
-- button when a new page tier is reached. The header shows total entries and claims the next
-- milestone. The server checks every claim again (GlowdexService).
--
-- Placeholder for UI: the panel (artists replace it in Phase 4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Glowdex = require(Shared:WaitForChild("Glowdex"))
local Roll = require(Shared:WaitForChild("Roll"))
local economy = require(Config:WaitForChild("economy")) :: any
local species = require(Config:WaitForChild("species")) :: any
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local StateController = require(script.Parent:WaitForChild("StateController"))

local PANEL = Color3.fromRGB(20, 24, 40)
local CLAIM = Color3.fromRGB(90, 170, 110)
local DIM = Color3.fromRGB(60, 60, 70)
local ROW_HEIGHT = 34
local HEADER = 44

type Row = { label: TextLabel, claim: TextButton }

local GlowdexController = {}

local panel: Frame? = nil
local header: TextLabel? = nil
local milestoneButton: TextButton? = nil
local rows: { [string]: Row } = {}
local dirty = true

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function button(parent: Instance, name: string): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextColor3 = Color3.new(1, 1, 1)
	corner(b, 8)
	b.Parent = parent
	return b
end

local function setButton(b: TextButton, text: string, enabled: boolean)
	b.Text = text
	b.BackgroundColor3 = if enabled then CLAIM else DIM
	b.AutoButtonColor = enabled
end

-- The next unclaimed milestone index, or nil when all are claimed.
local function nextMilestone(claimed: any): number?
	for i, milestone in economy.glowdex.milestones do
		if claimed[Glowdex.milestoneKey(milestone.entries)] == nil then
			return i
		end
	end
	return nil
end

local function refresh()
	local frame, title, mButton = panel, header, milestoneButton
	local data = StateController.get()
	if frame == nil or title == nil or mButton == nil or not frame.Visible or data == nil then
		return
	end
	dirty = false
	local dex, claimed = data.dex or {}, data.dexClaimed or {}
	local total = Glowdex.reachable(economy, species, function(entry)
		return Roll.speciesFloor(economy, entry)
	end)
	title.Text = `Glowdex {Glowdex.entries(dex)}/{total}`
	local index = nextMilestone(claimed)
	if index == nil then
		setButton(mButton, "All milestones", false)
	else
		local m = economy.glowdex.milestones[index]
		setButton(
			mButton,
			`{m.entries}: +{m.embers} Em`,
			Glowdex.canClaimMilestone(economy, dex, claimed, index) ~= nil
		)
	end
	for _, entry in species.species do
		local row = rows[entry.id]
		local page = dex[entry.id]
		local dots = {}
		local floor = Roll.speciesFloor(economy, entry)
		for r = 1, #economy.rarities do
			-- rarities under the species' floor can't be caught (D18)
			dots[r] = if Glowdex.hasRarity(page, r) then "●" elseif r < floor then "·" else "○"
		end
		local stamps = (if Glowdex.hasMutation(page, 1) then " G" else "")
			.. (if Glowdex.hasMutation(page, 2) then " R" else "")
		local done = tonumber(claimed[entry.id]) or 0
		local tierName = if done > 0 then ` · {economy.glowdex.tiers[done].id}` else ""
		row.label.Text = `{entry.name}{tierName}\n{table.concat(dots)}{stamps}`
		local nextTier = Glowdex.canClaimPage(economy, dex, claimed, entry.id, floor)
		if nextTier ~= nil then
			setButton(row.claim, economy.glowdex.tiers[nextTier].id, true)
		else
			setButton(row.claim, "—", false)
		end
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "GlowdexGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local toggle = Instance.new("TextButton")
	toggle.Name = "GlowdexButton"
	toggle.AnchorPoint = Vector2.new(0, 0.5)
	toggle.Position = UDim2.new(0, 12, 0.5, 192) -- under "Rebirth"
	toggle.Size = UDim2.fromOffset(120, 40)
	toggle.BackgroundColor3 = PANEL
	toggle.BackgroundTransparency = 0.15
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 17
	toggle.TextColor3 = Color3.fromRGB(150, 230, 160)
	toggle.Text = "Glowdex"
	corner(toggle, 10)
	toggle.Parent = gui

	local frame = Instance.new("Frame")
	frame.Name = "Glowdex"
	frame.AnchorPoint = Vector2.new(0, 0.5)
	frame.Position = UDim2.new(0, 140, 0.5, 0)
	frame.Size = UDim2.fromOffset(340, 380)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.1
	frame.Visible = false
	corner(frame, 12)
	frame.Parent = gui
	panel = frame

	local title = Instance.new("TextLabel")
	title.Name = "Entries"
	title.Position = UDim2.fromOffset(12, 8)
	title.Size = UDim2.new(1, -150, 0, HEADER - 14)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(150, 230, 160)
	title.Parent = frame
	header = title

	local mButton = button(frame, "Milestone")
	mButton.AnchorPoint = Vector2.new(1, 0)
	mButton.Position = UDim2.new(1, -12, 0, 8)
	mButton.Size = UDim2.fromOffset(130, HEADER - 14)
	milestoneButton = mButton
	mButton.Activated:Connect(function()
		local data = StateController.get()
		local index = data and nextMilestone(data.dexClaimed or {})
		if index ~= nil then
			NetClient.send("Claim", "dex_milestone", tostring(index))
		end
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Position = UDim2.fromOffset(12, HEADER)
	scroll.Size = UDim2.new(1, -24, 1, -HEADER - 10)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.fromOffset(0, #species.species * ROW_HEIGHT)
	scroll.Parent = frame

	for i, entry in species.species do
		local rowFrame = Instance.new("Frame")
		rowFrame.Name = entry.id
		rowFrame.Position = UDim2.fromOffset(0, (i - 1) * ROW_HEIGHT)
		rowFrame.Size = UDim2.new(1, -10, 0, ROW_HEIGHT - 4)
		rowFrame.BackgroundTransparency = 1
		rowFrame.Parent = scroll
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -90, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 12
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Parent = rowFrame
		local claim = button(rowFrame, "Claim")
		claim.Position = UDim2.new(1, 0, 0.5, 0)
		claim.Size = UDim2.fromOffset(80, 26)
		claim.Activated:Connect(function()
			NetClient.send("Claim", "dex_page", entry.id)
		end)
		rows[entry.id] = { label = label, claim = claim }
	end

	toggle.Activated:Connect(function()
		frame.Visible = not frame.Visible
		-- One panel at a time: close the others when this one opens.
		if frame.Visible then
			local others = {
				{ "UpgradeGui", "Upgrades" },
				{ "ShopGui", "Shop" },
				{ "StorageGui", "Storage" },
				{ "RebirthGui", "Rebirth" },
			}
			for _, pair in others do
				local other = gui.Parent and gui.Parent:FindFirstChild(pair[1])
				local otherPanel = other and other:FindFirstChild(pair[2])
				if otherPanel ~= nil and otherPanel:IsA("GuiObject") then
					otherPanel.Visible = false
				end
			end
		end
		dirty = true
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function GlowdexController.Init() end

function GlowdexController.Start()
	build()
	StateController.Changed:Connect(function(key: string)
		if key == "dex" or key == "dexClaimed" then
			dirty = true
		end
	end)
	StateController.Loaded:Connect(function()
		dirty = true
	end)
	RunService.Heartbeat:Connect(function()
		if dirty then
			refresh()
		end
	end)
end

return GlowdexController
