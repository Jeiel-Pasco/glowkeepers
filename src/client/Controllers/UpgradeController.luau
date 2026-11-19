--!strict
-- The upgrade panel (GAME_SYSTEMS §9, §11). An "Upgrades" button on the left opens rows for
-- Lantern, Boots and Slots (level, next price, Buy and Max) and Lock Charges (held, buy with
-- Glow or Embers). Prices come from Shared.Economy, the balance from StateController's
-- extrapolated wallet; the server checks everything again (UpgradeService).
--
-- Placeholder for UI: the panel (artists replace it in Phase 3).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local StateController = require(script.Parent:WaitForChild("StateController"))

local PANEL = Color3.fromRGB(20, 24, 40)
local BUY = Color3.fromRGB(70, 140, 220)
local DIM = Color3.fromRGB(60, 60, 70)
local ROW_HEIGHT = 52

type Row = { label: TextLabel, buy: TextButton, alt: TextButton }

local UPGRADES = {
	{ id = "lantern", name = "Lantern", effect = "+12% luck each" },
	{ id = "boots", name = "Boots", effect = "+4% run; +1 catch per 5" },
	{ id = "slots", name = "Slots", effect = "+1 display slot" },
}

local HudLayout = require(script.Parent:WaitForChild("HudLayout"))

local UpgradeController = {}

local panel: Frame? = nil
local rows: { [string]: Row } = {}

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function makeButton(parent: Instance, x: number, width: number): TextButton
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0, 0.5)
	b.Position = UDim2.new(0, x, 0.5, 0)
	b.Size = UDim2.fromOffset(width, 36)
	b.BackgroundColor3 = BUY
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.TextColor3 = Color3.new(1, 1, 1)
	corner(b, 8)
	b.Parent = parent
	return b
end

local function makeRow(parent: Instance, index: number, name: string): Row
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = UDim2.fromOffset(10, 10 + (index - 1) * ROW_HEIGHT)
	frame.Size = UDim2.new(1, -20, 0, ROW_HEIGHT - 6)
	frame.BackgroundTransparency = 1
	frame.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 170, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = frame
	return { label = label, buy = makeButton(frame, 176, 90), alt = makeButton(frame, 272, 70) }
end

local function setButton(b: TextButton, text: string, enabled: boolean)
	b.Text = text
	b.BackgroundColor3 = if enabled then BUY else DIM
	b.AutoButtonColor = enabled
end

local function refresh()
	local frame = panel
	local data = StateController.get()
	if frame == nil or not frame.Visible or data == nil or data.up == nil then
		return
	end
	local now = workspace:GetServerTimeNow()
	local glow = StateController.glowAt(now)
	for _, upgrade in UPGRADES do
		local row = rows[upgrade.id]
		local level = data.up[upgrade.id] or 0
		local max = Economy.upgradeMax(economy, upgrade.id)
		local shown = if upgrade.id == "slots"
			then `{Economy.slotCount(economy, level)}/{economy.upgrades.slots.max}`
			else `{level}/{max}`
		row.label.Text = `{upgrade.name} {shown}\n{upgrade.effect}`
		local price = Economy.upgradeCost(economy, upgrade.id, level)
		if price == nil then
			setButton(row.buy, "MAX", false)
			setButton(row.alt, "MAX", false)
		else
			setButton(row.buy, EconomyMath.formatNumber(price), glow >= price)
			setButton(row.alt, "Max", glow >= price)
		end
	end
	local wallet = StateController.wallet()
	local charges = data.lockCharges or 0
	local full = charges >= economy.lock.maxCharges
	local glowPrice = Economy.lockChargePrice(economy, "glow", wallet.perSec)
	local row = rows.lockCharge
	row.label.Text = `Lock Charges {charges}/{economy.lock.maxCharges}\nSkip the lock recharge`
	setButton(row.buy, `{EconomyMath.formatNumber(glowPrice)} Glow`, not full and glow >= glowPrice)
	setButton(row.alt, `{economy.lock.chargeEmbers} Em`, not full and wallet.embers >= economy.lock.chargeEmbers)
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "UpgradeGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local toggle = Instance.new("TextButton")
	toggle.Name = "UpgradesButton"
	toggle.Size = UDim2.fromOffset(120, 40)
	toggle.BackgroundColor3 = PANEL
	toggle.BackgroundTransparency = 0.15
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 17
	toggle.TextColor3 = Color3.fromRGB(255, 221, 120)
	toggle.Text = "Upgrades"
	corner(toggle, 10)
	HudLayout.dock("left", toggle, 1)

	local frame = Instance.new("Frame")
	frame.Name = "Upgrades"
	frame.AnchorPoint = Vector2.new(0, 0.5)
	frame.Position = UDim2.new(0, 140, 0.5, 0)
	frame.Size = UDim2.fromOffset(362, 20 + 4 * ROW_HEIGHT)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.1
	frame.Visible = false
	corner(frame, 12)
	frame.Parent = gui
	panel = frame

	for i, upgrade in UPGRADES do
		local row = makeRow(frame, i, upgrade.name)
		rows[upgrade.id] = row
		row.buy.Activated:Connect(function()
			NetClient.send("UpgradeBuy", upgrade.id, false)
		end)
		row.alt.Activated:Connect(function()
			NetClient.send("UpgradeBuy", upgrade.id, true)
		end)
	end
	local lockRow = makeRow(frame, 4, "LockCharges")
	rows.lockCharge = lockRow
	lockRow.buy.Activated:Connect(function()
		NetClient.send("LockChargeBuy", "glow")
	end)
	lockRow.alt.Activated:Connect(function()
		NetClient.send("LockChargeBuy", "embers")
	end)

	toggle.Activated:Connect(function()
		frame.Visible = not frame.Visible
		refresh()
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function UpgradeController.Init() end

function UpgradeController.Start()
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

return UpgradeController
