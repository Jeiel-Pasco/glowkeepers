--!strict
-- The storage panel (GAME_SYSTEMS §7). A "Storage" button under "Shop" lists the Glowlings in
-- storage, best first, each with its release value and a Release button, plus "Place best".
-- Releasing an Epic or better asks a second time; Legendary or better needs a hold instead
-- (D9). The server checks everything again (ReleaseService).
--
-- Placeholder for UI: the panel (artists replace it in Phase 3).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Economy = require(Shared:WaitForChild("Economy"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local Inventory = require(Shared:WaitForChild("Inventory"))
local economy = require(Config:WaitForChild("economy")) :: any
local species = require(Config:WaitForChild("species")) :: any
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local StateController = require(script.Parent:WaitForChild("StateController"))

local PANEL = Color3.fromRGB(20, 24, 40)
local BUY = Color3.fromRGB(70, 140, 220)
local WARN = Color3.fromRGB(200, 90, 60)
local ROW_HEIGHT = 46
local HEADER = 40
local EPIC = 4 -- rarity index: Epic and above ask twice
local LEGENDARY = 5 -- Legendary and above need a hold
local CONFIRM_SECONDS = 3
local HOLD_SECONDS = 1.5

local StorageController = {}

local panel: Frame? = nil
local list: ScrollingFrame? = nil
local title: TextLabel? = nil
local dirty = true

local names: { [string]: string } = {}
for _, entry in species.species do
	names[entry.id] = entry.name
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function valueOf(record: any): number
	return Economy.glowlingValue(economy, record.r, record.m, record.s)
end

local function describe(record: any): string
	local rarity = economy.rarities[record.r]
	local mutation = if record.m > 0 then `{economy.mutations[record.m].id} ` else ""
	return `{mutation}{names[record.sp] or record.sp} · {rarity and rarity.id or "?"} · {string.format(
		"%.2f",
		record.s
	)}`
end

-- Epic+: the first press arms the button, a second press within 3 s releases.
-- Legendary+: hold for 1.5 s. Below Epic: one press.
local function wireRelease(button: TextButton, record: any, value: number)
	local label = `Release\n{EconomyMath.formatNumber(value)}`
	button.Text = label
	local send = function()
		NetClient.send("Release", { record.id })
	end
	if record.r >= LEGENDARY then
		button.Text = `Hold\n{EconomyMath.formatNumber(value)}`
		local holding = 0
		button.MouseButton1Down:Connect(function()
			holding += 1
			local mine = holding
			local start = os.clock()
			while holding == mine and button.Parent ~= nil do
				local t = os.clock() - start
				if t >= HOLD_SECONDS then
					holding += 1
					send()
					return
				end
				button.Text = string.format("Holding %.1f", HOLD_SECONDS - t)
				RunService.Heartbeat:Wait()
			end
		end)
		local stop = function()
			holding += 1
			button.Text = `Hold\n{EconomyMath.formatNumber(value)}`
		end
		button.MouseButton1Up:Connect(stop)
		button.MouseLeave:Connect(stop)
	elseif record.r >= EPIC then
		local armedAt = -math.huge
		button.Activated:Connect(function()
			if os.clock() - armedAt <= CONFIRM_SECONDS then
				send()
				return
			end
			armedAt = os.clock()
			button.Text = "Sure?"
			button.BackgroundColor3 = WARN
			task.delay(CONFIRM_SECONDS, function()
				if button.Parent ~= nil and os.clock() - armedAt >= CONFIRM_SECONDS then
					button.Text = label
					button.BackgroundColor3 = BUY
				end
			end)
		end)
	else
		button.Activated:Connect(send)
	end
end

local function rebuild()
	local frame, scroll, header = panel, list, title
	local data = StateController.get()
	if frame == nil or scroll == nil or header == nil or not frame.Visible or data == nil or data.glowlings == nil then
		return
	end
	dirty = false
	for _, child in scroll:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local stored = {}
	for _, id in Inventory.ranked(data, valueOf) do
		if Inventory.locate(data, id) == "storage" then
			table.insert(stored, data.glowlings[id])
		end
	end
	header.Text = `Storage {#stored}/{economy.storage.size}`
	for i, record in stored do
		local row = Instance.new("Frame")
		row.Name = `Row{i}`
		row.Position = UDim2.fromOffset(0, (i - 1) * ROW_HEIGHT)
		row.Size = UDim2.new(1, -10, 0, ROW_HEIGHT - 6)
		row.BackgroundTransparency = 1
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -100, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 14
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = `{describe(record)}\n{EconomyMath.formatNumber(valueOf(record))} Glow/s placed`
		label.Parent = row
		local button = Instance.new("TextButton")
		button.Name = "Release"
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, 0, 0.5, 0)
		button.Size = UDim2.fromOffset(92, 38)
		button.BackgroundColor3 = BUY
		button.Font = Enum.Font.GothamBold
		button.TextSize = 13
		button.TextColor3 = Color3.new(1, 1, 1)
		corner(button, 8)
		button.Parent = row
		wireRelease(button, record, Economy.releaseValue(economy, valueOf(record), data.stars or 0))
		row.Parent = scroll
	end
	scroll.CanvasSize = UDim2.fromOffset(0, #stored * ROW_HEIGHT)
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "StorageGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local toggle = Instance.new("TextButton")
	toggle.Name = "StorageButton"
	toggle.AnchorPoint = Vector2.new(0, 0.5)
	toggle.Position = UDim2.new(0, 12, 0.5, 96) -- under "Shop"
	toggle.Size = UDim2.fromOffset(120, 40)
	toggle.BackgroundColor3 = PANEL
	toggle.BackgroundTransparency = 0.15
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 17
	toggle.TextColor3 = Color3.fromRGB(255, 221, 120)
	toggle.Text = "Storage"
	corner(toggle, 10)
	toggle.Parent = gui

	local frame = Instance.new("Frame")
	frame.Name = "Storage"
	frame.AnchorPoint = Vector2.new(0, 0.5)
	frame.Position = UDim2.new(0, 140, 0.5, 0)
	frame.Size = UDim2.fromOffset(360, 360)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.1
	frame.Visible = false
	corner(frame, 12)
	frame.Parent = gui
	panel = frame

	local header = Instance.new("TextLabel")
	header.Name = "Count"
	header.Position = UDim2.fromOffset(12, 6)
	header.Size = UDim2.new(1, -140, 0, HEADER - 10)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBold
	header.TextSize = 16
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = Color3.fromRGB(255, 221, 120)
	header.Parent = frame
	title = header

	local best = Instance.new("TextButton")
	best.Name = "PlaceBest"
	best.AnchorPoint = Vector2.new(1, 0)
	best.Position = UDim2.new(1, -12, 0, 6)
	best.Size = UDim2.fromOffset(110, HEADER - 10)
	best.BackgroundColor3 = BUY
	best.Font = Enum.Font.GothamBold
	best.TextSize = 14
	best.TextColor3 = Color3.new(1, 1, 1)
	best.Text = "Place best"
	corner(best, 8)
	best.Parent = frame
	best.Activated:Connect(function()
		NetClient.send("PlaceBest")
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Position = UDim2.fromOffset(12, HEADER)
	scroll.Size = UDim2.new(1, -24, 1, -HEADER - 10)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.Parent = frame
	list = scroll

	toggle.Activated:Connect(function()
		frame.Visible = not frame.Visible
		-- One panel at a time: close the upgrades and shop panels when storage opens.
		if frame.Visible then
			for _, pair in { { "UpgradeGui", "Upgrades" }, { "ShopGui", "Shop" } } do
				local other = gui.Parent and gui.Parent:FindFirstChild(pair[1])
				local otherPanel = other and other:FindFirstChild(pair[2])
				if otherPanel ~= nil and otherPanel:IsA("GuiObject") then
					otherPanel.Visible = false
				end
			end
		end
		rebuild()
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function StorageController.Init() end

function StorageController.Start()
	build()
	StateController.Changed:Connect(function(key: string)
		if key == "glowlings" or key == "vault" or key == "display" or key == "stars" then
			dirty = true
		end
	end)
	StateController.Loaded:Connect(function()
		dirty = true
	end)
	RunService.Heartbeat:Connect(function()
		local frame = panel
		if dirty and frame ~= nil and frame.Visible then
			rebuild()
		end
	end)
end

return StorageController
