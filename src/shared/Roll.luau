--!strict
-- Rarity, mutation and size rolls (GAME_SYSTEMS §4 and §5).
--
-- Pure: no requires and no engine calls, so the Lune tests run exactly the code the server runs.
-- `cfg` is config/economy.json. `rng` returns a number in [0, 1), for example
-- `function() return random:NextNumber() end` on the server.
-- Rarity tiers are 1-based: 1 = Common ... 7 = Secret. Mutation 0 = none, otherwise an index
-- into cfg.mutations (1 Golden, 2 Rainbow, 3 Moonlit).

local Roll = {}

export type Rng = () -> number
export type Result = { r: number, m: number, s: number }

local function tierChance(cfg: any, luck: number, tier: number): number
	local p = 1 / cfg.rarities[tier].oneIn
	if tier >= cfg.luck.appliesFromRarity then
		p = math.min(p * luck, cfg.luck.tierCap)
	end
	return p
end

function Roll.rarityIndex(cfg: any, id: string): number
	for i, rarity in cfg.rarities do
		if rarity.id == id then
			return i
		end
	end
	error(`unknown rarity id {id}`)
end

local function checkFloor(cfg: any, floor: number?): number
	local low = floor or 1
	assert(low >= 1 and low <= #cfg.rarities and low % 1 == 0, "rarity floor out of range")
	return low
end

-- Rarest first, from Secret down to the floor. Each tier gets one draw; the floor tier is
-- returned when every rarer check fails. This is the algorithm sim.py and sim_v3.py use.
function Roll.rarity(cfg: any, luck: number, floor: number?, rng: Rng): number
	local low = checkFloor(cfg, floor)
	for tier = #cfg.rarities, low + 1, -1 do
		if rng() < tierChance(cfg, luck, tier) then
			return tier
		end
	end
	return low
end

-- Exact probability of each tier for the same algorithm. The odds tab shows these numbers,
-- so the shown odds and the real odds come from one piece of code.
function Roll.distribution(cfg: any, luck: number, floor: number?): { number }
	local low = checkFloor(cfg, floor)
	local n = #cfg.rarities
	local probs = table.create(n, 0)
	local remaining = 1
	for tier = n, low + 1, -1 do
		local p = tierChance(cfg, luck, tier)
		probs[tier] = remaining * p
		remaining *= 1 - p
	end
	probs[low] = remaining
	return probs
end

-- Night catch with pity (§5). After `pity.legendaryAfterNightCatches` night catches below
-- Legendary, the next night catch is at least Legendary. Returns the tier and the new counter.
function Roll.nightRarity(cfg: any, luck: number, pity: number, rng: Rng): (number, number)
	local legendary = Roll.rarityIndex(cfg, "Legendary")
	local floor = if pity >= cfg.pity.legendaryAfterNightCatches then legendary else 1
	local tier = Roll.rarity(cfg, luck, floor, rng)
	return tier, if tier >= legendary then 0 else pity + 1
end

function Roll.nightOdds(cfg: any, luck: number, pity: number): { number }
	local legendary = Roll.rarityIndex(cfg, "Legendary")
	local floor = if pity >= cfg.pity.legendaryAfterNightCatches then legendary else 1
	return Roll.distribution(cfg, luck, floor)
end

-- Lure roll: the floor is the lure's tier (1..lures.maxFloor) and the result can land higher (D4).
-- lures.resultCap, when set, caps the result (the rejected D4 variant; null at launch).
function Roll.lureRarity(cfg: any, luck: number, floor: number, rng: Rng): number
	assert(floor <= cfg.lures.maxFloor, "lure floor above lures.maxFloor")
	local tier = Roll.rarity(cfg, luck, floor, rng)
	local cap = cfg.lures.resultCap
	if cap ~= nil and tier > cap then
		tier = cap
	end
	return tier
end

function Roll.lureOdds(cfg: any, luck: number, floor: number): { number }
	local probs = Roll.distribution(cfg, luck, floor)
	local cap = cfg.lures.resultCap
	if cap ~= nil then
		for tier = cap + 1, #probs do
			probs[cap] += probs[tier]
			probs[tier] = 0
		end
	end
	return probs
end

-- Non-event mutation indices, rarest first (largest oneIn first).
local function mutationOrder(cfg: any): { number }
	local order = {}
	for i, mutation in cfg.mutations do
		if not mutation.eventOnly then
			table.insert(order, i)
		end
	end
	table.sort(order, function(a, b)
		return cfg.mutations[a].oneIn > cfg.mutations[b].oneIn
	end)
	return order
end

-- One draw decides the mutation, rarest first: under 1/200 Rainbow, else under 1/20 Golden,
-- so Golden is 4.5% (matches the sim). Event-only mutations listed as active in `events`
-- (e.g. { Moonlit = true }) are checked first, each with its own draw. Luck never applies.
function Roll.mutation(cfg: any, rng: Rng, events: { [string]: boolean }?): number
	if events then
		for i, mutation in cfg.mutations do
			if mutation.eventOnly and events[mutation.id] and rng() < 1 / mutation.oneIn then
				return i
			end
		end
	end
	local r = rng()
	for _, i in mutationOrder(cfg) do
		if r < 1 / cfg.mutations[i].oneIn then
			return i
		end
	end
	return 0
end

-- Exact mutation odds; index 0 is "no mutation".
function Roll.mutationOdds(cfg: any, events: { [string]: boolean }?): { [number]: number }
	local odds: { [number]: number } = {}
	local remaining = 1
	if events then
		for i, mutation in cfg.mutations do
			if mutation.eventOnly and events[mutation.id] then
				local p = 1 / mutation.oneIn
				odds[i] = remaining * p
				remaining *= 1 - p
			end
		end
	end
	local previous = 0
	for _, i in mutationOrder(cfg) do
		local threshold = 1 / cfg.mutations[i].oneIn
		odds[i] = remaining * (threshold - previous)
		previous = threshold
	end
	odds[0] = remaining * (1 - previous)
	return odds
end

-- Uniform between size.min and size.max, rounded to 2 decimal places.
function Roll.size(cfg: any, rng: Rng): number
	local low, high = cfg.size.min, cfg.size.max
	return math.floor((low + rng() * (high - low)) * 100 + 0.5) / 100
end

-- Display label for a size (cosmetic only).
function Roll.sizeLabel(size: number): string?
	if size >= 1.28 then
		return "Huge"
	elseif size >= 1.2 then
		return "Big"
	elseif size < 0.9 then
		return "Tiny"
	end
	return nil
end

-- Species ids in `pool` ("Clearing", "Deepwood", ...), in config order. `speciesCfg` is
-- config/species.json.
function Roll.pool(speciesCfg: any, pool: string): { string }
	local ids = {}
	for _, species in speciesCfg.species do
		if species.pool == pool then
			table.insert(ids, species.id)
		end
	end
	return ids
end

-- One species from a pool, uniformly. Rarity never depends on the species (CONTENT §A3).
function Roll.species(ids: { string }, rng: Rng): string
	assert(#ids > 0, "empty species pool")
	return ids[math.min(#ids, 1 + math.floor(rng() * #ids))]
end

-- Rarity first, then mutation, then size, each from its own draws (as in the sim).
function Roll.finish(cfg: any, tier: number, rng: Rng, events: { [string]: boolean }?): Result
	return { r = tier, m = Roll.mutation(cfg, rng, events), s = Roll.size(cfg, rng) }
end

return Roll
