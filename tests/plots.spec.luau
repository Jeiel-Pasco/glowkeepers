-- Plots: assignment next to friends, the replicated view, diffs and patches (GAME_SYSTEMS §1).
local H = require("./harness")
local Plots = require("../src/shared/Plots")

local IDS = { 1, 2, 3, 4, 5, 6, 7, 8 }

local function copy(view: any): any
	local pads = {}
	for key, pad in view.pads do
		pads[key] = table.clone(pad)
	end
	local result = table.clone(view)
	result.pads = pads
	return result
end

local function sameList(actual: { number }, expected: { number }, label: string)
	H.eq(#actual, #expected, `{label} length`)
	for i, value in expected do
		H.eq(actual[i], value, `{label}[{i}]`)
	end
end

H.test("neighbors wrap around the ring", function()
	sameList(Plots.neighbors(IDS, 1), { 8, 2 }, "plot 1")
	sameList(Plots.neighbors(IDS, 8), { 7, 1 }, "plot 8")
	sameList(Plots.neighbors(IDS, 4), { 3, 5 }, "plot 4")
	sameList(Plots.neighbors({ 3, 1, 2 }, 1), { 3, 2 }, "unsorted ids")
	sameList(Plots.neighbors({ 1, 2 }, 1), { 2 }, "two plots: one neighbour")
	sameList(Plots.neighbors({ 1 }, 1), {}, "one plot")
	sameList(Plots.neighbors(IDS, 9), {}, "unknown plot")
end)

H.test("pick: the lowest free plot when no friend is here", function()
	H.eq(Plots.pick(IDS, {}, {}), 1, "empty server")
	H.eq(Plots.pick(IDS, { [1] = true, [2] = true, [4] = true }, {}), 3, "lowest free")
	local full = {}
	for _, id in IDS do
		full[id] = true
	end
	H.eq(Plots.pick(IDS, full, {}), nil, "no free plot")
end)

H.test("pick: next to a friend when a neighbouring plot is free", function()
	H.eq(Plots.pick(IDS, { [5] = true }, { 5 }), 4, "lower neighbour first")
	H.eq(Plots.pick(IDS, { [4] = true, [5] = true }, { 5 }), 6, "the other neighbour")
	H.eq(Plots.pick(IDS, { [1] = true }, { 1 }), 2, "plot 1's neighbours are 8 and 2: lowest is 2")
	H.eq(Plots.pick(IDS, { [1] = true, [2] = true }, { 1 }), 8, "wraps to 8")
	H.eq(Plots.pick(IDS, { [3] = true, [6] = true }, { 6, 3 }), 2, "two friends: the lowest free neighbour")
	H.eq(Plots.pick(IDS, { [4] = true, [5] = true, [6] = true }, { 5 }), 1, "friend boxed in: lowest free")
end)

local function data(): any
	return {
		stars = 2,
		glowlings = {
			a = { id = "a", sp = "mothlet", r = 3, m = 1, s = 1.1 },
			b = { id = "b", sp = "puffwick", r = 1, m = 0, s = 0.9 },
			c = { id = "c", sp = "moonbun", r = 2, m = 0, s = 1 },
		},
		vault = { ["1"] = "a" },
		display = { ["6"] = "b", ["7"] = "ghost" }, -- "ghost" isn't owned: skipped
	}
end

H.test("view: owner, layout, stars, and what sits on each pad", function()
	local view = Plots.view(3, 42, data(), { slots = 8, vault = 5 })
	H.eq(view.id, 3, "id")
	H.eq(view.owner, 42, "owner")
	H.eq(view.slots, 8, "slots")
	H.eq(view.vault, 5, "vault")
	H.eq(view.stars, 2, "stars")
	H.eq(view.pads["1"].sp, "mothlet", "pad 1")
	H.eq(view.pads["1"].m, 1, "pad 1 mutation")
	H.eq(view.pads["6"].s, 0.9, "pad 6 size")
	H.eq(view.pads["7"], nil, "unowned id skipped")
	H.eq((view.pads :: any)["1"].id, nil, "ids are not replicated")
	local empty = Plots.empty(5)
	H.eq(empty.owner, 0, "free plot")
	H.eq(next(empty.pads), nil, "no pads")
end)

H.test("diff and apply: only what changed, and apply rebuilds the new view", function()
	local layout = { slots = 8, vault = 3 }
	local d = data()
	local old = Plots.view(3, 42, d, layout)
	H.eq(Plots.diff(old, copy(old)), nil, "no change → nil")

	d.vault["1"] = nil -- a moved out
	d.display["4"] = "c" -- c placed
	d.glowlings.b.m = 2 -- b changed in place (cannot happen yet, but a diff must catch it)
	d.stars = 3
	local new = Plots.view(3, 42, d, { slots = 9, vault = 4 })
	local patch = Plots.diff(old, new) :: any
	H.ok(patch ~= nil, "a patch")
	H.eq(patch.owner, nil, "owner unchanged")
	H.eq(patch.slots, 9, "slots")
	H.eq(patch.vault, 4, "vault")
	H.eq(patch.stars, 3, "stars")
	H.eq(patch.pads["1"], false, "pad 1 emptied")
	H.eq(patch.pads["4"].sp, "moonbun", "pad 4 filled")
	H.eq(patch.pads["6"].m, 2, "pad 6 changed")

	local applied = Plots.apply(copy(old), patch)
	H.eq(Plots.diff(applied, new), nil, "apply(old, diff(old, new)) == new")
	H.eq(applied.pads["1"], nil, "pad 1 gone")
end)

H.test("a freed plot diffs to owner 0 with every pad cleared", function()
	local old = Plots.view(2, 42, data(), { slots = 8, vault = 3 })
	local patch = Plots.diff(old, Plots.empty(2)) :: any
	H.eq(patch.owner, 0, "owner cleared")
	H.eq(patch.pads["1"], false, "pad 1 cleared")
	H.eq(patch.pads["6"], false, "pad 6 cleared")
	local applied = Plots.apply(copy(old), patch)
	H.eq(next(applied.pads), nil, "no pads left")
end)

H.finish("plots")
