--!strict
-- Lantern shop rules (GAME_SYSTEMS §8). Pure: no requires and no engine calls.
-- Every player has their own lure stock per restock window (os.time() // shop.restockSeconds,
-- the same in every server). The profile keeps `shop = { window, bought }`, so leaving and
-- rejoining in the same window doesn't refill it; unused stock doesn't carry over.

local Shop = {}

export type Record = { window: number, bought: { number } } -- bought[floor] this window

export type Check = {
	floor: number, -- the lure's rarity index, 1 Common .. lures.maxFloor
	price: number, -- Economy.lureCost
	glow: number,
	left: number, -- Shop.left
	storage: number, -- Glowlings in storage
}

local function current(record: any, window: number): boolean
	return type(record) == "table" and record.window == window and type(record.bought) == "table"
end

-- Lures of `floor` this player can still buy in `window`.
function Shop.left(cfg: any, record: any, window: number, floor: number): number
	local stock = cfg.lures.stockPerRestock[floor] or 0
	if not current(record, window) then
		return stock -- a new window: full stock
	end
	return math.max(0, stock - (tonumber(record.bought[floor]) or 0))
end

-- Lures can't be bought while storage is at its cap (§7: night catches may still overflow it).
function Shop.canBuyLure(cfg: any, c: Check): (boolean, string?)
	if c.floor < 1 or c.floor > cfg.lures.maxFloor then
		return false, "unknown"
	elseif c.left <= 0 then
		return false, "sold_out"
	elseif c.storage >= cfg.storage.size then
		return false, "storage_full"
	elseif c.glow < c.price then
		return false, "too_poor"
	end
	return true, nil
end

-- The record after one more lure of `floor` in `window` (a new window starts from zero).
function Shop.bought(cfg: any, record: any, window: number, floor: number): Record
	local bought = {}
	for i = 1, cfg.lures.maxFloor do
		bought[i] = if current(record, window) then tonumber(record.bought[i]) or 0 else 0
	end
	bought[floor] += 1
	return { window = window, bought = bought }
end

return Shop
