--!strict
-- The in-world leaderboards (GAME_SYSTEMS §24): a board over the "Leaderboards" station with
-- four columns (Stars, Glowdex, Kindest Keepers = revives this week, Nights this week), from
-- the server's `Leaderboards` event. The station can stream out, so the board checks every 2 s
-- and re-attaches when it streams back in.
--
-- Placeholder for UI: BL builds the real boards in Phase 4.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))

local COLUMNS = {
	{ key = "stars", title = "Stars" },
	{ key = "dex", title = "Glowdex" },
	{ key = "revives", title = "Kindest Keepers" },
	{ key = "nights", title = "Nights (week)" },
}

local LeaderboardController = {}

local board: BillboardGui? = nil
local columns: { [string]: TextLabel } = {}

local function attach()
	local gui = board
	if gui == nil then
		return
	end
	for _, station in CollectionService:GetTagged("Station") do
		if station:GetAttribute("Kind") == "Leaderboards" then
			local part = if station:IsA("Model")
				then station.PrimaryPart or station:FindFirstChildWhichIsA("BasePart", true)
				else station
			if part ~= nil and part:IsA("BasePart") then
				gui.Adornee = part
				return
			end
		end
	end
end

local function show(boards: { [string]: any })
	for _, column in COLUMNS do
		local lines = { column.title }
		for i, entry in boards[column.key] or {} do
			table.insert(lines, `{i}. {entry.name}  {math.floor(entry.value)}`)
		end
		if #lines == 1 then
			table.insert(lines, "—")
		end
		columns[column.key].Text = table.concat(lines, "\n")
	end
end

local function build()
	local gui = Instance.new("BillboardGui")
	gui.Name = "Leaderboards"
	gui.Size = UDim2.fromScale(24, 9)
	gui.StudsOffset = Vector3.new(0, 9, 0)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
	frame.BackgroundTransparency = 0.2
	frame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Parent = frame
	for i, column in COLUMNS do
		local label = Instance.new("TextLabel")
		label.Name = column.key
		label.LayoutOrder = i
		label.Size = UDim2.fromScale(1 / #COLUMNS, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.TextColor3 = Color3.fromRGB(240, 230, 200)
		label.Text = column.title
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0.04, 0)
		pad.PaddingLeft = UDim.new(0.04, 0)
		pad.PaddingRight = UDim.new(0.04, 0)
		pad.Parent = label
		label.Parent = frame
		columns[column.key] = label
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	board = gui
end

function LeaderboardController.Init()
	NetClient.on("Leaderboards", function(boards: { [string]: any })
		if board ~= nil then
			show(boards)
		end
	end)
end

function LeaderboardController.Start()
	build()
	-- The station (or its parts) can stream in and out: re-attach whenever the board lost it.
	task.spawn(function()
		while true do
			local gui = board :: BillboardGui
			if gui.Adornee == nil or not gui.Adornee:IsDescendantOf(workspace) then
				attach()
			end
			task.wait(2)
		end
	end)
end

return LeaderboardController
