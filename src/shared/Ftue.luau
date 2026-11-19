--!strict
-- The phase-aware new-player tutorial (GAME_SYSTEMS §22, D7). Pure: TutorialService feeds it
-- the saved progress and the cycle, and it says which step to show.
--
-- Progress is a bitmask of finished steps (save `ftue.step`; bit k-1 = step k), so steps can
-- finish out of order. The path is picked once, at the first join, from the phase:
--   day    more than 60 s of day left   1 → 6, free play, then 7 → 10
--   late   60 s or less, or dusk         1 → 4, 7 → 10, then 5 → 6 at dawn
--   night  joined at night               1 → 2, 8 → 10, then 3 → 6 at dawn
-- Each step only shows in its phase (stealing by day, feeding at night, ...). The two moments,
-- dusk (7) and dawn (10), come first when they're on, and a night step that wasn't done in time
-- is skipped at dawn, so nobody is ever stuck waiting.

local Ftue = {}

Ftue.STEPS = {
	"spawn", -- 1 the guide Wisp shows the Free Lure
	"first_lure", -- 2 a guaranteed Uncommon, placed for you
	"first_income", -- 3 reach the price of a lure
	"first_buy", -- 4 buy a lure
	"tutorial_steal", -- 5 grab from the Wisp's Stash and carry it home
	"first_lock", -- 6 lock your base once
	"first_dusk", -- 7 night is coming
	"first_feed", -- 8 feed the fire
	"first_catch", -- 9 catch a Glowling (guaranteed Rare)
	"first_dawn", -- 10 you survived; the next goal
}
Ftue.COUNT = #Ftue.STEPS
Ftue.ALL = 2 ^ Ftue.COUNT - 1
Ftue.LATE_SECONDS = 60

Ftue.ORDER = {
	day = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 },
	late = { 1, 2, 3, 4, 7, 8, 9, 10, 5, 6 },
	night = { 1, 2, 8, 9, 10, 3, 4, 5, 6 },
}

export type Path = "day" | "late" | "night"

-- What the cycle looks like to the tutorial. `sawNight`: this player was here for a night (so
-- dawn means they survived one).
export type Moment = { phase: string, phaseRemaining: number, grabsAllowed: boolean, sawNight: boolean }

function Ftue.pathFor(phase: string, phaseRemaining: number): Path
	if phase == "Night" then
		return "night"
	elseif phase == "Dusk" or phaseRemaining <= Ftue.LATE_SECONDS then
		return "late"
	end
	return "day"
end

function Ftue.isDone(mask: number, step: number): boolean
	return bit32.btest(mask, bit32.lshift(1, step - 1))
end

function Ftue.mark(mask: number, step: number): number
	return bit32.bor(mask, bit32.lshift(1, step - 1))
end

-- The steps of a path, as listed in ORDER (night skips the dusk step).
function Ftue.order(path: string): { number }
	return Ftue.ORDER[path] or Ftue.ORDER.day
end

-- Is every step of the path done?
function Ftue.finished(mask: number, path: string): boolean
	for _, step in Ftue.order(path) do
		if not Ftue.isDone(mask, step) then
			return false
		end
	end
	return true
end

-- Can `step` be done right now?
function Ftue.open(step: number, m: Moment): boolean
	if step <= 2 then
		return true
	elseif step <= 4 then
		return m.phase ~= "Night"
	elseif step == 5 then
		return m.grabsAllowed
	elseif step == 6 then
		return m.phase == "Day"
	elseif step == 7 then
		return m.phase == "Dusk"
	elseif step <= 9 then
		return m.phase == "Night"
	end
	return m.phase == "Day" and m.sawNight -- 10: the dawn after a night
end

-- Steps whose moment has passed: the dusk warning once night falls, and the night steps once a
-- night this player saw is over. Returns the mask with them marked, and the list skipped.
function Ftue.skipPassed(mask: number, path: string, m: Moment): (number, { number })
	local skipped = {}
	for _, step in Ftue.order(path) do
		if Ftue.isDone(mask, step) then
			continue
		end
		local passed = (step == 7 and (m.phase == "Night" or (m.phase == "Day" and m.sawNight)))
			or ((step == 8 or step == 9) and m.phase == "Day" and m.sawNight)
		if passed then
			mask = Ftue.mark(mask, step)
			table.insert(skipped, step)
		end
	end
	return mask, skipped
end

local function openOn(path: string, step: number, m: Moment): boolean
	if path == "late" and (step == 5 or step == 6) and not m.sawNight then
		return false -- the late path steals and locks at dawn
	end
	return Ftue.open(step, m)
end

-- The step to show now, or nil while waiting for a phase (free play). After the Free Lure
-- (1–2), dusk and dawn come first when they're on; otherwise the first open step in the
-- path's order. Steps before it that aren't open yet wait their turn.
function Ftue.current(mask: number, path: string, m: Moment): number?
	local order = Ftue.order(path)
	if Ftue.isDone(mask, 1) and Ftue.isDone(mask, 2) then
		for _, moment in { 7, 10 } do
			if table.find(order, moment) and not Ftue.isDone(mask, moment) and openOn(path, moment, m) then
				return moment
			end
		end
	end
	for _, step in order do
		if not Ftue.isDone(mask, step) and openOn(path, step, m) then
			return step
		end
	end
	return nil
end

return Ftue
