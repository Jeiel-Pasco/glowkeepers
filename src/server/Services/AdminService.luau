--!strict
-- Admin and support tools (TECH_SPEC §13). Group rank ≥ admin.minRank in admin.groupId; in
-- Studio on DEV/BETA everyone is an admin. Admins get the player attribute IsAdmin (the client
-- shows the panel) and send AdminCommand(cmd, targetUserId, arg); the answer comes back as
-- AdminResult(text). The rules live in Server.Admin.Commands. A non-admin call is rejected
-- and flagged (NetServer.reject).
--
-- Every action goes to telemetry (admin_action) and, on the live stores, the DataStore `Audit`
-- (key <yyyy-mm-dd>_<JobId>, a list of { t, admin, cmd, target, detail }). Erasure logs only
-- the request id, never data.
-- Not yet: profile rollback (ProfileStore VersionQuery), offline grants, crew membership erasure.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Env = require(Shared:WaitForChild("Env"))
local Boards = require(Shared:WaitForChild("Boards"))
local economy = require(Config:WaitForChild("economy")) :: any
local species = require(Config:WaitForChild("species")) :: any
local Commands = require(Server:WaitForChild("Admin"):WaitForChild("Commands"))
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local GlowlingService = require(script.Parent:WaitForChild("GlowlingService"))
local LiveConfigService = require(script.Parent:WaitForChild("LiveConfigService"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))

local ADMIN_SOURCE = Enum.AnalyticsEconomyTransactionType.Gameplay.Name

local AdminService = {}

local speciesIds: { [string]: boolean } = {}
for _, s in species.species do
	speciesIds[s.id] = true
end

local admins: { [Player]: boolean } = {}
local pendingLive: { [Player]: string } = {} -- live_set JSON waiting for live_confirm

local function checkAdmin(player: Player): boolean
	if Env.get().name ~= "PROD" and RunService:IsStudio() then
		return true
	end
	local group = economy.admin.groupId
	if group <= 0 then
		return false
	end
	local ok, rank = pcall(function()
		return player:GetRankInGroup(group)
	end)
	return ok and rank >= economy.admin.minRank
end

function AdminService.isAdmin(player: Player): boolean
	return admins[player] == true
end

-- Telemetry plus, on the live stores, one appended record in the Audit store.
function AdminService.audit(admin: Player, cmd: string, target: number, detail: string)
	warn(`[Admin] {admin.Name} ({admin.UserId}) {cmd} {target} {detail}`)
	Telemetry.custom(admin, "admin_action", nil, { cmd })
	if DataService.storeMode() ~= "profilestore" then
		return
	end
	local key = `{os.date("!%Y-%m-%d")}_{game.JobId}`
	local record = { t = os.time(), admin = admin.UserId, cmd = cmd, target = target, detail = detail }
	task.spawn(function()
		local ok, err = pcall(function()
			DataStoreService:GetDataStore("Audit"):UpdateAsync(key, function(list: any)
				list = if type(list) == "table" then list else {}
				table.insert(list, record)
				return list
			end)
		end)
		if not ok then
			warn(`[Admin] audit write failed: {err}`)
		end
	end)
end

local function summary(data: any, online: boolean): string
	local count = 0
	for _ in data.glowlings or {} do
		count += 1
	end
	local flags = data.flags or {}
	return table.concat({
		if online then "online" else "offline (read-only copy)",
		`Glow {math.floor(data.glow or 0)} · Embers {data.embers or 0} · Stars {data.stars or 0}`,
		`Glowlings {count} · play days {data.playDays or 0} · trades {(data.stats or {}).trades or 0}`,
		`flags {#(flags.log or {})} · kicks {flags.kicks or 0}`,
	}, "\n")
end

local function flagLog(data: any): string
	local log = (data.flags or {}).log or {}
	if #log == 0 then
		return "no flags"
	end
	local lines = {}
	for i = #log, math.max(1, #log - 14), -1 do
		local e = log[i]
		table.insert(lines, `{os.date("!%m-%d %H:%M", e.t)} {e.k} {e.d}`)
	end
	return table.concat(lines, "\n")
end

local function pastBans(userId: number): number
	local ok, count = pcall(function()
		local pages = Players:GetBanHistoryAsync(userId)
		local n = 0
		while true do
			for _, entry in pages:GetCurrentPage() do
				if entry.Ban then
					n += 1
				end
			end
			if pages.IsFinished then
				break
			end
			pages:AdvanceToNextPageAsync()
		end
		return n
	end)
	return if ok then count else 0
end

local function eraseBoards(userId: number): number
	local now = os.time()
	local names = {}
	for _, key in Boards.KEYS do
		for _, unix in { now, now - 7 * 86400 } do
			names[Boards.storeName(key, Boards.isoWeek(unix))] = true
		end
	end
	local removed = 0
	for name in names do
		local ok = pcall(function()
			DataStoreService:GetOrderedDataStore(name):RemoveAsync(tostring(userId))
		end)
		if ok then
			removed += 1
		end
	end
	return removed
end

local function readLive(): any
	local ok, value = pcall(function()
		return DataStoreService:GetDataStore("LiveConfig"):GetAsync("current")
	end)
	if not ok then
		return nil
	end
	if type(value) == "string" then
		local okDecode, decoded = pcall(HttpService.JSONDecode, HttpService, value)
		return if okDecode then decoded else nil
	end
	return value
end

local function banText(days: number): string
	return if days < 0 then "permanently" else `for {days} day(s)`
end

-- Runs one checked command; returns the text for AdminResult.
local function run(admin: Player, c: Commands.Parsed): string
	local target = if c.target > 0 then Players:GetPlayerByUserId(c.target) else nil
	local data = if target then DataService.get(target) else nil
	local cmd = c.cmd

	if cmd == "lookup" or cmd == "flags" then
		local copy = data or DataService.peek(c.target)
		if copy == nil then
			return "no profile found"
		end
		AdminService.audit(admin, cmd, c.target, "")
		return if cmd == "lookup" then summary(copy, data ~= nil) else flagLog(copy)
	elseif cmd == "embers" or cmd == "glowling" then
		if target == nil or data == nil then
			return "the player must be in this server"
		end
		local reason = c.reason :: string
		if cmd == "embers" then
			local amount = c.amount :: number
			data.embers += amount
			DataService.sendWallet(target)
			Telemetry.economy(target, "Source", "Embers", amount, data.embers, ADMIN_SOURCE, "admin")
			NetServer.send(target, "Toast", `Support granted you {amount} Embers`, "good")
			AdminService.audit(admin, cmd, c.target, `{amount} · {reason}`)
			return `granted {amount} Embers`
		end
		local size = math.clamp(1, economy.size.min, economy.size.max)
		local rolled = { sp = c.species :: string, r = c.rarity :: number, m = 0, s = size }
		local record = GlowlingService.create(target, rolled :: any, "admin")
		if record == nil then
			return "no room in their storage"
		end
		NetServer.send(target, "Toast", "Support granted you a Glowling", "good")
		AdminService.audit(admin, cmd, c.target, `{c.species} r{c.rarity} {record.id} · {reason}`)
		return `granted {c.species} (rarity {c.rarity})`
	elseif cmd == "kick" then
		if target == nil then
			return "the player isn't in this server"
		end
		AdminService.audit(admin, cmd, c.target, c.reason :: string)
		target:Kick(c.reason)
		return "kicked"
	elseif cmd == "ban" then
		local days = if c.ladder then Commands.ladderDays(economy, pastBans(c.target)) else c.days :: number
		local ok, err = pcall(function()
			Players:BanAsync({
				UserIds = { c.target },
				ApplyToUniverse = true,
				Duration = if days < 0 then -1 else days * 86400,
				DisplayReason = "You broke the Glowkeepers rules.",
				PrivateReason = c.reason :: string,
				ExcludeAltAccounts = false,
			})
		end)
		if not ok then
			return `ban failed: {err}`
		end
		AdminService.audit(admin, cmd, c.target, `{banText(days)} · {c.reason}`)
		return `banned {banText(days)}`
	elseif cmd == "unban" then
		local ok, err = pcall(function()
			Players:UnbanAsync({ UserIds = { c.target }, ApplyToUniverse = true })
		end)
		if not ok then
			return `unban failed: {err}`
		end
		AdminService.audit(admin, cmd, c.target, "")
		return "unbanned"
	elseif cmd == "erase" then
		if target ~= nil then
			return "the player is in this server: kick them first"
		end
		local ok, err = DataService.erase(c.target)
		if not ok then
			return `erase failed: {err}`
		end
		local boards = eraseBoards(c.target)
		AdminService.audit(admin, cmd, c.target, `request {c.requestId}`) -- the id only, never data
		return `erased the profile and {boards} leaderboard entries`
	elseif cmd == "live_get" then
		local value = readLive()
		return if value == nil then "LiveConfig/current is empty" else HttpService:JSONEncode(value)
	elseif cmd == "live_set" then
		local ok, new = pcall(HttpService.JSONDecode, HttpService, c.json or "")
		if not ok or type(new) ~= "table" then
			return "not a JSON object"
		end
		pendingLive[admin] = c.json :: string
		local lines = Commands.diff(readLive() or {}, new)
		return if #lines == 0 then "no changes" else `{table.concat(lines, "\n")}\nSend live_confirm to save.`
	elseif cmd == "live_confirm" then
		local json = pendingLive[admin]
		if json == nil then
			return "nothing to confirm: send live_set first"
		end
		pendingLive[admin] = nil
		local value = HttpService:JSONDecode(json)
		local ok, err = pcall(function()
			DataStoreService:GetDataStore("LiveConfig"):SetAsync("current", value)
		end)
		if not ok then
			return `save failed: {err}`
		end
		LiveConfigService.refresh()
		AdminService.audit(admin, cmd, 0, json)
		return "saved; this server re-read it, others pick it up at their next poll"
	end
	return "unknown command"
end

function AdminService.Init()
	NetServer.on("AdminCommand", function(player: Player, cmd: string, target: number, arg: string)
		if not admins[player] then
			NetServer.reject(player, "AdminCommand", "not an admin")
			return
		end
		local parsed, reason = Commands.parse(economy, speciesIds, cmd, target, arg)
		local text = if parsed == nil then `refused: {reason}` else run(player, parsed)
		if player.Parent == Players then
			NetServer.send(player, "AdminResult", text)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		admins[player] = nil
		pendingLive[player] = nil
	end)
end

function AdminService.Start()
	local function add(player: Player)
		if checkAdmin(player) then
			admins[player] = true
			player:SetAttribute("IsAdmin", true)
		end
	end
	Players.PlayerAdded:Connect(add)
	for _, player in Players:GetPlayers() do
		task.spawn(add, player)
	end
end

return AdminService
