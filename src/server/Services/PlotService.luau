--!strict
-- The 8 plots (GAME_SYSTEMS §1, TECH_SPEC §6–6a). Assigns a plot when a player's profile is
-- ready (next to a friend's plot if one is free, else the lowest free one), frees it when they
-- leave, and replicates every plot: PlotSnapshot to each client once it is ready, then a
-- PlotDelta to every ready client whenever a plot's owner, layout or pads change.
--
-- The map is found only by tag and attribute: Models tagged `Plot` with a `PlotId`, their
-- `Slots` pads with a `Slot` number, and the `Zone` volume over the plot (StealService delivers
-- there). Never by position, so the map can move. Rules for assignment and the view live in
-- Shared.Plots.
--
-- Each view carries its Base Lock's end time, set by LockService through setLock, and whether
-- the owner has the new-player shield (ShieldService calls refresh when it ends).
--
-- Not yet: decorations and the base name (Phase 4), and
-- spawning the player at their plot.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Decor = require(Shared:WaitForChild("Decor"))
local Plots = require(Shared:WaitForChild("Plots"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))

type Plot = { id: number, model: Model, pads: { [number]: BasePart }, zone: BasePart? }

local PlotService = {}
PlotService.Assigned = Signal.new() -- (player, plotId)
PlotService.Released = Signal.new() -- (player, plotId): StealService cancels carries from it

local plots: { [number]: Plot } = {}
local ids: { number } = {}
local owners: { [number]: Player } = {}
local plotOf: { [Player]: number } = {}
local views: { [number]: Plots.View } = {} -- what clients were last sent; never mutated
local locks: { [number]: number } = {} -- plotId → server time its Base Lock ends (LockService)
local overcharged: { [Player]: { [number]: any }? } = {}
local synced: { [Player]: boolean } = {} -- has the snapshot, so gets deltas

function PlotService.plotOf(player: Player): number?
	return plotOf[player]
end

function PlotService.ownerOf(plotId: number): Player?
	return owners[plotId]
end

function PlotService.model(plotId: number): Model?
	local plot = plots[plotId]
	return if plot then plot.model else nil
end

function PlotService.pad(plotId: number, pad: number): BasePart?
	local plot = plots[plotId]
	return if plot then plot.pads[pad] else nil
end

function PlotService.zone(plotId: number): BasePart?
	local plot = plots[plotId]
	return if plot then plot.zone else nil
end

-- Is `position` inside the plot's Zone volume?
function PlotService.inZone(plotId: number, position: Vector3): boolean
	local plot = plots[plotId]
	local zone = if plot then plot.zone else nil
	if zone == nil then
		return false
	end
	local inside = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(inside.X) <= half.X and math.abs(inside.Y) <= half.Y and math.abs(inside.Z) <= half.Z
end

local function discover()
	for _, instance in CollectionService:GetTagged("Plot") do
		local id = instance:GetAttribute("PlotId")
		if not instance:IsA("Model") or type(id) ~= "number" or id % 1 ~= 0 or id < 1 then
			warn(`[PlotService] {instance:GetFullName()}: a Plot must be a Model with a whole PlotId ≥ 1`)
			continue
		end
		if plots[id] ~= nil then
			warn(`[PlotService] PlotId {id} is used twice; ignoring {instance:GetFullName()}`)
			continue
		end
		local pads: { [number]: BasePart } = {}
		local count = 0
		local slots = instance:FindFirstChild("Slots")
		if slots ~= nil then
			for _, child in slots:GetChildren() do
				local n = child:GetAttribute("Slot")
				if child:IsA("BasePart") and type(n) == "number" and pads[n] == nil then
					pads[n] = child
					count += 1
				end
			end
		end
		if count < economy.upgrades.slots.max then
			warn(`[PlotService] Plot {id} has {count} slot pads; it needs {economy.upgrades.slots.max}`)
		end
		local zone = instance:FindFirstChild("Zone")
		if zone == nil or not zone:IsA("BasePart") then
			warn(`[PlotService] Plot {id} has no Zone part; nothing can be delivered to it`)
			zone = nil
		end
		plots[id] = { id = id, model = instance, pads = pads, zone = zone :: BasePart? }
		table.insert(ids, id)
		views[id] = Plots.empty(id)
	end
	table.sort(ids)
	if #ids == 0 then
		warn("[PlotService] No Models tagged Plot. Build the map with tools/BuildGreybox.luau (TECH_SPEC §6a).")
	elseif #ids < economy.server.maxPlayers then
		warn(`[PlotService] {#ids} plots for {economy.server.maxPlayers} players`)
	end
end

local function buildView(plotId: number): Plots.View
	local owner = owners[plotId]
	local data = if owner ~= nil then DataService.get(owner) else nil
	if owner == nil or data == nil then
		return Plots.empty(plotId)
	end
	local name = Decor.baseName(economy, data.baseName.a, data.baseName.n)
	local layout = InventoryService.layout(owner, data)
	return Plots.view(plotId, owner.UserId, data, layout, locks[plotId], name, overcharged[owner])
end

-- Rebuilds one plot's view and sends what changed to every ready client.
local function publish(plotId: number)
	local view = buildView(plotId)
	local patch = Plots.diff(views[plotId], view)
	if patch == nil then
		return
	end
	views[plotId] = view
	for player in synced do
		NetServer.send(player, "PlotDelta", plotId, patch)
	end
end

-- LockService sets when a plot's Base Lock ends (0 to open it now); everyone sees it.
function PlotService.setLock(plotId: number, untilTime: number)
	locks[plotId] = if untilTime > 0 then untilTime else nil
	publish(plotId)
end

function PlotService.isLocked(plotId: number): boolean
	return (locks[plotId] or 0) > workspace:GetServerTimeNow()
end

-- Sends a player's plot to everyone again (ShieldService, when their shield ends).
-- TraitService's Overcharges for this player's pads; the plot view shows them.
function PlotService.setOvercharged(player: Player, over: { [number]: any }?)
	overcharged[player] = over
	PlotService.refresh(player)
end

function PlotService.refresh(player: Player)
	local id = plotOf[player]
	if id ~= nil then
		publish(id)
	end
end

local function sendSnapshot(player: Player)
	local all: { [string]: Plots.View } = {}
	for id, view in views do
		all[tostring(id)] = view
	end
	synced[player] = true
	NetServer.send(player, "PlotSnapshot", all)
end

local function assign(player: Player)
	if plotOf[player] ~= nil then
		return
	end
	-- IsFriendsWith yields, so ask about every owner before picking. Nothing yields after this.
	local others = {}
	for id, owner in owners do
		table.insert(others, { id = id, userId = owner.UserId })
	end
	local friendPlots = {}
	for _, other in others do
		local ok, isFriend = pcall(player.IsFriendsWith, player, other.userId)
		if ok and isFriend then
			table.insert(friendPlots, other.id)
		end
	end
	if player.Parent ~= Players or plotOf[player] ~= nil or not DataService.isReady(player) then
		return
	end

	local id = Plots.pick(ids, owners, friendPlots)
	if id == nil then
		warn(`[PlotService] No free plot for {player.Name}`)
		return
	end
	owners[id] = player
	plotOf[player] = id
	publish(id)
	PlotService.Assigned:Fire(player, id)
end

local function release(player: Player)
	synced[player] = nil
	local id = plotOf[player]
	if id == nil then
		return
	end
	plotOf[player] = nil
	overcharged[player] = nil
	owners[id] = nil
	locks[id] = nil
	publish(id)
	PlotService.Released:Fire(player, id)
end

function PlotService.Init()
	discover()
	DataService.ClientReady:Connect(sendSnapshot)
	DataService.PlayerReady:Connect(assign)
	DataService.PlayerLeaving:Connect(release)
	Players.PlayerRemoving:Connect(release) -- also covers a session that ended without PlayerLeaving
	InventoryService.Changed:Connect(function(player: Player)
		local id = plotOf[player]
		if id ~= nil then
			publish(id)
		end
	end)
end

return PlotService
