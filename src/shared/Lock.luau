--!strict
-- Base Lock rules (GAME_SYSTEMS §11). Pure: no requires and no engine calls.
-- A tap closes the base for lock.activeSeconds; then it recharges for lock.rechargeSeconds.
-- A Lock Charge skips the recharge. No locks at night, and not while carrying a stolen
-- Glowling. While a base is locked, nobody but its owner may come into its zone; the server
-- moves anyone who does to the nearest edge (pushOut).

local Lock = {}

export type Check = {
	phase: string, -- Cycle phase: no locks at night
	hasPlot: boolean,
	carrying: boolean, -- carrying a stolen Glowling
	now: number,
	lockedUntil: number, -- the lock that may still be running
	readyAt: number, -- when the recharge ends
	charges: number, -- Lock Charges owned
}

-- Returns ok, a reason code when not, and whether the lock spends a Lock Charge.
function Lock.canLock(c: Check): (boolean, string?, boolean)
	if c.phase == "Night" then
		return false, "night", false
	elseif not c.hasPlot then
		return false, "no_plot", false
	elseif c.carrying then
		return false, "carrying", false
	elseif c.now < c.lockedUntil then
		return false, "active", false
	elseif c.now < c.readyAt then
		if c.charges > 0 then
			return true, nil, true -- a charge skips the recharge
		end
		return false, "recharging", false
	end
	return true, nil, false
end

-- A lock that starts now: when it ends, and when the next one is ready without a charge.
function Lock.times(cfg: any, now: number): (number, number)
	local lockedUntil = now + cfg.lock.activeSeconds
	return lockedUntil, lockedUntil + cfg.lock.rechargeSeconds
end

-- Moves a point that is inside a zone (in the zone's own space, centred on 0) out through the
-- nearest side, `margin` studs past it. Only x and z: the zone is a box over the plot.
function Lock.pushOut(x: number, z: number, halfX: number, halfZ: number, margin: number): (number, number)
	local toPlusX, toMinusX = halfX - x, x + halfX
	local toPlusZ, toMinusZ = halfZ - z, z + halfZ
	local nearest = math.min(toPlusX, toMinusX, toPlusZ, toMinusZ)
	if nearest == toPlusX then
		return halfX + margin, z
	elseif nearest == toMinusX then
		return -halfX - margin, z
	elseif nearest == toPlusZ then
		return x, halfZ + margin
	end
	return x, -halfZ - margin
end

return Lock
