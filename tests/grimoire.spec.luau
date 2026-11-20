-- Grimoire slice rules: types, spells, writing, levels, loot, enemies, quests, saves (GDD v2).
local H = require("./harness")
local Element = require("../src/shared/Element")
local Spells = require("../src/shared/Spells")
local Writing = require("../src/shared/Writing")
local Level = require("../src/shared/Level")
local Loot = require("../src/shared/Loot")
local Enemies = require("../src/shared/Enemies")
local Quests = require("../src/shared/Quests")
local Schema = require("../src/server/Data/Schema")

H.test("type chart: Fire > Leaf > Water > Fire, Neutral even, Light/Dark mythic", function()
	H.eq(Element.mult("Fire", "Leaf"), 1.5, "fire beats leaf")
	H.eq(Element.mult("Leaf", "Fire"), 0.67, "leaf weak to fire")
	H.eq(Element.mult("Water", "Fire"), 1.5, "water beats fire")
	H.eq(Element.mult("Fire", "Fire"), 1, "mirror")
	H.eq(Element.mult("Neutral", "Fire"), 1, "neutral attack")
	H.eq(Element.mult("Light", "Dark"), 1.5, "light beats dark")
	H.eq(Element.mult("Dark", "Fire"), 1.25, "mythic vs element")
	H.eq(Element.mult("Fire", "Dark"), 1, "element vs mythic")
end)

H.test("every spell has a known kind, rarity and a pool entry", function()
	local kinds = {
		bolt = true,
		burst = true,
		area = true,
		beam = true,
		shield = true,
		heal = true,
		dash = true,
		blink = true,
		buff = true,
	}
	for _, spell in Spells.list do
		H.ok(kinds[spell.kind], `{spell.id} kind`)
		H.ok(table.find(Spells.RARITIES, spell.rarity), `{spell.id} rarity`)
		H.ok(table.find(Spells.pools[spell.type][spell.rarity], spell.id), `{spell.id} pooled`)
		H.ok(spell.cooldown > 0, `{spell.id} cooldown`)
	end
	H.near(Spells.levelScale(5), 1.4, 1e-9, "max level scale")
	H.near(Spells.cooldownAt(Spells.byId.pulse, 5), 5 * 0.84, 1e-9, "cooldown at 5")
end)

H.test("odds tables sum to 1", function()
	for name, odds in Writing.ODDS do
		local sum = 0
		for _, p in odds do
			sum += p
		end
		H.near(sum, 1, 1e-9, name)
	end
end)

H.test("rarity draw walks the table; pick falls back to a rarity the pool has", function()
	H.eq(Writing.rarity(Writing.ODDS.element, 0), "Common", "low roll")
	H.eq(Writing.rarity(Writing.ODDS.element, 0.95), "Epic", "high roll")
	H.eq(Writing.rarity(Writing.ODDS.element, 0.999), "Legendary", "top roll")
	H.eq(Writing.pick("Fire", "Mythic", 0), "meteor_fall", "no Fire mythic: falls to legendary")
	H.eq(Writing.pick("Water", "Common", 0), nil, "no Water spells in the slice")
end)

H.test("apply: add, level, max, then choose when full; resolve replaces or tears", function()
	local book = { type = "Neutral", pages = {} }
	H.eq(Writing.apply(book, "pulse"), "added", "first")
	H.eq(Writing.apply(book, "pulse"), "level", "dupe levels")
	for _ = 1, 3 do
		Writing.apply(book, "pulse")
	end
	H.eq(book.pages[1].lv, 5, "level 5")
	H.eq(Writing.apply(book, "pulse"), "maxed", "past max")
	for _, id in { "ward", "mend", "blink" } do
		Writing.apply(book, id)
	end
	H.eq(Writing.apply(book, "force_lance"), "choose", "full")
	H.eq(#book.pages, 4, "still 4 pages")
	H.ok(Writing.resolve(book, "force_lance", 2), "replace page 2")
	H.eq(book.pages[2].sp, "force_lance", "replaced")
	H.ok(Writing.resolve(book, "arcane_bolt", 0), "tear out")
	H.ok(not Writing.resolve(book, "arcane_bolt", 5), "bad page")
end)

H.test("levels: XP curve, cap, points, health, damage", function()
	H.eq(Level.xpToNext(1), 40, "level 1")
	local level, xp, ups = Level.addXp(1, 0, 45)
	H.eq(level, 2, "level up")
	H.eq(xp, 5, "carry over")
	H.eq(ups, 1, "ups")
	level, xp = Level.addXp(14, 0, 1e9)
	H.eq(level, Level.CAP, "capped")
	H.eq(xp, 0, "no xp at cap")
	H.eq(Level.pointsEarned(15), 42, "points at cap")
	H.eq(Level.maxHealth(1, 0), 100, "base hp")
	H.eq(Level.maxHealth(3, 2), 144, "hp")
	H.near(Level.damage(10, 1, 0, 1.5, 0), 15, 1e-9, "type mult")
	H.near(Level.damage(10, 1, 50, 1, 50), 10, 1e-9, "power and defense cancel")
end)

H.test("loot: take rounds down, recovered adds the bonus, repair cleans junk", function()
	local bag = { coins = 9, ink = { Fire = 3 }, frag = {} }
	local half = Loot.take(bag, 0.5)
	H.eq(half.coins, 4, "half coins")
	H.eq(half.ink.Fire, 1, "half ink")
	H.eq(bag.coins, 5, "left coins")
	H.eq(bag.ink.Fire, 2, "left ink")
	local back = Loot.recovered({ coins = 50, ink = { Fire = 1 }, frag = {} })
	H.eq(back.coins, 55, "bonus")
	H.eq(back.ink.Fire, 1, "ink back")
	local fixed = Loot.repair({ coins = -3, ink = { Fire = 0 / 0, Neutral = 2.7, [1] = 4 }, frag = "x" })
	H.eq(fixed.coins, 0, "negative")
	H.eq(fixed.ink.Fire, nil, "nan dropped")
	H.eq(fixed.ink.Neutral, 2, "floored")
	H.eq(fixed.ink[1], nil, "number key dropped")
	H.ok(Loot.isEmpty(Loot.empty()), "empty")
end)

H.test("enemies: scaling, boss health per attacker, boss credit", function()
	local imp = Enemies.kinds.ember_imp
	H.eq(Enemies.maxHp(imp, 1), 40, "imp hp")
	H.eq(Enemies.maxHp(imp, 3), 72, "imp hp lv3")
	local golem = Enemies.kinds.cinder_golem
	H.eq(Enemies.bossHp(golem, 12, 1), Enemies.maxHp(golem, 12), "solo")
	H.eq(Enemies.bossHp(golem, 12, 3), math.floor(Enemies.maxHp(golem, 12) * 2.2), "three attackers")
	H.ok(Enemies.earnsDrop(300, 3000, 12, 12), "10% dealt")
	H.ok(not Enemies.earnsDrop(299, 3000, 12, 12), "under 10%")
	H.ok(not Enemies.earnsDrop(3000, 3000, 28, 12), "over-levelled")
	for id, kind in Enemies.kinds do
		H.eq(kind.id, id, `{id} id`)
	end
end)

H.test("quests: tutorial chain, kills by kind, level steps, repeatables cycle", function()
	local first = Quests.step(1)
	H.eq(first.event, "write", "starts at the desk")
	H.eq(Quests.advance(Quests.step(2), 0, "kill", "ember_imp"), 1, "imp counts")
	H.eq(Quests.advance(Quests.step(2), 0, "kill", "raider"), nil, "raider doesn't")
	H.eq(Quests.advance(Quests.step(9), 3, "level", 7), 7, "level step uses the level")
	H.eq(Quests.step(6).event, "element", "element pick ends the tutorial")
	H.ok(Quests.inTutorial(6) and not Quests.inTutorial(7), "tutorial range")
	H.eq(Quests.step(#Quests.STEPS + 1), Quests.REPEAT[1], "repeat 1")
	H.eq(Quests.step(#Quests.STEPS + #Quests.REPEAT + 1), Quests.REPEAT[1], "wraps")
	for i = 1, #Quests.STEPS do
		local step = Quests.step(i)
		if step.event == "kill" then
			H.ok(Enemies.kinds[step.target], `step {i} target`)
		end
	end
end)

H.test("save: template repairs clean and broken saves", function()
	local data = Schema.template()
	H.eq(#Schema.repair(data), 0, "clean template")
	H.eq(data.books[1].type, "Neutral", "neutral book")
	local bad = Schema.template()
	bad.level = 5
	bad.stats = { health = 99, power = 0, defense = 0 }
	bad.books = { { type = "Fire", pages = { { sp = "ember_shot", lv = 9 }, { sp = "pulse", lv = 1 } } }, "junk" }
	bad.equipped = { 3, 1, 1 }
	bad.active = 1
	bad.bank = { coins = 1 / 0, ink = { Fire = -1 }, frag = {} }
	Schema.repair(bad)
	H.eq(bad.stats.health, 0, "overspent stats reset")
	H.eq(#bad.books, 1, "junk book dropped")
	H.eq(#bad.books[1].pages, 1, "bad page level dropped")
	H.eq(bad.equipped[1], 0, "out of range slot")
	H.eq(bad.equipped[2], 1, "first valid kept")
	H.eq(bad.equipped[3], 0, "duplicate cleared")
	H.eq(bad.active, 2, "active moved to a filled slot")
	H.eq(bad.bank.coins, 0, "inf coins")
	H.eq(bad.bank.ink.Fire, nil, "negative ink")
	local view = Schema.clientView(bad)
	H.eq(view.receipts, nil, "private")
end)

H.finish("grimoire")
