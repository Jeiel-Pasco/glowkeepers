--!strict
-- Daily gift rules (GAME_SYSTEMS §19). Pure: no requires and no engine calls.
--
-- A 28-step calendar that advances one step per UTC day the player claims, and never resets:
-- missing days only pauses it. After step 28 it loops. The profile keeps
-- `gift = { claimed, lastDay }`: steps claimed so far, and the UTC day (os.time() // 86400) of
-- the last claim. Rewards are in economy.json under `gift.steps`.

local Gift = {}

local DAY = 86400

export type Reward = { kind: string, amount: number?, floor: number?, id: string? }

function Gift.day(unix: number): number
	return unix // DAY
end

-- Seconds until the next UTC day starts.
function Gift.secondsToNextDay(unix: number): number
	return DAY - unix % DAY
end

-- Whether today's step can be claimed (one claim per UTC day).
function Gift.canClaim(gift: any, today: number): boolean
	return today > (tonumber(gift.lastDay) or 0)
end

-- The step (1..#steps) the next claim gives, and its reward.
function Gift.next(cfg: any, gift: any): (number, Reward)
	local steps = cfg.gift.steps
	local step = (tonumber(gift.claimed) or 0) % #steps + 1
	return step, steps[step]
end

-- The gift record after claiming on `today`.
function Gift.claimed(gift: any, today: number): { claimed: number, lastDay: number }
	return { claimed = (tonumber(gift.claimed) or 0) + 1, lastDay = today }
end

return Gift
