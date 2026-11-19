--!strict
-- How a base looks at each size (Design & Asset Bible: a base should visibly grow up).
-- Pure: PlotController reads it to dress each plot from its unlocked pads.
--
--   tier  pads    home behind the plot   fence         floor        extras
--   0     free    (empty clearing)       rope          moss         -
--   1     8–11    patched tent           rope          moss         -
--   2     12–16   log cabin              wood picket   planks       corner lamps
--   3     17–22   stone cottage          wood picket   planks       lamps, banners
--   4     23–29   treehouse              stone wall    flagstone    lamps, banners, lantern arch
--   5     30      spirit-tree sanctuary  stone wall    flagstone    crystal lamps, banners, star arch

local BaseTier = {}

export type Look = {
	tier: number,
	name: string,
	home: string?, -- template in WorldAssets.Tiers
	homeHeight: number, -- studs
	fence: string, -- template in WorldAssets.Tiers
	floor: string, -- Enum.Material name
	floorColor: { number },
	lamps: string?, -- template for the four corner lamps
	banners: boolean,
	arch: string?, -- template over the gate
}

-- Pads needed for each tier (index = tier).
BaseTier.THRESHOLDS = { 8, 12, 17, 23, 30 }

local LOOKS: { Look } = {
	{
		tier = 1,
		name = "Camp",
		home = "Tent",
		homeHeight = 8,
		fence = "FenceRope",
		floor = "Grass",
		floorColor = { 98, 128, 70 },
		lamps = nil,
		banners = false,
		arch = nil,
	},
	{
		tier = 2,
		name = "Cabin",
		home = "Cabin",
		homeHeight = 13,
		fence = "FenceWood",
		floor = "WoodPlanks",
		floorColor = { 150, 112, 78 },
		lamps = "LampPost",
		banners = false,
		arch = nil,
	},
	{
		tier = 3,
		name = "Cottage",
		home = "Cottage",
		homeHeight = 19,
		fence = "FenceWood",
		floor = "WoodPlanks",
		floorColor = { 168, 126, 86 },
		lamps = "LampPost",
		banners = true,
		arch = nil,
	},
	{
		tier = 4,
		name = "Treehouse",
		home = "Treehouse",
		homeHeight = 30,
		fence = "FenceStone",
		floor = "Cobblestone",
		floorColor = { 128, 120, 110 },
		lamps = "LampPost",
		banners = true,
		arch = "gift_lantern_arch",
	},
	{
		tier = 5,
		name = "Sanctuary",
		home = "Sanctuary",
		homeHeight = 38,
		fence = "FenceStone",
		floor = "Cobblestone",
		floorColor = { 170, 160, 190 },
		lamps = "crystal_lamp",
		banners = true,
		arch = "star_arch",
	},
}

local EMPTY: Look = {
	tier = 0,
	name = "Clearing",
	home = nil,
	homeHeight = 0,
	fence = "FenceRope",
	floor = "Grass",
	floorColor = { 98, 128, 70 },
	lamps = nil,
	banners = false,
	arch = nil,
}

-- The tier for a plot with `slots` unlocked pads; 0 for a free plot.
function BaseTier.tier(slots: number, owned: boolean): number
	if not owned then
		return 0
	end
	local tier = 1
	for i, need in BaseTier.THRESHOLDS do
		if slots >= need then
			tier = i
		end
	end
	return tier
end

function BaseTier.look(slots: number, owned: boolean): Look
	local tier = BaseTier.tier(slots, owned)
	return if tier == 0 then EMPTY else LOOKS[tier]
end

return BaseTier
