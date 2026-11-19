--!strict
-- The store (GAME_SYSTEMS §23): a "Store" button top-right (under "Decor") opens the game
-- passes and developer products with their R$ price. Buy asks the server to prompt
-- (PromptProduct); the server checks caps, policy and timing again. Owned passes show "Owned"
-- (player attributes Pass_<key>); Server Luck is hidden when paid random items are restricted.
-- No pop-ups: the store only opens when tapped.
--
-- Placeholder for UI (GS builds the real store in Phase 5).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))

local PANEL = Color3.fromRGB(20, 24, 40)
local BUY = Color3.fromRGB(60, 160, 90)
local DIM = Color3.fromRGB(60, 60, 70)
local ROW_HEIGHT = 38

type Row = { frame: Frame, button: TextButton, pass: boolean }

local StoreController = {}

local rows: { [string]: Row } = {}
local panel: Frame? = nil

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function refresh()
	local player = Players.LocalPlayer
	local restricted = player:GetAttribute("PaidRandomRestricted") ~= false
	local y = 10
	for _, item in economy.store.passes do
		local row = rows[item.key]
		local owned = player:GetAttribute(`Pass_{item.key}`) == true
		row.button.Text = if owned then "Owned" else "Buy"
		row.button.BackgroundColor3 = if owned then DIM else BUY
		row.button.AutoButtonColor = not owned
		row.frame.Position = UDim2.fromOffset(12, y)
		y += ROW_HEIGHT
	end
	for _, item in economy.store.products do
		local row = rows[item.key]
		row.frame.Visible = not (item.paidRandom and restricted)
		if row.frame.Visible then
			row.frame.Position = UDim2.fromOffset(12, y)
			y += ROW_HEIGHT
		end
	end
	if panel then
		panel.Size = UDim2.fromOffset(340, y + 8)
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "StoreGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local toggle = Instance.new("TextButton")
	toggle.Name = "StoreButton"
	toggle.AnchorPoint = Vector2.new(1, 0)
	toggle.Position = UDim2.new(1, -12, 0, 324) -- under "Decor"
	toggle.Size = UDim2.fromOffset(120, 36)
	toggle.BackgroundColor3 = PANEL
	toggle.BackgroundTransparency = 0.15
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 17
	toggle.TextColor3 = Color3.fromRGB(140, 230, 160)
	toggle.Text = "Store"
	corner(toggle, 10)
	toggle.Parent = gui

	local frame = Instance.new("Frame")
	frame.Name = "Store"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -140, 0, 282)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.1
	frame.Visible = false
	corner(frame, 12)
	frame.Parent = gui
	panel = frame

	local function addRow(item: any, pass: boolean)
		local row = Instance.new("Frame")
		row.Name = item.key
		row.Size = UDim2.new(1, -24, 0, ROW_HEIGHT - 6)
		row.BackgroundTransparency = 1
		row.Parent = frame
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -90, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 14
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = `{item.name}  ·  R$ {item.robux}{if pass then "  (pass)" else ""}`
		label.Parent = row
		local button = Instance.new("TextButton")
		button.Name = "Buy"
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, 0, 0.5, 0)
		button.Size = UDim2.fromOffset(80, 28)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 14
		button.TextColor3 = Color3.new(1, 1, 1)
		button.BackgroundColor3 = BUY
		button.Text = "Buy"
		corner(button, 8)
		button.Parent = row
		local key = item.key
		button.Activated:Connect(function()
			if not (pass and Players.LocalPlayer:GetAttribute(`Pass_{key}`) == true) then
				NetClient.send("PromptProduct", key)
			end
		end)
		rows[key] = { frame = row, button = button, pass = pass }
	end
	for _, item in economy.store.passes do
		addRow(item, true)
	end
	for _, item in economy.store.products do
		addRow(item, false)
	end

	toggle.Activated:Connect(function()
		frame.Visible = not frame.Visible
		if frame.Visible then
			local decor = gui.Parent and gui.Parent:FindFirstChild("DecorGui")
			local decorPanel = decor and decor:FindFirstChild("Decor")
			if decorPanel ~= nil and decorPanel:IsA("GuiObject") then
				decorPanel.Visible = false
			end
		end
		refresh()
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	refresh()
end

function StoreController.Init() end

function StoreController.Start()
	build()
	Players.LocalPlayer.AttributeChanged:Connect(function(name: string)
		if string.sub(name, 1, 5) == "Pass_" or name == "PaidRandomRestricted" then
			refresh()
		end
	end)
end

return StoreController
