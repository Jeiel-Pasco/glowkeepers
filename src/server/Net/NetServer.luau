--!strict
-- Server side of the remote registry (TECH_SPEC §7).
--
-- Builds ReplicatedStorage.Remotes from Shared.Net when first required. Every client call goes
-- through the rate limit, then the argument check, and only then reaches its handler. Dropped
-- calls are counted; a flood (over 3× the per-minute limit) or repeated invalid calls fire
-- NetServer.Abuse, which ModerationService acts on. Handlers call NetServer.reject when a
-- well-formed call names something that isn't the player's (another player's id, an unknown
-- product): logged, and flagged once per remote per minute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net")) :: any
local Validate = require(Shared.Net:WaitForChild("Validate"))
local TokenBucket = require(Shared.Net:WaitForChild("TokenBucket"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

type Handler = (player: Player, ...any) -> ()
type Window = { since: number, calls: number, invalid: number, flagged: boolean }

local WINDOW_SECONDS = 60
local INVALID_CALLS_TO_FLAG = 10

local NetServer = {}
NetServer.Abuse = Signal.new() -- (player, remoteName, reason: "flood" | "invalid" | "rejected")

local remotes: { [string]: Instance } = {}
local handlers: { [string]: Handler } = {}
local buckets: { [Player]: { [string]: TokenBucket.Bucket } } = {}
local windows: { [Player]: { [string]: Window } } = {}

local function windowFor(player: Player, name: string, now: number): Window
	local perPlayer = windows[player]
	if perPlayer == nil then
		perPlayer = {}
		windows[player] = perPlayer
	end
	local window = perPlayer[name]
	if window == nil or now - window.since >= WINDOW_SECONDS then
		window = { since = now, calls = 0, invalid = 0, flagged = false }
		perPlayer[name] = window
	end
	return window
end

local function bucketFor(player: Player, name: string, def: any, now: number): TokenBucket.Bucket
	local perPlayer = buckets[player]
	if perPlayer == nil then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local bucket = perPlayer[name]
	if bucket == nil then
		bucket = TokenBucket.new(def.rate.perSecond, def.rate.burst, now)
		perPlayer[name] = bucket
	end
	return bucket
end

local function flag(player: Player, name: string, window: Window, reason: string)
	if not window.flagged then
		window.flagged = true
		NetServer.Abuse:Fire(player, name, reason)
	end
end

local function onClientCall(name: string, def: any): (Player, ...any) -> ()
	local schemas = def.args or {}
	local floodLimit = 3 * (def.rate.perSecond * WINDOW_SECONDS + def.rate.burst)
	return function(player: Player, ...: any)
		local now = os.clock()
		local window = windowFor(player, name, now)
		window.calls += 1
		if window.calls > floodLimit then
			flag(player, name, window, "flood")
		end
		if not TokenBucket.take(bucketFor(player, name, def, now), now) then
			return
		end
		local ok, reason = Validate.args(schemas, table.pack(...))
		if not ok then
			window.invalid += 1
			if window.invalid >= INVALID_CALLS_TO_FLAG then
				flag(player, name, window, "invalid")
			end
			if RunService:IsStudio() then
				warn(`[Net] {name} from {player.Name} rejected: {reason}`)
			end
			return
		end
		local handler = handlers[name]
		if handler ~= nil then
			handler(player, ...)
		end
	end
end

-- Build the remotes once, on first require.
do
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for name, def in Net.remotes do
		local className = if def.unreliable then "UnreliableRemoteEvent" else "RemoteEvent"
		local remote = folder:FindFirstChild(name)
		if remote == nil then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
		remotes[name] = remote
		if def.dir == "c2s" then
			assert(def.rate ~= nil, `Net.remotes.{name}: client → server remotes need a rate`)
			-- Through a local: a line starting with `(` would be parsed as a call on assert's result.
			local event: any = remote
			event.OnServerEvent:Connect(onClientCall(name, def))
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
	windows[player] = nil
end)

-- A handler refusing a well-formed call that can't be honest (not the player's id, an
-- unknown product). Logged; flags the player once per remote per minute.
function NetServer.reject(player: Player, name: string, reason: string)
	local window = windowFor(player, name, os.clock())
	window.invalid += 1
	if RunService:IsStudio() then
		warn(`[Net] {name} from {player.Name} rejected: {reason}`)
	end
	flag(player, name, window, "rejected")
end

-- One handler per client → server remote. Arguments arrive already type-checked.
function NetServer.on(name: string, handler: Handler)
	local def = Net.remotes[name]
	assert(def ~= nil and def.dir == "c2s", `{name} is not a client → server remote`)
	assert(handlers[name] == nil, `{name} already has a handler`)
	handlers[name] = handler
end

function NetServer.send(player: Player, name: string, ...: any)
	local def = Net.remotes[name]
	assert(def ~= nil and def.dir == "s2c", `{name} is not a server → client remote`)
	local event: any = remotes[name]
	event:FireClient(player, ...)
end

function NetServer.sendAll(name: string, ...: any)
	local def = Net.remotes[name]
	assert(def ~= nil and def.dir == "s2c", `{name} is not a server → client remote`)
	local event: any = remotes[name]
	event:FireAllClients(...)
end

return NetServer
