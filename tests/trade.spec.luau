-- Trading rules (GAME_SYSTEMS §17).
local H = require("./harness")
local Trade = require("../src/shared/Trade")

local cfg = H.config()

local function unlock(over: any?): any
	local u = { stars = 3, playDays = 3, accountAge = 7, policy = true, killed = false }
	for k, v in over or {} do
		u[k] = v
	end
	return u
end

local function profile(): any
	return {
		glowlings = {
			a = { id = "a", r = 1 },
			b = { id = "b", r = 5 },
			c = { id = "c", r = 3, tradeLockUntil = 2000 },
			d = { id = "d", r = 2 },
			e = { id = "e", r = 1 },
			f = { id = "f", r = 1 },
		},
		vault = { ["1"] = "d" },
		display = {},
	}
end

H.test("unlock: kill switch, policy, Stars, play days, account age", function()
	H.eq(Trade.unlockReason(cfg, unlock()), nil)
	H.eq(Trade.unlockReason(cfg, unlock({ killed = true })), "killed")
	H.eq(Trade.unlockReason(cfg, unlock({ policy = false })), "policy")
	H.eq(Trade.unlockReason(cfg, unlock({ stars = 2 })), "stars")
	H.eq(Trade.unlockReason(cfg, unlock({ playDays = 2 })), "days")
	H.eq(Trade.unlockReason(cfg, unlock({ accountAge = 6 })), "account")
end)

H.test("offer: storage only, owned, unique, not held, not trade-locked, at most 4", function()
	local data = profile()
	H.eq(Trade.offerReason(cfg, data, { "a", "b" }, nil, 1000), nil)
	H.eq(Trade.offerReason(cfg, data, {}, nil, 1000), nil, "empty is fine")
	H.eq(Trade.offerReason(cfg, data, { "a", "a" }, nil, 1000), "duplicate")
	H.eq(Trade.offerReason(cfg, data, { "zzz" }, nil, 1000), "not_owned")
	H.eq(Trade.offerReason(cfg, data, { "d" }, nil, 1000), "placed")
	H.eq(Trade.offerReason(cfg, data, { "a" }, { a = true }, 1000), "held")
	H.eq(Trade.offerReason(cfg, data, { "c" }, nil, 1999), "trade_locked")
	H.eq(Trade.offerReason(cfg, data, { "c" }, nil, 2000), nil, "lock over")
	H.eq(Trade.offerReason(cfg, data, { "a", "b", "c", "e", "f" }, nil, 3000), "too_many")
end)

H.test("fee by rarity, uneven warning, confirm timing, room", function()
	local data = profile()
	H.eq(Trade.fee(cfg, { data.glowlings.a, data.glowlings.b }), 1 + 25)
	H.eq(Trade.uneven(100, 20), true, "5x")
	H.eq(Trade.uneven(100, 21), false)
	H.eq(Trade.uneven(0, 0), false)
	H.eq(Trade.uneven(0, 1), true)
	H.eq(Trade.confirmReason(cfg, 100, 104.9, 50, 10), "wait")
	H.eq(Trade.confirmReason(cfg, 100, 105, 9, 10), "fee")
	H.eq(Trade.confirmReason(cfg, 100, 105, 10, 10), nil)
	H.eq(Trade.roomFor(60, 4, 4, 60), true, "full storage swaps evenly")
	H.eq(Trade.roomFor(60, 4, 3, 60), false)
end)

H.finish("trade")
