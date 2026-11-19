--!strict
-- Stealing (GAME_SYSTEMS §10, TECH_SPEC §8): grab, carry, tag-back, deliver.
--
-- GrabStart begins a hold that the server times itself (1–3 s by rarity). Letting go
-- (GrabCancel), walking out of range, a tag or the dusk warning cancels it. A finished hold
-- becomes a carry: the Glowling leaves the victim's pad, so it stops earning and the pad
-- shows empty, but its record stays in the victim's profile, held, until the thief's root
-- part is inside their own plot's Zone. Then GlowlingService.transfer moves it to the thief's
-- storage (src "steal"; Place best shows it, §7). Anything else snaps it home: back onto its
-- pad if that pad is still free, else into the victim's storage. A record is never in two
-- profiles, and a crash mid-carry leaves it with the victim.
--
-- Replicates on the thief's character: GrabUntil (server time the hold ends, for the cosmetic
-- ring), CarrySp/CarryR/CarryM (the Marked glow everyone sees), CarryFrom (the victim's userId,
-- for their through-walls Highlight); and RunSpeed on thief and owner (MovementController).
-- The grab rules and the carry speed check live in Shared.Steal.
--
-- A locked base (PlotService.isLocked) can't be grabbed from, and a grab in progress there is
-- cancelled; a carry that already left keeps going. A shielded victim can't be robbed, and a
-- shielded thief must drop their own shield first (ShieldService, after a client confirm).
--
-- Not yet:
-- crew-mates as taggers (Phase 4), the owner's alarm
-- arrow (GS), the Audit store for Legendary-or-better steals (Phase 5).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Economy = require(Shared:WaitForChild("Economy"))
local Inventory = require(Shared:WaitForChild("Inventory"))
local Steal = require(Shared:WaitForChild("Steal"))
local Traits = require(Shared:WaitForChild("Traits"))
local economy = require(Config:WaitForChild("economy")) :: any
local speciesConfig = require(Config:WaitForChild("species")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local CycleService = require(script.Parent:WaitForChild("CycleService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local GlowlingService = require(script.Parent:WaitForChild("GlowlingService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local LiveConfigService = require(script.Parent:WaitForChild("LiveConfigService"))
local GamePassService = require(script.Parent:WaitForChild("GamePassService"))

local TICK_SECONDS = 0.1 -- 10 Hz: tags, delivery and the carry check (TECH_SPEC §8)
local GRAB_SLACK = 2 -- studs past grabRange before a hold in progress cancels (latency)
local CARRY_KEYS = { "GrabUntil", "CarrySp", "CarryR", "CarryM", "CarryFrom" }

type Job = {
	thief: Player,
	victim: Player,
	character: Model, -- the thief's character when the grab began; a respawn ends the job
	plotId: number,
	pad: number,
	id: string,
	record: any,
	stage: "grab" | "carry",
	ends: number, -- grab: the hold ends; carry: the timeout
	samples: { Steal.Sample },
}

local StealService = {}

local jobs: { [Player]: Job } = {} -- by thief: one grab or carry at a time
local safeUntil: { [number]: number } = {} -- victim userId → end of their cooldown
local stolen: { [string]: { index: number, count: number } } = {} -- "thief:victim" → steals this day
local boostUntil: { [Player]: number } = {} -- the owner's chase boost
local friends: { [Player]: { [Player]: boolean } } = {}

local speciesNames: { [string]: string } = {}
local speciesById: { [string]: any } = {}
for _, species in speciesConfig.species do
	speciesNames[species.id] = species.name
	speciesById[species.id] = species
end

-- Extra grab seconds on the victim's pad from their Guardians (GAME_SYSTEMS §31). Thieves only
-- grab display pads.
local function guardBonus(victimData: any, pad: number): number
	local placed: Traits.Placed = {}
	for at, id in Inventory.placedPads(victimData) do
		local record = victimData.glowlings[id]
		if record ~= nil then
			placed[at] = record.sp
		end
	end
	return Traits.grabBonus(economy, speciesById, placed, pad, true)
end

local function nameOf(record: any): string
	local rarity = economy.rarities[record.r]
	return `{if rarity then rarity.id else "?"} {speciesNames[record.sp] or record.sp}`
end

local function rarityId(record: any): string
	local rarity = economy.rarities[record.r]
	return if rarity then rarity.id else "?"
end

local function toast(player: Player, text: string, kind: string?)
	if player.Parent == Players then
		NetServer.send(player, "Toast", text, kind)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function isFriend(a: Player, b: Player): boolean
	local list = friends[a]
	return list ~= nil and list[b] == true
end

-- IsFriendsWith yields, so friendships are learned once per join, both ways.
local function learnFriends(player: Player)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local ok, yes = pcall(player.IsFriendsWith, player, other.UserId)
			if ok and yes and player.Parent == Players and other.Parent == Players then
				friends[player] = friends[player] or {}
				friends[player][other] = true
				friends[other] = friends[other] or {}
				friends[other][player] = true
			end
		end
	end
end

local function stolenToday(thief: Player, victim: Player, index: number): number
	local entry = stolen[`{thief.UserId}:{victim.UserId}`]
	return if entry ~= nil and entry.index == index then entry.count else 0
end

local function carrying(player: Player): Job?
	local job = jobs[player]
	return if job ~= nil and job.stage == "carry" then job else nil
end

-- Carrying a stolen Glowling home (LockService: no locking your base while carrying).
function StealService.isCarrying(player: Player): boolean
	return carrying(player) ~= nil
end

-- Run speed from Boots, ×0.85 while carrying, ×1.2 during a chase boost.
local function speedOf(player: Player, now: number): number
	local data = DataService.get(player)
	local swift = GamePassService.owns(player, "swiftBoots")
	local speed = Economy.runSpeed(economy, if data then data.up.boots else 0, swift, carrying(player) ~= nil)
	if (boostUntil[player] or 0) > now then
		speed *= economy.steal.chaseBoostMult
	end
	return speed
end

-- Sets the character's RunSpeed (nil = the default movement.run). UpgradeService calls it
-- through StealService.refreshSpeed after Boots are bought.
local function updateSpeed(player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	local now = workspace:GetServerTimeNow()
	local data = DataService.get(player)
	local boots = if data ~= nil then data.up.boots else 0
	local changed = boots > 0
		or GamePassService.owns(player, "swiftBoots")
		or carrying(player) ~= nil
		or (boostUntil[player] or 0) > now
	character:SetAttribute("RunSpeed", if changed then speedOf(player, now) else nil)
end

StealService.refreshSpeed = updateSpeed

local function clearCharacter(job: Job)
	for _, key in CARRY_KEYS do
		job.character:SetAttribute(key, nil)
	end
end

-- What each side hears when a job ends early, by stage and reason.
local function endText(job: Job, why: string, tagger: Player?): (string?, string?)
	local name = nameOf(job.record)
	if job.stage == "grab" then
		if why == "tagged" then
			return `{if tagger then tagger.DisplayName else "They"} stopped your grab!`, "Grab stopped!"
		elseif why == "dusk" then
			return "Too late: grabs stop at dusk", nil
		elseif why == "locked" then
			return "The base locked: grab cancelled", nil
		elseif why == "moved" then
			return "Too far: grab cancelled", nil
		elseif why == "owner_left" then
			return "Owner left: steal cancelled", nil
		elseif why == "gone" then
			return "It got away", nil
		end
		return nil, if why == "released" then nil else `Your {name} is safe`
	end
	local home = `Your {name} came home`
	if why == "tagged" then
		local who = if tagger == nil or tagger == job.victim then "You" else tagger.DisplayName
		return `Tagged! The {name} ran home`, `{who} got your {name} back!`
	elseif why == "timeout" then
		return `Too slow: the {name} ran home`, home
	elseif why == "night" then
		return `Night fell: the {name} ran home`, home
	elseif why == "no_room" then
		return `Your storage is full: the {name} ran home`, home
	elseif why == "owner_left" then
		return "Owner left: steal cancelled", nil
	end
	return `The {name} ran home`, home -- the thief died, left or failed the carry check
end

-- Ends a grab or carry without a theft. A carried Glowling goes back to its pad if that pad
-- is still free, else it stays in the victim's storage, where it has been all along.
local function snapHome(job: Job, why: string, tagger: Player?)
	if jobs[job.thief] ~= job then
		return
	end
	jobs[job.thief] = nil
	clearCharacter(job)
	InventoryService.hold(job.victim, job.id, false)
	if job.stage == "grab" then
		PlotService.setFrozen(job.plotId, job.pad, nil) -- it wanders again
	end
	if job.stage == "carry" then
		local data = DataService.get(job.victim)
		local key = tostring(job.pad)
		if data ~= nil and data.glowlings[job.id] ~= nil and data.display[key] == nil and data.vault[key] == nil then
			InventoryService.place(job.victim, job.id, job.pad)
		end
	end
	updateSpeed(job.thief)
	local thiefText, victimText = endText(job, why, tagger)
	if thiefText ~= nil then
		toast(job.thief, thiefText, "bad")
	end
	if victimText ~= nil then
		toast(job.victim, victimText, "good")
	end
	if job.stage == "carry" and (why == "tagged" or why == "timeout") then
		Telemetry.custom(job.thief, `steal_{why}`, nil, { rarityId(job.record) })
	end
end

-- The owner, or a Roblox friend of the owner, within tagRadius of the thief.
local function tagger(job: Job, root: BasePart): Player?
	for _, player in Players:GetPlayers() do
		if player ~= job.thief and (player == job.victim or isFriend(job.victim, player)) then
			local other = rootOf(player)
			if other ~= nil and (other.Position - root.Position).Magnitude <= economy.steal.tagRadius then
				return player
			end
		end
	end
	return nil
end

-- Reach from the thief to the Glowling itself, wherever it has wandered (Shared.Roam).
local function padDistance(plotId: number, pad: number, root: BasePart?): number
	local spot = PlotService.spot(plotId, pad)
	if spot == nil or root == nil then
		return math.huge
	end
	local offset = spot - root.Position
	return Steal.reach(economy, offset.X, offset.Y, offset.Z)
end

local REJECT_TEXT: { [string]: string } = {
	not_day = "You can only steal by day",
	no_plot = "You need a plot first",
	storage_full = "Your storage is full",
	vault = "Vault slots can't be stolen",
	busy = "You're already stealing one",
	taken = "Someone's already grabbing that one",
	locked = "That base is locked",
	shielded = "That player is protected",
	thief_shielded = "Drop your protection to steal",
	too_far = "Get closer",
}

local function grabStart(thief: Player, plotId: number, pad: number)
	local thiefData = DataService.get(thief)
	if thiefData == nil then
		return
	elseif LiveConfigService.killed("stealing") then
		NetServer.send(thief, "Toast", "Stealing is paused right now", "bad")
		return
	end
	local victim = PlotService.ownerOf(plotId)
	local victimData = if victim ~= nil then DataService.get(victim) else nil
	local id = if victimData ~= nil then victimData.display[tostring(pad)] else nil
	local now = workspace:GetServerTimeNow()
	local state = CycleService.get()
	local root = rootOf(thief)
	local check: Steal.Check = {
		phase = state.phase,
		thief = thief.UserId,
		owner = if victim ~= nil and victimData ~= nil then victim.UserId else 0,
		thiefHasPlot = PlotService.plotOf(thief) ~= nil,
		thiefHasRoom = GlowlingService.hasRoom(thief),
		padKind = if victim ~= nil and victimData ~= nil
			then Inventory.padKind(InventoryService.layout(victim, victimData), pad)
			else nil,
		hasGlowling = id ~= nil,
		busy = jobs[thief] ~= nil,
		padTaken = victim ~= nil and id ~= nil and InventoryService.isHeld(victim, id),
		locked = PlotService.isLocked(plotId),
		shielded = victimData ~= nil and victimData.shield.active == true,
		thiefShielded = thiefData.shield.active == true,
		now = now,
		victimSafeUntil = if victim ~= nil then safeUntil[victim.UserId] or 0 else 0,
		stolenToday = if victim ~= nil then stolenToday(thief, victim, state.index) else 0,
		distance = padDistance(plotId, pad, root),
	}
	local ok, why = Steal.canGrab(economy, check)
	if not ok or victim == nil or victimData == nil or id == nil or root == nil then
		local text = if why ~= nil then REJECT_TEXT[why] else nil
		if why == "cooldown" and victim ~= nil then
			text = `{victim.DisplayName} was just robbed. Try again in {math.ceil(check.victimSafeUntil - now)} s`
		elseif why == "daily_limit" and victim ~= nil then
			text = `You already stole from {victim.DisplayName} today`
		end
		if text ~= nil then
			toast(thief, text, "bad")
		end
		return
	end

	local record = victimData.glowlings[id]
	local character = thief.Character :: Model -- rootOf found the root in it
	local job: Job = {
		thief = thief,
		victim = victim,
		character = character,
		plotId = plotId,
		pad = pad,
		id = id,
		record = record,
		stage = "grab",
		ends = now + Steal.holdSeconds(economy, record.r) + guardBonus(victimData, pad),
		samples = {},
	}
	jobs[thief] = job
	PlotService.setFrozen(plotId, pad, now) -- it stands still while being grabbed
	InventoryService.hold(victim, id, true)
	character:SetAttribute("GrabUntil", job.ends)
	toast(victim, `{thief.DisplayName} is stealing your {nameOf(record)}!`, "alarm")
end

local function beginCarry(job: Job, now: number)
	local data = DataService.get(job.victim)
	if data == nil or data.display[tostring(job.pad)] ~= job.id then
		snapHome(job, "gone") -- the pad turned into a vault pad mid-grab
		return
	end
	PlotService.setFrozen(job.plotId, job.pad, nil)
	Inventory.forget(data, job.id)
	InventoryService.notify(job.victim)
	job.stage = "carry"
	job.ends = now + economy.steal.carryTimeout
	local character = job.character
	character:SetAttribute("GrabUntil", nil)
	character:SetAttribute("CarrySp", job.record.sp)
	character:SetAttribute("CarryR", job.record.r)
	character:SetAttribute("CarryM", job.record.m)
	character:SetAttribute("CarryFrom", job.victim.UserId)
	boostUntil[job.victim] = now + economy.steal.chaseBoostSeconds
	updateSpeed(job.thief)
	updateSpeed(job.victim)
	toast(job.thief, "Got it! Run it back to your base", "good")
	toast(job.victim, `{job.thief.DisplayName} took your {nameOf(job.record)}! Chase them!`, "alarm")
end

local function deliver(job: Job, now: number)
	local thief, victim = job.thief, job.victim
	local moved = GlowlingService.transfer(victim, thief, job.id, "steal")
	if moved == nil then
		snapHome(job, "no_room")
		return
	end
	jobs[thief] = nil
	clearCharacter(job)
	InventoryService.hold(victim, job.id, false)
	updateSpeed(thief)

	local thiefData, victimData = DataService.get(thief), DataService.get(victim)
	if thiefData ~= nil then
		thiefData.stats.steals += 1
		Progress.add(thief, "steal")
		DataService.changed(thief, "stats")
	end
	if victimData ~= nil then
		victimData.stats.stolenFrom += 1
		DataService.changed(victim, "stats")
		victim:SetAttribute("LostGlowlingAt", now) -- no store prompts right after a loss (§23)
	end
	safeUntil[victim.UserId] = now + economy.steal.victimCooldown
	local index = CycleService.get().index
	stolen[`{thief.UserId}:{victim.UserId}`] = { index = index, count = stolenToday(thief, victim, index) + 1 }
	-- Both profiles changed at once: save both now, so a crash can't leave the record in two.
	DataService.save(thief)
	DataService.save(victim)

	local name = nameOf(moved)
	toast(thief, `Stolen: {name}! Place best to show it`, "good")
	toast(victim, `{thief.DisplayName} stole your {name}`, "bad")
	Telemetry.custom(thief, "steal_success", nil, { rarityId(moved) })
end

local function tick()
	local now = workspace:GetServerTimeNow()
	local state = CycleService.get()
	for thief, job in jobs do
		local root = rootOf(thief)
		if root == nil or thief.Character ~= job.character then
			snapHome(job, "thief_down")
			continue
		end
		if job.stage == "grab" then
			local by = tagger(job, root)
			if not state.grabsAllowed then
				snapHome(job, "dusk")
			elseif PlotService.isLocked(job.plotId) then
				snapHome(job, "locked")
			elseif padDistance(job.plotId, job.pad, root) > economy.steal.grabRange + GRAB_SLACK then
				snapHome(job, "moved")
			elseif by ~= nil then
				snapHome(job, "tagged", by)
			elseif now >= job.ends then
				beginCarry(job, now)
			end
			continue
		end

		local position = root.Position
		table.insert(job.samples, { t = now, x = position.X, z = position.Z })
		Steal.trim(economy, job.samples, now)
		local violation = Steal.moveViolation(economy, job.samples, speedOf(thief, now))
		local thiefPlot = PlotService.plotOf(thief)
		if violation ~= nil then
			snapHome(job, "violation")
			NetServer.Abuse:Fire(thief, "Carry", violation)
			warn(`[StealService] {thief.Name} failed the carry check: {violation}`)
		elseif not state.carriesAllowed then
			snapHome(job, "night")
		elseif now >= job.ends then
			snapHome(job, "timeout")
		else
			local by = tagger(job, root)
			if by ~= nil then
				snapHome(job, "tagged", by)
			elseif thiefPlot ~= nil and PlotService.inZone(thiefPlot, position) then
				deliver(job, now)
			end
		end
	end
	for player, untilTime in boostUntil do
		if untilTime <= now then
			boostUntil[player] = nil
			updateSpeed(player)
		end
	end
end

-- Ends every job that involves a player whose plot is going away (they left).
local function onReleased(player: Player)
	local own = jobs[player]
	if own ~= nil then
		snapHome(own, "thief_left")
	end
	for _, job in jobs do
		if job.victim == player then
			snapHome(job, "owner_left")
		end
	end
	boostUntil[player] = nil
end

function StealService.Init()
	GamePassService.Changed:Connect(function(player: Player, key: string)
		if key == "swiftBoots" then
			updateSpeed(player)
		end
	end)
	NetServer.on("GrabStart", grabStart)
	NetServer.on("GrabCancel", function(thief: Player)
		local job = jobs[thief]
		if job ~= nil and job.stage == "grab" then
			snapHome(job, "released")
		end
	end)
	PlotService.Released:Connect(onReleased)
	Players.PlayerRemoving:Connect(function(player: Player)
		onReleased(player) -- also covers a player who never had a plot
		friends[player] = nil
		for _, list in friends do
			list[player] = nil
		end
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function()
			task.defer(updateSpeed, player)
		end)
		learnFriends(player)
	end)
end

function StealService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(learnFriends, player)
	end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= TICK_SECONDS then
			elapsed = 0
			tick()
		end
	end)
end

return StealService
