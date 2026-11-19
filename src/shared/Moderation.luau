--!strict
-- Exploit flags and the graduated response (TECH_SPEC §8). Pure: no requires and no engine calls.
--
-- Steps 1–2 (drop the request, snap the action back) happen where the request is handled.
-- Here: 3. raise a flag (logged in the profile's `flags`), 4. kick once the points of the flags
-- raised since the last kick, within moderation.windowSeconds, reach moderation.kickAt.
-- 5. Bans are never automatic: an admin bans after reviewing the log.
--
-- flags = { log = { { t, k, d } } (newest last, at most logKeep), counts = { [kind]: n },
--           kicks: number, lastKick: number }

local Moderation = {}

-- Fills in a missing or partial flags table in place and returns it.
function Moderation.shape(flags: any): any
	if type(flags.log) ~= "table" then
		flags.log = {}
	end
	if type(flags.counts) ~= "table" then
		flags.counts = {}
	end
	flags.kicks = tonumber(flags.kicks) or 0
	flags.lastKick = tonumber(flags.lastKick) or 0
	return flags
end

function Moderation.points(cfg: any, kind: string): number
	return cfg.moderation.points[kind] or 1
end

-- Points of the flags since the last kick and within the window.
function Moderation.recentPoints(cfg: any, flags: any, now: number): number
	local since = math.max(flags.lastKick, now - cfg.moderation.windowSeconds)
	local sum = 0
	for _, entry in flags.log do
		if entry.t > since then
			sum += Moderation.points(cfg, entry.k)
		end
	end
	return sum
end

-- Logs one flag; returns "kick" when this one reaches the kick threshold, else "flag".
-- `kickAt` overrides moderation.kickAt (DEV testing).
function Moderation.record(cfg: any, flags: any, kind: string, detail: string, now: number, kickAt: number?): string
	Moderation.shape(flags)
	flags.counts[kind] = (tonumber(flags.counts[kind]) or 0) + 1
	table.insert(flags.log, { t = now, k = kind, d = string.sub(detail, 1, 80) })
	while #flags.log > cfg.moderation.logKeep do
		table.remove(flags.log, 1)
	end
	if Moderation.recentPoints(cfg, flags, now) >= (kickAt or cfg.moderation.kickAt) then
		flags.kicks += 1
		flags.lastKick = now
		return "kick"
	end
	return "flag"
end

return Moderation
