--!strict
-- Glowkeepers-specific economy formulas (GAME_SYSTEMS §4, §6–9, §15).
--
-- Pure: pass config/economy.json in as `cfg`. Generic maths (buy max, trySpend, offline
-- earnings, sanitizers, number formatting) lives in EconomyMath. Formulas that the sim also
-- uses are checked against sim/golden_odds.json by tests/golden.spec.luau.

local Economy = {}

export type LuckOptions = {
	fireSurvived: boolean?, -- last night's fire survived: ×1.25
	eventMult: number?, -- live event multiplier
	serverLuck: boolean?, -- Server Luck product active: ×1.5
}

-- (1 + 0.12 × Lantern) × (1 + 0.06 × Stars) × the active bonuses.
function Economy.luck(cfg: any, lantern: number, stars: number, options: LuckOptions?): number
	local lk = cfg.luck
	local luck = (1 + lk.perLanternLevel * lantern) * (1 + lk.perStar * stars)
	if options then
		if options.fireSurvived then
			luck *= lk.fireSurvivedMult
		end
		if options.eventMult then
			luck *= options.eventMult
		end
		if options.serverLuck then
			luck *= lk.serverLuckMult
		end
	end
	return luck
end

-- Glow per second of one Glowling before the Star bonus: base × mutation × size.
function Economy.glowlingValue(cfg: any, r: number, m: number, s: number): number
	local mult = if m > 0 then cfg.mutations[m].mult else 1
	return cfg.rarities[r].glowPerSec * mult * s
end

-- 1 + 0.35 × Stars, times any extra multiplier (VIP, events).
function Economy.incomeMultiplier(cfg: any, stars: number, extra: number?): number
	return (1 + cfg.income.starBonus * stars) * (extra or 1)
end

-- Every placed Glowling earns (vault and display slots). `values` are glowlingValue results.
function Economy.incomePerSec(cfg: any, values: { number }, stars: number, extra: number?): number
	local sum = 0
	for _, value in values do
		sum += value
	end
	return sum * Economy.incomeMultiplier(cfg, stars, extra)
end

-- Glow to earn since the last rebirth to reach the next Star: 250,000 × 3.2^k, and 2.0× per
-- Star after Star 8 (D8). k = current Stars.
function Economy.rebirthRequirement(cfg: any, stars: number): number
	local rb = cfg.rebirth
	if rb.stepEnabled and stars > rb.stepAfterStar then
		local s = rb.stepAfterStar
		return rb.baseRequirement * rb.growth ^ s * rb.growthAfterStep ^ (stars - s)
	end
	return rb.baseRequirement * rb.growth ^ stars
end

-- Slots: the profile stores levels bought beyond the starting 8.
function Economy.slotCount(cfg: any, slotLevel: number): number
	return cfg.upgrades.slots.start + slotLevel
end

-- The first 3 + Stars slots (+ extra, e.g. 2 with the pass) are vault slots, capped at the slot count.
function Economy.vaultSlots(cfg: any, slotCount: number, stars: number, extra: number?): number
	return math.min(slotCount, cfg.vault.start + cfg.vault.perStar * stars + (extra or 0))
end

function Economy.displaySlots(cfg: any, slotCount: number, stars: number, extra: number?): number
	return slotCount - Economy.vaultSlots(cfg, slotCount, stars, extra)
end

function Economy.upgradeMax(cfg: any, id: string): number
	local upgrade = cfg.upgrades[id]
	assert(upgrade ~= nil, "unknown upgrade")
	if id == "slots" then
		return upgrade.max - upgrade.start
	end
	return upgrade.max
end

-- Price of the next level when `level` are owned: floor(base × growth^level), the same
-- expression as EconomyMath.levelCost. nil at the max level.
function Economy.upgradeCost(cfg: any, id: string, level: number): number?
	if level >= Economy.upgradeMax(cfg, id) then
		return nil
	end
	local upgrade = cfg.upgrades[id]
	return math.floor(upgrade.baseCost * upgrade.growth ^ level)
end

-- Lure price = 40 × 14^(floor − 1); floor is the rarity index (1 Common .. 4 Epic).
function Economy.lureCost(cfg: any, floor: number): number
	assert(floor >= 1 and floor <= cfg.lures.maxFloor, "lure floor out of range")
	return math.floor(cfg.lures.baseCost * cfg.lures.growth ^ (floor - 1))
end

function Economy.lureStock(cfg: any, floor: number): number
	return cfg.lures.stockPerRestock[floor] or 0
end

-- Restocks happen on the UTC boundary, so every server agrees (GAME_SYSTEMS §8).
function Economy.restockWindow(cfg: any, unixTime: number): number
	return unixTime // cfg.shop.restockSeconds
end

function Economy.secondsToRestock(cfg: any, unixTime: number): number
	local period = cfg.shop.restockSeconds
	return period - unixTime % period
end

-- Night catches = 3 + floor(Boots / 5), plus the modifier's extra catches.
function Economy.nightCatches(cfg: any, boots: number, modifier: any?): number
	local extra = if modifier ~= nil and modifier.extraCatches ~= nil then modifier.extraCatches else 0
	return cfg.night.baseCatches + boots // cfg.upgrades.boots.levelsPerExtraCatch + extra
end

-- Run speed = 22 × (1 + 0.04 × Boots) × (1.15 with Swift Boots), ×0.85 while carrying.
function Economy.runSpeed(cfg: any, boots: number, swiftBoots: boolean, carrying: boolean): number
	local speed = cfg.movement.run * (1 + cfg.upgrades.boots.speedPerLevel * boots)
	if swiftBoots then
		speed *= cfg.movement.swiftBootsMult
	end
	if carrying then
		speed *= cfg.steal.carrySpeedMult
	end
	return speed
end

-- Release pays 60 s of that Glowling's current income (Star bonus included).
function Economy.releaseValue(cfg: any, value: number, stars: number, extra: number?): number
	return math.floor(value * cfg.storage.releaseIncomeSeconds * Economy.incomeMultiplier(cfg, stars, extra))
end

-- Levels of an upgrade that `money` Glow buys from `level` owned: one level, or with `all` as
-- many as it affords ("Buy max", walking the real price list up to the max). Returns the count
-- and the total price; (0, 0) when it's maxed or the next level is unaffordable.
function Economy.upgradePurchase(cfg: any, id: string, level: number, money: number, all: boolean): (number, number)
	local count, total = 0, 0
	while true do
		local price = Economy.upgradeCost(cfg, id, level + count)
		if price == nil or total + price > money then
			break
		end
		total += price
		count += 1
		if not all then
			break
		end
	end
	return count, total
end

-- A Lock Charge costs Glow (lockChargeGlow) or a flat number of Embers.
function Economy.lockChargePrice(cfg: any, currency: string, perSec: number): number
	return if currency == "embers" then cfg.lock.chargeEmbers else Economy.lockChargeGlow(cfg, perSec)
end

-- Lock Charge price in Glow: max(200, 120 s of income).
function Economy.lockChargeGlow(cfg: any, perSec: number): number
	return math.floor(math.max(cfg.lock.chargeMinGlow, cfg.lock.chargeGlowSecondsOfIncome * perSec))
end

-- A Lost night takes 5% of the current Glow balance (never Glowlings or Embers).
function Economy.nightLostPenalty(cfg: any, glow: number): number
	return math.floor(math.max(0, glow) * cfg.fire.failGlowLoss)
end

return Economy
