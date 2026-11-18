-- Schema: template, migrations, load-time repair, join bookkeeping (TECH_SPEC §5).
local H = require("./harness")
local Schema = require("../src/server/Data/Schema")

local cfg = H.config()

local function glowling(id: string, r: number?, m: number?, s: number?): any
	return { id = id, sp = "glimmermouse", r = r or 1, m = m or 0, s = s or 1, src = "lure", at = 1, by = 1 }
end

local function count(map: any): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

H.test("a fresh template needs no migrations or repairs", function()
	local data = Schema.template()
	H.eq(#Schema.migrate(data), 0, "migrations")
	H.eq(#Schema.repair(data, cfg), 0, "repairs")
	H.eq(data.v, Schema.VERSION, "version")
	H.ok(data.shield.active, "new players start shielded")
end)

H.test("broken numbers are repaired, never errored", function()
	local data = Schema.template()
	data.glow = 0 / 0
	data.embers = -5
	data.stars = math.huge
	data.lockCharges = 2.7
	data.lastIncomePerSec = 12.5
	data.up.lantern = 999
	data.settings.music = 5
	data.pity.sinceLegendary = 400
	local notes = Schema.repair(data, cfg)
	H.eq(data.glow, 0, "NaN Glow")
	H.eq(data.embers, 0, "negative Embers")
	H.eq(data.stars, 0, "infinite Stars")
	H.eq(data.lockCharges, 2, "whole numbers are floored")
	H.eq(data.lastIncomePerSec, 12.5, "fractional fields keep fractions")
	H.eq(data.up.lantern, cfg.upgrades.lantern.max, "level clamped to max")
	H.eq(data.settings.music, 1, "volume clamped")
	H.eq(data.pity.sinceLegendary, cfg.pity.legendaryAfterNightCatches, "pity clamped")
	H.ok(#notes >= 7, "every repair is noted")
end)

H.test("wrong types reset to defaults; missing keys are filled", function()
	local data = Schema.template()
	data.settings = "loud"
	data.glowlings = 5
	data.stats = nil
	Schema.reconcile(data, Schema.template())
	Schema.repair(data, cfg)
	H.eq(type(data.settings), "table", "settings reset")
	H.eq(data.settings.music, 0.8, "default volume")
	H.eq(type(data.glowlings), "table", "glowlings reset")
	H.eq(data.stats.catches, 0, "stats filled")
end)

H.test("Glowling records: broken ones dropped, fixable ones fixed", function()
	local data = Schema.template()
	data.glowlings = {
		a = glowling("a"),
		b = glowling("wrong-id", 5),
		c = glowling("c", 9),
		d = glowling("d", 2, 0, 1.234),
		e = glowling("e", 3, 0, 7),
		f = { sp = 1 },
		g = glowling("g", 1, 4),
	}
	Schema.repair(data, cfg)
	H.ok(data.glowlings.a ~= nil, "valid record kept")
	H.eq(data.glowlings.b.id, "b", "id fixed to its key")
	H.eq(data.glowlings.c, nil, "rarity 9 removed")
	H.eq(data.glowlings.d.s, 1.23, "size rounded")
	H.eq(data.glowlings.e.s, 1.3, "size clamped")
	H.eq(data.glowlings.f, nil, "garbage removed")
	H.eq(data.glowlings.g, nil, "unknown mutation removed")
end)

H.test("slot maps: bad entries go back to storage, number keys become strings", function()
	local data = Schema.template()
	data.glowlings = { a = glowling("a"), b = glowling("b"), c = glowling("c"), d = glowling("d") }
	data.vault = { ["1"] = "a", ["2"] = "b" }
	data.display = { ["1"] = "b", ["2"] = "missing", ["40"] = "c", [3] = "d" }
	Schema.repair(data, cfg)
	H.eq(data.vault["1"], "a", "vault 1")
	H.eq(data.vault["2"], "b", "vault 2")
	H.eq(data.display["1"], nil, "b is already in the vault")
	H.eq(data.display["2"], nil, "missing Glowling")
	H.eq(data.display["40"], nil, "beyond the slot count")
	H.eq(data.display["3"], "d", "number key moved to a string key")
	H.eq(data.display[3], nil, "number key removed")
	H.ok(data.glowlings.c ~= nil, "unplaced Glowlings stay owned")
end)

H.test("receipts keep the newest 200", function()
	local data = Schema.template()
	for i = 1, 250 do
		data.receipts[`p{i}`] = i
	end
	Schema.repair(data, cfg)
	H.eq(count(data.receipts), 200, "count")
	H.eq(data.receipts.p1, nil, "oldest dropped")
	H.eq(data.receipts.p250, 250, "newest kept")
end)

H.test("migrate: an invalid version counts as 1", function()
	local data = Schema.template()
	data.v = "abc"
	local notes = Schema.migrate(data)
	H.eq(data.v, 1, "version")
	H.eq(#notes, 1, "noted")
end)

H.test("a save from a newer build is left alone apart from broken numbers", function()
	local data = Schema.template()
	data.v = 99
	data.up.lantern = 999
	data.glowlings = { x = glowling("x", 9) }
	data.glow = 0 / 0
	Schema.migrate(data)
	Schema.repair(data, cfg)
	H.eq(data.v, 99, "version kept")
	H.eq(data.up.lantern, 999, "not clamped")
	H.ok(data.glowlings.x ~= nil, "unknown rarity kept for the newer build")
	H.eq(data.glow, 0, "NaN still fixed")
end)

H.test("onJoin: first join, same day, next day, and a future lastSeen", function()
	local midnight = 1_800_000_000 - 1_800_000_000 % 86400
	local data = Schema.template()

	local away, first = Schema.onJoin(data, midnight + 100)
	H.eq(away, 0, "first join pays nothing")
	H.ok(first, "first session")
	H.eq(data.playDays, 1, "day 1")
	H.eq(data.firstJoin, midnight + 100, "firstJoin")

	away, first = Schema.onJoin(data, midnight + 3700)
	H.eq(away, 3600, "an hour away")
	H.ok(not first, "not first")
	H.eq(data.playDays, 1, "same day")

	away = Schema.onJoin(data, midnight + 86400 + 10)
	H.eq(away, 86400 + 10 - 3700, "away overnight")
	H.eq(data.playDays, 2, "next day")

	data.lastSeen = midnight + 10 ^ 7
	away = Schema.onJoin(data, midnight + 90000)
	H.eq(away, 0, "a future lastSeen pays nothing")
end)

H.test("clientView hides receipts and flags", function()
	local data = Schema.template()
	data.receipts.p1 = 1
	local view = Schema.clientView(data)
	H.eq(view.receipts, nil, "receipts")
	H.eq(view.flags, nil, "flags")
	H.eq(view.glow, 0, "public fields stay")
	H.ok(Schema.isPrivate("flags"), "isPrivate")
end)

H.finish("schema")
