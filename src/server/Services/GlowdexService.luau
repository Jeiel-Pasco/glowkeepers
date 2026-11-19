--!strict
-- The Glowdex (GAME_SYSTEMS §16, D10). Every new Glowling from a crediting source (night, lure,
-- event, tutorial; not steal, trade or fuse) sets its species' rarity bit and mutation stamp
-- in `dex`, in the same frame as the catch. Page tiers and milestones are claimed with
-- Claim("dex_page", speciesId) and Claim("dex_milestone", index) (through ClaimService): each
-- only once, checked here.
-- Claimed pages add income (IncomeService reads Glowdex.incomeBonus); milestones pay Embers.
-- The rules live in Shared.Glowdex.
--
-- Replicates: `dex` and `dexClaimed` in PlayerState, and the Wallet after a milestone.
--
-- Not yet: the cosmetic page rewards (decorations, nameplate frames, statues, auras, titles)
-- and limited species pages.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Glowdex = require(Shared:WaitForChild("Glowdex"))
local Roll = require(Shared:WaitForChild("Roll"))
local economy = require(Config:WaitForChild("economy")) :: any
local species = require(Config:WaitForChild("species")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local ClaimService = require(script.Parent:WaitForChild("ClaimService"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local GlowlingService = require(script.Parent:WaitForChild("GlowlingService"))
local IncomeService = require(script.Parent:WaitForChild("IncomeService"))

local GAMEPLAY = Enum.AnalyticsEconomyTransactionType.Gameplay.Name

local names: { [string]: string } = {}
local floors: { [string]: number } = {} -- species id → floor rarity (D18)
for _, entry in species.species do
	names[entry.id] = entry.name
	floors[entry.id] = Roll.speciesFloor(economy, entry)
end

local GlowdexService = {}

local function toast(player: Player, text: string, kind: string?)
	if player.Parent == Players then
		NetServer.send(player, "Toast", text, kind)
	end
end

local function credit(player: Player, record: any)
	local data = DataService.get(player)
	if data == nil or not Glowdex.credits(economy, record.src) or names[record.sp] == nil then
		return
	end
	local entry, new = Glowdex.record(data.dex[record.sp], record.r, record.m)
	if new then
		data.dex[record.sp] = entry
		DataService.changed(player, "dex")
	end
end

local function claimPage(player: Player, data: any, speciesId: string)
	if names[speciesId] == nil then
		return
	end
	local tier = Glowdex.canClaimPage(economy, data.dex, data.dexClaimed, speciesId, floors[speciesId])
	if tier == nil then
		toast(player, "Nothing new to claim on that page yet", "bad")
		return
	end
	data.dexClaimed[speciesId] = tier
	DataService.changed(player, "dexClaimed")
	IncomeService.recompute(player) -- the page's income bonus starts now
	if tier == 1 then
		Progress.add(player, "bronze")
	end
	local tierId = economy.glowdex.tiers[tier].id
	toast(player, `{names[speciesId]}: {tierId} page claimed`, "good")
	Telemetry.custom(player, "dex_page", tier, { tierId })
end

local function claimMilestone(player: Player, data: any, index: number)
	local embers = Glowdex.canClaimMilestone(economy, data.dex, data.dexClaimed, index)
	if embers == nil then
		return
	end
	local milestone = economy.glowdex.milestones[index]
	data.dexClaimed[Glowdex.milestoneKey(milestone.entries)] = 1
	data.embers += embers
	DataService.changed(player, "dexClaimed")
	DataService.sendWallet(player)
	toast(player, `{milestone.entries} Glowdex entries: +{embers} Embers`, "good")
	Telemetry.economy(player, "Source", "Embers", embers, data.embers, GAMEPLAY, "dex_milestone")
end

function GlowdexService.Init()
	GlowlingService.Added:Connect(credit)
	ClaimService.register("dex_page", function(player: Player, id: string)
		local data = DataService.get(player)
		if data ~= nil then
			claimPage(player, data, id)
		end
	end)
	ClaimService.register("dex_milestone", function(player: Player, id: string)
		local data = DataService.get(player)
		local index = tonumber(id)
		if data ~= nil and index ~= nil and index % 1 == 0 then
			claimMilestone(player, data, index)
		end
	end)
end

function GlowdexService.Start() end

return GlowdexService
