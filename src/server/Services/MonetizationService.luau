--!strict
-- Developer products, purchase prompts and ProcessReceipt (GAME_SYSTEMS §23). Rules in
-- Shared.Store; pass ownership in GamePassService; policy in PolicyGate.
--
-- PromptProduct(key): the server checks Store.canPrompt (id set, not killed, policy, owned,
-- daily cap, not mid-theft or right after a loss) and then prompts. Never unprompted.
-- ProcessReceipt: profile not loaded → NotProcessedYet (Roblox retries, also on the next
-- join); a PurchaseId already in `receipts` → PurchaseGranted; otherwise grant, record the id,
-- save, PurchaseGranted. A receipt is always granted, even over a daily cap.
-- Server Luck: workspace `ServerLuckEnds` (server time), read by RollService.luck; announced.
-- Auto-Place pass: Place best after every inventory change and every new Glowling.
--
-- DEV/BETA: workspace DebugReceipt = "<productKey>:<purchaseId>" runs the grant path.
-- Not yet: the VIP chat tag and lantern skin, the Roblox Premium perk (†), the store nudge.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Env = require(Shared:WaitForChild("Env"))
local Store = require(Shared:WaitForChild("Store"))
local economy = require(Config:WaitForChild("economy")) :: any
local products = require(Config:WaitForChild("products")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local GamePassService = require(script.Parent:WaitForChild("GamePassService"))
local PolicyGate = require(script.Parent:WaitForChild("PolicyGate"))
local LiveConfigService = require(script.Parent:WaitForChild("LiveConfigService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local GlowlingService = require(script.Parent:WaitForChild("GlowlingService"))
local StealService = require(script.Parent:WaitForChild("StealService"))
local NightPassService = require(script.Parent:WaitForChild("NightPassService"))

local IAP = Enum.AnalyticsEconomyTransactionType.IAP.Name

local REFUSALS: { [string]: string } = {
	unavailable = "That isn't available right now",
	policy = "That isn't available in your region",
	owned = "You already own that",
	cap = "You've reached today's limit for that",
	busy = "The store can wait: try again in a moment",
	no_season = "No Night Pass season is running",
	premium_owned = "You already have this season's premium pass",
}

local MonetizationService = {}

local function toast(player: Player, text: string, kind: string?)
	if player.Parent == Players then
		NetServer.send(player, "Toast", text, kind)
	end
end

local function productIds(): { [string]: number }
	return products[Env.get().name].products
end

local function keyForProduct(id: number): string?
	for key, productId in productIds() do
		if productId == id and id > 0 then
			return key
		end
	end
	return nil
end

local function addEmbers(player: Player, data: any, amount: number, sku: string)
	data.embers += amount
	Telemetry.economy(player, "Source", "Embers", amount, data.embers, IAP, sku)
end

-- Applies one product to a loaded profile. Never refuses: a receipt is always granted.
local function grant(player: Player, data: any, key: string)
	local product = Store.product(economy, key) :: any
	if product.kind == "embers" then
		addEmbers(player, data, product.amount, key)
		toast(player, `+{product.amount} Embers. Thank you!`, "good")
	elseif product.kind == "lockCharges" then
		local room = math.max(0, economy.lock.maxCharges - data.lockCharges)
		local given = math.min(product.amount, room)
		data.lockCharges += given
		DataService.changed(player, "lockCharges")
		if given < product.amount then
			addEmbers(player, data, (product.amount - given) * economy.lock.chargeEmbers, "lock_charge_over_max")
		end
		toast(player, `+{product.amount} Lock Charges`, "good")
	elseif product.kind == "serverLuck" then
		local now = workspace:GetServerTimeNow()
		local current = tonumber(workspace:GetAttribute("ServerLuckEnds")) or 0
		workspace:SetAttribute("ServerLuckEnds", Store.extendLuck(economy, current, now))
		NetServer.sendAll("Announce", `{player.DisplayName} lit the Lucky Lantern!`)
	elseif product.kind == "passPremium" then
		if NightPassService.grantPremium(player) then
			toast(player, "Premium Night Pass unlocked. Thank you!", "good")
		else
			addEmbers(player, data, economy.pass.premiumEmbers, "pass_premium_refund")
			toast(player, `You already had it: +{economy.pass.premiumEmbers} Embers instead`, "good")
		end
	end
	Store.rollDay(data.daily, os.time())
	Store.countBuy(data.daily, product.capGroup)
	DataService.sendWallet(player)
end

-- The grant path shared by ProcessReceipt and the DEV hook.
local function processKey(player: Player?, key: string?, purchaseId: string): Enum.ProductPurchaseDecision
	local data = if player ~= nil then DataService.get(player) else nil
	if player == nil or data == nil or key == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not Store.recordReceipt(data.receipts, purchaseId, os.time(), economy.store.keepReceipts) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already granted
	end
	grant(player, data, key)
	Telemetry.custom(player, "purchase", nil, { key })
	DataService.save(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	return processKey(player, keyForProduct(receipt.ProductId), tostring(receipt.PurchaseId))
end

local function onPrompt(player: Player, key: string)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	Store.rollDay(data.daily, os.time())
	local pass = Store.pass(economy, key)
	local id = if pass ~= nil then GamePassService.id(key) else tonumber(productIds()[key]) or 0
	local reason = Store.canPrompt(economy, {
		key = key,
		id = id,
		killed = LiveConfigService.get().killSwitches.products[key] == true
			or (key == "serverLuck" and LiveConfigService.killed("serverLuck")),
		paidRandomRestricted = PolicyGate.paidRandomRestricted(player),
		owned = pass ~= nil and GamePassService.owns(player, key),
		daily = data.daily,
		carrying = StealService.isCarrying(player) or InventoryService.anyHeld(player),
		now = workspace:GetServerTimeNow(),
		lostGlowlingAt = tonumber(player:GetAttribute("LostGlowlingAt")) or 0,
		lostNightAt = tonumber(player:GetAttribute("LostNightAt")) or 0,
		season = data.pass.season,
		premium = data.pass.premium,
	})
	if reason ~= nil then
		if reason == "unknown" then
			NetServer.reject(player, "PromptProduct", `unknown {key}`)
		end
		toast(player, REFUSALS[reason] or "That isn't available", "bad")
		return
	end
	if pass ~= nil then
		MarketplaceService:PromptGamePassPurchase(player, id)
	else
		MarketplaceService:PromptProductPurchase(player, id)
	end
end

local function autoPlace(player: Player)
	if GamePassService.owns(player, "autoPlace") then
		InventoryService.placeBest(player) -- no change → no Changed event, so this settles
	end
end

function MonetizationService.Init()
	MarketplaceService.ProcessReceipt = processReceipt
	NetServer.on("PromptProduct", onPrompt)
	InventoryService.Changed:Connect(function(player: Player)
		task.defer(autoPlace, player)
	end)
	GlowlingService.Added:Connect(function(player: Player)
		task.defer(autoPlace, player)
	end)
	GamePassService.Changed:Connect(function(player: Player, key: string)
		if key == "autoPlace" then
			task.defer(autoPlace, player)
		end
	end)
	if Env.get().name ~= "PROD" then
		workspace:GetAttributeChangedSignal("DebugReceipt"):Connect(function()
			local value = workspace:GetAttribute("DebugReceipt")
			if type(value) ~= "string" then
				return
			end
			local key, purchaseId = string.match(value, "^(%w+):(.+)$")
			if key ~= nil and Store.product(economy, key) ~= nil then
				for _, player in Players:GetPlayers() do
					processKey(player, key, `{purchaseId}:{player.UserId}`)
				end
			end
		end)
	end
end

function MonetizationService.Start() end

return MonetizationService
