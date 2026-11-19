--!strict
-- Plot assignment and the replicated plot view (GAME_SYSTEMS §1, TECH_SPEC §6).
--
-- Pure: no requires and no engine calls. The server builds a View per plot, sends every View
-- in PlotSnapshot when a client is ready, then a Patch in PlotDelta whenever one changes.
-- The client applies the patch with Plots.apply, so both sides share one shape.
--
-- Plot ids come from the map's `PlotId` attributes. Plots form a ring in id order, so plot 1
-- sits next to plot 2 and the last plot.

local Plots = {}

export type PadView = { sp: string, r: number, m: number, s: number }

export type DecorView = { id: string, x: number, z: number, rot: number }

export type View = {
	id: number,
	owner: number, -- userId, 0 when free
	slots: number, -- unlocked pads
	vault: number, -- how many of them are vault pads (pads 1..vault)
	stars: number,
	lock: number, -- server time the Base Lock ends; 0 (or a past time) when open
	shield: boolean, -- the owner has the new-player shield: nobody can steal here
	pads: { [string]: PadView }, -- pad number as a string → the Glowling on it
	name: string, -- the preset base name ("" = none yet)
	decor: { DecorView }, -- placed decorations (Shared.Decor)
}

-- Only the fields that changed. A pad set to `false` is now empty.
export type Patch = {
	owner: number?,
	slots: number?,
	vault: number?,
	stars: number?,
	lock: number?,
	shield: boolean?,
	pads: { [string]: PadView | false }?,
	name: string?,
	decor: { DecorView }?, -- the whole list when anything in it changed
}

local SCALARS = { "owner", "slots", "vault", "stars", "lock", "shield", "name" }

-- The two plots next to `plotId` in the ring. `ids` is every plot id, in any order.
function Plots.neighbors(ids: { number }, plotId: number): { number }
	local ring = table.clone(ids)
	table.sort(ring)
	local index = table.find(ring, plotId)
	if index == nil or #ring < 2 then
		return {}
	end
	local before = ring[(index - 2) % #ring + 1]
	local after = ring[index % #ring + 1]
	return if before == after then { before } else { before, after }
end

-- The plot a joining player gets: the lowest free plot next to a friend's plot, otherwise
-- the lowest free plot, otherwise nil (the server is over its plot count).
-- `taken` maps taken plot ids to anything; `friendPlots` are the plots friends own.
function Plots.pick(ids: { number }, taken: { [number]: any }, friendPlots: { number }): number?
	local best: number? = nil
	for _, friendPlot in friendPlots do
		for _, near in Plots.neighbors(ids, friendPlot) do
			if taken[near] == nil and (best == nil or near < best) then
				best = near
			end
		end
	end
	if best ~= nil then
		return best
	end
	for _, id in ids do
		if taken[id] == nil and (best == nil or id < best) then
			best = id
		end
	end
	return best
end

function Plots.empty(id: number): View
	return {
		id = id,
		owner = 0,
		slots = 0,
		vault = 0,
		stars = 0,
		lock = 0,
		shield = false,
		pads = {},
		name = "",
		decor = {},
	}
end

local function decorList(data: any): { DecorView }
	local out = {}
	local placed = if type(data.decor) == "table" then data.decor.placed else nil
	for i, d in placed or {} do
		out[i] = { id = d.id, x = d.x, z = d.z, rot = d.rot }
	end
	return out
end

-- What everyone sees of an owned plot. `layout` is Inventory's { slots, vault }; `lock` is
-- when its Base Lock ends (LockService); `name` the preset base name (Decor.baseName).
function Plots.view(
	id: number,
	owner: number,
	data: any,
	layout: { slots: number, vault: number },
	lock: number?,
	name: string?
): View
	local pads: { [string]: PadView } = {}
	for _, map in { data.vault, data.display } do
		for key, glowlingId in map do
			local record = data.glowlings[glowlingId]
			if record ~= nil then
				pads[key] = { sp = record.sp, r = record.r, m = record.m, s = record.s }
			end
		end
	end
	return {
		id = id,
		owner = owner,
		slots = layout.slots,
		vault = layout.vault,
		stars = data.stars,
		lock = lock or 0,
		shield = data.shield ~= nil and data.shield.active == true,
		pads = pads,
		name = name or "",
		decor = decorList(data),
	}
end

local function decorKey(list: { DecorView }): string
	local parts = {}
	for i, d in list do
		parts[i] = `{d.id}:{d.x}:{d.z}:{d.rot}`
	end
	return table.concat(parts, ",")
end

local function samePad(a: PadView?, b: PadView?): boolean
	if a == nil or b == nil then
		return a == b
	end
	return a.sp == b.sp and a.r == b.r and a.m == b.m and a.s == b.s
end

-- The patch that turns `old` into `new`, or nil if nothing changed.
function Plots.diff(old: View, new: View): Patch?
	local patch: any = {}
	local any = false
	local before: any, after: any = old, new
	for _, key in SCALARS do
		if before[key] ~= after[key] then
			patch[key] = after[key]
			any = true
		end
	end
	local pads = {}
	local anyPad = false
	for key, pad in new.pads do
		if not samePad(old.pads[key], pad) then
			pads[key] = table.clone(pad)
			anyPad = true
		end
	end
	for key in old.pads do
		if new.pads[key] == nil then
			pads[key] = false
			anyPad = true
		end
	end
	if anyPad then
		patch.pads = pads
		any = true
	end
	if decorKey(old.decor or {}) ~= decorKey(new.decor) then
		patch.decor = table.clone(new.decor)
		any = true
	end
	return if any then patch :: Patch else nil
end

-- Applies a patch in place and returns the view.
function Plots.apply(view: View, patch: Patch): View
	local target: any, source: any = view, patch
	for _, key in SCALARS do
		if source[key] ~= nil then
			target[key] = source[key]
		end
	end
	if patch.decor ~= nil then
		view.decor = table.clone(patch.decor)
	end
	if patch.pads ~= nil then
		for key, pad in patch.pads do
			view.pads[key] = if pad == false then nil else table.clone(pad :: PadView)
		end
	end
	return view
end

return Plots
