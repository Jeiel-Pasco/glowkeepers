--!strict
-- Stealing rules (GAME_SYSTEMS §10, TECH_SPEC §8). Pure: no requires and no engine calls.
-- StealService gathers the facts about a grab into a Check and asks canGrab; it samples the
-- carrier's position and asks moveViolation. Both sides of every rule live here, in one place.

local Steal = {}

export type Check = {
	phase: string, -- Cycle phase: grabs only by day, never from the dusk warning on
	thief: number, -- userId
	owner: number, -- the target plot's owner userId (0 = nobody)
	thiefHasPlot: boolean, -- a thief needs a plot to deliver to
	thiefHasRoom: boolean, -- and room in storage for what they bring home
	padKind: string?, -- Inventory.padKind of the target pad: only "display" can be stolen
	hasGlowling: boolean, -- the pad holds a Glowling
	busy: boolean, -- the thief is already grabbing or carrying (one at a time)
	padTaken: boolean, -- someone else is grabbing or carrying this pad's Glowling
	locked: boolean, -- the target plot's Base Lock is on (LockService)
	shielded: boolean, -- the victim has the new-player shield (Phase 3; a thief's grab ends their own)
	now: number,
	victimSafeUntil: number, -- the victim cooldown after losing a Glowling
	stolenToday: number, -- steals by this thief from this victim in this day phase
	distance: number, -- Steal.reach from the thief to the pad, studs
}

export type Sample = { t: number, x: number, z: number }

-- Hold time before a grab becomes a carry: 1 s Common–Rare, 2 s Epic–Legendary, 3 s Mythic–Secret.
function Steal.holdSeconds(cfg: any, rarity: number): number
	return cfg.steal.grabSeconds[rarity] or cfg.steal.grabSeconds[#cfg.steal.grabSeconds]
end

-- How far a player is from a pad for the grab range, from (pad − root part) offsets: flat
-- distance, since the root part stands about 3 studs above the pad. Out of reach (huge) when
-- more than grabRange above or below it.
function Steal.reach(cfg: any, dx: number, dy: number, dz: number): number
	if not (math.abs(dy) <= cfg.steal.grabRange) then
		return math.huge
	end
	return math.sqrt(dx * dx + dz * dz)
end

-- Every grab rule, in the order a player would want to hear about them. Returns ok, or false
-- and a reason code that StealService turns into a toast.
function Steal.canGrab(cfg: any, c: Check): (boolean, string?)
	local s = cfg.steal
	if c.phase ~= "Day" then
		return false, "not_day"
	elseif not c.thiefHasPlot then
		return false, "no_plot"
	elseif not c.thiefHasRoom then
		return false, "storage_full"
	elseif c.owner == 0 then
		return false, "empty"
	elseif c.owner == c.thief then
		return false, "own_plot"
	elseif c.padKind ~= "display" then
		return false, "vault"
	elseif not c.hasGlowling then
		return false, "empty"
	elseif c.busy then
		return false, "busy"
	elseif c.padTaken then
		return false, "taken"
	elseif c.locked then
		return false, "locked"
	elseif c.shielded then
		return false, "shielded"
	elseif c.now < c.victimSafeUntil then
		return false, "cooldown"
	elseif c.stolenToday >= s.perThiefPerVictimPerDay then
		return false, "daily_limit"
	elseif not (c.distance <= s.grabRange) then
		return false, "too_far"
	end
	return true
end

-- Checks the carrier's recent positions (TECH_SPEC §8). `samples` are oldest first, sampled at
-- about 10 Hz; `expectedSpeed` is their carry run speed (Boots, Swift Boots, ×0.85).
-- Returns "teleport" if the last step jumped steal.teleportStuds further than they could run
-- in that time (so a server hitch never trips it), "speed" if the distance covered over the
-- check window beats expectedSpeed × (1 + tolerance) plus a little slack for network jitter,
-- else nil. Horizontal distance only, so falling never counts.
function Steal.moveViolation(cfg: any, samples: { Sample }, expectedSpeed: number): string?
	local s = cfg.steal
	local n = #samples
	if n < 2 then
		return nil
	end
	local last, before = samples[n], samples[n - 1]
	local step = math.sqrt((last.x - before.x) ^ 2 + (last.z - before.z) ^ 2)
	if step > s.teleportStuds + expectedSpeed * (last.t - before.t) then
		return "teleport"
	end
	-- The oldest sample still inside the window.
	local first = samples[1]
	for i = n - 1, 1, -1 do
		first = samples[i]
		if last.t - samples[i].t >= s.carryCheckWindow then
			break
		end
	end
	local dt = last.t - first.t
	if dt < s.carryCheckWindow then
		return nil -- not enough history yet
	end
	local distance = math.sqrt((last.x - first.x) ^ 2 + (last.z - first.z) ^ 2)
	local allowed = expectedSpeed * (1 + s.speedTolerance) * dt + s.carrySlackStuds
	return if distance > allowed then "speed" else nil
end

-- Drops samples older than the check window (keeping one just before it), oldest first.
function Steal.trim(cfg: any, samples: { Sample }, now: number)
	local keepFrom = 1
	for i = #samples, 1, -1 do
		if now - samples[i].t >= cfg.steal.carryCheckWindow then
			keepFrom = i
			break
		end
	end
	for _ = 1, keepFrom - 1 do
		table.remove(samples, 1)
	end
end

return Steal
