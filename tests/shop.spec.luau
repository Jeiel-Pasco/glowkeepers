-- Shop: lure stock per restock window and the purchase rules (GAME_SYSTEMS §8).
local H = require("./harness")
local Shop = require("../src/shared/Shop")
local Economy = require("../src/shared/Economy")

local cfg = H.config()

local function check(overrides: { [string]: any }?): any
	local c = { floor = 1, price = Economy.lureCost(cfg, 1), glow = 1000, left = 16, storage = 0 }
	for key, value in overrides or {} do
		c[key] = value
	end
	return c
end

H.test("prices and stock per restock: 40 / 560 / 7,840 / 109,760 and 16 / 8 / 4 / 2", function()
	local prices, stocks = {}, {}
	for floor = 1, cfg.lures.maxFloor do
		prices[floor] = Economy.lureCost(cfg, floor)
		stocks[floor] = Shop.left(cfg, nil, 1, floor)
	end
	H.eq(table.concat(prices, ","), "40,560,7840,109760", "prices")
	H.eq(table.concat(stocks, ","), "16,8,4,2", "full stock")
end)

H.test("stock counts down within a window and resets at the boundary", function()
	local window = Economy.restockWindow(cfg, 1_800_000_123)
	local record = nil
	for _ = 1, 3 do
		record = Shop.bought(cfg, record, window, 2)
	end
	H.eq(Shop.left(cfg, record, window, 2), 5, "8 - 3 Uncommon")
	H.eq(Shop.left(cfg, record, window, 1), 16, "other lures untouched")
	H.eq(Shop.left(cfg, record, window + 1, 2), 8, "next window: full again")
	local fresh = Shop.bought(cfg, record, window + 1, 1)
	H.eq(fresh.bought[2], 0, "unused stock doesn't carry over")
	H.eq(fresh.bought[1], 1, "the new purchase")
	H.eq(Shop.left(cfg, "garbage", window, 3), 4, "a damaged record reads as full stock")
end)

H.test("the restock boundary is the same everywhere: os.time() // 300", function()
	H.eq(Economy.restockWindow(cfg, 599), 1, "window 1")
	H.eq(Economy.restockWindow(cfg, 600), 2, "the boundary")
	H.eq(Economy.secondsToRestock(cfg, 599), 1, "one second left")
end)

H.test("rules: sold out, storage full, too poor (no partial charge)", function()
	H.ok((Shop.canBuyLure(cfg, check())), "ok")
	H.eq(select(2, Shop.canBuyLure(cfg, check({ left = 0 }))), "sold_out", "sold out")
	H.eq(select(2, Shop.canBuyLure(cfg, check({ storage = cfg.storage.size }))), "storage_full", "storage at its cap")
	H.eq(select(2, Shop.canBuyLure(cfg, check({ glow = 39 }))), "too_poor", "too poor")
	H.eq(select(2, Shop.canBuyLure(cfg, check({ floor = 5 }))), "unknown", "no such lure")
end)

H.finish("shop")
