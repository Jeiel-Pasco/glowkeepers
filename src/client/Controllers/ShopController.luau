--!strict
-- The Lantern shop panel (GAME_SYSTEMS §8). A "Shop" button under "Upgrades" opens four lure
-- rows (price, stock left this window, Buy) and the restock countdown. The window is
-- server time // shop.restockSeconds, as on the server; stock left reads the profile's `shop`
-- (Shared.Shop.left). The server checks everything again; the result arrives as RollResult.
--
-- Placeholder for UI: the panel (artists replace it in Phase 3).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local Shop = require(Shared:WaitForChild("Shop"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local StateController = require(script.Parent:WaitForChild("StateController"))

local PANEL = Color3.fromRGB(20, 24, 40)
local BUY = Color3.fromRGB(70, 140, 220)
local DIM = Color3.fromRGB(60, 60, 70)
local ROW_HEIGHT = 48
local HEADER = 34

type Row = { label: TextLabel, buy: TextButton }

local ShopController = {}

local panel: Frame? = nil
local header: TextLabel? = nil
local rows: { Row } = {}

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function refresh()
	local frame = panel
	local data = StateController.get()
	if frame == nil or not frame.Visible or data == nil or header == nil then
		return
	end
	local now = workspace:GetServerTimeNow()
	local unix = math.floor(now)
	local window = Economy.restockWindow(economy, unix)
	local seconds = Economy.secondsToRestock(economy, unix)
	header.Text = string.format("Restock in %d:%02d", seconds // 60, seconds % 60)
	local glow = StateController.glowAt(now)
	for floor, row in rows do
		local price = Economy.lureCost(economy, floor)
		local left = Shop.left(economy, data.shop, window, floor)
		local name = economy.rarities[floor].id
		row.label.Text =
			`{name} lure\n{EconomyMath.formatNumber(price)} Glow · {left}/{Economy.lureStock(economy, floor)} left`
		local ok = left > 0 and glow >= price
		row.buy.Text = if left > 0 then "Buy" else "Sold out"
		row.buy.BackgroundColor3 = if ok then BUY else DIM
		row.buy.AutoButtonColor = ok
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local toggle = Instance.new("TextButton")
	toggle.Name = "ShopButton"
	toggle.AnchorPoint = Vector2.new(0, 0.5)
	toggle.Position = UDim2.new(0, 12, 0.5, 48) -- under "Upgrades"
	toggle.Size = UDim2.fromOffset(120, 40)
	toggle.BackgroundColor3 = PANEL
	toggle.BackgroundTransparency = 0.15
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 17
	toggle.TextColor3 = Color3.fromRGB(255, 221, 120)
	toggle.Text = "Shop"
	corner(toggle, 10)
	toggle.Parent = gui

	local frame = Instance.new("Frame")
	frame.Name = "Shop"
	frame.AnchorPoint = Vector2.new(0, 0.5)
	frame.Position = UDim2.new(0, 140, 0.5, 0)
	frame.Size = UDim2.fromOffset(320, HEADER + 10 + economy.lures.maxFloor * ROW_HEIGHT)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.1
	frame.Visible = false
	corner(frame, 12)
	frame.Parent = gui
	panel = frame

	local title = Instance.new("TextLabel")
	title.Name = "Restock"
	title.Position = UDim2.fromOffset(12, 6)
	title.Size = UDim2.new(1, -24, 0, HEADER - 6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 221, 120)
	title.Parent = frame
	header = title

	for floor = 1, economy.lures.maxFloor do
		local rowFrame = Instance.new("Frame")
		rowFrame.Name = `Lure{floor}`
		rowFrame.Position = UDim2.fromOffset(12, HEADER + (floor - 1) * ROW_HEIGHT)
		rowFrame.Size = UDim2.new(1, -24, 0, ROW_HEIGHT - 6)
		rowFrame.BackgroundTransparency = 1
		rowFrame.Parent = frame
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -100, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 15
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Parent = rowFrame
		local buy = Instance.new("TextButton")
		buy.AnchorPoint = Vector2.new(1, 0.5)
		buy.Position = UDim2.new(1, 0, 0.5, 0)
		buy.Size = UDim2.fromOffset(90, 36)
		buy.Font = Enum.Font.GothamBold
		buy.TextSize = 15
		buy.TextColor3 = Color3.new(1, 1, 1)
		corner(buy, 8)
		buy.Parent = rowFrame
		buy.Activated:Connect(function()
			NetClient.send("ShopBuy", `lure{floor}`)
		end)
		rows[floor] = { label = label, buy = buy }
	end

	toggle.Activated:Connect(function()
		frame.Visible = not frame.Visible
		-- One panel at a time: close the upgrades panel when the shop opens.
		local upgrades = gui.Parent and gui.Parent:FindFirstChild("UpgradeGui")
		local other = upgrades and upgrades:FindFirstChild("Upgrades")
		if frame.Visible and other ~= nil and other:IsA("GuiObject") then
			other.Visible = false
		end
		refresh()
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function ShopController.Init() end

function ShopController.Start()
	build()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= 0.3 then
			elapsed = 0
			refresh()
		end
	end)
end

return ShopController
