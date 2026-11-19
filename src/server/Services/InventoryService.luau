--!strict
-- Where each owned Glowling sits (GAME_SYSTEMS §7): the Place, Unplace and PlaceBest intents,
-- the player's pad layout (unlocked pads, vault pads) and the storage cap. The rules live in
-- Shared.Inventory; this service applies them to the live profile and tells the others.
--
-- Fires Changed(player) after anything moves, so IncomeService and PlotService can update.
-- A Glowling being grabbed or carried is held (StealService; TradeService will hold offers
-- too): its owner can't move it, and Place best leaves it where it is.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local Inventory = require(Shared:WaitForChild("Inventory"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local InventoryService = {}
InventoryService.Changed = Signal.new() -- (player): pads changed; Glow/s and the plot view may differ

local held: { [Player]: { [string]: boolean } } = {}

-- Vault pads from passes (+2 with the pass, §7). Passes arrive in Phase 5.
local function passVaultBonus(_player: Player): number
	return 0
end

function InventoryService.layout(player: Player, data: any): Inventory.Layout
	local slots = Economy.slotCount(economy, data.up.slots)
	return { slots = slots, vault = Economy.vaultSlots(economy, slots, data.stars, passVaultBonus(player)) }
end

-- Glow/s of one Glowling before the Star bonus.
function InventoryService.valueOf(record: any): number
	return Economy.glowlingValue(economy, record.r, record.m, record.s)
end

-- The most storage may ever hold: the bag plus the overflow that night catches may use (§7).
function InventoryService.storageCap(): number
	return economy.storage.size + economy.storage.overflow
end

-- After changing pads (and possibly other top-level keys) in place: replicate and notify.
function InventoryService.notify(player: Player, ...: string)
	DataService.changed(player, "display", "vault", ...)
	InventoryService.Changed:Fire(player)
end

-- Holds (or lets go of) a Glowling while it is grabbed or carried.
function InventoryService.hold(player: Player, id: string, on: boolean)
	local ids = held[player]
	if on then
		if ids == nil then
			ids = {}
			held[player] = ids
		end
		ids[id] = true
	elseif ids ~= nil then
		ids[id] = nil
		if next(ids) == nil then
			held[player] = nil
		end
	end
end

-- The ids this player can't move right now (grabbed, carried, offered), or nil.
function InventoryService.heldIds(player: Player): { [string]: boolean }?
	return held[player]
end

function InventoryService.isHeld(player: Player, id: string): boolean
	local ids = held[player]
	return ids ~= nil and ids[id] == true
end

function InventoryService.place(player: Player, id: string, pad: number): (boolean, string?)
	local data = DataService.get(player)
	if data == nil then
		return false, "not loaded"
	end
	local occupant = data.display[tostring(pad)] or data.vault[tostring(pad)]
	if InventoryService.isHeld(player, id) or (occupant ~= nil and InventoryService.isHeld(player, occupant)) then
		return false, "busy" -- a swap would move the held one
	end
	local ok, reason = Inventory.place(data, InventoryService.layout(player, data), id, pad)
	if ok then
		InventoryService.notify(player)
	end
	return ok, reason
end

-- Manual moves to storage stop at the bag size; only night catches may use the overflow.
function InventoryService.unplace(player: Player, id: string): (boolean, string?)
	local data = DataService.get(player)
	if data == nil then
		return false, "not loaded"
	elseif InventoryService.isHeld(player, id) then
		return false, "busy"
	end
	local ok, reason = Inventory.unplace(data, id, economy.storage.size)
	if ok then
		InventoryService.notify(player)
	end
	return ok, reason
end

function InventoryService.placeBest(player: Player): boolean
	local data = DataService.get(player)
	if data == nil then
		return false
	end
	local layout = InventoryService.layout(player, data)
	local changed = Inventory.placeBest(data, layout, InventoryService.valueOf, held[player])
	if changed then
		InventoryService.notify(player)
	end
	return changed
end

function InventoryService.Init()
	-- The vault may have grown since the last session (a Star, a pass): fit the pads to it.
	DataService.PlayerReady:Connect(function(player: Player, data: any)
		if Inventory.normalize(data, InventoryService.layout(player, data)) then
			InventoryService.notify(player)
		end
	end)

	NetServer.on("Place", function(player: Player, id: string, pad: number)
		InventoryService.place(player, id, pad)
	end)
	NetServer.on("Unplace", function(player: Player, id: string)
		InventoryService.unplace(player, id)
	end)
	NetServer.on("PlaceBest", function(player: Player)
		InventoryService.placeBest(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		held[player] = nil
	end)
end

return InventoryService
