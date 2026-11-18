-- Config validator: config/*.json is internally consistent (TECH_SPEC §14).
local H = require("./harness")
local Economy = require("../src/shared/Economy")

local cfg = H.config()
local envs = H.json("config/environments.json")

local function unique(list: { any }, key: string, label: string)
	local seen = {}
	for _, item in list do
		local id = item[key]
		H.ok(type(id) == "string", `{label}: every entry needs a string {key}`)
		H.ok(not seen[id], `{label}: duplicate {id}`)
		seen[id] = true
	end
end

H.test("rarities: 7 tiers, rarer and richer each step", function()
	H.eq(#cfg.rarities, 7, "tier count")
	unique(cfg.rarities, "id", "rarities")
	for i = 2, #cfg.rarities do
		H.ok(cfg.rarities[i].oneIn > cfg.rarities[i - 1].oneIn, `oneIn rises at tier {i}`)
		H.ok(cfg.rarities[i].glowPerSec > cfg.rarities[i - 1].glowPerSec, `glowPerSec rises at tier {i}`)
	end
	H.eq(cfg.rarities[5].id, "Legendary", "pity relies on tier 5 being Legendary")
end)

H.test("mutations and luck", function()
	unique(cfg.mutations, "id", "mutations")
	for _, mutation in cfg.mutations do
		H.ok(mutation.oneIn > 1 and mutation.mult > 1, `{mutation.id} odds and multiplier`)
	end
	local lk = cfg.luck
	H.ok(lk.appliesFromRarity >= 1 and lk.appliesFromRarity <= #cfg.rarities, "appliesFromRarity")
	H.ok(lk.tierCap > 0 and lk.tierCap <= 1, "tierCap")
	H.ok(lk.fireSurvivedMult >= 1 and lk.serverLuckMult >= 1, "bonuses never lower luck")
	H.ok(cfg.size.min > 0 and cfg.size.min < cfg.size.max, "size range")
end)

H.test("lures and shop", function()
	local lures = cfg.lures
	H.ok(lures.maxFloor >= 1 and lures.maxFloor <= #cfg.rarities, "maxFloor")
	H.eq(#lures.stockPerRestock, lures.maxFloor, "one stock number per lure")
	H.ok(
		lures.resultCap == nil or (lures.resultCap >= lures.maxFloor and lures.resultCap <= #cfg.rarities),
		"resultCap"
	)
	H.ok(cfg.shop.restockSeconds > 0, "restock")
end)

H.test("cycle and night modifiers", function()
	local c = cfg.cycle
	H.ok(c.duskWarningAt > 0 and c.duskWarningAt < c.daySeconds, "dusk warning inside the day")
	H.ok(c.stalkerGraceSeconds < c.nightSeconds, "grace inside the night")
	H.ok(c.modifierChance >= 0 and c.modifierChance <= 1, "modifierChance")
	unique(c.nightModifiers, "id", "nightModifiers")
	H.ok(#c.nightModifiers >= 2, "never-twice-in-a-row needs at least 2 modifiers")
	for _, wave in cfg.night.spawnWavesAt do
		H.ok(wave < c.nightSeconds, "spawn waves inside the night")
	end
end)

H.test("fire", function()
	local f = cfg.fire
	H.ok(f.start > 0 and f.start <= f.max, "start")
	H.ok(f.drainBase > 0 and f.drainPerPlayer >= 0, "the fire always drains (D1)")
	H.ok(f.wood > 0 and f.shard > f.wood, "fuel")
	for _, modifier in cfg.cycle.nightModifiers do
		if modifier.fireStart ~= nil then
			H.ok(modifier.fireStart > 0 and modifier.fireStart <= f.max, `{modifier.id} fireStart`)
		end
	end
end)

H.test("upgrades, slots, vault, storage", function()
	for id, upgrade in cfg.upgrades do
		H.ok(upgrade.baseCost >= 1 and upgrade.growth > 1, `{id} price curve`)
		H.ok(Economy.upgradeMax(cfg, id) >= 1, `{id} max`)
	end
	H.ok(cfg.vault.start <= cfg.upgrades.slots.start, "the starting vault fits the starting slots")
	H.ok(cfg.storage.size > 0, "storage")
	H.ok(cfg.lock.maxCharges >= 1, "lock charges")
end)

H.test("per-rarity tables have one entry per rarity", function()
	H.eq(#cfg.steal.grabSeconds, #cfg.rarities, "steal.grabSeconds")
	H.eq(#cfg.trade.feeByRarity, #cfg.rarities, "trade.feeByRarity")
end)

H.test("environments: lists of game ids, none shared", function()
	local seen = {}
	for _, name in { "DEV", "BETA", "PROD" } do
		local ids = envs[name]
		H.ok(type(ids) == "table", `{name} must be a list (it may be empty)`)
		for _, id in ids do
			H.ok(type(id) == "number" and id % 1 == 0 and id > 0, `{name}: game ids are positive whole numbers`)
			H.ok(seen[id] == nil, `game id {id} is in both {seen[id]} and {name}`)
			seen[id] = name
		end
	end
end)

H.finish("config")
