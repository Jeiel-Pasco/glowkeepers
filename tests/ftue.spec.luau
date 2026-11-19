-- The phase-aware tutorial (Shared.Ftue, GAME_SYSTEMS §22).
local H = require("./harness")
local Ftue = require("../src/shared/Ftue")

local function moment(phase: string, sawNight: boolean?): any
	return { phase = phase, phaseRemaining = 100, grabsAllowed = phase == "Day", sawNight = sawNight == true }
end

-- Plays a path: at each phase, finish whatever is shown until nothing is.
local function play(path: string, phases: { any }): { number }
	local mask, seen = 0, {}
	for _, m in phases do
		mask = Ftue.skipPassed(mask, path, m)
		local step = Ftue.current(mask, path, m)
		while step ~= nil do
			table.insert(seen, step)
			mask = Ftue.mark(mask, step)
			step = Ftue.current(mask, path, m)
		end
	end
	H.eq(Ftue.finished(mask, path), true, `{path} finished`)
	return seen
end

H.test("the path comes from the phase at the first join", function()
	H.eq(Ftue.pathFor("Day", 200), "day")
	H.eq(Ftue.pathFor("Day", 60), "late")
	H.eq(Ftue.pathFor("Dusk", 20), "late")
	H.eq(Ftue.pathFor("Night", 100), "night")
end)

H.test("day path: 1 → 6 by day, then 7 → 10", function()
	local seen = play("day", { moment("Day"), moment("Dusk"), moment("Night", true), moment("Day", true) })
	H.eq(table.concat(seen, ","), "1,2,3,4,5,6,7,8,9,10")
end)

H.test("late path: 1 → 4, 7 → 10, then 5 → 6 at dawn", function()
	local seen = play("late", { moment("Day"), moment("Dusk"), moment("Night", true), moment("Day", true) })
	H.eq(table.concat(seen, ","), "1,2,3,4,7,8,9,10,5,6")
end)

H.test("night path: 1 → 2, 8 → 10, then 3 → 6 at dawn", function()
	local seen = play("night", { moment("Night", true), moment("Day", true) })
	H.eq(table.concat(seen, ","), "1,2,8,9,10,3,4,5,6")
end)

H.test("a slow day player still gets the night steps, and the rest at dawn", function()
	local mask = Ftue.mark(Ftue.mark(Ftue.mark(0, 1), 2), 3) -- stuck on buying a lure
	H.eq(Ftue.current(mask, "day", moment("Dusk")), 7, "dusk comes first")
	mask = Ftue.mark(mask, 7)
	H.eq(Ftue.current(mask, "day", moment("Night", true)), 8, "no shop steps at night")
	H.eq(Ftue.current(mask, "day", moment("Day", true)), 10, "dawn first")
end)

H.test("missed moments are skipped, never waited on", function()
	local mask = Ftue.mark(Ftue.mark(0, 1), 2)
	local after, skipped = Ftue.skipPassed(mask, "day", moment("Night", true))
	H.eq(Ftue.isDone(after, 7) and #skipped == 1, true, "dusk passed")
	after, skipped = Ftue.skipPassed(after, "day", moment("Day", true))
	H.eq(Ftue.isDone(after, 8) and Ftue.isDone(after, 9) and #skipped == 2, true, "the night is over")
	local fresh = Ftue.skipPassed(mask, "day", moment("Day", false))
	H.eq(fresh, mask, "nothing skipped before the first night")
end)

H.test("the Free Lure comes before the dusk warning", function()
	H.eq(Ftue.current(0, "late", moment("Dusk")), 1)
end)

H.test("waiting for a phase shows nothing", function()
	local mask = 0
	for step = 1, 6 do
		mask = Ftue.mark(mask, step)
	end
	H.eq(Ftue.current(mask, "day", moment("Day")), nil, "free play until dusk")
	H.eq(Ftue.ALL, 1023)
end)

H.finish("ftue")
