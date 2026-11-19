-- Shield: the new-player shield's play-time limit (GAME_SYSTEMS §11).
local H = require("./harness")
local Shield = require("../src/shared/Shield")

local cfg = H.config()
local max = cfg.shield.maxPlaySeconds

H.test("45 minutes of play", function()
	H.eq(max, 45 * 60, "the D2 limit")
end)

H.test("play time accumulates across sessions and ends the shield at the limit", function()
	local total, ended = Shield.accrue(cfg, 0, 600)
	H.eq(total, 600, "first session")
	H.ok(not ended, "still shielded")
	total, ended = Shield.accrue(cfg, total, max - 601) -- a rejoin carries on from the saved time
	H.ok(not ended, "one second left")
	total, ended = Shield.accrue(cfg, total, 1)
	H.eq(total, max, "at the limit")
	H.ok(ended, "ends")
	H.eq((Shield.accrue(cfg, 100, -5)), 100, "a negative step adds nothing")
end)

H.test("ends-at counts down only the play time left", function()
	H.eq(Shield.endsAt(cfg, 600, 1000), 1000 + max - 600, "time left from now")
	H.eq(Shield.endsAt(cfg, max + 10, 1000), 1000, "never in the past")
end)

H.finish("shield")
