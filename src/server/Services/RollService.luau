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
local Events = require(Shared:WaitForChild("Events"))
local Store = require(Shared:WaitForChild("Store"))
local Roll = require(Shared:WaitForChild("Roll"))
local Types = require(Shared:WaitForChild("Types"))
local economy = require(Config:WaitForChild("economy")) :: any
local speciesConfig = require(Config:WaitForChild("species")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local LiveConfigService = require(script.Parent:WaitForChild("LiveConfigService"))
local CampfireService = require(script.Parent:WaitForChild("CampfireService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local GlowlingService = require(script.Parent:WaitForChild("GlowlingService"))

local RollService = {}

local random = Random.new()
local function rng(): number
	return random:NextNumber()
end

local pools: { [string]: { string } } = {}
local speciesById: { [string]: any } = {}
for _, entry in speciesConfig.species do
	speciesById[entry.id] = entry
end

-- The pool's species that can appear at rarity `r` (D18): their floor is at most r.
local function pool(name: string, r: number): { string }
	local key = `{name}{r}`
	local ids = pools[key]
	if ids == nil then
		ids = Roll.eligible(economy, speciesConfig, name, r)
		assert(#ids > 0, `species pool {name} has nothing at rarity {r}`)
		pools[key] = ids
	end
	return ids
end

function RollService.luck(player: Player): number
	local data = DataService.get(player)
	if data == nil then
		return 1
	end
	local luck =
		Economy.luck(economy, data.up.lantern, data.stars, { fireSurvived = CampfireService.survivedLastNight() })
	-- An event's luck boost (§21), and Server Luck (§23) unless live config switched it off.
	local serverLuck = if LiveConfigService.killed("serverLuck")
		then 1
		else Store.serverLuckMult(
			economy,
			tonumber(workspace:GetAttribute("ServerLuckEnds")) or 0,
			workspace:GetServerTimeNow()
		)
	return luck * LiveConfigService.mult("luckMult") * serverLuck
end

local function grant(player: Player, tier: number, poolName: string, src: string, species: string?): Types.Glowling?
	if species ~= nil then
		-- A wild's species was picked at spawn; the catch is never below its floor (D25).
		tier = math.max(tier, Roll.speciesFloor(economy, speciesById[species]))
	end
	local result = Roll.finish(economy, tier, rng, Events.mutationFlags(LiveConfigService.event()))
	local record = GlowlingService.create(player, {
		sp = species or Roll.species(pool(poolName, result.r), rng),
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

-- Tutorial grants (GAME_SYSTEMS §22): a set rarity, outside the odds; Glowdex credit (src
-- "tutorial"). `species` may be picked earlier with RollService.pick (the stash shows it).
function RollService.tutorial(player: Player, tier: number, species: string?): Types.Glowling?
	if not GlowlingService.hasRoom(player) then
		return nil
	end
	return grant(player, tier, "Clearing", "tutorial", species)
end

-- A random species of rarity `tier` from a pool.
function RollService.pick(poolName: string, tier: number): string
	return Roll.species(pool(poolName, tier), rng)
end

-- Picks a species from a pool: ForestService shows a wild's species before it's caught. The
-- species comes from a base-luck rarity roll, so floor species spawn about as often as their
-- rarity (D25); the catch itself rolls again with the catcher's luck.
function RollService.species(poolName: string): string
	-- Today's featured Deepwood species has 2× weight (§21).
	local featured = Events.featured(speciesConfig, os.time())
	local ids = pool(poolName, Roll.rarity(economy, 1, nil, rng))
	return Events.pickSpecies(ids, featured, economy.events.featuredWeight, rng)
end

-- A night catch from `poolName` ("Clearing" in the forest, "Deepwood" past it), with pity (§5).
-- `species` is the wild's species, already picked; the rarity is rolled now, with luck, and is
-- at least `minTier` (a tutorial wild).
function RollService.night(player: Player, poolName: string, species: string?, minTier: number?): Types.Glowling?
	local data = DataService.get(player)
	if data == nil or not GlowlingService.hasRoom(player) then
		return nil
	end
	local tier, pity = Roll.nightRarity(economy, RollService.luck(player), data.pity.sinceLegendary, rng)
	tier = math.max(tier, minTier or 1)
	local record = grant(player, tier, poolName, "night", species)
	if record ~= nil then
		data.pity.sinceLegendary = pity
		DataService.changed(player, "pity")
	end
	return record
end

function RollService.Init()
	pool("Clearing", 1) -- fail at boot, not mid-game, if the config lost a pool
	pool("Deepwood", 1)

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
