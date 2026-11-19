-- Where Glowlings wander inside the fence (Shared.Roam).
local H = require("./harness")
local Roam = require("../src/shared/Roam")

local AREA = { halfW = 18, halfD = 20 }

H.test("wanderers stay inside the fence and out of the den", function()
	for plot = 1, 8 do
		for pad = 7, 30 do
			for t = 0, 200, 0.7 do
				local x, z = Roam.at(AREA, plot, pad, t)
				H.eq(
					math.abs(x) <= 18 - Roam.EDGE + 1e-6 and math.abs(z) <= 20 - Roam.EDGE + 1e-6,
					true,
					`{plot}/{pad}/{t}`
				)
				local inDen = x < Roam.DEN.x + Roam.DEN_CLEAR - 1e-6 and z > Roam.DEN.z - Roam.DEN_CLEAR + 1e-6
				H.eq(inDen, false, `den {plot}/{pad}/{t}`)
			end
		end
	end
end)

H.test("wandering is smooth and the same everywhere", function()
	local fastest = 0
	for pad = 7, 30 do
		local lx, lz = Roam.at(AREA, 3, pad, 0)
		for t = 0.1, 100, 0.1 do
			local x, z = Roam.at(AREA, 3, pad, t)
			fastest = math.max(fastest, math.sqrt((x - lx) ^ 2 + (z - lz) ^ 2) / 0.1)
			lx, lz = x, z
		end
		local a1, b1 = Roam.at(AREA, 3, pad, 42.5)
		local a2, b2 = Roam.at(AREA, 3, pad, 42.5)
		H.eq(a1 == a2 and b1 == b2, true)
	end
	H.eq(fastest < 12, true, `fastest {fastest} studs/s`)
end)

H.test("a grabbed Glowling freezes and vault Glowlings sleep by the den", function()
	local x1, z1 = Roam.spot(AREA, 2, 12, 3, 50, 40)
	local x2, z2 = Roam.spot(AREA, 2, 12, 3, 90, 40)
	H.eq(x1 == x2 and z1 == z2, true)
	local _, _, _, walking = Roam.spot(AREA, 2, 12, 3, 90, 40)
	H.eq(walking, false)
	for pad = 1, 3 do
		local x, z = Roam.spot(AREA, 2, pad, 3, 10)
		local d = math.sqrt((x - Roam.DEN.x) ^ 2 + (z - Roam.DEN.z) ^ 2)
		H.eq(d < 5 and math.abs(x) < 18 and math.abs(z) < 20, true)
	end
end)

H.test("a base's Glowlings spread over the yard", function()
	local left, right, front, back = 0, 0, 0, 0
	for pad = 7, 30 do
		local x, z = Roam.home(AREA, 5, pad)
		left += if x < 0 then 1 else 0
		right += if x >= 0 then 1 else 0
		front += if z < 0 then 1 else 0
		back += if z >= 0 then 1 else 0
	end
	H.eq(math.min(left, right, front, back) >= 5, true, `{left} {right} {front} {back}`)
end)

H.finish("roam")
