--!strict
-- Game pass ownership (GAME_SYSTEMS §23): VIP Lantern, +2 Vault Slots, Swift Boots, Auto-Place.
-- Checked on join (UserOwnsGamePassAsync) and after an in-game purchase; cached per player and
-- mirrored to player attributes `Pass_<key>` for the client.
--
-- Effects live where they apply: IncomeService (vip ×incomeMult), InventoryService (vault2),
-- StealService.updateSpeed (swiftBoots), MonetizationService (autoPlace). They listen to Changed.
-- DEV/BETA: workspace attribute DebugPasses = "vip,vault2" grants those passes to everyone
-- ("" removes them).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Env = require(Shared:WaitForChild("Env"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local economy = require(Config:WaitForChild("economy")) :: any
local products = require(Config:WaitForChild("products")) :: any

local GamePassService = {}
GamePassService.Changed = Signal.new() -- (player, key)

local owned: { [Player]: { [string]: boolean } } = {}
local debugKeys: { [string]: boolean } = {}

local function ids(): { [string]: number }
	return products[Env.get().name].passes
end

function GamePassService.id(key: string): number
	return tonumber(ids()[key]) or 0
end

function GamePassService.owns(player: Player, key: string): boolean
	return debugKeys[key] == true or (owned[player] ~= nil and owned[player][key] == true)
end

local function set(player: Player, key: string, on: boolean)
	local map = owned[player]
	if map == nil or map[key] == on then
		return
	end
	map[key] = on
	player:SetAttribute(`Pass_{key}`, GamePassService.owns(player, key))
	GamePassService.Changed:Fire(player, key)
end

local function load(player: Player)
	owned[player] = {}
	for _, pass in economy.store.passes do
		local id = GamePassService.id(pass.key)
		local has = false
		if id > 0 then
			local ok, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			has = ok and result == true
		end
		set(player, pass.key, has)
		player:SetAttribute(`Pass_{pass.key}`, GamePassService.owns(player, pass.key))
	end
end

function GamePassService.Init()
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		owned[player] = nil
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, id: number, bought: boolean)
		if not bought then
			return
		end
		for _, pass in economy.store.passes do
			if GamePassService.id(pass.key) == id then
				set(player, pass.key, true)
			end
		end
	end)
	if Env.get().name ~= "PROD" then
		workspace:GetAttributeChangedSignal("DebugPasses"):Connect(function()
			local value = workspace:GetAttribute("DebugPasses")
			local before = debugKeys
			debugKeys = {}
			if type(value) == "string" then
				for key in string.gmatch(value, "[^,%s]+") do
					debugKeys[key] = true
				end
			end
			for _, player in Players:GetPlayers() do
				for _, pass in economy.store.passes do
					if (before[pass.key] == true) ~= (debugKeys[pass.key] == true) then
						player:SetAttribute(`Pass_{pass.key}`, GamePassService.owns(player, pass.key))
						GamePassService.Changed:Fire(player, pass.key)
					end
				end
			end
		end)
	end
end

function GamePassService.Start() end

return GamePassService
