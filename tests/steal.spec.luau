-- Steal: grab rules and carry checks (GAME_SYSTEMS §10, TECH_SPEC §8).
local H = require("./harness")
local Steal = require("../src/shared/Steal")
local Economy = require("../src/shared/Economy")

local cfg = H.config()

-- A grab that passes every rule; each test breaks one.
local function check(overrides: { [string]: any }?): any
	local c = {
		phase = "Day",
		thief = 1,
		owner = 2,
		thiefHasPlot = true,
		thiefHasRoom = true,
		padKind = "display",
		hasGlowling = true,
		busy = false,
		padTaken = false,
		locked = false,
		shielded = false,
		now = 1000,
		victimSafeUntil = 0,
		stolenToday = 0,
		distance = 4,
	}
	for key, value in overrides or {} do
		c[key] = value
	end
	return c
end

local function reason(overrides: { [string]: any }): string?
	local ok, why = Steal.canGrab(cfg, check(overrides))
	H.ok(not ok, "should be rejected")
	return why
end

H.test("hold times by rarity (§10)", function()
	H.eq(Steal.holdSeconds(cfg, 1), 1, "Common")
	H.eq(Steal.holdSeconds(cfg, 3), 1, "Rare")
	H.eq(Steal.holdSeconds(cfg, 4), 2, "Epic")
	H.eq(Steal.holdSeconds(cfg, 5), 2, "Legendary")
	H.eq(Steal.holdSeconds(cfg, 6), 3, "Mythic")
	H.eq(Steal.holdSeconds(cfg, 7), 3, "Secret")
end)

H.test("a valid grab passes", function()
	H.ok(Steal.canGrab(cfg, check()), "valid")
	H.ok(Steal.canGrab(cfg, check({ distance = cfg.steal.grabRange })), "exactly at range")
end)

H.test("each rule rejects with its own reason", function()
	H.eq(reason({ phase = "Dusk" }), "not_day", "blocked from the dusk warning (3:30)")
	H.eq(reason({ phase = "Night" }), "not_day", "night")
	H.eq(reason({ thiefHasPlot = false }), "no_plot", "nowhere to deliver")
	H.eq(reason({ thiefHasRoom = false }), "storage_full", "no room for it")
	H.eq(reason({ owner = 0 }), "empty", "free plot")
	H.eq(reason({ owner = 1 }), "own_plot", "own plot")
	H.eq(reason({ padKind = "vault" }), "vault", "vault pads are never stolen")
	local lockedPad = check()
	lockedPad.padKind = nil -- not a pad this plot has unlocked
	H.eq(select(2, Steal.canGrab(cfg, lockedPad)), "vault", "locked pad")
	H.eq(reason({ hasGlowling = false }), "empty", "empty pad")
	H.eq(reason({ busy = true }), "busy", "one carry at a time")
	H.eq(reason({ padTaken = true }), "taken", "someone else has it")
	H.eq(reason({ locked = true }), "locked", "Base Lock")
	H.eq(reason({ shielded = true }), "shielded", "shield")
	H.eq(reason({ victimSafeUntil = 1001 }), "cooldown", "victim cooldown")
	H.eq(reason({ stolenToday = 1 }), "daily_limit", "once per victim per day phase")
	H.eq(reason({ distance = cfg.steal.grabRange + 0.01 }), "too_far", "out of range")
	H.eq(reason({ distance = 0 / 0 }), "too_far", "NaN distance")
end)

H.test("reach is flat distance, within a height limit", function()
	-- Standing next to a pad: the root part is about 3 studs above it.
	H.near(Steal.reach(cfg, 3, -3, 4), 5, 1e-9, "3-4-5 on the ground, height ignored")
	H.ok(Steal.reach(cfg, 5.5, -3, 0) <= cfg.steal.grabRange, "5.5 studs away is in range")
	H.eq(Steal.reach(cfg, 1, -(cfg.steal.grabRange + 1), 0), math.huge, "on a roof above the pad")
	H.eq(Steal.reach(cfg, 0, 0 / 0, 0), math.huge, "NaN")
end)

H.test("the victim cooldown ends on time", function()
	H.ok(Steal.canGrab(cfg, check({ now = 1045, victimSafeUntil = 1045 })), "safe until 1045, grab at 1045")
end)

-- Samples every 0.1 s moving along x at `speed` studs/s.
local function run(speed: number, count: number): { any }
	local samples = {}
	for i = 0, count - 1 do
		table.insert(samples, { t = i * 0.1, x = speed * i * 0.1, z = 0 })
	end
	return samples
end

H.test("carry checks: a legit carrier passes, a fast one and a teleport fail", function()
	local carrySpeed = Economy.runSpeed(cfg, 0, false, true) -- 22 × 0.85 = 18.7
	H.near(carrySpeed, 18.7, 1e-9, "carry speed at Boots 0")
	H.eq(Steal.moveViolation(cfg, run(carrySpeed, 8), carrySpeed), nil, "running while carrying")
	-- 20% over: inside the 25% tolerance.
	H.eq(Steal.moveViolation(cfg, run(carrySpeed * 1.2, 8), carrySpeed), nil, "inside the tolerance")
	-- Twice the speed over the window: 0.5 s × 37.4 = 18.7 studs > 0.5 × 23.4 + 2 = 13.7.
	H.eq(Steal.moveViolation(cfg, run(carrySpeed * 2, 8), carrySpeed), "speed", "speed hack")
	local jump = run(carrySpeed, 4)
	table.insert(jump, { t = 0.4, x = 50, z = 0 })
	H.eq(Steal.moveViolation(cfg, jump, carrySpeed), "teleport", "a 30+ stud jump in one sample")
	-- A 1 s server hitch: one step of 18.7 studs is just running.
	H.eq(
		Steal.moveViolation(cfg, { { t = 0, x = 0, z = 0 }, { t = 1, x = carrySpeed, z = 0 } }, carrySpeed),
		nil,
		"hitch"
	)
	H.eq(Steal.moveViolation(cfg, run(200, 1), carrySpeed), nil, "one sample: nothing to compare")
	H.eq(Steal.moveViolation(cfg, run(carrySpeed * 2, 3), carrySpeed), nil, "under the window: wait for more")
end)

H.test("carry checks: falling never counts, and one network burst is absorbed", function()
	local carrySpeed = 18.7
	local falling = {}
	for i = 0, 7 do
		table.insert(falling, { t = i * 0.1, x = 0, z = 0 }) -- y isn't sampled at all
	end
	H.eq(Steal.moveViolation(cfg, falling, carrySpeed), nil, "standing still")
	-- A late packet: no movement for 0.3 s, then the whole 0.5 s of running arrives at once.
	local burst = {
		{ t = 0, x = 0, z = 0 },
		{ t = 0.1, x = 0, z = 0 },
		{ t = 0.2, x = 0, z = 0 },
		{ t = 0.3, x = 0, z = 0 },
		{ t = 0.4, x = 0, z = 0 },
		{ t = 0.5, x = carrySpeed * 0.5, z = 0 },
	}
	H.eq(Steal.moveViolation(cfg, burst, carrySpeed), nil, "a burst inside the window is fine")
end)

H.test("trim keeps the window plus one older sample", function()
	local samples = run(10, 20) -- t = 0 .. 1.9
	Steal.trim(cfg, samples, 1.9)
	H.ok(samples[1].t <= 1.9 - cfg.steal.carryCheckWindow, "one sample at or past the window edge")
	H.ok(#samples <= 8, `trimmed to about the window, got {#samples}`)
	H.near(samples[#samples].t, 1.9, 1e-9, "newest kept")
	H.eq(Steal.moveViolation(cfg, samples, 10), nil, "still checkable after trimming")
end)

H.finish("steal")
