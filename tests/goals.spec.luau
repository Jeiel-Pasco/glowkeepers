-- Goal tracker: candidates, bands and text (GAME_SYSTEMS §19 †).
local H = require("./harness")
local Goals = require("../src/shared/Goals")

local cfg = H.config()
local CYCLE = 360

local function fmt(n: number): string
	return tostring(math.floor(n))
end

-- Monday 2026-11-16 00:00 UTC, and that Wednesday.
local MONDAY = 1794787200
local WED = MONDAY + 2 * 86400

local function input(over: any?): any
	local base = {
		glow = 1000,
		since = 0,
		perSec = 10,
		unix = WED,
		upgrades = { { name = "Lantern 5", cost = 2200 }, { name = "Boots 2", cost = nil } },
		rebirthRequirement = 10000,
		weekly = {},
		dex = {},
		dexClaimed = {},
		species = {},
	}
	for k, v in over or {} do
		base[k] = v
	end
	return base
end

H.test("cycle is day + night", function()
	H.eq(Goals.cycleSeconds(cfg), CYCLE)
end)

H.test("week elapsed counts from Monday 00:00 UTC", function()
	H.eq(Goals.weekElapsed(MONDAY), 0)
	H.eq(Goals.weekElapsed(WED + 60), 2 * 86400 + 60)
end)

H.test("glow candidates: need / income, maxed upgrades skipped", function()
	local list = Goals.candidates(cfg, input({ since = 6300 }))
	H.eq(#list, 2, "lantern + rebirth")
	H.eq(list[1].name, "Lantern 5")
	H.eq(list[1].need, 1200)
	H.eq(list[1].seconds, 120)
	H.eq(list[2].kind, "rebirth")
	H.near(list[2].pct :: number, 0.63, 1e-9)
	H.eq(list[2].seconds, 370)
end)

H.test("no income: Glow goals have no estimate, affordable ones are ready", function()
	local list = Goals.candidates(cfg, input({ perSec = 0, glow = 5000 }))
	H.eq(list[1].seconds, 0, "lantern affordable")
	H.eq(list[2].seconds, math.huge, "rebirth unknown")
end)

H.test("weekly quests: pace so far, glow quests by income, claimed skipped", function()
	local weekly = {
		{ event = "survive", n = 4, target = 20 },
		{ event = "glow", n = 0, target = 3600 },
		{ event = "revive", n = 0, target = 10 },
		{ event = "star", n = 1, target = 1, claimed = true },
	}
	local list = Goals.candidates(cfg, input({ weekly = weekly, rebirthRequirement = 0 }))
	H.eq(#list, 4, "lantern + 3 quests")
	H.eq(list[2].seconds, 16 * 2 * 86400 / 4, "4 nights in 2 days -> 16 more in 8 days")
	H.eq(list[3].seconds, 360, "3600 Glow at 10/s")
	H.eq(list[4].seconds, math.huge, "no progress yet")
end)

H.test("dex: closest species page, one night per missing rarity", function()
	local dex = { mothlet = { r = 0b0111, m = 0 }, sprig = { r = 0b0001, m = 0 } }
	local species = { { id = "mothlet", name = "Mothlet" }, { id = "sprig", name = "Sprig" } }
	H.eq(Goals.dexMissing(cfg, dex.mothlet, 0), 1, "Bronze needs 4")
	H.eq(Goals.dexMissing(cfg, dex.mothlet, 4), nil, "all claimed")
	local list = Goals.candidates(cfg, input({ dex = dex, species = species, upgrades = {}, rebirthRequirement = 0 }))
	H.eq(#list, 1)
	H.eq(list[1].name, "Mothlet Bronze")
	H.eq(list[1].seconds, CYCLE)
	H.eq(list[1].pct, 0.75)
end)

H.test("pick: closest in each band", function()
	local list = {
		{ kind = "upgrade", name = "a", seconds = 300 },
		{ kind = "upgrade", name = "b", seconds = 100 },
		{ kind = "rebirth", name = "c", seconds = 1000 },
		{ kind = "rebirth", name = "d", seconds = 800 },
		{ kind = "quest", name = "e", seconds = 90000 },
		{ kind = "dex", name = "f", seconds = 5000 },
	}
	local out = Goals.pick(cfg, list)
	H.eq((out[1] :: any).name, "b")
	H.eq((out[2] :: any).name, "d")
	H.eq((out[3] :: any).name, "f", "5000 s > 5 cycles")
end)

H.test("pick: empty bands borrow the nearest unused candidate", function()
	local list = {
		{ kind = "upgrade", name = "a", seconds = 10 },
		{ kind = "upgrade", name = "b", seconds = 20 },
		{ kind = "upgrade", name = "c", seconds = 30 },
	}
	local out = Goals.pick(cfg, list)
	H.eq((out[1] :: any).name, "a")
	H.eq((out[2] :: any).name, "c", "nearest to the session band")
	H.eq((out[3] :: any).name, "b")
	local short = Goals.pick(cfg, { list[1] })
	H.eq((short[1] :: any).name, "a")
	H.eq(short[2], nil)
end)

H.test("text matches the spec examples", function()
	local list = Goals.candidates(cfg, input({ since = 6300, perSec = 1 }))
	H.eq(Goals.text(cfg, list[1], fmt), "Lantern 5: 1200 Glow to go (~3 nights)")
	H.eq(Goals.text(cfg, list[2], fmt), "Rebirth: 63% (~10 nights)")
	H.eq(Goals.eta(cfg, 100), "<1 night")
	H.eq(Goals.eta(cfg, 0), "now")
	H.eq(Goals.eta(cfg, math.huge), "?")
	H.eq(Goals.eta(cfg, CYCLE), "~1 night")
	H.eq(Goals.text(cfg, { kind = "upgrade", name = "Boots 3", need = 0, seconds = 0 }, fmt), "Boots 3: ready to buy")
	H.eq(Goals.text(cfg, { kind = "rebirth", name = "Rebirth", pct = 1, seconds = 0 }, fmt), "Rebirth: ready!")
end)

H.finish("goals")
