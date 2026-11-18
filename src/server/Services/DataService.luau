--!strict
-- Loads and saves player profiles with ProfileStore (TECH_SPEC §5), repairs them on load, and
-- replicates each player's own state to their client.
--
-- Join: session-locked load → migrate → reconcile → repair → join bookkeeping → PlayerReady.
-- A player whose profile can't load is kicked with a retry message; nobody ever plays on an
-- empty profile. Other services attach per-player state only after PlayerReady.
--
-- Store selection:
--   * Server.Vendor.ProfileStore present → ProfileStore store "PlayerData" (key Player_<userId>).
--     In Studio on the PROD experience it uses the mock store, so Studio never touches live saves.
--   * Missing in DEV → an in-memory stand-in that saves nothing (loud warning).
--   * Missing in BETA or PROD → sessions are refused and players are kicked with a message.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Env = require(Shared:WaitForChild("Env"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local Schema = require(Server:WaitForChild("Data"):WaitForChild("Schema"))
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))

local STORE_NAME = "PlayerData"
local LAST_SEEN_EVERY = 30 -- seconds; keeps offline time right even if a server crashes

export type JoinInfo = { away: number, firstSession: boolean }

local DataService = {}
DataService.PlayerReady = Signal.new() -- (player, data, info: JoinInfo)
DataService.PlayerLeaving = Signal.new() -- (player, data): last chance to write before the session ends

local store: any = nil
local storeMode = "none" -- "profilestore" | "mock" | "memory" | "none"
local profiles: { [Player]: any } = {}
local clientReady: { [Player]: boolean } = {}
local stateSent: { [Player]: boolean } = {}
local incomeRate: { [Player]: number } = {}

-- The subset of ProfileStore's API used below. DEV only; saves nothing.
local function newMemoryStore(): any
	local saved: { [string]: any } = {}
	local memory: any = {}
	function memory.StartSessionAsync(_: any, key: string, _params: any): any
		local data = saved[key] or Schema.template()
		saved[key] = data
		local ended = Signal.new()
		local active = true
		local profile: any = { Data = data, OnSessionEnd = ended }
		function profile.AddUserId(_: any, _userId: number) end
		function profile.Reconcile(self: any)
			Schema.reconcile(self.Data, Schema.template())
		end
		function profile.Save(_: any) end
		function profile.IsActive(_: any): boolean
			return active
		end
		function profile.EndSession(_: any)
			if active then
				active = false
				ended:Fire()
			end
		end
		return profile
	end
	return memory
end

local function openStore()
	local env = Env.get()
	local vendor = Server:FindFirstChild("Vendor")
	local module = if vendor then vendor:FindFirstChild("ProfileStore") else nil
	if module == nil or not module:IsA("ModuleScript") then
		if env.name ~= "DEV" then
			warn(`[DataService] ProfileStore is missing on {env.name}. Sessions are refused until it is installed.`)
			storeMode = "none"
			return
		end
		warn("[DataService] Server.Vendor.ProfileStore not found. Using an in-memory store: NOTHING IS SAVED.")
		store = newMemoryStore()
		storeMode = "memory"
		return
	end
	local ProfileStore = require(module) :: any
	local live = ProfileStore.New(STORE_NAME, Schema.template())
	if env.studio and env.name == "PROD" then
		store = live.Mock
		storeMode = "mock"
	else
		store = live
		storeMode = "profilestore"
	end
end

local function sendWallet(player: Player)
	local profile = profiles[player]
	if profile == nil or not stateSent[player] then
		return
	end
	local data = profile.Data
	NetServer.send(player, "Wallet", data.glow, incomeRate[player] or 0, workspace:GetServerTimeNow(), data.embers)
end

-- The full snapshot goes out once both the profile and the client are ready.
local function sendState(player: Player)
	local profile = profiles[player]
	if profile == nil or not clientReady[player] then
		return
	end
	stateSent[player] = true
	NetServer.send(player, "PlayerState", true, Schema.clientView(profile.Data))
	sendWallet(player)
end

local function loadProfile(player: Player)
	if store == nil then
		player:Kick("Glowkeepers can't load saves right now. Please try again in a few minutes.")
		return
	end

	local profile = store:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if profile == nil then
		if player.Parent == Players then
			player:Kick("We couldn't load your save. Please rejoin in a minute.")
		end
		return
	end

	profile:AddUserId(player.UserId) -- lets a data-erasure request find this profile
	local notes = Schema.migrate(profile.Data)
	profile:Reconcile()
	for _, note in Schema.repair(profile.Data, economy) do
		table.insert(notes, note)
	end
	if #notes > 0 then
		warn(`[DataService] {player.UserId}: {#notes} save note(s): {table.concat(notes, "; ")}`)
		Telemetry.custom(player, "save_repaired", #notes)
	end

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent == Players then
			player:Kick("Your save was opened on another server. Please rejoin.")
		end
	end)

	if player.Parent ~= Players then
		profile:EndSession() -- left while loading
		return
	end

	local away, firstSession = Schema.onJoin(profile.Data, os.time())
	profiles[player] = profile
	DataService.PlayerReady:Fire(player, profile.Data, { away = away, firstSession = firstSession } :: JoinInfo)
	sendState(player)
end

local function releaseProfile(player: Player)
	local profile = profiles[player]
	if profile ~= nil then
		DataService.PlayerLeaving:Fire(player, profile.Data) -- handlers run now, before the session ends
		profile.Data.lastSeen = os.time()
		profile:EndSession()
	end
	profiles[player] = nil
	clientReady[player] = nil
	stateSent[player] = nil
	incomeRate[player] = nil
end

-- The live profile data, or nil if the player's profile isn't loaded (yet).
function DataService.get(player: Player): any?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

function DataService.isReady(player: Player): boolean
	return profiles[player] ~= nil
end

function DataService.storeMode(): string
	return storeMode
end

-- After changing top-level keys in place, send them to the owner:
--   data.settings.calm = true; DataService.changed(player, "settings")
function DataService.changed(player: Player, ...: string)
	local profile = profiles[player]
	if profile == nil or not stateSent[player] then
		return -- the snapshot will carry the change
	end
	local patch = {}
	for _, key in { ... } do
		assert(not Schema.isPrivate(key), `{key} is private and never replicated`)
		patch[key] = profile.Data[key]
	end
	NetServer.send(player, "PlayerState", false, patch)
end

-- IncomeService (Phase 2) calls this whenever Glow/s changes; it also resends the wallet.
function DataService.setIncomeRate(player: Player, perSec: number)
	incomeRate[player] = perSec
	local data = DataService.get(player)
	if data ~= nil then
		data.lastIncomePerSec = perSec
	end
	sendWallet(player)
end

DataService.sendWallet = sendWallet

-- Forced save: after every Robux purchase, completed trade and rebirth (TECH_SPEC §5).
function DataService.save(player: Player)
	local profile = profiles[player]
	if profile ~= nil then
		profile:Save()
	end
end

function DataService.Init()
	openStore()
	NetServer.on("ClientReady", function(player: Player)
		clientReady[player] = true
		sendState(player)
	end)
end

function DataService.Start()
	Players.PlayerAdded:Connect(loadProfile)
	Players.PlayerRemoving:Connect(releaseProfile)
	for _, player in Players:GetPlayers() do
		task.spawn(loadProfile, player)
	end

	while true do
		task.wait(LAST_SEEN_EVERY)
		local now = os.time()
		for _, profile in profiles do
			profile.Data.lastSeen = now
		end
	end
end

return DataService
