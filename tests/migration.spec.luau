-- Save migrations against stored fixtures (IMPLEMENTATION_PLAN §7, TECH_SPEC §5).
-- Every fixture in tests/fixtures/saves goes through the join path (migrate → reconcile →
-- repair) and must come out at the current version with every template key, its own data
-- kept, and nothing left to repair. Add a fixture (v<N>_<label>.json) whenever the schema
-- version goes up or the save shape changes.
local fs = require("@lune/fs")
local H = require("./harness")
local Schema = require("../src/server/Data/Schema")

local cfg = H.config()
local DIR = "tests/fixtures/saves"

local function fixtures(): { string }
	local names = {}
	for _, name in fs.readDir(DIR) do
		if string.match(name, "^v%d+_.+%.json$") then
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

local function load(name: string): any
	local data = H.json(`{DIR}/{name}`)
	data._note = nil
	Schema.migrate(data)
	Schema.reconcile(data, Schema.template())
	Schema.repair(data, cfg)
	return data
end

-- Every key of the template is present with the template's type, recursively.
local function hasShape(data: any, template: any, path: string)
	for key, default in template do
		local value = data[key]
		H.ok(value ~= nil, `{path}{key} missing`)
		H.eq(type(value), type(default), `{path}{key} type`)
		if type(default) == "table" and next(default) ~= nil and type(value) == "table" then
			hasShape(value, default, `{path}{key}.`)
		end
	end
end

H.test("there is a fixture for every schema version", function()
	local seen = {}
	for _, name in fixtures() do
		seen[tonumber(string.match(name, "^v(%d+)_")) :: number] = true
	end
	for v = 1, Schema.VERSION do
		H.ok(seen[v], `no fixture for v{v}`)
	end
end)

H.test("every fixture loads to the current shape and needs no further repair", function()
	for _, name in fixtures() do
		local data = load(name)
		H.eq(data.v, Schema.VERSION, name)
		hasShape(data, Schema.template(), `{name}: `)
		H.eq(#Schema.repair(data, cfg), 0, `{name}: repair is idempotent`)
		H.eq(#Schema.migrate(data), 0, `{name}: migrate is idempotent`)
	end
end)

H.test("the launch-shape save keeps its progress and gets the new keys", function()
	local data = load("v1_launch.json")
	H.eq(data.glow, 12345.5)
	H.eq(data.embers, 40)
	H.eq(data.stars, 2)
	H.eq(data.display["1"], "aaaaaaaa-0000-0000-0000-000000000001")
	H.eq(data.vault["1"], "aaaaaaaa-0000-0000-0000-000000000002")
	H.eq(data.glowlings["aaaaaaaa-0000-0000-0000-000000000003"].r, 2)
	H.eq(data.receipts["p-1"], 1790000500)
	H.eq(data.stats.catches, 30)
	H.eq(data.stats.fireSaves, 0, "added")
	H.eq(data.quests.rerollDay, 0, "added")
	H.eq(data.lb.week, "", "added")
	H.eq(type(data.badges), "table", "added")
end)

H.test("the Phase 5 save keeps trade locks, flags, pass and decor", function()
	local data = load("v1_phase5.json")
	H.eq(data.glowlings["bbbbbbbb-0000-0000-0000-000000000002"].tradeLockUntil, 1795086500)
	H.eq(data.flags.counts.flood, 1)
	H.eq(data.pass.premium, true)
	H.eq(data.decor.placed[1].id, "string_lights")
	H.eq(data.badges.first_trade, true)
	H.eq(data.stats.fireSaves, 3)
end)

H.finish("migration")
