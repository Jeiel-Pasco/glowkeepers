-- Daily gift: one step per UTC day claimed, never resets, loops after 28 (GAME_SYSTEMS §19).
local H = require("./harness")
local Gift = require("../src/shared/Gift")

local cfg = H.config()

H.test("28 steps; day 7 is a guaranteed-Epic lure, day 28 a decoration", function()
	H.eq(#cfg.gift.steps, 28, "28 steps")
	local _, day7 = Gift.next(cfg, { claimed = 6, lastDay = 0 })
	H.eq(day7.kind, "lure", "day 7 kind")
	H.eq(day7.floor, 4, "day 7 is Epic or better")
	local step, day28 = Gift.next(cfg, { claimed = 27, lastDay = 0 })
	H.eq(step, 28, "step 28")
	H.eq(day28.kind, "decor", "day 28 kind")
	for i, reward in cfg.gift.steps do
		local ok = (reward.kind == "embers" or reward.kind == "lockCharge") and (reward.amount or 0) > 0
			or reward.kind == "lure" and reward.floor >= 1 and reward.floor <= cfg.lures.maxFloor
			or reward.kind == "decor" and type(reward.id) == "string"
		H.ok(ok, `step {i} is a valid reward`)
	end
end)

H.test("one claim per UTC day; missed days pause it; it loops after 28", function()
	local today = Gift.day(1_800_000_000)
	local gift = { claimed = 0, lastDay = 0 }
	H.ok(Gift.canClaim(gift, today), "a new player can claim")
	gift = Gift.claimed(gift, today)
	H.ok(not Gift.canClaim(gift, today), "not twice the same day")
	H.ok(Gift.canClaim(gift, today + 5), "five days later: just the next step")
	H.eq(Gift.next(cfg, gift), 2, "step 2 after one claim")
	H.eq(Gift.next(cfg, { claimed = 28, lastDay = today }), 1, "loops to step 1")
	H.eq(Gift.day(86399), 0, "the UTC day boundary")
	H.eq(Gift.day(86400), 1, "the next day")
	H.eq(Gift.secondsToNextDay(86399), 1, "one second to the next day")
end)

H.finish("gift")
