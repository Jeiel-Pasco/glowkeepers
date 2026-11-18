--!strict
-- Server rolls (GAME_SYSTEMS §4–5): wraps the pure Shared.Roll with one per-server Random,
-- picks the species, grants the record through GlowlingService and sends RollResult.
--
-- Callers: ShopService (lures, Phase 3) and ForestService (night catches). Luck here is
-- Lantern, Stars and last night's fire; events, Server Luck and tutorial overrides join as
-- the services that own them arrive.
--
-- DEV/BETA: set the server-side workspace attribute DebugRoll to a lure floor (1–4) to give
-- every player one lure roll and run "Place best" for them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Economy = require(Shared:WaitForChild("Economy"))
local Env = require(Shared:WaitForChild("Env"))
local Roll = require(Shared:WaitForChild("Roll"))
local Types = require(Shared:WaitForChild("Types"))
local economy = require(Config:WaitForChild("economy")) :: any
local speciesConfig = require(Config:WaitForChild("species")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local CampfireService = require(script.Parent:WaitForChild("CampfireService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local GlowlingService = require(script.Parent:WaitForChild("GlowlingService"))

local RollService = {}

local random = Random.new()
local function rng(): number
	return random:NextNumber()
end

local pools: { [string]: { string } } = {}

local function pool(name: string): { string }
	local ids = pools[name]
	if ids == nil then
		ids = Roll.pool(speciesConfig, name)
		assert(#ids > 0, `species pool {name} is empty`)
		pools[name] = ids
	end
	return ids
end

function RollService.luck(player: Player): number
	local data = DataService.get(player)
	if data == nil then
		return 1
	end
	return Economy.luck(economy, data.up.lantern, data.stars, { fireSurvived = CampfireService.survivedLastNight() })
end

local function grant(player: Player, tier: number, poolName: string, src: string): Types.Glowling?
	local result = Roll.finish(economy, tier, rng)
	local record = GlowlingService.create(player, {
		sp = Roll.species(pool(poolName), rng),
		r = result.r,
		m = result.m,
		s = result.s,
	}, src)
	if record ~= nil then
		NetServer.send(player, "RollResult", record, src)
		Telemetry.custom(player, "catch", nil, { economy.rarities[record.r].id, src })
	end
	return record
end

-- A lure of rarity `floor` (1 Common .. lures.maxFloor). Clearing species only (§8).
-- Returns nil if the player isn't loaded or storage is full; nothing is rolled then.
function RollService.lure(player: Player, floor: number): Types.Glowling?
	if not GlowlingService.hasRoom(player) then
		return nil
	end
	local tier = Roll.lureRarity(economy, RollService.luck(player), floor, rng)
	return grant(player, tier, "Clearing", "lure")
end

-- A night catch from `poolName` ("Clearing" in the forest, "Deepwood" past it), with pity (§5).
function RollService.night(player: Player, poolName: string): Types.Glowling?
	local data = DataService.get(player)
	if data == nil or not GlowlingService.hasRoom(player) then
		return nil
	end
	local tier, pity = Roll.nightRarity(economy, RollService.luck(player), data.pity.sinceLegendary, rng)
	local record = grant(player, tier, poolName, "night")
	if record ~= nil then
		data.pity.sinceLegendary = pity
		DataService.changed(player, "pity")
	end
	return record
end

function RollService.Init()
	pool("Clearing") -- fail at boot, not mid-game, if the config lost a pool
	pool("Deepwood")

	if Env.get().name ~= "PROD" then
		workspace:GetAttributeChangedSignal("DebugRoll"):Connect(function()
			local floor = workspace:GetAttribute("DebugRoll")
			if type(floor) ~= "number" then
				return
			end
			workspace:SetAttribute("DebugRoll", nil) -- so the same value works again
			floor = math.clamp(math.floor(floor), 1, economy.lures.maxFloor)
			for _, player in Players:GetPlayers() do
				if RollService.lure(player, floor) ~= nil then
					InventoryService.placeBest(player)
				end
			end
		end)
	end
end

return RollService
