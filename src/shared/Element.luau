--!strict
-- The 11 Black Clover / Blox Fruits Grimoire Types, Clover Counts, Rarities, Passive Perks, and
-- Elemental Type Chart. Pure.

local Element = {}

export type Type =
	"Neutral"
	| "Fire"
	| "Water"
	| "Leaf"
	| "Wind"
	| "Earth"
	| "Frost"
	| "Lightning"
	| "Gravity"
	| "Light"
	| "Dark"

export type Passive = {
	name: string,
	blurb: string,
	speed: number?, -- movement speed bonus while held (e.g. 0.08 = +8%)
	jump: number?, -- jump height bonus while held
	defense: number?, -- flat damage reduction fraction while held (e.g. 0.08 = -8% dmg taken)
	cdr: number?, -- cooldown reduction fraction while held
	power: number?, -- bonus spell damage fraction while held
	regen: number?, -- out-of-combat regen multiplier bonus
	m1Effect: string?, -- 4th M1 combo finisher special effect
}

Element.TYPES = {
	"Neutral",
	"Fire",
	"Water",
	"Leaf",
	"Wind",
	"Earth",
	"Frost",
	"Lightning",
	"Gravity",
	"Light",
	"Dark",
} :: { Type }

Element.ELEMENTS = { "Fire", "Water", "Leaf" } :: { Type } -- the 3 Common elements
Element.STRONG = 1.5
Element.WEAK = 0.67
Element.MYTHIC = 1.25
Element.PVP_STRONG = 1.30
Element.PVP_WEAK = 0.77
Element.PVP_MYTHIC = 1.15

-- Clover leaf tier: all standard Grimoires are 3-Leaf; Light is 4-Leaf; Dark is 5-Leaf.
Element.CLOVERS = {
	Neutral = 3,
	Fire = 3,
	Water = 3,
	Leaf = 3,
	Wind = 3,
	Earth = 3,
	Frost = 3,
	Lightning = 3,
	Gravity = 3,
	Light = 4,
	Dark = 5,
} :: { [string]: number }

-- Grimoire Rarity tier (Blox Fruits style).
Element.RARITY = {
	Neutral = "Starter",
	Fire = "Common",
	Water = "Common",
	Leaf = "Common",
	Wind = "Uncommon",
	Earth = "Uncommon",
	Frost = "Rare",
	Lightning = "Epic",
	Gravity = "Legendary",
	Light = "Mythic",
	Dark = "Mythic",
} :: { [string]: string }

-- Star cost to roll a new Grimoire at the Scriptorium Desk.
Element.STAR_ROLL_COST = 5

-- Gacha pools and odds by rarity tier.
Element.GACHA_TIERS = {
	{ rarity = "Common", chance = 0.48, types = { "Fire", "Water", "Leaf" } },
	{ rarity = "Uncommon", chance = 0.26, types = { "Wind", "Earth" } },
	{ rarity = "Rare", chance = 0.14, types = { "Frost" } },
	{ rarity = "Epic", chance = 0.08, types = { "Lightning" } },
	{ rarity = "Legendary", chance = 0.03, types = { "Gravity" } },
	{ rarity = "Mythic", chance = 0.01, types = { "Light", "Dark" } },
}

-- Unique Passive Perk while holding each Grimoire.
Element.PASSIVE = {
	Neutral = {
		name = "Mana Equilibrium",
		blurb = "Takes 1.0x damage from all elements (no elemental weakness).",
		m1Effect = "knockback",
	},
	Fire = {
		name = "Ignited Soul",
		blurb = "4th M1 combo hit sets the target ablaze (3 dps for 2s).",
		m1Effect = "burn",
	},
	Water = {
		name = "Valkyrie Current",
		blurb = "+8% Move Speed while held; 4th M1 combo hit slows by 25%.",
		speed = 0.08,
		m1Effect = "slow",
	},
	Leaf = {
		name = "Natural Grace",
		blurb = "+50% out-of-combat Health Regen and fastest M1 attacks; 4th M1 poisons.",
		regen = 0.5,
		m1Effect = "poison",
	},
	Wind = {
		name = "Spirit of Zephyr",
		blurb = "+12% Move Speed and +15% Jump Height while held.",
		speed = 0.12,
		jump = 0.15,
		m1Effect = "knockback",
	},
	Earth = {
		name = "Titan's Poise",
		blurb = "-8% damage taken from all sources while held.",
		defense = 0.08,
		m1Effect = "knockback",
	},
	Frost = {
		name = "Permafrost",
		blurb = "Frost hits apply Chill; 3 Chill stacks Freeze the target solid (1.2s Root).",
		m1Effect = "chill",
	},
	Lightning = {
		name = "Thunder Fiend Boots",
		blurb = "+10% Move Speed; 4th M1 discharges bonus shock damage.",
		speed = 0.10,
		m1Effect = "shock",
	},
	Gravity = {
		name = "Gravity Aura",
		blurb = "+6% Spell Damage; 4th M1 pulls the target toward you.",
		power = 0.06,
		m1Effect = "pull",
	},
	Light = {
		name = "4-Leaf Blessing",
		blurb = "+10% Cooldown Reduction and a golden 4-Leaf Clover aura.",
		cdr = 0.10,
		m1Effect = "knockback",
	},
	Dark = {
		name = "5-Leaf Devil's Pact",
		blurb = "+12% Spell Damage and a crimson-black 5-Leaf Devil aura.",
		power = 0.12,
		m1Effect = "burn",
	},
} :: { [string]: Passive }

-- Elemental counter table: BEATS[attacker][defender] = true means attacker counters defender.
local BEATS: { [string]: { [string]: boolean } } = {
	Fire = { Leaf = true, Frost = true },
	Water = { Fire = true, Earth = true },
	Leaf = { Water = true, Earth = true },
	Wind = { Leaf = true, Earth = true },
	Earth = { Fire = true, Lightning = true },
	Frost = { Leaf = true, Wind = true },
	Lightning = { Water = true, Wind = true },
	Gravity = { Earth = true, Wind = true },
}

-- Colours for UI, floating Grimoires and spell effects.
Element.COLOR = {
	Neutral = { 196, 188, 230 },
	Fire = { 255, 136, 60 },
	Water = { 92, 180, 255 },
	Leaf = { 120, 210, 96 },
	Wind = { 130, 240, 185 },
	Earth = { 186, 146, 96 },
	Frost = { 150, 230, 255 },
	Lightning = { 110, 195, 255 },
	Gravity = { 170, 110, 245 },
	Light = { 255, 232, 150 },
	Dark = { 150, 96, 220 },
} :: { [string]: { number } }

function Element.isType(value: any): boolean
	return type(value) == "string" and table.find(Element.TYPES, value :: any) ~= nil
end

function Element.clovers(kind: string): number
	return Element.CLOVERS[kind] or 3
end

-- Rolls a Grimoire type from the 6-Tier Gacha (`r1` picks tier, `r2` picks element within tier).
function Element.rollGacha(r1: number, r2: number): string
	local acc = 0
	local chosen = Element.GACHA_TIERS[1]
	for _, tier in Element.GACHA_TIERS do
		acc += tier.chance
		if r1 < acc then
			chosen = tier
			break
		end
	end
	local list = chosen.types
	local idx = math.clamp(math.floor(r2 * #list) + 1, 1, #list)
	return list[idx]
end

-- Damage multiplier for an attack of type `attack` on a defender of type `defend`.
function Element.mult(attack: string, defend: string, isPvp: boolean?): number
	local strong = if isPvp then Element.PVP_STRONG else Element.STRONG
	local weak = if isPvp then Element.PVP_WEAK else Element.WEAK
	local mythic = if isPvp then Element.PVP_MYTHIC else Element.MYTHIC
	if attack == "Light" or attack == "Dark" then
		if (attack == "Light" and defend == "Dark") or (attack == "Dark" and defend == "Light") then
			return strong
		elseif defend == "Light" or defend == "Dark" then
			return 1
		end
		return mythic
	end
	if attack == "Neutral" or defend == "Neutral" or defend == "Light" or defend == "Dark" then
		return 1
	end
	if BEATS[attack] and BEATS[attack][defend] then
		return strong
	elseif BEATS[defend] and BEATS[defend][attack] then
		return weak
	end
	return 1
end

return Element
