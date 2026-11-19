--!strict
-- Night Pass, data side (GAME_SYSTEMS §20). Rules in Shared.Pass.
--
-- XP: a night survived (Progress "survive"), lost ("lost"), a revive ("revive"), and quests
-- (QuestService calls addXp). ×1.5 in a season's last 2 weeks.
-- Claims: Claim("pass_free" | "pass_prem", tier) through ClaimService. Premium for Embers:
-- PassPremium() (the developer product comes with MonetizationService, Phase 5).
-- Season end: on join, and every minute for players online, a profile from an older season
-- gets its reached, unclaimed rewards granted, then a fresh pass for this season.
--
-- Replicates: `pass` (and `decor`, `cosmetics`) in PlayerState, and the Wallet.
-- DEV/BETA: workspace attribute DebugPassXp = N gives every player N pass XP (then clears).
--
-- Not yet: the Night Pass UI (GS), equipping cosmetics.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Env = require(Shared:WaitForChild("Env"))
local Pass = require(Shared:WaitForChild("Pass"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local GlowlingService = require(script.Parent:WaitForChild("GlowlingService"))
local RollService = require(script.Parent:WaitForChild("RollService"))
local ClaimService = require(script.Parent:WaitForChild("ClaimService"))
local LiveConfigService = require(script.Parent:WaitForChild("LiveConfigService"))

local GAMEPLAY = Enum.AnalyticsEconomyTransactionType.Gameplay.Name
local SHOP = Enum.AnalyticsEconomyTransactionType.Shop.Name

local NightPassService = {}

local function toast(player: Player, text: string, kind: string?)
	if player.Parent == Players then
		NetServer.send(player, "Toast", text, kind)
	end
end

local function addEmbers(player: Player, data: any, amount: number, sku: string)
	data.embers += amount
	Telemetry.economy(player, "Source", "Embers", amount, data.embers, GAMEPLAY, sku)
end

-- Grants one reward; returns its text. A lure with no storage room becomes Embers.
local function grant(player: Player, data: any, reward: Pass.Reward): string
	if reward.kind == "embers" then
		addEmbers(player, data, reward.amount :: number, "pass")
		return `+{reward.amount} Embers`
	elseif reward.kind == "lure" then
		if GlowlingService.hasRoom(player) then
			RollService.lure(player, reward.floor :: number) -- sends RollResult
			return `a {economy.rarities[reward.floor :: number].id} lure`
		end
		addEmbers(player, data, economy.pass.lureFallbackEmbers, "pass_lure_full")
		return `+{economy.pass.lureFallbackEmbers} Embers (storage full)`
	elseif reward.kind == "decor" then
		local id = reward.id :: string
		if (data.decor.owned[id] or 0) > 0 then
			addEmbers(player, data, economy.gift.dupDecorEmbers, "pass_decor_dup")
			return `+{economy.gift.dupDecorEmbers} Embers (decoration already owned)`
		end
		data.decor.owned[id] = 1
		DataService.changed(player, "decor")
		return "an exclusive decoration"
	elseif reward.kind == "cosmetic" then
		data.cosmetics[reward.id :: string] = 1
		DataService.changed(player, "cosmetics")
		return "a cosmetic"
	end
	return ""
end

-- Moves the profile to this season, auto-claiming what the old season left unclaimed.
local function roll(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local season = Pass.season(economy, os.time())
	if data.pass.season == season then
		return
	end
	local old = data.pass
	if old.season > 0 then
		local left = Pass.unclaimed(economy, old)
		for _, entry in left do
			local reward = Pass.canClaim(economy, old, entry.track, entry.tier) :: Pass.Reward
			local claimed = if entry.track == "free" then old.free else old.prem
			claimed[tostring(entry.tier)] = true
			grant(player, data, reward)
		end
		if #left > 0 then
			toast(player, `Season {old.season} ended: {#left} unclaimed rewards were added`, "good")
		end
		DataService.sendWallet(player)
	end
	data.pass = Pass.fresh(season)
	DataService.changed(player, "pass")
end

-- Adds pass XP (with the catch-up bonus); returns the XP actually added.
function NightPassService.addXp(player: Player, amount: number): number
	local data = DataService.get(player)
	if data == nil then
		return 0
	end
	roll(player)
	if data.pass.season == 0 then
		return 0
	end
	local before = Pass.tier(economy, data.pass.xp)
	local added = math.floor(Pass.xpFor(economy, amount, os.time()) * LiveConfigService.mult("passXpMult"))
	data.pass.xp += added
	DataService.changed(player, "pass")
	local after = Pass.tier(economy, data.pass.xp)
	if after > before then
		toast(player, `Night Pass tier {after}!`, "good")
	end
	return added
end

local function onClaim(track: string)
	return function(player: Player, id: string)
		local data = DataService.get(player)
		local tier = tonumber(id)
		if data == nil or tier == nil then
			return
		end
		roll(player)
		local reward, why = Pass.canClaim(economy, data.pass, track, tier)
		if reward == nil then
			if why == "locked" then
				toast(player, "Reach that tier first", "bad")
			elseif why == "premium" then
				toast(player, "That reward is on the premium track", "bad")
			end
			return
		end
		-- Mark it claimed first, with nothing yielding in between, so it can't be claimed twice.
		local claimed = if track == "free" then data.pass.free else data.pass.prem
		claimed[tostring(tier)] = true
		local text = grant(player, data, reward)
		DataService.changed(player, "pass")
		DataService.sendWallet(player)
		toast(player, `Tier {tier}: {text}`, "good")
		Telemetry.custom(player, "pass_claim", tier, { track, reward.kind })
	end
end

local function onPremium(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	roll(player)
	local price = economy.pass.premiumEmbers
	if data.pass.season == 0 then
		toast(player, "No Night Pass season is running", "bad")
		return
	elseif data.pass.premium then
		toast(player, "You already have this season's premium pass", "bad")
		return
	elseif data.embers < price then
		toast(player, "Not enough Embers", "bad")
		return
	end
	data.embers -= price
	data.pass.premium = true
	DataService.changed(player, "pass")
	DataService.sendWallet(player)
	Telemetry.economy(player, "Sink", "Embers", price, data.embers, SHOP, "pass_premium")
	toast(player, "Premium Night Pass unlocked", "good")
end

function NightPassService.Init()
	ClaimService.register("pass_free", onClaim("free"))
	ClaimService.register("pass_prem", onClaim("prem"))
	NetServer.on("PassPremium", onPremium)
	DataService.PlayerReady:Connect(function(player: Player)
		roll(player)
	end)
	Progress.Event:Connect(function(player: Player, event: string)
		local xp = economy.pass.xp[event]
		if xp ~= nil then
			NightPassService.addXp(player, xp)
		end
	end)
end

function NightPassService.Start()
	if Env.get().name ~= "PROD" then
		workspace:GetAttributeChangedSignal("DebugPassXp"):Connect(function()
			local amount = workspace:GetAttribute("DebugPassXp")
			if type(amount) == "number" and amount > 0 then
				workspace:SetAttribute("DebugPassXp", nil)
				for _, player in Players:GetPlayers() do
					NightPassService.addXp(player, amount)
				end
			end
		end)
	end
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				roll(player)
			end
		end
	end)
end

return NightPassService
