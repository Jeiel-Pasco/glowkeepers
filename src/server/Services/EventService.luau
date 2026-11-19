--!strict
-- Events (GAME_SYSTEMS §21). The event (when, which multipliers) is live config
-- (LiveConfigService); the services read its multipliers where they apply them:
--   luckMult RollService.luck · spawnMult ForestService waves · embersMult dawn Embers
--   glowMult IncomeService rate · passXpMult NightPassService.addXp · moonlit Roll.mutation
-- This service watches the event's start and end (every 30 s and on a live config change):
-- it recomputes everyone's income and announces the start. It also publishes today's featured
-- Deepwood species (2× spawn weight, RollService.species) as workspace `FeaturedSpecies`.
--
-- Not yet: the weekly limited species and its Glowdex page (needs limited species content and
-- events.json in ServerStorage), community goals (MemoryStore), codes (needs the Settings UI).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = require(Shared:WaitForChild("Events"))
local species = require(Shared:WaitForChild("Config"):WaitForChild("species")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local LiveConfigService = require(script.Parent:WaitForChild("LiveConfigService"))
local IncomeService = require(script.Parent:WaitForChild("IncomeService"))

local EventService = {}

local activeId: string? = nil

-- "blood_moon" → "Blood Moon"
function EventService.title(id: string): string
	local words = {}
	for word in string.gmatch(id, "[^_]+") do
		table.insert(words, string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2))
	end
	return table.concat(words, " ")
end

local function check()
	workspace:SetAttribute("FeaturedSpecies", Events.featured(species, os.time()))
	local event = LiveConfigService.event()
	local id = if event then event.id else nil
	if id == activeId then
		return
	end
	activeId = id
	for _, player in Players:GetPlayers() do
		IncomeService.recompute(player) -- glowMult changed
	end
	if id ~= nil then
		NetServer.sendAll("Announce", `{EventService.title(id)} has begun!`)
		for _, player in Players:GetPlayers() do
			Telemetry.custom(player, "event_seen", nil, { id })
		end
	end
end

function EventService.Init()
	LiveConfigService.Changed:Connect(function()
		task.defer(check)
	end)
end

function EventService.Start()
	task.spawn(function()
		while true do
			check()
			task.wait(30)
		end
	end)
end

return EventService
