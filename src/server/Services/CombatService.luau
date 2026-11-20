--!strict
-- Combat (GDD "Combat"): the 4-hit M1 combo, the equipped Grimoire's Z/X/C/V skills, the dodge
-- dash, projectiles, shields, buffs, burns, regen and every point of damage, for players and
-- enemies.
--
-- Server-authoritative: clients send an aim point; the server checks cooldowns, simulates every
-- projectile on Heartbeat and applies damage. Fx (unreliable) tells every client what to draw;
-- Hit sends damage numbers to the attacker and the victim. Movement spells (dash, blink) move
-- the character on its own client (it owns its physics); the server only checks the cooldown.
--
-- Gears and the Grimoire in hand change every fight (Shared.CombatRules): the Hat adds damage
-- and cuts cooldowns, the Robe cuts damage taken, Boots cut the dash cooldown, and each
-- Grimoire's passive adds its perk and its 4th-hit finisher (Permafrost chills, then Freezes).
-- Spells knock back or pull (push), weaken, root (slow amount 1) and cleanse; beams telegraph a
-- ground line before they fire.
--
-- PvP: players hit each other only outside the camp courtyard, when both stand in the Duel
-- Arena Ring or both have War Mode on (TogglePvp, switched in camp). PlayerDied carries the
-- killer and whether it was an arena duel; LootService pays bounties and skips duel drops.
--
-- Enemies register with addEnemy; EnemyService owns their AI and drops.

local Debris = game:GetService("Debris")
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
local Zones = require(Shared:WaitForChild("Zones")) :: any
local CombatRules = require(Shared:WaitForChild("CombatRules")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local CampService = require(script.Parent:WaitForChild("CampService"))

local CombatService = {}
CombatService.EnemyKilled = Signal.new() -- (model, info)
CombatService.EnemyHurt = Signal.new() -- (model, info, player, amount)
CombatService.PlayerHurt = Signal.new() -- (player, amount, attacker: Model?)
CombatService.PlayerDied = Signal.new() -- (player, position, killer: Player?, duel: boolean)
CombatService.Attacked = Signal.new() -- (player): dealt damage (combat tag, quests)

CombatService.DASH_COOLDOWN = 2.4
CombatService.DASH_IFRAMES = 0.3
CombatService.TAG_SECONDS = 15 -- leaving within this long of a hit counts as a death (GDD)
CombatService.REGEN_DELAY = 6
CombatService.REGEN_RATE = 0.04 -- of max health per second, out of combat
CombatService.CAMP_REGEN_RATE = 0.2

local SLACK = 0.12 -- cooldown tolerance for latency jitter
local PLAYER_SIZE = 1.6 -- a character's hit radius
local BLINK_LAND = 0.25 -- seconds for a blink's new position to replicate before it strikes

type Timed = { mult: number, untilT: number }
type Chill = { n: number, t: number }

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
	weaken: Timed?,
	chill: Chill?,
	onHurt: ((player: Player, amount: number) -> ())?,
}

type Burn = { dps: number, untilT: number, owner: Player?, type: string? }
type PlayerCombat = {
	ready: { [string]: number },
	shield: { amount: number, untilT: number, burn: any? }?,
	buff: { power: number, untilT: number, burn: any? }?,
	heal: { perSecond: number, untilT: number }?,
	weaken: Timed?,
	chill: Chill?,
	iframesUntil: number,
	lastHurt: number,
	lastAction: number,
	burn: Burn?,
	combo: number,
	comboT: number,
	lastAttacker: Player?,
	lastAttackerT: number,
}
-- One blow and what it does to whatever it lands on.
type Hit = {
	base: number,
	scale: number,
	type: string,
	burn: any?,
	slow: any?, -- { amount } from players' spells (1 = root); { factor } from enemies
	push: any?,
	weaken: any?,
	chill: number?, -- extra Permafrost stacks
	bonus: number?, -- extra damage fraction
	dot: boolean?, -- a burn tick: no buff, chill or on-hit effects
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
	push: any?,
	chill: number?,
	bonus: number?,
}
type PushFrom = (target: Vector3) -> Vector3

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
		s = {
			ready = {},
			iframesUntil = 0,
			lastHurt = -1e9,
			lastAction = -1e9,
			combo = 0,
			comboT = -1e9,
			lastAttackerT = -1e9,
		}
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

local function gearsOf(player: Player): any
	local data = DataService.get(player)
	return if data then data.gears else nil
end

local function isRooted(player: Player): boolean
	local character = player.Character
	return character ~= nil
		and Status.rooted({ RootUntil = character:GetAttribute("RootUntil") } :: any, workspace:GetServerTimeNow())
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

-- PvP ----------------------------------------------------------------------------------------

local function sideOf(player: Player): any
	local root = rootOf(player)
	if root == nil or humanoidOf(player) == nil then
		return nil
	end
	return {
		safe = CampService.isSafe(root.Position),
		arena = Zones.inArena(root.Position),
		war = player:GetAttribute("WarMode") == true,
	}
end

-- May `attacker` damage `victim` right now?
function CombatService.canHit(attacker: Player, victim: Player): boolean
	if attacker == victim then
		return false
	end
	local a, b = sideOf(attacker), sideOf(victim)
	return a ~= nil and b ~= nil and CombatRules.canPvp(a, b)
end

local function onTogglePvp(player: Player)
	local root = rootOf(player)
	if root == nil then
		return
	end
	if not CampService.isSafe(root.Position) then
		NetServer.send(player, "Toast", "Switch War Mode inside the Camp Courtyard", "warn")
		return
	end
	local on = player:GetAttribute("WarMode") ~= true
	player:SetAttribute("WarMode", on)
	NetServer.send(
		player,
		"Toast",
		if on
			then "War Mode ON: other War Mode wizards can fight you outside camp. +25% coins"
			else "War Mode OFF: no PvP outside the Duel Arena",
		if on then "warn" else nil
	)
end

-- Enemies -------------------------------------------------------------------------------------

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

-- Bosses stand their ground; everything else is shoved by a server-side LinearVelocity.
local function pushEnemy(info: EnemyInfo, from: Vector3, push: any)
	if info.kind.boss or info.dead then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = info.root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.MaxForce = math.huge
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VectorVelocity = Status.pushVelocity(from, info.root.Position, push.speed, push.lift)
	velocity.Parent = info.root
	Debris:AddItem(velocity, push.duration)
	Debris:AddItem(attachment, push.duration)
end

-- Permafrost stacks this blow adds: Frost hits from a wizard holding the Frost Grimoire.
local function chillsFrom(attacker: Player, hit: Hit): number
	if hit.dot or hit.type ~= "Frost" or playerType(attacker) ~= "Frost" then
		return 0
	end
	return 1 + (hit.chill or 0)
end

-- Adds chill to an enemy or player state; true when it Freezes.
local function addChill(holder: any, now: number, n: number): boolean
	local c: Chill = holder.chill or { n = 0, t = -1e9 }
	local stacks, frozen = CombatRules.addChill(c.n, c.t, now, n)
	holder.chill = { n = stacks, t = now }
	return frozen
end

-- Damage from a player's blow before the target's defences: base × spell level × stat power ×
-- type × level growth × (Hat + passive + bonus). In PvP only the first PVP_POWER_POINTS count.
local function attackAmount(player: Player, hit: Hit, mult: number, pvp: boolean?): number
	local data = DataService.get(player)
	local statPower = if data then data.stats.power else 0
	if pvp then
		statPower = math.min(statPower, CombatRules.PVP_POWER_POINTS)
	end
	local power = CombatRules.offense(if data then data.gears else nil, playerType(player))
	return Level.damage(hit.base, hit.scale, statPower, mult, 0)
		* Level.power(if data then data.level else 1)
		* (1 + power + (hit.bonus or 0))
end

local function hurtEnemy(info: EnemyInfo, player: Player, hit: Hit, from: Vector3?)
	if info.dead then
		return
	end
	local s = stateOf(player)
	local now = os.clock()
	local mult = Element.mult(hit.type, info.type)
	local amount = attackAmount(player, hit, mult)
	if info.weaken and info.weaken.untilT > now then
		amount *= info.weaken.mult
	end
	local burn = hit.burn
	if not hit.dot and s.buff and s.buff.untilT > now then
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
	if not hit.dot then
		if burn then
			enemyBurns[info.model] =
				{ dps = burn.dps, untilT = now + burn.duration, owner = player, type = burn.type or hit.type }
		end
		if hit.slow then
			local slowAmount = hit.slow.amount or (1 - (hit.slow.factor or 1))
			local current = info.slow
			if current == nil or current.untilT <= now or current.amount <= slowAmount then
				info.slow = { amount = slowAmount, untilT = now + hit.slow.duration }
			end
		end
		if hit.weaken then
			info.weaken = { mult = hit.weaken.mult, untilT = now + hit.weaken.duration }
		end
		if hit.push and from then
			pushEnemy(info, from, hit.push)
		end
		local n = chillsFrom(player, hit)
		if n > 0 and addChill(info, now, n) then
			info.slow = { amount = 1, untilT = now + CombatRules.FREEZE_SECONDS }
			local pos = info.root.Position
			fxAll("impact", pos.X, pos.Y, pos.Z, "Frost", info.kind.size + 2)
		end
	end
	if info.humanoid.Health <= 0 and not info.dead then
		info.dead = true
		CombatService.EnemyKilled:Fire(info.model, info)
	end
end

-- Player damage -----------------------------------------------------------------------------

-- Runs `amount` (already typed and scaled) through the victim's dodge, defence, weaken and
-- shield, then deals it. `attacker` is the player behind a PvP blow. Returns the damage dealt.
local function damagePlayer(player: Player, amount: number, mult: number, source: Model?, attacker: Player?): number
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
	local statDefense = if data then data.stats.defense else 0
	amount = amount / (1 + statDefense * Level.DEFENSE_PER_POINT)
	amount *= 1 - CombatRules.defense(if data then data.gears else nil, playerType(player))
	if s.weaken and s.weaken.untilT > now then
		amount *= s.weaken.mult
	end
	local shield = s.shield
	if shield and shield.untilT > now and shield.amount > 0 then
		local soaked = math.min(shield.amount, amount)
		shield.amount -= soaked
		amount -= soaked
		if shield.burn then
			if attacker then
				if CombatService.canHit(player, attacker) then
					CombatService.burnPlayer(
						attacker,
						shield.burn.dps * CombatRules.PVP_DAMAGE,
						shield.burn.duration,
						"Fire",
						player
					)
				end
			elseif source and enemies[source] then
				enemyBurns[source] = { dps = shield.burn.dps, untilT = now + shield.burn.duration, owner = player }
			end
		end
		if shield.amount <= 0 then
			s.shield = nil
			fxAll("shieldBreak", player.UserId)
		end
	end
	amount = math.floor(amount + 0.5)
	s.lastHurt = now
	if attacker then
		s.lastAttacker, s.lastAttackerT = attacker, now
	end
	if amount <= 0 then
		return 0
	end
	humanoid:TakeDamage(amount)
	NetServer.send(player, "Hit", player.Character, amount, mult)
	CombatService.PlayerHurt:Fire(player, amount, source)
	return amount
end

-- An enemy (or the world) damages a player. `attackType` is the attacker's type.
function CombatService.hurtPlayer(player: Player, base: number, attackType: string, attacker: Model?): number
	local mult = Element.mult(attackType, playerType(player))
	return damagePlayer(player, base * mult, mult, attacker, nil)
end

-- A damage-over-time. `owner` is the player who lit it (PvP), for kill credit.
function CombatService.burnPlayer(player: Player, dps: number, duration: number, kind: string?, owner: Player?)
	stateOf(player).burn = { dps = dps, untilT = os.clock() + duration, type = kind or "Fire", owner = owner }
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
	if root == nil or isRooted(player) then
		return
	end
	local v = Status.pushVelocity(from, root.Position, speed, lift)
	NetServer.send(player, "Fx", "push", v.X, v.Y, v.Z, seconds)
end

-- Purges burn, poison, weaken, chill, slow and root.
function CombatService.cleanse(player: Player)
	local s = stateOf(player)
	s.burn, s.weaken, s.chill = nil, nil, nil
	local character = player.Character
	if character then
		character:SetAttribute("SlowUntil", 0)
		character:SetAttribute("RootUntil", 0)
	end
end

-- A temporary speed multiplier (MovementController reads it).
local function boostSpeed(player: Player, mult: number, duration: number)
	local character = player.Character
	if character then
		character:SetAttribute("SpeedBoostMult", mult)
		character:SetAttribute("SpeedBoostUntil", workspace:GetServerTimeNow() + duration)
	end
end

-- A player slow from a hit: amount 1 roots; enemies' slows give a factor instead.
local function slowFromHit(player: Player, slow: any)
	if slow.amount and slow.amount >= 1 then
		CombatService.rootPlayer(player, slow.duration)
	else
		CombatService.slowPlayer(player, slow.factor or (1 - (slow.amount or 0.4)), slow.duration)
	end
end

-- A player's blow on another player (PvP). Returns the damage dealt.
local function strikePlayer(victim: Player, attacker: Player, hit: Hit, from: Vector3?): number
	if not CombatService.canHit(attacker, victim) then
		return 0
	end
	local s = stateOf(attacker)
	local now = os.clock()
	local mult = Element.mult(hit.type, playerType(victim), true)
	local amount = attackAmount(attacker, hit, mult, true) * CombatRules.PVP_DAMAGE
	local burn = hit.burn
	if not hit.dot and s.buff and s.buff.untilT > now then
		amount *= 1 + s.buff.power
		burn = burn or s.buff.burn
	end
	local dealt = damagePlayer(victim, amount, mult, attacker.Character, attacker)
	if dealt <= 0 then
		return 0
	end
	s.lastAction = now
	NetServer.send(attacker, "Hit", victim.Character, dealt, mult)
	CombatService.Attacked:Fire(attacker)
	if hit.dot then
		return dealt
	end
	if burn then
		local dps = burn.dps * CombatRules.PVP_DAMAGE
		CombatService.burnPlayer(victim, dps, burn.duration, burn.type or hit.type, attacker)
	end
	if hit.slow then
		slowFromHit(victim, hit.slow)
	end
	if hit.weaken then
		stateOf(victim).weaken = { mult = hit.weaken.mult, untilT = now + hit.weaken.duration }
	end
	if hit.push and from then
		CombatService.pushPlayer(victim, from, hit.push.speed, hit.push.lift, hit.push.duration)
	end
	local n = chillsFrom(attacker, hit)
	if n > 0 and addChill(stateOf(victim), now, n) then
		CombatService.rootPlayer(victim, CombatRules.FREEZE_SECONDS)
	end
	return dealt
end

-- Line telegraphs ---------------------------------------------------------------------------

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

-- Players `player` may hit near a point / along a segment.
local function foesNear(player: Player, pos: Vector3, radius: number): { Player }
	local out = {}
	for _, other in Players:GetPlayers() do
		local root = rootOf(other)
		if root and (root.Position - pos).Magnitude <= radius + PLAYER_SIZE and CombatService.canHit(player, other) then
			table.insert(out, other)
		end
	end
	return out
end

local function foesAlong(player: Player, a: Vector3, b: Vector3, width: number): { Player }
	local out = {}
	for _, other in Players:GetPlayers() do
		local root = rootOf(other)
		if
			root
			and distToSegment(root.Position, a, b) <= width + PLAYER_SIZE
			and CombatService.canHit(player, other)
		then
			table.insert(out, other)
		end
	end
	return out
end

-- Push origins: away from (or, for a pull, toward) a point, or along a direction of travel.
local function awayFrom(origin: Vector3): PushFrom
	return function(_target: Vector3)
		return origin
	end
end

local function along(dir: Vector3): PushFrom
	return function(target: Vector3)
		return target - dir * 5
	end
end

-- Lands `hit` on every enemy and PvP foe of `player` in range.
local function strikeNear(player: Player, pos: Vector3, radius: number, hit: Hit, pushFrom: PushFrom)
	for _, info in enemiesNear(pos, radius) do
		hurtEnemy(info, player, hit, pushFrom(info.root.Position))
	end
	for _, foe in foesNear(player, pos, radius) do
		local root = rootOf(foe)
		if root then
			strikePlayer(foe, player, hit, pushFrom(root.Position))
		end
	end
end

local function strikeAlong(player: Player, a: Vector3, b: Vector3, width: number, hit: Hit, pushFrom: PushFrom)
	for _, info in enemiesAlong(a, b, width) do
		hurtEnemy(info, player, hit, pushFrom(info.root.Position))
	end
	for _, foe in foesAlong(player, a, b, width) do
		local root = rootOf(foe)
		if root then
			strikePlayer(foe, player, hit, pushFrom(root.Position))
		end
	end
end

-- Projectiles -----------------------------------------------------------------------------

-- Fires a projectile. Enemies use this too (team "enemy").
function CombatService.fire(p: Projectile)
	table.insert(projectiles, p)
	local casterId = if p.owner then p.owner.UserId else 0
	fxAll("bolt", casterId, p.pos.X, p.pos.Y, p.pos.Z, p.dir.X, p.dir.Y, p.dir.Z, p.speed, p.range, p.type, p.radius)
end

local function projectileHit(p: Projectile): Hit
	return {
		base = p.damage,
		scale = 1,
		type = p.type,
		burn = p.burn,
		slow = p.slow,
		push = p.push,
		chill = p.chill,
		bonus = p.bonus,
	}
end

-- A player's projectile: the nearest enemy or PvP foe on this step's segment, if any.
local function stepPlayerProjectile(p: Projectile, from: Vector3, to: Vector3): Vector3?
	local owner = p.owner
	if owner == nil then
		return nil
	end
	local bestEnemy: EnemyInfo? = nil
	local bestFoe: Player? = nil
	local bestD = math.huge
	for _, info in enemies do
		if not info.dead and distToSegment(info.root.Position, from, to) <= p.radius + info.kind.size then
			local d = (info.root.Position - from).Magnitude
			if d < bestD then
				bestEnemy, bestFoe, bestD = info, nil, d
			end
		end
	end
	for _, foe in foesAlong(owner, from, to, p.radius) do
		local root = rootOf(foe)
		local d = if root then (root.Position - from).Magnitude else math.huge
		if d < bestD then
			bestEnemy, bestFoe, bestD = nil, foe, d
		end
	end
	if bestEnemy then
		local at = bestEnemy.root.Position
		hurtEnemy(bestEnemy, owner, projectileHit(p), at - p.dir * 5)
		return at
	end
	local root = bestFoe and rootOf(bestFoe)
	if bestFoe and root then
		strikePlayer(bestFoe, owner, projectileHit(p), root.Position - p.dir * 5)
		return root.Position
	end
	return nil
end

local function stepProjectiles(dt: number)
	for i = #projectiles, 1, -1 do
		local p = projectiles[i]
		local step = math.min(p.speed * dt, p.range - p.travelled)
		local from = p.pos
		local to = from + p.dir * step
		local hitPos: Vector3? = nil
		if p.team == "player" then
			hitPos = stepPlayerProjectile(p, from, to)
		else
			for _, player in Players:GetPlayers() do
				local root = rootOf(player)
				if root and distToSegment(root.Position, from, to) <= p.radius + PLAYER_SIZE then
					CombatService.hurtPlayer(player, p.damage, p.type, p.source)
					if p.burn then
						CombatService.burnPlayer(player, p.burn.dps, p.burn.duration, p.burn.type or p.type)
					end
					if p.slow then
						CombatService.slowPlayer(player, p.slow.factor or 0.6, p.slow.duration)
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

-- The 4-hit M1 combo: every 4th click within the window is the Grimoire's finisher.
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
	local now = os.clock()
	s.combo = CombatRules.comboStep(s.combo, s.comboT, now)
	s.comboT = now
	local finisher = if s.combo == CombatRules.COMBO_HITS then CombatRules.finisher(kind) else nil
	local big = s.combo == CombatRules.COMBO_HITS
	CombatService.fire({
		team = "player",
		owner = player,
		pos = origin,
		dir = dir,
		speed = basic.speed,
		range = basic.range,
		travelled = 0,
		radius = basic.radius * (if big then CombatRules.FINISHER_RADIUS else 1),
		damage = basic.damage * (if big then CombatRules.FINISHER_DAMAGE else 1),
		type = kind,
		burn = finisher and finisher.burn,
		slow = finisher and finisher.slow,
		push = finisher and finisher.push,
		chill = finisher and finisher.chill,
		bonus = finisher and finisher.bonus,
	})
end

local function spellHit(spell: any, scale: number): Hit
	return {
		base = spell.damage or 0,
		scale = scale,
		type = spell.type,
		burn = spell.burn,
		slow = spell.slow,
		push = spell.push,
		weaken = spell.weaken,
	}
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
	local _, cdr = CombatRules.offense(gearsOf(player), book.type)
	if not ready(s, `{book.type}:{spell.id}:{slot}`, Spells.cooldownAt(spell, page.lv) * (1 - cdr)) then
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
			push = spell.push,
		})
	elseif kind == "burst" then
		local pos = root.Position
		fxAll("burst", pos.X, pos.Y, pos.Z, spell.radius, spell.type)
		strikeNear(player, pos, spell.radius, spellHit(spell, scale), awayFrom(pos))
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
		local hit = spellHit(spell, scale)
		task.delay(spell.delay, function()
			fxAll("blast", pos.X, pos.Y, pos.Z, spell.radius, spell.type)
			if player.Parent == nil then
				return
			end
			strikeNear(player, pos, spell.radius, hit, awayFrom(pos))
		end)
	elseif kind == "beam" then
		-- Telegraphed: a ground line fills over `delay`, then the beam fires down that line.
		local length = spell.range
		local ray = workspace:Raycast(origin, dir * spell.range, rayParams)
		if ray then
			length = ray.Distance
		end
		local flat = Vector3.new(dir.X, 0, dir.Z)
		flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
		local delay = spell.delay or 0
		local ground = Vector3.new(origin.X, root.Position.Y - 2.8, origin.Z)
		CombatService.telegraphLine(ground, flat, length, spell.width, delay, spell.type)
		local finish = origin + dir * length
		local hit = spellHit(spell, scale)
		task.delay(delay, function()
			fxAll("beam", origin.X, origin.Y, origin.Z, finish.X, finish.Y, finish.Z, spell.type, spell.width)
			if player.Parent == nil then
				return
			end
			strikeAlong(player, origin, finish, spell.width, hit, along(dir))
		end)
	elseif kind == "shield" then
		s.shield = { amount = spell.amount * scale, untilT = now + spell.duration, burn = spell.burn }
		fxAll("shield", uid, spell.type, spell.duration)
		if spell.push then
			-- Repulse: shove everything nearby away, no damage.
			local pos = root.Position
			local radius = spell.radius or 12
			fxAll("burst", pos.X, pos.Y, pos.Z, radius, spell.type)
			for _, info in enemiesNear(pos, radius) do
				pushEnemy(info, pos, spell.push)
			end
			for _, foe in foesNear(player, pos, radius) do
				CombatService.pushPlayer(foe, pos, spell.push.speed, spell.push.lift, spell.push.duration)
			end
		end
	elseif kind == "heal" then
		s.heal = { perSecond = spell.amount * scale / spell.duration, untilT = now + spell.duration }
		if spell.cleanse then
			CombatService.cleanse(player)
		end
		fxAll("heal", uid, spell.duration)
	elseif kind == "buff" then
		s.buff = { power = spell.power, untilT = now + spell.duration, burn = spell.burn }
		fxAll("buff", uid, spell.type, spell.duration)
	elseif kind == "dash" then
		s.iframesUntil = now + CombatService.DASH_IFRAMES
		fxAll("dash", uid, spell.type)
		if not isRooted(player) then
			local flat = Vector3.new(dir.X, 0, dir.Z)
			flat = if flat.Magnitude > 0 then flat.Unit else root.CFrame.LookVector
			local a = root.Position
			local b = a + flat * spell.distance
			local hit = spellHit(spell, scale)
			task.delay(0.12, function()
				strikeAlong(player, a, b, 4, hit, awayFrom(a))
			end)
		end
	elseif kind == "blink" then
		s.iframesUntil = now + 0.2
		fxAll("blink", uid, root.Position.X, root.Position.Y, root.Position.Z, spell.type)
		if spell.damage and not isRooted(player) then
			-- Lightning Blitz, Black Meteorite: strike round where you land.
			local hit = spellHit(spell, scale)
			local radius = spell.radius or 8
			task.delay(BLINK_LAND, function()
				local landed = rootOf(player)
				if landed == nil then
					return
				end
				local pos = landed.Position
				fxAll("burst", pos.X, pos.Y, pos.Z, radius, spell.type)
				strikeNear(player, pos, radius, hit, awayFrom(pos))
			end)
		end
	end
	if spell.speedBoost then
		boostSpeed(player, spell.speedBoost.mult, spell.speedBoost.duration)
	end
	s.lastAction = now
end

local function onDash(player: Player)
	local s = stateOf(player)
	local cooldown = CombatRules.dashCooldown(CombatService.DASH_COOLDOWN, gearsOf(player))
	if humanoidOf(player) == nil or not ready(s, "dash", cooldown) then
		return
	end
	s.iframesUntil = os.clock() + CombatService.DASH_IFRAMES
	fxAll("dash", player.UserId, "Neutral")
end

-- Ticks: burns, heals, regen ---------------------------------------------------------------

local TICK = 0.5

local function tickPlayerBurn(player: Player, burn: Burn)
	local kind = burn.type or "Fire"
	local owner = burn.owner
	if owner and owner.Parent then
		local mult = Element.mult(kind, playerType(player), true)
		damagePlayer(player, burn.dps * TICK * mult, mult, owner.Character, owner)
	else
		CombatService.hurtPlayer(player, burn.dps * TICK, kind, nil)
	end
end

local function tick()
	local now = os.clock()
	for model, burn in enemyBurns do
		local info = enemies[model]
		if info == nil or info.dead or burn.untilT < now then
			enemyBurns[model] = nil
		elseif burn.owner and burn.owner.Parent then
			hurtEnemy(info, burn.owner, { base = burn.dps * TICK, scale = 1, type = burn.type or "Fire", dot = true })
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
				tickPlayerBurn(player, s.burn)
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
			local rate = CombatService.REGEN_RATE * CombatRules.regenMult(playerType(player))
			heal += humanoid.MaxHealth * rate * TICK
		end
		if heal > 0 and humanoid.Health < humanoid.MaxHealth then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + heal)
		end
	end
end

local function watchCharacter(player: Player, character: Model)
	local s = stateOf(player)
	s.shield, s.buff, s.heal, s.burn, s.weaken, s.chill = nil, nil, nil, nil, nil, nil
	s.lastHurt = -1e9
	s.combo, s.comboT = 0, -1e9
	s.lastAttacker, s.lastAttackerT = nil, -1e9
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.BreakJointsOnDeath = false
		humanoid.Died:Connect(function()
			local root = character:FindFirstChild("HumanoidRootPart")
			local pos = if root and root:IsA("BasePart") then root.Position else character:GetPivot().Position
			local attacker = s.lastAttacker
			local recent = os.clock() - s.lastAttackerT <= CombatRules.KILL_CREDIT_SECONDS
			local killer = if attacker and attacker.Parent and recent then attacker else nil
			CombatService.PlayerDied:Fire(player, pos, killer, Zones.inArena(pos))
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
	NetServer.on("TogglePvp", onTogglePvp)

	local function added(player: Player)
		player:SetAttribute("WarMode", false)
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
