-- Campfire look states (Design & Asset Bible §5B).
local H = require("./harness")
local FireLook = require("../src/shared/FireLook")

H.test("states by fire level, nil by day", function()
	H.eq(FireLook.state(nil), "Day")
	H.eq(FireLook.state(1), "Roaring")
	H.eq(FireLook.state(0.75), "Roaring")
	H.eq(FireLook.state(0.7499), "Steady")
	H.eq(FireLook.state(0.40), "Steady")
	H.eq(FireLook.state(0.3999), "Flickering")
	H.eq(FireLook.state(0.15), "Flickering")
	H.eq(FireLook.state(0.01), "Dying")
	H.eq(FireLook.state(0), "Cold")
end)

H.test("the fire shrinks and dims as the level drops", function()
	local order = { "Roaring", "Steady", "Flickering", "Dying", "Cold" }
	for i = 1, #order - 1 do
		local a, b = FireLook.LOOKS[order[i]], FireLook.LOOKS[order[i + 1]]
		H.ok(a.flameSize > b.flameSize, `{order[i]} flame > {order[i + 1]}`)
		H.ok(a.lightRange > b.lightRange, `{order[i]} light > {order[i + 1]}`)
	end
	H.ok(FireLook.LOOKS.Roaring.lightRange >= 40, "a roaring fire lights past the 30-stud ring")
	H.eq(FireLook.LOOKS.Cold.coreScale, 0, "no flame when cold")
end)

H.test("only warning states pulse; the pulse stays within 30–100% of the glow", function()
	H.eq(FireLook.runeGlow(FireLook.LOOKS.Roaring, 0.3), FireLook.LOOKS.Roaring.runeGlow)
	local look = FireLook.LOOKS.Flickering
	local low, high = math.huge, -math.huge
	for i = 0, 200 do
		local g = FireLook.runeGlow(look, i / 50)
		low, high = math.min(low, g), math.max(high, g)
	end
	H.ok(low >= look.runeGlow * 0.3 - 1e-9 and high <= look.runeGlow + 1e-9, "range")
	H.ok(high - low > 0.3 * look.runeGlow, "it visibly pulses")
end)

H.finish("firelook")
