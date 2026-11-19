-- Exploit flags and the graduated response (TECH_SPEC §8).
local H = require("./harness")
local Moderation = require("../src/shared/Moderation")

local cfg = H.config()

H.test("flags add points; kick at the threshold; the count restarts after a kick", function()
	local flags = Moderation.shape({})
	H.eq(Moderation.record(cfg, flags, "Carry", "speed", 100), "flag") -- 4
	H.eq(Moderation.record(cfg, flags, "flood", "Roll:flood", 101), "flag") -- 7
	H.eq(Moderation.record(cfg, flags, "invalid", "Place:invalid", 102), "flag") -- 9
	H.eq(Moderation.record(cfg, flags, "rejected", "Place:not owned", 103), "kick") -- 10
	H.eq(flags.kicks, 1)
	H.eq(flags.counts.Carry, 1)
	H.eq(Moderation.recentPoints(cfg, flags, 103), 0, "earlier flags don't count again")
	H.eq(Moderation.record(cfg, flags, "rejected", "x", 104), "flag")
end)

H.test("old flags fall out of the window; unknown kinds are worth 1; log is capped", function()
	local flags = Moderation.shape({})
	Moderation.record(cfg, flags, "Carry", "a", 1)
	Moderation.record(cfg, flags, "Carry", "b", 2)
	H.eq(Moderation.recentPoints(cfg, flags, 3), 8)
	H.eq(Moderation.recentPoints(cfg, flags, 2 + cfg.moderation.windowSeconds), 0)
	H.eq(Moderation.points(cfg, "whatever"), 1)
	for i = 1, cfg.moderation.logKeep + 5 do
		Moderation.record(cfg, flags, "x", tostring(i), 10000 + i * 1000)
	end
	H.eq(#flags.log, cfg.moderation.logKeep)
	H.eq(Moderation.record(cfg, flags, "Carry", "c", 1e9, 4), "kick", "kickAt override")
end)

H.test("shape repairs a malformed table", function()
	local flags = Moderation.shape({ log = 5, kicks = "x" })
	H.eq(type(flags.log), "table")
	H.eq(flags.kicks, 0)
	H.eq(flags.lastKick, 0)
end)

H.finish("moderation")
