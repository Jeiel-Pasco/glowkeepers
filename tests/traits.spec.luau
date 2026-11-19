-- Pet traits v1 (GAME_SYSTEMS §31).
local H = require("./harness")
local Traits = require("../src/shared/Traits")

local cfg = H.config()
local species = {}
local ids = {}
for _, entry in H.json("config/species.json").species do
	species[entry.id] = entry
	table.insert(ids, entry.id)
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

H.test("neighbours share an edge on the pad grid", function()
	H.eq(#Traits.PAD_POS, 30)
	local function has(list, n)
		return table.find(list, n) ~= nil
	end
	H.ok(has(Traits.neighbours(1), 3) and not has(Traits.neighbours(1), 2), "side strip runs front to back")
	H.ok(has(Traits.neighbours(7), 8) and has(Traits.neighbours(7), 15), "rows and columns")
	H.ok(not has(Traits.neighbours(7), 5), "the strips don't touch the rows")
	H.eq(#Traits.neighbours(16), 4, "a middle pad has four")
end)

H.test("family link: +5% per same-family neighbour, up to +10%", function()
	-- glimmermouse, mothlet, fireflypip, owlumen: Lantern family, none of them a Harmonizer
	local m = Traits.multipliers(cfg, species, { [8] = "glimmermouse", [9] = "mothlet" })
	H.ok(near(m[8], 1.05) and near(m[9], 1.05), "both rise")
	m = Traits.multipliers(cfg, species, { [8] = "glimmermouse", [10] = "mothlet" })
	H.ok(near(m[8], 1) and near(m[10], 1), "two pads apart: nothing")
	m = Traits.multipliers(
		cfg,
		species,
		{ [16] = "glimmermouse", [15] = "mothlet", [17] = "fireflypip", [8] = "owlumen", [24] = "glimmermouse" }
	)
	H.ok(near(m[16], 1.10), "capped at +10%")
	m = Traits.multipliers(cfg, species, { [8] = "glimmermouse", [9] = "puffwick" })
	H.ok(near(m[8], 1), "other families don't link")
end)

H.test("Harmonizer boosts same-family neighbours, not itself", function()
	local m = Traits.multipliers(cfg, species, { [8] = "glimmermouse", [9] = "lanternbug" })
	H.ok(near(m[8], 1.05 * 1.15), `neighbour {m[8]}`)
	H.ok(near(m[9], 1.05), `harmonizer itself {m[9]}`)
	m = Traits.multipliers(cfg, species, { [16] = "glimmermouse", [15] = "lanternbug", [17] = "fuzzlight" })
	H.ok(near(m[16], 1.10 * 1.15), "two Harmonizers don't stack")
end)

H.test("apex species work on the whole plot, and the best one counts", function()
	local m = Traits.multipliers(cfg, species, { [7] = "puffwick", [30] = "lunadrake" })
	H.ok(near(m[7], 1.25) and near(m[30], 1.25), "Lunadrake +25% on every pad")
	m = Traits.multipliers(cfg, species, { [7] = "puffwick", [20] = "skywhalecalf", [30] = "lunadrake" })
	H.ok(near(m[7], 1.25), "whole-plot bonuses don't stack")
end)

H.test("no Glowling's multiplier ever exceeds the cap (random plots)", function()
	local state = 7
	local function rand(): number -- an LCG: Lune has no Random
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	local worst = 0
	for _ = 1, 2000 do
		local placed = {}
		for pad = 1, 30 do
			if rand() < 0.8 then
				placed[pad] = ids[1 + math.floor(rand() * #ids)]
			end
		end
		for _, mult in Traits.multipliers(cfg, species, placed) do
			worst = math.max(worst, mult)
			H.ok(mult >= 1, "never below 1")
		end
	end
	H.ok(worst <= cfg.traits.cap + 1e-9, `worst {worst}`)
	-- the best combination today (two links, a Harmonizer, Lunadrake) is ×1.581: the cap guards tuning
	local m = Traits.multipliers(
		cfg,
		species,
		{ [16] = "glimmermouse", [15] = "lanternbug", [17] = "mothlet", [30] = "lunadrake" }
	)
	H.ok(near(m[16], 1.10 * 1.15 * 1.25), `best {m[16]}`)
	H.ok(worst <= m[16] + 1e-9, "the random plots found nothing above it")
end)

H.test("Guardian grab time: neighbours, higher floors, whole plot, at most 1.5 s", function()
	H.eq(Traits.grabBonus(cfg, species, { [8] = "sparkhop" }, 9, true), 0.5)
	H.eq(Traits.grabBonus(cfg, species, { [8] = "sparkhop" }, 8, true), 0.5, "its own pad")
	H.eq(Traits.grabBonus(cfg, species, { [8] = "sparkhop" }, 10, true), 0)
	H.eq(
		Traits.grabBonus(cfg, species, { [8] = "sparkhop", [10] = "gloomraven" }, 9, true),
		1.0,
		"Rare floor, best counts"
	)
	H.eq(Traits.grabBonus(cfg, species, { [1] = "eldersapling" }, 20, true), 1.0, "Elder Sapling: any display pad")
	H.eq(Traits.grabBonus(cfg, species, { [1] = "eldersapling" }, 20, false), 0, "not vault pads")
	H.eq(Traits.grabBonus(cfg, species, { [1] = "eldersapling", [8] = "gloomraven" }, 9, true), 1.5, "capped")
end)

H.test("floors come from minRarity", function()
	H.eq(Traits.floor(cfg, species.glimmermouse), 1)
	H.eq(Traits.floor(cfg, species.gloomraven), 3)
	H.eq(Traits.floor(cfg, species.lunadrake), 5)
end)

H.finish("traits")
