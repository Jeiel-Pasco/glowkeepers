--!strict
-- Grimoires (Black Clover / Blox Fruits model):
--   RollGrimoire   spend 5★ Stars at the Desk to roll a Grimoire from the 6-Tier Gacha (with Pity)
--   UpgradeSkill   spend Universal Ink at the Desk to unlock fixed pages X → C → V and upgrade Lv 1–5
--   EquipBook      choose up to 3 equipped Grimoires at the Shelf
--   SwapBook       swap the active Grimoire in hand (1.5 s swap cooldown)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Element = require(Shared:WaitForChild("Element")) :: any
local Loot = require(Shared:WaitForChild("Loot")) :: any
local Writing = require(Shared:WaitForChild("Writing")) :: any
local Spells = require(Shared:WaitForChild("Spells")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local CampService = require(script.Parent:WaitForChild("CampService"))
local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))

local GrimoireService = {}

GrimoireService.TEAR_COINS = 15
GrimoireService.SWAP_COOLDOWN = 1.5
GrimoireService.STARTERS = { Fire = "ember_shot", Water = "tide_bolt", Leaf = "thorn_dart" }

local pending: { [Player]: { book: number, spell: string } } = {}
local swapReadyAt: { [Player]: number } = {}
local rng = Random.new()

local function atDesk(player: Player): boolean
	local character = player.Character
	return character ~= nil and CampService.atDesk(player, character:GetPivot().Position)
end

local function toast(player: Player, text: string, kind: string?)
	NetServer.send(player, "Toast", text, kind or "warn")
end

-- Replicates the player's currently held Grimoire type and clover tier to their character so
-- every client draws the floating 3-Leaf / 4-Leaf / 5-Leaf Grimoire and applies its passive perk.
function GrimoireService.syncActiveAttr(player: Player)
	local data = DataService.get(player)
	local character = player.Character
	if data == nil or character == nil then
		return
	end
	local book = data.books[data.equipped[data.active]]
	local kind = if book then book.type else "Neutral"
	character:SetAttribute("ActiveBook", kind)
	character:SetAttribute("Clovers", Element.clovers(kind))
	-- Ensure Page 1 (Z) is always present on fixed-skill books.
	if book and #book.pages == 0 then
		local fixed = Spells.fixedFor(kind)
		book.pages[1] = { sp = fixed[1], lv = 1 }
	end
end

-- Rolls the 6-Tier Black Clover Grimoire Gacha at the Desk for 5★ Stars (with Pity).
local function rollGrimoire(player: Player)
	local data = DataService.get(player)
	if data == nil or not atDesk(player) then
		return
	end
	if data.stars < Element.STAR_ROLL_COST then
		toast(player, `You need {Element.STAR_ROLL_COST}★ Stars to roll a Grimoire (complete Quests & Bosses!)`)
		return
	end
	data.stars -= Element.STAR_ROLL_COST
	data.pity = (data.pity or 0) + 1
	data.counts.rolls = (data.counts.rolls or 0) + 1

	local r1 = rng:NextNumber()
	-- Pity rules: every 40th roll guarantees Legendary/Mythic; every 15th guarantees Epic+;
	-- every 5th guarantees Rare+.
	if data.pity >= 40 then
		r1 = 0.96 + rng:NextNumber() * 0.04
		data.pity = 0
	elseif data.pity % 15 == 0 then
		r1 = math.max(r1, 0.88)
	elseif data.pity % 5 == 0 then
		r1 = math.max(r1, 0.74)
	end
	local rolledType = Element.rollGacha(r1, rng:NextNumber())
	local rarity = Element.RARITY[rolledType] or "Common"
	local clovers = Element.clovers(rolledType)
	local fixed = Spells.fixedFor(rolledType)

	if data.element == "" then
		data.element = rolledType
	end

	-- Check if the player already owns this Grimoire type.
	local existingIdx: number? = nil
	for idx, b in data.books do
		if b.type == rolledType then
			existingIdx = idx
			break
		end
	end

	if existingIdx == nil then
		local newBook = Writing.newBook(rolledType)
		table.insert(data.books, newBook)
		local newIdx = #data.books
		for slot = 1, #data.equipped do
			if data.equipped[slot] == 0 then
				data.equipped[slot] = newIdx
				data.active = slot
				break
			end
		end
		DataService.changed(player, "books", "equipped", "active", "stars", "pity", "element")
		GrimoireService.syncActiveAttr(player)
		NetServer.send(player, "WriteResult", "rolled", fixed[1], newIdx, 1)
		toast(
			player,
			`Rolled [{rarity}] {clovers}-Leaf {rolledType} Grimoire!`,
			if clovers >= 4 then "level" else "quest"
		)
	else
		-- Duplicate Grimoire roll converts into +3 Universal Ink in the Bank & auto-upgrades if possible.
		data.bank.ink.Universal = (data.bank.ink.Universal or 0) + 3
		DataService.changed(player, "bank", "stars", "pity", "element")
		NetServer.send(player, "WriteResult", "dupe_book", fixed[1], existingIdx, 1)
		toast(player, `Rolled duplicate {rolledType} Grimoire → +3 Universal Ink banked!`, "loot")
	end
	ProgressionService.note(player, "element")
	ProgressionService.note(player, "write")
end

-- Unlocks or upgrades fixed skill slot `slot` (1..4 = Z, X, C, V) on `bookIndex` using Universal Ink.
local function upgradeSkill(player: Player, bookIndex: number, slot: number)
	local data = DataService.get(player)
	if data == nil or not atDesk(player) then
		return
	end
	local book = data.books[bookIndex]
	if book == nil then
		return
	end
	local cost, action = Writing.slotCost(book, slot)
	if cost == nil then
		if action == "locked_prev" then
			toast(player, "Unlock the previous page first!")
		elseif action == "maxed" then
			toast(player, "This skill is already at Max Level (Lv 5)!")
		end
		return
	end
	if not Loot.spendInk(data.bank, cost) then
		toast(player, `You need {cost} Banked Ink (you have {Loot.totalInk(data.bank)})`)
		return
	end
	local outcome, spellId, newLv = Writing.upgradeSlot(book, slot)
	if outcome == nil or spellId == nil then
		return
	end
	data.counts.writes += 1
	DataService.changed(player, "books", "bank")
	local spell = Spells.get(spellId)
	local spellName = if spell then spell.name else spellId
	NetServer.send(player, "WriteResult", if outcome == "unlocked" then "added" else "level", spellId, bookIndex, slot)
	toast(
		player,
		if outcome == "unlocked" then `Unlocked {spellName}!` else `Upgraded {spellName} to Lv {newLv}!`,
		"quest"
	)
	ProgressionService.note(player, "write")
end

-- Legacy Write handler: routes to upgrading the next available fixed slot on `bookIndex`.
local function write(player: Player, bookIndex: number, _stars: boolean)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local book = data.books[bookIndex]
	if book == nil then
		return
	end
	-- Find the first slot that can be unlocked, or the lowest-level unlocked slot.
	local targetSlot = 1
	if #book.pages < Writing.PAGES then
		targetSlot = #book.pages + 1
	else
		local bestLv = Spells.MAX_LEVEL + 1
		for s = 1, Writing.PAGES do
			local p = book.pages[s]
			if p and p.lv < bestLv then
				bestLv = p.lv
				targetSlot = s
			end
		end
	end
	upgradeSkill(player, bookIndex, targetSlot)
end

local function resolve(player: Player, page: number)
	local data = DataService.get(player)
	local choice = pending[player]
	if data == nil or choice == nil then
		return
	end
	local book = data.books[choice.book]
	if book == nil or not Writing.resolve(book, choice.spell, page) then
		return
	end
	pending[player] = nil
	if page == 0 then
		data.bank.coins += GrimoireService.TEAR_COINS
	end
	DataService.changed(player, "books", "bank")
	NetServer.send(player, "WriteResult", if page == 0 then "torn" else "replaced", choice.spell, choice.book, page)
	ProgressionService.note(player, "write")
end

local function equip(player: Player, slot: number, bookIndex: number)
	local data = DataService.get(player)
	if data == nil or slot > #data.equipped or data.books[bookIndex] == nil or not atDesk(player) then
		return
	end
	local from = table.find(data.equipped, bookIndex)
	if from then
		data.equipped[from] = data.equipped[slot]
	end
	data.equipped[slot] = bookIndex
	if data.equipped[data.active] == 0 then
		data.active = slot
	end
	DataService.changed(player, "equipped", "active")
	GrimoireService.syncActiveAttr(player)
end

local function swap(player: Player, slot: number)
	local data = DataService.get(player)
	if data == nil or slot > #data.equipped or data.equipped[slot] == 0 or data.active == slot then
		return
	end
	local now = os.clock()
	local ready = swapReadyAt[player] or 0
	if now < ready - 0.1 then
		return
	end
	swapReadyAt[player] = now + GrimoireService.SWAP_COOLDOWN
	data.active = slot
	DataService.changed(player, "active")
	GrimoireService.syncActiveAttr(player)
end

local function pickElement(player: Player, element: string)
	local data = DataService.get(player)
	if data == nil or data.element ~= "" or not atDesk(player) then
		return
	end
	local first = GrimoireService.STARTERS[element]
	if first == nil then
		return
	end
	data.element = element
	table.insert(data.books, Writing.newBook(element))
	local index = #data.books
	for slot = 1, #data.equipped do
		if data.equipped[slot] == 0 then
			data.equipped[slot] = index
			data.active = slot
			break
		end
	end
	DataService.changed(player, "element", "books", "equipped", "active")
	GrimoireService.syncActiveAttr(player)
	toast(player, `You got a 3-Leaf {element} Grimoire with {Spells.byId[first].name}!`, "quest")
	ProgressionService.note(player, "element")
end

function GrimoireService.Init()
	NetServer.on("Write", write)
	NetServer.on("WriteResolve", resolve)
	NetServer.on("RollGrimoire", rollGrimoire)
	NetServer.on("UpgradeSkill", upgradeSkill)
	NetServer.on("EquipBook", equip)
	NetServer.on("SwapBook", swap)
	NetServer.on("PickElement", pickElement)

	local function onCharacter(player: Player)
		task.defer(GrimoireService.syncActiveAttr, player)
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
	end)
	DataService.PlayerReady:Connect(onCharacter)

	-- DEV: in Studio, a local test player's DebugGrimoire attribute (a Grimoire type) gives them
	-- that Grimoire with all four pages at Lv 1 and puts it in hand. Never on real accounts.
	if RunService:IsStudio() then
		Players.PlayerAdded:Connect(function(player)
			player:GetAttributeChangedSignal("DebugGrimoire"):Connect(function()
				local kind = player:GetAttribute("DebugGrimoire")
				local data = DataService.get(player)
				if player.UserId > 0 or data == nil or not Element.isType(kind) then
					return
				end
				local book = Writing.newBook(kind)
				for slot, id in Spells.fixedFor(kind) do
					book.pages[slot] = { sp = id, lv = 1 }
				end
				table.insert(data.books, book)
				data.equipped[1] = #data.books
				data.active = 1
				DataService.changed(player, "books", "equipped", "active")
				GrimoireService.syncActiveAttr(player)
			end)
		end)
	end

	DataService.PlayerLeaving:Connect(function(player: Player)
		pending[player] = nil
		swapReadyAt[player] = nil
	end)
end

return GrimoireService
