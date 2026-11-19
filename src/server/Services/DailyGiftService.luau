--!strict
-- The daily gift (GAME_SYSTEMS §19): a 28-step calendar, one step per UTC day the player
-- claims, never reset, looping after 28. Claimed with Claim("gift", _) through ClaimService.
-- Rewards: Embers, a lure (rolled now, like a shop lure, so storage must have room), Lock
-- Charges (capped; any over the cap become Embers) and a decoration (a repeat becomes Embers).
-- The rules live in Shared.Gift; the steps in economy.json under `gift`.
--
-- Replicates: `gift` (and what the reward changed) in PlayerState, and the Wallet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gift = require(Shared:WaitForChild("Gift"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local ClaimService = require(script.Parent:WaitForChild("ClaimService"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local GlowlingService = require(script.Parent:WaitForChild("GlowlingService"))
local RollService = require(script.Parent:WaitForChild("RollService"))

local GAMEPLAY = Enum.AnalyticsEconomyTransactionType.Gameplay.Name

local DailyGiftService = {}

local function toast(player: Player, text: string, kind: string?)
	if player.Parent == Players then
		NetServer.send(player, "Toast", text, kind)
	end
end

local function addEmbers(player: Player, data: any, amount: number, sku: string)
	data.embers += amount
	Telemetry.economy(player, "Source", "Embers", amount, data.embers, GAMEPLAY, sku)
end

local function onClaim(player: Player, _id: string)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local today = Gift.day(os.time())
	if not Gift.canClaim(data.gift, today) then
		toast(player, "Today's gift is already claimed. Come back tomorrow!", "bad")
		return
	end
	local step, reward = Gift.next(economy, data.gift)
	if reward.kind == "lure" and not GlowlingService.hasRoom(player) then
		toast(player, "Your storage is full. Make room to open today's gift", "bad")
		return
	end

	-- Mark it claimed first, with nothing yielding in between, so it can't be claimed twice.
	data.gift = Gift.claimed(data.gift, today)
	local text = `Day {step} gift`
	if reward.kind == "embers" then
		addEmbers(player, data, reward.amount :: number, "gift")
		text = `{text}: +{reward.amount} Embers`
	elseif reward.kind == "lure" then
		RollService.lure(player, reward.floor :: number) -- sends RollResult
		text = `{text}: a {economy.rarities[reward.floor :: number].id} lure`
	elseif reward.kind == "lockCharge" then
		local amount = reward.amount :: number
		local room = math.max(0, economy.lock.maxCharges - data.lockCharges)
		local given = math.min(amount, room)
		data.lockCharges += given
		DataService.changed(player, "lockCharges")
		if given < amount then
			addEmbers(player, data, (amount - given) * economy.lock.chargeEmbers, "gift_lock_charge")
		end
		text = `{text}: +{amount} Lock Charge{if amount == 1 then "" else "s"}`
	elseif reward.kind == "decor" then
		local id = reward.id :: string
		if (data.decor.owned[id] or 0) > 0 then
			addEmbers(player, data, economy.gift.dupDecorEmbers, "gift_decor_dup")
			text = `{text}: +{economy.gift.dupDecorEmbers} Embers (decoration already owned)`
		else
			data.decor.owned[id] = 1
			DataService.changed(player, "decor")
			text = `{text}: an exclusive decoration`
		end
	end
	DataService.changed(player, "gift")
	DataService.sendWallet(player)
	toast(player, text, "good")
	Telemetry.custom(player, "daily_gift", step, { reward.kind })
end

function DailyGiftService.Init()
	ClaimService.register("gift", onClaim)
end

function DailyGiftService.Start() end

return DailyGiftService
