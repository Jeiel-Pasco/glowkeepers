-- Decorations and base names (GAME_SYSTEMS §18).
local H = require("./harness")
local Decor = require("../src/shared/Decor")

local cfg = H.config()

local function decor(owned: any?, placed: any?): any
	return { owned = owned or {}, placed = placed or {} }
end

H.test("config: 24 items for sale plus the gift arch, prices 20-400, even footprints", function()
	local forSale = 0
	for _, item in cfg.decor.items do
		if not item.exclusive then
			forSale += 1
			H.ok(item.price >= 20 and item.price <= 400, item.id)
		end
		H.eq(item.w % cfg.decor.grid, 0, item.id .. " w")
		H.eq(item.d % cfg.decor.grid, 0, item.id .. " d")
	end
	H.eq(forSale, 24)
	H.ok(Decor.item(cfg, "gift_lantern_arch") ~= nil, "the daily gift's day-28 decoration exists")
	H.eq(#cfg.decor.nameAdjectives, 64)
	H.eq(#cfg.decor.nameNouns, 64)
end)

H.test("buy: price, or unknown / not_for_sale / max_owned / too_poor", function()
	H.eq(Decor.canBuy(cfg, decor(), 100, "hedge"), 40)
	H.eq(select(2, Decor.canBuy(cfg, decor(), 100, "nope")), "unknown")
	H.eq(select(2, Decor.canBuy(cfg, decor(), 1000, "gift_lantern_arch")), "not_for_sale")
	H.eq(select(2, Decor.canBuy(cfg, decor({ hedge = cfg.decor.maxPerItem }), 1000, "hedge")), "max_owned")
	H.eq(select(2, Decor.canBuy(cfg, decor(), 39, "hedge")), "too_poor")
end)

H.test("place: owned copies, grid, bounds, rotation", function()
	local d = decor({ hedge = 1 })
	H.eq(Decor.canPlace(cfg, d, { id = "hedge", x = 0, z = 0, rot = 0 }), nil)
	H.eq(Decor.canPlace(cfg, d, { id = "pond", x = 0, z = 0, rot = 0 }), "not_owned")
	H.eq(Decor.canPlace(cfg, d, { id = "hedge", x = 1, z = 0, rot = 0 }), "off_grid")
	H.eq(Decor.canPlace(cfg, d, { id = "hedge", x = 0, z = 0, rot = 4 }), "bad_rot")
	H.eq(Decor.canPlace(cfg, d, { id = "hedge", x = 10, z = 0, rot = 0 }), nil, "4 wide at x=10 reaches 12")
	H.eq(Decor.canPlace(cfg, d, { id = "hedge", x = 12, z = 0, rot = 0 }), "out_of_bounds")
	H.eq(Decor.canPlace(cfg, d, { id = "hedge", x = 0, z = 10, rot = 1 }), nil, "turned: 4 deep at z=10")
	H.eq(Decor.canPlace(cfg, d, { id = "hedge", x = 0, z = 12, rot = 1 }), "out_of_bounds")
end)

H.test("place: overlap, touching edges, all copies placed, cap", function()
	local d = decor({ hedge = 3 }, { { id = "hedge", x = 0, z = 0, rot = 0 } })
	H.eq(Decor.canPlace(cfg, d, { id = "hedge", x = 2, z = 0, rot = 0 }), "overlap")
	H.eq(Decor.canPlace(cfg, d, { id = "hedge", x = 4, z = 0, rot = 0 }), nil, "edges touch")
	H.eq(Decor.canPlace(cfg, d, { id = "hedge", x = 0, z = 2, rot = 0 }), nil, "2 deep: touches")
	local full = decor({ hedge = 1 }, { { id = "hedge", x = 0, z = 0, rot = 0 } })
	H.eq(Decor.canPlace(cfg, full, { id = "hedge", x = 6, z = 6, rot = 0 }), "not_owned")
	local many = {}
	for i = 1, cfg.decor.maxPlaced do
		many[i] = { id = "glow_mushrooms", x = 100 + i * 2, z = 100, rot = 0 }
	end
	H.eq(Decor.canPlace(cfg, decor({ hedge = 1 }, many), { id = "hedge", x = 0, z = 0, rot = 0 }), "cap")
end)

H.test("find and freeSpot", function()
	local d = decor({ pond = 2 }, { { id = "pond", x = -9, z = -10, rot = 0 } })
	H.eq(Decor.find(d.placed, "pond", -9, -10), 1)
	H.eq(Decor.find(d.placed, "pond", 0, 0), nil)
	local x, z = Decor.freeSpot(cfg, decor({ pond = 2 }), "pond", 0)
	H.eq(x, -8)
	H.eq(z, -10)
	local packed = decor({ pond = 1 }, { { id = "pond", x = -8, z = -10, rot = 0 } })
	H.eq(Decor.freeSpot(cfg, packed, "pond", 0), nil, "the only copy is placed")
end)

H.test("base name", function()
	H.eq(Decor.baseName(cfg, 1, 1), "Mossy Hollow")
	H.eq(Decor.baseName(cfg, 0, 1), "")
	H.eq(Decor.baseName(cfg, 65, 1), "")
end)

H.finish("decor")
