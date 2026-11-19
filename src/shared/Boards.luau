--!strict
-- Leaderboards and badges (GAME_SYSTEMS §24). Pure: no requires and no engine calls
-- (os.date only).
--
-- Boards: all-time Stars and Glowdex entries, and this ISO week's revives and nights survived.
-- Weekly counts live in the profile as `lb = { week, revives, nights }` and restart when the
-- ISO week changes, so newcomers can place. Store names follow TECH_SPEC §5:
-- LB_Stars, LB_Dex, LB_Revives_<yyyy>W<ww>, LB_Nights_<yyyy>W<ww>.
--
-- Badges: Badges.earned reads only the profile, so a badge missed while offline (or before
-- this build) is awarded on the next join.

local Boards = {}

local DAY = 86400

-- "2026W47": the ISO 8601 week (Monday start; week 1 holds the year's first Thursday).
function Boards.isoWeek(unix: number): string
	local day = unix // DAY
	local weekday = (day + 3) % 7 -- Monday = 0 (1970-01-01 was a Thursday)
	local thursday = (day - weekday + 3) * DAY
	local t = os.date("!*t", thursday) :: any
	local week = (t.yday - 1) // 7 + 1
	return string.format("%dW%02d", t.year, week)
end

-- Rolls `lb` to `week` (resetting the counts when it changed). Returns true if it rolled.
function Boards.roll(lb: any, week: string): boolean
	if lb.week == week then
		return false
	end
	lb.week = week
	lb.revives = 0
	lb.nights = 0
	return true
end

local function popcount(mask: number): number
	local n = 0
	while mask ~= 0 do
		mask = bit32.band(mask, mask - 1)
		n += 1
	end
	return n
end

-- The value of each board for this profile ("revives"/"nights" only count this ISO week).
function Boards.values(data: any, week: string): { [string]: number }
	local entries = 0
	for _, entry in data.dex or {} do
		if type(entry) == "table" then
			entries += popcount(tonumber(entry.r) or 0)
		end
	end
	local lb = data.lb or {}
	local current = lb.week == week
	return {
		stars = tonumber(data.stars) or 0,
		dex = entries,
		revives = if current then tonumber(lb.revives) or 0 else 0,
		nights = if current then tonumber(lb.nights) or 0 else 0,
	}
end

Boards.KEYS = { "stars", "dex", "revives", "nights" }

-- The OrderedDataStore name of a board for an ISO week.
function Boards.storeName(key: string, week: string): string
	if key == "stars" then
		return "LB_Stars"
	elseif key == "dex" then
		return "LB_Dex"
	elseif key == "revives" then
		return `LB_Revives_{week}`
	end
	return `LB_Nights_{week}`
end

-- Whether a changed value may be written now: at most once per writeGapSeconds per board.
function Boards.canWrite(cfg: any, lastWrite: number?, now: number): boolean
	return lastWrite == nil or now - lastWrite >= cfg.leaderboards.writeGapSeconds
end

-- Badge keys this profile has earned (in config order), whether awarded yet or not.
function Boards.badgesEarned(cfg: any, data: any): { string }
	local stats = data.stats or {}
	local rarities = 0
	for _, entry in data.dex or {} do
		if type(entry) == "table" then
			rarities = bit32.bor(rarities, tonumber(entry.r) or 0)
		end
	end
	local bronze = false
	for key, done in data.dexClaimed or {} do
		if type(key) == "string" and string.sub(key, 1, 1) ~= "@" and (tonumber(done) or 0) >= 1 then
			bronze = true
			break
		end
	end
	local stars = tonumber(data.stars) or 0
	local function hasRarity(r: number): boolean
		return bit32.btest(rarities, bit32.lshift(1, r - 1))
	end
	local rules: { [string]: boolean } = {
		welcome = true,
		night1 = (stats.nightsSurvived or 0) >= 1,
		rare = hasRarity(3),
		epic = hasRarity(4),
		legendary = hasRarity(5),
		mythic = hasRarity(6),
		secret = hasRarity(7),
		rebirth1 = stars >= 1 or (stats.rebirths or 0) >= 1,
		star5 = stars >= 5,
		star10 = stars >= 10,
		bronze1 = bronze,
		revives10 = (stats.revives or 0) >= 10,
		firesave = (stats.fireSaves or 0) >= 1,
		days7 = (tonumber(data.playDays) or 0) >= 7,
		trade1 = (stats.trades or 0) >= 1,
	}
	local out = {}
	for _, badge in cfg.badges do
		if rules[badge.key] then
			table.insert(out, badge.key)
		end
	end
	return out
end

return Boards
