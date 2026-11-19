-- Night Companion (GAME_SYSTEMS §31, D23).
local H = require("./harness")
local Companion = require("../src/shared/Companion")

local cfg = H.config()
local species = {}
for _, entry in H.json("config/species.json").species do
	species[entry.id] = entry
end

local function save(companion: string, inVault: boolean)
	return {
		companion = companion,
		glowlings = { a = { sp = "puffwick", r = 1, m = 0, s = 1 } },
		vault = if inVault then { ["1"] = "a" } else {},
		display = if inVault then {} else { ["8"] = "a" },
	}
end

H.test("only a vault Glowling counts, and only by day can it change", function()
	H.eq(Companion.species(save("a", true), species).id, "puffwick")
	H.eq(Companion.species(save("a", false), species), nil, "moved out of the vault")
	H.eq(Companion.species(save("", true), species), nil, "none")
	H.eq(Companion.canSet(save("", true), "a", "Day"), nil)
	H.eq(Companion.canSet(save("", true), "a", "Night"), "night")
	H.eq(Companion.canSet(save("", false), "a", "Day"), "not_in_vault")
end)

H.test("Firebinder: +15% (Rare floor or lower), Emberwing +50%; others nothing", function()
	H.eq(Companion.fuelMult(cfg, species.puffwick), 1.15)
	H.eq(Companion.fuelMult(cfg, species.emberwing), 1.5)
	H.eq(Companion.fuelMult(cfg, species.mossbear), 1)
	H.eq(Companion.fuelMult(cfg, nil), 1)
end)

H.test("Savior: revive hold 0.6 s shorter, never under 1.8 s", function()
	H.eq(Companion.reviveHold(cfg, species.moonbun, 3), 2.4)
	H.eq(Companion.reviveHold(cfg, species.moonbun, 2), 1.8)
	H.eq(Companion.reviveHold(cfg, species.puffwick, 3), 3)
end)

H.test("Wayfinder: nearest Rare-floor wild within 60 studs", function()
	local here = { X = 0, Y = 0, Z = 0 }
	local wilds = {
		{ id = "1", sp = "puffwick", x = 5, y = 0, z = 0 }, -- Common floor: ignored
		{ id = "2", sp = "gloomraven", x = 40, y = 0, z = 0 },
		{ id = "3", sp = "lunadrake", x = 30, y = 0, z = 0 },
		{ id = "4", sp = "auroralynx", x = 70, y = 0, z = 0 }, -- too far
	}
	H.eq(Companion.wayfind(cfg, species, here, wilds).id, "3")
	H.eq(Companion.wayfind(cfg, species, here, { wilds[1], wilds[4] }), nil)
end)

H.finish("companion")
