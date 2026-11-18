-- Inventory: pads, vault, storage and "Place best" (GAME_SYSTEMS §7).
local H = require("./harness")
local Inventory = require("../src/shared/Inventory")
local Economy = require("../src/shared/Economy")

local cfg = H.config()

local function valueOf(record: any): number
	return Economy.glowlingValue(cfg, record.r, record.m, record.s)
end

-- A profile fragment with Glowlings of the given rarities, ids "g1", "g2", ...
local function profile(rarities: { number }): any
	local data = { glowlings = {}, vault = {}, display = {} }
	for i, r in rarities do
		local id = `g{i}`
		data.glowlings[id] = { id = id, sp = "mothlet", r = r, m = 0, s = 1, src = "lure", at = i, by = 1 }
	end
	return data
end

local LAYOUT = { slots = 8, vault = 3 } -- a new player: 8 pads, 3 of them vault

local function count(map: { [any]: any }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

H.test("locate, padKind and storageCount", function()
	local data = profile({ 1, 2, 3 })
	data.vault["1"] = "g1"
	data.display["5"] = "g2"
	local where, pad = Inventory.locate(data, "g1")
	H.eq(where, "vault", "g1 where")
	H.eq(pad, 1, "g1 pad")
	where, pad = Inventory.locate(data, "g2")
	H.eq(where, "display", "g2 where")
	H.eq(pad, 5, "g2 pad")
	H.eq((Inventory.locate(data, "g3")), "storage", "g3")
	H.eq((Inventory.locate(data, "nope")), nil, "not owned")
	H.eq(Inventory.storageCount(data), 1, "storage count")
	H.eq(Inventory.padKind(LAYOUT, 3), "vault", "pad 3")
	H.eq(Inventory.padKind(LAYOUT, 4), "display", "pad 4")
	H.eq(Inventory.padKind(LAYOUT, 9), nil, "pad 9 is locked")
	H.eq(Inventory.padKind(LAYOUT, 0), nil, "pad 0")
	H.eq(Inventory.padKind(LAYOUT, 1.5), nil, "fractional pad")
end)

H.test("place from storage: the pad decides vault or display", function()
	local data = profile({ 1, 2 })
	H.ok(Inventory.place(data, LAYOUT, "g1", 2), "place on vault pad")
	H.eq(data.vault["2"], "g1", "in the vault map")
	H.ok(Inventory.place(data, LAYOUT, "g2", 6), "place on display pad")
	H.eq(data.display["6"], "g2", "in the display map")
	H.eq(Inventory.storageCount(data), 0, "storage empty")
end)

H.test("place onto an occupied pad from storage sends the occupant to storage", function()
	local data = profile({ 1, 2 })
	Inventory.place(data, LAYOUT, "g1", 4)
	H.ok(Inventory.place(data, LAYOUT, "g2", 4), "replace")
	H.eq(data.display["4"], "g2", "new occupant")
	H.eq((Inventory.locate(data, "g1")), "storage", "old occupant")
end)

H.test("place between pads swaps, and each lands in the right map", function()
	local data = profile({ 1, 2 })
	Inventory.place(data, LAYOUT, "g1", 1) -- vault
	Inventory.place(data, LAYOUT, "g2", 7) -- display
	H.ok(Inventory.place(data, LAYOUT, "g2", 1), "swap")
	H.eq(data.vault["1"], "g2", "g2 now in the vault")
	H.eq(data.display["7"], "g1", "g1 took g2's display pad")
	H.eq(count(data.vault), 1, "vault count")
	H.eq(count(data.display), 1, "display count")
	H.ok(Inventory.place(data, LAYOUT, "g1", 8), "move to an empty pad")
	H.eq(data.display["7"], nil, "old pad cleared")
	H.eq(data.display["8"], "g1", "new pad")
end)

H.test("place rejects locked pads, strangers' ids, and is a no-op in place", function()
	local data = profile({ 1 })
	local ok, reason = Inventory.place(data, LAYOUT, "g1", 9)
	H.ok(not ok and reason == "slot locked", "pad past the unlocked slots")
	H.ok(not Inventory.place(data, LAYOUT, "g1", 0), "pad 0")
	H.ok(not Inventory.place(data, LAYOUT, "g1", 2.5), "fractional pad")
	ok, reason = Inventory.place(data, LAYOUT, "someone-else", 1)
	H.ok(not ok and reason == "not owned", "not owned")
	Inventory.place(data, LAYOUT, "g1", 5)
	H.ok(Inventory.place(data, LAYOUT, "g1", 5), "same pad")
	H.eq(data.display["5"], "g1", "still there")
end)

H.test("unplace returns a Glowling to storage unless storage is full", function()
	local data = profile({ 1, 2, 3 })
	Inventory.place(data, LAYOUT, "g1", 1)
	Inventory.place(data, LAYOUT, "g2", 4)
	local ok, reason = Inventory.unplace(data, "g1", 1)
	H.ok(not ok and reason == "storage full", "storage already holds 1 of 1")
	H.ok(Inventory.unplace(data, "g1", 60), "unplace")
	H.eq(data.vault["1"], nil, "pad cleared")
	H.eq(Inventory.storageCount(data), 2, "back in storage")
	ok, reason = Inventory.unplace(data, "g3", 60)
	H.ok(not ok and reason == "already in storage", "storage")
	ok, reason = Inventory.unplace(data, "nope", 60)
	H.ok(not ok and reason == "not owned", "not owned")
end)

H.test("forget drops the pad reference only", function()
	local data = profile({ 1, 2 })
	Inventory.place(data, LAYOUT, "g1", 4)
	H.ok(Inventory.forget(data, "g1"), "forgot")
	H.eq(data.display["4"], nil, "pad cleared")
	H.ok(data.glowlings.g1 ~= nil, "record kept")
	H.ok(not Inventory.forget(data, "g2"), "nothing to forget")
end)

H.test("normalize follows the vault as it grows, and drops locked pads to storage", function()
	local data = profile({ 1, 2, 3, 4 })
	data.display["4"] = "g1" -- pad 4 becomes a vault pad at vault 4
	data.display["5"] = "g2" -- stays display
	data.display["12"] = "g3" -- past 10 unlocked pads
	data.vault["2"] = "g4"
	H.ok(Inventory.normalize(data, { slots = 10, vault = 4 }), "changed")
	H.eq(data.vault["4"], "g1", "pad 4 moved to the vault map")
	H.eq(data.display["4"], nil, "and left the display map")
	H.eq(data.display["5"], "g2", "display untouched")
	H.eq((Inventory.locate(data, "g3")), "storage", "locked pad → storage")
	H.eq(data.vault["2"], "g4", "vault untouched")
	H.ok(not Inventory.normalize(data, { slots = 10, vault = 4 }), "a second run changes nothing")

	-- A vault entry on a pad that is now a display pad (data from a build with a bigger vault).
	local other = profile({ 1 })
	other.vault["5"] = "g1"
	H.ok(Inventory.normalize(other, LAYOUT), "changed")
	H.eq(other.display["5"], "g1", "moved to display")
end)

H.test("placeBest: best to the vault, next best to display, the rest in storage", function()
	-- 12 Glowlings: rarities 1..6 twice. 8 pads, 3 vault.
	local data = profile({ 1, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5, 6 })
	H.ok(Inventory.placeBest(data, LAYOUT, valueOf), "changed")
	-- Best: two Mythics (g6, g12), then the Legendaries (g5, g11), then Epics (g4, g10), Rares (g3, g9).
	H.eq(data.vault["1"], "g6", "vault 1: oldest Mythic")
	H.eq(data.vault["2"], "g12", "vault 2: the other Mythic")
	H.eq(data.vault["3"], "g5", "vault 3: oldest Legendary")
	H.eq(data.display["4"], "g11", "display 4")
	H.eq(data.display["5"], "g4", "display 5")
	H.eq(data.display["6"], "g10", "display 6")
	H.eq(data.display["7"], "g3", "display 7")
	H.eq(data.display["8"], "g9", "display 8")
	H.eq(Inventory.storageCount(data), 4, "four left in storage")
	H.ok(not Inventory.placeBest(data, LAYOUT, valueOf), "a second run changes nothing")
end)

H.test("placeBest moves as little as possible after one new catch", function()
	local data = profile({ 3, 3, 3, 2, 2 })
	Inventory.placeBest(data, LAYOUT, valueOf)
	local before = table.clone(data.display)
	local vaultBefore = table.clone(data.vault)
	-- A new Uncommon, worth the same as g4 and g5 but younger: it fills the next free display pad.
	data.glowlings.g6 = { id = "g6", sp = "mothlet", r = 2, m = 0, s = 1, src = "lure", at = 6, by = 1 }
	H.ok(Inventory.placeBest(data, LAYOUT, valueOf), "changed")
	for key, id in before do
		H.eq(data.display[key], id, `display {key} kept`)
	end
	for key, id in vaultBefore do
		H.eq(data.vault[key], id, `vault {key} kept`)
	end
	H.eq(data.display["6"], "g6", "the new one takes the next free pad")

	-- A new Epic beats every vaulted Rare: it takes the vault, and the weakest vaulted Rare
	-- (the youngest one) drops to display.
	data.glowlings.g7 = { id = "g7", sp = "mothlet", r = 4, m = 0, s = 1, src = "lure", at = 7, by = 1 }
	Inventory.placeBest(data, LAYOUT, valueOf)
	H.eq((Inventory.locate(data, "g7")), "vault", "the Epic is vaulted")
	H.eq((Inventory.locate(data, "g3")), "display", "the youngest Rare moved to display")
	H.eq((Inventory.locate(data, "g1")), "vault", "g1 stayed")
	H.eq((Inventory.locate(data, "g2")), "vault", "g2 stayed")
end)

H.test("placeBest with fewer Glowlings than vault pads fills the vault only", function()
	local data = profile({ 1, 5 })
	Inventory.placeBest(data, LAYOUT, valueOf)
	H.eq(data.vault["1"], "g2", "the Legendary first")
	H.eq(data.vault["2"], "g1", "then the Common")
	H.eq(count(data.display), 0, "no display")
end)

H.test("placeBest leaves held Glowlings (mid-steal) where they are", function()
	local data = profile({ 1, 2, 3, 4, 5, 6, 1, 2, 3 })
	Inventory.placeBest(data, LAYOUT, valueOf)
	-- g9 (a Rare) is being grabbed off its display pad; g2 (an Uncommon) is being carried home
	-- after it was taken off another pad, so it sits in storage.
	local grabbedPad = select(2, Inventory.locate(data, "g9"))
	H.eq((Inventory.locate(data, "g9")), "display", "g9 is on display")
	Inventory.forget(data, "g2")
	data.glowlings.g10 = { id = "g10", sp = "mothlet", r = 6, m = 0, s = 1, src = "lure", at = 10, by = 1 }
	local held = { g9 = true, g2 = true }
	H.ok(Inventory.placeBest(data, LAYOUT, valueOf, held), "changed")
	H.eq(select(2, Inventory.locate(data, "g9")), grabbedPad, "the grabbed one keeps its pad")
	H.eq((Inventory.locate(data, "g2")), "storage", "the carried one stays in storage")
	H.eq((Inventory.locate(data, "g10")), "vault", "the new Mythic is vaulted")
	H.eq(count(data.vault) + count(data.display), 8, "every pad is full")
	H.ok(not Inventory.placeBest(data, LAYOUT, valueOf, held), "a second run changes nothing")
end)

H.test("placedValue sums every placed Glowling, vault and display", function()
	local data = profile({ 1, 2, 3 })
	Inventory.place(data, LAYOUT, "g1", 1)
	Inventory.place(data, LAYOUT, "g3", 6)
	data.glowlings.g3.m = 1 -- Golden ×2
	data.glowlings.g3.s = 1.1
	H.near(Inventory.placedValue(data, valueOf), 1 + 20 * 2 * 1.1, 1e-9, "1 + 44")
	H.eq(#Inventory.placedIds(data), 2, "placed ids")
	local ranked = Inventory.ranked(data, valueOf)
	H.eq(ranked[1], "g3", "ranked best first")
	H.eq(ranked[3], "g1", "ranked worst last")
end)

H.finish("inventory")
