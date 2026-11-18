--!strict
-- Downed and revive rules (GAME_SYSTEMS §14). Pure: no requires and no engine calls.
-- DownedService gathers the facts about a revive into a Check and asks canStart, and keeps
-- each downed player's bleed-out in a Bleed, which a revive in progress pauses.

local Revive = {}

-- "alive" plays normally; "downed" is frozen until revived or bled out; "wisp" spectates
-- until dawn after bleeding out.
export type Life = "alive" | "downed" | "wisp"

export type Check = {
	night: boolean, -- downed players only exist at night
	self: boolean, -- trying to revive yourself
	reviver: Life,
	target: Life,
	busy: boolean, -- the reviver is already reviving someone
	taken: boolean, -- someone else is already reviving the target
	distance: number, -- reviver to target, studs
}

-- The bleed-out of one downed player. `paused` holds the seconds left while a revive holds it.
export type Bleed = { ends: number, paused: number? }

-- Every revive rule, in the order a player would want to hear about them. Returns ok, or false
-- and a reason code.
function Revive.canStart(cfg: any, c: Check): (boolean, string?)
	if not c.night then
		return false, "not_night"
	elseif c.self then
		return false, "self"
	elseif c.reviver ~= "alive" then
		return false, "not_alive"
	elseif c.target ~= "downed" then
		return false, "not_downed"
	elseif c.busy then
		return false, "busy"
	elseif c.taken then
		return false, "taken"
	elseif not (c.distance <= cfg.revive.range) then
		return false, "too_far"
	end
	return true
end

function Revive.bleed(cfg: any, now: number): Bleed
	return { ends = now + cfg.revive.bleedOutSeconds }
end

-- A revive hold started: the bleed-out stops counting down, so a revive that began in time
-- always gets to finish.
function Revive.pause(bleed: Bleed, now: number)
	if bleed.paused == nil then
		bleed.paused = math.max(0, bleed.ends - now)
	end
end

-- The hold was let go or broken: the bleed-out carries on from where it stopped.
function Revive.resume(bleed: Bleed, now: number)
	local left = bleed.paused
	if left ~= nil then
		bleed.ends = now + left
		bleed.paused = nil
	end
end

function Revive.bledOut(bleed: Bleed, now: number): boolean
	return bleed.paused == nil and now >= bleed.ends
end

return Revive
