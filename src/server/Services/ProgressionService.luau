--!strict
-- Levels, stat points, Robe Gear HP bonuses, and Black Clover Storyline Area Quests
-- (selectable at Elder Orsi, Scout Captain, and Knight Envoy; awards XP, Coins, Ink & ★ Stars).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Gears = require(Shared:WaitForChild("Gears")) :: any
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
	local gearStats = Gears.stats(data.gears)
	local max = Level.maxHealth(data.level, data.stats.health) + gearStats.hp
	local full = humanoid.Health >= humanoid.MaxHealth - 0.5
	humanoid.MaxHealth = max
	if full or humanoid.Health > max then
		humanoid.Health = max
	end
	player:SetAttribute("Level", data.level)
	player:SetAttribute("Bounty", data.bounty or 0)
end

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
	local active = data.activeQuest
	local boardQuest = active and Quests.BOARD_BY_ID[active.id]
	if boardQuest then
		NetServer.send(player, "Quest", {
			id = boardQuest.id,
			title = `{boardQuest.areaName} · {boardQuest.title}`,
			text = boardQuest.text,
			n = boardQuest.n,
			progress = math.min(active.n or 0, boardQuest.n),
			hint = nil,
			tutorial = false,
		})
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

local function acceptQuest(player: Player, questId: string)
	local data = DataService.get(player)
	local q = Quests.BOARD_BY_ID[questId]
	if data == nil or q == nil then
		return
	end
	if data.level < q.minLevel then
		NetServer.send(player, "Toast", `Requires Level {q.minLevel} for {q.title}`, "warn")
		return
	end
	data.activeQuest = { id = q.id, n = 0 }
	DataService.changed(player, "activeQuest")
	NetServer.send(player, "Toast", `Accepted: {q.title} ({q.areaName})`, "quest")
	sendQuest(player)
end

function ProgressionService.note(player: Player, event: string, arg: any?, role: string?)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	-- 1. Advance active Area Quest from a Quest Giver NPC.
	local active = data.activeQuest
	local boardQuest = active and Quests.BOARD_BY_ID[active.id]
	if boardQuest then
		local p = Quests.advance(boardQuest, active.n or 0, event, arg, role)
		if p ~= nil then
			active.n = p
			if p >= boardQuest.n then
				active.n = 0
				local r = boardQuest.reward
				LootService.reward(player, {
					coins = r.coins,
					ink = if r.ink and r.ink > 0 then { Universal = r.ink } else {},
					frag = {},
				})
				data.stars += r.stars
				DataService.changed(player, "stars", "activeQuest")
				NetServer.send(
					player,
					"Toast",
					`Quest Complete: {boardQuest.title}! +{r.xp} XP, +{r.coins} Coins, +{r.stars}★ Stars`,
					"quest"
				)
				ProgressionService.addXp(player, r.xp)
			else
				DataService.changed(player, "activeQuest")
			end
			sendQuest(player)
		end
	end

	-- 2. Also advance linear tutorial steps if still in progress.
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
		for _, n in reward.ink or {} do
			ink.Universal = (ink.Universal or 0) + n
		end
		LootService.reward(player, { coins = reward.coins, ink = ink, frag = {} })
		local starsEarned = reward.stars or 0
		if starsEarned > 0 then
			data.stars += starsEarned
			DataService.changed(player, "stars")
		end
		DataService.changed(player, "quest")
		ProgressionService.addXp(player, reward.xp)
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
	NetServer.on("AcceptQuest", acceptQuest)
	LootService.Banked:Connect(function(player: Player)
		ProgressionService.note(player, "bank")
	end)
	LootService.GearChanged:Connect(applyHealth)
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
		task.defer(sendQuest, player)
	end)
end

return ProgressionService
