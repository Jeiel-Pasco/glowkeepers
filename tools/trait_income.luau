-- How much pet traits raise a plot's income (GAME_SYSTEMS §31), measured with the real
-- Shared.Traits rules, for sim/sim_v3.py.
--
-- For each slot count it draws many collections (rarities by base odds, species from the
-- eligible pools, the best `slots` kept, "Place best" order: the best on pad 1), then runs
-- Traits.step for 30 minutes of 2 s ticks: time-averaged income with multipliers and
-- Overcharges, plus Forager pouches, divided by the same plot with no traits.
-- "arranged" also swaps pads greedily to raise the static multipliers, like an engaged player.
--
--   lune run tools/trait_income.luau
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Traits = require("../src/shared/Traits")
local Roll = require("../src/shared/Roll")

local cfg = serde.decode("json", fs.readFile("config/economy.json"))
local speciesCfg = serde.decode("json", fs.readFile("config/species.json"))
local species = {}
local pools = {}
for _, entry in speciesCfg.species do
	species[entry.id] = entry
	pools[entry.pool] = true
end

local seed = 12345
local function rng(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local weights, total = {}, 0
for i, rarity in cfg.rarities do
	weights[i] = 1 / rarity.oneIn
	total += weights[i]
end
local function rollRarity(): number
	local x = rng() * total
	for i, w in weights do
		x -= w
		if x <= 0 then
			return i
		end
	end
	return 1
end

local function collection(slots: number): { { sp: string, v: number } }
	local pets = {}
	for _ = 1, slots * 4 do
		local r = rollRarity()
		local options = {}
		for pool in pools do
			for _, id in Roll.eligible(cfg, speciesCfg, pool, r) do
				table.insert(options, id)
			end
		end
		local sp = options[math.floor(rng() * #options) + 1]
		table.insert(pets, { sp = sp, v = cfg.rarities[r].glowPerSec * (0.8 + 0.4 * rng()) })
	end
	table.sort(pets, function(a, b)
		return a.v > b.v
	end)
	local kept = {}
	for i = 1, slots do
		kept[i] = pets[i]
	end
	return kept
end

local function staticIncome(onPad: { [number]: { sp: string, v: number } }): number
	local placed = {}
	for pad, pet in onPad do
		placed[pad] = pet.sp
	end
	local mult = Traits.multipliers(cfg, species, placed, nil)
	local sum = 0
	for pad, pet in onPad do
		sum += pet.v * (mult[pad] or 1)
	end
	return sum
end

local function arrange(onPad: { [number]: { sp: string, v: number } }, slots: number)
	local best = staticIncome(onPad)
	for _ = 1, 3 do
		local improved = false
		for a = 1, slots do
			for b = a + 1, slots do
				onPad[a], onPad[b] = onPad[b], onPad[a]
				local value = staticIncome(onPad)
				if value > best + 1e-9 then
					best, improved = value, true
				else
					onPad[a], onPad[b] = onPad[b], onPad[a]
				end
			end
		end
		if not improved then
			break
		end
	end
end

local function measure(onPad: { [number]: { sp: string, v: number } }): number
	local placed, ids, base = {}, {}, 0
	for pad, pet in onPad do
		placed[pad] = pet.sp
		ids[pad] = tostring(pad) .. pet.sp
		base += pet.v
	end
	local timers = Traits.newTimers()
	local earned, seconds, tick = 0, 1800, 2
	for now = 0, seconds - tick, tick do
		local _, pouches = Traits.step(cfg, species, placed, ids, timers, now, rng)
		local mult = Traits.multipliers(cfg, species, placed, timers.over)
		local perSec = 0
		for pad, pet in onPad do
			perSec += pet.v * (mult[pad] or 1)
		end
		earned += perSec * tick
		for _, pad in pouches do
			earned += cfg.traits.forager.pouchSeconds * onPad[pad].v * (mult[pad] or 1)
		end
	end
	return earned / (base * seconds)
end

local TRIALS = 300
local out = {}
print("slots  placeBest  arranged")
for _, slots in { 8, 10, 12, 15, 18, 21, 24, 27, 30 } do
	local sumBest, sumArranged = 0, 0
	for _ = 1, TRIALS do
		local pets = collection(slots)
		local onPad = table.clone(pets)
		sumBest += measure(onPad)
		arrange(onPad, slots)
		sumArranged += measure(onPad)
	end
	local row = { slots = slots, placeBest = sumBest / TRIALS, arranged = sumArranged / TRIALS }
	table.insert(out, row)
	print(string.format("%5d  %9.3f  %8.3f", slots, row.placeBest, row.arranged))
end
fs.writeFile("sim/trait_income.json", serde.encode("json", out, true))
