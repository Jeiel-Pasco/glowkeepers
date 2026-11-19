--!strict
-- Live config (TECH_SPEC §10). Pure: no requires and no engine calls.
--
-- The DataStore value `LiveConfig/current` is merged over `live.defaults` from economy.json:
--   killSwitches  { trading, stealing, serverLuck: boolean, products: { [key]: boolean } }
--   event         { id, start, end, luckMult?, embersMult?, spawnMult?, glowMult?, passXpMult?, moonlit? }
--   limitedSpecies { week, species }
--   codes         { [CODE]: { embers?, lure?, expires? } }
-- Anything malformed is dropped (a bad edit must never break servers): unknown kill switches,
-- non-boolean switches, an event without id/start/end, multipliers outside (0, live.maxMult].

local LiveConfig = {}

export type Live = {
	killSwitches: { [string]: any },
	event: { [string]: any }?,
	limitedSpecies: { week: string, species: string }?,
	codes: { [string]: any },
}

local function copyDefaults(cfg: any): Live
	local d = cfg.live.defaults
	local products = table.clone(d.killSwitches.products)
	local switches: { [string]: any } = { products = products }
	for key, on in d.killSwitches do
		if key ~= "products" then
			switches[key] = on
		end
	end
	return { killSwitches = switches, event = nil, limitedSpecies = nil, codes = {} }
end

local function cleanEvent(cfg: any, raw: any): { [string]: any }?
	if type(raw) ~= "table" or type(raw.id) ~= "string" then
		return nil
	end
	local start, finish = tonumber(raw.start), tonumber(raw["end"])
	if start == nil or finish == nil or finish <= start then
		return nil
	end
	local event: { [string]: any } = { id = raw.id, start = start, ["end"] = finish, moonlit = raw.moonlit == true }
	for _, key in cfg.live.multKeys do
		local value = tonumber(raw[key])
		if value ~= nil and value > 0 and value <= cfg.live.maxMult then
			event[key] = value
		end
	end
	return event
end

-- The effective live config: defaults with `raw` (decoded JSON, or nil) merged over them.
function LiveConfig.merge(cfg: any, raw: any): Live
	local live = copyDefaults(cfg)
	if type(raw) ~= "table" then
		return live
	end
	if type(raw.killSwitches) == "table" then
		for key, value in raw.killSwitches do
			if key == "products" and type(value) == "table" then
				for product, off in value do
					if type(product) == "string" and type(off) == "boolean" then
						live.killSwitches.products[product] = off
					end
				end
			elseif key ~= "products" and type(value) == "boolean" and live.killSwitches[key] ~= nil then
				live.killSwitches[key] = value
			end
		end
	end
	live.event = cleanEvent(cfg, raw.event)
	local limited = raw.limitedSpecies
	if type(limited) == "table" and type(limited.week) == "string" and type(limited.species) == "string" then
		live.limitedSpecies = { week = limited.week, species = limited.species }
	end
	if type(raw.codes) == "table" then
		for code, entry in raw.codes do
			if type(code) == "string" and type(entry) == "table" then
				live.codes[string.upper(code)] = entry
			end
		end
	end
	return live
end

-- Whether a feature is switched off ("stealing", "trading", "serverLuck").
function LiveConfig.killed(live: Live, name: string): boolean
	return live.killSwitches[name] == true
end

function LiveConfig.productKilled(live: Live, product: string): boolean
	return live.killSwitches.products[product] == true
end

-- The event running at `unix`, or nil.
function LiveConfig.event(live: Live, unix: number): { [string]: any }?
	local event = live.event
	if event ~= nil and unix >= event.start and unix < event["end"] then
		return event
	end
	return nil
end

-- An event multiplier ("luckMult", ...) at `unix`; 1 with no event or no such key.
function LiveConfig.mult(live: Live, key: string, unix: number): number
	local event = LiveConfig.event(live, unix)
	return if event ~= nil and event[key] ~= nil then event[key] else 1
end

return LiveConfig
