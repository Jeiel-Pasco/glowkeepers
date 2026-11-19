-- Rebirth: the gate, and what is wiped and kept (GAME_SYSTEMS §15, D3).
local H = require("./harness")
local Rebirth = require("../src/shared/Rebirth")
local Economy = require("../src/shared/Economy")

local cfg = H.config()

local function valueOf(record: any): number
	return Economy.glowlingValue(cfg, record.r, record.m, record.s)
end

-- A profile at Star 1: g1 (Rare) and g2 (Epic) in the vault, g3 (Rare) and g4 (Uncommon) on
-- display, g5 (Legendary) and g6 (Common) in storage.
local function profile(): any
	local data = {
		glow = 5e6,
		glowSinceRebirth = 900000,
		embers = 42,
		stars = 1,
		lockCharges = 2,
		up = { lantern = 7, boots = 3, slots = 4 },
		glowlings = {},
		vault = { ["1"] = "g1", ["2"] = "g2" },
		display = { ["5"] = "g3", ["6"] = "g4" },
		dex = { mothlet = 1 },
		stats = { rebirths = 1 },
	}
	for i, r in { 3, 4, 3, 2, 5, 1 } do
		local id = `g{i}`
		data.glowlings[id] = { id = id, sp = "mothlet", r = r, m = 0, s = 1, src = "lure", at = i, by = 1 }
	end
	return data
end

H.test("gate: the requirement, then not carrying, then nothing held", function()
	local need = Economy.rebirthRequirement(cfg, 1)
	local c = { glowSinceRebirth = need, requirement = need, carrying = false, busy = false }
	H.ok((Rebirth.canRebirth(c)), "exactly the requirement")
	c.glowSinceRebirth = need - 1
	H.eq(select(2, Rebirth.canRebirth(c)), "too_early", "one Glow short")
	c.glowSinceRebirth = need
	c.carrying = true
	H.eq(select(2, Rebirth.canRebirth(c)), "carrying", "carrying a stolen one")
	c.carrying = false
	c.busy = true
	H.eq(select(2, Rebirth.canRebirth(c)), "busy", "a Glowling held by a thief or trade")
	H.eq(Rebirth.remaining(600000, 800000), 200000, "remaining")
	H.eq(Rebirth.remaining(900000, 800000), 0, "never below 0")
end)

H.test("apply: wipes and keeps exactly the D3 lists", function()
	local data = profile()
	local result = Rebirth.apply(data, valueOf)
	H.eq(result.best, "g5", "the Legendary in storage is the best outside the vault")
	H.eq(table.concat(result.removed, ","), "g3,g4,g6", "display and storage wiped")
	H.ok(data.glowlings.g1 ~= nil and data.glowlings.g2 ~= nil, "vault kept")
	H.ok(data.glowlings.g5 ~= nil, "best kept")
	H.eq(next(data.display), nil, "display empty")
	H.eq(data.vault["1"], "g1", "vault pads unchanged")
	H.eq(data.glow, 0, "Glow wiped")
	H.eq(data.glowSinceRebirth, 0, "progress reset")
	H.eq(data.up.lantern + data.up.boots + data.up.slots, 0, "upgrades wiped (slots back to 8)")
	H.eq(data.stars, 2, "+1 Star")
	H.eq(data.stats.rebirths, 2, "counted")
	H.eq(data.embers, 42, "Embers kept")
	H.eq(data.lockCharges, 2, "Lock Charges kept")
	H.eq(data.dex.mothlet, 1, "Glowdex kept")
end)

H.test("best outside the vault: on display counts too; ties go to the oldest", function()
	local data = profile()
	data.glowlings.g5 = nil
	H.eq(Rebirth.bestOutsideVault(data, valueOf), "g3", "the Rare on display")
	data.glowlings.g7 = { id = "g7", sp = "mothlet", r = 3, m = 0, s = 1, src = "lure", at = 0, by = 1 }
	H.eq(Rebirth.bestOutsideVault(data, valueOf), "g7", "same value, older")
	local empty = { glowlings = { g1 = data.glowlings.g1 }, vault = { ["1"] = "g1" } }
	H.eq(Rebirth.bestOutsideVault(empty, valueOf), nil, "only the vault: nothing extra kept")
end)

H.finish("rebirth")
