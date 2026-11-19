-- Glowling look ladder (CONTENT §A1, D24).
local H = require("./harness")
local RarityLook = require("../src/shared/RarityLook")

H.test("the ladder only adds: form and scale never drop, forms at Epic and Mythic", function()
	for r = 2, 7 do
		local a, b = RarityLook.look(r - 1), RarityLook.look(r)
		H.ok(b.form >= a.form, `form {r}`)
		H.ok(b.scale >= a.scale, `scale {r}`)
		H.ok(b.light > a.light, `light {r}`)
	end
	H.eq(RarityLook.look(3).form, 1)
	H.eq(RarityLook.look(4).form, 2)
	H.eq(RarityLook.look(6).form, 3)
	H.eq(RarityLook.look(5).scale, 1.08)
	H.eq(RarityLook.look(6).scale, 1.15)
	H.eq(RarityLook.look(7).scale, 1.25)
	H.ok(RarityLook.look(7).prismatic and not RarityLook.look(6).prismatic, "only Secret is prismatic")
	H.eq(RarityLook.look(0), RarityLook.look(1), "clamped low")
	H.eq(RarityLook.look(99), RarityLook.look(7), "clamped high")
end)

H.test("tones are stable per species and every family has a glow", function()
	H.eq(RarityLook.hash("moonbun"), RarityLook.hash("moonbun"))
	H.ok(RarityLook.hash("moonbun") ~= RarityLook.hash("mossbear"), "different ids differ")
	H.eq(RarityLook.tone("moonbun"), RarityLook.tone("moonbun"))
	local species = H.json("config/species.json")
	for _, entry in species.species do
		H.ok(RarityLook.FAMILY_GLOW[entry.family] ~= nil, `{entry.id} glow`)
		H.ok(RarityLook.RIGS[entry.rig] ~= nil, `{entry.id} rig`)
	end
	H.eq(RarityLook.glow(nil), RarityLook.FAMILY_GLOW.Lantern)
	H.eq(RarityLook.hash("a"), 0xe40c292c, "FNV-1a reference value")
	local used = {}
	for _, entry in species.species do
		used[RarityLook.tone(entry.id)] = true
	end
	local count = 0
	for _ in used do
		count += 1
	end
	H.ok(count >= 6, `the 40 species spread over the tones ({count} of 8 used)`)
end)

H.test("lights go to the rarest pads, at most the cap", function()
	local pads = {}
	for n = 1, 12 do
		pads[tostring(n)] = { r = if n == 9 then 7 elseif n == 3 then 5 else 1 }
	end
	local picks = RarityLook.lightPicks(pads, 8)
	local count = 0
	for _ in picks do
		count += 1
	end
	H.eq(count, 8)
	H.ok(picks["9"] and picks["3"], "rarest first")
	H.ok(picks["1"] and not picks["12"], "ties to the lower pad")
	H.eq(next(RarityLook.lightPicks({}, 8)), nil)
end)

H.finish("raritylook")
