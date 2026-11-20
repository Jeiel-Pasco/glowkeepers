--!strict
-- Carried and banked loot (GDD "Loot, camp and risk"). Pure.
--
-- A bag is { coins, ink = { [type]: n }, frag = { [type]: n } }. What you pick up on a trip is
-- carried until you bank it at your camp. Death drops half of it; a raider's hit steals some.

local Loot = {}

export type Bag = { coins: number, ink: { [string]: number }, frag: { [string]: number } }

Loot.DEATH_SHARE = 0.5
Loot.RAIDER_SHARE = 0.25 -- of each carried thing, per raider hit
Loot.RAIDER_BONUS = 0.1 -- the victim gets this much extra back
Loot.RAIDER_MIN_CARRY = 20 -- raiders only chase players carrying at least this value
Loot.INK_VALUE = 10 -- coins an ink is "worth" when raiders pick targets

function Loot.empty(): Bag
	return { coins = 0, ink = {}, frag = {} }
end

local function eachCount(bag: Bag, fn: (map: { [string]: number }, key: string, n: number) -> ())
	for key, n in bag.ink do
		fn(bag.ink, key, n)
	end
	for key, n in bag.frag do
		fn(bag.frag, key, n)
	end
end

function Loot.isEmpty(bag: Bag): boolean
	if bag.coins > 0 then
		return false
	end
	for _, n in bag.ink do
		if n > 0 then
			return false
		end
	end
	for _, n in bag.frag do
		if n > 0 then
			return false
		end
	end
	return true
end

-- A rough value, for raiders choosing whom to chase.
function Loot.value(bag: Bag): number
	local v = bag.coins
	for _, n in bag.ink do
		v += n * Loot.INK_VALUE
	end
	for _, n in bag.frag do
		v += n * Loot.INK_VALUE * 5
	end
	return v
end

-- Adds `from` into `into` (both bags), in place.
function Loot.add(into: Bag, from: Bag)
	into.coins += from.coins
	for key, n in from.ink do
		into.ink[key] = (into.ink[key] or 0) + n
	end
	for key, n in from.frag do
		into.frag[key] = (into.frag[key] or 0) + n
	end
end

-- Takes `share` (rounded down) of everything in `bag` out into a new bag.
function Loot.take(bag: Bag, share: number): Bag
	local out = Loot.empty()
	local coins = math.floor(bag.coins * share)
	bag.coins -= coins
	out.coins = coins
	eachCount(bag, function(map, key, n)
		local taken = math.floor(n * share)
		if taken > 0 then
			map[key] = n - taken
			local target = if map == bag.ink then out.ink else out.frag
			target[key] = taken
		end
	end)
	return out
end

-- What a victim gets back for killing the raider that robbed them: all of it plus the bonus.
function Loot.recovered(stolen: Bag): Bag
	local out = Loot.empty()
	Loot.add(out, stolen)
	out.coins += math.floor(stolen.coins * Loot.RAIDER_BONUS)
	return out
end

-- Repairs a saved bag: whole, finite, non-negative numbers; drops junk keys.
function Loot.repair(bag: any): Bag
	local out = Loot.empty()
	if type(bag) ~= "table" then
		return out
	end
	local function clean(n: any): number
		if type(n) ~= "number" or n ~= n or n == math.huge or n < 0 then
			return 0
		end
		return math.floor(n)
	end
	out.coins = clean(bag.coins)
	for _, field in { "ink", "frag" } do
		if type(bag[field]) == "table" then
			for key, n in bag[field] do
				if type(key) == "string" and clean(n) > 0 then
					(out :: any)[field][key] = clean(n)
				end
			end
		end
	end
	return out
end

return Loot
