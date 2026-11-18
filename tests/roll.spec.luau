-- Roll: rarity, pity, lures, mutation, size (GAME_SYSTEMS §4–5).
local H = require("./harness")
local Roll = require("../src/shared/Roll")

local cfg = H.config()

local function sum(list: { number }): number
	local total = 0
	for _, value in list do
		total += value
	end
	return total
end

-- GAME_SYSTEMS §4 odds table, in percent.
local GDD_TABLE = {
	{ luck = 1, pct = { 75.16, 18.79, 4.945, 0.999, 0.100, 0.010, 0.001 } },
	{ luck = 3, pct = { 65.74, 16.44, 14.50, 2.99, 0.300, 0.030, 0.003 } },
	{ luck = 10, pct = { 35.60, 8.90, 44.50, 9.89, 0.999, 0.100, 0.010 } },
}

H.test("odds match the GAME_SYSTEMS §4 table to 4 significant figures", function()
	for _, row in GDD_TABLE do
		local probs = Roll.distribution(cfg, row.luck, 1)
		for tier, expected in row.pct do
			H.rel(probs[tier] * 100, expected, 1e-3, `luck {row.luck} tier {tier}`)
		end
	end
end)

H.test("distribution sums to 1 for every luck and floor", function()
	for _, luck in { 1, 2, 5, 10, 30, 1000 } do
		for floor = 1, 4 do
			H.near(sum(Roll.distribution(cfg, luck, floor)), 1, 1e-12, `luck {luck} floor {floor}`)
		end
	end
end)

H.test("lure floors at luck 1 (§4 lure table)", function()
	H.rel(Roll.distribution(cfg, 1, 2)[2], 0.939, 1e-3, "Uncommon lure → Uncommon")
	H.rel(Roll.distribution(cfg, 1, 3)[3], 0.989, 1e-3, "Rare lure → Rare")
	H.rel(Roll.distribution(cfg, 1, 4)[4], 0.999, 1e-3, "Epic lure → Epic")
	local epic1 = Roll.distribution(cfg, 1, 4)
	H.rel(epic1[5] + epic1[6] + epic1[7], 0.00111, 1e-3, "Epic lure Legendary+ at luck 1 (0.11%)")
	local epic5 = Roll.distribution(cfg, 5, 4)
	H.rel(epic5[5] + epic5[6] + epic5[7], 0.005547, 1e-3, "Epic lure Legendary+ at luck 5 (0.56%)")
end)

H.test("rarity: all draws fail → floor; first draw passes → Secret", function()
	H.eq(Roll.rarity(cfg, 1, 1, H.constant(0.999999)), 1, "floor Common")
	H.eq(Roll.rarity(cfg, 1, 3, H.constant(0.999999)), 3, "floor Rare")
	H.eq(Roll.rarity(cfg, 1, 1, H.constant(0)), 7, "Secret")
	H.throws(function()
		Roll.rarity(cfg, 1, 8, H.constant(0.5))
	end, "floor above Secret")
end)

H.test("luck is capped at 50% per tier", function()
	local probs = Roll.distribution(cfg, 1e9, 1)
	H.near(probs[7], 0.5, 1e-12, "Secret capped")
	H.near(probs[2], 0.2 * 0.5 ^ 5, 1e-12, "Uncommon gets no luck")
end)

H.test("200k sampled rolls land within 4 sigma of the exact odds", function()
	local n = 200000
	local rng = H.rng(20261118)
	local counts = table.create(7, 0)
	for _ = 1, n do
		local tier = Roll.rarity(cfg, 1, 1, rng)
		counts[tier] += 1
	end
	local probs = Roll.distribution(cfg, 1, 1)
	for tier = 1, 4 do
		local p = probs[tier]
		local sigma = math.sqrt(p * (1 - p) / n)
		H.near(counts[tier] / n, p, 4 * sigma, `tier {tier}`)
	end
end)

H.test("pity: 150 night catches below Legendary guarantee the next one (§5)", function()
	local miss = H.constant(0.999999)
	local tier, pity = Roll.nightRarity(cfg, 1, 149, miss)
	H.eq(tier, 1, "149 → normal roll")
	H.eq(pity, 150, "counter after a miss")
	tier, pity = Roll.nightRarity(cfg, 1, 150, miss)
	H.eq(tier, 5, "150 → Legendary")
	H.eq(pity, 0, "counter resets")
	tier, pity = Roll.nightRarity(cfg, 1, 10, H.constant(0))
	H.eq(tier, 7, "natural Secret")
	H.eq(pity, 0, "a natural Legendary+ resets too")
	H.eq(Roll.nightOdds(cfg, 1, 150)[1], 0, "odds tab shows no Common at 150")
end)

H.test("lures: floor holds, results can roll higher, resultCap caps", function()
	H.eq(Roll.lureRarity(cfg, 1, 4, H.constant(0.999999)), 4, "Epic lure floor")
	H.eq(Roll.lureRarity(cfg, 1, 4, H.constant(0)), 7, "Epic lure can land Secret")
	H.throws(function()
		Roll.lureRarity(cfg, 1, 5, H.constant(0.5))
	end, "floor above maxFloor")

	local capped = H.config()
	capped.lures.resultCap = 4
	H.eq(Roll.lureRarity(capped, 1, 2, H.constant(0)), 4, "capped at Epic")
	local odds = Roll.lureOdds(capped, 1, 2)
	H.near(sum(odds), 1, 1e-12, "capped odds sum")
	H.eq(odds[5] + odds[6] + odds[7], 0, "nothing above the cap")
end)

H.test("mutation: one draw, rarest first; Moonlit checked first on event nights", function()
	H.eq(Roll.mutation(cfg, H.sequence({ 0.004 })), 2, "Rainbow under 1/200")
	H.eq(Roll.mutation(cfg, H.sequence({ 0.0499 })), 1, "Golden under 1/20")
	H.eq(Roll.mutation(cfg, H.sequence({ 0.05 })), 0, "1/20 itself is no mutation")
	local events = { Moonlit = true }
	H.eq(Roll.mutation(cfg, H.sequence({ 0.005 }), events), 3, "Moonlit first")
	H.eq(Roll.mutation(cfg, H.sequence({ 0.5, 0.004 }), events), 2, "then the normal draw")
	H.eq(Roll.mutation(cfg, H.sequence({ 0.005 })), 1, "Moonlit is event-only")
end)

H.test("mutation odds: Golden 4.5%, Rainbow 0.5%", function()
	local odds = Roll.mutationOdds(cfg)
	H.near(odds[1], 0.045, 1e-12, "Golden")
	H.near(odds[2], 0.005, 1e-12, "Rainbow")
	H.near(odds[0], 0.95, 1e-12, "none")
	H.eq(odds[3], nil, "no Moonlit outside events")
	local moon = Roll.mutationOdds(cfg, { Moonlit = true })
	H.near(moon[3], 0.01, 1e-12, "Moonlit")
	H.near(moon[1], 0.045 * 0.99, 1e-12, "Golden on a Moonlit night")
	H.near(moon[0] + moon[1] + moon[2] + moon[3], 1, 1e-12, "sum")
end)

H.test("size: 0.80–1.30 in 0.01 steps, with labels", function()
	H.eq(Roll.size(cfg, H.constant(0)), 0.8, "min")
	H.eq(Roll.size(cfg, H.constant(0.999999)), 1.3, "max")
	H.eq(Roll.size(cfg, H.constant(0.5)), 1.05, "middle")
	local rng = H.rng(7)
	for _ = 1, 1000 do
		local s = Roll.size(cfg, rng)
		H.ok(s >= 0.8 and s <= 1.3, "in range")
		H.near(s * 100, math.floor(s * 100 + 0.5), 1e-9, "two decimals")
	end
	H.eq(Roll.sizeLabel(0.85), "Tiny", "Tiny")
	H.eq(Roll.sizeLabel(1.0), nil, "no label")
	H.eq(Roll.sizeLabel(1.2), "Big", "Big")
	H.eq(Roll.sizeLabel(1.28), "Huge", "Huge")
end)

H.test("finish draws mutation, then size", function()
	local result = Roll.finish(cfg, 5, H.sequence({ 0.01, 0 }))
	H.eq(result.r, 5, "rarity kept")
	H.eq(result.m, 1, "Golden")
	H.eq(result.s, 0.8, "size")
end)

H.test("species pools come from config/species.json", function()
	local speciesCfg = H.json("config/species.json")
	local clearing = Roll.pool(speciesCfg, "Clearing")
	H.eq(#clearing, 16, "Clearing species")
	H.eq(#Roll.pool(speciesCfg, "Deepwood"), 24, "Deepwood species")
	H.eq(#Roll.pool(speciesCfg, "Nowhere"), 0, "unknown pool")
	H.eq(clearing[1], "glimmermouse", "config order")
end)

H.test("species pick is uniform and stays inside the pool", function()
	local ids = { "a", "b", "c", "d" }
	H.eq(Roll.species(ids, H.constant(0)), "a", "lowest draw")
	H.eq(Roll.species(ids, H.constant(0.2499)), "a", "first quarter")
	H.eq(Roll.species(ids, H.constant(0.25)), "b", "second quarter")
	H.eq(Roll.species(ids, H.constant(0.999999)), "d", "highest draw")
	H.eq(Roll.species(ids, H.constant(1)), "d", "a draw of exactly 1 still lands inside")
	local counts = { a = 0, b = 0, c = 0, d = 0 }
	local rng = H.rng(7)
	for _ = 1, 40000 do
		local id = Roll.species(ids, rng)
		counts[id] += 1
	end
	for id, n in counts do
		H.near(n / 40000, 0.25, 0.01, `share of {id}`)
	end
	H.throws(function()
		Roll.species({}, rng)
	end, "empty pool")
end)

H.finish("roll")
