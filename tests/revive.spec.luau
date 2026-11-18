-- Revive: downed, bleed-out and revive rules (GAME_SYSTEMS §14).
local H = require("./harness")
local Revive = require("../src/shared/Revive")

local cfg = H.config()

-- A revive that passes every rule; each test breaks one.
local function check(overrides: { [string]: any }?): any
	local c = {
		night = true,
		self = false,
		reviver = "alive",
		target = "downed",
		busy = false,
		taken = false,
		distance = 5,
	}
	for key, value in overrides or {} do
		c[key] = value
	end
	return c
end

local function reason(overrides: { [string]: any }): string?
	local ok, why = Revive.canStart(cfg, check(overrides))
	H.ok(not ok, "should be rejected")
	return why
end

H.test("a valid revive passes", function()
	H.ok(Revive.canStart(cfg, check()), "valid")
	H.ok(Revive.canStart(cfg, check({ distance = cfg.revive.range })), "exactly at range")
end)

H.test("each rule rejects with its own reason", function()
	H.eq(reason({ night = false }), "not_night", "by day")
	H.eq(reason({ self = true }), "self", "yourself")
	H.eq(reason({ reviver = "downed" }), "not_alive", "a downed reviver")
	H.eq(reason({ reviver = "wisp" }), "not_alive", "a wisp")
	H.eq(reason({ target = "alive" }), "not_downed", "nobody to revive")
	H.eq(reason({ target = "wisp" }), "not_downed", "too late: already a wisp")
	H.eq(reason({ busy = true }), "busy", "one revive at a time")
	H.eq(reason({ taken = true }), "taken", "someone else is on it")
	H.eq(reason({ distance = cfg.revive.range + 0.01 }), "too_far", "out of range")
	H.eq(reason({ distance = 0 / 0 }), "too_far", "NaN distance")
end)

H.test("bleed-out runs out on time", function()
	local bleed = Revive.bleed(cfg, 100)
	H.eq(bleed.ends, 100 + cfg.revive.bleedOutSeconds, "30 s")
	H.ok(not Revive.bledOut(bleed, 129.9), "still downed")
	H.ok(Revive.bledOut(bleed, 130), "bled out")
end)

H.test("a revive in progress pauses the bleed-out", function()
	local bleed = Revive.bleed(cfg, 100)
	Revive.pause(bleed, 128) -- 2 s left, a 3 s hold begins
	H.ok(not Revive.bledOut(bleed, 131), "paused past the old end")
	Revive.pause(bleed, 129) -- a second pause changes nothing
	Revive.resume(bleed, 135) -- let go: the 2 s left carry on
	H.eq(bleed.ends, 137, "2 s left after letting go")
	H.ok(not Revive.bledOut(bleed, 136.9), "still downed")
	H.ok(Revive.bledOut(bleed, 137), "bled out")
	Revive.resume(bleed, 200) -- resuming twice changes nothing
	H.eq(bleed.ends, 137, "unchanged")
end)

H.test("a pause after the end leaves nothing", function()
	local bleed = Revive.bleed(cfg, 0)
	Revive.pause(bleed, 40)
	Revive.resume(bleed, 41)
	H.ok(Revive.bledOut(bleed, 41), "no time left")
end)

H.finish("revive")
