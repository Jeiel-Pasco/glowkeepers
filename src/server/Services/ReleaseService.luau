--!strict
-- Release (GAME_SYSTEMS §7, D9): storage Glowlings become Glow. Each pays 60 s of its current
-- income, Star bonus included (Economy.releaseValue). Storage only: a Glowling on a pad, or one
-- held (being grabbed, carried or offered in a trade), can't be released. A request of up to
-- 20 ids is all or nothing (Shared.Inventory.canRelease).
--
-- The Epic+ second confirmation and the Legendary+ hold-to-confirm are the client's job
-- (StorageController). Glowdex entries are kept (GlowdexService, Phase 4).
--
-- Replicates: `glowlings` in PlayerState, and the Wallet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local Inventory = require(Shared:WaitForChild("Inventory"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local GlowlingService = require(script.Parent:WaitForChild("GlowlingService"))

local GAMEPLAY = Enum.AnalyticsEconomyTransactionType.Gameplay.Name

local REJECT_TEXT: { [string]: string } = {
	placed = "Only Glowlings in storage can be released",
	held = "That Glowling is busy right now",
}

local ReleaseService = {}

local function onRelease(player: Player, ids: { string })
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local ok, why = Inventory.canRelease(data, ids, InventoryService.heldIds(player))
	if not ok then
		local text = if why ~= nil then REJECT_TEXT[why] else nil
		if text ~= nil and player.Parent == Players then
			NetServer.send(player, "Toast", text, "bad")
		end
		return
	end

	-- Value everything first, then remove and pay, with nothing yielding in between.
	local total = 0
	for _, id in ids do
		total += Economy.releaseValue(economy, InventoryService.valueOf(data.glowlings[id]), data.stars)
	end
	for _, id in ids do
		GlowlingService.remove(player, id)
	end
	data.glow += total
	data.lifetimeGlow += total
	data.glowSinceRebirth += total
	DataService.sendWallet(player)
	NetServer.send(player, "Toast", `Released {#ids} for {EconomyMath.formatNumber(total)} Glow`, "good")
	Telemetry.economy(player, "Source", "Glow", total, math.floor(data.glow), GAMEPLAY, "release", { tostring(#ids) })
end

function ReleaseService.Init()
	NetServer.on("Release", onRelease)
end

function ReleaseService.Start() end

return ReleaseService
