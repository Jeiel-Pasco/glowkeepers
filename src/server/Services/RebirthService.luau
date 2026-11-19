--!strict
-- Rebirth (GAME_SYSTEMS §15, D3, D8): once a player has earned Economy.rebirthRequirement Glow
-- since the last rebirth, they trade Glow, upgrades, and display and storage Glowlings for +1
-- Star (+35% income, +6% luck, +1 vault slot, all permanent). The vault and the single best
-- Glowling outside it are kept. The rules live in Shared.Rebirth.
--
-- Refused while carrying a stolen Glowling, or while any of the player's Glowlings is held
-- (grabbed by a thief, or in a trade). The first rebirth ends the new-player shield. The
-- profile is saved straight away (TECH_SPEC §5, forced saves).
--
-- DEV/BETA: set the server-side workspace attribute DebugRebirthReady to make every player's
-- Glow since the last rebirth exactly the requirement for their next Star.
--
-- Replicates: the changed top-level keys in PlayerState, and the Wallet.
--
-- Not yet: badges at Star 1, 5 and 10 (BadgeService) and the star-burst cinematic (GS).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local Env = require(Shared:WaitForChild("Env"))
local Rebirth = require(Shared:WaitForChild("Rebirth"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local IncomeService = require(script.Parent:WaitForChild("IncomeService"))
local StealService = require(script.Parent:WaitForChild("StealService"))
local ForestService = require(script.Parent:WaitForChild("ForestService"))
local ShieldService = require(script.Parent:WaitForChild("ShieldService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))

local GAMEPLAY = Enum.AnalyticsEconomyTransactionType.Gameplay.Name

local REJECT_TEXT: { [string]: string } = {
	too_early = "Not enough Glow earned for the next Star yet",
	carrying = "Deliver or drop what you're carrying first",
	busy = "One of your Glowlings is busy right now",
}

local RebirthService = {}

local function toast(player: Player, text: string, kind: string?)
	if player.Parent == Players then
		NetServer.send(player, "Toast", text, kind)
	end
end

local function onRebirth(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	IncomeService.recompute(player) -- pay income up to now: it counts toward the requirement
	local held = InventoryService.heldIds(player)
	local ok, why = Rebirth.canRebirth({
		glowSinceRebirth = data.glowSinceRebirth,
		requirement = Economy.rebirthRequirement(economy, data.stars),
		carrying = StealService.isCarrying(player),
		busy = held ~= nil and next(held) ~= nil,
	})
	if not ok then
		local text = if why ~= nil then REJECT_TEXT[why] else nil
		if text ~= nil then
			toast(player, text, "bad")
		end
		return
	end

	local lost = math.floor(data.glow)
	local result = Rebirth.apply(data, InventoryService.valueOf)
	InventoryService.placeBest(player) -- fits the vault to the new Star and places the kept best
	DataService.changed(player, "glowlings", "display", "vault", "up", "stars", "stats")
	IncomeService.recompute(player)
	DataService.sendWallet(player)
	StealService.refreshSpeed(player) -- Boots are back to 0
	ForestService.refresh(player)
	if ShieldService.isShielded(player) then
		ShieldService.drop(player, "rebirth")
	end
	PlotService.refresh(player)
	DataService.save(player)
	Progress.add(player, "star")

	toast(player, `Star {data.stars}! +35% income, +6% luck and +1 vault slot, for good`, "good")
	if lost > 0 then
		Telemetry.economy(player, "Sink", "Glow", lost, 0, GAMEPLAY, "rebirth")
	end
	Telemetry.custom(player, "rebirth", data.stars, { tostring(#result.removed) })
	if data.stars == 1 then
		Telemetry.funnel(player, "FirstRebirth", nil, 4, "rebirth")
	end
end

local function debugRebirthReady()
	if workspace:GetAttribute("DebugRebirthReady") == nil then
		return
	end
	workspace:SetAttribute("DebugRebirthReady", nil) -- so the same value works again
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data ~= nil then
			IncomeService.recompute(player)
			data.glowSinceRebirth = Economy.rebirthRequirement(economy, data.stars)
			DataService.sendWallet(player)
		end
	end
end

function RebirthService.Init()
	NetServer.on("Rebirth", onRebirth)
	if Env.get().name ~= "PROD" then
		workspace:GetAttributeChangedSignal("DebugRebirthReady"):Connect(debugRebirthReady)
	end
end

function RebirthService.Start() end

return RebirthService
