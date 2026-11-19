-- How bases look as they grow (Shared.BaseTier).
local H = require("./harness")
local BaseTier = require("../src/shared/BaseTier")
local economy = H.json("config/economy.json")

H.test("free plots are an empty clearing", function()
	H.eq(BaseTier.tier(30, false), 0)
	H.eq(BaseTier.look(8, false).home, nil)
end)

H.test("a new keeper starts in a tent and the max base is the sanctuary", function()
	local slots = economy.upgrades.slots
	H.eq(BaseTier.look(slots.start, true).home, "Tent")
	H.eq(BaseTier.look(slots.max, true).home, "Sanctuary")
	H.eq(BaseTier.tier(slots.max - 1, true), 4, "the top tier is only for a maxed base")
end)

H.test("every pad count maps to a tier that never goes down", function()
	local last = 0
	for slots = economy.upgrades.slots.start, economy.upgrades.slots.max do
		local tier = BaseTier.tier(slots, true)
		H.eq(tier >= last and tier >= 1 and tier <= 5, true, `slots {slots}`)
		last = tier
	end
	H.eq(last, 5)
end)

H.finish("basetier")
