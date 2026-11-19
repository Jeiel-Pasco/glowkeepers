--!strict
-- The Night Companion (GAME_SYSTEMS §31, D23): SetCompanion picks or clears it by day, and the
-- player attribute `Companion` ("sp|r|m", or nil) tells every client what to draw beside them.
-- CampfireService (Firebinder) and DownedService (Savior) read the save through
-- Shared.Companion; Wayfinder runs on the client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Companion = require(Shared:WaitForChild("Companion"))
local speciesConfig = require(Shared:WaitForChild("Config"):WaitForChild("species")) :: any
local NetServer = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local CycleService = require(script.Parent:WaitForChild("CycleService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))

local CompanionService = {}

local speciesById: { [string]: any } = {}
for _, entry in speciesConfig.species do
	speciesById[entry.id] = entry
end

local REJECT = {
	night = "Companions can only change by day",
	not_in_vault = "Pick a Glowling from your vault",
}

-- The companion's species entry, or nil.
function CompanionService.species(player: Player): any
	local data = DataService.get(player)
	return if data ~= nil then Companion.species(data, speciesById) else nil
end

local function publish(player: Player)
	local data = DataService.get(player)
	local value: string? = nil
	if data ~= nil and Companion.species(data, speciesById) ~= nil then
		local record = data.glowlings[data.companion]
		value = `{record.sp}|{record.r}|{record.m}`
	end
	if player:GetAttribute("Companion") ~= value then
		player:SetAttribute("Companion", value)
	end
end

local function set(player: Player, id: string)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local why = Companion.canSet(data, id, CycleService.get().phase)
	if why ~= nil then
		NetServer.send(player, "Toast", REJECT[why], "bad")
		NetServer.reject(player, "SetCompanion", why)
		return
	end
	data.companion = if data.companion == id then "" else id
	DataService.changed(player, "companion")
	publish(player)
end

function CompanionService.Init()
	NetServer.on("SetCompanion", set)
	DataService.PlayerReady:Connect(publish)
	InventoryService.Changed:Connect(publish) -- moved out of the vault, stolen, traded, released
	Players.PlayerRemoving:Connect(function(player: Player)
		player:SetAttribute("Companion", nil)
	end)
end

return CompanionService
