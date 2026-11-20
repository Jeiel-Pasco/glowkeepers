--!strict
-- Combat (GDD "Combat"): the click attack, the equipped book's four spells, the dodge dash,
-- projectiles, shields, buffs, burns, regen and every point of damage, for players and enemies.
--
-- Server-authoritative: clients send an aim point; the server checks cooldowns, simulates every
-- projectile on Heartbeat and applies damage. Fx (unreliable) tells every client what to draw;
-- Hit sends damage numbers to the attacker and the victim. Movement spells (dash, blink) move
-- the character on its own client (it owns its physics); the server only checks the cooldown.
--
-- Enemies register with addEnemy; EnemyService owns their AI and drops. PvP is off in the slice.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Spells = require(Shared:WaitForChild("Spells")) :: any
local Element = require(Shared:WaitForChild("Element")) :: any
local Level = require(Shared:WaitForChild("Level")) :: any
local Status = require(Shared:WaitForChild("Status")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local CampService = require(script.Parent:WaitForChild("CampService"))

local CombatService = {}
CombatService.EnemyKilled = Signal.new() -- (model, info)
CombatService.EnemyHurt = Signal.new() -- (model, info, player, amount)
CombatService.PlayerHurt = Signal.new() -- (player, amount, attacker: Model?)
CombatService.PlayerDied = Signal.new() -- (player, position)
CombatService.Attacked = Signal.new() -- (player): dealt damage (combat tag, quests)

CombatService.DASH_COOLDOWN = 2.4
CombatService.DASH_IFRAMES = 0.3
CombatService.TAG_SECONDS = 15 -- leaving within this long of a hit counts as a death (GDD)
CombatService.REGEN_DELAY = 6
CombatService.REGEN_RATE = 0.04 -- of max health per second, out of combat
CombatService.CAMP_REGEN_RATE = 0.2

local SLACK = 0.12 -- cooldown tolerance for latency jitter

export type EnemyInfo = {
	kind: any,
	level: number,
	type: string,
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	dealt: { [Player]: number },
	dead: boolean,
	slow: { amount: number, untilT: number }?,
	onHurt: ((player: Player, amount: number) -> ())?,
}

type Burn = { dps: number, untilT: number, owner: Player?, type: string? }
type PlayerCombat = {
	ready: { [string]: number },
	shield: { amount: number, untilT: number, burn: any? }?,
	buff: { power: number, untilT: number, burn: any? }?,
	heal: { perSecond: number, untilT: number }?,
	iframesUntil: number,
	lastHurt: number,
	lastAction: number,
	burn: Burn?,
}
type Projectile = {
	team: "player" | "enemy",
	owner: Player?,
	source: Model?,
	pos: Vector3,
	dir: Vector3,
	speed: number,
	range: number,
	travelled: number,
	radius: number,
	damage: number,
	type: string,
	burn: any?,
	slow: any?,
}

local enemies: { [Model]: EnemyInfo } = {}
local state: { [Player]: PlayerCombat } = {}
local projectiles: { Projectile } = {}
local enemyBurns: { [Model]: Burn } = {}
local enemyFolder: Folder

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function stateOf(player: Player): PlayerCombat
	local s = state[player]
	if s == nil then
		s = { ready = {}, iframesUntil = 0, lastHurt = -1e9, lastAction = -1e9 }
		state[player] = s
	end
	return s
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid else nil
end

-- The book in hand: (book, data) or nil.
function CombatService.activeBook(player: Player): (any?, any?)
	local data = DataService.get(player)
	if data == nil then
		return nil, nil
	end
	local index = data.equipped[data.active]
	return data.books[index], data
end

local function playerType(player: Player): string
	local book = CombatService.activeBook(player)
	return if book then book.type else "Neutral"
end

local function fxAll(...: any)
	NetServer.sendAll("Fx", ...)
end

local function refreshRayParams()
	local list: { Instance } = { enemyFolder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	local emberfall = workspace:FindFirstChild("Emberfall")
	if emberfall then
		-- Props block shots only via terrain; small rocks and trees don't eat bolts.
		table.insert(list, emberfall)
	end
	rayParams.FilterDescendantsInstances = list
end

-- Damage ----------------------------------------------------------------------------------

function CombatService.addEnemy(info: EnemyInfo)
	enemies[info.model] = info
	info.model.Parent = enemyFolder
end

function CombatService.removeEnemy(model: Model)
	enemies[model] = nil
	enemyBurns[model] = nil
end

function CombatService.enemies(): { [Model]: EnemyInfo }
	return enemies
end

local function hurtEnemy(
	info: EnemyInfo,
	player: Player,
	base: number,
	levelScale: number,
	attackType: string,
	burn: any?,
	slow: any?
)
	if info.dead then
		return
	end
	local data = DataService.get(player)
	local s = stateOf(player)
	local now = os.clock()
	local power = if data then data.stats.power else 0
	local mult = Element.mult(attackType, info.type)
	local amount = Level.damage(base, levelScale, power, mult, 0) * Level.power(if data then data.level else 1)
	if s.buff and s.buff.untilT > now then
		amount *= 1 + s.buff.power
		burn = burn or s.buff.burn
	end
	amount = math.max(1, math.floor(amount + 0.5))
	s.lastAction = now
	info.dealt[player] = (info.dealt[player] or 0) + math.min(amount, info.humanoid.Health)
	info.humanoid.Health -= amount
	NetServer.send(player, "Hit", info.model, amount, mult)
	CombatService.Attacked:Fire(player)
	CombatService.EnemyHurt:Fire(info.model, info, player, amount)
	if info.onHurt then
		info.onHurt(player, amount)
	end
	if burn then
		enemyBurns[info.model] = { dps = burn.dps, untilT = now + burn.duration, owner = player, type = attackType }
	end
	if slow then
		info.slow = { amount = slow.amount, untilT = now + slow.duration }
	end
	if info.humanoid.Health <= 0 and not info.dead then
		info.dead = true
		CombatService.EnemyKilled:Fire(info.model, info)
	end
end

-- An enemy (or the world) damages a player. `attackType` is the attacker's type.
function CombatService.hurtPlayer(player: Player, base: number, attackType: string, attacker: Model?): number
	local humanoid = humanoidOf(player)
	local root = rootOf(player)
	if humanoid == nil or root == nil or CampService.isSafe(root.Position) then
		return 0
	end
	local s = stateOf(player)
	local now = os.clock()
	if s.iframesUntil > now then
		return 0
	end
	local data = DataService.get(player)
	local defense = if data then data.stats.defense else 0
	local mult = Element.mult(attackType, playerType(player))
	local amount = Level.damage(base, 1, 0, mult, defense)
	local shield = s.shield
	if shield and shield.untilT > now and shield.amount > 0 then
		local soaked = math.min(shield.amount, amount)
		shield.amount -= soaked
		amount -= soaked
		if shield.burn and attacker and enemies[attacker] then
			enemyBurns[attacker] = { dps = shield.burn.dps, untilT = now + shield.burn.duration, owner = player }
		end
		if shield.amount <= 0 then
			s.shield = nil
			fxAll("shieldBreak", player.UserId)
		end
	end
	amount = math.floor(amount + 0.5)
	s.lastHurt = now
	if amount <= 0 then
		return 0
	end
	humanoid:TakeDamage(amount)
	NetServer.send(player, "Hit", player.Character, amount, mult)
	CombatService.PlayerHurt:Fire(player, amount, attacker)
	return amount
end

function CombatService.burnPlayer(player: Player, dps: number, duration: number, kind: string?)
	stateOf(player).burn = { dps = dps, untilT = os.clock() + duration, type = kind or "Fire" }
end

-- Status effects (Shared.Status) ------------------------------------------------------------

-- Poison: a Leaf damage-over-time, the same tick as a burn.
function CombatService.poisonPlayer(player: Player, dps: number, duration: number)
	CombatService.burnPlayer(player, dps, duration, "Leaf")
end

-- Slows walk and run speed to `factor` (≥ Status.MIN_SLOW) for `duration` seconds.
function CombatService.slowPlayer(player: Player, factor: number, duration: number)
	local character = player.Character
	if character == nil then
		return
	end
	local now = workspace:GetServerTimeNow()
	local attrs = { SlowUntil = character:GetAttribute("SlowUntil"), SlowFactor = character:GetAttribute("SlowFactor") }
	local f, untilT = Status.addSlow(attrs :: any, now, factor, duration)
	character:SetAttribute("SlowFactor", f)
	character:SetAttribute("SlowUntil", untilT)
	fxAll("status", player.UserId, "slow", untilT - now)
end

-- Roots: no moving, jumping, dashing or blinking for `duration` seconds.
function CombatService.rootPlayer(player: Player, duration: number)
	local character = player.Character
	if character == nil then
		return
	end
	local now = workspace:GetServerTimeNow()
	local untilT = math.max(character:GetAttribute("RootUntil") or 0, now + duration)
	character:SetAttribute("RootUntil", untilT)
	fxAll("status", player.UserId, "root", untilT - now)
end

-- Knockback (positive speed, away from `from`) or pull (negative, toward it). The player's own
-- client moves them, since it owns their character's physics.
function CombatService.pushPlayer(player: Player, from: Vector3, speed: number, lift: number, seconds: number)
	local root = rootOf(player)
	if
		root == nil
		or Status.rooted(
			{ RootUntil = root.Parent and root.Parent:GetAttribute("RootUntil") } :: any,
			workspace:GetServerTimeNow()
		)
	then
		return
	end
	local v = Status.pushVelocity(from, root.Position, speed, lift)
	NetServer.send(player, "Fx", "push", v.X, v.Y, v.Z, seconds)
end

-- A line telegraph: a ground strip from `origin` along flat unit `dir`, filling over `delay`.
function CombatService.telegraphLine(
	origin: Vector3,
	dir: Vector3,
	length: number,
	width: number,
	delay: number,
	kind: string
)
	fxAll("line", origin.X, origin.Y, origin.Z, dir.X, dir.Z, length, width, delay, kind)
end

-- Players standing in a line telegraph's strip.
function CombatService.playersInLine(origin: Vector3, dir: Vector3, length: number, width: number): { Player }
	local out = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and Status.inLine(origin, dir, length, width + 3, root.Position) then
			table.insert(out, player)
		end
	end
	return out
end

function CombatService.inCombat(player: Player): boolean
	local s = state[player]
	return s ~= nil and os.clock() - s.lastHurt < CombatService.TAG_SECONDS
end

-- Area helpers ----------------------------------------------------------------------------

local function enemiesNear(pos: Vector3, radius: number): { EnemyInfo }
	local out = {}
	for _, info in enemies do
		if not info.dead and (info.root.Position - pos).Magnitude <= radius + info.kind.size then
			table.insert(out, info)
		end
	end
	return out
end

local function distToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local t = if ab.Magnitude > 0 then math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1) else 0
	return (a + ab * t - p).Magnitude
end

local function enemiesAlong(a: Vector3, b: Vector3, width: number): { EnemyInfo }
	local out = {}
	for _, info in enemies do
		if not info.dead and distToSegment(info.root.Position, a, b) <= width + info.kind.size then
			table.insert(out, info)
		end
	end
	return out
end

-- Fires a projectile. Enemies use this too (team "enemy").
function CombatService.fire(p: Projectile)
	table.insert(projectiles, p)
	local casterId = if p.owner then p.owner.UserId else 0
	fxAll("bolt", casterId, p.pos.X, p.pos.Y, p.pos.Z, p.dir.X, p.dir.Y, p.dir.Z, p.speed, p.range, p.type, p.radius)
end

local function stepProjectiles(dt: number)
	for i = #projectiles, 1, -1 do
		local p = projectiles[i]
		local step = math.min(p.speed * dt, p.range - p.travelled)
		local from = p.pos
		local to = from + p.dir * step
		local hitPos: Vector3? = nil
		if p.team == "player" then
			local best, bestD = nil, math.huge
			for _, info in enemies do
				if not info.dead and distToSegment(info.root.Position, from, to) <= p.radius + info.kind.size then
					local d = (info.root.Position - from).Magnitude
					if d < bestD then
						best, bestD = info, d
					end
				end
			end
			if best and p.owner then
				hurtEnemy(best, p.owner, p.damage, 1, p.type, p.burn, p.slow)
				hitPos = best.root.Position
			end
		else
			for _, player in Players:GetPlayers() do
				local root = rootOf(player)
				if root and distToSegment(root.Position, from, to) <= p.radius + 1.6 then
					CombatService.hurtPlayer(player, p.damage, p.type, p.source)
					if p.burn then
						CombatService.burnPlayer(player, p.burn.dps, p.burn.duration)
					end
					hitPos = root.Position
					break
				end
			end
		end
		if hitPos == nil then
			local ray = workspace:Raycast(from, to - from, rayParams)
			if ray then
				hitPos = ray.Position
			end
		end
		p.pos = to
		p.travelled += step
		if hitPos then
			fxAll("impact", hitPos.X, hitPos.Y, hitPos.Z, p.type, p.radius)
			table.remove(projectiles, i)
		elseif p.travelled >= p.range then
			table.remove(projectiles, i)
		end
	end
end

-- Casting ---------------------------------------------------------------------------------

local function ready(s: PlayerCombat, key: string, cooldown: number): boolean
	local now = os.clock()
	if (s.ready[key] or 0) - SLACK > now then
		return false
	end
	s.ready[key] = now + cooldown
	return true
end

-- Origin and flat-ish aim direction from the character toward the aim point.
local function aim(player: Player, x: number, y: number, z: number): (Vector3?, Vector3?, Vector3?)
	local root = rootOf(player)
	if root == nil or humanoidOf(player) == nil then
		return nil, nil, nil
	end
	local origin = root.Position + Vector3.new(0, 1.2, 0)
	local target = Vector3.new(x, y, z)
	local delta = target - origin
	if delta.Magnitude < 0.5 then
		delta = root.CFrame.LookVector
	end
	local dir = delta.Unit
	-- Keep shots roughly level so they don't dive into the ground at close range.
	dir = Vector3.new(dir.X, math.clamp(dir.Y, -0.35, 0.35), dir.Z).Unit
	return origin + dir * 1.5, dir, target
end

local function onBasic(player: Player, x: number, y: number, z: number)
	local origin, dir = aim(player, x, y, z)
	if origin == nil or dir == nil then
		return
	end
	local kind = playerType(player)
	local basic = Spells.BASIC[kind] or Spells.BASIC.Neutral
	local s = stateOf(player)
	if not ready(s, "basic", basic.cooldown) then
		return
	end
	CombatService.fire({
		team = "player",
		owner = player,
		pos = origin,
		dir = dir,
		speed = basic.speed,
		range = basic.range,
		travelled = 0,
		radius = basic.radius,
		damage = basic.damage,
		type = kind,
	})
end

local function onCast(player: Player, slot: number, x: number, y: number, z: number)
	local book = CombatService.activeBook(player)
	if book == nil then
		return
	end
	local page = book.pages[slot]
	local spell = page and Spells.get(page.sp)
	if spell == nil then
		return
	end
	local origin, dir, target = aim(player, x, y, z)
	local root = rootOf(player)
	if origin == nil or dir == nil or target == nil or root == nil then
		return
	end
	local s = stateOf(player)
	if not ready(s, `{book.type}:{spell.id}:{slot}`, Spells.cooldownAt(spell, page.lv)) then
		return
	end
	local scale = Spells.levelScale(page.lv)
	local now = os.clock()
	local kind = spell.kind
	local uid = player.UserId
	if kind == "bolt" then
		CombatService.fire({
			team = "player",
			owner = player,
			pos = origin,
			dir = dir,
			speed = spell.speed,
			range = spell.range,
			travelled = 0,
			radius = spell.radius,
			damage = spell.damage * scale,
			type = spell.type,
			burn = spell.burn,
			slow = spell.slow,
		})
	elseif kind == "burst" then
		local pos = root.Position
		fxAll("burst", pos.X, pos.Y, pos.Z, spell.radius, spell.type)
		for _, info in enemiesNear(pos, spell.radius) do
			hurtEnemy(info, player, spell.damage, scale, spell.type, spell.burn, spell.slow)
		end
	elseif kind == "area" then
		local flat = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
		if flat.Magnitude > spell.range then
			flat = flat.Unit * spell.range
		end
		local pos = Vector3.new(root.Position.X + flat.X, root.Position.Y - 2.5, root.Position.Z + flat.Z)
		local ray = workspace:Raycast(pos + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), rayParams)
		if ray then
			pos = ray.Position
		end
		fxAll("area", pos.X, pos.Y, pos.Z, spell.radius, spell.type, spell.delay)
		task.delay(spell.delay, function()
			fxAll("blast", pos.X, pos.Y, pos.Z, spell.radius, spell.type)
			if player.Parent == nil then
				return
			end
			for _, info in enemiesNear(pos, spell.radius) do
				hurtEnemy(info, player, spell.damage, scale, spell.type, spell.burn, spell.slow)
			end
		end)
	elseif kind == "beam" then
		local finish = origin + dir * spell.range
		local ray = workspace:Raycast(origin, dir * spell.range, rayParams)
		if ray then
			finish = ray.Position
		end
		fxAll("beam", origin.X, origin.Y, origin.Z, finish.X, finish.Y, finish.Z, spell.type, spell.width)
		for _, info in enemiesAlong(origin, finish, spell.width) do
			hurtEnemy(info, player, spell.damage, scale, spell.type, spell.burn, spell.slow)
		end
	elseif kind == "shield" then
		s.shield = { amount = spell.amount * scale, untilT = now + spell.duration, burn = spell.burn }
		fxAll("shield", uid, spell.type, spell.duration)
	elseif kind == "heal" then
		s.heal = { perSecond = spell.amount * scale / spell.duration, untilT = now + spell.duration }
		fxAll("heal", uid, spell.duration)
	elseif kind == "buff" then
		s.buff = { power = spell.power, untilT = now + spell.duration, burn = spell.burn }
		fxAll("buff", uid, spell.type, spell.duration)
	elseif kind == "dash" then
		s.iframesUntil = now + CombatService.DASH_IFRAMES
		local flat = Vector3.new(dir.X, 0, dir.Z)
		flat = if flat.Magnitude > 0 then flat.Unit else root.CFrame.LookVector
		local a = root.Position
		local b = a + flat * spell.distance
		fxAll("dash", uid, spell.type)
		task.delay(0.12, function()
			for _, info in enemiesAlong(a, b, 4) do
				hurtEnemy(info, player, spell.damage, scale, spell.type, spell.burn, spell.slow)
			end
		end)
	elseif kind == "blink" then
		s.iframesUntil = now + 0.2
		fxAll("blink", uid, root.Position.X, root.Position.Y, root.Position.Z, spell.type)
	end
	s.lastAction = now
end

local function onDash(player: Player)
	local s = stateOf(player)
	if humanoidOf(player) == nil or not ready(s, "dash", CombatService.DASH_COOLDOWN) then
		return
	end
	s.iframesUntil = os.clock() + CombatService.DASH_IFRAMES
	fxAll("dash", player.UserId, "Neutral")
end

-- Ticks: burns, heals, regen ---------------------------------------------------------------

local TICK = 0.5

local function tick()
	local now = os.clock()
	for model, burn in enemyBurns do
		local info = enemies[model]
		if info == nil or info.dead or burn.untilT < now then
			enemyBurns[model] = nil
		elseif burn.owner and burn.owner.Parent then
			hurtEnemy(info, burn.owner, burn.dps * TICK, 1, burn.type or "Fire", nil)
		end
	end
	for player, s in state do
		local humanoid = humanoidOf(player)
		local root = rootOf(player)
		if humanoid == nil or root == nil then
			continue
		end
		if s.burn then
			if s.burn.untilT < now then
				s.burn = nil
			else
				CombatService.hurtPlayer(player, s.burn.dps * TICK, s.burn.type or "Fire", nil)
			end
		end
		local heal = 0
		if s.heal then
			if s.heal.untilT < now then
				s.heal = nil
			else
				heal += s.heal.perSecond * TICK
			end
		end
		if CampService.isSafe(root.Position) then
			heal += humanoid.MaxHealth * CombatService.CAMP_REGEN_RATE * TICK
		elseif now - s.lastHurt > CombatService.REGEN_DELAY then
			heal += humanoid.MaxHealth * CombatService.REGEN_RATE * TICK
		end
		if heal > 0 and humanoid.Health < humanoid.MaxHealth then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + heal)
		end
	end
end

local function watchCharacter(player: Player, character: Model)
	local s = stateOf(player)
	s.shield, s.buff, s.heal, s.burn = nil, nil, nil, nil
	s.lastHurt = -1e9
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.BreakJointsOnDeath = false
		humanoid.Died:Connect(function()
			local root = character:FindFirstChild("HumanoidRootPart")
			local pos = if root and root:IsA("BasePart") then root.Position else character:GetPivot().Position
			CombatService.PlayerDied:Fire(player, pos)
		end)
	end
	refreshRayParams()
end

function CombatService.Init()
	enemyFolder = Instance.new("Folder")
	enemyFolder.Name = "Enemies"
	enemyFolder.Parent = workspace

	NetServer.on("Basic", onBasic)
	NetServer.on("Cast", onCast)
	NetServer.on("Dash", onDash)

	local function added(player: Player)
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
		if player.Character then
			task.spawn(watchCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(added)
	for _, player in Players:GetPlayers() do
		added(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		state[player] = nil
		for _, info in enemies do
			info.dealt[player] = nil
		end
		task.defer(refreshRayParams)
	end)
end

function CombatService.Start()
	refreshRayParams()
	RunService.Heartbeat:Connect(stepProjectiles)
	while true do
		task.wait(TICK)
		tick()
	end
end

return CombatService
