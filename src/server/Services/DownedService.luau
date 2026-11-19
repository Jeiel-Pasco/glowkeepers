--!strict
-- Downed, bleed-out, revive and wisps (GAME_SYSTEMS §14, TECH_SPEC §7–8).
--
-- DownedService.down(player) is how a player goes down at night (the Stalker calls it). A
-- downed player is frozen (the server anchors their root part) and can't act; they bleed out
-- after 30 s. A teammate holds Revive for 3 s within 8 studs (ReviveStart / ReviveCancel,
-- timed here), which pauses the bleed-out. A revived player is safe from the Stalker for 3 s.
-- Bleeding out makes a spectator wisp until dawn. Dawn brings everyone back.
-- The rules live in Shared.Revive.
--
-- Replicates on the character: `Life` ("downed" | "wisp"; nil = alive), `BleedUntil` (server
-- time; nil while a revive holds it), `ReviveUntil` on the reviver (for the cosmetic bar) and
-- `SafeUntil`. CampfireService counts only living players and pays revive Embers at dawn.
--
-- DEV/BETA: at night, set the server-side workspace attribute DebugDown to a userId (or 0 for
-- everyone) to down that player.
--
-- Not yet: the Stalker (GS) that calls down() and reads isSafe(), losing unused catches on
-- bleed-out (ForestService), revive pass XP (Phase 3) and the weekly revive board (Phase 4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Env = require(Shared:WaitForChild("Env"))
local Revive = require(Shared:WaitForChild("Revive"))
local Companion = require(Shared:WaitForChild("Companion"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local CycleService = require(script.Parent:WaitForChild("CycleService"))

local speciesById: { [string]: any } = {}
for _, entry in (require(Shared:WaitForChild("Config"):WaitForChild("species")) :: any).species do
	speciesById[entry.id] = entry
end

-- The player's Night Companion species (D23), or nil.
local function companionOf(player: Player): any
	local data = DataService.get(player)
	return if data ~= nil then Companion.species(data, speciesById) else nil
end

local TICK_SECONDS = 0.1
local RANGE_SLACK = 2 -- studs past revive.range before a hold in progress breaks (latency)

type Hold = { reviver: Player, target: Player, character: Model, ends: number }

local DownedService = {}
DownedService.Downed = Signal.new() -- (player)
DownedService.Revived = Signal.new() -- (player, by: Player)
DownedService.BledOut = Signal.new() -- (player): a wisp until dawn

local life: { [Player]: Revive.Life } = {} -- missing = alive
local bleeds: { [Player]: Revive.Bleed } = {}
local holds: { [Player]: Hold } = {} -- by reviver
local holdOn: { [Player]: Hold } = {} -- by target
local revivesTonight: { [Player]: number } = {}
local safeUntil: { [Player]: number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function isNight(): boolean
	return CycleService.get().phase == "Night"
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

function DownedService.life(player: Player): Revive.Life
	return life[player] or "alive"
end

-- Alive, not downed and not a wisp: drains the fire and may act.
function DownedService.isLiving(player: Player): boolean
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return life[player] == nil and humanoid ~= nil and humanoid.Health > 0
end

-- Revives this player made tonight (the dawn Embers count up to embers.reviveCap).
function DownedService.revives(player: Player): number
	return revivesTonight[player] or 0
end

-- Just revived: the Stalker leaves them alone for revive.safeSeconds.
function DownedService.isSafe(player: Player): boolean
	return (safeUntil[player] or 0) > now()
end

-- Writes the replicated attributes and the freeze from the server state.
local function show(player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	local state = life[player]
	local bleed = bleeds[player]
	character:SetAttribute("Life", state)
	character:SetAttribute("BleedUntil", if bleed ~= nil and bleed.paused == nil then bleed.ends else nil)
	local hold = holds[player]
	character:SetAttribute("ReviveUntil", if hold ~= nil then hold.ends else nil)
	local safe = safeUntil[player]
	character:SetAttribute("SafeUntil", if safe ~= nil and safe > now() then safe else nil)
	local root = rootOf(player)
	if root ~= nil then
		local frozen = state == "downed"
		if root.Anchored ~= frozen then
			root.Anchored = frozen
			if not frozen then
				pcall(root.SetNetworkOwner, root, player)
			end
		end
	end
end

-- Ends a revive hold that didn't finish; the target's bleed-out carries on.
local function letGo(hold: Hold)
	if holds[hold.reviver] ~= hold then
		return
	end
	holds[hold.reviver] = nil
	holdOn[hold.target] = nil
	local bleed = bleeds[hold.target]
	if bleed ~= nil then
		Revive.resume(bleed, now())
	end
	show(hold.reviver)
	show(hold.target)
end

local function setAlive(player: Player)
	local hold = holdOn[player]
	if hold ~= nil then
		letGo(hold)
	end
	life[player] = nil
	bleeds[player] = nil
	show(player)
end

-- Downs a living player at night. Returns false if they can't go down right now.
function DownedService.down(player: Player): boolean
	if not isNight() or not DownedService.isLiving(player) or DownedService.isSafe(player) then
		return false
	end
	local own = holds[player]
	if own ~= nil then
		letGo(own)
	end
	life[player] = "downed"
	bleeds[player] = Revive.bleed(economy, now())
	show(player)
	Telemetry.custom(player, "downed")
	DownedService.Downed:Fire(player)
	return true
end

local function bleedOut(player: Player)
	local hold = holdOn[player]
	if hold ~= nil then
		letGo(hold)
	end
	life[player] = "wisp"
	bleeds[player] = nil
	show(player)
	toast(player, "You faded away. You'll be back at dawn", "bad")
	DownedService.BledOut:Fire(player)
end

local function revive(hold: Hold)
	local reviver, target = hold.reviver, hold.target
	holds[reviver] = nil
	holdOn[target] = nil
	safeUntil[target] = now() + economy.revive.safeSeconds
	setAlive(target)
	show(reviver)

	local count = (revivesTonight[reviver] or 0) + 1
	revivesTonight[reviver] = count
	local data = DataService.get(reviver)
	if data ~= nil then
		data.stats.revives += 1
		Progress.add(reviver, "revive")
		DataService.changed(reviver, "stats")
	end
	Telemetry.custom(reviver, "revive")
	local reward = if count <= economy.embers.reviveCap
		then ` +{economy.embers.perRevive} Embers at dawn if the fire lasts`
		else ""
	toast(reviver, `You revived {target.DisplayName}!{reward}`, "good")
	toast(target, `{reviver.DisplayName} saved you!`, "good")
	if target.Parent == Players then
		NetServer.send(target, "Revived", reviver.UserId)
	end
	DownedService.Revived:Fire(target, reviver)
end

local REJECT_TEXT: { [string]: string } = {
	busy = "You're already reviving someone",
	taken = "Someone's already reviving them",
	too_far = "Get closer",
}

local function reviveStart(reviver: Player, userId: number)
	local target = Players:GetPlayerByUserId(userId)
	local mine, theirs = rootOf(reviver), if target ~= nil then rootOf(target) else nil
	local check: Revive.Check = {
		night = isNight(),
		self = target == reviver,
		reviver = if DownedService.isLiving(reviver) then "alive" else DownedService.life(reviver),
		target = if target ~= nil then DownedService.life(target) else "alive",
		busy = holds[reviver] ~= nil,
		taken = target ~= nil and holdOn[target] ~= nil,
		distance = if mine ~= nil and theirs ~= nil then (mine.Position - theirs.Position).Magnitude else math.huge,
	}
	local ok, why = Revive.canStart(economy, check)
	local character = reviver.Character
	if not ok or target == nil or character == nil then
		local text = if why ~= nil then REJECT_TEXT[why] else nil
		if text ~= nil then
			toast(reviver, text, "bad")
		end
		return
	end
	local hold: Hold = {
		reviver = reviver,
		target = target,
		character = character,
		ends = now() + Companion.reviveHold(economy, companionOf(reviver), economy.revive.holdSeconds),
	}
	holds[reviver] = hold
	holdOn[target] = hold
	Revive.pause(bleeds[target], now())
	show(reviver)
	show(target)
end

local function tick()
	local t = now()
	for reviver, hold in holds do
		local mine, theirs = rootOf(reviver), rootOf(hold.target)
		if
			not DownedService.isLiving(reviver)
			or reviver.Character ~= hold.character
			or life[hold.target] ~= "downed"
			or mine == nil
			or theirs == nil
			or (mine.Position - theirs.Position).Magnitude > economy.revive.range + RANGE_SLACK
		then
			letGo(hold)
		elseif t >= hold.ends then
			revive(hold)
		end
	end
	for player, bleed in bleeds do
		if Revive.bledOut(bleed, t) then
			bleedOut(player)
		end
	end
	for player, untilTime in safeUntil do
		if untilTime <= t then
			safeUntil[player] = nil
			show(player)
		end
	end
end

-- Dawn: every downed player and wisp is back.
local function dawn()
	for _, hold in holds do
		letGo(hold)
	end
	for player in life do
		setAlive(player)
	end
	table.clear(safeUntil)
end

local function forget(player: Player)
	local own = holds[player]
	if own ~= nil then
		letGo(own)
	end
	local onThem = holdOn[player]
	if onThem ~= nil then
		letGo(onThem)
	end
	life[player] = nil
	bleeds[player] = nil
	revivesTonight[player] = nil
	safeUntil[player] = nil
end

function DownedService.Init()
	NetServer.on("ReviveStart", reviveStart)
	NetServer.on("ReviveCancel", function(reviver: Player)
		local hold = holds[reviver]
		if hold ~= nil then
			letGo(hold)
		end
	end)

	CycleService.PhaseChanged:Connect(function(phase: string)
		if phase == "Night" then
			table.clear(revivesTonight) -- dawn reads tonight's count before this clears it
		elseif phase == "Day" then
			dawn()
		end
	end)

	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			-- A new character mid-night: a downed player who reset is a wisp until dawn.
			if life[player] == "downed" then
				bleedOut(player)
			end
			task.defer(show, player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(forget)

	if Env.get().name ~= "PROD" then
		workspace:GetAttributeChangedSignal("DebugDown"):Connect(function()
			local userId = workspace:GetAttribute("DebugDown")
			if type(userId) ~= "number" then
				return
			end
			workspace:SetAttribute("DebugDown", nil) -- so the same value works again
			for _, player in Players:GetPlayers() do
				if userId == 0 or player.UserId == userId then
					DownedService.down(player)
				end
			end
		end)
	end
end

function DownedService.Start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= TICK_SECONDS then
			elapsed = 0
			tick()
		end
	end)
end

return DownedService
