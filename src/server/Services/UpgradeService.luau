--!strict
-- Upgrades bought with Glow (GAME_SYSTEMS §9): Lantern (+12% luck), Boots (+4% run speed, +1
-- night catch per 5 levels) and Slots (+1 display slot), one level at a time or "Buy max";
-- and Lock Charges (§11), for Glow or Embers, up to 5 held. Prices and rules live in
-- Shared.Economy (upgradeCost, upgradePurchase, lockChargePrice).
--
-- Effects: the Lantern is read live by RollService.luck; Boots refresh the RunSpeed attribute
-- (StealService.refreshSpeed) and tonight's catches (ForestService.refresh); Slots change the
-- layout, so InventoryService.notify recomputes income and the plot view. Lock Charges are
-- `lockCharges`, which LockService spends.
--
-- Replicates: `up`, `lockCharges` in PlayerState, and the Wallet after every purchase.
--
-- Rebirth resets Lantern, Boots and Slots (RebirthService).
--
-- Not yet: the Swift Boots pass (Phase 5).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local IncomeService = require(script.Parent:WaitForChild("IncomeService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local StealService = require(script.Parent:WaitForChild("StealService"))
local ForestService = require(script.Parent:WaitForChild("ForestService"))

local NAMES: { [string]: string } = { lantern = "Lantern", boots = "Boots", slots = "Slots" }
local SHOP = Enum.AnalyticsEconomyTransactionType.Shop.Name

local UpgradeService = {}

local function toast(player: Player, text: string, kind: string?)
	if player.Parent == Players then
		NetServer.send(player, "Toast", text, kind)
	end
end

local function onUpgrade(player: Player, id: string, all: boolean?)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	IncomeService.recompute(player) -- pay income up to now, so the balance matches the client's
	local level = data.up[id]
	local count, total = Economy.upgradePurchase(economy, id, level, data.glow, all == true)
	if count == 0 then
		local maxed = Economy.upgradeCost(economy, id, level) == nil
		toast(player, if maxed then `{NAMES[id]} is maxed` else "Not enough Glow", "bad")
		return
	end
	data.glow -= total
	data.up[id] = level + count
	DataService.changed(player, "up")
	DataService.sendWallet(player)
	Telemetry.economy(player, "Sink", "Glow", total, math.floor(data.glow), SHOP, id, { tostring(level + count) })

	if id == "boots" then
		StealService.refreshSpeed(player)
		ForestService.refresh(player)
	elseif id == "slots" then
		InventoryService.notify(player)
	end
	local shown = if id == "slots" then Economy.slotCount(economy, data.up.slots) else data.up[id]
	toast(player, `{NAMES[id]} {shown}`, "good")
end

local function onLockCharge(player: Player, currency: string)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	if data.lockCharges >= economy.lock.maxCharges then
		toast(player, `You hold the most Lock Charges ({economy.lock.maxCharges})`, "bad")
		return
	end
	IncomeService.recompute(player)
	local price = Economy.lockChargePrice(economy, currency, IncomeService.perSec(player))
	local key = if currency == "embers" then "embers" else "glow"
	if data[key] < price then
		toast(player, if key == "embers" then "Not enough Embers" else "Not enough Glow", "bad")
		return
	end
	data[key] -= price
	data.lockCharges += 1
	DataService.changed(player, "lockCharges")
	DataService.sendWallet(player)
	local currencyName = if key == "embers" then "Embers" else "Glow"
	Telemetry.economy(player, "Sink", currencyName, price, math.floor(data[key]), SHOP, "lock_charge")
	toast(player, `Lock Charge bought ({data.lockCharges} held)`, "good")
end

function UpgradeService.Init()
	NetServer.on("UpgradeBuy", onUpgrade)
	NetServer.on("LockChargeBuy", onLockCharge)
	DataService.PlayerReady:Connect(function(player: Player)
		StealService.refreshSpeed(player) -- Boots bought in an earlier session
	end)
end

function UpgradeService.Start() end

return UpgradeService
