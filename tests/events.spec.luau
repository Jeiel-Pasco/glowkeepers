-- Events and the daily featured species (GAME_SYSTEMS §21).
local H = require("./harness")
local Events = require("../src/shared/Events")

local cfg = H.config()
local species = H.json("config/species.json")

local deepwood = {}
for _, s in species.species do
	if s.pool == "Deepwood" then
		table.insert(deepwood, s.id)
	end
end

H.test("featured: a Deepwood species, fixed for the UTC day, every one in rotation", function()
	local day0 = 1794787200
	local first = Events.featured(species, day0)
	H.ok(table.find(deepwood, first) ~= nil, "from Deepwood")
	H.eq(Events.featured(species, day0 + 86399), first, "same day")
	local seen = {}
	for d = 0, #deepwood - 1 do
		seen[Events.featured(species, day0 + d * 86400) :: string] = true
	end
	local count = 0
	for _ in seen do
		count += 1
	end
	H.eq(count, #deepwood, "each species once per cycle")
	H.eq(Events.featured({ species = {} }, day0), nil)
end)

H.test("pickSpecies: the featured one gets 2x weight", function()
	local ids = { "a", "b", "c" }
	-- total 4: [0,2) featured "b", then "a", "c"
	H.eq(Events.pickSpecies(ids, "b", cfg.events.featuredWeight, H.constant(0)), "b")
	H.eq(Events.pickSpecies(ids, "b", 2, H.constant(0.49)), "b")
	H.eq(Events.pickSpecies(ids, "b", 2, H.constant(0.5)), "a")
	H.eq(Events.pickSpecies(ids, "b", 2, H.constant(0.99)), "c")
	H.eq(Events.pickSpecies(ids, "z", 2, H.constant(0.99)), "c", "not in this pool: uniform")
	H.eq(Events.pickSpecies(ids, nil, 2, H.constant(0)), "a")
end)

H.test("Moonlit flag only when the event turns it on", function()
	H.eq(Events.mutationFlags(nil), nil)
	H.eq(Events.mutationFlags({ id = "x", moonlit = false }), nil)
	H.eq((Events.mutationFlags({ id = "x", moonlit = true }) :: any).Moonlit, true)
end)

H.finish("events")
