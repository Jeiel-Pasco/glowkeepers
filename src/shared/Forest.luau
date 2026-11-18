--!strict
-- Wild Glowlings at night (GAME_SYSTEMS §12). Pure: no requires and no engine calls.
-- ForestService asks how big each spawn wave is, where to put it, and whether a catch is
-- allowed. The species of a wild is picked at spawn (it's visible); its rarity is rolled when
-- it's caught, with the catcher's luck (RollService).

local Forest = {}

export type Check = {
	night: boolean, -- catching happens only at night
	living: boolean, -- not downed and not a wisp
	exists: boolean, -- the wild is still there (nobody caught it first)
	catchesLeft: number, -- 3 + floor(Boots / 5) a night, plus the modifier's extra
	hasRoom: boolean, -- storage below its hard cap (bag + overflow)
	distance: number, -- catcher to wild, studs
}

-- The species pool a WildSpawn marker's `Area` draws from.
function Forest.poolFor(area: string): string
	return if area == "Deepwood" then "Deepwood" else "Clearing"
end

-- Wild Glowlings in each wave tonight: spawnsPerPlayer per player in total (× the night
-- modifier's spawnMult), spread over the waves, earlier waves taking any remainder.
function Forest.waveSizes(cfg: any, players: number, modifier: any?): { number }
	local mult = if modifier ~= nil and modifier.spawnMult ~= nil then modifier.spawnMult else 1
	local total = math.floor(cfg.night.spawnsPerPlayer * math.max(0, players) * mult + 0.5)
	local waves = #cfg.night.spawnWavesAt
	local sizes = {}
	for i = 1, waves do
		sizes[i] = total // waves + (if i <= total % waves then 1 else 0)
	end
	return sizes
end

-- The next wave due `elapsed` seconds into the night, after `done` waves, or nil.
function Forest.dueWave(cfg: any, elapsed: number, done: number): number?
	local at = cfg.night.spawnWavesAt[done + 1]
	return if at ~= nil and elapsed >= at then done + 1 else nil
end

-- Picks `count` markers out of `markers` (1..markers), free ones first, so wilds spread out.
-- `taken[i]` marks a marker that already holds a wild; rng returns [0, 1).
function Forest.pickMarkers(count: number, markers: number, taken: { [number]: boolean }, rng: () -> number): { number }
	local free, used = {}, {}
	for i = 1, markers do
		table.insert(if taken[i] then used else free, i)
	end
	local picks = {}
	for _ = 1, count do
		local list = if #free > 0 then free else used
		if #list == 0 then
			break
		end
		local i = math.min(#list, math.floor(rng() * #list) + 1)
		local marker = list[i]
		table.insert(picks, marker)
		if list == free then
			table.remove(free, i)
			table.insert(used, marker)
		end
	end
	return picks
end

-- Every catch rule, in the order a player would want to hear about them. Returns ok, or false
-- and a reason code.
function Forest.canCatch(cfg: any, c: Check): (boolean, string?)
	if not c.night then
		return false, "not_night"
	elseif not c.living then
		return false, "not_living"
	elseif not c.exists then
		return false, "gone"
	elseif c.catchesLeft <= 0 then
		return false, "no_catches"
	elseif not c.hasRoom then
		return false, "storage_full"
	elseif not (c.distance <= cfg.night.catchRange) then
		return false, "too_far"
	end
	return true
end

return Forest
