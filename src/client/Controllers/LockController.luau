--!strict
-- Base Lock on the client (GAME_SYSTEMS §11). A Lock button under the cycle ring (also L on a
-- keyboard, Y on a gamepad) sends Lock; the server checks every rule again and toasts a
-- refusal. The button reads the plot view's `lock` (when the lock ends), the Player attribute
-- `LockReadyAt` (when the recharge ends) and the profile's `lockCharges`. It hides at night and
-- before the player has a plot.
--
-- Every locked plot gets see-through walls around its zone. Other players' walls are solid for
-- this player, unless they were inside when the lock started: then they can walk out, and the
-- walls close behind them. The server pushes out anyone who gets in anyway (LockService).
--
-- Placeholders for UI: the button and the walls (artists replace them in Phase 3).

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local PlotController = require(script.Parent:WaitForChild("PlotController"))
local StateController = require(script.Parent:WaitForChild("StateController"))
local CycleFXController = require(script.Parent:WaitForChild("CycleFXController"))

local LOCK_ACTION = "GlowkeepersLock"
local CHECK_SECONDS = 0.2
local WALL_HEIGHT = 10
local WALL_THICKNESS = 1
local WALL_COLOR = Color3.fromRGB(120, 200, 255)
local READY_COLOR = Color3.fromRGB(70, 140, 220)
local WAIT_COLOR = Color3.fromRGB(60, 60, 70)

type Walls = { model: Model, zone: BasePart, passThrough: boolean, untilTime: number }

local LockController = {}

local button: TextButton? = nil
local folder: Folder? = nil
local walls: { [number]: Walls } = {}

local function inside(zone: BasePart, position: Vector3): boolean
	local offset = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z
end

-- Four walls on the zone's sides, standing on its floor.
local function buildWalls(plotId: number, zone: BasePart): Model
	local model = Instance.new("Model")
	model.Name = `Lock{plotId}`
	local half = zone.Size / 2
	local base = zone.CFrame * CFrame.new(0, -half.Y + WALL_HEIGHT / 2, 0)
	local sides = {
		{ CFrame.new(half.X, 0, 0), Vector3.new(WALL_THICKNESS, WALL_HEIGHT, zone.Size.Z) },
		{ CFrame.new(-half.X, 0, 0), Vector3.new(WALL_THICKNESS, WALL_HEIGHT, zone.Size.Z) },
		{ CFrame.new(0, 0, half.Z), Vector3.new(zone.Size.X, WALL_HEIGHT, WALL_THICKNESS) },
		{ CFrame.new(0, 0, -half.Z), Vector3.new(zone.Size.X, WALL_HEIGHT, WALL_THICKNESS) },
	}
	for i, side in sides do
		local wall = Instance.new("Part")
		wall.Name = `Wall{i}`
		wall.CFrame = base * side[1]
		wall.Size = side[2]
		wall.Color = WALL_COLOR
		wall.Material = Enum.Material.ForceField
		wall.Transparency = 0.4
		wall.Anchored = true
		wall.CanTouch = false
		wall.CanQuery = false
		wall.CastShadow = false
		wall.Parent = model
	end
	model.Parent = folder
	return model
end

local function setSolid(entry: Walls, solid: boolean)
	for _, wall in entry.model:GetChildren() do
		if wall:IsA("BasePart") then
			wall.CanCollide = solid
		end
	end
end

local function clearWalls(plotId: number)
	local entry = walls[plotId]
	if entry ~= nil then
		entry.model:Destroy()
		walls[plotId] = nil
	end
end

local function updateWalls(now: number)
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local position = if root ~= nil and root:IsA("BasePart") then root.Position else nil
	local mine = PlotController.mine()
	for plotId, entry in walls do
		local view = PlotController.get(plotId)
		if view == nil or view.lock <= now or view.lock ~= entry.untilTime or entry.zone.Parent == nil then
			clearWalls(plotId) -- ended, or a new lock: rebuilt below
		end
	end
	for _, model in CollectionService:GetTagged("Plot") do -- the plots streamed in
		local plotId = model:GetAttribute("PlotId")
		local view = if type(plotId) == "number" then PlotController.get(plotId) else nil
		if type(plotId) == "number" and view ~= nil and view.lock > now then
			local entry = walls[plotId]
			if entry == nil then
				local zone = model:FindFirstChild("Zone")
				if zone ~= nil and zone:IsA("BasePart") then
					local wasInside = position ~= nil and inside(zone, position)
					entry = {
						model = buildWalls(plotId, zone),
						zone = zone,
						passThrough = wasInside,
						untilTime = view.lock,
					}
					walls[plotId] = entry
				end
			end
			if entry ~= nil then
				if entry.passThrough and (position == nil or not inside(entry.zone, position)) then
					entry.passThrough = false -- out now: it closes behind them
				end
				setSolid(entry, plotId ~= mine and not entry.passThrough)
			end
		end
	end
end

local function updateButton(now: number)
	local lockButton = button
	if lockButton == nil then
		return
	end
	local state = CycleFXController.state()
	local mine = PlotController.mine()
	local view = if mine ~= nil then PlotController.get(mine) else nil
	if state == nil or state.phase == "Night" or view == nil then
		lockButton.Visible = false
		return
	end
	lockButton.Visible = true
	local readyAt = Players.LocalPlayer:GetAttribute("LockReadyAt")
	local data = StateController.get()
	local charges = if data ~= nil and type(data.lockCharges) == "number" then data.lockCharges else 0
	local ready = true
	if view.lock > now then
		lockButton.Text = `Locked · {math.ceil(view.lock - now)} s`
		ready = false
	elseif type(readyAt) == "number" and readyAt > now then
		if charges > 0 then
			lockButton.Text = `Lock (charge, {charges} left)`
		else
			lockButton.Text = `Lock in {math.ceil(readyAt - now)} s`
			ready = false
		end
	else
		lockButton.Text = "Lock base"
	end
	lockButton.BackgroundColor3 = if ready then READY_COLOR else WAIT_COLOR
end

local function buildButton(): TextButton
	local gui = Instance.new("ScreenGui")
	gui.Name = "LockGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local lockButton = Instance.new("TextButton")
	lockButton.Name = "LockButton"
	lockButton.AnchorPoint = Vector2.new(1, 0)
	lockButton.Position = UDim2.new(1, -12, 0, 112) -- under the cycle ring
	lockButton.Size = UDim2.fromOffset(170, 40)
	lockButton.BackgroundColor3 = READY_COLOR
	lockButton.BackgroundTransparency = 0.15
	lockButton.Font = Enum.Font.GothamBold
	lockButton.TextSize = 18
	lockButton.TextColor3 = Color3.new(1, 1, 1)
	lockButton.Text = "Lock base"
	lockButton.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = lockButton
	lockButton.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return lockButton
end

function LockController.Init() end

function LockController.Start()
	local wallFolder = Instance.new("Folder")
	wallFolder.Name = "LockWalls"
	wallFolder.Parent = workspace
	folder = wallFolder

	local lockButton = buildButton()
	button = lockButton
	lockButton.Activated:Connect(function()
		NetClient.send("Lock")
	end)
	ContextActionService:BindAction(LOCK_ACTION, function(_: string, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin and lockButton.Visible then
			NetClient.send("Lock")
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.L, Enum.KeyCode.ButtonY)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= CHECK_SECONDS then
			elapsed = 0
			local now = workspace:GetServerTimeNow()
			updateButton(now)
			updateWalls(now)
		end
	end)
end

return LockController
