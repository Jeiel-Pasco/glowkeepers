--!strict
-- Save data: the v1 template, migrations, and load-time repair (TECH_SPEC §5).
--
-- Pure (no requires, no engine calls), so the Lune tests can feed it broken and old saves.
-- Rules:
--   * Repair on load; never error. NaN, infinity and negatives become 0, whole-number fields
--     are floored, levels are clamped to their current max, broken records are dropped.
--   * Migrations only ever add or fill fields (TECH_SPEC §12). An older build that loads a newer
--     save leaves its version alone and runs only the non-destructive repairs, so a rollback
--     can't delete anything the newer build wrote.
--   * Saved maps never use sparse number keys (see Types.luau); slot maps use "1", "2", ...

local Schema = {}

Schema.VERSION = 1

local MAX_RECEIPTS = 200
local LAST_FTUE_STEP = 10

-- Keys whose numbers may hold fractions. Every other number in the template is whole.
local FRACTIONAL = {
	glow = true,
	glowSinceRebirth = true,
	lifetimeGlow = true,
	lastIncomePerSec = true,
	music = true,
	sfx = true,
	playSeconds = true,
}

-- Never sent to the client.
local PRIVATE = { receipts = true, flags = true }

-- MIGRATIONS[n] upgrades a save from version n to n + 1, in place. Add or fill fields only.
local MIGRATIONS: { [number]: (data: any) -> () } = {
	-- [1] = function(data) data.example = data.example or 0 end, -- v1 → v2
}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = deepCopy(item)
	end
	return copy
end
Schema.deepCopy = deepCopy

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isWhole(value: any, low: number, high: number): boolean
	return isFiniteNumber(value) and value % 1 == 0 and value >= low and value <= high
end

function Schema.template(): any
	return {
		v = Schema.VERSION,
		glow = 0,
		glowSinceRebirth = 0,
		lifetimeGlow = 0,
		embers = 0,
		embersBoughtLifetime = 0,
		stars = 0,
		up = { lantern = 0, boots = 0, slots = 0 },
		lockCharges = 0,
		glowlings = {},
		display = {},
		vault = {},
		pity = { sinceLegendary = 0 },
		dex = {},
		dexClaimed = {},
		decor = { owned = {}, placed = {} },
		baseName = { a = 0, n = 0 },
		quests = { day = 0, daily = {}, week = 0, weekly = {} },
		gift = { claimed = 0, lastDay = 0 },
		pass = { season = 0, xp = 0, premium = false, free = {}, prem = {} },
		firstJoin = 0,
		lastSeen = 0,
		lastIncomePerSec = 0,
		playDays = 0,
		lastPlayDay = 0,
		shield = { active = true, playSeconds = 0 }, -- new players start shielded (§11)
		ftue = { step = 0, done = false },
		stats = {
			catches = 0,
			steals = 0,
			stolenFrom = 0,
			revives = 0,
			nightsSurvived = 0,
			firesLost = 0,
			rebirths = 0,
			trades = 0,
			piecesFed = 0,
		},
		daily = { day = 0, buys = {} },
		receipts = {},
		settings = { calm = false, reducedFlash = false, music = 0.8, sfx = 1, breakReminder = true },
		notifyOptIn = false,
		flags = {},
	}
end

function Schema.isPrivate(key: string): boolean
	return PRIVATE[key] == true
end

-- Runs the migrations a save needs. Returns notes for the log.
function Schema.migrate(data: any): { string }
	local notes = {}
	local version = data.v
	if not isWhole(version, 1, math.huge) then
		table.insert(notes, `v: {tostring(version)} is invalid, treated as 1`)
		version = 1
	end
	if version > Schema.VERSION then
		table.insert(notes, `v{version} is newer than this build (v{Schema.VERSION}); left as is`)
		data.v = version
		return notes
	end
	while version < Schema.VERSION do
		local step = MIGRATIONS[version]
		assert(step ~= nil, `missing migration from v{version}`)
		step(data)
		version += 1
		table.insert(notes, `migrated to v{version}`)
	end
	data.v = version
	return notes
end

-- Fills keys that are missing (nil), recursively, from the template. ProfileStore's
-- profile:Reconcile() does the same; this one serves the in-memory store and the tests.
function Schema.reconcile(data: any, template: any)
	for key, default in template do
		local value = data[key]
		if value == nil then
			data[key] = deepCopy(default)
		elseif type(default) == "table" and type(value) == "table" and next(default) ~= nil then
			Schema.reconcile(value, default)
		end
	end
end

-- Types and numbers, for every key the template defines.
local function repairShape(data: any, template: any, path: string, notes: { string })
	for key, default in template do
		local value = data[key]
		local here = if path == "" then key else `{path}.{key}`
		if type(value) ~= type(default) then
			data[key] = deepCopy(default)
			if value ~= nil then
				table.insert(notes, `{here}: wrong type ({type(value)}), reset`)
			end
		elseif type(default) == "number" then
			local fixed = value
			if not isFiniteNumber(value) or value < 0 then
				fixed = 0
			elseif not FRACTIONAL[key] then
				fixed = math.floor(value)
			end
			if fixed ~= value then
				data[key] = fixed
				table.insert(notes, `{here}: {tostring(value)} → {fixed}`)
			end
		elseif type(default) == "table" and next(default) ~= nil then
			repairShape(value, default, here, notes)
		end
	end
end

local function clampTo(tbl: any, key: string, max: number, label: string, notes: { string })
	if tbl[key] > max then
		table.insert(notes, `{label}: {tbl[key]} → {max}`)
		tbl[key] = max
	end
end

local function repairGlowlings(data: any, cfg: any, notes: { string })
	local rarities, mutations = #cfg.rarities, #cfg.mutations
	for key, record in data.glowlings do
		local valid = type(key) == "string"
			and type(record) == "table"
			and type(record.sp) == "string"
			and isWhole(record.r, 1, rarities)
			and isWhole(record.m, 0, mutations)
			and isFiniteNumber(record.s)
		if not valid then
			data.glowlings[key] = nil
			table.insert(notes, `glowling {tostring(key)}: invalid record removed`)
			continue
		end
		if record.id ~= key then
			record.id = key
			table.insert(notes, `glowling {key}: id fixed`)
		end
		local size = math.clamp(math.floor(record.s * 100 + 0.5) / 100, cfg.size.min, cfg.size.max)
		if size ~= record.s then
			record.s = size
			table.insert(notes, `glowling {key}: size fixed`)
		end
		if type(record.src) ~= "string" then
			record.src = "unknown"
		end
		if not isFiniteNumber(record.at) then
			record.at = 0
		end
		if not isFiniteNumber(record.by) then
			record.by = 0
		end
		if record.tradeLockUntil ~= nil and not isFiniteNumber(record.tradeLockUntil) then
			record.tradeLockUntil = nil
		end
	end
end

-- Slot keys must be "1".."slotCount", point at an owned Glowling, and hold each id once
-- (the vault wins over display). Exact vault and display counts depend on passes, which
-- PlotService checks at runtime; here an index only has to fit the total slot count.
-- A Glowling dropped from a slot stays owned and goes back to storage.
local function repairSlots(data: any, map: any, label: string, slotCount: number, placed: { [string]: boolean }, notes: { string })
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	for _, key in keys do
		local id = map[key]
		map[key] = nil
		local index = tonumber(key)
		local ok = index ~= nil
			and index % 1 == 0
			and index >= 1
			and index <= slotCount
			and type(id) == "string"
			and data.glowlings[id] ~= nil
			and not placed[id]
		if ok then
			local canonical = tostring(index)
			if map[canonical] ~= nil then
				ok = false
			else
				map[canonical] = id
				placed[id] = true
				if canonical ~= key then
					table.insert(notes, `{label}[{tostring(key)}]: key fixed`)
				end
			end
		end
		if not ok then
			table.insert(notes, `{label}[{tostring(key)}]: removed`)
		end
	end
end

local function repairReceipts(data: any, notes: { string })
	local ids = {}
	for id, at in data.receipts do
		if type(id) ~= "string" or not isFiniteNumber(at) then
			data.receipts[id] = nil
		else
			table.insert(ids, id)
		end
	end
	if #ids > MAX_RECEIPTS then
		table.sort(ids, function(a, b)
			return data.receipts[a] > data.receipts[b]
		end)
		for i = MAX_RECEIPTS + 1, #ids do
			data.receipts[ids[i]] = nil
		end
		table.insert(notes, `receipts: kept the newest {MAX_RECEIPTS} of {#ids}`)
	end
end

-- Repairs a loaded save in place. `cfg` is config/economy.json. Returns notes for the log.
function Schema.repair(data: any, cfg: any): { string }
	local notes = {}
	repairShape(data, Schema.template(), "", notes)

	-- Optional fields.
	if data.ftue.path ~= nil and type(data.ftue.path) ~= "string" then
		data.ftue.path = nil
	end
	if data.crewId ~= nil and type(data.crewId) ~= "string" then
		data.crewId = nil
	end

	if data.v > Schema.VERSION then
		return notes -- a newer build wrote this save: no clamps or removals (see the header)
	end

	clampTo(data.up, "lantern", cfg.upgrades.lantern.max, "up.lantern", notes)
	clampTo(data.up, "boots", cfg.upgrades.boots.max, "up.boots", notes)
	clampTo(data.up, "slots", cfg.upgrades.slots.max - cfg.upgrades.slots.start, "up.slots", notes)
	clampTo(data, "lockCharges", cfg.lock.maxCharges, "lockCharges", notes)
	clampTo(data.pity, "sinceLegendary", cfg.pity.legendaryAfterNightCatches, "pity.sinceLegendary", notes)
	clampTo(data.settings, "music", 1, "settings.music", notes)
	clampTo(data.settings, "sfx", 1, "settings.sfx", notes)
	clampTo(data.shield, "playSeconds", cfg.shield.maxPlaySeconds, "shield.playSeconds", notes)
	clampTo(data.ftue, "step", LAST_FTUE_STEP, "ftue.step", notes)

	repairGlowlings(data, cfg, notes)
	local slotCount = cfg.upgrades.slots.start + data.up.slots
	local placed = {}
	repairSlots(data, data.vault, "vault", slotCount, placed, notes)
	repairSlots(data, data.display, "display", slotCount, placed, notes)

	for species, entry in data.dex do
		if type(species) ~= "string" or type(entry) ~= "table" or not isWhole(entry.r, 0, 2 ^ 31) or not isWhole(entry.m, 0, 2 ^ 31) then
			data.dex[species] = nil
			table.insert(notes, `dex {tostring(species)}: removed`)
		end
	end
	repairReceipts(data, notes)
	return notes
end

-- Join bookkeeping, before any gameplay. Returns the seconds away (0 for a first join, or a
-- missing or future lastSeen, so a bad clock never pays) and whether this is the first session.
function Schema.onJoin(data: any, now: number): (number, boolean)
	local firstSession = data.firstJoin == 0
	local away = 0
	if firstSession then
		data.firstJoin = now
	elseif data.lastSeen > 0 and data.lastSeen <= now then
		away = now - data.lastSeen
	end
	data.lastSeen = now
	local day = now // 86400 -- UTC day
	if data.lastPlayDay ~= day then
		data.playDays += 1
		data.lastPlayDay = day
	end
	return away, firstSession
end

-- What the owner's client receives: everything except the private keys. Shallow, because
-- FireClient serialises the table immediately.
function Schema.clientView(data: any): any
	local view = {}
	for key, value in data do
		if not PRIVATE[key] then
			view[key] = value
		end
	end
	return view
end

return Schema
