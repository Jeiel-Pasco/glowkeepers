--!strict
-- Enemies (GDD "Enemies and bosses"): spawns them on the east trail and in Emberfall Ridge,
-- runs their AI, and hands out XP, loot and quest credit when they die.
--
-- AI per enemy, ticked every 0.15 s: idle near home → chase the nearest player in aggro range
-- → wind up (telegraphed on clients by Fx "windup") → attack → cool down. Past the leash it
-- walks home and heals. Nobody follows you into the camp clearing.
--
-- Raiders hunt players carrying loot, steal a share per hit, then flee; killing one returns it
-- all plus a bonus. The tutorial raider is spawned for one player on that quest step.
-- The Cinder Golem's health grows with each new attacker; drops need 10% of its health dealt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Enemies = require(Shared:WaitForChild("Enemies")) :: any
local Loot = require(Shared:WaitForChild("Loot")) :: any
local Quests = require(Shared:WaitForChild("Quests")) :: any
local EnemyLooks = require(Server:WaitForChild("World"):WaitForChild("EnemyLooks"))
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local CampService = require(script.Parent:WaitForChild("CampService"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local LootService = require(script.Parent:WaitForChild("LootService"))
local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))
local WorldService = require(script.Parent:WaitForChild("WorldService"))

local EnemyService = {}

local TICK = 0.15
local RESPAWN =
	{ ember_imp = 9, cinder_caster = 12, ashling = 25, cinder_golem = 90, raider = 40 } :: { [string]: number }
local OVERLEVEL_XP = 8 -- this many levels above a normal enemy: a quarter of the XP
local FLEE_SECONDS = 9
local RAIDER_STASH_SECONDS = 60 -- stolen loot is gone this long after the raider escapes

type Spawn = { kind: string, pos: Vector3, level: number, wander: number? }

-- The spawn table: the east trail, then the ridge from mouth to caldera.
local SPAWNS: { Spawn } = {
	-- East trail (inside the ring): tutorial imps and the Ashling.
	{ kind = "ember_imp", pos = Vector3.new(172, 0, 22), level = 1 },
	{ kind = "ember_imp", pos = Vector3.new(186, 0, -20), level = 1 },
	{ kind = "ember_imp", pos = Vector3.new(204, 0, 14), level = 2 },
	{ kind = "ember_imp", pos = Vector3.new(214, 0, -26), level = 2 },
	{ kind = "ashling", pos = Vector3.new(238, 0, 0), level = 3, wander = 6 },
	-- Ridge mouth.
	{ kind = "ember_imp", pos = Vector3.new(290, 0, 24), level = 3 },
	{ kind = "ember_imp", pos = Vector3.new(298, 0, -22), level = 3 },
	{ kind = "ember_imp", pos = Vector3.new(318, 0, 40), level = 4 },
	{ kind = "ember_imp", pos = Vector3.new(332, 0, -6), level = 4 },
	{ kind = "ember_imp", pos = Vector3.new(350, 0, 52), level = 5 },
	{ kind = "cinder_caster", pos = Vector3.new(360, 0, 6), level = 5 },
	-- Ash fields.
	{ kind = "cinder_caster", pos = Vector3.new(386, 0, 50), level = 6 },
	{ kind = "cinder_caster", pos = Vector3.new(404, 0, -30), level = 6 },
	{ kind = "ember_imp", pos = Vector3.new(396, 0, 14), level = 6 },
	{ kind = "ember_imp", pos = Vector3.new(420, 0, 30), level = 7 },
	{ kind = "cinder_caster", pos = Vector3.new(440, 0, -48), level = 7 },
	{ kind = "ember_imp", pos = Vector3.new(452, 0, 4), level = 8 },
	{ kind = "cinder_caster", pos = Vector3.new(470, 0, 30), level = 8 },
	-- Cinder steps.
	{ kind = "ember_imp", pos = Vector3.new(500, 0, -36), level = 9 },
	{ kind = "cinder_caster", pos = Vector3.new(512, 0, 20), level = 9 },
	{ kind = "ember_imp", pos = Vector3.new(526, 0, -10), level = 10 },
	{ kind = "cinder_caster", pos = Vector3.new(540, 0, -40), level = 10 },
	{ kind = "ember_imp", pos = Vector3.new(546, 0, 26), level = 11 },
	-- The caldera.
	{ kind = "cinder_golem", pos = WorldService.CALDERA, level = 12, wander = 0 },
	-- Raiders roam the wilds between camp and ridge.
	{ kind = "raider", pos = Vector3.new(196, 0, 70), level = 2, wander = 40 },
	{ kind = "raider", pos = Vector3.new(330, 0, -60), level = 5, wander = 40 },
}

type Enemy = {
	info: any,
	spawn: Spawn?,
	home: Vector3,
	state: string, -- idle | chase | windup | cooldown | home | flee
	target: Player?,
	readyAt: number,
	stateUntil: number,
	wanderAt: number,
	attackers: number,
	bossStep: number,
	stolen: { [Player]: any }, -- raiders
	owner: Player?, -- the tutorial raider's one target
	fleeFrom: Vector3?,
}

local live: { [Model]: Enemy } = {}
local tutorialRaiders: { [Player]: Model } = {}

local function groundAt(pos: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local ray = workspace:Raycast(Vector3.new(pos.X, 120, pos.Z), Vector3.new(0, -240, 0), params)
	return if ray then ray.Position else pos
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function spawnEnemy(kindId: string, level: number, pos: Vector3, spawn: Spawn?): Enemy
	local kind = Enemies.kinds[kindId]
	local model = EnemyLooks.build(kindId)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model.PrimaryPart :: BasePart
	local ground = groundAt(pos)
	model:PivotTo(
		CFrame.new(ground + Vector3.new(0, humanoid.HipHeight + 1, 0)) * CFrame.Angles(0, math.random() * 6.28, 0)
	)
	humanoid.MaxHealth = Enemies.maxHp(kind, level)
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = kind.speed
	model:SetAttribute("Kind", kindId)
	model:SetAttribute("Name", kind.name)
	model:SetAttribute("Level", level)
	model:SetAttribute("Type", kind.type)
	model:SetAttribute("Boss", kind.boss == true or kindId == "ashling")
	local enemy: Enemy = {
		info = {
			kind = kind,
			level = level,
			type = kind.type,
			model = model,
			root = root,
			humanoid = humanoid,
			dealt = {},
			dead = false,
		},
		spawn = spawn,
		home = ground,
		state = "idle",
		target = nil,
		readyAt = 0,
		stateUntil = 0,
		wanderAt = 0,
		attackers = 1,
		bossStep = 0,
		stolen = {},
	}
	if kind.boss then
		enemy.info.onHurt = function()
			local count = 0
			for _ in enemy.info.dealt do
				count += 1
			end
			if count > enemy.attackers then
				local ratio = humanoid.Health / humanoid.MaxHealth
				enemy.attackers = count
				humanoid.MaxHealth = Enemies.bossHp(kind, level, count)
				humanoid.Health = humanoid.MaxHealth * ratio
			end
		end
	end
	CombatService.addEnemy(enemy.info)
	root:SetNetworkOwner(nil)
	live[model] = enemy
	return enemy
end

-- Targeting ---------------------------------------------------------------------------------

local function pickTarget(enemy: Enemy): Player?
	local kind = enemy.info.kind
	local pos = enemy.info.root.Position
	if enemy.owner then
		local root = rootOf(enemy.owner)
		return if root and not CampService.isSafe(root.Position) then enemy.owner else nil
	end
	local best, bestD = nil, kind.aggro
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and not CampService.isSafe(root.Position) then
			local d = (root.Position - pos).Magnitude
			if
				kind.raider
				and LootService.carriedValue(player) < Loot.RAIDER_MIN_CARRY
				and enemy.info.dealt[player] == nil
			then
				continue -- raiders ignore empty pockets unless you hit them
			end
			if d < bestD then
				best, bestD = player, d
			end
		end
	end
	return best
end

-- Attacks -----------------------------------------------------------------------------------

local function melee(enemy: Enemy, target: Player)
	local info = enemy.info
	local root = rootOf(target)
	if root == nil then
		return
	end
	NetServer.sendAll("Fx", "slash", info.model, info.kind.reach)
	if (root.Position - info.root.Position).Magnitude <= info.kind.reach + info.kind.size + 1.5 then
		local dealt = CombatService.hurtPlayer(target, Enemies.damage(info.kind, info.level), info.type, info.model)
		if info.kind.raider and dealt > 0 then
			local taken = LootService.steal(target, Loot.RAIDER_SHARE)
			if not Loot.isEmpty(taken) then
				local mine = enemy.stolen[target] or Loot.empty()
				Loot.add(mine, taken)
				enemy.stolen[target] = mine
				info.model:SetAttribute("Loaded", true)
				enemy.state = "flee"
				enemy.fleeFrom = root.Position
				enemy.stateUntil = os.clock() + FLEE_SECONDS
			end
		end
	end
end

local function bolt(enemy: Enemy, target: Player, spread: number?)
	local info = enemy.info
	local root = rootOf(target)
	if root == nil then
		return
	end
	local origin = info.root.Position + Vector3.new(0, 1.5, 0)
	local dir = (root.Position - origin).Unit
	if spread then
		dir = (CFrame.fromAxisAngle(Vector3.yAxis, spread) * dir).Unit
	end
	CombatService.fire({
		team = "enemy",
		source = info.model,
		pos = origin + dir * (info.kind.size + 1),
		dir = dir,
		speed = if info.kind.boss then 55 else 62,
		range = info.kind.reach + 20,
		travelled = 0,
		radius = if info.kind.boss then 2.2 else 1.3,
		damage = Enemies.damage(info.kind, info.level) * (if info.kind.boss then 0.6 else 1),
		type = info.type,
		burn = if info.kind.boss then { dps = 3, duration = 2 } else nil,
	})
end

-- The Golem rotates: slam (ring round it), volley (5 fireballs), eruptions (circles under players).
local function bossAttack(enemy: Enemy, target: Player)
	local info = enemy.info
	enemy.bossStep += 1
	local step = enemy.bossStep % 3
	local pos = info.root.Position
	local damage = Enemies.damage(info.kind, info.level)
	if step == 1 then
		local radius = 22
		local ground = groundAt(pos)
		NetServer.sendAll("Fx", "ring", ground.X, ground.Y, ground.Z, radius, 1.1)
		task.delay(1.1, function()
			if info.dead then
				return
			end
			NetServer.sendAll("Fx", "blast", ground.X, ground.Y, ground.Z, radius, "Fire")
			for _, player in Players:GetPlayers() do
				local root = rootOf(player)
				if root and (root.Position - ground).Magnitude <= radius then
					CombatService.hurtPlayer(player, damage * 1.3, info.type, info.model)
				end
			end
		end)
	elseif step == 2 then
		for i = -2, 2 do
			bolt(enemy, target, i * 0.18)
		end
	else
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if root and (root.Position - pos).Magnitude < 90 then
				local spot = groundAt(root.Position)
				NetServer.sendAll("Fx", "ring", spot.X, spot.Y, spot.Z, 9, 1.3)
				task.delay(1.3, function()
					if info.dead then
						return
					end
					NetServer.sendAll("Fx", "blast", spot.X, spot.Y, spot.Z, 9, "Fire")
					local now = rootOf(player)
					if now and (now.Position - spot).Magnitude <= 9 then
						CombatService.hurtPlayer(player, damage, info.type, info.model)
						CombatService.burnPlayer(player, 4, 3)
					end
				end)
			end
		end
	end
end

-- The AI tick -------------------------------------------------------------------------------

local function think(enemy: Enemy, now: number)
	local info = enemy.info
	local kind = info.kind
	local humanoid = info.humanoid
	local pos = info.root.Position
	local fromHome = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(enemy.home.X, 0, enemy.home.Z)).Magnitude

	if enemy.state == "flee" then
		if now > enemy.stateUntil then
			enemy.state = "home"
		else
			local away = pos - (enemy.fleeFrom or enemy.home)
			away = Vector3.new(away.X, 0, away.Z)
			away = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
			humanoid.WalkSpeed = kind.speed + 1
			humanoid:MoveTo(pos + away * 20)
		end
		return
	end

	if enemy.state == "home" then
		humanoid.WalkSpeed = kind.speed
		humanoid:MoveTo(enemy.home)
		if fromHome < 6 then
			enemy.state = "idle"
			humanoid.Health = humanoid.MaxHealth
			table.clear(info.dealt)
			enemy.attackers = 1
			if kind.boss then
				humanoid.MaxHealth = Enemies.maxHp(kind, info.level)
				humanoid.Health = humanoid.MaxHealth
			end
			if next(enemy.stolen) ~= nil then
				task.delay(RAIDER_STASH_SECONDS, function()
					table.clear(enemy.stolen)
					info.model:SetAttribute("Loaded", nil)
				end)
			end
		end
		return
	end

	if enemy.state == "windup" then
		if now >= enemy.stateUntil then
			local target = enemy.target
			enemy.state = "cooldown"
			enemy.stateUntil = now + 0.35
			enemy.readyAt = now + kind.cooldown
			if target then
				if kind.attack == "melee" then
					melee(enemy, target)
				elseif kind.attack == "bolt" then
					bolt(enemy, target)
				else
					bossAttack(enemy, target)
				end
			end
		end
		return
	end
	if enemy.state == "cooldown" and now < enemy.stateUntil then
		return
	end

	if fromHome > kind.leash then
		enemy.state = "home"
		enemy.target = nil
		return
	end

	local target = pickTarget(enemy)
	enemy.target = target
	if target == nil then
		enemy.state = "idle"
		if now > enemy.wanderAt then
			enemy.wanderAt = now + math.random(3, 7)
			local wander = if enemy.spawn and enemy.spawn.wander then enemy.spawn.wander else 12
			if wander > 0 then
				local angle = math.random() * math.pi * 2
				humanoid.WalkSpeed = kind.speed * 0.45
				humanoid:MoveTo(enemy.home + Vector3.new(math.cos(angle), 0, math.sin(angle)) * math.random() * wander)
			end
		end
		return
	end

	local troot = rootOf(target) :: BasePart
	local delta = troot.Position - pos
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local dist = flat.Magnitude
	humanoid.WalkSpeed = kind.speed
	enemy.state = "chase"

	local inReach
	if kind.attack == "melee" then
		inReach = dist <= kind.reach + kind.size
		if not inReach then
			humanoid:MoveTo(troot.Position - flat.Unit * (kind.reach * 0.6))
		end
	elseif kind.attack == "bolt" then
		inReach = dist <= kind.reach
		-- Casters keep their distance.
		if dist < kind.reach * 0.45 then
			humanoid:MoveTo(pos - flat.Unit * 12)
		elseif not inReach then
			humanoid:MoveTo(troot.Position)
		else
			humanoid:MoveTo(pos)
		end
	else
		inReach = dist <= 60
		if dist > kind.reach + kind.size then
			humanoid:MoveTo(troot.Position)
		else
			humanoid:MoveTo(pos)
		end
	end

	if inReach and now >= enemy.readyAt then
		enemy.state = "windup"
		enemy.stateUntil = now + kind.windup
		humanoid:MoveTo(pos)
		-- Face the target while winding up.
		info.root.CFrame = CFrame.lookAt(pos, Vector3.new(troot.Position.X, pos.Y, troot.Position.Z))
		NetServer.sendAll("Fx", "windup", info.model, kind.windup, kind.attack)
	end
end

-- Death and drops -----------------------------------------------------------------------------

local function rollBag(kind: any): any
	local bag = Loot.empty()
	bag.coins = math.random(kind.coins[1], kind.coins[2])
	for _, drop in kind.ink do
		if math.random() < drop.chance then
			bag.ink[drop.type] = (bag.ink[drop.type] or 0) + drop.count
		end
	end
	if kind.frag and math.random() < kind.frag.chance then
		bag.frag[kind.frag.type] = 1
	end
	return bag
end

local function onKilled(model: Model, info: any)
	local enemy = live[model]
	if enemy == nil then
		return
	end
	live[model] = nil
	local kind = info.kind
	local pos = info.root.Position
	NetServer.sendAll("Fx", "death", pos.X, pos.Y, pos.Z, info.type, kind.size)

	for player, dealt in info.dealt do
		if player.Parent == nil then
			continue
		end
		local data = DataService.get(player)
		if data == nil then
			continue
		end
		if kind.boss and not Enemies.earnsDrop(dealt, info.humanoid.MaxHealth, data.level, info.level) then
			NetServer.send(player, "Toast", "Deal more damage to the boss to earn its drops", "warn")
			continue
		end
		local xp = Enemies.xp(kind, info.level)
		if not kind.boss and data.level - info.level >= OVERLEVEL_XP then
			xp = math.floor(xp / 4)
		end
		ProgressionService.addXp(player, xp)
		LootService.give(player, rollBag(kind))
		if kind.stars then
			data.stars += kind.stars
			DataService.changed(player, "stars")
			NetServer.send(player, "Toast", `+{kind.stars} star`, "level")
		end
		data.counts.kills += 1
		if kind.boss then
			data.counts.bosses += 1
		end
		ProgressionService.note(player, "kill", kind.id)
		if kind.raider then
			ProgressionService.note(player, "raider")
		end
	end
	-- Raiders give back what they stole, plus a bonus, to each player they robbed.
	for victim, stolen in enemy.stolen do
		if victim.Parent then
			LootService.give(victim, Loot.recovered(stolen))
		end
	end

	CombatService.removeEnemy(model)
	task.delay(1.2, function()
		model:Destroy()
	end)
	if enemy.owner then
		tutorialRaiders[enemy.owner] = nil
	elseif enemy.spawn then
		local spawn = enemy.spawn
		task.delay(RESPAWN[kind.id] or 10, function()
			spawnEnemy(spawn.kind, spawn.level, spawn.pos, spawn)
		end)
	end
end

-- The tutorial raider: appears near a player on that quest step and robs them.
local function tutorialRaider(player: Player)
	if tutorialRaiders[player] then
		return
	end
	local data = DataService.get(player)
	local root = rootOf(player)
	if data == nil or root == nil or CampService.isSafe(root.Position) then
		return
	end
	if Quests.step(data.quest.step).event ~= "raider" then
		return
	end
	local ahead = root.Position - root.CFrame.LookVector * 24
	local enemy = spawnEnemy("raider", 1, ahead, nil)
	enemy.owner = player
	enemy.home = groundAt(root.Position + Vector3.new(60, 0, 0))
	tutorialRaiders[player] = enemy.info.model
	-- Make sure there's something to steal: the Ashling's drops are in the carried bag.
	if Loot.isEmpty(data.carried) then
		LootService.give(player, { coins = 20, ink = {}, frag = {} })
	end
	NetServer.send(player, "Toast", "Look out, a raider!", "warn")
	task.delay(120, function()
		local model = tutorialRaiders[player]
		if model == enemy.info.model and not enemy.info.dead then
			tutorialRaiders[player] = nil
			live[model] = nil
			CombatService.removeEnemy(model)
			model:Destroy()
		end
	end)
end

function EnemyService.Init()
	CombatService.EnemyKilled:Connect(onKilled)
	CombatService.EnemyHurt:Connect(function(model: Model, _info: any, player: Player)
		local enemy = live[model]
		if enemy and enemy.state == "idle" then
			enemy.target = player -- being hit wakes them, even out of aggro range
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local model = tutorialRaiders[player]
		if model then
			tutorialRaiders[player] = nil
			live[model] = nil
			CombatService.removeEnemy(model)
			model:Destroy()
		end
		for _, enemy in live do
			enemy.stolen[player] = nil
			if enemy.target == player then
				enemy.target = nil
			end
		end
	end)
end

function EnemyService.Start()
	task.wait(1) -- WorldService carves the ridge first
	for _, spawn in SPAWNS do
		spawnEnemy(spawn.kind, spawn.level, spawn.pos, spawn)
	end
	local lastTutorial = 0
	while true do
		task.wait(TICK)
		local now = os.clock()
		for _, enemy in live do
			if not enemy.info.dead then
				local ok, err = pcall(think, enemy, now)
				if not ok then
					warn("[EnemyService]", err)
				end
			end
		end
		if now - lastTutorial > 2 then
			lastTutorial = now
			for _, player in Players:GetPlayers() do
				tutorialRaider(player)
			end
		end
	end
end

return EnemyService
