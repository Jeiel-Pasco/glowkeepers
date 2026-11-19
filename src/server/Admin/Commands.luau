--!strict
-- Admin command rules (TECH_SPEC §13). Pure: no requires and no engine calls.
--
-- AdminCommand(cmd, targetUserId, arg) is checked here before AdminService acts:
--   lookup                       profile summary (online, or a read-only offline copy)
--   flags                        the exploit flag log
--   embers   "<amount> <reason>" grant Embers (online)
--   glowling "<species> <rarity 1..7> <reason>"  grant a Glowling (online)
--   kick     "<reason>"
--   ban      "<days|next> <reason>"  next = the ladder (1 d, 7 d, permanent) by past bans
--   unban
--   erase    "<requestId>"       Right to Erasure: profile key + leaderboard entries
--   versions "[unix]"            saved versions at or before that time (default now)
--   rollback "<unix> <reason>"   restore the newest version at or before that time (offline)
--   live_get / live_set "<json>" (shows a diff) / live_confirm (writes it)
-- Every grant, kick and ban needs a reason.

local Commands = {}

Commands.LIST = {
	"lookup",
	"flags",
	"embers",
	"glowling",
	"kick",
	"ban",
	"unban",
	"erase",
	"versions",
	"rollback",
	"live_get",
	"live_set",
	"live_confirm",
}

local NEEDS_TARGET = {
	lookup = true,
	flags = true,
	embers = true,
	glowling = true,
	kick = true,
	ban = true,
	unban = true,
	erase = true,
	versions = true,
	rollback = true,
}

export type Parsed = {
	cmd: string,
	target: number,
	at: number?,
	amount: number?,
	species: string?,
	rarity: number?,
	days: number?,
	ladder: boolean?,
	reason: string?,
	requestId: string?,
	json: string?,
}

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

-- Splits "first rest…" into its first word and the trimmed rest.
local function head(s: string): (string, string)
	local first, rest = string.match(trim(s), "^(%S+)%s*(.*)$")
	return first or "", rest or ""
end

-- Parses and checks one command. Returns the parsed command, or nil and a reason.
-- `speciesIds` is the set of valid species ids.
function Commands.parse(
	cfg: any,
	speciesIds: { [string]: boolean },
	cmd: string,
	target: number,
	arg: string
): (Parsed?, string?)
	if table.find(Commands.LIST, cmd) == nil then
		return nil, "unknown command"
	end
	if NEEDS_TARGET[cmd] and target <= 0 then
		return nil, "needs a target user id"
	end
	local out: Parsed = { cmd = cmd, target = target }
	if cmd == "embers" then
		local amount, reason = head(arg)
		local n = tonumber(amount)
		if n == nil or n % 1 ~= 0 or n < 1 or n > cfg.admin.maxEmbers then
			return nil, `amount must be a whole number 1..{cfg.admin.maxEmbers}`
		end
		out.amount, out.reason = n, reason
	elseif cmd == "glowling" then
		local sp, rest = head(arg)
		local rarity, reason = head(rest)
		local r = tonumber(rarity)
		if not speciesIds[sp] then
			return nil, "unknown species"
		elseif r == nil or r % 1 ~= 0 or r < 1 or r > #cfg.rarities then
			return nil, `rarity must be 1..{#cfg.rarities}`
		end
		out.species, out.rarity, out.reason = sp, r, reason
	elseif cmd == "kick" then
		out.reason = trim(arg)
	elseif cmd == "ban" then
		local days, reason = head(arg)
		if days == "next" then
			out.ladder = true
		else
			local n = tonumber(days)
			if n == nil or (n ~= -1 and (n % 1 ~= 0 or n < 1)) then
				return nil, "days must be a whole number ≥ 1, -1 (permanent) or next"
			end
			out.days = n
		end
		out.reason = reason
	elseif cmd == "erase" then
		local id = trim(arg)
		if id == "" then
			return nil, "needs the erasure request id"
		end
		out.requestId = id
	elseif cmd == "versions" or cmd == "rollback" then
		local at, reason = head(arg)
		local n = tonumber(at)
		if cmd == "versions" and at == "" then
			n = nil
		elseif n == nil or n % 1 ~= 0 or n <= 0 then
			return nil, "time must be a unix timestamp in seconds"
		end
		out.at, out.reason = n, if cmd == "rollback" then reason else nil
	elseif cmd == "live_set" then
		out.json = trim(arg)
	end
	local needsReason = { embers = true, glowling = true, kick = true, ban = true, rollback = true }
	if needsReason[cmd] and (out.reason or "") == "" then
		return nil, "needs a reason"
	end
	return out, nil
end

-- Ban length in days for the ladder: the nth ban (0 before) → banLadderDays; -1 = permanent.
function Commands.ladderDays(cfg: any, pastBans: number): number
	local ladder = cfg.admin.banLadderDays
	return ladder[math.min(pastBans + 1, #ladder)]
end

local function flatten(value: any, path: string, out: { [string]: string })
	if type(value) == "table" then
		for k, v in value do
			flatten(v, if path == "" then tostring(k) else `{path}.{tostring(k)}`, out)
		end
	else
		out[path] = tostring(value)
	end
end

-- The changed leaf paths between two decoded JSON values, sorted: "path: old → new".
function Commands.diff(old: any, new: any): { string }
	local a, b = {}, {}
	flatten(old, "", a)
	flatten(new, "", b)
	local lines = {}
	for path, value in b do
		if a[path] ~= value then
			table.insert(lines, `{path}: {a[path] or "∅"} → {value}`)
		end
	end
	for path, value in a do
		if b[path] == nil then
			table.insert(lines, `{path}: {value} → ∅`)
		end
	end
	table.sort(lines)
	return lines
end

return Commands
