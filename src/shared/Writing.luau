--!strict
-- Writing spells into grimoires (GDD "Spells"). Pure: the server passes the RNG.
--
-- A write spends 1 ink of the book's type and draws a rarity from the odds table, then a spell
-- of that rarity from the type's pool (falling back to the nearest rarity the pool has).
-- What happens next:
--   "level"    the book already has the spell: it levels up (to MAX_LEVEL; past that it refunds)
--   "added"    a free page: it goes there
--   "choose"   the book is full: the player replaces a page or tears the spell out

-- In Roblox a sibling ModuleScript; under Lune (tests) a path.
-- selene: allow(incorrect_standard_library_use)
local Spells = if script ~= nil then require(script.Parent:WaitForChild("Spells")) :: any else require("./Spells")

local Writing = {}

Writing.PAGES = 4
Writing.STAR_COST = 10 -- stars for a boosted element write
Writing.TEAR_REFUND = 0.5 -- of an ink, rounded down on the bank side

export type Page = { sp: string, lv: number }
export type Book = { type: string, pages: { Page } }

-- Rarity odds per write.
Writing.ODDS = {
	element = { Common = 0.60, Rare = 0.30, Epic = 0.08, Legendary = 0.02 },
	elementStars = { Common = 0.40, Rare = 0.35, Epic = 0.15, Legendary = 0.10 },
	mythic = { Rare = 0.55, Epic = 0.33, Legendary = 0.10, Mythic = 0.02 },
	mythicStars = { Rare = 0.35, Epic = 0.35, Legendary = 0.22, Mythic = 0.08 },
} :: { [string]: { [string]: number } }

function Writing.oddsFor(bookType: string, stars: boolean): { [string]: number }
	local mythic = bookType == "Light" or bookType == "Dark"
	if mythic then
		return if stars then Writing.ODDS.mythicStars else Writing.ODDS.mythic
	end
	return if stars then Writing.ODDS.elementStars else Writing.ODDS.element
end

-- Draws a rarity with `r` in [0, 1).
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

-- A spell of `rarity` from the type's pool, or the nearest rarity below (then above) it.
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

-- Rolls a spell for a book. `rng` returns numbers in [0, 1).
function Writing.roll(bookType: string, stars: boolean, rng: () -> number): string?
	local rarity = Writing.rarity(Writing.oddsFor(bookType, stars), rng())
	return Writing.pick(bookType, rarity, rng())
end

-- Applies a written spell to a book in place. Returns the outcome and the page it touched.
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

-- Resolves a "choose": page 1–4 replaces that page; 0 tears the new spell out.
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
