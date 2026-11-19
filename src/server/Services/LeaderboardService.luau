--!strict
-- In-world leaderboards (GAME_SYSTEMS §24, TECH_SPEC §5). Rules in Shared.Boards.
--
-- Boards: all-time Stars (LB_Stars) and Glowdex entries (LB_Dex), and this ISO week's revives
-- (LB_Revives_<yyyy>W<ww>) and nights survived (LB_Nights_<yyyy>W<ww>). The weekly counts
-- live in the profile (`lb`) and restart each ISO week.
--
-- Writes: a board value is marked dirty when it changes (revive, survive, star, a new Glowling
-- for the Glowdex, and on join), and written at most once per leaderboards.writeGapSeconds per
-- player and board; whatever is still dirty is written when the player leaves. Reads: the top
-- N of each board every leaderboards.refreshSeconds, sent to everyone as `Leaderboards`.
--
-- Only real DataStores ("profilestore" mode) are written and read. In Studio without API
-- access the boards show the players in this server, so the UI can still be tested.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Boards = require(Shared:WaitForChild("Boards"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local GlowlingService = require(script.Parent:WaitForChild("GlowlingService"))

type Entry = { name: string, value: number }

local LeaderboardService = {}

local values: { [Player]: { [string]: number } } = {} -- last known board values
local dirty: { [Player]: { [string]: boolean } } = {}
local lastWrite: { [Player]: { [string]: number } } = {}
local names: { [number]: string } = {}
local latest: { [string]: any } = {} -- what was last sent: { stars = { Entry }, ..., week }

local function week(): string
	return Boards.isoWeek(os.time())
end

local function live(): boolean
	return DataService.storeMode() == "profilestore"
end

local function mark(player: Player, keys: { string })
	local data = DataService.get(player)
	if data == nil then
		return
	end
	values[player] = Boards.values(data, week())
	local d = dirty[player] or {}
	for _, key in keys do
		d[key] = true
	end
	dirty[player] = d
end

local function write(player: Player, key: string, value: number, wk: string)
	local ok, err = pcall(function()
		DataStoreService:GetOrderedDataStore(Boards.storeName(key, wk)):SetAsync(tostring(player.UserId), value)
	end)
	if not ok then
		warn(`[LeaderboardService] write {key} failed: {err}`)
	end
end

-- Writes this player's dirty boards that are due (or all of them when `force`).
local function flush(player: Player, force: boolean)
	local d, v = dirty[player], values[player]
	if d == nil or v == nil or not live() then
		return
	end
	local now = os.clock()
	local writes = lastWrite[player] or {}
	lastWrite[player] = writes
	local wk = week()
	for key in d do
		if force or Boards.canWrite(economy, writes[key], now) then
			d[key] = nil
			writes[key] = now
			task.spawn(write, player, key, v[key], wk)
		end
	end
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and type(name) == "string" then name else `Player {userId}`
	names[userId] = result
	return result
end

local function readLive(key: string, wk: string): { Entry }
	local out = {}
	local ok, err = pcall(function()
		local store = DataStoreService:GetOrderedDataStore(Boards.storeName(key, wk))
		local page = store:GetSortedAsync(false, economy.leaderboards.top):GetCurrentPage()
		for _, item in page do
			local userId = tonumber(item.key)
			if userId ~= nil and item.value > 0 then
				table.insert(out, { name = nameOf(userId), value = item.value })
			end
		end
	end)
	if not ok then
		warn(`[LeaderboardService] read {key} failed: {err}`)
	end
	return out
end

-- The same boards from the players in this server (Studio and mock stores).
local function readLocal(key: string): { Entry }
	local out = {}
	for player, v in values do
		if player.Parent == Players and v[key] > 0 then
			table.insert(out, { name = player.DisplayName, value = v[key] })
		end
	end
	table.sort(out, function(a, b)
		return a.value > b.value
	end)
	while #out > economy.leaderboards.top do
		table.remove(out)
	end
	return out
end

local function refresh()
	local wk = week()
	local boards: { [string]: any } = { week = wk }
	for _, key in Boards.KEYS do
		boards[key] = if live() then readLive(key, wk) else readLocal(key)
	end
	latest = boards
	NetServer.sendAll("Leaderboards", boards)
end

function LeaderboardService.Init()
	DataService.PlayerReady:Connect(function(player: Player, data: any)
		Boards.roll(data.lb, week())
		mark(player, Boards.KEYS)
		if not live() then
			task.delay(1, refresh)
		end
	end)
	DataService.ClientReady:Connect(function(player: Player)
		if latest.week ~= nil then
			NetServer.send(player, "Leaderboards", latest)
		end
	end)
	Progress.Event:Connect(function(player: Player, event: string)
		local data = DataService.get(player)
		if data == nil then
			return
		end
		if event == "revive" or event == "survive" then
			Boards.roll(data.lb, week())
			if event == "revive" then
				data.lb.revives += 1
				mark(player, { "revives" })
			else
				data.lb.nights += 1
				mark(player, { "nights" })
			end
		elseif event == "star" then
			mark(player, { "stars" })
		end
	end)
	GlowlingService.Added:Connect(function(player: Player)
		task.defer(mark, player, { "dex" }) -- after GlowdexService records it
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		flush(player, true)
		values[player] = nil
		dirty[player] = nil
		lastWrite[player] = nil
		if not live() then
			task.defer(refresh)
		end
	end)
end

function LeaderboardService.Start()
	task.spawn(function()
		while true do
			for player in dirty do
				flush(player, false)
			end
			task.wait(30)
		end
	end)
	task.spawn(function()
		task.wait(40) -- after the first write pass
		while true do
			refresh()
			task.wait(economy.leaderboards.refreshSeconds)
		end
	end)
end

return LeaderboardService
