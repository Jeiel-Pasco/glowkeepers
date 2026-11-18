-- Cycle: phase timing, skip, night modifiers (GAME_SYSTEMS §2).
local H = require("./harness")
local Cycle = require("../src/shared/Cycle")

local cfg = H.config()
local EPOCH = 1_795_000_000 -- any server time works

local function at(t: number)
	return Cycle.at(cfg, EPOCH, EPOCH + t)
end

H.test("a cycle is 6 minutes: day 4:00, night 2:00", function()
	H.eq(Cycle.length(cfg), 360, "length")
	local s = at(0)
	H.eq(s.phase, "Day", "dawn is day")
	H.eq(s.index, 0, "first cycle")
	H.eq(s.phaseRemaining, 210, "until the dusk warning")
	H.eq(s.untilNight, 240, "until night")
	H.eq(s.untilDawn, 360, "until the next dawn")
end)

H.test("grab at 3:31 is rejected; a carry from 3:29 lasts until 4:00 (§2 acceptance)", function()
	H.ok(at(209).grabsAllowed, "3:29 grab allowed")
	H.eq(at(211).phase, "Dusk", "3:31 is dusk")
	H.ok(not at(211).grabsAllowed, "3:31 grab rejected")
	H.ok(at(239.9).carriesAllowed, "carry still allowed at 3:59.9")
	H.eq(at(240).phase, "Night", "4:00 is night")
	H.ok(not at(240).carriesAllowed, "carries snap back at 4:00")
end)

H.test("the Stalker wakes 30 s into the night", function()
	H.ok(not at(269.9).stalkerActive, "grace period")
	H.ok(at(270).stalkerActive, "awake")
	H.ok(not at(10).stalkerActive, "asleep by day")
end)

H.test("cycles repeat, and times before the epoch count as the first dawn", function()
	local s = at(360)
	H.eq(s.index, 1, "second cycle")
	H.eq(s.phase, "Day", "dawn")
	H.near(s.t, 0, 1e-9, "t")
	H.eq(at(-50).index, 0, "before the epoch")
	H.eq(at(-50).phase, "Day", "before the epoch")
	local month = at(30 * 86400 + 250)
	H.eq(month.phase, "Night", "a month in")
	H.eq(month.index, 7200, "cycles in 30 days")
end)

H.test("skipEpoch jumps to the start of the next phase", function()
	local epoch = EPOCH
	local now = EPOCH + 100
	epoch = Cycle.skipEpoch(cfg, epoch, now)
	H.eq(Cycle.at(cfg, epoch, now).phase, "Dusk", "day → dusk")
	epoch = Cycle.skipEpoch(cfg, epoch, now)
	H.eq(Cycle.at(cfg, epoch, now).phase, "Night", "dusk → night")
	epoch = Cycle.skipEpoch(cfg, epoch, now)
	local s = Cycle.at(cfg, epoch, now)
	H.eq(s.phase, "Day", "night → dawn")
	H.eq(s.index, 1, "next cycle")
end)

H.test("pickModifier: 25% chance, never the previous modifier", function()
	H.eq(Cycle.pickModifier(cfg, nil, 0.3, 0), nil, "r1 above the chance")
	H.eq(Cycle.pickModifier(cfg, nil, 0.1, 0).id, "Fog", "first option")
	H.eq(Cycle.pickModifier(cfg, "Fog", 0.1, 0).id, "FireflyBloom", "Fog excluded")
	H.eq(Cycle.pickModifier(cfg, nil, 0.1, 0.999999).id, "Starfall", "last option")

	local rng = H.rng(99)
	local nights, withModifier = 100000, 0
	local last: string? = nil
	for _ = 1, nights do
		local modifier = Cycle.pickModifier(cfg, last, rng(), rng())
		if modifier ~= nil then
			withModifier += 1
			H.ok(modifier.id ~= last, "repeated a modifier")
			last = modifier.id
		end
	end
	H.near(withModifier / nights, cfg.cycle.modifierChance, 0.01, "share of modifier nights")
end)

H.test("modifier lookup and countdown text", function()
	H.eq(Cycle.modifier(cfg, "Gusty").fireDrainMult, 1.25, "Gusty")
	H.eq(Cycle.modifier(cfg, nil), nil, "none")
	H.eq(Cycle.modifier(cfg, "Nope"), nil, "unknown")
	H.eq(Cycle.formatClock(125), "2:05", "2:05")
	H.eq(Cycle.formatClock(0.2), "0:01", "rounds up")
	H.eq(Cycle.formatClock(0), "0:00", "zero")
	H.eq(Cycle.formatClock(-3), "0:00", "negative")
end)

H.finish("cycle")
