--!strict
-- Trading (GAME_SYSTEMS §17, TECH_SPEC §8). Rules in Shared.Trade.
--
-- Flow: TradeRequest(userId) → the other player gets a request → TradeRespond(userId, accept)
-- opens a session. TradeOffer({ids}) sets your side (≤ 4, storage only) and resets both
-- confirms; TradeConfirm() unlocks 5 s after the last change and needs the Embers fee for
-- what you receive. Both confirmed → 2-minute cooling-off: the offered Glowlings are held
-- (no place, release, steal) and either side may TradeCancel(). Then the server checks
-- everything again, takes the fees, swaps both sides in one go (no yield), locks the moved
-- Glowlings for 24 h, and force-saves both profiles. A player leaving, or the server
-- shutting down, before the swap moves nothing.
--
-- Sends `TradeState(view)` to each side on every change (view = nil when the session ends).
-- Audit: Legendary+ trades go to the DataStore `TradeAudit` (live stores) and telemetry.
-- DEV/BETA: workspace DebugTradeUnlock = true skips the unlock rules (Studio test players are
-- new accounts with no Stars).

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Env = require(Shared:WaitForChild("Env"))
local Inventory = require(Shared:WaitForChild("Inventory"))
local Store = require(Shared:WaitForChild("Store"))
local Trade = require(Shared:WaitForChild("Trade"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local GlowlingService = require(script.Parent:WaitForChild("GlowlingService"))
local PolicyGate = require(script.Parent:WaitForChild("PolicyGate"))
local LiveConfigService = require(script.Parent:WaitForChild("LiveConfigService"))

type Session = {
	id: string,
	players: { Player },
	offers: { [Player]: { string } },
	confirmed: { [Player]: boolean },
	lastChange: number,
	escrowEnds: number?, -- server time; set once both confirmed
}

local UNLOCK_TEXT: { [string]: string } = {
	killed = "Trading is paused right now",
	policy = "Trading isn't available for this account",
	stars = `Trading unlocks at Star {economy.trade.minStars}`,
	days = `Trading unlocks after {economy.trade.minPlayDays} play days`,
	account = `Trading needs a Roblox account at least {economy.trade.minAccountAgeDays} days old`,
}

local OFFER_TEXT: { [string]: string } = {
	too_many = `Offer at most {economy.trade.maxPerSide} Glowlings`,
	placed = "Take it off its pad first",
	held = "That Glowling is busy",
	trade_locked = "That Glowling was traded recently (24 h lock)",
}

local TradeService = {}

local sessions: { [Player]: Session } = {}
local requests: { [Player]: { from: Player, at: number } } = {} -- keyed by the asked player

local function now(): number
	return workspace:GetServerTimeNow()
end

local function toast(player: Player, text: string, kind: string?)
	if player.Parent == Players then
		NetServer.send(player, "Toast", text, kind)
	end
end

local function other(session: Session, player: Player): Player
	return if session.players[1] == player then session.players[2] else session.players[1]
end

local function unlockReason(player: Player): string?
	local data = DataService.get(player)
	if data == nil then
		return "killed"
	end
	if Env.get().name ~= "PROD" and workspace:GetAttribute("DebugTradeUnlock") == true then
		return nil
	end
	return Trade.unlockReason(economy, {
		stars = data.stars,
		playDays = data.playDays,
		accountAge = player.AccountAge,
		policy = PolicyGate.canTrade(player),
		killed = LiveConfigService.killed("trading"),
	})
end

local function recordsOf(player: Player, ids: { string }): { any }
	local data = DataService.get(player)
	local out = {}
	for _, id in ids do
		local record = data and data.glowlings[id]
		if record ~= nil then
			table.insert(out, record)
		end
	end
	return out
end

local function valueOf(records: { any }): number
	local sum = 0
	for _, record in records do
		sum += InventoryService.valueOf(record)
	end
	return sum
end

local function view(session: Session, player: Player): any
	local partner = other(session, player)
	local mine, theirs = recordsOf(player, session.offers[player]), recordsOf(partner, session.offers[partner])
	return {
		partner = partner.DisplayName,
		partnerId = partner.UserId,
		mine = mine,
		theirs = theirs,
		myConfirmed = session.confirmed[player] == true,
		theirConfirmed = session.confirmed[partner] == true,
		confirmAt = session.lastChange + economy.trade.confirmDelay,
		escrowEnds = session.escrowEnds,
		feeIn = Trade.fee(economy, theirs),
		uneven = Trade.uneven(valueOf(mine), valueOf(theirs)),
	}
end

local function push(session: Session)
	for _, player in session.players do
		if player.Parent == Players then
			NetServer.send(player, "TradeState", view(session, player))
		end
	end
end

local function hold(session: Session, on: boolean)
	for _, player in session.players do
		for _, id in session.offers[player] do
			InventoryService.hold(player, id, on)
		end
	end
end

local function close(session: Session, text: string?)
	if session.escrowEnds ~= nil then
		hold(session, false)
	end
	for _, player in session.players do
		if sessions[player] == session then
			sessions[player] = nil
		end
		if player.Parent == Players then
			NetServer.send(player, "TradeState", nil)
			if text then
				toast(player, text)
			end
		end
	end
end

local function audit(session: Session, moved: { [Player]: { any } })
	local rare = false
	local entry: { [string]: any } = { id = session.id, at = os.time(), sides = {} }
	for _, player in session.players do
		local list = {}
		for _, record in moved[player] do
			table.insert(list, { id = record.id, sp = record.sp, r = record.r, m = record.m })
			rare = rare or record.r >= 5
		end
		entry.sides[tostring(player.UserId)] = list
	end
	if not rare then
		return
	end
	for _, player in session.players do
		Telemetry.custom(player, "trade_audit", nil, { session.id })
	end
	if DataService.storeMode() == "profilestore" then
		task.spawn(function()
			local ok, err = pcall(function()
				DataStoreService:GetDataStore("TradeAudit"):SetAsync(session.id, entry)
			end)
			if not ok then
				warn(`[TradeService] audit write failed: {err}`)
			end
		end)
	end
end

-- Re-checks everything, then swaps both sides with no yield in between.
local function swap(session: Session)
	local a, b = session.players[1], session.players[2]
	local dataA, dataB = DataService.get(a), DataService.get(b)
	if dataA == nil or dataB == nil or a.Parent ~= Players or b.Parent ~= Players then
		close(session, "The trade was cancelled")
		return
	end
	hold(session, false)
	session.escrowEnds = nil
	local unix = os.time()
	local cap = InventoryService.storageCap()
	for _, pair in { { a, dataA, b, dataB }, { b, dataB, a, dataA } } do
		local player: Player, data, partner: Player = pair[1], pair[2], pair[3]
		local give, get = session.offers[player], session.offers[partner]
		local fee = Trade.fee(economy, recordsOf(partner, get))
		if
			Trade.offerReason(economy, data, give, nil, unix) ~= nil
			or not Trade.roomFor(Inventory.storageCount(data), #get, #give, cap)
			or data.embers < fee
		then
			close(session, "The trade couldn't finish: something changed")
			return
		end
	end
	local moved: { [Player]: { any } } = { [a] = {}, [b] = {} }
	for _, pair in { { a, dataA, b }, { b, dataB, a } } do
		local player: Player, data, partner: Player = pair[1], pair[2], pair[3]
		local fee = Trade.fee(economy, recordsOf(partner, session.offers[partner]))
		data.embers -= fee
		Telemetry.economy(
			player,
			"Sink",
			"Embers",
			fee,
			data.embers,
			Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
			"trade_fee"
		)
	end
	for _, pair in { { a, b }, { b, a } } do
		local from: Player, to: Player = pair[1], pair[2]
		for _, id in session.offers[from] do
			local record = GlowlingService.transfer(from, to, id, "trade", true)
			if record ~= nil then
				record.tradeLockUntil = unix + economy.trade.tradeLockHours * 3600
				table.insert(moved[from], record)
			end
		end
	end
	for _, pair in { { a, dataA }, { b, dataB } } do
		local player: Player, data = pair[1], pair[2]
		data.stats.trades += 1
		Store.rollDay(data.daily, unix)
		Store.countBuy(data.daily, "trades")
		DataService.changed(player, "stats", "glowlings")
		DataService.sendWallet(player)
		Telemetry.custom(player, "trade_complete", #moved[player])
	end
	audit(session, moved)
	close(session, "Trade complete!")
	DataService.save(a)
	DataService.save(b)
end

local function dailyFull(player: Player): boolean
	local data = DataService.get(player)
	if data == nil then
		return true
	end
	Store.rollDay(data.daily, os.time())
	return Store.boughtToday(data.daily, "trades") >= economy.trade.maxPerDay
end

local function onRequest(player: Player, userId: number)
	local target = Players:GetPlayerByUserId(userId)
	if target == nil or target == player then
		return
	end
	local mine, theirs = unlockReason(player), unlockReason(target)
	if mine ~= nil then
		toast(player, UNLOCK_TEXT[mine], "bad")
		return
	elseif theirs ~= nil then
		toast(player, `{target.DisplayName} can't trade yet`, "bad")
		return
	elseif sessions[player] ~= nil or sessions[target] ~= nil then
		toast(player, "One of you is already trading", "bad")
		return
	elseif dailyFull(player) then
		toast(player, `You've made {economy.trade.maxPerDay} trades today`, "bad")
		return
	end
	requests[target] = { from = player, at = now() }
	NetServer.send(target, "TradeRequested", player.UserId, player.DisplayName)
	toast(player, `Trade request sent to {target.DisplayName}`)
end

local function onRespond(player: Player, userId: number, accept: boolean)
	local request = requests[player]
	if request == nil or request.from.UserId ~= userId or now() - request.at > 30 then
		return
	end
	requests[player] = nil
	local from = request.from
	if not accept then
		toast(from, `{player.DisplayName} declined the trade`)
		return
	end
	if from.Parent ~= Players or sessions[from] ~= nil or sessions[player] ~= nil then
		return
	elseif unlockReason(player) ~= nil or unlockReason(from) ~= nil or dailyFull(player) then
		toast(player, "You can't trade right now", "bad")
		return
	end
	local session: Session = {
		id = HttpService:GenerateGUID(false),
		players = { from, player },
		offers = { [from] = {}, [player] = {} },
		confirmed = {},
		lastChange = now(),
	}
	sessions[from] = session
	sessions[player] = session
	for _, p in session.players do
		Telemetry.custom(p, "trade_open")
	end
	push(session)
end

local function onOffer(player: Player, ids: { string })
	local session = sessions[player]
	local data = DataService.get(player)
	if session == nil or session.escrowEnds ~= nil or data == nil then
		return
	end
	local reason = Trade.offerReason(economy, data, ids, InventoryService.heldIds(player), os.time())
	if reason ~= nil then
		if reason == "not_owned" or reason == "duplicate" or reason == "too_many" then
			NetServer.reject(player, "TradeOffer", reason)
		end
		local text = OFFER_TEXT[reason]
		if text then
			toast(player, text, "bad")
		end
		return
	end
	session.offers[player] = table.clone(ids)
	session.confirmed = {}
	session.lastChange = now()
	push(session)
end

local function onConfirm(player: Player)
	local session = sessions[player]
	local data = DataService.get(player)
	if session == nil or session.escrowEnds ~= nil or data == nil then
		return
	end
	local partner = other(session, player)
	local fee = Trade.fee(economy, recordsOf(partner, session.offers[partner]))
	local reason = Trade.confirmReason(economy, session.lastChange, now(), data.embers, fee)
	if reason == "fee" then
		toast(player, `You need {fee} Embers for the fee`, "bad")
		return
	elseif reason ~= nil then
		return
	end
	local cap = InventoryService.storageCap()
	if not Trade.roomFor(Inventory.storageCount(data), #session.offers[partner], #session.offers[player], cap) then
		toast(player, "Make room in storage first", "bad")
		return
	end
	session.confirmed[player] = true
	if session.confirmed[partner] then
		session.escrowEnds = now() + economy.trade.escrowSeconds
		hold(session, true)
		task.delay(economy.trade.escrowSeconds, function()
			if sessions[player] == session and session.escrowEnds ~= nil then
				swap(session)
			end
		end)
	end
	push(session)
end

local function onCancel(player: Player)
	local session = sessions[player]
	if session ~= nil then
		close(session, `{player.DisplayName} cancelled the trade`)
	end
end

function TradeService.isTrading(player: Player): boolean
	return sessions[player] ~= nil
end

function TradeService.Init()
	NetServer.on("TradeRequest", onRequest)
	NetServer.on("TradeRespond", onRespond)
	NetServer.on("TradeOffer", onOffer)
	NetServer.on("TradeConfirm", onConfirm)
	NetServer.on("TradeCancel", onCancel)
	Players.PlayerRemoving:Connect(function(player: Player)
		requests[player] = nil
		local session = sessions[player]
		if session ~= nil then
			close(session, `{player.DisplayName} left: the trade was cancelled`)
		end
	end)
end

function TradeService.Start() end

return TradeService
