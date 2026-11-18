-- Fire: drain, feeding, whole nights (GAME_SYSTEMS §12, D1).
local H = require("./harness")
local Fire = require("../src/shared/Fire")
local Cycle = require("../src/shared/Cycle")

local cfg = H.config()

local function woodAt(times: { number }): { Fire.Feed }
	local feeds = {}
	for _, t in times do
		table.insert(feeds, { t = t, kind = "wood" })
	end
	return feeds
end

H.test("drain = 0.5% + 0.0375% per living player", function()
	H.near(Fire.drainPerSecond(cfg, 1), 0.005375, 1e-12, "1 player")
	H.near(Fire.drainPerSecond(cfg, 8), 0.008, 1e-12, "8 players")
	H.near(Fire.drainPerSecond(cfg, 0), 0.005, 1e-12, "everyone downed")
	H.near(Fire.secondsLeft(0.6, Fire.drainPerSecond(cfg, 8)), 75, 1e-9, "unfed fire dies after about 75 s")
end)

H.test("1 player feeding 2 pieces survives (§12 acceptance)", function()
	local outcome = Fire.simulate(cfg, 1, woodAt({ 30, 60 }))
	H.ok(outcome.survived, "survived")
	H.near(outcome.level, 0.015, 1e-9, "level at dawn")
end)

H.test("8 players feeding 8 pieces in total lose (§12 acceptance)", function()
	local outcome = Fire.simulate(cfg, 8, woodAt({ 5, 15, 25, 35, 45, 55, 65, 75 }))
	H.ok(not outcome.survived, "lost")
	H.near(outcome.lostAt :: number, 105, 1e-9, "goes out at 1:45")
end)

H.test("feeding is capped at 100% and a dead fire stays dead", function()
	H.eq(Fire.feed(cfg, 0.99, "wood"), 1, "cap")
	H.near(Fire.feed(cfg, 0.5, "shard"), 0.56, 1e-12, "shard is +6%")
	H.eq(Fire.feed(cfg, 0, "wood"), 0, "dead fire")
	H.eq(Fire.step(cfg, 0.01, 0.008, 5), 0, "step floors at 0")
	H.eq(Fire.step(cfg, 0, 0.008, -5), 0, "no revival")
	H.throws(function()
		Fire.feedAmount(cfg, "coal" :: any)
	end, "unknown fuel")
end)

H.test("night modifiers: Gusty drains 25% faster, Starfall starts at 70%", function()
	local gusty = Cycle.modifier(cfg, "Gusty")
	local starfall = Cycle.modifier(cfg, "Starfall")
	H.near(Fire.drainPerSecond(cfg, 8, gusty), 0.01, 1e-12, "Gusty")
	H.eq(Fire.startLevel(cfg, starfall), 0.7, "Starfall")
	H.eq(Fire.startLevel(cfg, nil), 0.6, "normal start")
	H.near(Fire.simulate(cfg, 3, {}, starfall).lostAt :: number, 0.7 / 0.006125, 1e-9, "Starfall unfed")
end)

H.test("feeds after dawn are ignored and order doesn't matter", function()
	local a = Fire.simulate(cfg, 1, woodAt({ 90, 10, 50, 500 }))
	local b = Fire.simulate(cfg, 1, woodAt({ 10, 50, 90 }))
	H.eq(a.survived, b.survived, "same outcome")
	H.near(a.level, b.level, 1e-12, "same level")
end)

H.test("dawn Embers (§14): survived formula, caps, friend bonus, and the lost consolation", function()
	-- 10 + floor(60% / 10) = 16
	H.eq(Fire.dawnEmbers(cfg, true, 0.6, 0, 0), 16, "fire 60%, nothing else")
	-- 10 + 7 + 5 × 2 + 1 × 3 = 30
	H.eq(Fire.dawnEmbers(cfg, true, 0.7, 2, 3), 30, "0.7 must count as 7 tenths")
	H.eq(Fire.dawnEmbers(cfg, true, 0.79, 0, 0), 17, "79% floors to 7 tenths")
	-- Caps: revives at 4 (20), pieces at 6 (6). 10 + 10 + 20 + 6 = 46
	H.eq(Fire.dawnEmbers(cfg, true, 1, 9, 20), 46, "caps")
	-- Friend bonus: +10% each, max +30%. 16 × 1.2 = 19.2 → 19; 16 × 1.3 = 20.8 → 20
	H.eq(Fire.dawnEmbers(cfg, true, 0.6, 0, 0, 2), 19, "two friends")
	H.eq(Fire.dawnEmbers(cfg, true, 0.6, 0, 0, 5), 20, "friend bonus capped at +30%")
	H.eq(Fire.dawnEmbers(cfg, true, 0.01, 0, 0), 10, "barely survived")
	H.eq(Fire.dawnEmbers(cfg, false, 0, 4, 6, 3), 3, "lost: consolation only")
	H.eq(Fire.dawnEmbers(cfg, true, 0.6, -2, -1), 16, "negative counts never take Embers away")
end)

H.finish("fire")
