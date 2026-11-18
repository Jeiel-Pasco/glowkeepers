--!strict
-- Day/night timing (GAME_SYSTEMS §2).
--
-- Pure. The phase is derived from the server epoch (workspace attribute `CycleEpoch`) and the
-- current server time (`workspace:GetServerTimeNow()`), so every client computes the same
-- countdown and nothing has to replicate each second.
--
--   0:00 Dawn → Day (income, shop, stealing, locks)
--   3:30 Dusk warning: new grabs blocked, carries in progress may finish until 4:00
--   4:00 Night: truce, fire, catching; the Stalker wakes after the grace period
--   6:00 Dawn again

local Cycle = {}

export type Phase = "Day" | "Dusk" | "Night"

export type State = {
	index: number, -- cycles completed since the epoch (0 = the first one)
	t: number, -- seconds into this cycle, 0 <= t < length
	length: number,
	phase: Phase,
	phaseRemaining: number, -- seconds until this phase ends
	untilNight: number, -- 0 during the night
	untilDawn: number, -- seconds until the next dawn
	stalkerActive: boolean,
	grabsAllowed: boolean, -- new grabs: Day only
	carriesAllowed: boolean, -- carries already in progress: until night starts
}

function Cycle.length(cfg: any): number
	return cfg.cycle.daySeconds + cfg.cycle.nightSeconds
end

function Cycle.at(cfg: any, epoch: number, now: number): State
	local c = cfg.cycle
	local length = c.daySeconds + c.nightSeconds
	local elapsed = math.max(0, now - epoch)
	local index = math.floor(elapsed / length)
	local t = elapsed - index * length
	if t >= length then -- guard against float rounding at the boundary
		index += 1
		t -= length
	end

	local phase: Phase
	local phaseRemaining: number
	if t < c.duskWarningAt then
		phase = "Day"
		phaseRemaining = c.duskWarningAt - t
	elseif t < c.daySeconds then
		phase = "Dusk"
		phaseRemaining = c.daySeconds - t
	else
		phase = "Night"
		phaseRemaining = length - t
	end

	return {
		index = index,
		t = t,
		length = length,
		phase = phase,
		phaseRemaining = phaseRemaining,
		untilNight = math.max(0, c.daySeconds - t),
		untilDawn = length - t,
		stalkerActive = phase == "Night" and t - c.daySeconds >= c.stalkerGraceSeconds,
		grabsAllowed = phase == "Day",
		carriesAllowed = phase ~= "Night",
	}
end

-- The epoch that makes the current phase end right now. Used by the DEV skip command:
-- moving the epoch back by the time left (plus 10 ms, so float rounding can't leave us a hair
-- before the boundary) jumps everyone to the start of the next phase.
function Cycle.skipEpoch(cfg: any, epoch: number, now: number): number
	return epoch - Cycle.at(cfg, epoch, now).phaseRemaining - 0.01
end

function Cycle.modifier(cfg: any, id: string?): any?
	if id == nil then
		return nil
	end
	for _, modifier in cfg.cycle.nightModifiers do
		if modifier.id == id then
			return modifier
		end
	end
	return nil
end

-- A share of nights (cycle.modifierChance) roll a modifier, never the same one as the last
-- modifier night. r1 decides whether tonight has one and r2 picks it; both are in [0, 1).
function Cycle.pickModifier(cfg: any, previousId: string?, r1: number, r2: number): any?
	if r1 >= cfg.cycle.modifierChance then
		return nil
	end
	local options = {}
	for _, modifier in cfg.cycle.nightModifiers do
		if modifier.id ~= previousId then
			table.insert(options, modifier)
		end
	end
	if #options == 0 then
		return nil
	end
	return options[math.min(#options, math.floor(r2 * #options) + 1)]
end

-- "2:05" style countdown text.
function Cycle.formatClock(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

return Cycle
