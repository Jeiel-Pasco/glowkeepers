--!strict
-- The Stalker NPC (GAME_SYSTEMS §13, TECH_SPEC §7). One per server, out only at night. The
-- brain is Shared.Stalker; this service senses the players and the fire at 10 Hz, steps the
-- brain, and moves the model every frame.
--
-- Movement is kinematic: the model is anchored, owned by the server, and moved along the
-- ground (a raycast down). With line of sight to its goal it goes straight there; otherwise it
-- follows a PathfindingService path, recomputed every stalker.repathSeconds.
--
-- A touch during a Lunge downs the target (DownedService.down). The first touch on a player in
-- their first night (stats.nightsSurvived = 0) is a near-miss instead: they're shoved toward the
-- fire. Every lunge is logged with its telegraph time (Telemetry `stalker_lunge`).
--
-- Replicates: the model `Stalker` in Workspace (streamed to everyone), with attributes `State`,
-- `Target` (the target's userId while stalking or lunging) and `LungeAt` (server time).
--
-- Placeholders for GS/AR/SD: the model (a dark body and two glowing eyes), and no hiss.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Stalker = require(Shared:WaitForChild("Stalker"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local CycleService = require(script.Parent:WaitForChild("CycleService"))
local DownedService = require(script.Parent:WaitForChild("DownedService"))
local CampfireService = require(script.Parent:WaitForChild("CampfireService"))

local TICK_SECONDS = 0.1
local HIP = 3 -- body centre above the ground
local WAYPOINT_REACHED = 1.5
local WANDER_REACHED = 4
local WANDER_NEAR = 80 -- prowl to markers this close, so it doesn't cross the clearing
local RETREAT_STUDS = 40
local FIRE_MARGIN = 10

type Living = { player: Player, root: BasePart, point: Stalker.Point }

local StalkerService = {}

local model: Model? = nil
local body: BasePart? = nil
local brain: Stalker.Brain = { state = "Dormant", since = 0 }
local night = false
local markers: { Vector3 } = {}
local steer: Vector3? = nil -- where it's heading this tick
local speed = 0
local wanderGoal: Vector3? = nil
local retreatGoal: Vector3? = nil
local stalkStarted = 0
local nearMissUsed: { [number]: boolean } = {} -- userId → had their near-miss tonight

local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 6, AgentCanJump = false })
local waypoints: { Vector3 } = {}
local waypointIndex = 1
local computing = false
local lastPath = -math.huge
local pathGoal: Vector3? = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Stalker.Point
	return { x = v.X, z = v.Z }
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local function fireInfo(): (Stalker.Fire?, Vector3?)
	local campfire = CollectionService:GetTagged("Campfire")[1]
	local pit = if campfire ~= nil and campfire:IsA("Model") then campfire.PrimaryPart else nil
	if campfire == nil or pit == nil then
		return nil, nil
	end
	local radius = campfire:GetAttribute("LightRadius")
	local fire = {
		x = pit.Position.X,
		z = pit.Position.Z,
		radius = if type(radius) == "number" then radius else 30,
		lit = not CampfireService.isLost(),
	}
	return fire, pit.Position
end

local function rayParams(): RaycastParams
	local exclude: { Instance } = {}
	if model ~= nil then
		table.insert(exclude, model)
	end
	for _, player in Players:GetPlayers() do
		if player.Character ~= nil then
			table.insert(exclude, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	return params
end

local function groundAt(position: Vector3, params: RaycastParams): number
	local hit = workspace:Raycast(position + Vector3.new(0, 20, 0), Vector3.new(0, -80, 0), params)
	return if hit ~= nil then hit.Position.Y else position.Y - HIP
end

local function build(): Model
	local stalker = Instance.new("Model")
	stalker.Name = "Stalker"
	local part = Instance.new("Part")
	part.Name = "Body"
	part.Size = Vector3.new(2.5, 6, 1.5)
	part.Color = Color3.fromRGB(18, 18, 26)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Parent = stalker
	for _, x in { -0.45, 0.45 } do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.one * 0.35
		eye.CFrame = part.CFrame * CFrame.new(x, 2.2, -0.8)
		eye.Color = Color3.fromRGB(255, 236, 170)
		eye.Material = Enum.Material.Neon
		eye.Anchored = true
		eye.CanCollide = false
		eye.CanTouch = false
		eye.CanQuery = false
		eye.Parent = stalker
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 150)
	light.Range = 8
	light.Brightness = 1.5
	light.Parent = part
	stalker.PrimaryPart = part
	stalker.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	body = part
	return stalker
end

local function position(): Vector3
	return if body ~= nil then body.Position else Vector3.zero
end

local function setAttributes(target: Player?, lungeAt: number?)
	local stalker = model
	if stalker == nil then
		return
	end
	stalker:SetAttribute("State", brain.state)
	stalker:SetAttribute("Target", if target ~= nil then target.UserId else nil)
	stalker:SetAttribute("LungeAt", lungeAt)
end

local function requestPath(goal: Vector3)
	if computing then
		return
	end
	computing = true
	lastPath = os.clock()
	pathGoal = goal
	local from = position() - Vector3.new(0, HIP, 0)
	task.spawn(function()
		local ok = pcall(function()
			path:ComputeAsync(from, goal)
		end)
		computing = false
		table.clear(waypoints)
		waypointIndex = 1
		if ok and path.Status == Enum.PathStatus.Success then
			for i, waypoint in path:GetWaypoints() do
				if i > 1 then
					table.insert(waypoints, waypoint.Position)
				end
			end
		end
	end)
end

-- Picks where to head this tick: straight at the goal with line of sight, else along a path.
local function steerTo(goal: Vector3, params: RaycastParams)
	local from = position()
	local to = goal + Vector3.new(0, HIP, 0)
	local hit = workspace:Raycast(from, to - from, params)
	if hit == nil then
		table.clear(waypoints)
		steer = goal
		return
	end
	local stale = pathGoal == nil or (pathGoal - goal).Magnitude > 4
	if stale or os.clock() - lastPath >= economy.stalker.repathSeconds then
		requestPath(goal)
	end
	local waypoint = waypoints[waypointIndex]
	while waypoint ~= nil and Stalker.distance(flat(waypoint), flat(from)) < WAYPOINT_REACHED do
		waypointIndex += 1
		waypoint = waypoints[waypointIndex]
	end
	steer = waypoint or goal
end

local function pickWander(fire: Stalker.Fire?): Vector3?
	local from = position()
	local near, any = {}, {}
	for _, marker in markers do
		local outside = fire == nil or Stalker.distance(flat(marker), fire) > fire.radius + FIRE_MARGIN
		if outside and Stalker.distance(flat(marker), flat(from)) > WANDER_REACHED then
			table.insert(any, marker)
			if (marker - from).Magnitude <= WANDER_NEAR then
				table.insert(near, marker)
			end
		end
	end
	local pool = if #near > 0 then near else any
	return if #pool > 0 then pool[math.random(#pool)] else nil
end

-- Somewhere RETREAT_STUDS away from the threat, on the far side.
local function retreatFrom(threat: Vector3): Vector3
	local from = position()
	local away = Vector3.new(from.X - threat.X, 0, from.Z - threat.Z)
	if away.Magnitude < 0.1 then
		away = Vector3.new(1, 0, 0)
	end
	return from + away.Unit * RETREAT_STUDS
end

local function shoveTowardFire(player: Player, firePosition: Vector3?)
	local character = player.Character
	local root = rootOf(player)
	if character == nil or root == nil or firePosition == nil then
		return
	end
	local toward = Vector3.new(firePosition.X - root.Position.X, 0, firePosition.Z - root.Position.Z)
	if toward.Magnitude > 0.1 then
		character:PivotTo(character:GetPivot() + toward.Unit * economy.stalker.nearMissShove)
	end
	NetServer.send(player, "Toast", "Too close! Get back to the fire", "bad")
end

local function onTouch(target: Player, firePosition: Vector3?)
	local data = DataService.get(target)
	local firstNight = data ~= nil and data.stats.nightsSurvived == 0
	if firstNight and not nearMissUsed[target.UserId] then
		nearMissUsed[target.UserId] = true
		shoveTowardFire(target, firePosition)
		Telemetry.custom(target, "stalker_touch", nil, { "near_miss" })
		return
	end
	DownedService.down(target)
	Telemetry.custom(target, "stalker_touch", nil, { "down" })
end

local function tick()
	if not night or model == nil then
		return
	end
	local t = now()
	local params = rayParams()
	local fire, firePosition = fireInfo()
	local at = position()
	local living: { Living } = {}
	local points: { Stalker.Point } = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root ~= nil and DownedService.isLiving(player) then
			table.insert(living, { player = player, root = root, point = flat(root.Position) })
			table.insert(points, flat(root.Position))
		end
	end

	local target: Living? = nil
	local others: { Stalker.Point } = {}
	for _, entry in living do
		if brain.target ~= nil and entry.player.UserId == brain.target then
			target = entry
		else
			table.insert(others, entry.point)
		end
	end
	local candidateIndex = if brain.state == "Prowl" then Stalker.pickTarget(economy, flat(at), points, fire) else nil
	local touched = false
	if target ~= nil then
		local offset = target.root.Position - at
		touched = Stalker.distance(target.point, flat(at)) <= economy.stalker.touchRange and math.abs(offset.Y) < 5
	end

	local cycle = CycleService.get()
	local sense: Stalker.Sense = {
		now = t,
		nightElapsed = cycle.t - economy.cycle.daySeconds,
		repelled = brain.state ~= "Dormant" and Stalker.repelled(economy, flat(at), points, fire),
		candidate = if candidateIndex ~= nil then living[candidateIndex].player.UserId else nil,
		targetLone = target ~= nil and Stalker.isLone(economy, target.point, others, fire),
		touched = touched,
	}
	local nextBrain, event = Stalker.step(economy, brain, sense)
	brain = nextBrain

	if event == "stalk" then
		stalkStarted = t
		local entry = living[candidateIndex :: number]
		target = entry
		setAttributes(entry.player, t + economy.stalker.stalkSeconds)
	elseif event == "lunge" and target ~= nil then
		Telemetry.custom(target.player, "stalker_lunge", t - stalkStarted)
		setAttributes(target.player, t)
	elseif event == "down" or event == "miss" or event == "repelled" then
		if event == "down" and target ~= nil then
			onTouch(target.player, firePosition)
		end
		local nearest: Vector3? = nil
		for _, entry in living do
			if nearest == nil or (entry.root.Position - at).Magnitude < (nearest - at).Magnitude then
				nearest = entry.root.Position
			end
		end
		local threat = if fire ~= nil
				and Stalker.inFire(fire, flat(at))
				and firePosition ~= nil
			then firePosition
			elseif target ~= nil then target.root.Position
			else nearest or firePosition or at + Vector3.new(0, 0, 1)
		retreatGoal = retreatFrom(threat)
		setAttributes(nil, nil)
	elseif event ~= nil then
		wanderGoal = nil
		setAttributes(nil, nil)
	end

	-- Where to go, and how fast.
	local state = brain.state
	local targetSpeed = if target ~= nil
		then Vector3.new(target.root.AssemblyLinearVelocity.X, 0, target.root.AssemblyLinearVelocity.Z).Magnitude
		else 0
	speed = Stalker.speed(economy, state, targetSpeed)
	if state == "Dormant" then
		steer = nil
	elseif state == "Prowl" then
		if wanderGoal == nil or Stalker.distance(flat(wanderGoal), flat(at)) < WANDER_REACHED then
			wanderGoal = pickWander(fire)
		end
		if wanderGoal ~= nil then
			steerTo(wanderGoal, params)
		end
	elseif (state == "Stalk" or state == "Lunge") and target ~= nil then
		local goal = target.root.Position - Vector3.new(0, HIP, 0)
		if state == "Stalk" and Stalker.distance(target.point, flat(at)) <= economy.stalker.stalkDistance then
			steer = nil -- close enough: lurk
		else
			steerTo(goal, params)
		end
	elseif state == "Retreat" and retreatGoal ~= nil then
		steer = retreatGoal
	end
end

-- Moves the model toward `steer` along the ground.
local function move(dt: number)
	local stalker = model
	local target = steer
	if not night or stalker == nil or target == nil or speed <= 0 then
		return
	end
	local from = position()
	local delta = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
	local distance = delta.Magnitude
	if distance < 0.05 then
		return
	end
	local step = math.min(speed * dt, distance)
	local nextFlat = from + delta.Unit * step
	local y = groundAt(nextFlat, rayParams()) + HIP
	local nextPosition = Vector3.new(nextFlat.X, y, nextFlat.Z)
	stalker:PivotTo(CFrame.lookAt(nextPosition, nextPosition + delta.Unit))
end

local function spawnPoint(firePosition: Vector3?): Vector3
	local best, bestDistance = Vector3.new(0, HIP, 150), -1
	for _, marker in markers do
		local d = if firePosition ~= nil then (marker - firePosition).Magnitude else 0
		if d > bestDistance then
			best, bestDistance = marker, d
		end
	end
	return best
end

local function startNight()
	night = true
	table.clear(nearMissUsed)
	brain = { state = "Dormant", since = now() }
	wanderGoal, retreatGoal, steer = nil, nil, nil
	table.clear(waypoints)
	local stalker = model or build()
	model = stalker
	local _, firePosition = fireInfo()
	local at = spawnPoint(firePosition)
	local y = groundAt(at, rayParams()) + HIP
	stalker:PivotTo(CFrame.new(at.X, y, at.Z))
	setAttributes(nil, nil)
	stalker.Parent = workspace
end

local function endNight()
	night = false
	steer = nil
	brain = { state = "Dormant", since = now() }
	if model ~= nil then
		setAttributes(nil, nil)
		model.Parent = nil
	end
end

function StalkerService.Init()
	for _, part in CollectionService:GetTagged("WildSpawn") do
		if part:IsA("BasePart") then
			table.insert(markers, part.Position)
		end
	end
	if #markers == 0 then
		warn("[StalkerService] No WildSpawn markers to prowl between (TECH_SPEC §6a).")
	end
	CycleService.PhaseChanged:Connect(function(phase: string)
		if phase == "Night" and not night then
			startNight()
		elseif phase ~= "Night" and night then
			endNight()
		end
	end)
end

function StalkerService.Start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		move(dt)
		elapsed += dt
		if elapsed >= TICK_SECONDS then
			elapsed = 0
			tick()
		end
	end)
end

return StalkerService
