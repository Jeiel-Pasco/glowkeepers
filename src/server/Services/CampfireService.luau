--!strict
-- The campfire at night (GAME_SYSTEMS §12, §14; D1): the fire meter, wood piles, carrying and
-- feeding, and the dawn result. Fire maths live in Shared.Fire.
--
-- Replication (TECH_SPEC §6):
--   * workspace `Fire`: the level 0..1, set when night falls and updated at 4 Hz; nil by day.
--     0 means the night is Lost: the clearing goes dark and feeding no longer helps.
--   * each WoodPile model's `Available`: false while it respawns.
--   * the character's `CarryFuel`: "wood" while carrying a piece (hands hold one at a time).
--
-- Only living players (DownedService) drain the fire, carry and feed; a player who goes down
-- drops their wood. The dawn Embers count each player's revives tonight.
--
-- Not yet: glow-shards (they need a per-night spawn count in config), the friend bonus in the
-- dawn Embers (SocialService), and Night Pass XP.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local Fire = require(Shared:WaitForChild("Fire"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local CycleService = require(script.Parent:WaitForChild("CycleService"))
local DownedService = require(script.Parent:WaitForChild("DownedService"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))

local TICK_SECONDS = 0.25 -- 4 Hz
local DEFAULT_FEED_RADIUS = 10

type Pile = { id: string, model: Model, available: boolean, respawnAt: number }

local CampfireService = {}
CampfireService.Lost = Signal.new() -- (): the fire hit 0; the Stalker may enter the clearing
CampfireService.Dawn = Signal.new() -- (survived: boolean, level: number)

local pit: BasePart? = nil
local feedRadius = DEFAULT_FEED_RADIUS
local piles: { [string]: Pile } = {}

local night = false
local level = 0
local lost = false
local survivedLastNight = false
local carrying: { [Player]: Fire.Fuel } = {}
local fed: { [Player]: number } = {} -- pieces fed this night

function CampfireService.level(): number?
	return if night then level else nil
end

function CampfireService.isLost(): boolean
	return night and lost
end

-- Luck ×1.25 until the next dawn when last night's fire survived (§4).
function CampfireService.survivedLastNight(): boolean
	return survivedLastNight
end

function CampfireService.carrying(player: Player): Fire.Fuel?
	return carrying[player]
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

-- Living players drain the fire; downed players and wisps don't.
local function livingCount(): number
	local n = 0
	for _, player in Players:GetPlayers() do
		if DownedService.isLiving(player) then
			n += 1
		end
	end
	return n
end

local function setCarry(player: Player, fuel: Fire.Fuel?)
	carrying[player] = fuel
	local character = player.Character
	if character ~= nil then
		character:SetAttribute("CarryFuel", fuel)
	end
end

local function setPileAvailable(pile: Pile, available: boolean)
	pile.available = available
	pile.model:SetAttribute("Available", available)
end

local function publish()
	workspace:SetAttribute("Fire", if night then math.floor(level * 1000 + 0.5) / 1000 else nil)
end

local function discover()
	local fires = CollectionService:GetTagged("Campfire")
	local campfire = fires[1]
	if campfire == nil or not campfire:IsA("Model") then
		warn("[CampfireService] No Model tagged Campfire. Build the map with tools/BuildGreybox.luau (TECH_SPEC §6a).")
	else
		if #fires > 1 then
			warn(`[CampfireService] {#fires} Campfires tagged; using {campfire:GetFullName()}`)
		end
		local primary = campfire.PrimaryPart or campfire:FindFirstChild("Pit")
		pit = if primary ~= nil and primary:IsA("BasePart") then primary else nil
		local radius = campfire:GetAttribute("FeedRadius")
		feedRadius = if type(radius) == "number" and radius > 0 then radius else DEFAULT_FEED_RADIUS
		if pit == nil then
			warn("[CampfireService] The Campfire has no Pit (PrimaryPart)")
		end
	end

	for _, instance in CollectionService:GetTagged("WoodPile") do
		local id = instance:GetAttribute("PileId")
		if not instance:IsA("Model") or type(id) ~= "string" then
			warn(`[CampfireService] {instance:GetFullName()}: a WoodPile must be a Model with a PileId`)
		elseif piles[id] ~= nil then
			warn(`[CampfireService] PileId {id} is used twice; ignoring {instance:GetFullName()}`)
		else
			local pile = { id = id, model = instance, available = true, respawnAt = 0 }
			piles[id] = pile
			setPileAvailable(pile, true)
		end
	end
end

local function startNight()
	night = true
	lost = false
	level = Fire.startLevel(economy, CycleService.modifier())
	table.clear(fed)
	for _, pile in piles do
		setPileAvailable(pile, true)
	end
	publish()
end

local function dawn()
	local survived = night and not lost and level > 0
	local finalLevel = level
	night = false
	survivedLastNight = survived
	for player in carrying do
		setCarry(player, nil)
	end
	publish()

	local gameplay = Enum.AnalyticsEconomyTransactionType.Gameplay.Name
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data == nil then
			continue
		end
		local pieces = fed[player] or 0
		local revives = DownedService.revives(player)
		local embers = Fire.dawnEmbers(economy, survived, finalLevel, revives, pieces)
		local glowLost = 0
		data.embers += embers
		if survived then
			data.stats.nightsSurvived += 1
			Telemetry.custom(player, "fire_survived", math.floor(finalLevel * 100))
		else
			glowLost = Economy.nightLostPenalty(economy, data.glow)
			data.glow -= glowLost
			data.stats.firesLost += 1
			Telemetry.custom(player, "fire_lost")
			Telemetry.economy(player, "Sink", "Glow", glowLost, math.floor(data.glow), gameplay, "night_lost")
		end
		Telemetry.economy(player, "Source", "Embers", embers, data.embers, gameplay, "dawn")
		DataService.changed(player, "stats")
		DataService.sendWallet(player)
		NetServer.send(player, "DawnResult", {
			survived = survived,
			fire = finalLevel,
			embers = embers,
			glowLost = glowLost,
			piecesFed = pieces,
			revives = revives,
		})
	end
	table.clear(fed)
	CampfireService.Dawn:Fire(survived, finalLevel)
end

local function tick(dt: number)
	local now = os.clock()
	for _, pile in piles do
		if not pile.available and now >= pile.respawnAt then
			setPileAvailable(pile, true)
		end
	end
	if not night or lost then
		return
	end
	level = Fire.step(economy, level, Fire.drainPerSecond(economy, livingCount(), CycleService.modifier()), dt)
	if level <= 0 then
		level = 0
		lost = true
		CampfireService.Lost:Fire()
	end
	publish()
end

local function onPickup(player: Player, pileId: string)
	local pile = piles[pileId]
	local root = rootOf(player)
	if not night or pile == nil or not pile.available or carrying[player] ~= nil or root == nil then
		return
	elseif not DownedService.isLiving(player) then
		return
	end
	if (root.Position - pile.model:GetPivot().Position).Magnitude > economy.fire.pickupRange then
		return
	end
	pile.respawnAt = os.clock() + economy.fire.pileRespawnSeconds
	setPileAvailable(pile, false)
	setCarry(player, "wood")
end

local function onFeed(player: Player)
	local fuel = carrying[player]
	local root = rootOf(player)
	local firePit = pit
	if not night or lost or fuel == nil or root == nil or firePit == nil then
		return
	elseif not DownedService.isLiving(player) then
		return
	end
	if (root.Position - firePit.Position).Magnitude > feedRadius then
		return
	end
	setCarry(player, nil)
	level = Fire.feed(economy, level, fuel)
	fed[player] = (fed[player] or 0) + 1
	local data = DataService.get(player)
	if data ~= nil then
		data.stats.piecesFed += 1
		DataService.changed(player, "stats")
	end
	publish()
end

function CampfireService.Init()
	discover()
	NetServer.on("PickupFuel", onPickup)
	NetServer.on("FeedFire", onFeed)
	DownedService.Downed:Connect(function(player: Player)
		if carrying[player] ~= nil then
			setCarry(player, nil) -- dropped: the hands of the downed are empty
		end
	end)

	CycleService.PhaseChanged:Connect(function(phase: string)
		if phase == "Night" and not night then
			startNight()
		elseif phase == "Day" and night then
			dawn()
		end
	end)

	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			carrying[player] = nil -- a new character has empty hands
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		carrying[player] = nil
		fed[player] = nil
	end)
end

function CampfireService.Start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= TICK_SECONDS then
			tick(elapsed)
			elapsed = 0
		end
	end)
end

return CampfireService
