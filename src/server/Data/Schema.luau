--!strict
-- Save data: the template (GDD v2, the grimoire slice), migrations, and load-time repair.
--
-- Pure (no requires, no engine calls), so the Lune tests can feed it broken and old saves.
-- Rules:
--   * Repair on load; never error. NaN, infinity and negatives become 0, whole-number fields
--     are floored, levels are clamped to their current max, broken records are dropped.
--   * Migrations only ever add or fill fields (TECH_SPEC §12). An older build that loads a newer
--     save leaves its version alone and runs only the non-destructive repairs, so a rollback
--     can't delete anything the newer build wrote.
--   * Saved maps never use sparse number keys; lists are dense arrays.

local Schema = {}

Schema.VERSION = 1

local MAX_RECEIPTS = 200
local MAX_BOOKS = 30
local PAGES = 4

-- Keys whose numbers may hold fractions. Every other number in the template is whole.
local FRACTIONAL = {
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

local function bag(): any
	return { coins = 0, ink = {}, frag = {} }
end

function Schema.template(): any
	return {
		v = Schema.VERSION,
		level = 1,
		xp = 0,
		stats = { health = 0, power = 0, defense = 0 }, -- stat points spent
		books = { { type = "Neutral", pages = {} } }, -- grimoires; pages = { { sp, lv } }
		equipped = { 1, 0, 0 }, -- book index per equipped slot (0 = empty)
		active = 1, -- the equipped slot in hand
		bank = { coins = 0, ink = { Neutral = 1 }, frag = {} }, -- one free ink for the first write
		carried = bag(), -- picked up on this trip; banked at camp
		stars = 0,
		element = "", -- the starter element, once picked
		quest = { step = 1, n = 0 }, -- the tutorial chain (Shared.Quests); step past the end = done
		counts = { kills = 0, deaths = 0, bosses = 0, writes = 0 },
		firstJoin = 0,
		lastSeen = 0,
		playSeconds = 0,
		receipts = {},
		settings = { calm = false, reducedFlash = false, music = 0.8, sfx = 1, breakReminder = true },
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

-- A loot bag: whole, non-negative counts under string keys.
local function cleanBag(value: any): any
	local out = bag()
	local function count(n: any): number
		return if isFiniteNumber(n) and n > 0 then math.floor(n) else 0
	end
	out.coins = count(value.coins)
	for _, field in { "ink", "frag" } do
		if type(value[field]) == "table" then
			for key, n in value[field] do
				if type(key) == "string" and count(n) > 0 then
					out[field][key] = count(n)
				end
			end
		end
	end
	return out
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

function Schema.repair(data: any): { string }
	local notes = {}
	repairShape(data, Schema.template(), "", notes)
	data.level = math.clamp(data.level, 1, 60)
	data.bank = cleanBag(data.bank)
	data.carried = cleanBag(data.carried)
	-- Books: a known type and at most 4 well-formed pages each.
	local books = {}
	for _, book in data.books do
		if type(book) == "table" and type(book.type) == "string" and type(book.pages) == "table" then
			local pages = {}
			for _, page in book.pages do
				if
					#pages < PAGES
					and type(page) == "table"
					and type(page.sp) == "string"
					and isWhole(page.lv, 1, 5)
				then
					table.insert(pages, { sp = page.sp, lv = page.lv })
				end
			end
			table.insert(books, { type = book.type, pages = pages })
		end
		if #books >= MAX_BOOKS then
			break
		end
	end
	if #books == 0 then
		books = { { type = "Neutral", pages = {} } }
		table.insert(notes, "books: none left, reset to a Neutral grimoire")
	end
	data.books = books
	local equipped = {}
	for i = 1, 3 do
		local index = data.equipped[i]
		equipped[i] = if isWhole(index, 1, #books) and table.find(equipped, index) == nil then index else 0
	end
	if equipped[1] == 0 and equipped[2] == 0 and equipped[3] == 0 then
		equipped[1] = 1
	end
	data.equipped = equipped
	if not isWhole(data.active, 1, 3) or equipped[data.active] == 0 then
		data.active = if equipped[1] ~= 0 then 1 elseif equipped[2] ~= 0 then 2 else 3
	end
	-- Stat points can't exceed what the level earned.
	local spent = data.stats.health + data.stats.power + data.stats.defense
	if spent > (data.level - 1) * 3 then
		data.stats = { health = 0, power = 0, defense = 0 }
		table.insert(notes, "stats: more points spent than earned, reset")
	end
	-- Receipts: keep the newest.
	local receipts = {}
	for key, value in data.receipts do
		if type(key) == "string" and isFiniteNumber(value) then
			table.insert(receipts, { key, value })
		end
	end
	table.sort(receipts, function(a, b)
		return a[2] > b[2]
	end)
	data.receipts = {}
	for i = 1, math.min(#receipts, MAX_RECEIPTS) do
		data.receipts[receipts[i][1]] = receipts[i][2]
	end
	return notes
end

function Schema.onJoin(data: any, now: number): (number, boolean)
	local firstSession = data.firstJoin == 0
	local away = 0
	if firstSession then
		data.firstJoin = now
	elseif data.lastSeen > 0 and data.lastSeen <= now then
		away = now - data.lastSeen
	end
	data.lastSeen = now
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
