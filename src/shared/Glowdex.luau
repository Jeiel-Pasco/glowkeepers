--!strict
-- Glowdex rules (GAME_SYSTEMS §16, D10). Pure: no requires and no engine calls.
--
-- `dex[species] = { r, m }` are bitmasks: bit r-1 of `r` is set once that species has been
-- credited at rarity r (1 Common .. 7 Secret), and bit m-1 of `m` for mutation m (1 Golden,
-- 2 Rainbow, ...): the stamps. Entries count rarity bits only (40 species × 7 = 280).
--
-- A species page reaches tier t (Bronze, Silver, Gold, Radiant) once it has every rarity up to
-- glowdex.tiers[t].needs. Tiers are claimed one at a time, in order: `dexClaimed[species]` is
-- the highest tier claimed. Milestones on total entries are claimed once each, saved in
-- `dexClaimed` under "@<entries>" (e.g. "@10"), which can never clash with a species id.

local Glowdex = {}

local function has(mask: number, index: number): boolean
	return bit32.btest(mask, bit32.lshift(1, index - 1))
end

local function popcount(mask: number): number
	local n = 0
	while mask ~= 0 do
		mask = bit32.band(mask, mask - 1)
		n += 1
	end
	return n
end

-- Whether a Glowling from `src` counts (night, lure, event, tutorial; not steal, trade, fuse).
function Glowdex.credits(cfg: any, src: string): boolean
	return table.find(cfg.glowdex.credit, src) ~= nil
end

-- The entry after crediting rarity r and mutation m (0 = none), and whether anything is new.
function Glowdex.record(entry: any, r: number, m: number): ({ r: number, m: number }, boolean)
	local rMask = if type(entry) == "table" then tonumber(entry.r) or 0 else 0
	local mMask = if type(entry) == "table" then tonumber(entry.m) or 0 else 0
	local newR = bit32.bor(rMask, bit32.lshift(1, r - 1))
	local newM = if m > 0 then bit32.bor(mMask, bit32.lshift(1, m - 1)) else mMask
	return { r = newR, m = newM }, newR ~= rMask or newM ~= mMask
end

function Glowdex.hasRarity(entry: any, r: number): boolean
	return type(entry) == "table" and has(tonumber(entry.r) or 0, r)
end

function Glowdex.hasMutation(entry: any, m: number): boolean
	return type(entry) == "table" and has(tonumber(entry.m) or 0, m)
end

-- The highest page tier this entry has reached (0 = none). Rarities below the species' floor
-- (`floor`, a rarity index, default 1) can't be caught, so they aren't needed; a tier below the
-- floor needs just the floor rarity (D18).
function Glowdex.tier(cfg: any, entry: any, floor: number?): number
	local from = floor or 1
	local reached = 0
	for t, tier in cfg.glowdex.tiers do
		for r = from, math.max(tier.needs, from) do
			if not Glowdex.hasRarity(entry, r) then
				return reached
			end
		end
		reached = t
	end
	return reached
end

-- Entries a full Glowdex has: each species from its floor up to the top rarity (254 at launch).
-- `floorOf(species)` returns the floor as a rarity index.
function Glowdex.reachable(cfg: any, speciesCfg: any, floorOf: (any) -> number): number
	local n = 0
	for _, species in speciesCfg.species do
		n += #cfg.rarities - floorOf(species) + 1
	end
	return n
end

-- Total entries: rarity bits across every species.
function Glowdex.entries(dex: any): number
	local n = 0
	for _, entry in dex do
		if type(entry) == "table" then
			n += popcount(tonumber(entry.r) or 0)
		end
	end
	return n
end

-- The next page tier of `species` this player may claim, or nil and "nothing_new".
function Glowdex.canClaimPage(cfg: any, dex: any, claimed: any, species: string, floor: number?): (number?, string?)
	local done = tonumber(claimed[species]) or 0
	if Glowdex.tier(cfg, dex[species], floor) <= done then
		return nil, "nothing_new"
	end
	return done + 1, nil
end

-- Income bonus from claimed pages: +0.5% Bronze, +0.5% Silver, +1% Gold, summed over species.
-- The income multiplier is 1 + this.
function Glowdex.incomeBonus(cfg: any, claimed: any): number
	local sum = 0
	for key, done in claimed do
		if type(key) == "string" and string.sub(key, 1, 1) ~= "@" then
			for t = 1, math.min(tonumber(done) or 0, #cfg.glowdex.tiers) do
				sum += cfg.glowdex.tiers[t].income
			end
		end
	end
	return sum
end

function Glowdex.milestoneKey(entries: number): string
	return `@{entries}`
end

-- Embers for claiming milestone `index`, or nil and a reason ("unknown", "claimed", "not_yet").
function Glowdex.canClaimMilestone(cfg: any, dex: any, claimed: any, index: number): (number?, string?)
	local milestone = cfg.glowdex.milestones[index]
	if milestone == nil then
		return nil, "unknown"
	elseif claimed[Glowdex.milestoneKey(milestone.entries)] ~= nil then
		return nil, "claimed"
	elseif Glowdex.entries(dex) < milestone.entries then
		return nil, "not_yet"
	end
	return milestone.embers, nil
end

return Glowdex
