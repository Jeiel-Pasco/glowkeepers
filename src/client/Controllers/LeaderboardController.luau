--!strict
-- The in-world leaderboards (GAME_SYSTEMS §24), painted on the "Leaderboards" station's
-- BoardFace: four cards (Stars, Glowdex, Kindest Keepers = revives this week, Nights this week),
-- each with its top five, gold/silver/bronze medals and the value right-aligned, from the
-- server's `Leaderboards` event. The station can stream out, so the board checks every 2 s and
-- re-attaches when it streams back in. (Older places without a BoardFace get a billboard.)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))

local COLUMNS = {
	{ key = "stars", title = "Stars", icon = "★", color = Color3.fromRGB(255, 214, 110) },
	{ key = "dex", title = "Glowdex", icon = "✦", color = Color3.fromRGB(130, 220, 230) },
	{ key = "revives", title = "Kindest", icon = "♥", color = Color3.fromRGB(255, 150, 170) },
	{ key = "nights", title = "Nights", icon = "☾", color = Color3.fromRGB(180, 160, 255) },
}
local ROWS = 5
local MEDALS = {
	Color3.fromRGB(240, 196, 70),
	Color3.fromRGB(200, 205, 215),
	Color3.fromRGB(205, 140, 90),
}
local INK = Color3.fromRGB(250, 238, 210)
local CARD = Color3.fromRGB(58, 42, 34)
local FONT = Enum.Font.FredokaOne

local LeaderboardController = {}

local gui: (SurfaceGui | BillboardGui)? = nil
local rows: { [string]: { { name: TextLabel, value: TextLabel } } } = {}
local latest: { [string]: any }? = nil -- the last boards, shown again when the board is rebuilt

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2, align: Enum.TextXAlignment): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = FONT
	l.TextScaled = true
	l.TextColor3 = INK
	l.TextXAlignment = align
	l.Text = text
	l.Parent = parent
	return l
end

local function short(n: number): string
	if n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.floor(n))
end

local function show(boards: { [string]: any })
	for _, column in COLUMNS do
		local entries = boards[column.key] or {}
		for i, row in rows[column.key] or {} do
			local entry = entries[i]
			row.name.Text = if entry ~= nil then entry.name else "—"
			row.value.Text = if entry ~= nil then short(entry.value) else ""
		end
	end
end

local function build(root: GuiObject)
	local title = label(
		root,
		"✧ Keepers of the Glade ✧",
		UDim2.fromScale(1, 0.13),
		UDim2.fromScale(0, 0.02),
		Enum.TextXAlignment.Center
	)
	title.TextColor3 = Color3.fromRGB(255, 222, 140)
	local strip = Instance.new("Frame")
	strip.BackgroundTransparency = 1
	strip.Size = UDim2.fromScale(0.96, 0.8)
	strip.Position = UDim2.fromScale(0.02, 0.17)
	strip.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0.015, 0)
	layout.Parent = strip
	for i, column in COLUMNS do
		local card = Instance.new("Frame")
		card.LayoutOrder = i
		card.Size = UDim2.fromScale(0.235, 1)
		card.BackgroundColor3 = CARD
		card.BackgroundTransparency = 0.1
		corner(card, 18)
		local rim = Instance.new("UIStroke")
		rim.Color = column.color
		rim.Thickness = 3
		rim.Transparency = 0.3
		rim.Parent = card
		card.Parent = strip
		local head = label(
			card,
			`{column.icon} {column.title}`,
			UDim2.fromScale(0.9, 0.16),
			UDim2.fromScale(0.05, 0.03),
			Enum.TextXAlignment.Center
		)
		head.TextColor3 = column.color
		local list = {}
		for r = 1, ROWS do
			local y = 0.22 + (r - 1) * 0.155
			local medal = Instance.new("TextLabel")
			medal.Size = UDim2.fromScale(0.16, 0.12)
			medal.Position = UDim2.fromScale(0.04, y)
			medal.SizeConstraint = Enum.SizeConstraint.RelativeYY
			medal.BackgroundColor3 = MEDALS[r] or Color3.fromRGB(90, 72, 60)
			medal.Font = FONT
			medal.TextScaled = true
			medal.Text = tostring(r)
			medal.TextColor3 = if r <= 3 then Color3.fromRGB(60, 40, 20) else INK
			corner(medal, 100)
			medal.Parent = card
			local name =
				label(card, "—", UDim2.fromScale(0.5, 0.1), UDim2.fromScale(0.24, y + 0.01), Enum.TextXAlignment.Left)
			local value =
				label(card, "", UDim2.fromScale(0.24, 0.1), UDim2.fromScale(0.72, y + 0.01), Enum.TextXAlignment.Right)
			value.TextColor3 = column.color
			value.Size = UDim2.fromScale(0.22, 0.1)
			table.insert(list, { name = name, value = value })
		end
		rows[column.key] = list
	end
end

local function station(): Instance?
	for _, s in CollectionService:GetTagged("Station") do
		if s:GetAttribute("Kind") == "Leaderboards" then
			return s
		end
	end
	return nil
end

-- (Re)attaches the board to the station's BoardFace, or as a billboard over it.
local function attach()
	local s = station()
	if s == nil then
		return
	end
	local face = s:FindFirstChild("BoardFace", true)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if gui ~= nil and face ~= nil and gui:IsA("BillboardGui") then
		gui:Destroy() -- the face streamed in after the fallback billboard was made
		gui = nil
	end
	if gui == nil then
		local root: GuiObject
		if face ~= nil then
			local surface = Instance.new("SurfaceGui")
			surface.Name = "Leaderboards"
			surface.Face = Enum.NormalId.Front
			surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			surface.PixelsPerStud = 40
			surface.LightInfluence = 0.3
			surface.MaxDistance = 140
			surface.ResetOnSpawn = false
			gui = surface
		else
			local billboard = Instance.new("BillboardGui")
			billboard.Name = "Leaderboards"
			billboard.Size = UDim2.fromScale(24, 10)
			billboard.StudsOffset = Vector3.new(0, 10, 0)
			billboard.MaxDistance = 120
			billboard.LightInfluence = 0
			billboard.ResetOnSpawn = false
			gui = billboard
		end
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.fromRGB(34, 26, 22)
		frame.BackgroundTransparency = if face ~= nil then 0 else 0.15
		frame.Parent = gui
		root = frame
		build(root)
		if latest ~= nil then
			show(latest)
		end
		(gui :: Instance).Parent = playerGui
	end
	local target = face or (if s:IsA("Model") then s.PrimaryPart else s);
	(gui :: any).Adornee = target
end

function LeaderboardController.Init()
	NetClient.on("Leaderboards", function(boards: { [string]: any })
		latest = boards
		if gui ~= nil then
			show(boards)
		end
	end)
end

function LeaderboardController.Start()
	task.spawn(function()
		while true do
			local g = gui :: any
			local lost = g == nil or g.Adornee == nil or not g.Adornee:IsDescendantOf(workspace)
			if lost or g:IsA("BillboardGui") then -- a billboard keeps looking for the face
				attach()
			end
			task.wait(2)
		end
	end)
end

return LeaderboardController
