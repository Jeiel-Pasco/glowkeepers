--!strict
-- Grimoire fixed-page skill unlocking & upgrading with Universal Ink, plus legacy odds helpers.
--
-- Fixed 4-page Black Clover / Blox Fruits model:
--   Every Grimoire type has 4 fixed signature skills (Spells.fixedFor(book.type) = { Z, X, C, V }).
--   Page 1 (Z) starts unlocked at Lv 1 when you acquire the book.
--   Universal Ink unlocks X (2 Ink) → C (4 Ink) → V (6 Ink), and upgrades any unlocked skill
--   from Lv 1 → Lv 5 (costing 1 → 2 → 3 → 4 Ink).

-- In Roblox a sibling ModuleScript; under Lune (tests) a path.
-- selene: allow(incorrect_standard_library_use)
local Spells = if script ~= nil then require(script.Parent:WaitForChild("Spells")) :: any else require("./Spells")

local Writing = {}

Writing.PAGES = 4
Writing.STAR_COST = 5 -- Stars to roll a Grimoire at the Desk
Writing.TEAR_REFUND = 0.5

export type Page = { sp: string, lv: number }
export type Book = { type: string, pages: { Page } }

-- Rarity odds kept for spec compatibility.
Writing.ODDS = {
	element = { Common = 0.60, Rare = 0.30, Epic = 0.08, Legendary = 0.02 },
	elementStars = { Common = 0.40, Rare = 0.35, Epic = 0.15, Legendary = 0.10 },
	mythic = { Rare = 0.55, Epic = 0.33, Legendary = 0.10, Mythic = 0.02 },
	mythicStars = { Rare = 0.35, Epic = 0.35, Legendary = 0.22, Mythic = 0.08 },
} :: { [string]: { [string]: number } }

-- Creates a new Grimoire of `bookType` with Page 1 (Z) already unlocked at Lv 1.
function Writing.newBook(bookType: string): Book
	local fixed = Spells.fixedFor(bookType)
	return {
		type = bookType,
		pages = { { sp = fixed[1], lv = 1 } },
	}
end

-- Cost in Universal Ink to unlock or upgrade fixed slot `slot` (1..4) on `book`.
-- Returns (cost, action: "unlock" | "upgrade" | "locked_prev" | "maxed").
function Writing.slotCost(book: Book, slot: number): (number?, string)
	if slot < 1 or slot > Writing.PAGES or slot % 1 ~= 0 then
		return nil, "invalid"
	end
	local fixed = Spells.fixedFor(book.type)
	local targetId = fixed[slot]
	if targetId == nil then
		return nil, "invalid"
	end
	local page = book.pages[slot]
	if page == nil then
		if slot > #book.pages + 1 then
			return nil, "locked_prev"
		end
		return Spells.UNLOCK_INK[slot] or 2, "unlock"
	end
	if page.lv >= Spells.MAX_LEVEL then
		return nil, "maxed"
	end
	return Spells.UPGRADE_INK[page.lv] or page.lv, "upgrade"
end

-- Unlocks or upgrades fixed `slot` (1..4) on `book` in place. Returns ("unlocked" | "upgraded", spellId, newLv).
function Writing.upgradeSlot(book: Book, slot: number): (string?, string?, number?)
	local cost, action = Writing.slotCost(book, slot)
	if cost == nil then
		return nil, nil, nil
	end
	local fixed = Spells.fixedFor(book.type)
	local spellId = fixed[slot]
	if action == "unlock" then
		book.pages[slot] = { sp = spellId, lv = 1 }
		return "unlocked", spellId, 1
	elseif action == "upgrade" then
		book.pages[slot].sp = spellId
		book.pages[slot].lv += 1
		return "upgraded", spellId, book.pages[slot].lv
	end
	return nil, nil, nil
end

function Writing.oddsFor(bookType: string, stars: boolean): { [string]: number }
	local mythic = bookType == "Light" or bookType == "Dark"
	if mythic then
		return if stars then Writing.ODDS.mythicStars else Writing.ODDS.mythic
	end
	return if stars then Writing.ODDS.elementStars else Writing.ODDS.element
end

function Writing.rarity(odds: { [string]: number }, r: number): string
	local acc = 0
	local last = "Common"
	for _, rarity in Spells.RARITIES do
		local p = odds[rarity]
		if p ~= nil then
			acc += p
			last = rarity
			if r < acc then
				return rarity
			end
		end
	end
	return last
end

function Writing.pick(bookType: string, rarity: string, r: number): string?
	local pool = Spells.pools[bookType]
	if pool == nil then
		return nil
	end
	local index = table.find(Spells.RARITIES, rarity) or 1
	local order = {}
	for i = index, 1, -1 do
		table.insert(order, Spells.RARITIES[i])
	end
	for i = index + 1, #Spells.RARITIES do
		table.insert(order, Spells.RARITIES[i])
	end
	for _, tier in order do
		local ids = pool[tier]
		if ids ~= nil and #ids > 0 then
			return ids[math.clamp(math.floor(r * #ids) + 1, 1, #ids)]
		end
	end
	return nil
end

function Writing.roll(bookType: string, stars: boolean, rng: () -> number): string?
	local rarity = Writing.rarity(Writing.oddsFor(bookType, stars), rng())
	return Writing.pick(bookType, rarity, rng())
end

function Writing.apply(book: Book, spellId: string): (string, number?)
	for i, page in book.pages do
		if page.sp == spellId then
			if page.lv >= Spells.MAX_LEVEL then
				return "maxed", i
			end
			page.lv += 1
			return "level", i
		end
	end
	if #book.pages < Writing.PAGES then
		table.insert(book.pages, { sp = spellId, lv = 1 })
		return "added", #book.pages
	end
	return "choose", nil
end

function Writing.resolve(book: Book, spellId: string, page: number): boolean
	if page == 0 then
		return true
	end
	if page < 1 or page > #book.pages or page % 1 ~= 0 then
		return false
	end
	book.pages[page] = { sp = spellId, lv = 1 }
	return true
end

return Writing
