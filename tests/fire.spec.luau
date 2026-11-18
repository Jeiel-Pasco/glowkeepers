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

H.finish("fire")
