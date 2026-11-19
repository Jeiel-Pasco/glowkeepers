-- Leaderboards and badges (GAME_SYSTEMS §24).
local H = require("./harness")
local Boards = require("../src/shared/Boards")

local cfg = H.config()

local MONDAY = 1794787200 -- 2026-11-16, ISO week 47
local NEW_YEAR = 1798761600 -- 2027-01-01, a Friday: still ISO week 53 of 2026

H.test("ISO week keys", function()
	H.eq(Boards.isoWeek(MONDAY), "2026W47")
	H.eq(Boards.isoWeek(MONDAY - 1), "2026W46", "Sunday night is the week before")
	H.eq(Boards.isoWeek(MONDAY + 6 * 86400 + 86399), "2026W47", "through Sunday")
	H.eq(Boards.isoWeek(NEW_YEAR), "2026W53")
	H.eq(Boards.isoWeek(NEW_YEAR + 3 * 86400), "2027W01", "the next Monday")
	H.eq(Boards.storeName("revives", "2026W47"), "LB_Revives_2026W47")
	H.eq(Boards.storeName("stars", "2026W47"), "LB_Stars")
end)

H.test("weekly counts roll with the week; values read only the current week", function()
	local lb = { week = "2026W46", revives = 4, nights = 9 }
	local data = { stars = 3, dex = { a = { r = 0b111 }, b = { r = 0b1 } }, lb = lb }
	local v = Boards.values(data, "2026W47")
	H.eq(v.stars, 3)
	H.eq(v.dex, 4)
	H.eq(v.revives, 0, "last week's revives don't count")
	H.eq(Boards.roll(lb, "2026W47"), true)
	H.eq(lb.nights, 0)
	H.eq(Boards.roll(lb, "2026W47"), false)
	lb.revives = 2
	H.eq(Boards.values(data, "2026W47").revives, 2)
end)

H.test("writes at most once per gap", function()
	H.eq(Boards.canWrite(cfg, nil, 0), true)
	H.eq(Boards.canWrite(cfg, 100, 399), false)
	H.eq(Boards.canWrite(cfg, 100, 400), true)
end)

H.test("badges: 15 in config, earned from the profile", function()
	H.eq(#cfg.badges, 15)
	H.eq(table.concat(Boards.badgesEarned(cfg, { stats = {} }), ","), "welcome")
	local data = {
		stars = 5,
		playDays = 7,
		dex = { a = { r = 0b10100 }, b = { r = 0b1 } }, -- Rare and Legendary
		dexClaimed = { ["@10"] = 1, a = 1 },
		stats = { nightsSurvived = 1, revives = 10, fireSaves = 1, trades = 0 },
	}
	local earned = table.concat(Boards.badgesEarned(cfg, data), ",")
	H.eq(earned, "welcome,night1,rare,legendary,rebirth1,star5,bronze1,revives10,firesave,days7")
	H.eq(
		table.concat(Boards.badgesEarned(cfg, { stats = {}, dexClaimed = { ["@10"] = 1 } }), ","),
		"welcome",
		"a milestone is not a Bronze page"
	)
end)

H.finish("boards")
