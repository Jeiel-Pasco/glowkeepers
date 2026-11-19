--!strict
-- Daily and weekly quests (GAME_SYSTEMS §19): 3 a day (00:00 UTC) and 3 a week (Monday
-- 00:00 UTC), rolled on join and when the day or week turns. Progress comes from Progress
-- events and from GlowlingService.Added (night catches, and Rare or better). Rewards are claimed
-- with Claim("quest", "d1".."d3" | "w1".."w3") through ClaimService: Embers and pass XP. One
-- free reroll a day (QuestReroll). The rules live in Shared.Quest; the pools in economy.json.
--
-- Replicates: `quests` (and `pass` after a claim) in PlayerState, and the Wallet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quest = require(Shared:WaitForChild("Quest"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local ClaimService = require(script.Parent:WaitForChild("ClaimService"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local GlowlingService = require(script.Parent:WaitForChild("GlowlingService"))
local IncomeService = require(script.Parent:WaitForChild("IncomeService"))
local ShieldService = require(script.Parent:WaitForChild("ShieldService"))
local NightPassService = require(script.Parent:WaitForChild("NightPassService"))

local GAMEPLAY = Enum.AnalyticsEconomyTransactionType.Gameplay.Name
local CHECK_SECONDS = 30 -- how often to look for a new UTC day or week

local QuestService = {}

local rng = Random.new()
local function roll(): number
	return rng:NextNumber()
end

local function toast(player: Player, text: string, kind: string?)
	if player.Parent == Players then
		NetServer.send(player, "Toast", text, kind)
	end
end

local function options(player: Player): Quest.Options
	return { shielded = ShieldService.isShielded(player), perSec = IncomeService.perSec(player) }
end

local function refresh(player: Player)
	local data = DataService.get(player)
	if data ~= nil and Quest.refresh(economy, data.quests, os.time(), roll, options(player)) then
		DataService.changed(player, "quests")
	end
end

local function advance(player: Player, event: string, amount: number)
	local data = DataService.get(player)
	if data ~= nil and Quest.advance(data.quests, event, amount) then
		DataService.changed(player, "quests")
	end
end

local function onClaim(player: Player, id: string)
	local data = DataService.get(player)
	local scope, index = string.match(id, "^([dw])(%d)$")
	if data == nil or scope == nil then
		return
	end
	refresh(player)
	local slot = tonumber(index) :: number
	local reward, why = Quest.canClaim(economy, data.quests, scope, slot)
	if reward == nil then
		if why == "not_done" then
			toast(player, "That quest isn't finished yet", "bad")
		end
		return
	end
	local list = if scope == "d" then data.quests.daily else data.quests.weekly
	list[slot].claimed = true
	data.embers += reward.embers
	local xp = NightPassService.addXp(player, reward.xp) -- with the catch-up bonus
	DataService.changed(player, "quests")
	DataService.sendWallet(player)
	toast(player, `Quest done: +{reward.embers} Embers, +{xp} pass XP`, "good")
	Telemetry.economy(player, "Source", "Embers", reward.embers, data.embers, GAMEPLAY, "quest", { list[slot].id })
end

local function onReroll(player: Player, index: number)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	refresh(player)
	local ok, why = Quest.reroll(economy, data.quests, index, roll, options(player))
	if ok then
		DataService.changed(player, "quests")
	elseif why == "used" then
		toast(player, "You've used today's free reroll", "bad")
	end
end

function QuestService.Init()
	ClaimService.register("quest", onClaim)
	NetServer.on("QuestReroll", onReroll)
	Progress.Event:Connect(advance)
	GlowlingService.Added:Connect(function(player: Player, record: any)
		if record.src == "night" then
			advance(player, "catch_night", 1)
			if record.r >= 3 then
				advance(player, "catch_rare", 1)
			end
		end
	end)
	DataService.PlayerReady:Connect(function(player: Player)
		refresh(player)
	end)
end

function QuestService.Start()
	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			for _, player in Players:GetPlayers() do
				refresh(player)
			end
		end
	end)
end

return QuestService
