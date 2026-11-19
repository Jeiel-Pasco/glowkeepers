-- Stalker: the brain's states, lone targets and repelling (GAME_SYSTEMS §13).
local H = require("./harness")
local Stalker = require("../src/shared/Stalker")

local cfg = H.config()
local fire = { x = 0, z = 0, radius = 30, lit = true }

local function sense(overrides: { [string]: any }?): any
	local s = { now = 100, nightElapsed = 60, repelled = false, candidate = nil, targetLone = true, touched = false }
	for key, value in overrides or {} do
		s[key] = value
	end
	return s
end

H.test("config: every lunge has at least the telegraph, and stalking is escapable", function()
	H.ok(cfg.stalker.stalkSeconds >= cfg.stalker.telegraphSeconds, "Stalk lasts at least the telegraph")
	H.ok(cfg.stalker.stalkSpeedMult < 1, "slower than the target while stalking")
	H.ok(cfg.stalker.lungeSpeedMult > 1, "faster than the target while lunging")
end)

H.test("dormant for the grace period, then prowls", function()
	local b = { state = "Dormant", since = 0 }
	H.eq(
		(Stalker.step(cfg, b, sense({ nightElapsed = cfg.cycle.stalkerGraceSeconds - 1 }))).state,
		"Dormant",
		"still dormant"
	)
	local nextBrain, event = Stalker.step(cfg, b, sense({ nightElapsed = cfg.cycle.stalkerGraceSeconds }))
	H.eq(nextBrain.state, "Prowl", "prowls")
	H.eq(event, "prowl", "event")
end)

H.test("prowl, stalk, lunge, then down or miss", function()
	local b, event = Stalker.step(cfg, { state = "Prowl", since = 0 }, sense({ candidate = 7 }))
	H.eq(b.state, "Stalk", "stalks a lone target")
	H.eq(b.target, 7, "the candidate")
	H.eq(event, "stalk", "event")
	local stalkStart = b.since

	local early = Stalker.step(cfg, b, sense({ now = stalkStart + cfg.stalker.stalkSeconds - 0.1 }))
	H.eq(early.state, "Stalk", "no lunge before stalkSeconds")
	b, event = Stalker.step(cfg, b, sense({ now = stalkStart + cfg.stalker.stalkSeconds }))
	H.eq(b.state, "Lunge", "lunges")
	H.ok(b.since - stalkStart >= cfg.stalker.telegraphSeconds, "telegraphed for at least 2 s")

	local hit, hitEvent = Stalker.step(cfg, b, sense({ now = b.since + 0.5, touched = true }))
	H.eq(hit.state, "Retreat", "retreats after a touch")
	H.eq(hitEvent, "down", "downs the target")
	local miss, missEvent = Stalker.step(cfg, b, sense({ now = b.since + cfg.stalker.lungeSeconds }))
	H.eq(miss.state, "Retreat", "retreats after a miss")
	H.eq(missEvent, "miss", "missed")
end)

H.test("a target that reaches friends or the fire is lost; retreat ends after 10 s", function()
	local b, event = Stalker.step(cfg, { state = "Stalk", since = 99, target = 7 }, sense({ targetLone = false }))
	H.eq(b.state, "Prowl", "back to prowling")
	H.eq(event, "lost", "lost the target")
	local r = { state = "Retreat", since = 100 }
	H.eq((Stalker.step(cfg, r, sense({ now = 109.9, repelled = true }))).state, "Retreat", "still retreating")
	H.eq((Stalker.step(cfg, r, sense({ now = 110 }))).state, "Prowl", "prowls after 10 s")
end)

H.test("repelled by the lit fire or a group of 3, from any active state", function()
	local players = { { x = 40, z = 0 }, { x = 44, z = 0 }, { x = 40, z = 5 } }
	H.ok(Stalker.repelled(cfg, { x = 42, z = 2 }, players, fire), "a group of 3 within 12 studs")
	H.ok(not Stalker.repelled(cfg, { x = 42, z = 2 }, { players[1], players[2] }, fire), "2 isn't a group")
	H.ok(Stalker.repelled(cfg, { x = 10, z = 0 }, {}, fire), "inside the lit fire")
	H.ok(
		not Stalker.repelled(cfg, { x = 10, z = 0 }, {}, { x = 0, z = 0, radius = 30, lit = false }),
		"an out fire repels nothing"
	)
	for _, state in { "Prowl", "Stalk", "Lunge" } do
		local b = Stalker.step(cfg, { state = state, since = 99, target = 7 }, sense({ repelled = true }))
		H.eq(b.state, "Retreat", `{state} retreats when repelled`)
	end
end)

H.test("only lone players outside the fire are targets", function()
	local living = {
		{ x = 10, z = 0 }, -- by the fire
		{ x = 50, z = 0 }, -- with a friend
		{ x = 55, z = 0 },
		{ x = 100, z = 0 }, -- alone
	}
	H.eq(Stalker.pickTarget(cfg, { x = 60, z = 0 }, living, fire), 4, "the lone one, though farther")
	H.eq(Stalker.pickTarget(cfg, { x = 60, z = 0 }, { living[1], living[2], living[3] }, fire), nil, "nobody lone")
	local out = { x = 0, z = 0, radius = 30, lit = false }
	H.eq(Stalker.pickTarget(cfg, { x = 12, z = 0 }, { living[1] }, out), 1, "the fire is out: nobody is safe there")
end)

H.test("speeds: 0.9 of the target stalking, 1.25 lunging, a still target counts as walking", function()
	H.near(Stalker.speed(cfg, "Stalk", 22), 22 * 0.9, 1e-9, "stalk")
	H.near(Stalker.speed(cfg, "Lunge", 22), 22 * 1.25, 1e-9, "lunge")
	H.near(Stalker.speed(cfg, "Stalk", 0), cfg.movement.walk * 0.9, 1e-9, "still target")
	H.eq(Stalker.speed(cfg, "Prowl", 30), cfg.stalker.prowlSpeed, "prowl")
end)

H.finish("stalker")
