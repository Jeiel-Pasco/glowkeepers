--!strict
-- Base Lock (GAME_SYSTEMS §11, TECH_SPEC §7). A tap (the Lock remote) closes the owner's base
-- for 60 s: nobody else may come into its zone, and grabs in progress there cancel
-- (StealService). Then it recharges for 90 s; a Lock Charge skips the recharge. No locks at
-- night (a lock running at nightfall ends, and recharges from then), and not while carrying a
-- stolen Glowling.
-- The rules live in Shared.Lock.
--
-- The plots are open greybox floors, so the "gate" is this service: at 10 Hz, a non-owner who
-- comes into a locked zone is moved out through its nearest side. Anyone already inside when
-- the lock starts (a thief carrying out, a visitor) may stay and leave, but can't come back.
-- Clients draw the walls (LockController), which honest players bump into.
--
-- Replicates: the lock's end in the plot view (PlotService.setLock), and the owner's Player
-- attribute `LockReadyAt` (server time the recharge ends). Lock Charges are `lockCharges` in
-- the profile; buying them is the shop's job (Phase 3).
--
-- Not yet: the shield bubble (Phase 3), lock pass perks (Phase 5).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Lock = require(Shared:WaitForChild("Lock"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local CycleService = require(script.Parent:WaitForChild("CycleService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local StealService = require(script.Parent:WaitForChild("StealService"))

local TICK_SECONDS = 0.1
local PUSH_MARGIN = 2 -- studs past the zone's side

type Active = {
	owner: Player,
	untilTime: number,
	inside: { [Player]: boolean }, -- non-owners inside when it locked: they may leave
	warned: { [Player]: boolean }, -- told "locked" once per lock
}

local LockService = {}

local active: { [number]: Active } = {} -- plotId → the lock running there
local readyAt: { [Player]: number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local function toast(player: Player, text: string, kind: string?)
	if player.Parent == Players then
		NetServer.send(player, "Toast", text, kind)
	end
end

local REJECT_TEXT: { [string]: string } = {
	night = "No locks at night",
	no_plot = "You need a plot first",
	carrying = "You can't lock while carrying",
	active = "Your base is already locked",
	recharging = "The lock is recharging",
}

local function onLock(player: Player)
	local data = DataService.get(player)
	local plotId = PlotService.plotOf(player)
	if data == nil then
		return
	end
	local t = now()
	local current = if plotId ~= nil then active[plotId] else nil
	local ok, why, usesCharge = Lock.canLock({
		phase = CycleService.get().phase,
		hasPlot = plotId ~= nil,
		carrying = StealService.isCarrying(player),
		now = t,
		lockedUntil = if current ~= nil then current.untilTime else 0,
		readyAt = readyAt[player] or 0,
		charges = data.lockCharges,
	})
	if not ok or plotId == nil then
		local text = if why ~= nil then REJECT_TEXT[why] else nil
		if why == "recharging" then
			text = `The lock is ready in {math.ceil((readyAt[player] or t) - t)} s`
		end
		if text ~= nil then
			toast(player, text, "bad")
		end
		return
	end

	if usesCharge then
		data.lockCharges -= 1
		DataService.changed(player, "lockCharges")
	end
	local lockedUntil, ready = Lock.times(economy, t)
	readyAt[player] = ready
	player:SetAttribute("LockReadyAt", ready)
	local inside = {}
	for _, other in Players:GetPlayers() do
		local root = rootOf(other)
		if other ~= player and root ~= nil and PlotService.inZone(plotId, root.Position) then
			inside[other] = true
		end
	end
	active[plotId] = { owner = player, untilTime = lockedUntil, inside = inside, warned = {} }
	PlotService.setLock(plotId, lockedUntil)
	Telemetry.custom(player, "lock_used", nil, { if usesCharge then "charge" else "free" })
	Progress.add(player, "lock")
	toast(player, `Base locked for {economy.lock.activeSeconds} s`, "good")
end

local function unlock(plotId: number)
	active[plotId] = nil
	PlotService.setLock(plotId, 0)
end

-- Moves a player out of the zone through its nearest side, keeping their facing.
local function pushOut(player: Player, zone: BasePart, root: BasePart)
	local character = player.Character
	if character == nil then
		return
	end
	local offset = zone.CFrame:PointToObjectSpace(root.Position)
	local x, z = Lock.pushOut(offset.X, offset.Z, zone.Size.X / 2, zone.Size.Z / 2, PUSH_MARGIN)
	local target = zone.CFrame:PointToWorldSpace(Vector3.new(x, offset.Y, z))
	character:PivotTo(character:GetPivot() + (target - root.Position))
end

local function tick()
	local t = now()
	for plotId, lock in active do
		if t >= lock.untilTime or lock.owner.Parent ~= Players then
			unlock(plotId)
			continue
		end
		local zone = PlotService.zone(plotId)
		if zone == nil then
			continue
		end
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if player == lock.owner or root == nil then
				continue
			end
			if not PlotService.inZone(plotId, root.Position) then
				lock.inside[player] = nil -- once out, they can't come back while it's locked
			elseif not lock.inside[player] then
				pushOut(player, zone, root)
				if not lock.warned[player] then
					lock.warned[player] = true
					toast(player, `{lock.owner.DisplayName}'s base is locked`, "bad")
				end
			end
		end
	end
end

function LockService.Init()
	NetServer.on("Lock", onLock)
	CycleService.PhaseChanged:Connect(function(phase: string)
		if phase ~= "Night" then
			return
		end
		local t = now()
		for plotId, lock in active do
			unlock(plotId) -- no locks at night; the recharge starts now, not when it would have ended
			local owner = lock.owner
			local ready = t + economy.lock.rechargeSeconds
			if owner.Parent == Players and ready < (readyAt[owner] or math.huge) then
				readyAt[owner] = ready
				owner:SetAttribute("LockReadyAt", ready)
			end
		end
	end)
	PlotService.Released:Connect(function(_player: Player, plotId: number)
		active[plotId] = nil -- PlotService already cleared the view's lock
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		readyAt[player] = nil
	end)
end

function LockService.Start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= TICK_SECONDS then
			elapsed = 0
			tick()
		end
	end)
end

return LockService
