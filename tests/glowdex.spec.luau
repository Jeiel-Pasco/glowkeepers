-- Glowdex: entries, stamps, page tiers, claims and milestones (GAME_SYSTEMS §16).
local H = require("./harness")
local Glowdex = require("../src/shared/Glowdex")

local cfg = H.config()

local function entryWith(rarities: { number }): any
	local entry = nil
	for _, r in rarities do
		entry = Glowdex.record(entry, r, 0)
	end
	return entry
end

H.test("credit: night, lure, event, tutorial; not steal, trade or fuse (D10)", function()
	for _, src in { "night", "lure", "event", "tutorial" } do
		H.ok(Glowdex.credits(cfg, src), src)
	end
	for _, src in { "steal", "trade", "fuse" } do
		H.ok(not Glowdex.credits(cfg, src), src)
	end
end)

H.test("record: rarity bits and mutation stamps; repeats change nothing", function()
	local entry, new = Glowdex.record(nil, 3, 1)
	H.ok(new, "first Rare Golden is new")
	H.ok(Glowdex.hasRarity(entry, 3) and not Glowdex.hasRarity(entry, 2), "Rare only")
	H.ok(Glowdex.hasMutation(entry, 1) and not Glowdex.hasMutation(entry, 2), "Golden stamp")
	local again, newAgain = Glowdex.record(entry, 3, 1)
	H.ok(not newAgain, "the same again is not new")
	H.eq(again.r, entry.r, "unchanged")
	H.eq(Glowdex.entries({ a = entryWith({ 1, 2, 3 }), b = entryWith({ 7 }) }), 4, "entries count rarities")
end)

H.test("tiers: Bronze needs Common to Epic, then Legendary, Mythic, Secret in order", function()
	H.eq(Glowdex.tier(cfg, entryWith({ 1, 2, 3 })), 0, "no Epic")
	H.eq(Glowdex.tier(cfg, entryWith({ 1, 2, 3, 4 })), 1, "Bronze")
	H.eq(Glowdex.tier(cfg, entryWith({ 1, 2, 3, 4, 5, 7 })), 2, "Silver: a Secret without the Mythic isn't Gold")
	H.eq(Glowdex.tier(cfg, entryWith({ 1, 2, 3, 4, 5, 6, 7 })), 4, "Radiant")
end)

H.test("claims: one tier at a time, once each; income bonus from claimed pages", function()
	local dex = { mothlet = entryWith({ 1, 2, 3, 4, 5 }) }
	local claimed = {}
	H.eq(Glowdex.canClaimPage(cfg, dex, claimed, "mothlet"), 1, "Bronze first")
	claimed.mothlet = 1
	H.eq(Glowdex.canClaimPage(cfg, dex, claimed, "mothlet"), 2, "then Silver")
	claimed.mothlet = 2
	H.eq(select(2, Glowdex.canClaimPage(cfg, dex, claimed, "mothlet")), "nothing_new", "nothing more")
	H.eq(select(2, Glowdex.canClaimPage(cfg, dex, claimed, "puffwick")), "nothing_new", "an empty page")
	claimed.puffwick = 3
	claimed["@10"] = 1
	H.near(Glowdex.incomeBonus(cfg, claimed), 0.01 + 0.02, 1e-12, "Silver plus Gold; milestones add none")
end)

H.test("milestones: 10 entries pay 25 Embers, once", function()
	local dex = { a = entryWith({ 1, 2, 3, 4, 5, 6, 7 }), b = entryWith({ 1, 2 }) }
	H.eq(select(2, Glowdex.canClaimMilestone(cfg, dex, {}, 1)), "not_yet", "9 entries")
	dex.c = entryWith({ 1 })
	H.eq(Glowdex.canClaimMilestone(cfg, dex, {}, 1), 25, "10 entries")
	H.eq(select(2, Glowdex.canClaimMilestone(cfg, dex, { ["@10"] = 1 }, 1)), "claimed", "twice")
	H.eq(select(2, Glowdex.canClaimMilestone(cfg, dex, {}, 99)), "unknown", "no such milestone")
	local Roll = require("../src/shared/Roll")
	local reachable = Glowdex.reachable(cfg, H.json("config/species.json"), function(species)
		return Roll.speciesFloor(cfg, species)
	end)
	H.eq(reachable, 254, "GAME_SYSTEMS §16")
	H.eq(cfg.glowdex.milestones[#cfg.glowdex.milestones].entries, reachable, "the last is every entry")
end)

H.test("pages skip rarities under the species' floor", function()
	H.eq(Glowdex.tier(cfg, entryWith({ 3, 4 }), 3), 1, "Rare floor: Rare + Epic is Bronze")
	H.eq(Glowdex.tier(cfg, entryWith({ 3, 4 }), nil), 0, "no floor: needs Common too")
	H.eq(Glowdex.tier(cfg, entryWith({ 5 }), 5), 2, "Legendary floor: Bronze and Silver need just Legendary")
	H.eq(Glowdex.canClaimPage(cfg, { x = entryWith({ 5 }) }, {}, "x", 5), 1)
end)

H.finish("glowdex")
