--!strict
-- Where a Glowling stands inside its base's fence (GAME_SYSTEMS §7). Pure and deterministic:
-- the position is a function of (plot, pad, server time), so the server checks a thief's reach
-- against the same spot every client draws, with nothing replicated per frame.
--
-- Display Glowlings wander: each pad has a home spot (spread over the yard), and every STEP
-- seconds the Glowling walks to a new point near it, then idles. Vault Glowlings sleep in a
-- ring by the den in the back corner. A Glowling being grabbed freezes at the grab's start
-- time (`frozenAt`). Positions are plot-local studs on the floor: x across, z from the gate
-- (-z) to the back (+z).

local Roam = {}

Roam.STEP = 7 -- seconds per wander: walk, then idle
Roam.WALK = 3.5 -- seconds of it spent walking
Roam.RANGE = 7 -- how far from its home spot a Glowling wanders
Roam.EDGE = 2.5 -- kept this far inside the fence
Roam.DEN = { x = -14, z = 16 } -- the den, from the plot centre (a 36 × 40 plot)
Roam.DEN_CLEAR = 6 -- wanderers keep out of the den's corner: this far past it on x or z

export type Area = { halfW: number, halfD: number }

-- A hash of three integers in [0, 1).
local function noise(a: number, b: number, c: number): number
	local h = bit32.bxor(a * 374761393, b * 668265263, c * 2147483647 % 2 ^ 31)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = (h * 1274126177) % 2 ^ 32
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return (h % 1000003) / 1000003
end

local function clampToYard(area: Area, x: number, z: number): (number, number)
	local hw, hd = area.halfW - Roam.EDGE, area.halfD - Roam.EDGE
	x = math.clamp(x, -hw, hw)
	z = math.clamp(z, -hd, hd)
	-- The den's corner is off limits: slide out diagonally to its nearer edge (continuous, so
	-- a walk past the den bends round it instead of jumping).
	local edgeX, edgeZ = Roam.DEN.x + Roam.DEN_CLEAR, Roam.DEN.z - Roam.DEN_CLEAR
	if x < edgeX and z > edgeZ then
		local out = math.min(edgeX - x, z - edgeZ)
		x += out
		z -= out
	end
	return x, z
end

-- The pad's home spot in the yard.
function Roam.home(area: Area, plotId: number, pad: number): (number, number)
	local hw, hd = area.halfW - Roam.EDGE, area.halfD - Roam.EDGE
	local x = (noise(plotId, pad, 1) * 2 - 1) * hw
	local z = (noise(plotId, pad, 2) * 2 - 1) * hd
	return clampToYard(area, x, z)
end

local function waypoint(area: Area, plotId: number, pad: number, k: number): (number, number)
	local hx, hz = Roam.home(area, plotId, pad)
	local a = noise(plotId * 31 + pad, k, 3) * math.pi * 2
	local r = math.sqrt(noise(plotId * 31 + pad, k, 4)) * Roam.RANGE
	return clampToYard(area, hx + math.cos(a) * r, hz + math.sin(a) * r)
end

-- Where a display Glowling is at server time `t`: x, z, its heading (radians about Y, 0 =
-- facing -z), and whether it is walking.
function Roam.at(area: Area, plotId: number, pad: number, t: number): (number, number, number, boolean)
	local shifted = t + noise(plotId, pad, 5) * Roam.STEP -- so a base's Glowlings don't move in step
	local k = math.floor(shifted / Roam.STEP)
	local into = shifted - k * Roam.STEP
	local ax, az = waypoint(area, plotId, pad, k)
	local bx, bz = waypoint(area, plotId, pad, k + 1)
	local heading = math.atan2(-(bx - ax), -(bz - az))
	if into >= Roam.WALK then
		return bx, bz, heading, false
	end
	local f = into / Roam.WALK
	f = f * f * (3 - 2 * f) -- ease in and out
	local x, z = clampToYard(area, ax + (bx - ax) * f, az + (bz - az) * f)
	return x, z, heading, true
end

-- Where a vault Glowling sleeps: the `index`-th of `count` spots round the den, facing out.
function Roam.denSpot(index: number, count: number): (number, number, number)
	local a = math.pi * 1.5 + (index - 0.5) / math.max(count, 1) * math.pi * 0.5 -- the yard side
	local r = 4.2
	local x, z = Roam.DEN.x + math.cos(a) * r, Roam.DEN.z + math.sin(a) * r
	return x, z, math.atan2(-(x - Roam.DEN.x), -(z - Roam.DEN.z))
end

-- The spot for a placed Glowling: frozen while grabbed, at the den when in the vault.
-- `vault` is the base's vault pad count (pads 1..vault are vault pads).
function Roam.spot(
	area: Area,
	plotId: number,
	pad: number,
	vault: number,
	t: number,
	frozenAt: number?
): (number, number, number, boolean)
	if pad <= vault then
		local x, z, h = Roam.denSpot(pad, vault)
		return x, z, h, false
	end
	local x, z, h = Roam.at(area, plotId, pad, frozenAt or t)
	return x, z, h, frozenAt == nil and select(4, Roam.at(area, plotId, pad, t))
end

return Roam
