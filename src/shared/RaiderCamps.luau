--!strict
-- Raider camps (docs/LAYER_ONE.md step 4). Pure rules shared by RaiderCampService and the tests.
--
-- Each server picks ACTIVE camps from Zones.CAMP_SITES, one in each gap between zones (the sites
-- come in threes, one gap each). A camp has a palisade, tents, a fire and a chest, and GUARDS
-- that attack anyone who walks inside. Clearing the guards unlocks the chest once per player;
-- the whole camp comes back RESPAWN seconds after it is cleared.

-- Vector3 is a Roblox global; under Lune (tests) it comes from @lune/roblox.
-- selene: allow(incorrect_standard_library_use, shadowing)
local Vector3 = if script ~= nil then Vector3 else (require("@lune/roblox") :: any).Vector3
-- In Roblox a sibling ModuleScript; under Lune (tests) a path.
-- selene: allow(incorrect_standard_library_use)
local Zones = if script ~= nil then require(script.Parent:WaitForChild("Zones")) :: any else require("./Zones")

local RaiderCamps = {}

RaiderCamps.ACTIVE = 3
RaiderCamps.RESPAWN = 90
RaiderCamps.INK_CHANCE = 0.1 -- the chest's "low chance" of ink, otherwise coins
RaiderCamps.INK_TYPES = { "Fire", "Water", "Leaf" }
RaiderCamps.WALL_R = Zones.CAMP_SITE_R - 4 -- the palisade; guards attack anyone inside it

-- Guards round the camp centre: `ring` studs out at `a` degrees (0 faces away from the camp
-- entrance, which faces the campfire).
RaiderCamps.GUARDS = {
	{ kind = "raider_brute", ring = 8, a = 150 },
	{ kind = "raider_brute", ring = 8, a = 210 },
	{ kind = "raider_archer", ring = 15, a = 40 },
	{ kind = "raider_archer", ring = 15, a = 320 },
}

-- Which CAMP_SITES to use: one per gap, chosen by `rng` (a function returning 1..n).
function RaiderCamps.pick(rng: (n: number) -> number): { number }
	local out = {}
	local perGap = #Zones.CAMP_SITES // RaiderCamps.ACTIVE
	for gap = 0, RaiderCamps.ACTIVE - 1 do
		table.insert(out, gap * perGap + rng(perGap))
	end
	return out
end

-- Guards are tougher further out: level 4 nearest the camp ring, up to 8 deeper in the wilds.
function RaiderCamps.level(site: { r: number }): number
	local t = math.clamp((site.r - 135) / (225 - 135), 0, 1)
	return 4 + math.floor(t * 4 + 0.5)
end

-- Where a guard stands, given the camp centre and the direction of its entrance.
function RaiderCamps.guardPos(centre: Vector3, entrance: Vector3, guard: { ring: number, a: number }): Vector3
	local back = -entrance
	local a = math.rad(guard.a)
	local side = Vector3.new(-back.Z, 0, back.X)
	return centre + (back * math.cos(a) + side * math.sin(a)) * guard.ring
end

-- The chest's loot for one player: `roll` and `pickRoll` are 0..1 random numbers.
function RaiderCamps.chestBag(level: number, roll: number, pickRoll: number): any
	local bag = { coins = 0, ink = {}, frag = {} }
	if roll < RaiderCamps.INK_CHANCE then
		local i = math.clamp(math.floor(pickRoll * #RaiderCamps.INK_TYPES) + 1, 1, #RaiderCamps.INK_TYPES)
		bag.ink[RaiderCamps.INK_TYPES[i]] = 1
	else
		bag.coins = 15 + level * 5 + math.floor(pickRoll * 10)
	end
	return bag
end

return RaiderCamps
