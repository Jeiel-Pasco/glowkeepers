--!strict
-- The goal tracker (GAME_SYSTEMS §19 †): 3 lines top-right, under the Lock button and the
-- shield label: Next (within a cycle), Session (1-5 cycles) and Long (a Glowdex page or a
-- weekly quest), each with an estimate in nights from current income. Rules in Shared.Goals.
-- Client-only: it reads the replicated profile and Wallet, and refreshes once a second.
--
-- Placeholder for UI (artists replace it in Phase 4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Economy = require(Shared:WaitForChild("Economy"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local Goals = require(Shared:WaitForChild("Goals"))
local economy = require(Config:WaitForChild("economy")) :: any
local species = require(Config:WaitForChild("species")) :: any
local StateController = require(script.Parent:WaitForChild("StateController"))
local QuestController = require(script.Parent:WaitForChild("QuestController"))

local UPGRADES =
	{ { id = "lantern", name = "Lantern" }, { id = "boots", name = "Boots" }, { id = "slots", name = "Slots" } }
local BANDS = { "Next", "Session", "Long" }

local HudLayout = require(script.Parent:WaitForChild("HudLayout"))

local GoalController = {}

local lines: { TextLabel } = {}

local function fmt(n: number): string
	return EconomyMath.formatNumber(math.ceil(n))
end

local function refresh()
	local data = StateController.get()
	if data == nil then
		return
	end
	local now = workspace:GetServerTimeNow()
	local wallet = StateController.wallet()
	local up = data.up or {}
	local upgrades = {}
	for _, u in UPGRADES do
		local level = tonumber(up[u.id]) or 0
		table.insert(upgrades, { name = `{u.name} {level + 1}`, cost = Economy.upgradeCost(economy, u.id, level) })
	end
	local list = Goals.candidates(economy, {
		glow = StateController.glowAt(now),
		since = StateController.sinceRebirthAt(now),
		perSec = wallet.perSec,
		unix = math.floor(now),
		upgrades = upgrades,
		rebirthRequirement = Economy.rebirthRequirement(economy, tonumber(data.stars) or 0),
		weekly = data.quests and data.quests.weekly,
		questName = QuestController.name,
		dex = data.dex,
		dexClaimed = data.dexClaimed,
		species = species.species,
	})
	local picked = Goals.pick(economy, list)
	for i, label in lines do
		local goal = picked[i]
		label.Text = if goal then `{BANDS[i]} · {Goals.text(economy, goal, fmt)}` else ""
		label.Visible = goal ~= nil
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "GoalGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local frame = Instance.new("Frame")
	frame.Name = "Goals"
	frame.AnchorPoint = Vector2.new(1, 0)
	-- Beside the right dock, level with its top.
	frame.Position = UDim2.new(1, -(12 + HudLayout.RIGHT_WIDTH + 8), 0, HudLayout.RIGHT_TOP)
	frame.Size = UDim2.fromOffset(300, 78)
	frame.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
	frame.BackgroundTransparency = 0.35
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	frame.Parent = gui

	for i, band in BANDS do
		local label = Instance.new("TextLabel")
		label.Name = band
		label.Position = UDim2.fromOffset(10, 4 + (i - 1) * 24)
		label.Size = UDim2.new(1, -20, 0, 22)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 13
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.TextColor3 = Color3.fromRGB(230, 230, 240)
		label.Text = ""
		label.Parent = frame
		lines[i] = label
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function GoalController.Init() end

function GoalController.Start()
	build()
	task.spawn(function()
		while true do
			refresh()
			task.wait(1)
		end
	end)
end

return GoalController
