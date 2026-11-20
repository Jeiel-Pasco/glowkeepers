--!strict
-- Capped Backpack loot extraction, Camp Banking (+15% Full-Bag Bonus on foot), Recall (scaled by
-- Boots Gear), Death Satchels (scaled by Backpack Gear death protection), and the Camp Gear Shop
-- (buying the 4 Visible Gear Categories with Banked Coins).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local CombatRules = require(Shared:WaitForChild("CombatRules")) :: any
local Gears = require(Shared:WaitForChild("Gears")) :: any
local Loot = require(Shared:WaitForChild("Loot")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local CampService = require(script.Parent:WaitForChild("CampService"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))

local LootService = {}
LootService.Banked = Signal.new() -- (player, bag)
LootService.GearChanged = Signal.new() -- (player)

LootService.RECALL_SECONDS = 5
LootService.SATCHEL_SECONDS = 120
LootService.PRICES = { ink_Neutral = 40, ink_Fire = 80, ink_Water = 80, ink_Leaf = 80 } :: { [string]: number }

local recalls: { [Player]: number } = {} -- player → os.clock() when it lands

-- Replicates Backpack fullness & equipped Gear tiers to character attributes so all clients draw
-- the 3D Backpack (bulging/glowing when full), Cloak/Robe, Wizard Hat, and Boots.
function LootService.syncCharacterAttrs(player: Player)
	local data = DataService.get(player)
	local character = player.Character
	if data == nil or character == nil then
		return
	end
	local g = data.gears or { backpack = 1, robe = 0, hat = 0, boots = 0 }
	local stats = Gears.stats(g)
	local weight = Loot.weight(data.carried)
	character:SetAttribute("GearBackpack", g.backpack or 1)
	character:SetAttribute("GearRobe", g.robe or 0)
	character:SetAttribute("GearHat", g.hat or 0)
	character:SetAttribute("GearBoots", g.boots or 0)
	character:SetAttribute("BagWeight", weight)
	character:SetAttribute("BagCap", stats.capacity)
	character:SetAttribute("BagFull", weight >= stats.capacity)
end

-- "+12 coins, 1 Ink"
function LootService.describe(bag: any): string
	local parts = {}
	if bag.coins > 0 then
		table.insert(parts, `{bag.coins} coins`)
	end
	local ink = Loot.totalInk(bag)
	if ink > 0 then
		table.insert(parts, `{ink} Ink`)
	end
	for kind, n in bag.frag do
		if n > 0 then
			table.insert(parts, `{n} {kind} fragment`)
		end
	end
	return table.concat(parts, ", ")
end

-- Adds a bag to the player's capped Backpack (`data.carried`).
function LootService.give(player: Player, bag: any)
	local data = DataService.get(player)
	if data == nil or Loot.isEmpty(bag) then
		return
	end
	local stats = Gears.stats(data.gears)
	local cap = stats.capacity
	local currentWeight = Loot.weight(data.carried)
	if currentWeight >= cap then
		NetServer.send(player, "Toast", `Backpack FULL ({cap}/{cap})! Retreat to Camp to bank your loot!`, "warn")
		LootService.syncCharacterAttrs(player)
		return
	end

	-- War Mode (PvP ON) grants +25% bonus Coins from field drops!
	local warMult = if player:GetAttribute("WarMode") == true then 1.25 else 1
	local addCoins = math.floor((bag.coins or 0) * warMult + 0.5)
	local addInk = Loot.totalInk(bag)

	local remainingWeight = math.max(0, cap - currentWeight)
	local acceptedInk = math.min(addInk, remainingWeight // Loot.INK_WEIGHT)
	remainingWeight -= acceptedInk * Loot.INK_WEIGHT
	local acceptedCoins = math.min(addCoins, remainingWeight * Loot.COINS_PER_WEIGHT)

	local added = Loot.empty()
	added.coins = acceptedCoins
	if acceptedInk > 0 then
		added.ink.Universal = acceptedInk
	end
	if not Loot.isEmpty(added) then
		Loot.add(data.carried, added)
		DataService.changed(player, "carried")
		LootService.syncCharacterAttrs(player)
		local newWeight = Loot.weight(data.carried)
		if newWeight >= cap then
			NetServer.send(
				player,
				"Toast",
				`+{LootService.describe(added)} · BACKPACK FULL ({cap}/{cap})! Run to Camp for +15% bonus!`,
				"warn"
			)
		else
			NetServer.send(player, "Toast", `+{LootService.describe(added)}  ({newWeight}/{cap} bag)`, "loot")
		end
	else
		NetServer.send(player, "Toast", `Backpack FULL ({cap}/{cap})! Retreat to Camp to bank!`, "warn")
	end
end

-- Straight into the bank (quest rewards: never at risk).
function LootService.reward(player: Player, bag: any)
	local data = DataService.get(player)
	if data == nil or Loot.isEmpty(bag) then
		return
	end
	Loot.add(data.bank, bag)
	DataService.changed(player, "bank")
end

-- A raider's hit: takes `share` of what the player carries.
function LootService.steal(player: Player, share: number): any
	local data = DataService.get(player)
	if data == nil then
		return Loot.empty()
	end
	local taken = Loot.take(data.carried, share)
	if not Loot.isEmpty(taken) then
		DataService.changed(player, "carried")
		LootService.syncCharacterAttrs(player)
		NetServer.send(player, "Toast", `A raider grabbed {LootService.describe(taken)}! Chase it down`, "warn")
	end
	return taken
end

function LootService.carriedValue(player: Player): number
	local data = DataService.get(player)
	return if data then Loot.value(data.carried) else 0
end

local function bank(player: Player, viaRecall: boolean?)
	local data = DataService.get(player)
	if data == nil or Loot.isEmpty(data.carried) then
		return
	end
	local stats = Gears.stats(data.gears)
	local wasFull = not viaRecall and Loot.isFull(data.carried, stats.capacity)
	local moved = data.carried
	data.carried = Loot.empty()
	local bonusCoins = if wasFull then math.max(1, math.floor(moved.coins * Loot.FULL_BAG_BONUS + 0.5)) else 0
	moved.coins += bonusCoins
	Loot.add(data.bank, moved)
	DataService.changed(player, "carried", "bank")
	LootService.syncCharacterAttrs(player)
	if wasFull and bonusCoins > 0 then
		NetServer.send(
			player,
			"Toast",
			`FULL BAG EXTRACTION! Banked {LootService.describe(moved)} (+15% Full-Bag Bonus!)`,
			"bank"
		)
	else
		NetServer.send(player, "Toast", `Banked {LootService.describe(moved)}`, "bank")
	end
	LootService.Banked:Fire(player, moved)
end

-- Death satchel -----------------------------------------------------------------------------

local function dropSatchel(player: Player, position: Vector3, bag: any, killer: Player?)
	local satchel = Instance.new("Part")
	satchel.Name = "Satchel"
	satchel.Size = Vector3.new(2.4, 2, 2.4)
	satchel.Color = Color3.fromRGB(140, 96, 60)
	satchel.Material = Enum.Material.Fabric
	satchel.Anchored = true
	satchel.CanCollide = false
	satchel.CFrame = CFrame.new(position.X, position.Y - 1.5, position.Z)
	satchel:SetAttribute("OwnerId", player.UserId)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 140)
	light.Range = 12
	light.Parent = satchel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 36)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 250
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 230, 170)
	label.TextStrokeTransparency = 0.4
	label.Text = `{player.DisplayName}'s satchel`
	label.Parent = gui
	gui.Parent = satchel
	satchel.Parent = workspace

	local taken = false
	local claimUntil = os.clock() + 10
	satchel.Touched:Connect(function(hit)
		if taken then
			return
		end
		local who = Players:GetPlayerFromCharacter(hit.Parent)
		if who == nil then
			return
		end
		local allowed = who == player or who == killer or (killer ~= nil and os.clock() > claimUntil)
		if allowed then
			taken = true
			satchel:Destroy()
			LootService.give(who, bag)
		end
	end)
	task.delay(LootService.SATCHEL_SECONDS, function()
		if not taken then
			taken = true
			satchel:Destroy()
		end
	end)
end

-- A War Mode kill: the killer's bounty grows and they claim the victim's, in coins.
local function payBounty(victim: Player, victimData: any, killer: Player)
	local killerData = DataService.get(killer)
	if killerData == nil then
		return
	end
	local claimed = victimData.bounty or 0
	victimData.bounty = 0
	killerData.bounty = (killerData.bounty or 0) + 1
	DataService.changed(victim, "bounty")
	DataService.changed(killer, "bounty")
	victim:SetAttribute("Bounty", 0)
	killer:SetAttribute("Bounty", killerData.bounty)
	local reward = Loot.empty()
	reward.coins = CombatRules.bountyReward(claimed)
	NetServer.send(killer, "Toast", `You defeated {victim.DisplayName}! Bounty +1`, "loot")
	NetServer.send(victim, "Toast", `{killer.DisplayName} defeated you and claimed your bounty`, "warn")
	LootService.give(killer, reward)
end

local function onDied(player: Player, position: Vector3, killer: Player?, duel: boolean?)
	recalls[player] = nil
	NetServer.send(player, "RecallState", nil)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	data.counts.deaths += 1
	if duel then
		-- Duel Arena Ring: a friendly fight, nothing lost.
		if killer then
			NetServer.send(killer, "Toast", `You won the duel against {player.DisplayName}!`, "loot")
		end
		return
	end
	if killer then
		payBounty(player, data, killer)
	end
	local stats = Gears.stats(data.gears)
	local dropped = Loot.take(data.carried, stats.deathShare)
	DataService.changed(player, "carried")
	LootService.syncCharacterAttrs(player)
	if not Loot.isEmpty(dropped) then
		dropSatchel(player, position, dropped, killer)
		NetServer.send(
			player,
			"Toast",
			`You dropped {LootService.describe(dropped)}. Your satchel waits where you fell`,
			"warn"
		)
	end
end

-- Recall ----------------------------------------------------------------------------------

local function onRecall(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") or CampService.isSafe(root.Position) then
		return
	end
	if recalls[player] then
		recalls[player] = nil
		NetServer.send(player, "RecallState", nil)
		return
	end
	local data = DataService.get(player)
	local recallSec = if data then Gears.stats(data.gears).recallSeconds else LootService.RECALL_SECONDS
	recalls[player] = os.clock() + recallSec
	NetServer.send(player, "RecallState", workspace:GetServerTimeNow() + recallSec, recallSec)
end

-- Buying Gears with Banked Coins ----------------------------------------------------------

local function buyGear(player: Player, category: string)
	local data = DataService.get(player)
	local character = player.Character
	if data == nil or character == nil or not CampService.isSafe(character:GetPivot().Position) then
		return
	end
	data.gears = data.gears or { backpack = 1, robe = 0, hat = 0, boots = 0 }
	local currentTier = data.gears[category] or 0
	local nextItem = Gears.nextTier(category, currentTier)
	if nextItem == nil then
		NetServer.send(player, "Toast", `Your {Gears.LABELS[category] or category} is already Max Tier!`, "warn")
		return
	end
	if data.bank.coins < nextItem.price then
		NetServer.send(player, "Toast", `You need {nextItem.price} Banked Coins for {nextItem.name}`, "warn")
		return
	end
	data.bank.coins -= nextItem.price
	data.gears[category] = nextItem.tier
	DataService.changed(player, "bank", "gears")
	LootService.syncCharacterAttrs(player)
	LootService.GearChanged:Fire(player)
	NetServer.send(player, "Toast", `Equipped {nextItem.name}! ({nextItem.blurb})`, "bank")
end

local function buy(player: Player, item: string)
	local data = DataService.get(player)
	local price = LootService.PRICES[item]
	local character = player.Character
	if data == nil or price == nil or character == nil then
		return
	end
	if not CampService.isSafe(character:GetPivot().Position) then
		return
	end
	if data.bank.coins < price then
		NetServer.send(player, "Toast", `You need {price} banked coins`, "warn")
		return
	end
	data.bank.coins -= price
	data.bank.ink.Universal = (data.bank.ink.Universal or 0) + 1
	DataService.changed(player, "bank")
	NetServer.send(player, "Toast", "Bought 1 Universal Ink", "bank")
end

function LootService.Init()
	CombatService.PlayerDied:Connect(onDied)
	CombatService.PlayerHurt:Connect(function(player: Player)
		if recalls[player] then
			recalls[player] = nil
			NetServer.send(player, "RecallState", nil)
			NetServer.send(player, "Toast", "Recall broken by damage", "warn")
		end
	end)
	NetServer.on("Recall", onRecall)
	NetServer.on("Buy", buy)
	NetServer.on("BuyGear", buyGear)

	local function onCharacter(player: Player)
		task.defer(LootService.syncCharacterAttrs, player)
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
	end)
	DataService.PlayerReady:Connect(onCharacter)
	DataService.PlayerLeaving:Connect(function(player: Player, data: any)
		recalls[player] = nil
		if CombatService.inCombat(player) then
			local share = Gears.stats(data.gears).deathShare
			Loot.take(data.carried, share)
		end
	end)
end

function LootService.Start()
	while true do
		task.wait(0.4)
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root == nil or not root:IsA("BasePart") then
				continue
			end
			local landing = recalls[player]
			if landing and now >= landing then
				recalls[player] = nil
				NetServer.send(player, "RecallState", nil)
				character:PivotTo(CampService.spawnCFrame(player))
				bank(player, true)
			elseif CampService.atHome(player, root.Position) then
				bank(player, false)
			end
		end
	end
end

return LootService
