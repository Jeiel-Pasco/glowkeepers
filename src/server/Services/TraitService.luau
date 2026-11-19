--!strict
-- Timed pet traits (GAME_SYSTEMS §31): Infuser Overcharge and Forager pouches.
--
-- Every TICK seconds, for each loaded player, Shared.Traits.step advances that plot's timers.
-- When the Overcharges change, IncomeService switches to the new rate and PlotService shows
-- them (PadView.o). A ready Forager pays a pouch of forager.pouchSeconds × its own Glow/s,
-- collected at once (never Embers, D21). Timers aren't saved: they start again on join.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Traits = require(Shared:WaitForChild("Traits"))
local Inventory = require(Shared:WaitForChild("Inventory"))
local economy = require(Config:WaitForChild("economy")) :: any
local speciesConfig = require(Config:WaitForChild("species")) :: any
local DataService = require(script.Parent:WaitForChild("DataService"))
local IncomeService = require(script.Parent:WaitForChild("IncomeService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local NetServer = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetServer"))

local TICK = 2 -- seconds; timers run on 30–90 s periods

local TraitService = {}

local speciesById: { [string]: any } = {}
for _, entry in speciesConfig.species do
	speciesById[entry.id] = entry
end

local timers: { [Player]: Traits.Timers } = {}
local random = Random.new()
local function rng(): number
	return random:NextNumber()
end

local function step(player: Player, now: number)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local mine = timers[player]
	if mine == nil then
		mine = Traits.newTimers()
		timers[player] = mine
	end
	local ids = Inventory.placedPads(data)
	local placed: Traits.Placed = {}
	for pad, id in ids do
		local record = data.glowlings[id]
		if record ~= nil then
			placed[pad] = record.sp
		else
			ids[pad] = nil
		end
	end
	local changed, pouches = Traits.step(economy, speciesById, placed, ids, mine, now, rng)
	if changed then
		IncomeService.setOvercharged(player, mine.over)
		PlotService.setOvercharged(player, mine.over)
	end
	for _, pad in pouches do
		local amount = math.floor(economy.traits.forager.pouchSeconds * IncomeService.padPerSec(player, pad))
		IncomeService.bonus(player, amount, "forager")
		local plotId = PlotService.plotOf(player)
		if plotId ~= nil and amount > 0 then
			NetServer.sendAll("TraitPouch", plotId, pad, amount)
		end
	end
end

-- The running Overcharges of a player's pads (pad → { id, ends }).
function TraitService.overcharged(player: Player): { [number]: any }
	local mine = timers[player]
	return if mine ~= nil then mine.over else {}
end

function TraitService.Init()
	Players.PlayerRemoving:Connect(function(player: Player)
		timers[player] = nil
	end)
end

function TraitService.Start()
	while true do
		task.wait(TICK)
		local now = workspace:GetServerTimeNow()
		for _, player in Players:GetPlayers() do
			step(player, now)
		end
	end
end

return TraitService
