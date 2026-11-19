--!strict
-- Decorations and base names (GAME_SYSTEMS §18). Rules in Shared.Decor.
--
-- Remotes: DecorBuy(itemId) spends Embers; DecorPlace(itemId, x, z, rot) and
-- DecorRemove(itemId, x, z) edit `decor.placed`; SetBaseName(a, n) picks the preset name.
-- Everyone sees placed decorations and the name through the plot view (PlotService.refresh).
-- Decorations are never wiped: RebirthService leaves `decor` alone.
--
-- Not yet: placement mode (GS: drag on the grid; the panel places at the first free spot),
-- the trophy pedestal, base brightness from placed Glowlings, base themes (week L5).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Decor = require(Shared:WaitForChild("Decor"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))

local SHOP = Enum.AnalyticsEconomyTransactionType.Shop.Name

local BUY_REFUSALS: { [string]: string } = {
	unknown = "Unknown decoration",
	not_for_sale = "That decoration can't be bought",
	max_owned = `You own the most of that one ({economy.decor.maxPerItem})`,
	too_poor = "Not enough Embers",
}

local PLACE_REFUSALS: { [string]: string } = {
	not_owned = "Buy another one first",
	cap = `Your base holds at most {economy.decor.maxPlaced} decorations`,
	out_of_bounds = "That doesn't fit there",
	overlap = "Something is already there",
}

local DecorService = {}

local function toast(player: Player, text: string, kind: string?)
	if player.Parent == Players then
		NetServer.send(player, "Toast", text, kind)
	end
end

local function onBuy(player: Player, id: string)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local price, reason = Decor.canBuy(economy, data.decor, data.embers, id)
	if price == nil then
		toast(player, BUY_REFUSALS[reason :: string] or "Can't buy that", "bad")
		return
	end
	data.embers -= price
	data.decor.owned[id] = (tonumber(data.decor.owned[id]) or 0) + 1
	DataService.changed(player, "decor")
	DataService.sendWallet(player)
	Telemetry.economy(player, "Sink", "Embers", price, data.embers, SHOP, id)
	local item = Decor.item(economy, id) :: any
	toast(player, `{item.name} bought`, "good")
end

local function onPlace(player: Player, id: string, x: number, z: number, rot: number)
	local data = DataService.get(player)
	if data == nil or PlotService.plotOf(player) == nil then
		return
	end
	local entry = { id = id, x = x, z = z, rot = rot }
	local reason = Decor.canPlace(economy, data.decor, entry)
	if reason ~= nil then
		local text = PLACE_REFUSALS[reason]
		if text then
			toast(player, text, "bad")
		end
		return
	end
	table.insert(data.decor.placed, entry)
	DataService.changed(player, "decor")
	PlotService.refresh(player)
end

local function onRemove(player: Player, id: string, x: number, z: number)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local index = Decor.find(data.decor.placed, id, x, z)
	if index == nil then
		return
	end
	table.remove(data.decor.placed, index)
	DataService.changed(player, "decor")
	PlotService.refresh(player)
end

local function onBaseName(player: Player, a: number, n: number)
	local data = DataService.get(player)
	if data == nil or Decor.baseName(economy, a, n) == "" then
		return
	end
	data.baseName = { a = a, n = n }
	DataService.changed(player, "baseName")
	PlotService.refresh(player)
end

function DecorService.Init()
	NetServer.on("DecorBuy", onBuy)
	NetServer.on("DecorPlace", onPlace)
	NetServer.on("DecorRemove", onRemove)
	NetServer.on("SetBaseName", onBaseName)
end

function DecorService.Start() end

return DecorService
