-- Store rules (GAME_SYSTEMS §23).
local H = require("./harness")
local Store = require("../src/shared/Store")

local cfg = H.config()
local products = H.json("config/products.json")

local function check(over: any?): any
	local base = {
		key = "embers120",
		id = 1,
		killed = false,
		paidRandomRestricted = false,
		owned = false,
		daily = { day = 0, buys = {} },
		carrying = false,
		now = 1000,
		lostGlowlingAt = 0,
		lostNightAt = 0,
		season = 1,
		premium = false,
	}
	for k, v in over or {} do
		base[k] = v
	end
	return base
end

H.test("config: every key has an id slot in each environment", function()
	for _, env in { "DEV", "BETA", "PROD" } do
		for _, p in cfg.store.passes do
			H.ok(products[env].passes[p.key] ~= nil, `{env} pass {p.key}`)
		end
		for _, p in cfg.store.products do
			H.ok(products[env].products[p.key] ~= nil, `{env} product {p.key}`)
		end
	end
	H.eq(#Store.keys(cfg), 10)
	local Net = require("../src/shared/Net")
	H.eq(
		table.concat(Net.remotes.PromptProduct.args[1].values, ","),
		table.concat(Store.keys(cfg), ","),
		"PromptProduct enum = store keys"
	)
end)

H.test("prompt: unknown, unavailable, policy, owned", function()
	H.eq(Store.canPrompt(cfg, check()), nil)
	H.eq(Store.canPrompt(cfg, check({ key = "nope" })), "unknown")
	H.eq(Store.canPrompt(cfg, check({ id = 0 })), "unavailable")
	H.eq(Store.canPrompt(cfg, check({ killed = true })), "unavailable")
	H.eq(Store.canPrompt(cfg, check({ key = "serverLuck", paidRandomRestricted = true })), "policy")
	H.eq(Store.canPrompt(cfg, check({ key = "embers120", paidRandomRestricted = true })), nil, "not paid random")
	H.eq(Store.canPrompt(cfg, check({ key = "vip", owned = true })), "owned")
	H.eq(Store.canPrompt(cfg, check({ key = "vip", owned = true, id = 0 })), "owned", "before unavailable")
end)

H.test("prompt: daily caps per group, quiet after a loss, premium", function()
	local daily = { day = 0, buys = { embers = 3 } }
	H.eq(Store.canPrompt(cfg, check({ key = "embers2400", daily = daily })), "cap", "3 Ember packs of any size")
	H.eq(Store.canPrompt(cfg, check({ key = "lockCharge3", daily = daily })), nil)
	H.eq(Store.canPrompt(cfg, check({ carrying = true })), "busy")
	H.eq(Store.canPrompt(cfg, check({ lostGlowlingAt = 975 })), "busy", "25 s after a loss")
	H.eq(Store.canPrompt(cfg, check({ lostGlowlingAt = 970 })), nil, "30 s after")
	H.eq(Store.canPrompt(cfg, check({ lostNightAt = 990 })), "busy")
	H.eq(Store.canPrompt(cfg, check({ key = "passPremium", season = 0 })), "no_season")
	H.eq(Store.canPrompt(cfg, check({ key = "passPremium", premium = true })), "premium_owned")
end)

H.test("daily counts roll with the UTC day", function()
	local daily = { day = 0, buys = {} }
	Store.rollDay(daily, 86400 * 5 + 10)
	Store.countBuy(daily, "embers")
	Store.countBuy(daily, "embers")
	H.eq(Store.boughtToday(daily, "embers"), 2)
	Store.rollDay(daily, 86400 * 5 + 86399)
	H.eq(Store.boughtToday(daily, "embers"), 2, "same day")
	Store.rollDay(daily, 86400 * 6)
	H.eq(Store.boughtToday(daily, "embers"), 0)
end)

H.test("receipts: a duplicate is refused, only the newest are kept", function()
	local receipts = {}
	H.eq(Store.recordReceipt(receipts, "a", 1, 2), true)
	H.eq(Store.recordReceipt(receipts, "a", 2, 2), false, "duplicate")
	Store.recordReceipt(receipts, "b", 2, 2)
	Store.recordReceipt(receipts, "c", 3, 2)
	H.eq(receipts.a, nil, "oldest pruned")
	H.eq(receipts.c, 3)
end)

H.test("server luck: +15 min, queued up to 60", function()
	H.eq(Store.extendLuck(cfg, 0, 1000), 1000 + 900)
	H.eq(Store.extendLuck(cfg, 1900, 1000), 1000 + 1800, "extends from the current end")
	H.eq(Store.extendLuck(cfg, 1000 + 3500, 1000), 1000 + 3600, "capped at 60 min")
	H.eq(Store.serverLuckMult(cfg, 1500, 1000), 1.5)
	H.eq(Store.serverLuckMult(cfg, 1000, 1000), 1)
end)

H.finish("store")
