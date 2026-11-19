--!strict
-- Events and the daily featured species (GAME_SYSTEMS §21). Pure: no requires.
--
-- The event itself (when, which multipliers) comes from live config (Shared.LiveConfig).
-- The featured species is one Deepwood species per UTC day, rotating through the pool in a
-- fixed order, with 2× spawn weight (events.featuredWeight).

local Events = {}

local DAY = 86400

-- The featured Deepwood species id for the UTC day of `unix`, or nil if the pool is empty.
function Events.featured(speciesCfg: any, unix: number): string?
	local pool = {}
	for _, species in speciesCfg.species do
		if species.pool == "Deepwood" then
			table.insert(pool, species.id)
		end
	end
	if #pool == 0 then
		return nil
	end
	local day = unix // DAY
	-- Step 7 through the pool: every species comes up once per #pool days when 7 ∤ #pool.
	return pool[(day * 7) % #pool + 1]
end

-- One species from `ids`, with `featured` (if in the list) weighted `weight` and the rest 1.
function Events.pickSpecies(ids: { string }, featured: string?, weight: number, rng: () -> number): string
	assert(#ids > 0, "empty species pool")
	local has = featured ~= nil and table.find(ids, featured) ~= nil
	local total = #ids + (if has then weight - 1 else 0)
	local r = rng() * total
	if has then
		if r < weight then
			return featured :: string
		end
		r -= weight
		local rest = {}
		for _, id in ids do
			if id ~= featured then
				table.insert(rest, id)
			end
		end
		return rest[math.min(#rest, 1 + math.floor(r))]
	end
	return ids[math.min(#ids, 1 + math.floor(r))]
end

-- Roll.mutation's event flags for a running event (Moonlit on or off).
function Events.mutationFlags(event: { [string]: any }?): { [string]: boolean }?
	if event ~= nil and event.moonlit then
		return { Moonlit = true }
	end
	return nil
end

return Events
