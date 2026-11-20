--!strict
-- Enemy kinds (GDD "Enemies and bosses"). Pure data plus stat scaling.
--
-- Balance (tests/balance.spec.luau checks these against the player's kit):
--   * Health and damage grow 10% per level, the same rate as a player's level power, so an
--     on-level fight feels the same at level 2 and level 12.
--   * On-level minion: about 2 s to kill with a full kit, 4 s with clicks alone. It needs about
--     20 s to kill a player who stands still, so 2–3 at once are a real fight, not a wipe.
--   * Casters are fragile and hit from range. Bosses take a solo on-level player about a
--     minute, and their big hits are telegraphed.
--
-- attack: melee (wind up, hit in front), bolt (projectile), boss (slam, volley, eruptions).
-- role:   minion, caster, miniboss, boss, raider (quests count kills by role or by kind).

local Enemies = {}

export type Kind = {
	id: string,
	name: string,
	type: string,
	role: string,
	attack: string,
	size: number, -- rough radius, for hits and health bars
	hp: number, -- at level 1
	damage: number, -- per hit, at level 1
	speed: number,
	reach: number, -- melee reach or bolt range
	cooldown: number,
	windup: number,
	aggro: number,
	leash: number,
	xp: number, -- at level 1
	coins: { number },
	ink: { { type: string, chance: number, count: number } },
	frag: { type: string, chance: number }?,
	stars: number?,
	boss: boolean?,
	raider: boolean?,
}

Enemies.GROWTH = 0.1 -- health and damage per level above 1
Enemies.XP_GROWTH = 0.25
Enemies.BOSS_EXTRA_HP = 0.6 -- each extra attacker adds 60% of base health
Enemies.CREDIT_SHARE = 0.1 -- deal 10% of a boss's health for full drops
Enemies.OVERLEVEL = 15 -- this many levels above a boss: no drops or stars

local function minion(id: string, name: string, kind: string, extra: { [string]: any }): Kind
	local k: { [string]: any } = {
		id = id,
		name = name,
		type = kind,
		role = "minion",
		attack = "melee",
		size = 1.6,
		hp = 60,
		damage = 7,
		speed = 15,
		reach = 6,
		cooldown = 1.5,
		windup = 0.5,
		aggro = 30,
		leash = 60,
		xp = 10,
		coins = { 3, 7 },
		ink = { { type = kind, chance = 0.2, count = 1 }, { type = "Neutral", chance = 0.06, count = 1 } },
	}
	for key, value in extra do
		k[key] = value
	end
	return k :: any
end

local function caster(id: string, name: string, kind: string, extra: { [string]: any }): Kind
	local k: { [string]: any } = {
		id = id,
		name = name,
		type = kind,
		role = "caster",
		attack = "bolt",
		size = 2,
		hp = 48,
		damage = 9,
		speed = 11,
		reach = 44,
		cooldown = 2.4,
		windup = 0.7,
		aggro = 42,
		leash = 70,
		xp = 14,
		coins = { 5, 10 },
		ink = { { type = kind, chance = 0.3, count = 1 }, { type = "Neutral", chance = 0.08, count = 1 } },
	}
	for key, value in extra do
		k[key] = value
	end
	return k :: any
end

local function boss(id: string, name: string, kind: string, extra: { [string]: any }): Kind
	local k: { [string]: any } = {
		id = id,
		name = name,
		type = kind,
		role = "boss",
		attack = "boss",
		size = 6,
		hp = 1800,
		damage = 20,
		speed = 10,
		reach = 14,
		cooldown = 2.6,
		windup = 1.1,
		aggro = 60,
		leash = 90,
		xp = 160,
		coins = { 100, 150 },
		ink = { { type = kind, chance = 1, count = 2 }, { type = "Neutral", chance = 0.5, count = 1 } },
		frag = { type = kind, chance = 0.5 },
		stars = 1,
		boss = true,
	}
	for key, value in extra do
		k[key] = value
	end
	return k :: any
end

Enemies.kinds = {
	-- Fire: Emberfall Ridge
	ember_imp = minion("ember_imp", "Ember Imp", "Fire", {}),
	cinder_caster = caster("cinder_caster", "Cinder Caster", "Fire", {}),
	cinder_golem = boss("cinder_golem", "Cinder Golem", "Fire", {}),
	-- Water: Mistfall Basin
	tide_crab = minion("tide_crab", "Tide Crab", "Water", { hp = 72, damage = 6, speed = 13, size = 1.8 }),
	mist_caster = caster("mist_caster", "Mist Caller", "Water", {}),
	tide_warden = boss("tide_warden", "Tide Warden", "Water", {}),
	-- Leaf: Elderwood
	thorn_sprout = minion("thorn_sprout", "Thorn Sprout", "Leaf", { hp = 52, damage = 8, speed = 16 }),
	spore_caster = caster("spore_caster", "Spore Puff", "Leaf", {}),
	elder_treant = boss("elder_treant", "Elder Treant", "Leaf", {}),
	-- The tutorial trail's mini-boss.
	ashling = {
		id = "ashling",
		name = "Ashling",
		type = "Fire",
		role = "miniboss",
		attack = "melee",
		size = 3,
		hp = 300,
		damage = 9,
		speed = 13,
		reach = 9,
		cooldown = 1.8,
		windup = 0.8,
		aggro = 40,
		leash = 60,
		xp = 70,
		coins = { 30, 40 },
		ink = { { type = "Neutral", chance = 1, count = 1 } },
	},
	-- Raiders roam the wilds and steal what you carry.
	raider = {
		id = "raider",
		name = "Raider",
		type = "Neutral",
		role = "raider",
		attack = "melee",
		size = 1.8,
		hp = 70,
		damage = 5,
		speed = 19,
		reach = 6,
		cooldown = 1.2,
		windup = 0.35,
		aggro = 60,
		leash = 140,
		xp = 18,
		coins = { 4, 8 },
		ink = {},
		raider = true,
	},
} :: { [string]: Kind }

function Enemies.scale(level: number): number
	return 1 + Enemies.GROWTH * (math.max(level, 1) - 1)
end

function Enemies.maxHp(kind: Kind, level: number): number
	return math.floor(kind.hp * Enemies.scale(level))
end

function Enemies.damage(kind: Kind, level: number): number
	return kind.damage * Enemies.scale(level)
end

function Enemies.xp(kind: Kind, level: number): number
	return math.floor(kind.xp * (1 + Enemies.XP_GROWTH * (math.max(level, 1) - 1)))
end

-- A boss's health with `attackers` players on it (at least 1).
function Enemies.bossHp(kind: Kind, level: number, attackers: number): number
	return math.floor(Enemies.maxHp(kind, level) * (1 + Enemies.BOSS_EXTRA_HP * (math.max(attackers, 1) - 1)))
end

-- Does a player get drops from a boss? Enough damage, and not over-levelled.
function Enemies.earnsDrop(dealt: number, bossMax: number, playerLevel: number, bossLevel: number): boolean
	return dealt >= bossMax * Enemies.CREDIT_SHARE and playerLevel - bossLevel <= Enemies.OVERLEVEL
end

return Enemies
