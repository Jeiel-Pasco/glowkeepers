--!strict
-- Creates and removes Glowling records (GAME_SYSTEMS §3, TECH_SPEC §5). Every record lives in
-- the owner's profile under `glowlings`, keyed by a GUID. New records go to storage; where a
-- record sits is InventoryService's job. transfer moves a record between two players
-- (StealService delivery now, TradeService swaps later).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Inventory = require(Shared:WaitForChild("Inventory"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))

export type Rolled = { sp: string, r: number, m: number, s: number }

local GlowlingService = {}
GlowlingService.Added = Signal.new() -- (player, record)
GlowlingService.Removed = Signal.new() -- (player, record)

-- Adds a new record to storage. Returns nil when the profile isn't loaded or storage is at
-- its hard cap (bag + overflow); callers check room first and tell the player.
function GlowlingService.create(player: Player, rolled: Rolled, src: string): Types.Glowling?
	local data = DataService.get(player)
	if data == nil or not GlowlingService.hasRoom(player) then
		return nil
	end
	local id = HttpService:GenerateGUID(false)
	while data.glowlings[id] ~= nil do
		id = HttpService:GenerateGUID(false)
	end
	local record: Types.Glowling = {
		id = id,
		sp = rolled.sp,
		r = rolled.r,
		m = rolled.m,
		s = rolled.s,
		src = src,
		at = os.time(),
		by = player.UserId,
	}
	data.glowlings[id] = record
	DataService.changed(player, "glowlings")
	GlowlingService.Added:Fire(player, record)
	return record
end

function GlowlingService.hasRoom(player: Player): boolean
	local data = DataService.get(player)
	return data ~= nil and Inventory.storageCount(data) < InventoryService.storageCap()
end

-- Deletes a record, clearing its pad first. Returns the removed record.
function GlowlingService.remove(player: Player, id: string): Types.Glowling?
	local data = DataService.get(player)
	local record = if data ~= nil then data.glowlings[id] else nil
	if data == nil or record == nil then
		return nil
	end
	local wasPlaced = Inventory.forget(data, id)
	data.glowlings[id] = nil
	if wasPlaced then
		InventoryService.notify(player, "glowlings")
	else
		DataService.changed(player, "glowlings")
	end
	GlowlingService.Removed:Fire(player, record)
	return record
end

-- Moves a record from one loaded profile to another's storage: same id, mutation, size and
-- `by` (the original catcher); a new `src` and `at`. Returns the moved record, or nil when
-- either profile isn't loaded, `from` doesn't own it, or `to` has no room.
function GlowlingService.transfer(from: Player, to: Player, id: string, src: string): Types.Glowling?
	local fromData, toData = DataService.get(from), DataService.get(to)
	local record = if fromData ~= nil then fromData.glowlings[id] else nil
	if fromData == nil or toData == nil or record == nil or toData.glowlings[id] ~= nil then
		return nil
	elseif not GlowlingService.hasRoom(to) then
		return nil
	end
	local wasPlaced = Inventory.forget(fromData, id)
	fromData.glowlings[id] = nil
	local moved: Types.Glowling = table.clone(record)
	moved.src = src
	moved.at = os.time()
	toData.glowlings[id] = moved
	if wasPlaced then
		InventoryService.notify(from, "glowlings")
	else
		DataService.changed(from, "glowlings")
	end
	DataService.changed(to, "glowlings")
	GlowlingService.Removed:Fire(from, record)
	GlowlingService.Added:Fire(to, moved)
	return moved
end

return GlowlingService
