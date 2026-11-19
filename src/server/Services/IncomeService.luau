--!strict
-- Glow income (GAME_SYSTEMS §6): every placed Glowling earns. Glow/s is recomputed only when
-- the pads change (InventoryService.Changed); a 1 Hz loop pays it out. The client extrapolates
-- the counter from the Wallet {glow, perSec, t}, which is resent on every rate change and
-- every 10 s.
--
-- Accrual pays for the time actually passed (server clock), not a fixed 1 per tick, so a slow
-- frame never makes the server fall behind the client's counter.
--
-- Offline earnings (§6): on join, floor(min(away, 6 h) × lastIncomePerSec × 10%), with `away`
-- from the server clock (Schema.onJoin; a first join or a future lastSeen pays 0). It is read
-- before the join recompute overwrites lastIncomePerSec, and shown in the OfflineEarnings popup
-- once the client is ready.
--
-- Claimed Glowdex pages add their income bonus (Shared.Glowdex.incomeBonus).
--
-- Not yet: the VIP and event multipliers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local Glowdex = require(Shared:WaitForChild("Glowdex"))
local Inventory = require(Shared:WaitForChild("Inventory"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local DataService = require(script.Parent:WaitForChild("DataService"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local NetServer = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetServer"))

local TICK_SECONDS = 1
local WALLET_EVERY = 10 -- ticks
local TELEMETRY_EVERY = 300 -- ticks; AnalyticsService gets one income event per player per 5 min

local IncomeService = {}

local rates: { [Player]: number } = {}
local paidUntil: { [Player]: number } = {} -- server time income was last paid up to
local unlogged: { [Player]: number } = {} -- income not yet sent to Telemetry
local offline: { [Player]: { amount: number, away: number } } = {} -- popup waiting for the client
local clientReady: { [Player]: boolean } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function accrue(player: Player, at: number)
	local data = DataService.get(player)
	local from = paidUntil[player]
	if data == nil or from == nil then
		return
	end
	paidUntil[player] = math.max(from, at)
	local amount = (rates[player] or 0) * math.max(0, at - from)
	if amount > 0 then
		data.glow += amount
		data.glowSinceRebirth += amount
		data.lifetimeGlow += amount
		unlogged[player] = (unlogged[player] or 0) + amount
		Progress.add(player, "glow", amount)
	end
end

local function logIncome(player: Player)
	local data = DataService.get(player)
	local amount = math.floor(unlogged[player] or 0)
	if data == nil or amount <= 0 then
		return
	end
	unlogged[player] = (unlogged[player] or 0) - amount
	local gameplay = Enum.AnalyticsEconomyTransactionType.Gameplay.Name
	Telemetry.economy(player, "Source", "Glow", amount, math.floor(data.glow), gameplay, "income")
end

local function forget(player: Player)
	rates[player] = nil
	paidUntil[player] = nil
	unlogged[player] = nil
	offline[player] = nil
	clientReady[player] = nil
end

-- Sends the offline popup once both the payout and the client are ready (either comes first).
local function sendOffline(player: Player)
	local pay = offline[player]
	if pay ~= nil and clientReady[player] then
		offline[player] = nil
		NetServer.send(player, "OfflineEarnings", pay.amount, pay.away)
	end
end

-- Pays the time away at the rate saved when they left. Runs before the join recompute.
local function payOffline(player: Player, data: any, away: number)
	local inc = economy.income
	local amount = EconomyMath.offlineIncome(away, data.lastIncomePerSec, inc.offlineCapHours, inc.offlineEfficiency)
	if amount <= 0 then
		return
	end
	data.glow += amount
	data.glowSinceRebirth += amount
	data.lifetimeGlow += amount
	local gameplay = Enum.AnalyticsEconomyTransactionType.Gameplay.Name
	Telemetry.economy(player, "Source", "Glow", amount, math.floor(data.glow), gameplay, "offline")
	offline[player] = { amount = amount, away = away }
	sendOffline(player)
end

function IncomeService.perSec(player: Player): number
	return rates[player] or 0
end

-- Pays what is owed at the old rate, then switches to the new one and resends the Wallet.
function IncomeService.recompute(player: Player)
	local data = DataService.get(player)
	if data == nil or paidUntil[player] == nil then
		return -- not joined yet: the join computes it
	end
	accrue(player, now())
	local rate = Inventory.placedValue(data, InventoryService.valueOf)
		* Economy.incomeMultiplier(economy, data.stars, 1 + Glowdex.incomeBonus(economy, data.dexClaimed))
	if rate ~= rates[player] then
		rates[player] = rate
		DataService.setIncomeRate(player, rate)
	end
end

function IncomeService.Init()
	DataService.PlayerReady:Connect(function(player: Player, data: any, info: any)
		payOffline(player, data, info.away)
		paidUntil[player] = now()
		rates[player] = nil
		IncomeService.recompute(player)
	end)
	InventoryService.Changed:Connect(IncomeService.recompute)
	DataService.ClientReady:Connect(function(player: Player)
		clientReady[player] = true
		sendOffline(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		offline[player] = nil
		clientReady[player] = nil
	end)
	DataService.PlayerLeaving:Connect(function(player: Player)
		accrue(player, now())
		logIncome(player)
		forget(player)
	end)
end

function IncomeService.Start()
	local ticks = 0
	while true do
		task.wait(TICK_SECONDS)
		ticks += 1
		local at = now()
		for player in paidUntil do
			if DataService.get(player) == nil or player.Parent ~= Players then
				forget(player) -- the session ended without PlayerLeaving (e.g. opened elsewhere)
				continue
			end
			accrue(player, at)
			if ticks % WALLET_EVERY == 0 then
				DataService.sendWallet(player)
			end
			if ticks % TELEMETRY_EVERY == 0 then
				logIncome(player)
			end
		end
	end
end

return IncomeService
