--!strict
-- The Night Companion (GAME_SYSTEMS §31, D23). Pure.
--
-- One vault Glowling (`data.companion`, an id) goes with you at night: it keeps earning on its
-- pad, a copy floats beside you, and its night trait works for you:
--   Firebinder  fuel you feed counts +15% (floor Rare or lower) or +30% (higher); Emberwing +50%
--   Wayfinder   every 10 s points to the nearest wild within 60 studs whose species' floor is
--               Rare or higher (a wild's rarity is hidden until caught)
--   Savior      your revive hold is 0.6 s shorter, never under 1.8 s
-- It can only be chosen or changed by day, and only from the vault; a companion moved out of the
-- vault stops counting.

local Companion = {}

local function floorOf(cfg: any, species: any): number
	local id = if species ~= nil then species.minRarity else nil
	if type(id) == "string" then
		for i, rarity in cfg.rarities do
			if rarity.id == id then
				return i
			end
		end
	end
	return 1
end

-- The companion's species entry, or nil if there is none or it isn't in the vault.
function Companion.species(data: any, species: { [string]: any }): any
	local id = data.companion
	if type(id) ~= "string" or id == "" then
		return nil
	end
	local inVault = false
	for _, placed in data.vault do
		inVault = inVault or placed == id
	end
	local record = data.glowlings[id]
	if not inVault or record == nil then
		return nil
	end
	return species[record.sp]
end

-- Why `id` can't become the companion now, or nil if it can. Choosing the current one again
-- clears it (also by day only).
function Companion.canSet(data: any, id: string, phase: string): string?
	if phase ~= "Day" then
		return "night"
	end
	for _, placed in data.vault do
		if placed == id then
			return nil
		end
	end
	return "not_in_vault"
end

-- The fuel multiplier a Firebinder companion gives (1 otherwise).
function Companion.fuelMult(cfg: any, species: any): number
	if species == nil or species.trait ~= "Firebinder" then
		return 1
	end
	local apex = cfg.traits.apex[species.id]
	if apex ~= nil and apex.fuelBoost ~= nil then
		return 1 + apex.fuelBoost
	end
	local c = cfg.traits.companion
	return 1 + (if floorOf(cfg, species) > 3 then c.firebinderHigh else c.firebinder)
end

-- The revive hold with a Savior companion.
function Companion.reviveHold(cfg: any, species: any, hold: number): number
	if species == nil or species.trait ~= "Savior" then
		return hold
	end
	local c = cfg.traits.companion
	return math.max(c.saviorMin, hold - c.saviorCut)
end

export type Wild = { id: string, sp: string, x: number, y: number, z: number }

-- The wild a Wayfinder points to from `position` (a Vector3-like { X, Y, Z }), or nil.
function Companion.wayfind(cfg: any, species: { [string]: any }, position: any, wilds: { Wild }): Wild?
	local c = cfg.traits.companion
	local minFloor = floorOf(cfg, { minRarity = c.wayfinderMinFloor })
	local best: Wild?, bestDistance = nil, c.wayfinderRange
	for _, wild in wilds do
		if floorOf(cfg, species[wild.sp]) >= minFloor then
			local dx, dy, dz = wild.x - position.X, wild.y - position.Y, wild.z - position.Z
			local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
			if distance <= bestDistance then
				best, bestDistance = wild, distance
			end
		end
	end
	return best
end

return Companion
