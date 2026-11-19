--!strict
-- The trade panel (GAME_SYSTEMS §17). A "Trade" button top-right (under "Store") opens it:
--   no trade: the other players in the server with Request, and an incoming request with
--             Accept / Decline (it also opens the panel);
--   trading:  your storage (tap to add or remove from your offer, up to 4), their offer, the
--             fee you'd pay, the "looks uneven" warning, Confirm (after 5 s) and Cancel, then
--             the 2-minute cooling-off countdown.
-- The server checks everything again (TradeService).
--
-- Placeholder for UI (GS builds TradeUI in Phase 5).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local economy = require(Config:WaitForChild("economy")) :: any
local species = require(Config:WaitForChild("species")) :: any
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local StateController = require(script.Parent:WaitForChild("StateController"))

local PANEL = Color3.fromRGB(20, 24, 40)
local GO = Color3.fromRGB(60, 160, 90)
local PICKED = Color3.fromRGB(200, 150, 60)
local DIM = Color3.fromRGB(60, 60, 70)
local BAD = Color3.fromRGB(170, 70, 70)

local TradeController = {}

local names: { [string]: string } = {}
for _, s in species.species do
	names[s.id] = s.name
end

local state: any = nil -- the TradeState view, or nil
local request: { id: number, name: string }? = nil
local panel: Frame? = nil
local header: TextLabel? = nil
local status: TextLabel? = nil
local left: ScrollingFrame? = nil
local right: TextLabel? = nil
local confirm: TextButton? = nil
local cancel: TextButton? = nil

local function describe(record: any): string
	local rarity = economy.rarities[record.r]
	return `{rarity and rarity.id or "?"} {names[record.sp] or record.sp}`
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function button(parent: Instance, text: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = color
	b.Text = text
	corner(b, 8)
	b.Parent = parent
	return b
end

local function myOffer(): { string }
	local ids = {}
	if state ~= nil then
		for _, record in state.mine do
			table.insert(ids, record.id)
		end
	end
	return ids
end

local function storageRecords(): { any }
	local data = StateController.get()
	if data == nil then
		return {}
	end
	local onPad = {}
	for _, map in { data.vault or {}, data.display or {} } do
		for _, id in map do
			onPad[id] = true
		end
	end
	local out = {}
	for id, record in data.glowlings or {} do
		if not onPad[id] then
			table.insert(out, record)
		end
	end
	table.sort(out, function(a, b)
		return if a.r ~= b.r then a.r > b.r else a.id < b.id
	end)
	return out
end

local function clearList(list: Instance)
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function render()
	local frame, list = panel, left
	if frame == nil or list == nil or not frame.Visible then
		return
	end
	clearList(list)
	local y = 0
	local function row(text: string, color: Color3, onTap: () -> ())
		local b = button(list, text, color)
		b.Size = UDim2.new(1, -8, 0, 26)
		b.Position = UDim2.fromOffset(0, y)
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.Activated:Connect(onTap)
		y += 30
	end
	local s = state
	if s == nil then
		(header :: TextLabel).Text = "Trade with…"
		local pending = request
		if pending ~= nil then
			row(`{pending.name} wants to trade: Accept`, GO, function()
				NetClient.send("TradeRespond", pending.id, true)
				request = nil
			end)
			row("Decline", BAD, function()
				NetClient.send("TradeRespond", pending.id, false)
				request = nil
				render()
			end)
		end
		for _, player in Players:GetPlayers() do
			if player ~= Players.LocalPlayer then
				local id = player.UserId
				row(`Request {player.DisplayName}`, DIM, function()
					NetClient.send("TradeRequest", id)
				end)
			end
		end
		(status :: TextLabel).Text = "";
		(right :: TextLabel).Text = "";
		(confirm :: TextButton).Visible = false;
		(cancel :: TextButton).Visible = false
	else
		(header :: TextLabel).Text = `Trading with {s.partner}`
		local picked = {}
		for _, id in myOffer() do
			picked[id] = true
		end
		for _, record in storageRecords() do
			local id = record.id
			row(describe(record), if picked[id] then PICKED else DIM, function()
				if state == nil or state.escrowEnds ~= nil then
					return
				end
				local ids = myOffer()
				local at = table.find(ids, id)
				if at then
					table.remove(ids, at)
				elseif #ids < economy.trade.maxPerSide then
					table.insert(ids, id)
				end
				NetClient.send("TradeOffer", ids)
			end)
		end
		local theirs = {}
		for _, record in s.theirs do
			table.insert(theirs, describe(record))
		end
		(right :: TextLabel).Text = `They offer:\n{if #theirs > 0 then table.concat(theirs, "\n") else "(nothing yet)"}`
		local now = workspace:GetServerTimeNow()
		local lines = { `Fee for what you get: {s.feeIn} Embers` }
		if s.uneven then
			table.insert(lines, "This trade looks uneven.")
		end
		if s.escrowEnds ~= nil then
			table.insert(lines, `Both confirmed: swapping in {math.max(0, math.ceil(s.escrowEnds - now))} s`)
		else
			table.insert(
				lines,
				`You: {if s.myConfirmed then "confirmed" else "…"} · Them: {if s.theirConfirmed
					then "confirmed"
					else "…"}`
			)
		end
		(status :: TextLabel).Text = table.concat(lines, "\n")
		local c = confirm :: TextButton
		c.Visible = s.escrowEnds == nil
		local wait = math.ceil(s.confirmAt - now)
		c.Text = if s.myConfirmed then "Confirmed" elseif wait > 0 then `Confirm in {wait}` else "Confirm"
		c.BackgroundColor3 = if s.myConfirmed or wait > 0 then DIM else GO;
		(cancel :: TextButton).Visible = true
	end
	list.CanvasSize = UDim2.fromOffset(0, y)
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TradeGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local toggle = button(gui, "Trade", PANEL)
	toggle.Name = "TradeButton"
	toggle.AnchorPoint = Vector2.new(1, 0)
	toggle.Position = UDim2.new(1, -12, 0, 366) -- under "Store"
	toggle.Size = UDim2.fromOffset(120, 36)
	toggle.BackgroundTransparency = 0.15
	toggle.TextSize = 17
	toggle.TextColor3 = Color3.fromRGB(200, 200, 255)

	local frame = Instance.new("Frame")
	frame.Name = "Trade"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -140, 0, 200)
	frame.Size = UDim2.fromOffset(420, 330)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.1
	frame.Visible = false
	corner(frame, 12)
	frame.Parent = gui
	panel = frame

	local function label(name: string, pos: UDim2, size: UDim2, textSize: number): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.Position = pos
		l.Size = size
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextSize = textSize
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.TextColor3 = Color3.new(1, 1, 1)
		l.Text = ""
		l.Parent = frame
		return l
	end
	header = label("Header", UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 22), 16)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Position = UDim2.fromOffset(12, 36)
	scroll.Size = UDim2.new(0.5, -16, 1, -130)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.Parent = frame
	left = scroll
	right = label("Theirs", UDim2.new(0.5, 4, 0, 36), UDim2.new(0.5, -16, 1, -130), 13)
	status = label("Status", UDim2.new(0, 12, 1, -90), UDim2.new(1, -24, 0, 46), 13)
	confirm = button(frame, "Confirm", DIM)
	local c = confirm :: TextButton
	c.Name = "Confirm"
	c.Position = UDim2.new(0, 12, 1, -40)
	c.Size = UDim2.fromOffset(120, 30)
	c.Activated:Connect(function()
		NetClient.send("TradeConfirm")
	end)
	cancel = button(frame, "Cancel", BAD)
	local x = cancel :: TextButton
	x.Name = "Cancel"
	x.Position = UDim2.new(0, 140, 1, -40)
	x.Size = UDim2.fromOffset(100, 30)
	x.Activated:Connect(function()
		NetClient.send("TradeCancel")
	end)

	toggle.Activated:Connect(function()
		frame.Visible = not frame.Visible
		render()
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function TradeController.Init()
	NetClient.on("TradeState", function(view: any)
		state = view
		if view ~= nil and panel ~= nil then
			panel.Visible = true
		end
		render()
	end)
	NetClient.on("TradeRequested", function(fromId: number, fromName: string)
		request = { id = fromId, name = fromName }
		if panel ~= nil then
			panel.Visible = true
		end
		render()
	end)
end

function TradeController.Start()
	build()
	StateController.Changed:Connect(function(key: string)
		if key == "glowlings" or key == "vault" or key == "display" then
			render()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if state ~= nil then
				render() -- countdowns
			end
		end
	end)
end

return TradeController
