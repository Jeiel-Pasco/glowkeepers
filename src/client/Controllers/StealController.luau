--!strict
-- Stealing on the client (GAME_SYSTEMS §10). By day, next to another player's display pad
-- with a Glowling on it, the context button says "Grab": holding it sends GrabStart, letting
-- go early sends GrabCancel. The server times the hold and checks every rule again; the bar
-- here only follows the character's `GrabUntil`. Carriers (character `CarryFrom`) are Marked
-- with a glow everyone sees; the owner they robbed sees them through walls.
--
-- Placeholders for GS: the hold bar, the carry label and the Highlight colours.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Steal = require(Shared:WaitForChild("Steal"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local InputController = require(script.Parent:WaitForChild("InputController"))
local CycleFXController = require(script.Parent:WaitForChild("CycleFXController"))
local PlotController = require(script.Parent:WaitForChild("PlotController"))

local GRAB = "Grab"
local CHECK_SECONDS = 0.15
local MARGIN = 1 -- studs inside the server's range, so the button never shows where the server says no
local MARK_COLOR = Color3.fromRGB(255, 200, 80)

local StealController = {}

local target: { plotId: number, pad: number }? = nil
local grabStartedAt: number? = nil -- when this client first saw the current hold, for the bar
local bar: Frame? = nil
local fill: Frame? = nil
local carryLabel: TextLabel? = nil

-- The closest stealable pad within reach: another player's display pad with a Glowling.
local function nearestPad(position: Vector3): (number?, number?)
	local me = Players.LocalPlayer.UserId
	local bestDistance = economy.steal.grabRange - MARGIN
	local bestPlot: number?, bestPad: number? = nil, nil
	for _, model in CollectionService:GetTagged("Plot") do
		local plotId = model:GetAttribute("PlotId")
		local view = if type(plotId) == "number" then PlotController.get(plotId) else nil
		local slots = model:FindFirstChild("Slots")
		if view == nil or view.owner == 0 or view.owner == me or slots == nil then
			continue
		end
		for _, pad in slots:GetChildren() do
			local n = pad:GetAttribute("Slot")
			if pad:IsA("BasePart") and type(n) == "number" and n > view.vault and view.pads[tostring(n)] ~= nil then
				local offset = pad.Position - position
				local distance = Steal.reach(economy, offset.X, offset.Y, offset.Z)
				if distance <= bestDistance then
					bestDistance, bestPlot, bestPad = distance, plotId :: number, n
				end
			end
		end
	end
	return bestPlot, bestPad
end

local function updateContext(character: Model?, root: BasePart?)
	local label: string? = nil
	target = nil
	local state = CycleFXController.state()
	if character ~= nil and root ~= nil then
		if character:GetAttribute("GrabUntil") ~= nil then
			label = GRAB -- keep the button while holding, so letting go still reaches us
		elseif
			state ~= nil
			and state.grabsAllowed
			and character:GetAttribute("CarryFrom") == nil
			and PlotController.mine() ~= nil
		then
			local plotId, pad = nearestPad(root.Position)
			if plotId ~= nil and pad ~= nil then
				target = { plotId = plotId, pad = pad }
				label = GRAB
			end
		end
	end
	if label ~= nil then
		InputController.setContext(label)
	elseif InputController.context() == GRAB then
		InputController.setContext(nil) -- leave other controllers' labels alone
	end
end

local function updateMarks()
	local me = Players.LocalPlayer.UserId
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character == nil then
			continue
		end
		local from = character:GetAttribute("CarryFrom")
		local mark = character:FindFirstChild("StealMark")
		if from == nil then
			if mark ~= nil then
				mark:Destroy()
			end
			continue
		end
		if mark == nil or not mark:IsA("Highlight") then
			local highlight = Instance.new("Highlight")
			highlight.Name = "StealMark"
			highlight.FillColor = MARK_COLOR
			highlight.OutlineColor = MARK_COLOR
			highlight.FillTransparency = 0.6
			highlight.Parent = character
			mark = highlight
		end
		local highlight = mark :: Highlight
		highlight.DepthMode = if from == me
			then Enum.HighlightDepthMode.AlwaysOnTop
			else Enum.HighlightDepthMode.Occluded
	end
end

local function updateBars(character: Model?)
	local untilTime = if character then character:GetAttribute("GrabUntil") else nil
	local now = workspace:GetServerTimeNow()
	local holdBar, holdFill = bar, fill
	if holdBar ~= nil and holdFill ~= nil then
		if type(untilTime) == "number" then
			local started = grabStartedAt or now
			grabStartedAt = started
			local total = math.max(untilTime - started, 0.01)
			holdFill.Size = UDim2.fromScale(math.clamp((now - started) / total, 0, 1), 1)
			holdBar.Visible = true
		else
			grabStartedAt = nil
			holdBar.Visible = false
		end
	end
	local label = carryLabel
	if label ~= nil then
		label.Visible = character ~= nil and character:GetAttribute("CarryFrom") ~= nil
	end
end

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Steal"
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local holdBar = Instance.new("Frame")
	holdBar.Name = "HoldBar"
	holdBar.AnchorPoint = Vector2.new(0.5, 1)
	holdBar.Position = UDim2.new(0.5, 0, 1, -140)
	holdBar.Size = UDim2.fromOffset(220, 14)
	holdBar.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	holdBar.BorderSizePixel = 0
	holdBar.Visible = false
	holdBar.Parent = gui
	local holdFill = Instance.new("Frame")
	holdFill.Name = "Fill"
	holdFill.Size = UDim2.fromScale(0, 1)
	holdFill.BackgroundColor3 = MARK_COLOR
	holdFill.BorderSizePixel = 0
	holdFill.Parent = holdBar

	local label = Instance.new("TextLabel")
	label.Name = "Carrying"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -140)
	label.Size = UDim2.fromOffset(320, 30)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 22
	label.TextColor3 = MARK_COLOR
	label.TextStrokeTransparency = 0.4
	label.Text = "Carrying! Run back to your base"
	label.Visible = false
	label.Parent = gui

	bar, fill, carryLabel = holdBar, holdFill, label
end

function StealController.Start()
	buildGui()

	InputController.Action:Connect(function(label: string, began: boolean)
		if label ~= GRAB then
			return
		end
		local grab = target
		if began and grab ~= nil then
			NetClient.send("GrabStart", grab.plotId, grab.pad)
		elseif not began then
			NetClient.send("GrabCancel")
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		local character = Players.LocalPlayer.Character
		updateBars(character)
		elapsed += dt
		if elapsed < CHECK_SECONDS then
			return
		end
		elapsed = 0
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		updateContext(character, if root ~= nil and root:IsA("BasePart") then root else nil)
		updateMarks()
	end)
end

return StealController
