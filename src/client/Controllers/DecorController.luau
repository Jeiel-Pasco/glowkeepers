--!strict
-- The decoration panel (GAME_SYSTEMS §18). A "Decor" button top-right (under the goal tracker)
-- opens a list of the 24 decorations with Buy (Embers), Place (at the first free grid spot of
-- the DecorZone) and Remove (the last one placed), plus the base name with a "New name" button
-- that picks a random preset. The server checks everything again (DecorService).
--
-- Placeholder for UI: placement mode (drag and rotate on the grid) is GS work in Phase 4.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Decor = require(Shared:WaitForChild("Decor"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local StateController = require(script.Parent:WaitForChild("StateController"))

local PANEL = Color3.fromRGB(20, 24, 40)
local BUY = Color3.fromRGB(200, 120, 60)
local ALT = Color3.fromRGB(70, 110, 170)
local DIM = Color3.fromRGB(60, 60, 70)
local ROW_HEIGHT = 40

type Row = { label: TextLabel, buy: TextButton, place: TextButton, remove: TextButton }

local HudLayout = require(script.Parent:WaitForChild("HudLayout"))

local DecorController = {}

local panel: Frame? = nil
local nameLabel: TextLabel? = nil
local rows: { [string]: Row } = {}

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
	if frame == nil or not frame.Visible or data == nil or data.decor == nil then
		return
	end
	local decor = data.decor
	local embers = StateController.wallet().embers
	local base = if data.baseName then Decor.baseName(economy, data.baseName.a, data.baseName.n) else ""
	if nameLabel then
		nameLabel.Text = if base ~= "" then `Base: {base}` else "Base: (no name yet)"
	end
	for _, item in economy.decor.items do
		local row = rows[item.id]
		local owned = tonumber(decor.owned[item.id]) or 0
		local placed = Decor.placedCount(decor.placed, item.id)
		row.label.Text =
			`{item.name}\n{if item.exclusive then "Gift" else `{item.price} Embers`} · {placed}/{owned} placed`
		local price = Decor.canBuy(economy, decor, embers, item.id)
		setButton(row.buy, if item.exclusive then "—" else "Buy", if price then BUY else nil)
		local x = Decor.freeSpot(economy, decor, item.id, 0)
		setButton(row.place, "Place", if x ~= nil then ALT else nil)
		setButton(row.remove, "✕", if placed > 0 then ALT else nil)
	end
end

local function onPlace(id: string)
	local data = StateController.get()
	if data == nil then
		return
	end
	local x, z = Decor.freeSpot(economy, data.decor, id, 0)
	if x ~= nil then
		NetClient.send("DecorPlace", id, x, z, 0)
	end
end

local function onRemove(id: string)
	local data = StateController.get()
	if data == nil then
		return
	end
	for i = #data.decor.placed, 1, -1 do
		local p = data.decor.placed[i]
		if p.id == id then
			NetClient.send("DecorRemove", id, p.x, p.z)
			return
		end
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DecorGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local toggle = Instance.new("TextButton")
	toggle.Name = "DecorButton"
	toggle.Size = UDim2.fromOffset(120, 36)
	toggle.BackgroundColor3 = PANEL
	toggle.BackgroundTransparency = 0.15
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 17
	toggle.TextColor3 = Color3.fromRGB(230, 190, 140)
	toggle.Text = "Decor"
	corner(toggle, 10)
	HudLayout.dock("right", toggle, 3)

	local frame = Instance.new("Frame")
	frame.Name = "Decor"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -140, 0, 282)
	frame.Size = UDim2.fromOffset(360, 320)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.1
	frame.Visible = false
	corner(frame, 12)
	frame.Parent = gui
	panel = frame

	local label = Instance.new("TextLabel")
	label.Name = "BaseName"
	label.Position = UDim2.fromOffset(12, 8)
	label.Size = UDim2.new(1, -130, 0, 30)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = frame
	nameLabel = label
	local rename = Instance.new("TextButton")
	rename.Name = "NewName"
	rename.AnchorPoint = Vector2.new(1, 0)
	rename.Position = UDim2.new(1, -12, 0, 8)
	rename.Size = UDim2.fromOffset(110, 30)
	rename.Font = Enum.Font.GothamBold
	rename.TextSize = 14
	rename.TextColor3 = Color3.new(1, 1, 1)
	setButton(rename, "New name", ALT)
	corner(rename, 8)
	rename.Parent = frame
	rename.Activated:Connect(function()
		NetClient.send("SetBaseName", math.random(#economy.decor.nameAdjectives), math.random(#economy.decor.nameNouns))
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Position = UDim2.fromOffset(8, 46)
	scroll.Size = UDim2.new(1, -16, 1, -54)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.fromOffset(0, #economy.decor.items * ROW_HEIGHT)
	scroll.Parent = frame

	for i, item in economy.decor.items do
		local row = Instance.new("Frame")
		row.Name = item.id
		row.Position = UDim2.fromOffset(4, (i - 1) * ROW_HEIGHT)
		row.Size = UDim2.new(1, -14, 0, ROW_HEIGHT - 4)
		row.BackgroundTransparency = 1
		row.Parent = scroll
		local text = Instance.new("TextLabel")
		text.Size = UDim2.new(1, -170, 1, 0)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBold
		text.TextSize = 12
		text.TextWrapped = true
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextColor3 = Color3.new(1, 1, 1)
		text.Parent = row
		local function makeButton(name: string, x: number, width: number): TextButton
			local b = Instance.new("TextButton")
			b.Name = name
			b.AnchorPoint = Vector2.new(1, 0.5)
			b.Position = UDim2.new(1, x, 0.5, 0)
			b.Size = UDim2.fromOffset(width, 28)
			b.Font = Enum.Font.GothamBold
			b.TextSize = 13
			b.TextColor3 = Color3.new(1, 1, 1)
			corner(b, 8)
			b.Parent = row
			return b
		end
		local remove = makeButton("Remove", 0, 30)
		local place = makeButton("Place", -34, 60)
		local buy = makeButton("Buy", -98, 60)
		local id = item.id
		buy.Activated:Connect(function()
			NetClient.send("DecorBuy", id)
		end)
		place.Activated:Connect(function()
			onPlace(id)
		end)
		remove.Activated:Connect(function()
			onRemove(id)
		end)
		rows[id] = { label = text, buy = buy, place = place, remove = remove }
	end

	toggle.Activated:Connect(function()
		frame.Visible = not frame.Visible
		refresh()
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function DecorController.Init() end

function DecorController.Start()
	build()
	StateController.Changed:Connect(function(key: string)
		if key == "decor" or key == "baseName" then
			refresh()
		end
	end)
	StateController.WalletChanged:Connect(refresh)
end

return DecorController
