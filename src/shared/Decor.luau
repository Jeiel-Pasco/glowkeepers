--!strict
-- Decorations and base names (GAME_SYSTEMS §18). Pure: no requires and no engine calls.
--
-- Bought with Embers: `decor.owned[id]` counts how many of an item a player owns (up to
-- decor.maxPerItem). `decor.placed` is a list of { id, x, z, rot }: x and z are studs from the
-- centre of the plot's DecorZone (zoneSize × zoneSize), on the decor.grid, and rot is 0..3
-- quarter turns. Placed items stay inside the zone, never overlap, and number at most
-- decor.maxPlaced. Decorations are never wiped (rebirth keeps them).
--
-- Base names are preset: `baseName = { a, n }` index decor.nameAdjectives and decor.nameNouns
-- (0 = no name yet).

local Decor = {}

export type Placed = { id: string, x: number, z: number, rot: number }

function Decor.item(cfg: any, id: string): any?
	for _, item in cfg.decor.items do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- Embers price, or nil and a reason: unknown, not_for_sale (exclusives), max_owned, too_poor.
function Decor.canBuy(cfg: any, decor: any, embers: number, id: string): (number?, string?)
	local item = Decor.item(cfg, id)
	if item == nil then
		return nil, "unknown"
	elseif item.exclusive then
		return nil, "not_for_sale"
	elseif (tonumber(decor.owned[id]) or 0) >= cfg.decor.maxPerItem then
		return nil, "max_owned"
	elseif embers < item.price then
		return nil, "too_poor"
	end
	return item.price, nil
end

-- Width (x) and depth (z) after `rot` quarter turns.
function Decor.footprint(item: any, rot: number): (number, number)
	if rot % 2 == 1 then
		return item.d, item.w
	end
	return item.w, item.d
end

function Decor.placedCount(placed: { Placed }, id: string): number
	local n = 0
	for _, p in placed do
		if p.id == id then
			n += 1
		end
	end
	return n
end

local function overlaps(cfg: any, a: Placed, b: Placed): boolean
	local itemA, itemB = Decor.item(cfg, a.id), Decor.item(cfg, b.id)
	if itemA == nil or itemB == nil then
		return false
	end
	local aw, ad = Decor.footprint(itemA, a.rot)
	local bw, bd = Decor.footprint(itemB, b.rot)
	-- Touching edges are fine; only a real overlap counts.
	return math.abs(a.x - b.x) * 2 < aw + bw and math.abs(a.z - b.z) * 2 < ad + bd
end

-- nil if `entry` may be placed, else a reason: unknown, not_owned (all copies placed), cap,
-- bad_rot, off_grid, out_of_bounds, overlap.
function Decor.canPlace(cfg: any, decor: any, entry: Placed): string?
	local item = Decor.item(cfg, entry.id)
	if item == nil then
		return "unknown"
	elseif Decor.placedCount(decor.placed, entry.id) >= (tonumber(decor.owned[entry.id]) or 0) then
		return "not_owned"
	elseif #decor.placed >= cfg.decor.maxPlaced then
		return "cap"
	elseif entry.rot ~= math.floor(entry.rot) or entry.rot < 0 or entry.rot > 3 then
		return "bad_rot"
	elseif entry.x % cfg.decor.grid ~= 0 or entry.z % cfg.decor.grid ~= 0 then
		return "off_grid"
	end
	local w, d = Decor.footprint(item, entry.rot)
	local half = cfg.decor.zoneSize / 2
	if math.abs(entry.x) * 2 + w > half * 2 or math.abs(entry.z) * 2 + d > half * 2 then
		return "out_of_bounds"
	end
	for _, other in decor.placed do
		if overlaps(cfg, entry, other) then
			return "overlap"
		end
	end
	return nil
end

-- Index of the placed item `id` at (x, z), or nil.
function Decor.find(placed: { Placed }, id: string, x: number, z: number): number?
	for i, p in placed do
		if p.id == id and p.x == x and p.z == z then
			return i
		end
	end
	return nil
end

-- The first free spot for `id`, scanning the grid from the back-left corner, or nil.
function Decor.freeSpot(cfg: any, decor: any, id: string, rot: number): (number?, number?)
	local half = cfg.decor.zoneSize / 2
	local grid = cfg.decor.grid
	for z = -half, half, grid do
		for x = -half, half, grid do
			if Decor.canPlace(cfg, decor, { id = id, x = x, z = z, rot = rot }) == nil then
				return x, z
			end
		end
	end
	return nil, nil
end

-- "Mossy Hollow", or "" for no name (0 or out of range).
function Decor.baseName(cfg: any, a: number, n: number): string
	local adjective = cfg.decor.nameAdjectives[a]
	local noun = cfg.decor.nameNouns[n]
	if adjective == nil or noun == nil then
		return ""
	end
	return `{adjective} {noun}`
end

return Decor
