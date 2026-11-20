--!strict
-- Grimoires (GDD "Grimoires", "Spells"): writing spells at your desk, equipping books from the
-- shelf, swapping the book in hand, and the starter element pick after the tutorial.
--
-- A write spends 1 banked ink of the book's type (+10 stars for boosted odds). If the book is
-- full the player chooses a page to replace, or tears the new spell out (15 coins back).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Writing = require(Shared:WaitForChild("Writing")) :: any
local Spells = require(Shared:WaitForChild("Spells")) :: any
local Quests = require(Shared:WaitForChild("Quests")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local CampService = require(script.Parent:WaitForChild("CampService"))
local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))

local GrimoireService = {}

GrimoireService.TEAR_COINS = 15
GrimoireService.STARTERS = { Fire = "ember_shot", Water = "tide_bolt", Leaf = "thorn_dart" } -- first written spell

local pending: { [Player]: { book: number, spell: string } } = {}
local rng = Random.new()

local function atDesk(player: Player): boolean
	local character = player.Character
	return character ~= nil and CampService.atDesk(player, character:GetPivot().Position)
end

local function toast(player: Player, text: string, kind: string?)
	NetServer.send(player, "Toast", text, kind or "warn")
end

local function write(player: Player, bookIndex: number, stars: boolean)
	local data = DataService.get(player)
	if data == nil or not atDesk(player) then
		return
	end
	if pending[player] then
		toast(player, "Choose a page for your last spell first")
		return
	end
	local book = data.books[bookIndex]
	if book == nil then
		return
	end
	if (data.bank.ink[book.type] or 0) < 1 then
		toast(player, `You need banked {book.type} ink`)
		return
	end
	if stars and data.stars < Writing.STAR_COST then
		toast(player, `Boosted writing needs {Writing.STAR_COST} stars`)
		return
	end
	local spell = Writing.roll(book.type, stars, function()
		return rng:NextNumber()
	end)
	if spell == nil then
		toast(player, "This grimoire's spells aren't in the game yet")
		return
	end
	data.bank.ink[book.type] -= 1
	if stars then
		data.stars -= Writing.STAR_COST
	end
	data.counts.writes += 1
	local outcome, page = Writing.apply(book, spell)
	if outcome == "maxed" then
		data.bank.ink[book.type] += 1 -- already at max level: the ink comes back
	elseif outcome == "choose" then
		pending[player] = { book = bookIndex, spell = spell }
	end
	DataService.changed(player, "books", "bank", "stars")
	NetServer.send(player, "WriteResult", outcome, spell, bookIndex, page)
	if outcome ~= "choose" then
		ProgressionService.note(player, "write")
	end
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
	-- Moving a book that's already equipped swaps the two slots.
	local from = table.find(data.equipped, bookIndex)
	if from then
		data.equipped[from] = data.equipped[slot]
	end
	data.equipped[slot] = bookIndex
	if data.equipped[data.active] == 0 then
		data.active = slot
	end
	DataService.changed(player, "equipped", "active")
end

local function swap(player: Player, slot: number)
	local data = DataService.get(player)
	if data == nil or slot > #data.equipped or data.equipped[slot] == 0 or data.active == slot then
		return
	end
	data.active = slot
	DataService.changed(player, "active")
end

local function pickElement(player: Player, element: string)
	local data = DataService.get(player)
	if data == nil or data.element ~= "" or not atDesk(player) then
		return
	end
	local step = Quests.step(data.quest.step)
	if step.event ~= "element" then
		toast(player, "Finish your first quest to pick an element")
		return
	end
	local first = GrimoireService.STARTERS[element]
	if first == nil then
		return
	end
	data.element = element
	table.insert(data.books, { type = element, pages = { { sp = first, lv = 1 } } })
	local index = #data.books
	for slot = 1, #data.equipped do
		if data.equipped[slot] == 0 then
			data.equipped[slot] = index
			data.active = slot
			break
		end
	end
	DataService.changed(player, "element", "books", "equipped", "active")
	toast(player, `You got a {element} grimoire with {Spells.byId[first].name} written in it!`, "quest")
	ProgressionService.note(player, "element")
end

function GrimoireService.Init()
	NetServer.on("Write", write)
	NetServer.on("WriteResolve", resolve)
	NetServer.on("EquipBook", equip)
	NetServer.on("SwapBook", swap)
	NetServer.on("PickElement", pickElement)
	DataService.PlayerLeaving:Connect(function(player: Player)
		pending[player] = nil -- an unresolved choice keeps the old pages (the spell is torn out)
	end)
end

return GrimoireService
