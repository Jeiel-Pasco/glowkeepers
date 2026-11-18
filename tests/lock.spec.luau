-- Lock: Base Lock rules, timers and the push-out (GAME_SYSTEMS §11).
local H = require("./harness")
local Lock = require("../src/shared/Lock")

local cfg = H.config()

local function check(overrides: { [string]: any }?): any
	local c = {
		phase = "Day",
		hasPlot = true,
		carrying = false,
		now = 1000,
		lockedUntil = 0,
		readyAt = 0,
		charges = 0,
	}
	for key, value in overrides or {} do
		c[key] = value
	end
	return c
end

H.test("a ready lock passes without a charge", function()
	local ok, why, charge = Lock.canLock(check())
	H.ok(ok, "ok")
	H.eq(why, nil, "no reason")
	H.eq(charge, false, "no charge spent")
	H.ok((Lock.canLock(check({ phase = "Dusk" }))), "the dusk warning is still day for locks")
end)

H.test("each rule rejects with its own reason", function()
	H.eq(select(2, Lock.canLock(check({ phase = "Night" }))), "night", "no locks at night")
	H.eq(select(2, Lock.canLock(check({ hasPlot = false }))), "no_plot", "nothing to lock")
	H.eq(select(2, Lock.canLock(check({ carrying = true }))), "carrying", "not while carrying (§10)")
	H.eq(select(2, Lock.canLock(check({ lockedUntil = 1001 }))), "active", "already locked")
	H.eq(select(2, Lock.canLock(check({ lockedUntil = 990, readyAt = 1080 }))), "recharging", "recharging")
end)

H.test("a Lock Charge skips the recharge, never an active lock", function()
	local ok, _, charge = Lock.canLock(check({ lockedUntil = 990, readyAt = 1080, charges = 2 }))
	H.ok(ok, "charge used")
	H.eq(charge, true, "spends a charge")
	H.eq(select(2, Lock.canLock(check({ lockedUntil = 1030, readyAt = 1120, charges = 2 }))), "active", "still locked")
end)

H.test("timers: 60 s locked, then 90 s recharge", function()
	local lockedUntil, readyAt = Lock.times(cfg, 1000)
	H.eq(lockedUntil, 1000 + cfg.lock.activeSeconds, "locked for 60 s")
	H.eq(readyAt, lockedUntil + cfg.lock.rechargeSeconds, "ready 90 s after it ends")
	H.ok((Lock.canLock(check({ now = readyAt, lockedUntil = lockedUntil, readyAt = readyAt }))), "ready on time")
end)

H.test("push-out leaves through the nearest side", function()
	-- A 36 × 40 zone: half 18 × 20.
	local x, z = Lock.pushOut(17, 3, 18, 20, 2)
	H.eq(x, 20, "+X side")
	H.eq(z, 3, "z kept")
	x, z = Lock.pushOut(-16, 0, 18, 20, 2)
	H.eq(x, -20, "-X side")
	x, z = Lock.pushOut(0, 19.5, 18, 20, 2)
	H.eq(z, 22, "+Z side")
	H.eq(x, 0, "x kept")
	x, z = Lock.pushOut(5, -19, 18, 20, 2)
	H.eq(z, -22, "-Z side")
end)

H.finish("lock")
