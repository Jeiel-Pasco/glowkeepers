-- Economy: luck, income, rebirth, slots, upgrades, lures (GAME_SYSTEMS §4, §6–9, §15).
local H = require("./harness")
local Economy = require("../src/shared/Economy")
local EconomyMath = require("../src/shared/EconomyMath")
local Cycle = require("../src/shared/Cycle")

local cfg = H.config()

H.test("luck = (1 + 0.12 L)(1 + 0.06 S) × bonuses", function()
	H.eq(Economy.luck(cfg, 0, 0), 1, "base")
	H.near(Economy.luck(cfg, 10, 2), 2.2 * 1.12, 1e-12, "Lantern 10, Star 2")
	H.near(Economy.luck(cfg, 10, 2, { fireSurvived = true }), 2.2 * 1.12 * 1.25, 1e-12, "fire survived")
	H.near(Economy.luck(cfg, 0, 0, { serverLuck = true, eventMult = 2 }), 3, 1e-12, "Server Luck and an event")
end)

H.test("income: base × mutation × size, then the Star bonus", function()
	H.eq(Economy.glowlingValue(cfg, 5, 1, 1.2), 2400, "Golden Legendary 1.2")
	H.eq(Economy.glowlingValue(cfg, 1, 0, 1), 1, "plain Common")
	H.near(Economy.incomePerSec(cfg, { 10, 20 }, 2), 51, 1e-12, "30 × 1.7")
	H.near(Economy.incomePerSec(cfg, { 10 }, 0, 1.5), 15, 1e-12, "VIP-style extra")
	H.eq(Economy.incomePerSec(cfg, {}, 5), 0, "empty base")
end)

H.test("rebirth: 250K × 3.2^k, then 2.0× per Star after Star 8 (D8)", function()
	H.eq(Economy.rebirthRequirement(cfg, 0), 250000, "Star 0")
	H.near(Economy.rebirthRequirement(cfg, 1), 800000, 1e-6, "Star 1")
	local star8 = 250000 * 3.2 ^ 8
	H.rel(Economy.rebirthRequirement(cfg, 8), star8, 1e-12, "Star 8")
	H.rel(Economy.rebirthRequirement(cfg, 9), star8 * 2, 1e-12, "Star 9 uses the step")
	local flat = H.config()
	flat.rebirth.stepEnabled = false
	H.rel(Economy.rebirthRequirement(flat, 9), 250000 * 3.2 ^ 9, 1e-12, "without the step")
end)

H.test("big numbers: thresholds stay exact (below 2^53) through Star 28 (TECH_SPEC §5)", function()
	for stars = 0, 28 do
		H.ok(Economy.rebirthRequirement(cfg, stars) < 2 ^ 53, `Star {stars}`)
	end
	H.ok(Economy.rebirthRequirement(cfg, 30) > 2 ^ 53, "Star 30 passes 2^53, as documented")
end)

H.test("slots and the vault", function()
	H.eq(Economy.slotCount(cfg, 0), 8, "start with 8")
	H.eq(Economy.vaultSlots(cfg, 8, 0), 3, "3 vault slots at Star 0")
	H.eq(Economy.displaySlots(cfg, 8, 0), 5, "5 display slots")
	H.eq(Economy.vaultSlots(cfg, 8, 5), 8, "Star 5 after rebirth: all 8 are vault")
	H.eq(Economy.vaultSlots(cfg, 12, 2, 2), 7, "pass adds 2")
end)

H.test("upgrade prices match the sim and the §9 samples", function()
	H.eq(Economy.upgradeCost(cfg, "lantern", 1), 232, "Lantern 1")
	H.eq(Economy.upgradeCost(cfg, "lantern", 10), 12006, "Lantern 10")
	H.eq(Economy.upgradeCost(cfg, "lantern", 20), 961004, "Lantern 20")
	H.eq(Economy.upgradeCost(cfg, "slots", 0), 250, "slot 9 (sim_v3 prices the first slot at 250)")
	H.eq(Economy.upgradeCost(cfg, "boots", 2), 337, "Boots 2")
	H.eq(Economy.upgradeCost(cfg, "lantern", 60), nil, "Lantern max 60")
	H.eq(Economy.upgradeCost(cfg, "slots", 22), nil, "30 slots max")
	H.eq(Economy.upgradeMax(cfg, "slots"), 22, "22 slot levels")
	H.eq(Economy.upgradeCost(cfg, "lantern", 7), EconomyMath.levelCost(150, 1.55, 7), "same as EconomyMath")
end)

H.test("lures: 40 × 14^(floor − 1) and stock 16/8/4/2", function()
	local prices = { 40, 560, 7840, 109760 }
	local stock = { 16, 8, 4, 2 }
	for floor = 1, 4 do
		H.eq(Economy.lureCost(cfg, floor), prices[floor], `price {floor}`)
		H.eq(Economy.lureStock(cfg, floor), stock[floor], `stock {floor}`)
	end
	H.throws(function()
		Economy.lureCost(cfg, 5)
	end, "no Legendary lure")
end)

H.test("restock on the UTC 5-minute boundary", function()
	H.eq(Economy.restockWindow(cfg, 600), 2, "window")
	H.eq(Economy.secondsToRestock(cfg, 600), 300, "fresh window")
	H.eq(Economy.secondsToRestock(cfg, 899), 1, "about to restock")
end)

H.test("night catches, run speed, release, lock charges, lost nights", function()
	H.eq(Economy.nightCatches(cfg, 0), 3, "base")
	H.eq(Economy.nightCatches(cfg, 24), 7, "Boots 24")
	H.eq(Economy.nightCatches(cfg, 25, Cycle.modifier(cfg, "FireflyBloom")), 9, "Boots 25 + Firefly Bloom")
	H.eq(Economy.runSpeed(cfg, 0, false, false), 22, "run")
	H.near(Economy.runSpeed(cfg, 25, true, true), 22 * 2 * 1.15 * 0.85, 1e-9, "everything")
	H.eq(Economy.releaseValue(cfg, 100, 2), 10200, "60 s of income with Stars")
	H.eq(Economy.lockChargeGlow(cfg, 0), 200, "minimum")
	H.eq(Economy.lockChargeGlow(cfg, 10), 1200, "120 s of income")
	H.eq(Economy.nightLostPenalty(cfg, 1000), 50, "5%")
	H.eq(Economy.nightLostPenalty(cfg, -10), 0, "never negative")
end)

H.test("offline: 10% for at most 6 h (§6 acceptance)", function()
	local inc = cfg.income
	H.eq(EconomyMath.offlineIncome(9 * 3600, 10, inc.offlineCapHours, inc.offlineEfficiency), 21600, "9 h pays 6 h")
	H.eq(EconomyMath.offlineIncome(-60, 10, inc.offlineCapHours, inc.offlineEfficiency), 0, "clock went back")
end)

H.finish("economy")
