--!strict
-- Quest rules (GAME_SYSTEMS §19). Pure: no requires and no engine calls; randomness comes in
-- as `rng` (a function returning a number in [0, 1)).
--
-- 3 daily quests reset at 00:00 UTC and 3 weekly quests at Monday 00:00 UTC. Each quest is
-- `{ id, event, target, n, claimed }`; game events ("feed", "revive", "catch_night", ...) add
-- to every unclaimed quest with that event. One free reroll a day replaces one unclaimed daily
-- quest. The profile keeps `quests = { day, daily, week, weekly, rerollDay }`.

local Quest = {}

local DAY = 86400

export type Entry = { id: string, event: string, target: number, n: number, claimed: boolean }
export type Options = { shielded: boolean, perSec: number }

function Quest.day(unix: number): number
	return unix // DAY
end

-- Weeks start on Monday 00:00 UTC (1970-01-01 was a Thursday, so day 4 is the first Monday).
function Quest.week(unix: number): number
	return (unix // DAY + 3) // 7
end

-- A quest's target: fixed, or for "earn" quests (target 0) income × earnIncomeSeconds.
local function targetFor(cfg: any, def: any, opts: Options): number
	if def.target > 0 then
		return def.target
	end
	return math.max(cfg.quests.earnMin, math.floor(opts.perSec * cfg.quests.earnIncomeSeconds))
end

-- `count` distinct quests from `pool` by weight, skipping ids in `exclude` and steal quests
-- for shielded players.
function Quest.pick(
	cfg: any,
	pool: { any },
	count: number,
	rng: () -> number,
	opts: Options,
	exclude: { [string]: boolean }?
): { Entry }
	local candidates = {}
	for _, def in pool do
		if not (exclude and exclude[def.id]) and not (def.notShielded and opts.shielded) then
			table.insert(candidates, def)
		end
	end
	local out = {}
	while #out < count and #candidates > 0 do
		local total = 0
		for _, def in candidates do
			total += def.weight
		end
		local roll = rng() * total
		local index = #candidates
		for i, def in candidates do
			roll -= def.weight
			if roll < 0 then
				index = i
				break
			end
		end
		local def = table.remove(candidates, index) :: any
		table.insert(
			out,
			{ id = def.id, event = def.event, target = targetFor(cfg, def, opts), n = 0, claimed = false }
		)
	end
	return out
end

-- Rolls new daily and/or weekly quests when the UTC day or week has changed. Returns true if
-- anything changed.
function Quest.refresh(cfg: any, quests: any, unix: number, rng: () -> number, opts: Options): boolean
	local changed = false
	local day, week = Quest.day(unix), Quest.week(unix)
	if quests.day ~= day then
		quests.day = day
		quests.daily = Quest.pick(cfg, cfg.quests.dailyPool, cfg.quests.perDay, rng, opts)
		changed = true
	end
	if quests.week ~= week then
		quests.week = week
		quests.weekly = Quest.pick(cfg, cfg.quests.weeklyPool, cfg.quests.perWeek, rng, opts)
		changed = true
	end
	return changed
end

-- Adds `amount` to every unclaimed quest for `event`, capped at its target. Returns true if
-- any quest moved.
function Quest.advance(quests: any, event: string, amount: number): boolean
	local changed = false
	for _, list in { quests.daily, quests.weekly } do
		for _, q in list do
			if q.event == event and not q.claimed and q.n < q.target then
				q.n = math.min(q.target, q.n + amount)
				changed = true
			end
		end
	end
	return changed
end

-- The quest at `scope` ("d" or "w") and `index`, and its reward, if it can be claimed; else nil
-- and a reason ("unknown", "claimed", "not_done").
function Quest.canClaim(cfg: any, quests: any, scope: string, index: number): (any?, string?)
	local list = if scope == "d" then quests.daily elseif scope == "w" then quests.weekly else nil
	local q = if list ~= nil then list[index] else nil
	if q == nil then
		return nil, "unknown"
	elseif q.claimed then
		return nil, "claimed"
	elseif q.n < q.target then
		return nil, "not_done"
	end
	return if scope == "d" then cfg.quests.daily else cfg.quests.weekly, nil
end

-- Replaces daily quest `index` with a different one (the day's free reroll). Returns ok, or nil
-- and a reason ("used", "unknown", "claimed").
function Quest.reroll(cfg: any, quests: any, index: number, rng: () -> number, opts: Options): (boolean, string?)
	local q = quests.daily[index]
	if quests.rerollDay == quests.day then
		return false, "used"
	elseif q == nil then
		return false, "unknown"
	elseif q.claimed then
		return false, "claimed"
	end
	local exclude = {}
	for _, other in quests.daily do
		exclude[other.id] = true
	end
	local fresh = Quest.pick(cfg, cfg.quests.dailyPool, 1, rng, opts, exclude)[1]
	if fresh == nil then
		return false, "unknown"
	end
	quests.daily[index] = fresh
	quests.rerollDay = quests.day
	return true, nil
end

return Quest
