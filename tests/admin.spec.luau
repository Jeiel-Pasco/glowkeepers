-- Admin command rules (TECH_SPEC §13).
local H = require("./harness")
local Commands = require("../src/server/Admin/Commands")

local cfg = H.config()
local species = { glimmoth = true }

local function why(cmd: string, target: number, arg: string): string?
	local _, reason = Commands.parse(cfg, species, cmd, target, arg)
	return reason
end

H.test("parse: targets, amounts, species, rarity, reasons", function()
	H.eq(why("nope", 1, ""), "unknown command")
	H.eq(why("lookup", 0, ""), "needs a target user id")
	H.eq(why("live_get", 0, ""), nil)
	local p = Commands.parse(cfg, species, "embers", 5, " 250  refund for bug ") :: any
	H.eq(p.amount, 250)
	H.eq(p.reason, "refund for bug")
	H.eq(why("embers", 5, "250"), "needs a reason")
	H.eq(why("embers", 5, "2.5 x"), `amount must be a whole number 1..{cfg.admin.maxEmbers}`)
	H.eq(why("embers", 5, `{cfg.admin.maxEmbers + 1} x`), `amount must be a whole number 1..{cfg.admin.maxEmbers}`)
	local g = Commands.parse(cfg, species, "glowling", 5, "glimmoth 4 lost to a bug") :: any
	H.eq(g.species, "glimmoth")
	H.eq(g.rarity, 4)
	H.eq(why("glowling", 5, "nothing 4 x"), "unknown species")
	H.eq(why("glowling", 5, "glimmoth 9 x"), `rarity must be 1..{#cfg.rarities}`)
	H.eq(why("kick", 5, "  "), "needs a reason")
	H.eq(why("erase", 5, ""), "needs the erasure request id")
end)

H.test("ban: days, permanent, ladder", function()
	H.eq((Commands.parse(cfg, species, "ban", 5, "7 dupe") :: any).days, 7)
	H.eq((Commands.parse(cfg, species, "ban", 5, "-1 dupe") :: any).days, -1)
	H.eq((Commands.parse(cfg, species, "ban", 5, "next dupe") :: any).ladder, true)
	H.eq(why("ban", 5, "0 x"), "days must be a whole number ≥ 1, -1 (permanent) or next")
	H.eq(why("ban", 5, "next"), "needs a reason")
	H.eq(Commands.ladderDays(cfg, 0), 1)
	H.eq(Commands.ladderDays(cfg, 1), 7)
	H.eq(Commands.ladderDays(cfg, 2), -1)
	H.eq(Commands.ladderDays(cfg, 9), -1)
end)

H.test("versions and rollback: unix time, rollback needs a reason", function()
	H.eq((Commands.parse(cfg, species, "versions", 5, "") :: any).at, nil, "default now")
	H.eq((Commands.parse(cfg, species, "versions", 5, "1795000000") :: any).at, 1795000000)
	H.eq(why("versions", 5, "yesterday"), "time must be a unix timestamp in seconds")
	H.eq(why("rollback", 5, "1795000000"), "needs a reason")
	H.eq(why("rollback", 5, ""), "time must be a unix timestamp in seconds")
	local r = Commands.parse(cfg, species, "rollback", 5, "1795000000 dupe cleanup") :: any
	H.eq(r.at, 1795000000)
	H.eq(r.reason, "dupe cleanup")
	H.eq(why("rollback", 0, "1 x"), "needs a target user id")
end)

H.test("diff lists changed, added and removed leaves", function()
	local lines = Commands.diff(
		{ killSwitches = { trading = false, stealing = false }, codes = { A = { embers = 5 } } },
		{ killSwitches = { trading = true, stealing = false }, event = { id = "x" } }
	)
	H.eq(table.concat(lines, "|"), "codes.A.embers: 5 → ∅|event.id: ∅ → x|killSwitches.trading: false → true")
	H.eq(#Commands.diff({ a = 1 }, { a = 1 }), 0)
end)

H.test("the AdminCommand remote allows exactly these commands", function()
	local Net = require("../src/shared/Net") :: any
	H.eq(table.concat(Net.remotes.AdminCommand.args[1].values, ","), table.concat(Commands.LIST, ","))
end)

H.finish("admin")
