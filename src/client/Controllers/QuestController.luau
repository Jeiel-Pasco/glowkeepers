--!strict
-- The quest panel (GAME_SYSTEMS §19). A "Quests" button under "Gift" opens the 3 daily and 3
-- weekly quests with progress, Claim when done, and the day's free reroll on daily quests.
-- The server checks everything again (QuestService).
--
-- Placeholder for UI: the panel (artists replace it in Phase 4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local StateController = require(script.Parent:WaitForChild("StateController"))

local PANEL = Color3.fromRGB(20, 24, 40)
local READY = Color3.fromRGB(90, 170, 110)
local ALT = Color3.fromRGB(70, 110, 170)
local DIM = Color3.fromRGB(60, 60, 70)
local ROW_HEIGHT = 44

local TEXT: { [string]: string } = {
	feed = "Feed the fire",
	revive = "Revive a teammate",
	catch_night = "Catch Glowlings at night",
	catch_rare = "Catch a Rare or better at night",
	survive = "Survive nights",
	lure = "Buy lures",
	place = "Place Glowlings",
	glow = "Earn Glow",
	steal = "Steal a Glowling",
	bronze = "Finish Bronze Glowdex pages",
	star = "Earn a Star",
}

type Row = { label: TextLabel, claim: TextButton, reroll: TextButton? }

local HudLayout = require(script.Parent:WaitForChild("HudLayout"))

local QuestController = {}

local panel: Frame? = nil
local rows: { [string]: Row } = {} -- "d1".."d3", "w1".."w3"
local dirty = true

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function setButton(b: TextButton, text: string, color: Color3?)
	b.Text = text
	b.BackgroundColor3 = color or DIM
	b.AutoButtonColor = color ~= nil
end

local function refresh()
	local frame = panel
	local data = StateController.get()
	if frame == nil or not frame.Visible or data == nil or data.quests == nil then
		return
	end
	dirty = false
	local quests = data.quests
	local rerollUsed = quests.rerollDay == quests.day
	for _, scope in { "d", "w" } do
		local list = if scope == "d" then quests.daily else quests.weekly
		for i = 1, 3 do
			local row = rows[`{scope}{i}`]
			local q = list and list[i]
			if q == nil then
				row.label.Text = ""
				setButton(row.claim, "")
				if row.reroll then
					setButton(row.reroll, "")
				end
				continue
			end
			local name = TEXT[q.event] or q.event
			local prefix = if scope == "d" then "Daily" else "Weekly"
			row.label.Text = `{prefix}: {name}\n{EconomyMath.formatNumber(q.n)} / {EconomyMath.formatNumber(q.target)}`
			if q.claimed then
				setButton(row.claim, "Done")
			elseif q.n >= q.target then
				setButton(row.claim, "Claim", READY)
			else
				setButton(row.claim, "…")
			end
			if row.reroll then
				local canReroll = not rerollUsed and not q.claimed
				setButton(row.reroll, "↻", if canReroll then ALT else nil)
			end
		end
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "QuestGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local toggle = Instance.new("TextButton")
	toggle.Name = "QuestsButton"
	toggle.Size = UDim2.fromOffset(120, 40)
	toggle.BackgroundColor3 = PANEL
	toggle.BackgroundTransparency = 0.15
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 17
	toggle.TextColor3 = Color3.fromRGB(140, 200, 255)
	toggle.Text = "Quests"
	corner(toggle, 10)
	HudLayout.dock("left", toggle, 7)

	local frame = Instance.new("Frame")
	frame.Name = "Quests"
	frame.AnchorPoint = Vector2.new(0, 0.5)
	frame.Position = UDim2.new(0, 140, 0.5, 0)
	frame.Size = UDim2.fromOffset(340, 20 + 6 * ROW_HEIGHT)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.1
	frame.Visible = false
	corner(frame, 12)
	frame.Parent = gui
	panel = frame

	local order = { "d1", "d2", "d3", "w1", "w2", "w3" }
	for i, key in order do
		local rowFrame = Instance.new("Frame")
		rowFrame.Name = key
		rowFrame.Position = UDim2.fromOffset(12, 10 + (i - 1) * ROW_HEIGHT)
		rowFrame.Size = UDim2.new(1, -24, 0, ROW_HEIGHT - 6)
		rowFrame.BackgroundTransparency = 1
		rowFrame.Parent = frame
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -120, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 13
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Parent = rowFrame
		local function makeButton(name: string, x: number, width: number): TextButton
			local b = Instance.new("TextButton")
			b.Name = name
			b.AnchorPoint = Vector2.new(1, 0.5)
			b.Position = UDim2.new(1, x, 0.5, 0)
			b.Size = UDim2.fromOffset(width, 30)
			b.Font = Enum.Font.GothamBold
			b.TextSize = 14
			b.TextColor3 = Color3.new(1, 1, 1)
			corner(b, 8)
			b.Parent = rowFrame
			return b
		end
		local claim = makeButton("Claim", 0, 72)
		claim.Activated:Connect(function()
			NetClient.send("Claim", "quest", key)
		end)
		local reroll = nil
		if string.sub(key, 1, 1) == "d" then
			reroll = makeButton("Reroll", -78, 34)
			local index = tonumber(string.sub(key, 2)) :: number
			reroll.Activated:Connect(function()
				NetClient.send("QuestReroll", index)
			end)
		end
		rows[key] = { label = label, claim = claim, reroll = reroll }
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
				{ "GlowdexGui", "Glowdex" },
				{ "GiftGui", "Gift" },
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

-- The quest text for an event id (the goal tracker uses it).
function QuestController.name(event: string): string
	return TEXT[event] or event
end

function QuestController.Init() end

function QuestController.Start()
	build()
	StateController.Changed:Connect(function(key: string)
		if key == "quests" then
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

return QuestController
