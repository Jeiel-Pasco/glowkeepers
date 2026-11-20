--!strict
-- The 4 Visible Gear Categories bought with Banked Coins at the Camp Gear Shop:
--   backpack  Loot Capacity (25 → 250) & Death Protection (50% → 25% dropped on death)
--   robe      Max Health (+HP) & Defense (-% damage taken)
--   hat       Spell Power (+% damage) & Cooldown Reduction (-% cooldown)
--   boots     Movement Speed (+% speed), Dash Cooldown reduction, & Faster Recall (R)
-- Pure data plus stat aggregation, shared by server, client UI, character appearance, and tests.

local Gears = {}

export type Category = "backpack" | "robe" | "hat" | "boots"

export type Tier = {
	tier: number,
	name: string,
	price: number,
	color: { number },
	accent: { number },
	capacity: number?, -- backpack
	deathShare: number?, -- backpack (fraction of carried loot dropped on death)
	hp: number?, -- robe
	defense: number?, -- robe (0.04 = -4% dmg taken)
	power: number?, -- hat (0.05 = +5% spell dmg)
	cdr: number?, -- hat (0.03 = -3% cooldown)
	speed: number?, -- boots (0.06 = +6% walk/run speed)
	dashBonus: number?, -- boots (seconds shaved off Q dash cooldown)
	recallSeconds: number?, -- boots (Recall channel time)
	blurb: string,
}

Gears.CATEGORIES = { "backpack", "robe", "hat", "boots" } :: { Category }

Gears.LABELS = {
	backpack = "Backpack",
	robe = "Robe & Cloak",
	hat = "Wizard Hat",
	boots = "Boots",
} :: { [string]: string }

Gears.TIERS = {
	backpack = {
		{
			tier = 1,
			name = "Starter Satchel",
			price = 0,
			color = { 130, 92, 62 },
			accent = { 196, 160, 90 },
			capacity = 25,
			deathShare = 0.50,
			blurb = "25 Loot Capacity · 50% kept on death",
		},
		{
			tier = 2,
			name = "Scout's Pack",
			price = 120,
			color = { 96, 118, 76 },
			accent = { 178, 142, 104 },
			capacity = 50,
			deathShare = 0.45,
			blurb = "50 Loot Capacity · 55% kept on death",
		},
		{
			tier = 3,
			name = "Ranger's Chestpack",
			price = 350,
			color = { 110, 76, 52 },
			accent = { 210, 175, 95 },
			capacity = 90,
			deathShare = 0.40,
			blurb = "90 Loot Capacity · 60% kept on death",
		},
		{
			tier = 4,
			name = "Runed Vault-Pack",
			price = 800,
			color = { 84, 94, 138 },
			accent = { 150, 220, 240 },
			capacity = 150,
			deathShare = 0.32,
			blurb = "150 Loot Capacity · 68% kept on death",
		},
		{
			tier = 5,
			name = "Astral Dimensional Bag",
			price = 1800,
			color = { 120, 78, 168 },
			accent = { 255, 215, 110 },
			capacity = 250,
			deathShare = 0.25,
			blurb = "250 Loot Capacity · 75% kept on death",
		},
	},
	robe = {
		{
			tier = 1,
			name = "Apprentice Mantle",
			price = 100,
			color = { 96, 118, 78 },
			accent = { 168, 146, 98 },
			hp = 25,
			defense = 0.04,
			blurb = "+25 Max HP · -4% Damage Taken",
		},
		{
			tier = 2,
			name = "Forester's Cloak",
			price = 300,
			color = { 66, 104, 72 },
			accent = { 196, 170, 105 },
			hp = 60,
			defense = 0.08,
			blurb = "+60 Max HP · -8% Damage Taken",
		},
		{
			tier = 3,
			name = "Ironbark Robe",
			price = 700,
			color = { 128, 76, 62 },
			accent = { 230, 185, 95 },
			hp = 110,
			defense = 0.13,
			blurb = "+110 Max HP · -13% Damage Taken",
		},
		{
			tier = 4,
			name = "Archmage Vestments",
			price = 1500,
			color = { 88, 72, 136 },
			accent = { 255, 215, 110 },
			hp = 180,
			defense = 0.18,
			blurb = "+180 Max HP · -18% Damage Taken",
		},
	},
	hat = {
		{
			tier = 1,
			name = "Initiate Hood",
			price = 100,
			color = { 105, 82, 64 },
			accent = { 178, 146, 104 },
			power = 0.05,
			cdr = 0.03,
			blurb = "+5% Spell Damage · -3% Cooldowns",
		},
		{
			tier = 2,
			name = "Scholar's Pointed Hat",
			price = 300,
			color = { 76, 88, 126 },
			accent = { 220, 185, 100 },
			power = 0.10,
			cdr = 0.06,
			blurb = "+10% Spell Damage · -6% Cooldowns",
		},
		{
			tier = 3,
			name = "Runed Circlet",
			price = 700,
			color = { 150, 110, 74 },
			accent = { 140, 230, 240 },
			power = 0.16,
			cdr = 0.09,
			blurb = "+16% Spell Damage · -9% Cooldowns",
		},
		{
			tier = 4,
			name = "Crown of the Magi",
			price = 1500,
			color = { 130, 84, 175 },
			accent = { 255, 220, 115 },
			power = 0.24,
			cdr = 0.12,
			blurb = "+24% Spell Damage · -12% Cooldowns",
		},
	},
	boots = {
		{
			tier = 1,
			name = "Traveler's Boots",
			price = 100,
			color = { 112, 80, 56 },
			accent = { 178, 142, 104 },
			speed = 0.06,
			dashBonus = 0,
			recallSeconds = 4.5,
			blurb = "+6% Move Speed · 4.5s Recall",
		},
		{
			tier = 2,
			name = "Strider Greaves",
			price = 300,
			color = { 82, 112, 84 },
			accent = { 210, 180, 105 },
			speed = 0.12,
			dashBonus = 0.15,
			recallSeconds = 4.0,
			blurb = "+12% Move Speed · 4.0s Recall",
		},
		{
			tier = 3,
			name = "Windrunner Boots",
			price = 700,
			color = { 76, 126, 146 },
			accent = { 160, 240, 210 },
			speed = 0.18,
			dashBonus = 0.3,
			recallSeconds = 3.5,
			blurb = "+18% Move Speed · -0.3s Dash CD · 3.5s Recall",
		},
		{
			tier = 4,
			name = "Astral Striders",
			price = 1500,
			color = { 116, 78, 162 },
			accent = { 255, 215, 110 },
			speed = 0.24,
			dashBonus = 0.5,
			recallSeconds = 3.0,
			blurb = "+24% Move Speed · -0.5s Dash CD · 3.0s Recall",
		},
	},
} :: { [string]: { Tier } }

function Gears.get(category: string, tier: number): Tier?
	local list = Gears.TIERS[category]
	return if list then list[tier] else nil
end

function Gears.nextTier(category: string, currentTier: number): Tier?
	local list = Gears.TIERS[category]
	return if list then list[currentTier + 1] else nil
end

export type Summary = {
	capacity: number,
	deathShare: number,
	hp: number,
	defense: number,
	power: number,
	cdr: number,
	speed: number,
	dashBonus: number,
	recallSeconds: number,
}

function Gears.stats(equipped: { [string]: number }?): Summary
	local g = equipped or {}
	local bp = Gears.get("backpack", math.max(1, g.backpack or 1)) or Gears.TIERS.backpack[1]
	local robe = Gears.get("robe", g.robe or 0)
	local hat = Gears.get("hat", g.hat or 0)
	local boots = Gears.get("boots", g.boots or 0)
	return {
		capacity = bp.capacity or 25,
		deathShare = bp.deathShare or 0.5,
		hp = if robe and robe.hp then robe.hp else 0,
		defense = if robe and robe.defense then robe.defense else 0,
		power = if hat and hat.power then hat.power else 0,
		cdr = if hat and hat.cdr then hat.cdr else 0,
		speed = if boots and boots.speed then boots.speed else 0,
		dashBonus = if boots and boots.dashBonus then boots.dashBonus else 0,
		recallSeconds = if boots and boots.recallSeconds then boots.recallSeconds else 5.0,
	}
end

return Gears
