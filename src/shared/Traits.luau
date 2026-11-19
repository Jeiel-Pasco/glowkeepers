--!strict
-- Pet traits on placed Glowlings (GAME_SYSTEMS §31, D20–D23). Pure: callers pass config and
-- which species sits on which pad, so the server, the client and Lune all run the same rules.
--
-- Family link, Harmonizer, Infuser Overcharge (Aurora Lynx: up to 6 Glowlings), the ×cap on the
-- combined Glow/s multiplier, Guardian grab time and Forager pouches. The night companion traits
-- come later.
--
-- Glowlings wander their base (Shared.Roam), so traits count the whole base: every other
-- Glowling placed there, not pad neighbours. Pads are only the map's Slot numbers (Inventory).

local Traits = {}

export type Species = { id: string, family: string?, trait: string?, minRarity: string? }
export type Placed = { [number]: string } -- pad → species id

-- Every other occupied pad in the base, in pad order.
function Traits.mates(placed: Placed, pad: number): { number }
	local list = {}
	for other in placed do
		if other ~= pad then
			table.insert(list, other)
		end
	end
	table.sort(list)
	return list
end

-- Rarity index of a species' floor (1 = Common when unset).
function Traits.floor(cfg: any, species: Species?): number
	local id = if species ~= nil then species.minRarity else nil
	if id ~= nil then
		for i, rarity in cfg.rarities do
			if rarity.id == id then
				return i
			end
		end
	end
	return 1
end

local function apex(cfg: any, speciesId: string): any
	return cfg.traits.apex[speciesId]
end

-- The Glow/s multiplier of every occupied pad: family link (per other same-family Glowling in
-- the base) × Harmonizer (a same-family one in the base) × whole-plot bonus,
-- at most cfg.traits.cap.
function Traits.multipliers(
	cfg: any,
	species: { [string]: Species },
	placed: Placed,
	overcharged: { [number]: any }?
): { [number]: number }
	local t = cfg.traits
	local plotGlow = 0 -- whole-plot bonuses don't stack: the highest counts
	for _, id in placed do
		local a = apex(cfg, id)
		if a ~= nil and a.plotGlow ~= nil then
			plotGlow = math.max(plotGlow, a.plotGlow)
		end
	end
	local result = {}
	for pad, id in placed do
		local mine = species[id]
		local family = if mine ~= nil then mine.family else nil
		local same, harmonized = 0, false
		for _, n in Traits.mates(placed, pad) do
			local other = placed[n]
			local theirs = species[other]
			if theirs ~= nil and family ~= nil and theirs.family == family then
				same += 1
				-- An apex Harmonizer gives its whole-plot bonus instead.
				if theirs.trait == "Harmonizer" and apex(cfg, other) == nil then
					harmonized = true
				end
			end
		end
		local link = 1 + math.min(t.familyLinkMax, t.familyLinkPer * same)
		local harmony = if harmonized then 1 + t.harmonizer else 1
		local over = if overcharged ~= nil and overcharged[pad] ~= nil then t.infuser.mult else 1
		result[pad] = math.min(t.cap, link * harmony * (1 + plotGlow) * over)
	end
	return result
end

-- Extra grab seconds on `pad` from Guardians: the best one in the base (+more for a floor of
-- Rare or higher), plus the best whole-plot bonus on display pads; at most guardianMax.
function Traits.grabBonus(
	cfg: any,
	species: { [string]: Species },
	placed: Placed,
	_pad: number, -- every display Glowling in the base gets the same bonus
	display: boolean
): number
	local t = cfg.traits
	local rare = 3
	local localBonus = 0
	local function consider(id: string?)
		local s = if id ~= nil then species[id] else nil
		if s ~= nil and s.trait == "Guardian" and apex(cfg, s.id) == nil then
			local bonus = if Traits.floor(cfg, s) >= rare then t.guardianHigh else t.guardian
			localBonus = math.max(localBonus, bonus)
		end
	end
	for _, id in placed do
		consider(id)
	end
	local plotBonus = 0
	if display then
		for _, id in placed do
			local a = apex(cfg, id)
			if a ~= nil and a.plotGrab ~= nil then
				plotBonus = math.max(plotBonus, a.plotGrab)
			end
		end
	end
	return math.min(t.guardianMax, localBonus + plotBonus)
end

-- Timers for Infusers and Foragers, and the Overcharges running, for one plot. Not saved: a
-- rejoin starts the timers again (§31). `infuse`/`forage` are pad → { id, at } (the Glowling the
-- timer belongs to, and when it fires next); `over` is pad → { id, ends }.
export type Timers = {
	infuse: { [number]: { id: string, at: number } },
	forage: { [number]: { id: string, at: number } },
	over: { [number]: { id: string, ends: number } },
}

function Traits.newTimers(): Timers
	return { infuse = {}, forage = {}, over = {} }
end

-- Keeps `timers[pad]` for the Glowling now on the pad; a new Glowling starts a fresh period.
-- Returns true when the timer is due (and restarts it).
local function due(
	list: { [number]: { id: string, at: number } },
	pad: number,
	id: string,
	every: number,
	now: number
): boolean
	local timer = list[pad]
	if timer == nil or timer.id ~= id then
		list[pad] = { id = id, at = now + every }
		return false
	end
	if now >= timer.at then
		timer.at = now + every
		return true
	end
	return false
end

-- Advances the timers to `now`. `ids` is pad → Glowling id, `placed` pad → species id (the same
-- pads). Overcharges end after their time or when their Glowling leaves the pad; Infusers start
-- new ones on another Glowling in the base (Aurora Lynx: up to infuseTargets of them) that isn't
-- already overcharged. Returns whether the set of Overcharges changed, and the Forager pads whose
-- pouch is ready.
function Traits.step(
	cfg: any,
	species: { [string]: Species },
	placed: Placed,
	ids: { [number]: string },
	timers: Timers,
	now: number,
	rng: () -> number
): (boolean, { number })
	local t = cfg.traits
	local changed = false
	for pad, over in timers.over do
		if now >= over.ends or ids[pad] ~= over.id then
			timers.over[pad] = nil
			changed = true
		end
	end
	for _, list in { timers.infuse, timers.forage } do
		for pad, timer in list do
			if ids[pad] ~= timer.id then
				list[pad] = nil
			end
		end
	end

	local function overcharge(candidates: { number }, count: number)
		local free = {}
		for _, pad in candidates do
			if ids[pad] ~= nil and timers.over[pad] == nil then
				table.insert(free, pad)
			end
		end
		for _ = 1, math.min(count, #free) do
			local k = math.min(#free, 1 + math.floor(rng() * #free))
			local pad = table.remove(free, k) :: number
			timers.over[pad] = { id = ids[pad], ends = now + t.infuser.seconds }
			changed = true
		end
	end

	local pouches = {}
	local pads = {}
	for pad in placed do
		table.insert(pads, pad)
	end
	table.sort(pads) -- the same order every run, so a seeded rng gives the same result
	for _, pad in pads do
		local s = species[placed[pad]]
		local id = ids[pad]
		if s ~= nil and id ~= nil then
			local a = apex(cfg, s.id)
			if s.trait == "Infuser" then
				local every = if a ~= nil and a.infuseEvery ~= nil then a.infuseEvery else t.infuser.everySeconds
				if due(timers.infuse, pad, id, every, now) then
					if a ~= nil and a.infuseTargets ~= nil then
						overcharge(pads, a.infuseTargets)
					else
						overcharge(Traits.mates(placed, pad), 1)
					end
				end
			elseif s.trait == "Forager" then
				if due(timers.forage, pad, id, t.forager.everySeconds, now) then
					table.insert(pouches, pad)
				end
			end
		end
	end
	return changed, pouches
end

return Traits
