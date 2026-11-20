--!strict
-- Enemy kinds (GDD "Enemies and bosses"). Pure data plus stat scaling; numbers are starting values.
--
-- attack:
--   melee  wind up, then hit everything in `reach` in front
--   bolt   a projectile at the target
--   boss   the Cinder Golem's pattern: slams (a telegraphed ring) and fireball volleys
-- drops: coins [min, max]; ink { type, chance, count }; frag { type, chance }; stars.

local Enemies = {}

export type Kind = {
	id: string,
	name: string,
	type: string,
	attack: string,
	size: number, -- rough radius, for hits and health bars
	hp: number,
	hpPerLevel: number,
	damage: number,
	damagePerLevel: number,
	speed: number,
	reach: number, -- melee reach or bolt range
	cooldown: number,
	windup: number,
	aggro: number,
	leash: number,
	xp: number,
	xpPerLevel: number,
	coins: { number },
	ink: { { type: string, chance: number, count: number } },
	frag: { type: string, chance: number }?,
	stars: number?,
	boss: boolean?,
	raider: boolean?,
}

Enemies.kinds = {
	ember_imp = {
		id = "ember_imp",
		name = "Ember Imp",
		type = "Fire",
		attack = "melee",
		size = 1.6,
		hp = 40,
		hpPerLevel = 16,
		damage = 6,
		damagePerLevel = 1.6,
		speed = 15,
		reach = 6,
		cooldown = 1.4,
		windup = 0.45,
		aggro = 38,
		leash = 70,
		xp = 10,
		xpPerLevel = 4,
		coins = { 3, 7 },
		ink = { { type = "Fire", chance = 0.22, count = 1 }, { type = "Neutral", chance = 0.08, count = 1 } },
	},
	cinder_caster = {
		id = "cinder_caster",
		name = "Cinder Caster",
		type = "Fire",
		attack = "bolt",
		size = 2,
		hp = 34,
		hpPerLevel = 14,
		damage = 9,
		damagePerLevel = 2,
		speed = 11,
		reach = 46,
		cooldown = 2.2,
		windup = 0.6,
		aggro = 52,
		leash = 80,
		xp = 14,
		xpPerLevel = 5,
		coins = { 5, 10 },
		ink = { { type = "Fire", chance = 0.32, count = 1 }, { type = "Neutral", chance = 0.1, count = 1 } },
	},
	ashling = { -- the tutorial mini-boss on the trail
		id = "ashling",
		name = "Ashling",
		type = "Fire",
		attack = "melee",
		size = 3,
		hp = 260,
		hpPerLevel = 30,
		damage = 9,
		damagePerLevel = 2,
		speed = 13,
		reach = 9,
		cooldown = 1.8,
		windup = 0.7,
		aggro = 40,
		leash = 60,
		xp = 90,
		xpPerLevel = 10,
		coins = { 30, 40 },
		ink = { { type = "Neutral", chance = 1, count = 1 } },
	},
	cinder_golem = {
		id = "cinder_golem",
		name = "Cinder Golem",
		type = "Fire",
		attack = "boss",
		size = 6,
		hp = 1500,
		hpPerLevel = 120,
		damage = 18,
		damagePerLevel = 3,
		speed = 10,
		reach = 14,
		cooldown = 2.6,
		windup = 1.1,
		aggro = 60,
		leash = 90,
		xp = 380,
		xpPerLevel = 20,
		coins = { 100, 150 },
		ink = { { type = "Fire", chance = 1, count = 2 }, { type = "Neutral", chance = 0.5, count = 1 } },
		frag = { type = "Fire", chance = 0.5 },
		stars = 1,
		boss = true,
	},
	raider = {
		id = "raider",
		name = "Raider",
		type = "Neutral",
		attack = "melee",
		size = 1.8,
		hp = 60,
		hpPerLevel = 18,
		damage = 5,
		damagePerLevel = 1.2,
		speed = 19,
		reach = 6,
		cooldown = 1.2,
		windup = 0.35,
		aggro = 70,
		leash = 140,
		xp = 20,
		xpPerLevel = 4,
		coins = { 4, 8 },
		ink = {},
		raider = true,
	},
} :: { [string]: Kind }

Enemies.BOSS_EXTRA_HP = 0.6 -- each extra attacker adds 60% of base health (GDD: scales with attackers)
Enemies.CREDIT_SHARE = 0.1 -- deal 10% of a boss's health for full drops
Enemies.OVERLEVEL = 15 -- this many levels above a boss: no drops or stars

function Enemies.maxHp(kind: Kind, level: number): number
	return math.floor(kind.hp + kind.hpPerLevel * (level - 1))
end

function Enemies.damage(kind: Kind, level: number): number
	return kind.damage + kind.damagePerLevel * (level - 1)
end

function Enemies.xp(kind: Kind, level: number): number
	return math.floor(kind.xp + kind.xpPerLevel * (level - 1))
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
