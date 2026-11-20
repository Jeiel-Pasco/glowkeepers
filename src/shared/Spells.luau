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
	slow: { amount: number, duration: number }?, -- 1 = rooted
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
	Neutral = { damage = 7, cooldown = 0.5, speed = 110, range = 60, radius = 1.2 },
	Fire = { damage = 8, cooldown = 0.5, speed = 110, range = 60, radius = 1.2 },
	Water = { damage = 7, cooldown = 0.5, speed = 110, range = 64, radius = 1.4 },
	Leaf = { damage = 7, cooldown = 0.45, speed = 120, range = 60, radius = 1.1 },
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
	-- Water -------------------------------------------------------------------------------
	{
		id = "tide_bolt",
		name = "Tide Bolt",
		type = "Water",
		rarity = "Common",
		role = "attack",
		kind = "bolt",
		damage = 24,
		cooldown = 1.6,
		speed = 95,
		range = 80,
		radius = 1.7,
		slow = { amount = 0.3, duration = 2 },
		blurb = "A heavy water bolt that slows its target.",
	},
	{
		id = "splash_ring",
		name = "Splash Ring",
		type = "Water",
		rarity = "Common",
		role = "attack",
		kind = "burst",
		damage = 34,
		cooldown = 5,
		radius = 12,
		slow = { amount = 0.4, duration = 2 },
		blurb = "Water bursts out round you, slowing everything it hits.",
	},
	{
		id = "mist_veil",
		name = "Mist Veil",
		type = "Water",
		rarity = "Rare",
		role = "defence",
		kind = "shield",
		amount = 65,
		duration = 5,
		cooldown = 14,
		blurb = "A veil of mist soaks 65 damage.",
	},
	{
		id = "riptide",
		name = "Riptide",
		type = "Water",
		rarity = "Rare",
		role = "movement",
		kind = "dash",
		distance = 32,
		damage = 20,
		cooldown = 6,
		slow = { amount = 0.4, duration = 2 },
		blurb = "Surf forward, dragging down everything you pass.",
	},
	{
		id = "undertow",
		name = "Undertow",
		type = "Water",
		rarity = "Epic",
		role = "utility",
		kind = "area",
		damage = 40,
		range = 50,
		radius = 12,
		delay = 0.4,
		cooldown = 12,
		slow = { amount = 0.6, duration = 3 },
		blurb = "A whirlpool at the aim point that bogs enemies down.",
	},
	{
		id = "tidal_wave",
		name = "Tidal Wave",
		type = "Water",
		rarity = "Legendary",
		role = "attack",
		kind = "beam",
		damage = 95,
		range = 60,
		width = 6,
		cooldown = 12,
		slow = { amount = 0.5, duration = 2 },
		blurb = "A wide wave crashes through everything in front of you.",
	},
	-- Leaf --------------------------------------------------------------------------------
	{
		id = "thorn_dart",
		name = "Thorn Dart",
		type = "Leaf",
		rarity = "Common",
		role = "attack",
		kind = "bolt",
		damage = 25,
		cooldown = 1.5,
		speed = 110,
		range = 85,
		radius = 1.3,
		blurb = "A fast, sharp thorn.",
	},
	{
		id = "bramble_burst",
		name = "Bramble Burst",
		type = "Leaf",
		rarity = "Common",
		role = "attack",
		kind = "burst",
		damage = 36,
		cooldown = 5,
		radius = 11,
		burn = { dps = 3, duration = 3 },
		blurb = "Brambles burst out round you; the thorns keep stinging.",
	},
	{
		id = "bark_skin",
		name = "Bark Skin",
		type = "Leaf",
		rarity = "Rare",
		role = "defence",
		kind = "shield",
		amount = 80,
		duration = 5,
		cooldown = 15,
		blurb = "Bark hardens over you and soaks 80 damage.",
	},
	{
		id = "leaf_glide",
		name = "Leaf Glide",
		type = "Leaf",
		rarity = "Rare",
		role = "movement",
		kind = "blink",
		distance = 30,
		cooldown = 6,
		blurb = "Ride the wind a short way.",
	},
	{
		id = "vine_snare",
		name = "Vine Snare",
		type = "Leaf",
		rarity = "Epic",
		role = "utility",
		kind = "bolt",
		damage = 30,
		cooldown = 10,
		speed = 80,
		range = 70,
		radius = 2,
		slow = { amount = 1, duration = 2.5 },
		blurb = "A seed that roots its target in place.",
	},
	{
		id = "elder_wrath",
		name = "Elder Wrath",
		type = "Leaf",
		rarity = "Legendary",
		role = "attack",
		kind = "beam",
		damage = 110,
		range = 75,
		width = 4,
		cooldown = 13,
		blurb = "A line of roots erupts through everything ahead.",
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
