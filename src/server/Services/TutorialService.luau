--!strict
-- The new-player tutorial (GAME_SYSTEMS §22). Shared.Ftue decides which step shows from the
-- saved progress (`ftue.step`, a bitmask; `ftue.path`) and the cycle; this service finishes
-- steps from what the player does and publishes the current one as the Player attribute
-- `FtueStep` (1–10; 0 while waiting for a phase; nil when the tutorial is over).
-- TutorialController draws the banner, the guide Wisp and the arrow from it.
--
-- How each step finishes:
--   1–2  FtueAction "lure": a guaranteed Uncommon Clearing Glowling (src "tutorial"), placed
--   3    Glow reaches the price of a Common lure
--   4    a lure is bought (Progress "lure")
--   5    FtueAction "stash" next to the Wisp's Stash by day: the character carries a Common
--        (CarrySp/CarryR/CarryM, drawn like a steal; nobody can tag it, it isn't a theft and
--        doesn't end the shield). Reaching your own plot's Zone grants it.
--   6    the base is locked (Progress "lock")
--   7    shown at dusk; done when night falls
--   8    fuel fed to the fire (Progress "feed")
--   9    catch your personal Rare: a wild near the fire only you can see (ForestService.spawnFor;
--        its id is the Player attribute `FtueWild` so the guide points at it)
--   10   shown at the dawn after a night, for DAWN_SECONDS
-- Steps whose moment passed are skipped (Ftue.skipPassed). Every finished or skipped step is
-- logged with Telemetry.onboarding.
--
-- DEV/BETA: set the server-side workspace attribute DebugFtueReset to true (path from the
-- phase now) or to "day" / "late" / "night" to restart every player's tutorial on that path.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Ftue = require(Shared:WaitForChild("Ftue"))
local Economy = require(Shared:WaitForChild("Economy"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local CycleService = require(script.Parent:WaitForChild("CycleService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local RollService = require(script.Parent:WaitForChild("RollService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local ForestService = require(script.Parent:WaitForChild("ForestService"))
local Env = require(Shared:WaitForChild("Env"))

local TICK_SECONDS = 0.5
local DAWN_SECONDS = 12
local STASH_RANGE = 14 -- studs from the Wisp's Stash to grab
local COMMON, UNCOMMON, RARE = 1, 2, 3
local WILD_RING = 16 -- studs from the fire's centre to the personal wild

local TutorialService = {}

type Session = {
	sawNight: boolean,
	dawnShownAt: number?,
	carry: { sp: string, character: Model }?,
	wildId: string?, -- this player's personal wild (step 9)
}
local sessions: { [Player]: Session } = {}

local function toast(player: Player, text: string, kind: string?)
	NetServer.send(player, "Toast", text, kind)
end

local function moment(session: Session): Ftue.Moment
	local state = CycleService.get()
	return {
		phase = state.phase,
		phaseRemaining = state.phaseRemaining,
		grabsAllowed = state.grabsAllowed,
		sawNight = session.sawNight,
	}
end

local function active(player: Player): (any?, Session?)
	local data = DataService.get(player)
	local session = sessions[player]
	if data == nil or session == nil or data.ftue.done then
		return nil, nil
	end
	return data, session
end

local function current(player: Player): number?
	local data, session = active(player)
	if data == nil or session == nil then
		return nil
	end
	return Ftue.current(data.ftue.step, data.ftue.path or "day", moment(session))
end

local function log(player: Player, data: any, step: number, how: string)
	Telemetry.onboarding(player, step, Ftue.STEPS[step], { data.ftue.path or "day", how })
end

local function clearCarry(_player: Player, session: Session)
	local carry = session.carry
	session.carry = nil
	if carry ~= nil then
		for _, name in { "CarrySp", "CarryR", "CarryM" } do
			carry.character:SetAttribute(name, nil)
		end
	end
end

-- Publishes the step to show (and ends the tutorial once the path is done).
local function publish(player: Player)
	local data, session = active(player)
	if data == nil or session == nil then
		player:SetAttribute("FtueStep", nil)
		player:SetAttribute("FtueWild", nil)
		return
	end
	local path = data.ftue.path or "day"
	if Ftue.finished(data.ftue.step, path) then
		data.ftue.done = true
		DataService.changed(player, "ftue")
		clearCarry(player, session)
		player:SetAttribute("FtueStep", nil)
		player:SetAttribute("FtueWild", nil)
		return
	end
	local step = Ftue.current(data.ftue.step, path, moment(session))
	player:SetAttribute("FtueStep", step or 0)
	player:SetAttribute("FtueWild", if step == 9 then session.wildId else nil)
	if step ~= 10 then
		session.dawnShownAt = nil
	end
end

-- Finishes `step` if it's the one showing (or `anyTime`: whenever it isn't done yet).
local function finish(player: Player, step: number, anyTime: boolean?)
	local data, session = active(player)
	if data == nil or session == nil or Ftue.isDone(data.ftue.step, step) then
		return
	end
	if not anyTime and current(player) ~= step then
		return
	end
	data.ftue.step = Ftue.mark(data.ftue.step, step)
	DataService.changed(player, "ftue")
	log(player, data, step, "done")
	publish(player)
end

local function stashPart(): BasePart?
	local map = workspace:FindFirstChild("Map")
	local stations = if map ~= nil then map:FindFirstChild("Stations") else nil
	for _, station in if stations ~= nil then stations:GetChildren() else {} do
		if station:GetAttribute("Kind") == "WispStash" then
			local base = station:FindFirstChild("Base")
			if base ~= nil and base:IsA("BasePart") then
				return base
			end
		end
	end
	return nil
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local function openLure(player: Player)
	local data = active(player)
	if data == nil or Ftue.isDone(data.ftue.step, 2) or current(player) ~= 1 then
		return
	end
	local record = RollService.tutorial(player, UNCOMMON)
	if record == nil then
		toast(player, "Your storage is full", "bad")
		return
	end
	InventoryService.placeBest(player)
	finish(player, 1)
	finish(player, 2)
end

local function grabStash(player: Player)
	local data, session = active(player)
	local root = rootOf(player)
	if data == nil or session == nil or root == nil or session.carry ~= nil or current(player) ~= 5 then
		return
	end
	local stash = stashPart()
	if stash == nil or (stash.Position - root.Position).Magnitude > STASH_RANGE then
		toast(player, "Get closer to the Wisp's Stash", "bad")
		return
	end
	if PlotService.plotOf(player) == nil then
		return
	end
	local character = player.Character :: Model
	local sp = RollService.pick("Clearing", COMMON)
	session.carry = { sp = sp, character = character }
	character:SetAttribute("CarrySp", sp)
	character:SetAttribute("CarryR", COMMON)
	character:SetAttribute("CarryM", 0)
	toast(player, "Got one! Run it home to your base", "good")
end

-- Delivers or drops the stash carry.
local function stepCarry(player: Player, session: Session)
	local carry = session.carry
	if carry == nil then
		return
	end
	local root = rootOf(player)
	local plotId = PlotService.plotOf(player)
	if root == nil or player.Character ~= carry.character or not CycleService.get().carriesAllowed then
		clearCarry(player, session)
		toast(player, "The wisp slipped away. Try again by day", "bad")
		return
	end
	if plotId ~= nil and PlotService.inZone(plotId, root.Position) then
		clearCarry(player, session)
		if RollService.tutorial(player, COMMON, carry.sp) ~= nil then
			InventoryService.placeBest(player)
			finish(player, 5)
		else
			toast(player, "Your storage is full", "bad")
		end
	end
end

-- A spot on open ground near the fire for the personal wild.
local function nearFire(): Vector3?
	local map = workspace:FindFirstChild("Map")
	local fire = if map ~= nil then map:FindFirstChild("Campfire") else nil
	if fire == nil or not fire:IsA("Model") then
		return nil
	end
	local centre = fire:GetPivot().Position
	local angle = math.random() * math.pi * 2
	local at = centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * WILD_RING
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character ~= nil then
			table.insert(exclude, p.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(at + Vector3.new(0, 40, 0), Vector3.new(0, -80, 0), params)
	return if hit ~= nil then hit.Position + Vector3.new(0, 1.5, 0) else at
end

-- Step 9: keeps this player's personal Rare out there.
local function keepWild(player: Player, session: Session)
	if session.wildId ~= nil and ForestService.exists(session.wildId) then
		return
	end
	local at = nearFire()
	local id = if at ~= nil then ForestService.spawnFor(player, at, RollService.pick("Clearing", RARE), RARE) else nil
	session.wildId = id
	player:SetAttribute("FtueWild", id)
end

local function tick(now: number)
	for player, session in sessions do
		local data = active(player)
		if data == nil then
			continue
		end
		local m = moment(session)
		local path = data.ftue.path or "day"
		local mask, skipped = Ftue.skipPassed(data.ftue.step, path, m)
		if #skipped > 0 then
			data.ftue.step = mask
			DataService.changed(player, "ftue")
			for _, step in skipped do
				log(player, data, step, "skipped")
			end
		end
		stepCarry(player, session)
		local step = Ftue.current(data.ftue.step, path, m)
		if step == 9 then
			keepWild(player, session)
		end
		if step == 3 and data.glow >= Economy.lureCost(economy, 1) then
			finish(player, 3)
		elseif step == 10 then
			session.dawnShownAt = session.dawnShownAt or now
			if now - (session.dawnShownAt :: number) >= DAWN_SECONDS then
				finish(player, 10)
			end
		end
		if player:GetAttribute("FtueStep") ~= (current(player) or 0) then
			publish(player)
		end
	end
end

local function onReady(player: Player, data: any)
	if data.ftue.done then
		return
	end
	local state = CycleService.get()
	sessions[player] = { sawNight = state.phase == "Night" }
	if data.ftue.path == nil then
		data.ftue.path = Ftue.pathFor(state.phase, state.phaseRemaining)
		DataService.changed(player, "ftue")
	end
	publish(player)
end

function TutorialService.Init()
	DataService.PlayerReady:Connect(onReady)
	Players.PlayerRemoving:Connect(function(player: Player)
		local session = sessions[player]
		if session ~= nil then
			clearCarry(player, session)
		end
		sessions[player] = nil
	end)
	NetServer.on("FtueAction", function(player: Player, action: string)
		if action == "lure" then
			openLure(player)
		elseif action == "stash" then
			grabStash(player)
		end
	end)
	Progress.Event:Connect(function(player: Player, event: string)
		if event == "lure" then
			finish(player, 4)
		elseif event == "lock" then
			finish(player, 6)
		elseif event == "feed" then
			finish(player, 8)
		end
	end)
	ForestService.Caught:Connect(function(player: Player, wildId: string)
		local session = sessions[player]
		if session ~= nil and session.wildId == wildId then
			session.wildId = nil
			finish(player, 9)
		end
	end)
	if Env.get().name ~= "PROD" then
		workspace:GetAttributeChangedSignal("DebugFtueReset"):Connect(function()
			local value = workspace:GetAttribute("DebugFtueReset")
			if value == nil or value == false then
				return
			end
			workspace:SetAttribute("DebugFtueReset", nil)
			local state = CycleService.get()
			for _, player in Players:GetPlayers() do
				local data = DataService.get(player)
				if data ~= nil then
					local old = sessions[player]
					if old ~= nil then
						clearCarry(player, old)
					end
					sessions[player] = nil
					data.ftue = {
						step = 0,
						done = false,
						path = if type(value) == "string"
							then value
							else Ftue.pathFor(state.phase, state.phaseRemaining),
					}
					DataService.changed(player, "ftue")
					onReady(player, data)
				end
			end
		end)
	end
	CycleService.PhaseChanged:Connect(function(phase: string)
		for player, session in sessions do
			if phase == "Night" then
				session.sawNight = true
				finish(player, 7, true) -- the warning was shown at dusk (or skipped)
			end
			publish(player)
		end
	end)
end

function TutorialService.Start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= TICK_SECONDS then
			elapsed = 0
			tick(workspace:GetServerTimeNow())
		end
	end)
end

-- The step showing for `player`, or nil.
TutorialService.current = current

return TutorialService
