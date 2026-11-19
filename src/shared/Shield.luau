--!strict
-- New-player shield rules (GAME_SYSTEMS §11, D2). Pure: no requires and no engine calls.
-- The shield starts on the first join (Schema default) and ends after shield.maxPlaySeconds of
-- play, at the first rebirth, or when its owner chooses to steal. Play time is saved, so it
-- survives a rejoin and keeps accumulating.

local Shield = {}

-- Adds `dt` seconds of play. Returns the new play time and whether the shield ends now.
function Shield.accrue(cfg: any, playSeconds: number, dt: number): (number, boolean)
	local total = playSeconds + math.max(0, dt)
	return total, total >= cfg.shield.maxPlaySeconds
end

-- Server time the shield ends if its owner stays online from `now`.
function Shield.endsAt(cfg: any, playSeconds: number, now: number): number
	return now + math.max(0, cfg.shield.maxPlaySeconds - playSeconds)
end

return Shield
