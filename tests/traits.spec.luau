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

H.test("mates are every other Glowling in the base", function()
	local mates = Traits.mates({ [1] = "a", [9] = "b", [30] = "c" }, 9)
	H.eq(#mates, 2)
	H.eq(mates[1], 1)
	H.eq(mates[2], 30)
end)

H.test("family link: +5% per other same-family Glowling in the base, up to +10%", function()
	-- glimmermouse, mothlet, fireflypip, owlumen: Lantern family, none of them a Harmonizer
	local m = Traits.multipliers(cfg, species, { [8] = "glimmermouse", [9] = "mothlet" })
	H.ok(near(m[8], 1.05) and near(m[9], 1.05), "both rise")
	m = Traits.multipliers(cfg, species, { [7] = "glimmermouse", [30] = "mothlet" })
	H.ok(near(m[7], 1.05) and near(m[30], 1.05), "anywhere in the base")
	m = Traits.multipliers(
		cfg,
		species,
		{ [16] = "glimmermouse", [15] = "mothlet", [17] = "fireflypip", [8] = "owlumen", [24] = "glimmermouse" }
	)
	H.ok(near(m[16], 1.10), "capped at +10%")
	m = Traits.multipliers(cfg, species, { [8] = "glimmermouse", [9] = "puffwick" })
	H.ok(near(m[8], 1), "other families don't link")
end)

H.test("Harmonizer boosts same-family Glowlings in the base, not itself", function()
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

H.test("Guardian grab time: anywhere in the base, higher floors, at most 1.5 s", function()
	H.eq(Traits.grabBonus(cfg, species, { [8] = "sparkhop" }, 9, true), 0.5)
	H.eq(Traits.grabBonus(cfg, species, { [8] = "sparkhop" }, 8, true), 0.5, "its own pad")
	H.eq(Traits.grabBonus(cfg, species, { [8] = "sparkhop" }, 30, true), 0.5, "across the base")
	H.eq(Traits.grabBonus(cfg, species, { [8] = "glimmermouse" }, 30, true), 0, "no Guardian")
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

local function zero(): number
	return 0
end

H.test("Infuser: Overcharge on another Glowling every 60 s, ×1.5 for 30 s", function()
	local placed = { [8] = "glimmermouse", [9] = "mothlet" } -- Mothlet is a Lantern Infuser
	local ids = { [8] = "a", [9] = "b" }
	local timers = Traits.newTimers()
	local changed = Traits.step(cfg, species, placed, ids, timers, 0, zero)
	H.ok(not changed and next(timers.over) == nil, "nothing at once")
	changed = Traits.step(cfg, species, placed, ids, timers, 59, zero)
	H.ok(not changed, "not before 60 s")
	changed = Traits.step(cfg, species, placed, ids, timers, 60, zero)
	H.ok(changed and timers.over[8] ~= nil, "the other Glowling is overcharged")
	local m = Traits.multipliers(cfg, species, placed, timers.over)
	H.ok(near(m[8], 1.05 * 1.5), `link × Overcharge {m[8]}`)
	H.ok(near(m[9], 1.05), "the Infuser itself isn't")
	H.ok(not Traits.step(cfg, species, placed, ids, timers, 89, zero), "still running")
	H.ok(Traits.step(cfg, species, placed, ids, timers, 90, zero) and timers.over[8] == nil, "ends after 30 s")
end)

H.test("Overcharge ends when its Glowling leaves, and never stacks", function()
	local placed = { [8] = "glimmermouse", [9] = "mothlet", [10] = "mothlet" }
	local ids = { [8] = "a", [9] = "b", [10] = "c" }
	local timers = Traits.newTimers()
	Traits.step(cfg, species, placed, ids, timers, 0, zero)
	Traits.step(cfg, species, placed, ids, timers, 60, zero)
	local count = 0
	for _ in timers.over do
		count += 1
	end
	H.eq(count, 2, "two Infusers, two different targets") -- 9 overcharges 8, 10 overcharges 9
	H.ok(timers.over[8] ~= nil and timers.over[9] ~= nil, "8 and 9")
	placed[8], ids[8] = nil, nil
	H.ok(Traits.step(cfg, species, placed, ids, timers, 61, zero), "changed")
	H.eq(timers.over[8], nil, "moved away: over")
	ids[9] = "z"
	Traits.step(cfg, species, placed, ids, timers, 62, zero)
	H.eq(timers.over[9], nil, "a different Glowling on the pad: over")
end)

H.test("Aurora Lynx overcharges up to 6 pads anywhere every 45 s", function()
	local placed, ids = { [1] = "auroralynx" }, { [1] = "lynx" }
	for pad = 7, 16 do
		placed[pad], ids[pad] = "puffwick", `p{pad}`
	end
	local timers = Traits.newTimers()
	Traits.step(cfg, species, placed, ids, timers, 0, zero)
	H.ok(Traits.step(cfg, species, placed, ids, timers, 45, zero), "fires at 45 s")
	local count = 0
	for _ in timers.over do
		count += 1
	end
	H.eq(count, 6)
end)

H.test("Forager: a pouch every 90 s", function()
	local placed, ids = { [8] = "glimmermouse" }, { [8] = "a" }
	local timers = Traits.newTimers()
	local _, pouches = Traits.step(cfg, species, placed, ids, timers, 0, zero)
	H.eq(#pouches, 0)
	_, pouches = Traits.step(cfg, species, placed, ids, timers, 90, zero)
	H.eq(pouches[1], 8)
	_, pouches = Traits.step(cfg, species, placed, ids, timers, 120, zero)
	H.eq(#pouches, 0, "once per period")
	_, pouches = Traits.step(cfg, species, placed, ids, timers, 180, zero)
	H.eq(pouches[1], 8)
end)

H.test("with Overcharge the cap holds (random plots)", function()
	local state = 11
	local function rand(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	local hit = false
	for _ = 1, 1000 do
		local placed, over = {}, {}
		for pad = 1, 30 do
			if rand() < 0.8 then
				placed[pad] = ids[1 + math.floor(rand() * #ids)]
				if rand() < 0.5 then
					over[pad] = true
				end
			end
		end
		for _, mult in Traits.multipliers(cfg, species, placed, over) do
			H.ok(mult <= cfg.traits.cap + 1e-9, `over the cap: {mult}`)
			hit = hit or near(mult, cfg.traits.cap)
		end
	end
	H.ok(hit, "the cap is reached with Overcharge")
end)

H.finish("traits")
