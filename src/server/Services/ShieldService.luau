--!strict
-- New-player shield (GAME_SYSTEMS §11, D2). Every profile starts shielded (Schema default).
-- Nobody can steal from a shielded player (StealService reads `data.shield.active`), and the
-- plot view shows it so clients draw the bubble. The shield ends after 45 minutes of play
-- (saved, so it survives a rejoin), or when its owner says yes to stealing: the client asks
-- "This ends your protection. Steal anyway?" and sends DropShield. The rules live in
-- Shared.Shield.
--
-- Replicates: `shield` in PlayerState and the plot view, and the Player attributes `Shielded`
-- (true, or nil) and `ShieldEndsAt` (server time it ends if they stay online).
--
-- DEV/BETA: set the server-side workspace attribute DebugShieldLeft to a number of seconds to
-- leave that much play time on every shielded player, or to -1 to shield everyone again.
--
-- The first rebirth ends it (RebirthService calls drop with "rebirth").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Env = require(Shared:WaitForChild("Env"))
local Shield = require(Shared:WaitForChild("Shield"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))

local TICK_SECONDS = 1

local ENDED_TEXT: { [string]: string } = {
	time = "Your new-player protection has ended",
	steal = "Protection dropped. Your base can be robbed now",
	rebirth = "Your new-player protection has ended",
}

local ShieldService = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function publish(player: Player)
	local data = DataService.get(player)
	local active = data ~= nil and data.shield.active == true
	player:SetAttribute("Shielded", if active then true else nil)
	player:SetAttribute("ShieldEndsAt", if active then Shield.endsAt(economy, data.shield.playSeconds, now()) else nil)
end

function ShieldService.isShielded(player: Player): boolean
	local data = DataService.get(player)
	return data ~= nil and data.shield.active == true
end

-- Ends a player's shield. `reason` is "time", "steal" or "rebirth".
function ShieldService.drop(player: Player, reason: string)
	local data = DataService.get(player)
	if data == nil or not data.shield.active then
		return
	end
	data.shield.active = false
	DataService.changed(player, "shield")
	publish(player)
	PlotService.refresh(player)
	Telemetry.custom(player, "shield_ended", math.floor(data.shield.playSeconds), { reason })
	if player.Parent == Players then
		NetServer.send(player, "Toast", ENDED_TEXT[reason] or ENDED_TEXT.time, nil)
	end
end

local function tick(dt: number)
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data ~= nil and data.shield.active then
			local total, ended = Shield.accrue(economy, data.shield.playSeconds, dt)
			data.shield.playSeconds = total
			if ended then
				ShieldService.drop(player, "time")
			end
		end
	end
end

local function debugShieldLeft()
	local seconds = workspace:GetAttribute("DebugShieldLeft")
	if type(seconds) ~= "number" then
		return
	end
	workspace:SetAttribute("DebugShieldLeft", nil) -- so the same value works again
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data ~= nil and seconds < 0 then
			data.shield.active = true
			data.shield.playSeconds = 0
		elseif data ~= nil and data.shield.active then
			data.shield.playSeconds = math.max(0, economy.shield.maxPlaySeconds - seconds)
		end
		if data ~= nil then
			DataService.changed(player, "shield")
			publish(player)
			PlotService.refresh(player)
		end
	end
end

function ShieldService.Init()
	DataService.PlayerReady:Connect(publish)
	NetServer.on("DropShield", function(player: Player)
		ShieldService.drop(player, "steal")
	end)
	if Env.get().name ~= "PROD" then
		workspace:GetAttributeChangedSignal("DebugShieldLeft"):Connect(debugShieldLeft)
	end
end

function ShieldService.Start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= TICK_SECONDS then
			tick(elapsed)
			elapsed = 0
		end
	end)
end

return ShieldService
