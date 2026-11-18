--!strict
-- Applies SetSetting intents (GAME_SYSTEMS §26). The allowed keys and value ranges live in
-- Shared.Net.settings; NetServer has already checked that the key is one of them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net")) :: any
local Validate = require(Shared.Net:WaitForChild("Validate"))
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))

local SettingsService = {}

function SettingsService.Init()
	NetServer.on("SetSetting", function(player: Player, key: string, value: any)
		local schema = Net.settings[key]
		if schema == nil or not Validate.value(schema, value) then
			return
		end
		local data = DataService.get(player)
		if data == nil or data.settings[key] == value then
			return
		end
		data.settings[key] = value
		DataService.changed(player, "settings")
		if key == "calm" and value == true then
			Telemetry.custom(player, "calm_mode_on")
		end
	end)
end

return SettingsService
