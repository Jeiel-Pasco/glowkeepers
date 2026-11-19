-- Quests: UTC resets, picking, progress, claims and the daily reroll (GAME_SYSTEMS §19).
local H = require("./harness")
local Quest = require("../src/shared/Quest")

local cfg = H.config()
local OPTS = { shielded = false, perSec = 10 }

local function seq(values: { number }): () -> number
	local i = 0
	return function()
		i = i % #values + 1
		return values[i]
	end
end

H.test("days reset at 00:00 UTC, weeks at Monday 00:00 UTC", function()
	H.eq(Quest.day(86399), 0, "day boundary")
	H.eq(Quest.day(86400), 1, "next day")
	H.eq(Quest.week(3 * 86400), 0, "Sunday 4 Jan 1970: week 0")
	H.eq(Quest.week(4 * 86400), 1, "Monday 5 Jan 1970: week 1")
	H.eq(Quest.week(10 * 86400 + 86399), 1, "the next Sunday: still week 1")
	H.eq(Quest.week(11 * 86400), 2, "the next Monday")
end)

H.test("refresh rolls 3 distinct daily and 3 weekly quests, once per day and week", function()
	local quests = { day = 0, daily = {}, week = 0, weekly = {} }
	H.ok(Quest.refresh(cfg, quests, 1_800_000_000, seq({ 0.1, 0.5, 0.9 }), OPTS), "new day")
	H.eq(#quests.daily, 3, "3 daily")
	H.eq(#quests.weekly, 3, "3 weekly")
	H.ok(quests.daily[1].id ~= quests.daily[2].id and quests.daily[2].id ~= quests.daily[3].id, "distinct")
	H.ok(not Quest.refresh(cfg, quests, 1_800_000_000 + 60, seq({ 0.5 }), OPTS), "same day: nothing")
	local earn = Quest.pick(cfg, { { id = "earn", event = "glow", target = 0, weight = 1 } }, 1, seq({ 0 }), OPTS)[1]
	H.eq(earn.target, 18000, "earn: 10/s × 1800 s")
	local low = Quest.pick(
		cfg,
		{ { id = "earn", event = "glow", target = 0, weight = 1 } },
		1,
		seq({ 0 }),
		{ shielded = false, perSec = 0 }
	)[1]
	H.eq(low.target, 500, "earn: at least 500")
end)

H.test("shielded players never get the steal quest", function()
	for _ = 1, 20 do
		local picked = Quest.pick(cfg, cfg.quests.dailyPool, 9, math.random, { shielded = true, perSec = 1 })
		for _, q in picked do
			H.ok(q.event ~= "steal", "no steal quest")
		end
	end
end)

H.test("advance, claim once, and one free reroll a day", function()
	local quests = {
		day = 5,
		week = 1,
		daily = {
			{ id = "feed4", event = "feed", target = 4, n = 0, claimed = false },
			{ id = "lures3", event = "lure", target = 3, n = 0, claimed = false },
			{ id = "catch3", event = "catch_night", target = 3, n = 0, claimed = false },
		},
		weekly = { { id = "revive10", event = "revive", target = 10, n = 0, claimed = false } },
	}
	H.ok(Quest.advance(quests, "feed", 3), "feed moves")
	H.eq(select(2, Quest.canClaim(cfg, quests, "d", 1)), "not_done", "3 of 4")
	Quest.advance(quests, "feed", 5)
	H.eq(quests.daily[1].n, 4, "capped at the target")
	H.eq(Quest.canClaim(cfg, quests, "d", 1).embers, 15, "daily: 15 Embers")
	quests.daily[1].claimed = true
	H.ok(not Quest.advance(quests, "feed", 1), "claimed quests don't move")
	H.eq(select(2, Quest.canClaim(cfg, quests, "d", 1)), "claimed", "once")
	H.eq(select(2, Quest.canClaim(cfg, quests, "x", 1)), "unknown", "bad scope")
	H.eq(select(2, Quest.reroll(cfg, quests, 1, seq({ 0 }), OPTS)), "claimed", "can't reroll a claimed one")
	H.ok((Quest.reroll(cfg, quests, 2, seq({ 0 }), OPTS)), "reroll")
	H.ok(
		quests.daily[2].id ~= "lures3" and quests.daily[2].id ~= "feed4" and quests.daily[2].id ~= "catch3",
		"a different quest"
	)
	H.eq(select(2, Quest.reroll(cfg, quests, 3, seq({ 0 }), OPTS)), "used", "only one a day")
end)

H.finish("quest")
