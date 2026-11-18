-- Forest: spawn waves, markers and catch rules (GAME_SYSTEMS §12).
local H = require("./harness")
local Forest = require("../src/shared/Forest")
local Economy = require("../src/shared/Economy")

local cfg = H.config()

local function sum(list: { number }): number
	local n = 0
	for _, v in list do
		n += v
	end
	return n
end

local function modifier(id: string): any
	for _, m in cfg.cycle.nightModifiers do
		if m.id == id then
			return m
		end
	end
	error(`no modifier {id}`)
end

H.test("waves: 4 per player in total, over 3 waves", function()
	H.eq(#cfg.night.spawnWavesAt, 3, "three waves")
	local one = Forest.waveSizes(cfg, 1)
	H.eq(sum(one), 4, "1 player: 4")
	H.eq(one[1], 2, "the first wave takes the remainder")
	H.eq(one[3], 1, "last wave")
	H.eq(sum(Forest.waveSizes(cfg, 8)), 32, "8 players: 32")
	H.eq(sum(Forest.waveSizes(cfg, 0)), 0, "nobody here")
	H.eq(sum(Forest.waveSizes(cfg, 8, modifier("FireflyBloom"))), 48, "Firefly Bloom ×1.5")
	H.eq(sum(Forest.waveSizes(cfg, 3, modifier("Fog"))), 15, "Fog ×1.25: 12 × 1.25 = 15")
	H.eq(sum(Forest.waveSizes(cfg, 2, modifier("Gusty"))), 8, "Gusty doesn't change spawns")
end)

H.test("waves come at 0:10, 0:40 and 1:10 into the night", function()
	H.eq(Forest.dueWave(cfg, 9.9, 0), nil, "not yet")
	H.eq(Forest.dueWave(cfg, 10, 0), 1, "first wave")
	H.eq(Forest.dueWave(cfg, 39, 1), nil, "between waves")
	H.eq(Forest.dueWave(cfg, 75, 1), 2, "a late tick still gets wave 2")
	H.eq(Forest.dueWave(cfg, 70, 2), 3, "third wave")
	H.eq(Forest.dueWave(cfg, 119, 3), nil, "all done")
end)

H.test("markers: free ones first, then reuse", function()
	local rng = H.rng(7)
	local picks = Forest.pickMarkers(5, 5, {}, rng)
	table.sort(picks)
	H.eq(table.concat(picks, ","), "1,2,3,4,5", "5 markers, 5 wilds: one each")
	local more = Forest.pickMarkers(3, 2, { [1] = true }, rng)
	H.eq(more[1], 2, "the free marker first")
	H.eq(#more, 3, "then markers are shared")
	H.eq(#Forest.pickMarkers(3, 0, {}, rng), 0, "no markers, no wilds")
end)

H.test("pools by area", function()
	H.eq(Forest.poolFor("Forest"), "Clearing", "the forest draws Clearing species")
	H.eq(Forest.poolFor("Deepwood"), "Deepwood", "deepwood")
end)

local function check(overrides: { [string]: any }?): any
	local c = { night = true, living = true, exists = true, catchesLeft = 3, hasRoom = true, distance = 8 }
	for key, value in overrides or {} do
		c[key] = value
	end
	return c
end

local function reason(overrides: { [string]: any }): string?
	local ok, why = Forest.canCatch(cfg, check(overrides))
	H.ok(not ok, "should be rejected")
	return why
end

H.test("catch rules (§12 acceptance)", function()
	H.ok(Forest.canCatch(cfg, check()), "valid")
	H.ok(Forest.canCatch(cfg, check({ distance = 12 })), "exactly 12 studs")
	H.eq(reason({ distance = 20 }), "too_far", "a catch from 20 studs is rejected")
	H.eq(reason({ catchesLeft = 0 }), "no_catches", "a 4th catch with 0 left is rejected")
	H.eq(reason({ night = false }), "not_night", "by day")
	H.eq(reason({ living = false }), "not_living", "downed or a wisp")
	H.eq(reason({ exists = false }), "gone", "someone caught it first")
	H.eq(reason({ hasRoom = false }), "storage_full", "storage at its hard cap")
	H.eq(reason({ distance = 0 / 0 }), "too_far", "NaN")
end)

H.test("catches per night", function()
	H.eq(Economy.nightCatches(cfg, 0), 3, "3 at Boots 0")
	H.eq(Economy.nightCatches(cfg, 5), 4, "+1 at Boots 5")
	H.eq(Economy.nightCatches(cfg, 0, modifier("FireflyBloom")), 4, "Firefly Bloom +1")
end)

H.finish("forest")
