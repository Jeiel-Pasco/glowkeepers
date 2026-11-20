--!strict
-- Carried and banked loot (GDD "Loot, camp and risk"): what you pick up is carried until you
-- walk into your own camp, which banks it. Dying drops half of it as a satchel only you can pick
-- up; leaving the game within 15 s of a hit counts as dying there. Recall is a 5 s channel home
-- that any damage cancels. Raiders steal some of it per hit (EnemyService calls steal).
-- Also the camp's Ink Merchant: banked coins buy ink.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Loot = require(Shared:WaitForChild("Loot")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local CampService = require(script.Parent:WaitForChild("CampService"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))

local LootService = {}
LootService.Banked = Signal.new() -- (player, bag)

LootService.RECALL_SECONDS = 5
LootService.SATCHEL_SECONDS = 120
LootService.PRICES = { ink_Neutral = 40, ink_Fire = 80 } :: { [string]: number }

local recalls: { [Player]: number } = {} -- player → os.clock() when it lands

-- "+12 coins, 1 Fire ink"
function LootService.describe(bag: any): string
	local parts = {}
	if bag.coins > 0 then
		table.insert(parts, `{bag.coins} coins`)
	end
	for kind, n in bag.ink do
		if n > 0 then
			table.insert(parts, `{n} {kind} ink`)
		end
	end
	for kind, n in bag.frag do
		if n > 0 then
			table.insert(parts, `{n} {kind} fragment`)
		end
	end
	return table.concat(parts, ", ")
end

-- Adds a bag to what the player carries.
function LootService.give(player: Player, bag: any)
	local data = DataService.get(player)
	if data == nil or Loot.isEmpty(bag) then
		return
	end
	Loot.add(data.carried, bag)
	DataService.changed(player, "carried")
	NetServer.send(player, "Toast", `+{LootService.describe(bag)}`, "loot")
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

-- A raider's hit: takes `share` of what the player carries. Returns what was taken.
function LootService.steal(player: Player, share: number): any
	local data = DataService.get(player)
	if data == nil then
		return Loot.empty()
	end
	local taken = Loot.take(data.carried, share)
	if not Loot.isEmpty(taken) then
		DataService.changed(player, "carried")
		NetServer.send(player, "Toast", `A raider grabbed {LootService.describe(taken)}! Chase it down`, "warn")
	end
	return taken
end

function LootService.carriedValue(player: Player): number
	local data = DataService.get(player)
	return if data then Loot.value(data.carried) else 0
end

local function bank(player: Player)
	local data = DataService.get(player)
	if data == nil or Loot.isEmpty(data.carried) then
		return
	end
	local moved = data.carried
	data.carried = Loot.empty()
	Loot.add(data.bank, moved)
	DataService.changed(player, "carried", "bank")
	NetServer.send(player, "Toast", `Banked {LootService.describe(moved)}`, "bank")
	LootService.Banked:Fire(player, moved)
end

-- Death satchel -----------------------------------------------------------------------------

local function dropSatchel(player: Player, position: Vector3, bag: any)
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
	satchel.Touched:Connect(function(hit)
		if taken then
			return
		end
		local who = Players:GetPlayerFromCharacter(hit.Parent)
		if who == player then
			taken = true
			satchel:Destroy()
			LootService.give(player, bag)
		end
	end)
	task.delay(LootService.SATCHEL_SECONDS, function()
		if not taken then
			taken = true
			satchel:Destroy()
		end
	end)
end

local function onDied(player: Player, position: Vector3)
	recalls[player] = nil
	NetServer.send(player, "RecallState", nil)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	data.counts.deaths += 1
	local dropped = Loot.take(data.carried, Loot.DEATH_SHARE)
	DataService.changed(player, "carried")
	if not Loot.isEmpty(dropped) then
		dropSatchel(player, position, dropped)
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
	recalls[player] = os.clock() + LootService.RECALL_SECONDS
	NetServer.send(player, "RecallState", workspace:GetServerTimeNow() + LootService.RECALL_SECONDS)
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
	local kind = string.sub(item, 5)
	if kind == "Fire" and data.element ~= "Fire" then
		NetServer.send(player, "Toast", "Pick Fire as your element first", "warn")
		return
	end
	if data.bank.coins < price then
		NetServer.send(player, "Toast", `You need {price} banked coins`, "warn")
		return
	end
	data.bank.coins -= price
	data.bank.ink[kind] = (data.bank.ink[kind] or 0) + 1
	DataService.changed(player, "bank")
	NetServer.send(player, "Toast", `Bought 1 {kind} ink`, "bank")
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
	DataService.PlayerLeaving:Connect(function(player: Player, data: any)
		recalls[player] = nil
		if CombatService.inCombat(player) then
			Loot.take(data.carried, Loot.DEATH_SHARE) -- left mid-fight: the dropped half is gone
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
			elseif CampService.atHome(player, root.Position) then
				bank(player)
			end
		end
	end
end

return LootService
