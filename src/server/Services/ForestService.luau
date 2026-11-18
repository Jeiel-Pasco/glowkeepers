--!strict
-- Wild Glowlings and catching at night (GAME_SYSTEMS §12, TECH_SPEC §6–8).
--
-- Three spawn waves (0:10, 0:40 and 1:10 into the night) put 4 wilds per player in the
-- forest, each on a map marker tagged `WildSpawn`, whose `Area` ("Forest" or "Deepwood")
-- picks the species pool. The species shows at once; the rarity is rolled when it's caught,
-- with the catcher's luck (RollService.night). A catch is a tap within 12 studs, checked
-- here, and spends one of the player's catches for the night (3 + floor(Boots / 5), plus the
-- modifier's extra). Wilds stay until caught or dawn. The rules live in Shared.Forest.
--
-- Replicates: WildSpawned / WildGone to everyone (a client that becomes ready mid-night gets
-- every wild), and the Player attribute `CatchesLeft` at night (nil by day). A player who
-- bleeds out loses their unused catches. A Mythic-or-better catch is announced to everyone.
--
-- Not yet: tutorial-only spawns (Phase 3 FTUE) and glow-shards (they need a spawn count).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Economy = require(Shared:WaitForChild("Economy"))
local Forest = require(Shared:WaitForChild("Forest"))
local economy = require(Config:WaitForChild("economy")) :: any
local speciesConfig = require(Config:WaitForChild("species")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local CycleService = require(script.Parent:WaitForChild("CycleService"))
local DownedService = require(script.Parent:WaitForChild("DownedService"))
local GlowlingService = require(script.Parent:WaitForChild("GlowlingService"))
local RollService = require(script.Parent:WaitForChild("RollService"))

local TICK_SECONDS = 0.25
local JITTER = 3 -- studs: wilds sharing a marker stand a little apart
local ANNOUNCE_FROM = 6 -- Mythic

type Marker = { part: BasePart, area: string }
type Wild = { id: string, sp: string, area: string, x: number, y: number, z: number, marker: number }

local ForestService = {}

local markers: { Marker } = {}
local wilds: { [string]: Wild } = {}
local used: { [number]: number } = {} -- userId → catches spent tonight (survives a rejoin)
local night = false
local wavesDone = 0
local nextId = 0
local random = Random.new()

local speciesNames: { [string]: string } = {}
for _, species in speciesConfig.species do
	speciesNames[species.id] = species.name
end

local function rng(): number
	return random:NextNumber()
end

local function discover()
	for _, part in CollectionService:GetTagged("WildSpawn") do
		local area = part:GetAttribute("Area")
		if part:IsA("BasePart") and (area == "Forest" or area == "Deepwood") then
			table.insert(markers, { part = part, area = area })
		else
			warn(`[ForestService] {part:GetFullName()}: a WildSpawn must be a Part with Area "Forest" or "Deepwood"`)
		end
	end
	if #markers == 0 then
		warn("[ForestService] No parts tagged WildSpawn. Build the map with tools/BuildGreybox.luau (TECH_SPEC §6a).")
	end
end

local function catchesLeft(player: Player): number
	local data = DataService.get(player)
	if data == nil then
		return 0
	end
	local allowed = Economy.nightCatches(economy, data.up.boots, CycleService.modifier())
	return math.max(0, allowed - (used[player.UserId] or 0))
end

local function publishCatches(player: Player)
	player:SetAttribute("CatchesLeft", if night then catchesLeft(player) else nil)
end

local function view(wild: Wild): any
	return { id = wild.id, sp = wild.sp, area = wild.area, x = wild.x, y = wild.y, z = wild.z }
end

local function spawnWave(index: number)
	local sizes = Forest.waveSizes(economy, #Players:GetPlayers(), CycleService.modifier())
	local taken: { [number]: boolean } = {}
	for _, wild in wilds do
		taken[wild.marker] = true
	end
	local list = {}
	for _, m in Forest.pickMarkers(sizes[index] or 0, #markers, taken, rng) do
		local marker = markers[m]
		local shared = taken[m] == true
		taken[m] = true
		local position = marker.part.Position
		local dx = if shared then (rng() * 2 - 1) * JITTER else 0
		local dz = if shared then (rng() * 2 - 1) * JITTER else 0
		nextId += 1
		local wild: Wild = {
			id = tostring(nextId),
			sp = RollService.species(Forest.poolFor(marker.area)),
			area = marker.area,
			x = position.X + dx,
			y = position.Y,
			z = position.Z + dz,
			marker = m,
		}
		wilds[wild.id] = wild
		table.insert(list, view(wild))
	end
	if #list > 0 then
		NetServer.sendAll("WildSpawned", list)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local REJECT_TEXT: { [string]: string } = {
	no_catches = "No catches left tonight",
	storage_full = "Your storage is full",
	too_far = "Get closer",
}

local function onCatch(player: Player, wildId: string)
	local wild = wilds[wildId]
	local root = rootOf(player)
	local data = DataService.get(player)
	local check: Forest.Check = {
		night = night,
		living = DownedService.isLiving(player),
		exists = wild ~= nil,
		catchesLeft = catchesLeft(player),
		hasRoom = GlowlingService.hasRoom(player),
		distance = if wild ~= nil and root ~= nil
			then (root.Position - Vector3.new(wild.x, wild.y, wild.z)).Magnitude
			else math.huge,
	}
	local ok, why = Forest.canCatch(economy, check)
	if not ok or wild == nil or data == nil then
		local text = if why ~= nil then REJECT_TEXT[why] else nil
		if text ~= nil then
			NetServer.send(player, "Toast", text, "bad")
		end
		return
	end

	wilds[wildId] = nil -- gone before anything else can ask for it
	NetServer.sendAll("WildGone", { wildId })
	local record = RollService.night(player, Forest.poolFor(wild.area), wild.sp)
	if record == nil then
		return -- room was checked above, so only a profile that just unloaded gets here
	end
	used[player.UserId] = (used[player.UserId] or 0) + 1
	data.stats.catches += 1
	DataService.changed(player, "stats")
	publishCatches(player)
	if record.r >= ANNOUNCE_FROM then
		local rarity = economy.rarities[record.r].id
		NetServer.sendAll("Announce", `{player.DisplayName} caught a {rarity} {speciesNames[record.sp] or record.sp}!`)
	end
end

local function startNight()
	night = true
	wavesDone = 0
	table.clear(used)
	table.clear(wilds)
	for _, player in Players:GetPlayers() do
		publishCatches(player)
	end
end

local function dawn()
	night = false
	local ids = {}
	for id in wilds do
		table.insert(ids, id)
	end
	table.clear(wilds)
	if #ids > 0 then
		NetServer.sendAll("WildGone", ids)
	end
	for _, player in Players:GetPlayers() do
		publishCatches(player)
	end
end

local function tick()
	if not night then
		return
	end
	local state = CycleService.get()
	local elapsed = state.t - economy.cycle.daySeconds
	local due = Forest.dueWave(economy, elapsed, wavesDone)
	while due ~= nil do
		spawnWave(due)
		wavesDone = due
		due = Forest.dueWave(economy, elapsed, wavesDone)
	end
end

function ForestService.Init()
	discover()
	NetServer.on("Catch", onCatch)

	CycleService.PhaseChanged:Connect(function(phase: string)
		if phase == "Night" and not night then
			startNight()
		elseif phase ~= "Night" and night then
			dawn()
		end
	end)
	DataService.PlayerReady:Connect(publishCatches)
	DataService.ClientReady:Connect(function(player: Player)
		local list = {}
		for _, wild in wilds do
			table.insert(list, view(wild))
		end
		if #list > 0 then
			NetServer.send(player, "WildSpawned", list)
		end
	end)
	-- A wisp has faded for the night: their unused catches go with them.
	DownedService.BledOut:Connect(function(player: Player)
		local data = DataService.get(player)
		if data ~= nil then
			used[player.UserId] = Economy.nightCatches(economy, data.up.boots, CycleService.modifier())
		end
		publishCatches(player)
	end)
end

function ForestService.Start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= TICK_SECONDS then
			elapsed = 0
			tick()
		end
	end)
end

return ForestService
