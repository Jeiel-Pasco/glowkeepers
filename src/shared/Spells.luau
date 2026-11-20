--!strict
-- Every spell (GDD "Spells"). Pure data plus lookups; numbers are starting values.
--
-- kind:
--   bolt    a projectile from the caster toward the aim point (speed, range, radius)
--   burst   damage in a circle round the caster (radius)
--   area    damage in a circle at the aim point after `delay` seconds (range, radius)
--   beam    instant damage along a line toward the aim (range, width)
--   shield  absorbs `amount` damage for `duration` seconds (burn: burns melee attackers)
--   heal    heals `amount` over `duration` seconds
--   dash    the caster dashes `distance` studs toward the aim, hurting what it passes
--   blink   the caster teleports up to `distance` studs toward the aim
--   buff    +`power` damage for `duration` seconds (burn: the caster's hits also burn)
-- burn = { dps, duration } on anything a damaging spell hits.

local Spells = {}

export type Burn = { dps: number, duration: number }
export type Spell = {
	id: string,
	name: string,
	type: string,
	rarity: string,
	role: string,
	kind: string,
	cooldown: number,
	damage: number?,
	speed: number?,
	range: number?,
	radius: number?,
	width: number?,
	delay: number?,
	amount: number?,
	duration: number?,
	distance: number?,
	power: number?,
	burn: Burn?,
	blurb: string,
}

Spells.RARITIES = { "Common", "Rare", "Epic", "Legendary", "Mythic" }
Spells.RARITY_COLOR = {
	Common = { 214, 210, 200 },
	Rare = { 96, 196, 255 },
	Epic = { 196, 120, 255 },
	Legendary = { 255, 196, 70 },
	Mythic = { 255, 110, 170 },
} :: { [string]: { number } }
Spells.MAX_LEVEL = 5
Spells.LEVEL_BONUS = 0.1 -- +10% damage and -4% cooldown per level above 1
Spells.LEVEL_COOLDOWN = 0.04

-- The click attack of each type.
Spells.BASIC = {
	Neutral = { damage = 9, cooldown = 0.45, speed = 110, range = 60, radius = 1.2 },
	Fire = { damage = 10, cooldown = 0.45, speed = 110, range = 60, radius = 1.2 },
} :: { [string]: any }

local list: { Spell } = {
	-- Neutral -----------------------------------------------------------------------------
	{
		id = "arcane_bolt",
		name = "Arcane Bolt",
		type = "Neutral",
		rarity = "Common",
		role = "attack",
		kind = "bolt",
		damage = 24,
		cooldown = 1.6,
		speed = 95,
		range = 80,
		radius = 1.6,
		blurb = "A quick bolt of raw magic.",
	},
	{
		id = "pulse",
		name = "Pulse",
		type = "Neutral",
		rarity = "Common",
		role = "attack",
		kind = "burst",
		damage = 32,
		cooldown = 5,
		radius = 12,
		blurb = "A ring of force round you.",
	},
	{
		id = "ward",
		name = "Ward",
		type = "Neutral",
		rarity = "Rare",
		role = "defence",
		kind = "shield",
		amount = 60,
		duration = 5,
		cooldown = 14,
		blurb = "Soaks the next 60 damage.",
	},
	{
		id = "mend",
		name = "Mend",
		type = "Neutral",
		rarity = "Rare",
		role = "utility",
		kind = "heal",
		amount = 45,
		duration = 5,
		cooldown = 16,
		blurb = "Heals 45 over 5 seconds.",
	},
	{
		id = "blink",
		name = "Blink",
		type = "Neutral",
		rarity = "Epic",
		role = "movement",
		kind = "blink",
		distance = 28,
		cooldown = 7,
		blurb = "Teleport a short way.",
	},
	{
		id = "force_lance",
		name = "Force Lance",
		type = "Neutral",
		rarity = "Legendary",
		role = "attack",
		kind = "beam",
		damage = 80,
		range = 70,
		width = 2.5,
		cooldown = 9,
		blurb = "A piercing beam through everything in line.",
	},
	-- Fire --------------------------------------------------------------------------------
	{
		id = "ember_shot",
		name = "Ember Shot",
		type = "Fire",
		rarity = "Common",
		role = "attack",
		kind = "bolt",
		damage = 26,
		cooldown = 1.6,
		speed = 90,
		range = 80,
		radius = 1.6,
		burn = { dps = 4, duration = 3 },
		blurb = "A burning bolt that sets its target alight.",
	},
	{
		id = "flame_burst",
		name = "Flame Burst",
		type = "Fire",
		rarity = "Common",
		role = "attack",
		kind = "burst",
		damage = 38,
		cooldown = 5,
		radius = 11,
		blurb = "Fire bursts out all round you.",
	},
	{
		id = "heat_shield",
		name = "Heat Shield",
		type = "Fire",
		rarity = "Rare",
		role = "defence",
		kind = "shield",
		amount = 70,
		duration = 5,
		cooldown = 14,
		burn = { dps = 6, duration = 3 },
		blurb = "Soaks 70 damage and burns whoever hits you up close.",
	},
	{
		id = "scorch_dash",
		name = "Scorch Dash",
		type = "Fire",
		rarity = "Rare",
		role = "movement",
		kind = "dash",
		distance = 30,
		damage = 22,
		cooldown = 6,
		burn = { dps = 4, duration = 3 },
		blurb = "Dash forward, scorching everything you pass.",
	},
	{
		id = "kindle",
		name = "Kindle",
		type = "Fire",
		rarity = "Epic",
		role = "utility",
		kind = "buff",
		power = 0.3,
		duration = 6,
		cooldown = 16,
		burn = { dps = 5, duration = 3 },
		blurb = "+30% damage for 6 seconds, and every hit burns.",
	},
	{
		id = "meteor_fall",
		name = "Meteor Fall",
		type = "Fire",
		rarity = "Legendary",
		role = "attack",
		kind = "area",
		damage = 120,
		range = 60,
		radius = 14,
		delay = 0.9,
		cooldown = 14,
		burn = { dps = 8, duration = 4 },
		blurb = "Call down a meteor on the aim point.",
	},
}

Spells.list = list
Spells.byId = {} :: { [string]: Spell }
Spells.pools = {} :: { [string]: { [string]: { string } } } -- type → rarity → spell ids
for _, spell in list do
	Spells.byId[spell.id] = spell
	local pool = Spells.pools[spell.type] or {}
	Spells.pools[spell.type] = pool
	pool[spell.rarity] = pool[spell.rarity] or {}
	table.insert(pool[spell.rarity], spell.id)
end

function Spells.get(id: string): Spell?
	return Spells.byId[id]
end

-- Damage scale of a spell at `level` (1–5).
function Spells.levelScale(level: number): number
	return 1 + (math.clamp(level, 1, Spells.MAX_LEVEL) - 1) * Spells.LEVEL_BONUS
end

function Spells.cooldownAt(spell: Spell, level: number): number
	return spell.cooldown * (1 - (math.clamp(level, 1, Spells.MAX_LEVEL) - 1) * Spells.LEVEL_COOLDOWN)
end

return Spells
