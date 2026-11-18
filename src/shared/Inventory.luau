--!strict
-- Where each owned Glowling sits: on a pad (vault or display) or in storage (GAME_SYSTEMS §7).
--
-- Pure: no requires and no engine calls, so the Lune tests run exactly the code the server runs.
-- Callers pass in what depends on config (`layout`, `valueOf`), so this module needs nothing else.
--
-- One numbering for pads everywhere: pad N is the map's `Slot` N (TECH_SPEC §6a). Pads
-- 1..layout.vault are vault pads (never stealable); pads layout.vault + 1..layout.slots are
-- display pads. `data.vault` and `data.display` are keyed by the pad number as a string, so a
-- Glowling keeps its pad when the vault grows; normalize() then moves it into the vault map.
-- Storage is implicit: an owned Glowling on no pad is in storage.

local Inventory = {}

export type Layout = { slots: number, vault: number } -- unlocked pads, and how many of them are vault pads
export type ValueOf = (record: any) -> number

local function isPad(layout: Layout, pad: number): boolean
	return pad % 1 == 0 and pad >= 1 and pad <= layout.slots
end

local function mapFor(data: any, layout: Layout, pad: number): { [string]: string }
	return if pad <= layout.vault then data.vault else data.display
end

local function count(map: { [any]: any }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

-- Where a Glowling is: "vault" or "display" with its pad, "storage", or nil if not owned.
function Inventory.locate(data: any, id: string): (string?, number?)
	if data.glowlings[id] == nil then
		return nil, nil
	end
	for key, placed in data.vault do
		if placed == id then
			return "vault", tonumber(key)
		end
	end
	for key, placed in data.display do
		if placed == id then
			return "display", tonumber(key)
		end
	end
	return "storage", nil
end

function Inventory.padKind(layout: Layout, pad: number): string?
	if not isPad(layout, pad) then
		return nil
	end
	return if pad <= layout.vault then "vault" else "display"
end

function Inventory.storageCount(data: any): number
	return count(data.glowlings) - count(data.vault) - count(data.display)
end

-- Ids of every placed Glowling (vault and display). Every placed Glowling earns.
function Inventory.placedIds(data: any): { string }
	local ids = {}
	for _, id in data.vault do
		table.insert(ids, id)
	end
	for _, id in data.display do
		table.insert(ids, id)
	end
	return ids
end

-- Glow/s before the Star bonus: the sum of valueOf over placed Glowlings.
function Inventory.placedValue(data: any, valueOf: ValueOf): number
	local sum = 0
	for _, id in Inventory.placedIds(data) do
		local record = data.glowlings[id]
		if record ~= nil then
			sum += valueOf(record)
		end
	end
	return sum
end

-- Makes the maps fit the layout: a display pad that is now a vault pad moves to the vault map
-- (and back the other way), and anything past the unlocked pads goes to storage.
-- Returns true if anything moved.
function Inventory.normalize(data: any, layout: Layout): boolean
	local changed = false
	for _, source in { data.vault, data.display } do
		local keys = {}
		for key in source do
			table.insert(keys, key)
		end
		table.sort(keys)
		for _, key in keys do
			local pad = tonumber(key)
			local id = source[key]
			local target = if pad ~= nil and isPad(layout, pad) then mapFor(data, layout, pad) else nil
			if target ~= source then
				source[key] = nil
				changed = true
				if target ~= nil and target[key] == nil then
					target[key] = id
				end
			end
		end
	end
	return changed
end

-- Puts an owned Glowling on `pad`. If the pad holds another Glowling, the two swap places
-- (the other goes to storage when the first came from storage). Returns ok, and a reason
-- when it fails. Placing a Glowling where it already is succeeds and changes nothing.
function Inventory.place(data: any, layout: Layout, id: string, pad: number): (boolean, string?)
	if data.glowlings[id] == nil then
		return false, "not owned"
	end
	if not isPad(layout, pad) then
		return false, "slot locked"
	end
	local where, from = Inventory.locate(data, id)
	if where == "storage" then
		from = nil
	end
	local key = tostring(pad)
	if from == pad then
		return true
	end
	local target = mapFor(data, layout, pad)
	local occupant = target[key]
	if from ~= nil then
		local source = if where == "vault" then data.vault else data.display
		source[tostring(from)] = nil
		if occupant ~= nil then
			mapFor(data, layout, from)[tostring(from)] = occupant
		end
	end
	target[key] = id
	return true
end

-- Moves a placed Glowling back to storage. `storageCap` is the most storage may hold.
function Inventory.unplace(data: any, id: string, storageCap: number): (boolean, string?)
	local where, pad = Inventory.locate(data, id)
	if where == nil then
		return false, "not owned"
	elseif where == "storage" then
		return false, "already in storage"
	elseif Inventory.storageCount(data) >= storageCap then
		return false, "storage full"
	end
	local map = if where == "vault" then data.vault else data.display
	map[tostring(pad)] = nil
	return true
end

-- Drops any pad reference to `id` (the record is being removed or transferred).
function Inventory.forget(data: any, id: string): boolean
	for _, map in { data.vault, data.display } do
		for key, placed in map do
			if placed == id then
				map[key] = nil
				return true
			end
		end
	end
	return false
end

-- Owned ids, best first: by value, then oldest, then id (so the order is stable).
function Inventory.ranked(data: any, valueOf: ValueOf): { string }
	local ids = {}
	local values = {}
	for id, record in data.glowlings do
		table.insert(ids, id)
		values[id] = valueOf(record)
	end
	table.sort(ids, function(a, b)
		if values[a] ~= values[b] then
			return values[a] > values[b]
		end
		local atA, atB = data.glowlings[a].at, data.glowlings[b].at
		if atA ~= atB then
			return atA < atB
		end
		return a < b
	end)
	return ids
end

-- "Place best" (§7): the best earners fill the vault pads, the next best the display pads.
-- A Glowling that already sits on the right kind of pad keeps its pad, so a re-run after one
-- new catch moves as little as possible. Returns true if anything moved.
function Inventory.placeBest(data: any, layout: Layout, valueOf: ValueOf): boolean
	local changed = Inventory.normalize(data, layout)
	local ranked = Inventory.ranked(data, valueOf)
	local wantVault, wantDisplay = {}, {}
	for i, id in ranked do
		if i <= layout.vault then
			wantVault[id] = true
		elseif i <= layout.slots then
			wantDisplay[id] = true
		else
			break
		end
	end

	-- Clear anything on the wrong kind of pad (or not wanted on a pad at all).
	for _, pair in { { data.vault, wantVault }, { data.display, wantDisplay } } do
		local map, want = pair[1], pair[2]
		for key, id in map do
			if want[id] then
				want[id] = nil -- already in place
			else
				map[key] = nil
				changed = true
			end
		end
	end

	-- Fill free pads, lowest first, best Glowling first.
	local nextPad = { vault = 1, display = layout.vault + 1 }
	for _, id in ranked do
		local kind = if wantVault[id] then "vault" elseif wantDisplay[id] then "display" else nil
		if kind ~= nil then
			local map = if kind == "vault" then data.vault else data.display
			while map[tostring(nextPad[kind])] ~= nil do
				nextPad[kind] += 1
			end
			map[tostring(nextPad[kind])] = id
			nextPad[kind] += 1
			changed = true
		end
	end
	return changed
end

return Inventory
