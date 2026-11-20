-- Combat rules (Shared.CombatRules): gear and passive stats, the M1 combo, Permafrost, PvP.
local H = require("./harness")
local CombatRules = require("../src/shared/CombatRules")
local Element = require("../src/shared/Element")
local Gears = require("../src/shared/Gears")
local Level = require("../src/shared/Level")
local Spells = require("../src/shared/Spells")
local Zones = require("../src/shared/Zones")
local Vector3 = (require("@lune/roblox") :: any).Vector3

H.test("hat and passive add damage and cooldown cut, capped", function()
	local power, cdr = CombatRules.offense({ hat = 4 }, "Dark")
	H.near(power, 0.24 + 0.12, 1e-9, "Crown of the Magi + Devil's Pact power")
	H.near(cdr, 0.12, 1e-9, "Crown cdr")
	power, cdr = CombatRules.offense(nil, "Light")
	H.near(power, 0, 1e-9, "no hat")
	H.near(cdr, 0.10, 1e-9, "4-Leaf Blessing cdr")
	_, cdr = CombatRules.offense({ hat = 4 }, "Light")
	H.ok(cdr <= CombatRules.MAX_CDR, "cdr capped")
end)

H.test("robe and Earth passive cut damage taken; Leaf regens faster", function()
	H.near(CombatRules.defense({ robe = 4 }, "Earth"), 0.18 + 0.08, 1e-9, "Archmage + Titan's Poise")
	H.near(CombatRules.defense(nil, "Fire"), 0, 1e-9, "no robe")
	H.near(CombatRules.regenMult("Leaf"), 1.5, 1e-9, "Natural Grace")
	H.near(CombatRules.regenMult("Fire"), 1, 1e-9, "no regen perk")
end)

H.test("boots shave the dash cooldown, never below the floor", function()
	H.near(CombatRules.dashCooldown(2.4, nil), 2.4, 1e-9, "no boots")
	H.near(CombatRules.dashCooldown(2.4, { boots = 4 }), 1.9, 1e-9, "Astral Striders")
	H.eq(CombatRules.dashCooldown(1.5, { boots = 4 }), CombatRules.MIN_DASH_COOLDOWN, "floor")
end)

H.test("M1 combo counts to 4, then restarts; a pause resets it", function()
	local n, t = 0, -1e9
	local seen = {}
	for i = 1, 6 do
		n = CombatRules.comboStep(n, t, i * 0.4)
		t = i * 0.4
		table.insert(seen, n)
	end
	H.eq(table.concat(seen, ","), "1,2,3,4,1,2", "combo cycle")
	H.eq(CombatRules.comboStep(2, 0, CombatRules.COMBO_WINDOW + 0.1), 1, "window lapsed")
end)

H.test("every Grimoire has a 4th-hit finisher", function()
	for _, kind in Element.TYPES do
		H.ok(CombatRules.finisher(kind) ~= nil, `{kind} finisher`)
	end
	H.ok(CombatRules.finisher("Fire").burn ~= nil, "Fire burns")
	H.ok(CombatRules.finisher("Gravity").push.speed < 0, "Gravity pulls")
	H.ok(CombatRules.finisher("Lightning").bonus > 0, "Lightning shocks")
end)

H.test("Permafrost: 3 chill stacks Freeze, stacks melt after a pause", function()
	local stacks, frozen = CombatRules.addChill(0, -1e9, 0, 1)
	H.ok(stacks == 1 and not frozen, "1 stack")
	stacks, frozen = CombatRules.addChill(stacks, 0, 1, 1)
	H.ok(stacks == 2 and not frozen, "2 stacks")
	stacks, frozen = CombatRules.addChill(stacks, 1, 2, 1)
	H.ok(stacks == 0 and frozen, "Freeze spends the stacks")
	stacks, frozen = CombatRules.addChill(2, 0, CombatRules.CHILL_DECAY + 1, 1)
	H.ok(stacks == 1 and not frozen, "melted")
end)

H.test("PvP: never in camp; arena duels; War Mode both ways", function()
	local function side(safe, arena, war)
		return { safe = safe, arena = arena, war = war }
	end
	H.ok(CombatRules.canPvp(side(false, true, false), side(false, true, false)), "arena duel")
	H.ok(CombatRules.canPvp(side(false, false, true), side(false, false, true)), "both War Mode")
	H.ok(not CombatRules.canPvp(side(false, false, true), side(false, false, false)), "one War Mode")
	H.ok(not CombatRules.canPvp(side(true, false, true), side(false, false, true)), "attacker in camp")
	H.ok(not CombatRules.canPvp(side(false, true, false), side(false, false, false)), "arena vs wilds")
end)

H.test("Duel Arena Ring sits outside the camp courtyard", function()
	H.ok(Zones.inArena(Vector3.new(Zones.ARENA_X, 0, Zones.ARENA_Z)), "centre")
	H.ok(not Zones.inArena(Vector3.new(0, 0, 0)), "camp centre")
	H.ok(Zones.ARENA_Z - Zones.ARENA_R > Zones.CAMP_R, "ring clear of the safe radius")
end)

-- One PvP blow, as CombatService deals it: attackAmount × PVP_DAMAGE, then the victim's stat
-- defence and Robe/passive defence. A build is { level, power, health, defense } stat points.
local function pvpHit(base: number, scale: number, mult: number, a: any, d: any): number
	local power = CombatRules.offense(a.gears, a.book)
	local raw = Level.damage(base, scale, a.power, mult, 0) * Level.power(a.level) * (1 + power)
	local dealt = raw * CombatRules.PVP_DAMAGE / (1 + d.defense * Level.DEFENSE_PER_POINT)
	return dealt * (1 - CombatRules.defense(d.gears, d.book))
end

local function maxHp(b: any): number
	return Level.maxHealth(b.level, b.health) + Gears.stats(b.gears).hp
end

local MAX_GEAR = { backpack = 5, robe = 4, hat = 4, boots = 4 }

H.test("PvP at Lv 50, even builds and max gear: no ultimate one-shots", function()
	local even = { level = 50, power = 49, health = 49, defense = 49, gears = MAX_GEAR, book = "Dark" }
	local victim = table.clone(even)
	victim.book = "Fire"
	local strongest = 0
	for _, kind in Element.TYPES do
		local ult = Spells.get(Spells.fixedFor(kind)[4])
		strongest = math.max(strongest, ult.damage)
	end
	local hit = pvpHit(strongest, Spells.levelScale(5), Element.PVP_MYTHIC, even, victim)
	H.ok(maxHp(victim) / hit >= 1.8, `strongest Lv5 ultimate takes {maxHp(victim) / hit} hits`)
	local m1 = pvpHit(Spells.BASIC.Dark.damage, 1, Element.PVP_MYTHIC, even, victim)
	H.ok(maxHp(victim) / m1 >= 15, `M1 takes {maxHp(victim) / m1} hits`)
end)

H.test("PvP at Lv 1 with starter kits takes several bolts", function()
	local starter = { level = 1, power = 0, health = 0, defense = 0, gears = nil, book = "Neutral" }
	local hit = pvpHit(Spells.get("arcane_bolt").damage, 1, 1, starter, starter)
	H.ok(maxHp(starter) / hit >= 6, `Arcane Bolt takes {maxHp(starter) / hit} hits`)
end)

H.test("bounty pays more for wanted wizards", function()
	H.eq(CombatRules.bountyReward(0), CombatRules.BOUNTY_BASE, "base")
	H.ok(CombatRules.bountyReward(3) > CombatRules.bountyReward(1), "grows")
end)

H.finish("combat")
