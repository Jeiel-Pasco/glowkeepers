-- Sim parity: the Luau modules reproduce sim/golden_odds.json (TECH_SPEC §14).
-- Regenerate the file with `python sim/golden_odds.py` after changing config/economy.json.
local H = require("./harness")
local Cycle = require("../src/shared/Cycle")
local Economy = require("../src/shared/Economy")
local Fire = require("../src/shared/Fire")
local Roll = require("../src/shared/Roll")

local cfg = H.config()
local golden = H.json("sim/golden_odds.json")

H.test("rarity odds match the sim to within 1e-9", function()
	H.ok(#golden.rarity > 0, "golden rows")
	for _, row in golden.rarity do
		local probs = Roll.distribution(cfg, row.luck, row.floor)
		H.eq(#probs, #row.probs, "tier count")
		for tier, expected in row.probs do
			H.near(probs[tier], expected, 1e-9, `luck {row.luck} floor {row.floor} tier {tier}`)
		end
	end
end)

H.test("luck matches", function()
	for _, row in golden.luck do
		local value = Economy.luck(cfg, row.lantern, row.stars, { fireSurvived = row.fireSurvived })
		H.near(value, row.value, 1e-12, `Lantern {row.lantern} Star {row.stars}`)
	end
end)

H.test("rebirth thresholds match", function()
	for i, expected in golden.rebirth do
		H.rel(Economy.rebirthRequirement(cfg, i - 1), expected, 1e-12, `Star {i - 1}`)
	end
end)

H.test("upgrade and lure prices match", function()
	for id, prices in golden.upgrades do
		for i, expected in prices do
			H.eq(Economy.upgradeCost(cfg, id, i - 1), expected, `{id} level {i - 1}`)
		end
		H.eq(Economy.upgradeCost(cfg, id, #prices), nil, `{id} stops at its max`)
	end
	for floor, expected in golden.lures do
		H.eq(Economy.lureCost(cfg, floor), expected, `lure {floor}`)
	end
end)

H.test("whole-night fire outcomes match", function()
	for _, case in golden.fire do
		local feeds = {}
		for _, feed in case.feeds do
			table.insert(feeds, { t = feed[1], kind = feed[2] })
		end
		local outcome = Fire.simulate(cfg, case.players, feeds, Cycle.modifier(cfg, case.modifier))
		H.eq(outcome.survived, case.survived, case.name)
		H.near(outcome.level, case.level, 1e-9, `{case.name}: level`)
		if case.lostAt ~= nil then
			H.near(outcome.lostAt :: number, case.lostAt, 1e-9, `{case.name}: lostAt`)
		else
			H.eq(outcome.lostAt, nil, `{case.name}: survived`)
		end
	end
end)

H.finish("golden")
