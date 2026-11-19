--!strict
-- The Lantern shop (GAME_SYSTEMS §8): lures for Glow, from each player's own stock for the
-- current restock window (os.time() // 300, the same in every server). A lure rolls a Clearing
-- species at the lure's rarity floor or better, with the player's luck (RollService.lure,
-- which sends RollResult). The rules live in Shared.Shop; prices in Shared.Economy.
--
-- The balance check and the spend happen with no yield between them, so two purchases in the
-- same frame can't both pass one check. If the roll can't be granted, the purchase is refunded.
--
-- Replicates: `shop` (lures bought this window) in PlayerState, and the Wallet.
--
-- Not yet: the featured slot (Species Lure, decoration, Lock Charge bundle; †), and the
-- Glowdex credit (GlowdexService, Phase 4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local Inventory = require(Shared:WaitForChild("Inventory"))
local Shop = require(Shared:WaitForChild("Shop"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local IncomeService = require(script.Parent:WaitForChild("IncomeService"))
local RollService = require(script.Parent:WaitForChild("RollService"))

local SHOP = Enum.AnalyticsEconomyTransactionType.Shop.Name

local REJECT_TEXT: { [string]: string } = {
	sold_out = "Sold out until the restock",
	storage_full = "Your storage is full. Place or release some Glowlings",
	too_poor = "Not enough Glow",
}

local ShopService = {}

local function toast(player: Player, text: string, kind: string?)
	if player.Parent == Players then
		NetServer.send(player, "Toast", text, kind)
	end
end

local function onBuy(player: Player, itemId: string)
	local floor = tonumber(string.match(itemId, "^lure(%d)$"))
	local data = DataService.get(player)
	if floor == nil or data == nil then
		return
	end
	IncomeService.recompute(player) -- pay income up to now, so the balance matches the client's
	local window = Economy.restockWindow(economy, os.time())
	local price = Economy.lureCost(economy, floor)
	local ok, why = Shop.canBuyLure(economy, {
		floor = floor,
		price = price,
		glow = data.glow,
		left = Shop.left(economy, data.shop, window, floor),
		storage = Inventory.storageCount(data),
	})
	if not ok then
		local text = if why ~= nil then REJECT_TEXT[why] else nil
		if text ~= nil then
			toast(player, text, "bad")
		end
		return
	end

	-- Spend first, with nothing yielding in between.
	local before = data.shop
	data.glow -= price
	data.shop = Shop.bought(economy, before, window, floor)
	local record = RollService.lure(player, floor)
	if record == nil then
		data.glow += price -- couldn't grant it (the profile went away or storage filled): refund
		data.shop = before
		return
	end
	DataService.changed(player, "shop")
	DataService.sendWallet(player)
	Telemetry.economy(player, "Sink", "Glow", price, math.floor(data.glow), SHOP, itemId)
end

function ShopService.Init()
	NetServer.on("ShopBuy", onBuy)
end

function ShopService.Start() end

return ShopService
