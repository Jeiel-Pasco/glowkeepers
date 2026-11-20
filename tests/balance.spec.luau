-- Balance: the numbers behind "fair at every level" (Shared.Enemies header).
-- The model player clicks their basic attack and casts one Common bolt on cooldown, with no
-- stat points spent. Enemies grow 10% per level, the same as the player's level power, so
-- on-level fights should take the same time at level 2 and level 12.
local H = require("./harness")
local Spells = require("../src/shared/Spells")
local Level = require("../src/shared/Level")
local Enemies = require("../src/shared/Enemies")
local Zones = require("../src/shared/Zones")
-- selene: allow(incorrect_standard_library_use, shadowing)
local Vector3 = (require("@lune/roblox") :: any).Vector3

local function kitDps(level: number, kind: string): number
	local basic = Spells.BASIC[kind]
	local bolt =
		Spells.byId[({ Neutral = "arcane_bolt", Fire = "ember_shot", Water = "tide_bolt", Leaf = "thorn_dart" })[kind]]
	return (basic.damage / basic.cooldown + bolt.damage / bolt.cooldown) * Level.power(level)
end

local function clickDps(level: number): number
	local basic = Spells.BASIC.Neutral
	return basic.damage / basic.cooldown * Level.power(level)
end

local function enemyDps(kind: any, level: number): number
	return Enemies.damage(kind, level) / kind.cooldown
end

for _, level in { 2, 7, 12 } do
	H.test(`on-level minions and casters at level {level}`, function()
		for id, kind in Enemies.kinds do
			if kind.role == "minion" then
				local ttk = Enemies.maxHp(kind, level) / kitDps(level, "Fire")
				H.ok(ttk >= 1.5 and ttk <= 3, `{id} kit kill {ttk}s`)
				local clicks = Enemies.maxHp(kind, level) / clickDps(level)
				H.ok(clicks >= 3 and clicks <= 6, `{id} click-only kill {clicks}s`)
				local survive = Level.maxHealth(level, 0) / enemyDps(kind, level)
				H.ok(survive >= 15 and survive <= 30, `{id} kills an idle player in {survive}s`)
			elseif kind.role == "caster" then
				local ttk = Enemies.maxHp(kind, level) / kitDps(level, "Fire")
				H.ok(ttk >= 1 and ttk <= 2.5, `{id} kit kill {ttk}s`)
			end
		end
	end)
end

H.test("a solo on-level boss fight lasts about a minute", function()
	for id, kind in Enemies.kinds do
		if kind.role == "boss" then
			local ttk = Enemies.maxHp(kind, 12) / kitDps(12, kind.type == "Fire" and "Water" or "Fire")
			H.ok(ttk >= 45 and ttk <= 90, `{id} solo {ttk}s`)
		end
	end
end)

H.test("the tutorial Ashling takes 10–25 s with the first spell", function()
	local ashling = Enemies.kinds.ashling
	local ttk = Enemies.maxHp(ashling, 3) / kitDps(3, "Neutral")
	H.ok(ttk >= 10 and ttk <= 25, `ashling {ttk}s`)
end)

H.test("levelling 1 → 15 on on-level minions takes 45–150 minutes", function()
	local seconds = 0
	local kind = Enemies.kinds.ember_imp
	for level = 1, Level.CAP - 1 do
		local kills = Level.xpToNext(level) / Enemies.xp(kind, level)
		local perKill = Enemies.maxHp(kind, level) / kitDps(level, "Fire") + 6 -- 6 s to find the next one
		seconds += kills * perKill
	end
	local minutes = seconds / 60
	H.ok(minutes >= 45 and minutes <= 150, `{minutes} minutes`)
end)

H.test("every zone pack has a real enemy kind; zones sit apart and inside the world", function()
	local count = 0
	for _, spawn in Zones.spawns() do
		H.ok(Enemies.kinds[spawn.kind], `kind {spawn.kind}`)
		H.ok(spawn.pos.Magnitude < Zones.WORLD_R - 40, `{spawn.kind} inside the world`)
		count += 1
	end
	H.ok(count <= 50, `{count} enemies in the world`)
	-- Packs at least 40 studs apart (past minion and caster aggro), so one pull is one pack, and
	-- every pack inside its zone circle.
	for _, zone in Zones.list do
		local centre = Zones.toWorld(zone, Zones.ZONE_D, 0)
		for i, a in Zones.PACKS do
			local pa = Zones.toWorld(zone, a.d, a.s)
			H.ok((pa - centre).Magnitude <= Zones.ZONE_R - 25, `{zone.id} pack {i} inside the circle`)
			H.ok(math.abs(pa.Y - Zones.PLATEAU_Y) < 0.01, `{zone.id} pack {i} on the plateau`)
			for j, b in Zones.PACKS do
				if i < j then
					local d = (pa - Zones.toWorld(zone, b.d, b.s)).Magnitude
					H.ok(d >= 40, `{zone.id} packs {i},{j} {d}`)
				end
			end
		end
	end
end)

H.test("zone circles sit on the plateau with forest round them", function()
	H.ok(Zones.ZONE_D - Zones.ZONE_R >= Zones.CLIFF_OUT + 100, "forest between the cliff and each zone")
	H.ok(Zones.ZONE_D + Zones.ZONE_R <= Zones.WORLD_R - 100, "forest between each zone and the edge")
	local a, b = Zones.toWorld(Zones.list[1], Zones.ZONE_D, 0), Zones.toWorld(Zones.list[2], Zones.ZONE_D, 0)
	H.ok((a - b).Magnitude >= 2 * Zones.ZONE_R + 300, "zones far apart")
	H.ok(Zones.CAMP_R < Zones.GATE_D and Zones.GATE_D < Zones.CLIFF_IN, "camp, then lowland")
end)

local function angleGap(a: number, b: number): number
	return math.abs((a - b + math.pi) % (2 * math.pi) - math.pi)
end

H.test("parkour ledges are hard but reachable (JumpHeight 7.2)", function()
	local routes = Zones.routes()
	H.ok(#routes == 2 * #Zones.list, `{#routes} routes`)
	local half = Zones.LEDGE_SIZE.X / 2
	for n, route in routes do
		local ledges = route.ledges
		H.ok(ledges[1].Y - Zones.FLOOR_Y <= 5.5, `route {n} first ledge`)
		H.ok(Zones.PLATEAU_Y - ledges[#ledges].Y <= 5.5, `route {n} last ledge to the top`)
		for i = 2, #ledges do
			local a, b = ledges[i - 1], ledges[i]
			local rise = b.Y - a.Y
			local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude - 2 * half
			H.ok(rise > 0 and rise <= 5.5, `route {n} ledge {i} rise {rise}`)
			H.ok(flat >= 1 and flat <= 4, `route {n} ledge {i} gap {flat}`)
		end
		for _, ledge in ledges do
			local r = Vector3.new(ledge.X, 0, ledge.Z).Magnitude
			H.ok(r >= Zones.CLIFF_IN - 5 and r <= Zones.CLIFF_OUT, `route {n} ledge on the cliff at r{r}`)
		end
	end
end)

H.test("raider camp sites sit in the lowland, apart and off the routes", function()
	local sites = Zones.campSites()
	H.ok(#sites >= 8, `{#sites} camp sites`)
	local ledges = #Zones.routes()[1].ledges
	local spread = (ledges - 1) * Zones.LEDGE_STEP / Zones.CLIFF_IN -- a route's sideways span
	H.ok(spread < Zones.ROUTE_OFFSET, "routes stay their side of the zone angle")
	for i, site in Zones.CAMP_SITES do
		H.ok(site.r - Zones.CAMP_SITE_R >= Zones.GATE_D + 30, `site {i} outside the camp ring`)
		H.ok(site.r + Zones.CAMP_SITE_R <= Zones.CLIFF_IN - 20, `site {i} before the cliff`)
		local width = math.asin(Zones.CAMP_SITE_R / site.r)
		for _, zone in Zones.list do
			for _, side in { -1, 1 } do
				local route = zone.angle + side * Zones.ROUTE_OFFSET
				local gap = angleGap(site.angle, route) - width
				H.ok(gap >= math.rad(15), `site {i} clear of {zone.id} route ({math.deg(gap)}°)`)
			end
		end
		for j, other in sites do
			if j > i then
				local d = (sites[i] - other).Magnitude
				H.ok(d >= 2 * Zones.CAMP_SITE_R + 40, `sites {i},{j} {d}`)
			end
		end
		for _, raider in Zones.RAIDERS do
			local d = (sites[i] - Zones.polar(raider.angle, raider.r)).Magnitude
			H.ok(d >= Zones.CAMP_SITE_R + Zones.RAIDER_WANDER + 20, `site {i} clear of roaming raiders`)
		end
	end
	for _, raider in Zones.RAIDERS do
		H.ok(raider.r + Zones.RAIDER_WANDER <= Zones.CLIFF_IN, "raiders roam the lowland")
	end
end)

H.test("the quest guide goes through a gate and up the ledges", function()
	local ember = Zones.list[1]
	local entry = Zones.entry(ember)
	H.ok(entry.Y > Zones.PLATEAU_Y - 5, "zone entry on the plateau")
	-- In camp: out through the nearest gate.
	local out = Zones.guide(Vector3.new(0, 3, 0), entry)
	H.ok((out - Zones.polar(ember.angle, Zones.GATE_D + 16)).Magnitude < 1, `gate first {out}`)
	-- In the lowland: to the first ledge of the closest route.
	local route = Zones.routes()[1]
	local low = Zones.guide(Zones.polar(ember.angle, 400) + Vector3.new(0, 3, 0), entry)
	H.ok(low == route.ledges[1] or low == Zones.routes()[2].ledges[1], `first ledge {low}`)
	-- On ledge 5: the next one up.
	local on5 = route.ledges[5] + Vector3.new(0, 3, 0)
	H.ok(Zones.guide(on5, entry) == route.ledges[6], "next ledge")
	-- On the last ledge, and on the plateau: straight there.
	H.ok(Zones.guide(route.ledges[#route.ledges] + Vector3.new(0, 3, 0), entry) == entry, "top")
	H.ok(Zones.guide(Zones.polar(ember.angle, 600) + Vector3.new(0, 3, 0), entry) == entry, "plateau")
	-- Back to camp from the lowland: in through the nearest gate.
	local back = Zones.guide(Zones.polar(math.rad(100), 400) + Vector3.new(0, 3, 0), Vector3.new(0, 0, 0))
	H.ok((back - Zones.polar(math.rad(120), Zones.GATE_D - 16)).Magnitude < 1, `gate back {back}`)
end)

H.finish("balance")
