--!strict
-- Levels, stat points and the quest chain (GDD "Getting stronger", "Tutorial").
--
-- XP comes from kills and quests. Each level gives 3 stat points (health, power, defense);
-- resetting them is free in the slice. Max health follows level and health points. Quests
-- advance on events other services report through note(); the tracked quest goes to the client
-- as a Quest view.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Level = require(Shared:WaitForChild("Level")) :: any
local Quests = require(Shared:WaitForChild("Quests")) :: any
local Zones = require(Shared:WaitForChild("Zones")) :: any
local Enemies = require(Shared:WaitForChild("Enemies")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local LootService = require(script.Parent:WaitForChild("LootService"))

local ProgressionService = {}

local function applyHealth(player: Player)
	local data = DataService.get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if data == nil or humanoid == nil then
		return
	end
	local max = Level.maxHealth(data.level, data.stats.health)
	local full = humanoid.Health >= humanoid.MaxHealth - 0.5
	humanoid.MaxHealth = max
	if full or humanoid.Health > max then
		humanoid.Health = max
	end
	player:SetAttribute("Level", data.level)
end

-- Fills {zone} and {boss} with the player's element zone.
function ProgressionService.questText(data: any, text: string): string
	local zone = Zones.forElement(data.element)
	local text1 = string.gsub(text, "{zone}", zone.name)
	local text2 = string.gsub(text1, "{boss}", Enemies.kinds[zone.boss].name)
	return text2
end

local function sendQuest(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local step = Quests.step(data.quest.step)
	NetServer.send(player, "Quest", {
		index = data.quest.step,
		text = ProgressionService.questText(data, step.text),
		n = step.n,
		progress = math.min(data.quest.n, step.n),
		hint = step.hint,
		tutorial = Quests.inTutorial(data.quest.step),
	})
end

function ProgressionService.addXp(player: Player, amount: number)
	local data = DataService.get(player)
	if data == nil or amount <= 0 then
		return
	end
	local before = data.level
	data.level, data.xp = Level.addXp(data.level, data.xp, math.floor(amount))
	DataService.changed(player, "level", "xp")
	if data.level > before then
		applyHealth(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
		end
		NetServer.sendAll("Fx", "levelup", player.UserId, data.level)
		NetServer.send(
			player,
			"Toast",
			`Level {data.level}! +{(data.level - before) * Level.POINTS_PER_LEVEL} stat points`,
			"level"
		)
		ProgressionService.note(player, "level", data.level)
	end
end

-- Reports a quest event (see Shared.Quests).
function ProgressionService.note(player: Player, event: string, arg: any?, role: string?)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local step = Quests.step(data.quest.step)
	local progress = Quests.advance(step, data.quest.n, event, arg, role)
	if progress == nil then
		return
	end
	data.quest.n = progress
	if progress >= step.n then
		data.quest.step += 1
		data.quest.n = 0
		local reward = step.reward
		local ink = {}
		for kind, n in reward.ink or {} do
			local real = if kind == "element" then (if data.element ~= "" then data.element else "Neutral") else kind
			ink[real] = (ink[real] or 0) + n
		end
		LootService.reward(player, { coins = reward.coins, ink = ink, frag = {} })
		NetServer.send(player, "Toast", `Quest complete: {ProgressionService.questText(data, step.text)}`, "quest")
		DataService.changed(player, "quest")
		ProgressionService.addXp(player, reward.xp)
		-- A new "reach level" step may already be met.
		local nextStep = Quests.step(data.quest.step)
		if nextStep.event == "level" then
			task.defer(ProgressionService.note, player, "level", data.level)
		end
	else
		DataService.changed(player, "quest")
	end
	sendQuest(player)
end

function ProgressionService.questStep(player: Player): number
	local data = DataService.get(player)
	return if data then data.quest.step else 1
end

local function allocate(player: Player, stat: string, points: number)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local spent = data.stats.health + data.stats.power + data.stats.defense
	local free = Level.pointsEarned(data.level) - spent
	points = math.min(points, free)
	if points <= 0 then
		return
	end
	data.stats[stat] += points
	DataService.changed(player, "stats")
	applyHealth(player)
end

local function reset(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	data.stats = { health = 0, power = 0, defense = 0 }
	DataService.changed(player, "stats")
	applyHealth(player)
end

function ProgressionService.Init()
	NetServer.on("AllocateStat", allocate)
	NetServer.on("ResetStats", reset)
	LootService.Banked:Connect(function(player: Player)
		ProgressionService.note(player, "bank")
	end)
	DataService.ClientReady:Connect(function(player: Player)
		task.defer(sendQuest, player)
	end)
	local function added(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 10)
			applyHealth(player)
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = humanoid.MaxHealth
			end
		end)
	end
	Players.PlayerAdded:Connect(added)
	for _, player in Players:GetPlayers() do
		added(player)
	end
	DataService.PlayerReady:Connect(function(player: Player)
		applyHealth(player)
		task.defer(sendQuest, player) -- whichever of PlayerReady and ClientReady comes last sends it
	end)
end

return ProgressionService
