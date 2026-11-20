--!strict
-- Enemies (GDD "Enemies and bosses", LAYER_ONE Step 6): spawns wild Neutral creatures in the
-- lowland forest (re-rolling a random forest spot on every respawn), elemental packs and bosses
-- in the 3 stepped valleys, and raiders in the forest wedges.
--
-- Distinct elemental abilities (Step 6):
--   Fire:  Ember Imp melee burns; Cinder Caster bolt burns; Cinder Golem does slam ring, 5-bolt
--          fireball volley (burns), and lava eruptions under players (burns).
--   Water: Tide Crab melee knocks back; Mist Caller bolt slows; Tide Warden does tidal-wave line
--          (knockback), whirlpool ring (pull + slow), and bubble volley (slows).
--   Leaf:  Thorn Sprout lunges + poisons; Spore Puff casts a telegraphed poison spore cloud;
--          Elder Treant does root-snare circles (roots), thorn line (poisons), and summons
--          sprouts + heals.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Enemies = require(Shared:WaitForChild("Enemies")) :: any
local Loot = require(Shared:WaitForChild("Loot")) :: any
local Quests = require(Shared:WaitForChild("Quests")) :: any
local RaiderCamps = require(Shared:WaitForChild("RaiderCamps")) :: any
local Zones = require(Shared:WaitForChild("Zones")) :: any
local EnemyLooks = require(Server:WaitForChild("World"):WaitForChild("EnemyLooks"))
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local CampService = require(script.Parent:WaitForChild("CampService"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local LootService = require(script.Parent:WaitForChild("LootService"))
local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))

local EnemyService = {}

local TICK = 0.15
local RESPAWN = {
	forest_wisp = 8,
	ashling = 22,
	ember_imp = 9,
	cinder_caster = 12,
	cinder_golem = 90,
	tide_crab = 9,
	mist_caster = 12,
	tide_warden = 90,
	thorn_sprout = 9,
	spore_caster = 12,
	elder_treant = 90,
	raider = 40,
} :: { [string]: number }
local OVERLEVEL_XP = 8 -- this many levels above a normal enemy: a quarter of the XP
local FLEE_SECONDS = 9
local RAIDER_STASH_SECONDS = 60 -- stolen loot is gone this long after the raider escapes

type Spawn = { kind: string, pos: Vector3, level: number, wander: number?, wild: boolean? }

local SPAWNS: { Spawn } = Zones.spawns()

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
	camp: Vector3?, -- a raider camp guard's camp centre
	summons: { Model }?, -- Elder Treant's summoned sprouts
	summonedBy: Model?, -- a summoned add's boss model
}

local live: { [Model]: Enemy } = {}
local tutorialRaiders: { [Player]: Model } = {}

local function groundAt(pos: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local top = math.max(pos.Y, Zones.groundY(Vector2.new(pos.X, pos.Z).Magnitude)) + 80
	local ray = workspace:Raycast(Vector3.new(pos.X, top, pos.Z), Vector3.new(0, Zones.FLOOR_Y - 40 - top, 0), params)
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
	model:SetAttribute("Boss", kind.boss == true or kind.role == "miniboss")
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

local function clearSummons(enemy: Enemy)
	if enemy.summons == nil then
		return
	end
	for _, addModel in enemy.summons do
		local add = live[addModel]
		if add and not add.info.dead then
			add.info.dead = true
			live[addModel] = nil
			CombatService.removeEnemy(addModel)
			addModel:Destroy()
		end
	end
	table.clear(enemy.summons)
end

-- Targeting ---------------------------------------------------------------------------------

local function pickTarget(enemy: Enemy): Player?
	local kind = enemy.info.kind
	local pos = enemy.info.root.Position
	if enemy.owner then
		local root = rootOf(enemy.owner)
		return if root and not CampService.isSafe(root.Position) then enemy.owner else nil
	end
	local camp = enemy.camp
	if camp then
		local best, bestD = nil, math.huge
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if root then
				local inside = (Vector3.new(root.Position.X - camp.X, 0, root.Position.Z - camp.Z)).Magnitude
					<= RaiderCamps.WALL_R + 2
				local d = (root.Position - pos).Magnitude
				if (inside or (enemy.info.dealt[player] and d < kind.leash)) and d < bestD then
					best, bestD = player, d
				end
			end
		end
		return best
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
				continue
			end
			if d < bestD then
				best, bestD = player, d
			end
		end
	end
	return best
end

-- Attacks (Step 6: distinct abilities per element) ------------------------------------------

local function melee(enemy: Enemy, target: Player)
	local info = enemy.info
	local kind = info.kind
	local root = rootOf(target)
	if root == nil then
		return
	end
	-- Leaf Thorn Sprout lunges forward on its strike.
	if kind.lunge then
		local delta = Vector3.new(root.Position.X - info.root.Position.X, 0, root.Position.Z - info.root.Position.Z)
		if delta.Magnitude > 1 then
			local step = math.min(kind.lunge, math.max(0, delta.Magnitude - 2.5))
			local dest = groundAt(info.root.Position + delta.Unit * step)
			info.model:PivotTo(
				CFrame.lookAt(
					dest + Vector3.new(0, info.humanoid.HipHeight + 1, 0),
					Vector3.new(root.Position.X, dest.Y + info.humanoid.HipHeight + 1, root.Position.Z)
				)
			)
		end
	end
	NetServer.sendAll("Fx", "slash", info.model, kind.reach)
	if (root.Position - info.root.Position).Magnitude <= kind.reach + kind.size + 1.5 then
		local dealt = CombatService.hurtPlayer(target, Enemies.damage(kind, info.level), info.type, info.model)
		if dealt > 0 then
			if kind.burn then
				CombatService.burnPlayer(target, kind.burn.dps, kind.burn.duration)
			end
			if kind.poison then
				CombatService.poisonPlayer(target, kind.poison.dps, kind.poison.duration)
			end
			if kind.knockback then
				CombatService.pushPlayer(
					target,
					info.root.Position,
					kind.knockback.speed,
					kind.knockback.lift,
					kind.knockback.duration
				)
			end
			if kind.raider then
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
end

local function bolt(enemy: Enemy, target: Player, spread: number?, extraSlow: any?)
	local info = enemy.info
	local kind = info.kind
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
		pos = origin + dir * (kind.size + 1),
		dir = dir,
		speed = if kind.boss then 55 else 62,
		range = kind.reach + 20,
		travelled = 0,
		radius = if kind.boss then 2.2 else 1.3,
		damage = Enemies.damage(kind, info.level) * (if kind.boss then 0.6 else 1),
		type = info.type,
		burn = kind.burn or (if kind.boss and info.type == "Fire" then { dps = 3, duration = 2 } else nil),
		slow = extraSlow or kind.slow,
	})
end

-- Spore Puff (Leaf caster): a telegraphed poison spore cloud under the target.
local function sporeCloud(enemy: Enemy, target: Player)
	local info = enemy.info
	local kind = info.kind
	local root = rootOf(target)
	if root == nil then
		return
	end
	local spot = groundAt(root.Position)
	local radius = 8
	local delay = 1.0
	local damage = Enemies.damage(kind, info.level)
	NetServer.sendAll("Fx", "ring", spot.X, spot.Y, spot.Z, radius, delay)
	task.delay(delay, function()
		if info.dead then
			return
		end
		NetServer.sendAll("Fx", "blast", spot.X, spot.Y, spot.Z, radius, "Leaf")
		for _, player in Players:GetPlayers() do
			local now = rootOf(player)
			if now and (now.Position - spot).Magnitude <= radius then
				CombatService.hurtPlayer(player, damage, "Leaf", info.model)
				if kind.poison then
					CombatService.poisonPlayer(player, kind.poison.dps, kind.poison.duration)
				end
			end
		end
	end)
end

local function flatDirToward(from: Vector3, to: Vector3): Vector3
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	return if d.Magnitude > 0.1 then d.Unit else Vector3.zAxis
end

-- Fire boss (Cinder Golem): slam ring, 5-fireball burning volley, burning lava eruptions.
local function golemAttack(enemy: Enemy, target: Player, step: number, pos: Vector3, damage: number)
	local info = enemy.info
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
					CombatService.hurtPlayer(player, damage * 1.3, "Fire", info.model)
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
						CombatService.hurtPlayer(player, damage, "Fire", info.model)
						CombatService.burnPlayer(player, 4, 3)
					end
				end)
			end
		end
	end
end

-- Water boss (Tide Warden): tidal-wave line (knockback), whirlpool (pull + slow), bubble volley.
local function wardenAttack(enemy: Enemy, target: Player, step: number, pos: Vector3, damage: number)
	local info = enemy.info
	local ground = groundAt(pos)
	if step == 1 then
		local troot = rootOf(target)
		local dir = if troot then flatDirToward(ground, troot.Position) else Vector3.zAxis
		local length, width, delay = 56, 14, 1.05
		CombatService.telegraphLine(ground, dir, length, width, delay, "Water")
		task.delay(delay, function()
			if info.dead then
				return
			end
			local endPos = ground + dir * length
			NetServer.sendAll(
				"Fx",
				"beam",
				ground.X,
				ground.Y + 2,
				ground.Z,
				endPos.X,
				endPos.Y + 2,
				endPos.Z,
				"Water",
				width * 0.6
			)
			for _, player in CombatService.playersInLine(ground, dir, length, width) do
				CombatService.hurtPlayer(player, damage * 1.25, "Water", info.model)
				CombatService.pushPlayer(player, ground, 52, 14, 0.3)
			end
		end)
	elseif step == 2 then
		local radius = 24
		NetServer.sendAll("Fx", "ring", ground.X, ground.Y, ground.Z, radius, 1.1)
		task.delay(1.1, function()
			if info.dead then
				return
			end
			NetServer.sendAll("Fx", "blast", ground.X, ground.Y, ground.Z, radius, "Water")
			for _, player in Players:GetPlayers() do
				local root = rootOf(player)
				if root and (root.Position - ground).Magnitude <= radius then
					CombatService.hurtPlayer(player, damage, "Water", info.model)
					CombatService.pushPlayer(player, ground, -42, 6, 0.35)
					CombatService.slowPlayer(player, 0.5, 2.5)
				end
			end
		end)
	else
		local slow = { factor = 0.6, duration = 2 }
		for i = -2, 2 do
			bolt(enemy, target, i * 0.2, slow)
		end
	end
end

-- Leaf boss (Elder Treant): root-snare circles, poison thorn line, summon sprouts + heal.
local function treantAttack(enemy: Enemy, target: Player, step: number, pos: Vector3, damage: number)
	local info = enemy.info
	local ground = groundAt(pos)
	if step == 1 then
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if root and (root.Position - pos).Magnitude < 90 then
				local spot = groundAt(root.Position)
				NetServer.sendAll("Fx", "ring", spot.X, spot.Y, spot.Z, 9, 1.15)
				task.delay(1.15, function()
					if info.dead then
						return
					end
					NetServer.sendAll("Fx", "blast", spot.X, spot.Y, spot.Z, 9, "Leaf")
					local now = rootOf(player)
					if now and (now.Position - spot).Magnitude <= 9 then
						CombatService.hurtPlayer(player, damage, "Leaf", info.model)
						CombatService.rootPlayer(player, 1.8)
					end
				end)
			end
		end
	elseif step == 2 then
		local troot = rootOf(target)
		local dir = if troot then flatDirToward(ground, troot.Position) else Vector3.zAxis
		local length, width, delay = 58, 10, 1.05
		CombatService.telegraphLine(ground, dir, length, width, delay, "Leaf")
		task.delay(delay, function()
			if info.dead then
				return
			end
			local endPos = ground + dir * length
			NetServer.sendAll(
				"Fx",
				"beam",
				ground.X,
				ground.Y + 2,
				ground.Z,
				endPos.X,
				endPos.Y + 2,
				endPos.Z,
				"Leaf",
				width * 0.6
			)
			for _, player in CombatService.playersInLine(ground, dir, length, width) do
				CombatService.hurtPlayer(player, damage * 1.25, "Leaf", info.model)
				CombatService.poisonPlayer(player, 4, 3)
			end
		end)
	else
		-- Heal 4% and summon up to 2 Thorn Sprout adds.
		local humanoid = info.humanoid
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * 0.04)
		NetServer.sendAll("Fx", "burst", ground.X, ground.Y + 2, ground.Z, 12, "Leaf")
		local summons = enemy.summons or {}
		enemy.summons = summons
		for i = #summons, 1, -1 do
			if live[summons[i]] == nil or live[summons[i]].info.dead then
				table.remove(summons, i)
			end
		end
		for i = 1, 2 do
			if #summons >= 2 then
				break
			end
			local a = math.random() * math.pi * 2 + i * math.pi
			local addPos = ground + Vector3.new(math.cos(a) * 12, 0, math.sin(a) * 12)
			local add = spawnEnemy("thorn_sprout", 8, addPos, nil)
			add.summonedBy = info.model
			table.insert(summons, add.info.model)
		end
	end
end

local function bossAttack(enemy: Enemy, target: Player)
	local info = enemy.info
	enemy.bossStep += 1
	local step = enemy.bossStep % 3
	local pos = info.root.Position
	local damage = Enemies.damage(info.kind, info.level)
	if info.type == "Water" then
		wardenAttack(enemy, target, step, pos, damage)
	elseif info.type == "Leaf" then
		treantAttack(enemy, target, step, pos, damage)
	else
		golemAttack(enemy, target, step, pos, damage)
	end
end

-- The AI tick -------------------------------------------------------------------------------

local function speedFactor(enemy: Enemy, now: number): number
	local slow = enemy.info.slow
	if slow and slow.untilT > now then
		return 1 - slow.amount
	end
	return 1
end

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
		if math.abs(pos.Y - enemy.home.Y) > 15 then
			info.model:PivotTo(CFrame.new(enemy.home + Vector3.new(0, humanoid.HipHeight + 1, 0)))
		end
		humanoid:MoveTo(enemy.home)
		if fromHome < 6 then
			enemy.state = "idle"
			humanoid.Health = humanoid.MaxHealth
			table.clear(info.dealt)
			enemy.attackers = 1
			if kind.boss then
				humanoid.MaxHealth = Enemies.maxHp(kind, info.level)
				humanoid.Health = humanoid.MaxHealth
				clearSummons(enemy)
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
				elseif kind.attack == "cloud" then
					sporeCloud(enemy, target)
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
		local engageReach = kind.reach + kind.size + (kind.lunge or 0) * 0.7
		inReach = dist <= engageReach
		if not inReach then
			humanoid:MoveTo(troot.Position - flat.Unit * (kind.reach * 0.6))
		end
	elseif kind.attack == "bolt" or kind.attack == "cloud" then
		inReach = dist <= kind.reach
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
	if kind.boss then
		clearSummons(enemy)
	end

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
		ProgressionService.note(player, "kill", kind.id, kind.role)
		if kind.raider then
			ProgressionService.note(player, "raider")
		end
	end
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
			-- Wild Neutral creatures re-roll a brand-new random spot in the lowland forest!
			local nextPos = if spawn.wild or kind.wild then Zones.randomWildPos() else spawn.pos
			spawn.pos = nextPos
			spawnEnemy(spawn.kind, spawn.level, nextPos, spawn)
		end)
	end
end

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

function EnemyService.spawnGuard(kindId: string, level: number, pos: Vector3, camp: Vector3, campId: number): Model
	local enemy = spawnEnemy(kindId, level, pos, nil)
	enemy.camp = camp
	enemy.info.model:SetAttribute("Camp", campId)
	return enemy.info.model
end

function EnemyService.Init()
	CombatService.EnemyKilled:Connect(onKilled)
	CombatService.EnemyHurt:Connect(function(model: Model, _info: any, player: Player)
		local enemy = live[model]
		if enemy and enemy.state == "idle" then
			enemy.target = player
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
	for _, spawn in SPAWNS do
		local initialPos = if spawn.wild then Zones.randomWildPos() else spawn.pos
		spawn.pos = initialPos
		spawnEnemy(spawn.kind, spawn.level, initialPos, spawn)
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
				local factor = speedFactor(enemy, now)
				if factor < 1 then
					local humanoid = enemy.info.humanoid
					humanoid.WalkSpeed = math.min(humanoid.WalkSpeed, enemy.info.kind.speed * factor)
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
