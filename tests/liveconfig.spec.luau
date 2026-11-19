-- Live config merge and kill switches (TECH_SPEC §10).
local H = require("./harness")
local LiveConfig = require("../src/shared/LiveConfig")

local cfg = H.config()

H.test("nothing live: the defaults, nothing killed, no event", function()
	local live = LiveConfig.merge(cfg, nil)
	H.eq(LiveConfig.killed(live, "stealing"), false)
	H.eq(live.event, nil)
	H.eq(LiveConfig.mult(live, "luckMult", 0), 1)
end)

H.test("the TECH_SPEC example merges", function()
	local live = LiveConfig.merge(cfg, {
		killSwitches = { trading = false, stealing = true, serverLuck = false, products = { LockCharge3 = false } },
		event = { id = "lantern_festival", start = 1803049200, ["end"] = 1803254400, luckMult = 1.5, embersMult = 2 },
		limitedSpecies = { week = "2027W07", species = "koilight" },
		codes = { firstlight = { embers = 50, expires = 1803859200 } },
	})
	H.eq(LiveConfig.killed(live, "stealing"), true)
	H.eq(LiveConfig.productKilled(live, "LockCharge3"), false)
	H.eq(LiveConfig.mult(live, "luckMult", 1803049200), 1.5, "at the start")
	H.eq(LiveConfig.mult(live, "embersMult", 1803254399), 2)
	H.eq(LiveConfig.mult(live, "embersMult", 1803254400), 1, "ended")
	H.eq(LiveConfig.mult(live, "spawnMult", 1803100000), 1, "key not set")
	H.eq((live.limitedSpecies :: any).species, "koilight")
	H.eq(live.codes.FIRSTLIGHT.embers, 50, "codes are upper-cased")
end)

H.test("malformed values are dropped, defaults are not mutated", function()
	local live = LiveConfig.merge(cfg, {
		killSwitches = { stealing = "yes", nuke = true, products = { A = 1 } },
		event = { id = "x", start = 10, ["end"] = 5 },
	})
	H.eq(LiveConfig.killed(live, "stealing"), false, "non-boolean ignored")
	H.eq(live.killSwitches.nuke, nil, "unknown switch ignored")
	H.eq(live.killSwitches.products.A, nil)
	H.eq(live.event, nil, "end before start")
	local capped =
		LiveConfig.merge(cfg, { event = { id = "y", start = 0, ["end"] = 100, luckMult = 50, glowMult = -1 } })
	H.eq(LiveConfig.mult(capped, "luckMult", 1), 1, "over maxMult dropped")
	H.eq(LiveConfig.mult(capped, "glowMult", 1), 1, "negative dropped")
	LiveConfig.merge(cfg, { killSwitches = { stealing = true } })
	H.eq(cfg.live.defaults.killSwitches.stealing, false, "defaults untouched")
end)

H.finish("liveconfig")
