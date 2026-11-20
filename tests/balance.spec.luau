-- Balance: the numbers behind "fair at every level" (Shared.Enemies header).
-- The model player clicks their basic attack and casts one Common bolt on cooldown, with no
-- stat points spent. Enemies grow 10% per level, the same as the player's level power, so
-- on-level fights should take the same time at level 2 and level 12.
local H = require("./harness")
local Spells = require("../src/shared/Spells")
local Level = require("../src/shared/Level")
local Enemies = require("../src/shared/Enemies")
local Zones = require("../src/shared/Zones")
local RaiderCamps = require("../src/shared/RaiderCamps")
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

H.test("levelling 1 → 50 on on-level minions takes reasonable playtime", function()
	local seconds = 0
	local kind = Enemies.kinds.ember_imp
	for level = 1, Level.CAP - 1 do
		local kills = Level.xpToNext(level) / Enemies.xp(kind, level)
		local perKill = Enemies.maxHp(kind, level) / kitDps(level, "Fire") + 6
		seconds += kills * perKill
	end
	local hours = seconds / 3600
	H.ok(hours >= 1 and hours <= 120, `{hours} hours`)
end)

H.test("each area's front pack is near its entry level and the back pack near its cap", function()
	for _, zone in Zones.list do
		local low, high = math.huge, 0
		for _, pack in Zones.PACKS do
			if pack.role ~= "boss" then
				local lv = math.floor(zone.minLevel + (zone.maxLevel - zone.minLevel) * pack.t + 0.5)
				low, high = math.min(low, lv), math.max(high, lv)
			end
		end
		H.ok(low <= zone.minLevel + 2, `{zone.name} front pack Lv {low}`)
		H.ok(high >= zone.maxLevel - 3, `{zone.name} back pack Lv {high}`)
	end
end)

H.test("every zone pack has a real enemy kind; zones sit apart and inside the world", function()
	local count = 0
	for _, spawn in Zones.spawns() do
		H.ok(Enemies.kinds[spawn.kind], `kind {spawn.kind}`)
		H.ok(spawn.pos.Magnitude < Zones.WORLD_R - 40, `{spawn.kind} inside the world`)
		count += 1
	end
	H.ok(count <= 60, `{count} enemies in the world`)
	-- Packs at least 40 studs apart (past minion and caster aggro), so one pull is one pack, and
	-- every pack inside its zone valley.
	for _, zone in Zones.list do
		local centre = Zones.toWorld(zone, Zones.ZONE_D, 0)
		for i, a in Zones.PACKS do
			local pa = Zones.toWorld(zone, a.d, a.s)
			H.ok((pa - centre).Magnitude <= Zones.ZONE_R - 25, `{zone.id} pack {i} inside the valley`)
			H.ok(math.abs(pa.Y - Zones.PLATEAU_Y) < 0.01, `{zone.id} pack {i} on the valley plateau`)
			for j, b in Zones.PACKS do
				if i < j then
					local d = (pa - Zones.toWorld(zone, b.d, b.s)).Magnitude
					H.ok(d >= 40, `{zone.id} packs {i},{j} {d}`)
				end
			end
		end
	end
end)

H.test("wild Neutral forest spawns pick valid lowland positions outside the hub and clear of camps", function()
	local i = 0
	for _ = 1, 40 do
		local p = Zones.randomWildPos(function()
			i = (i + 1) % 97
			return (i + 0.5) / 97
		end)
		local r = Vector3.new(p.X, 0, p.Z).Magnitude
		H.ok(r > Zones.GATE_D + 15 and r < Zones.CLIFF_IN - 8, `wild spawn r={r} in lowland`)
		for j, site in Zones.campSites() do
			H.ok((p - site).Magnitude >= Zones.CAMP_SITE_R + 10, `wild spawn clear of camp site {j}`)
		end
	end
end)

H.test("zone valleys sit beyond the threshold with forest wedges between them", function()
	H.ok(Zones.ZONE_D - Zones.ZONE_R >= Zones.CLIFF_OUT + 10, "valleys start past the threshold")
	H.ok(Zones.ZONE_D + Zones.ZONE_R <= Zones.WORLD_R - 80, "mountain rim behind each valley")
	local a, b = Zones.toWorld(Zones.list[1], Zones.ZONE_D, 0), Zones.toWorld(Zones.list[2], Zones.ZONE_D, 0)
	H.ok((a - b).Magnitude >= 2 * Zones.ZONE_R + 200, "zones far apart")
	H.ok(Zones.CAMP_R < Zones.GATE_D and Zones.GATE_D < Zones.CLIFF_IN, "courtyard, then lowland")
end)

local function angleGap(a: number, b: number): number
	return math.abs((a - b + math.pi) % (2 * math.pi) - math.pi)
end

H.test("each zone has a walkable ramp up the cliff", function()
	for _, zone in Zones.list do
		local bottom, top = Zones.rampAt(zone, 0), Zones.rampAt(zone, 1)
		H.ok(Vector3.new(bottom.X, 0, bottom.Z).Magnitude <= Zones.CLIFF_IN, `{zone.id} ramp starts in the lowland`)
		H.ok(math.abs(bottom.Y - Zones.FLOOR_Y) < 0.01, `{zone.id} ramp starts on the floor`)
		H.ok(Vector3.new(top.X, 0, top.Z).Magnitude >= Zones.CLIFF_OUT, `{zone.id} ramp ends on the plateau`)
		H.ok(math.abs(top.Y - Zones.PLATEAU_Y) < 0.01, `{zone.id} ramp ends at plateau height`)
		for i = 1, 40 do
			local a, b = Zones.rampAt(zone, (i - 1) / 40), Zones.rampAt(zone, i / 40)
			local run = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude
			local slope = math.deg(math.atan2(b.Y - a.Y, run))
			H.ok(slope > 0 and slope <= 25, `{zone.id} ramp slope {slope}`)
		end
		local p = Zones.rampAt(zone, 0.3)
		local t, off = Zones.rampFrame(zone, p.X, p.Z)
		H.ok(math.abs(t - 0.3) < 0.001 and math.abs(off) < 0.001, "rampFrame inverts rampAt")
	end
end)

H.test("lantern trails wind from each gate to its zone", function()
	for _, zone in Zones.list do
		local trail = Zones.trail(zone)
		H.ok(#trail >= 15, `{zone.id} {#trail} points`)
		H.ok((trail[#trail] - Zones.entry(zone)).Magnitude < 0.01, `{zone.id} trail ends at the entry`)
		for i = 2, #trail do
			local d = (trail[i] - trail[i - 1]).Magnitude
			H.ok(d >= 8 and d <= 45, `{zone.id} trail step {i} {d}`)
		end
		for _, p in trail do
			for j, site in Zones.campSites() do
				H.ok((p - site).Magnitude >= Zones.CAMP_SITE_R + 10, `{zone.id} trail clear of site {j}`)
			end
		end
	end
end)

H.test("raider camp sites sit in the lowland, apart and off the routes", function()
	local sites = Zones.campSites()
	H.ok(#sites >= 8, `{#sites} camp sites`)
	for i, site in Zones.CAMP_SITES do
		H.ok(site.r - Zones.CAMP_SITE_R >= Zones.GATE_D + 20, `site {i} outside the courtyard ring`)
		H.ok(site.r + Zones.CAMP_SITE_R <= Zones.CLIFF_IN - 15, `site {i} before the valley threshold`)
		local width = math.asin(Zones.CAMP_SITE_R / site.r)
		for _, zone in Zones.list do
			local gap = angleGap(site.angle, zone.angle) - Zones.RAMP_SPAN / 2 - width
			H.ok(gap >= math.rad(15), `site {i} clear of the {zone.id} ramp ({math.deg(gap)})`)
		end
		for j, other in sites do
			if j > i then
				local d = (sites[i] - other).Magnitude
				H.ok(d >= 2 * Zones.CAMP_SITE_R + 22, `sites {i},{j} {d}`)
			end
		end
		for _, raider in Zones.RAIDERS do
			local d = (sites[i] - Zones.polar(raider.angle, raider.r)).Magnitude
			H.ok(d >= Zones.CAMP_SITE_R + Zones.RAIDER_WANDER + 10, `site {i} clear of roaming raiders`)
		end
	end
	for _, raider in Zones.RAIDERS do
		H.ok(raider.r + Zones.RAIDER_WANDER <= Zones.CLIFF_IN, "raiders roam the lowland")
	end
end)

H.test("the quest guide goes through a gate and along the trail", function()
	local ember = Zones.list[1]
	local entry = Zones.entry(ember)
	local trail = Zones.trail(ember)
	H.ok(entry.Y > Zones.PLATEAU_Y - 5, "zone entry on the plateau")
	-- In camp: out through the nearest gate.
	local out = Zones.guide(Vector3.new(0, 3, 0), entry)
	H.ok((out - Zones.polar(ember.angle, Zones.GATE_D + 16)).Magnitude < 1, `gate first {out}`)
	-- On the trail in the lowland: a couple of points further along it.
	local on = trail[3] + Vector3.new(0, 3, 0)
	H.ok(Zones.guide(on, entry) == trail[5], "along the trail")
	-- Off the trail in the lowland: to the ramp's foot.
	local off = Zones.guide(Zones.polar(math.rad(-45), 180) + Vector3.new(0, 3, 0), entry)
	H.ok(math.abs(Vector3.new(off.X, 0, off.Z).Magnitude - Zones.RAMP_R0) < 1, `ramp foot {off}`)
	-- Halfway up the ramp: further up it.
	local mid = Zones.rampAt(ember, 0.5)
	H.ok(Zones.guide(mid + Vector3.new(0, 3, 0), entry).Y > mid.Y + 5, "up the ramp")
	-- On the plateau: straight there.
	H.ok(Zones.guide(Zones.polar(ember.angle, 300) + Vector3.new(0, 3, 0), entry) == entry, "plateau")
	-- Back to camp from the lowland: in through the nearest gate.
	local back = Zones.guide(Zones.polar(math.rad(100), 150) + Vector3.new(0, 3, 0), Vector3.new(0, 0, 0))
	H.ok((back - Zones.polar(math.rad(120), Zones.GATE_D - 16)).Magnitude < 1, `gate back {back}`)
end)

H.test("raider camp guards are a real fight at their camp's level", function()
	for _, site in Zones.CAMP_SITES do
		local level = RaiderCamps.level(site)
		H.ok(level >= 4 and level <= 8, `camp level {level}`)
		local brute, archer = Enemies.kinds.raider_brute, Enemies.kinds.raider_archer
		local bruteKill = Enemies.maxHp(brute, level) / kitDps(level, "Fire")
		H.ok(bruteKill >= 3 and bruteKill <= 6, `brute kit kill {bruteKill}s`)
		local archerKill = Enemies.maxHp(archer, level) / kitDps(level, "Fire")
		H.ok(archerKill >= 1.5 and archerKill <= 3, `archer kit kill {archerKill}s`)
		-- The whole camp at once kills an idle player in 5–10 s: walking in unready is deadly.
		local dps = 0
		for _, guard in RaiderCamps.GUARDS do
			dps += enemyDps(Enemies.kinds[guard.kind], level)
		end
		local survive = Level.maxHealth(level, 0) / dps
		H.ok(survive >= 5 and survive <= 10, `camp kills an idle player in {survive}s`)
	end
end)

H.test("raider camps: one per gap, guards inside, chest mostly coins", function()
	for _, n in { 1, 2, 3 } do
		local picks = RaiderCamps.pick(function()
			return n
		end)
		H.ok(#picks == RaiderCamps.ACTIVE, `{#picks} camps`)
		for gap, index in picks do
			local site = Zones.CAMP_SITES[index]
			local centre = math.deg(site.angle) - (gap - 1) * 120
			H.ok(math.abs(centre - 60) <= 20, `camp {gap} in gap {gap} ({centre})`)
		end
	end
	local centre = Vector3.new(400, 0, 0)
	for _, guard in RaiderCamps.GUARDS do
		local pos = RaiderCamps.guardPos(centre, Vector3.new(-1, 0, 0), guard)
		H.ok((pos - centre).Magnitude < RaiderCamps.WALL_R - 4, `{guard.kind} inside the wall`)
		H.ok(Enemies.kinds[guard.kind] and Enemies.kinds[guard.kind].guard, `{guard.kind} is a guard`)
	end
	local ink, coins = 0, 0
	for i = 1, 1000 do
		local bag = RaiderCamps.chestBag(6, (i - 0.5) / 1000, (i * 7 % 1000) / 1000)
		if next(bag.ink) then
			ink += 1
		else
			H.ok(bag.coins > 0, "coins otherwise")
			coins += 1
		end
	end
	H.ok(ink >= 80 and ink <= 120, `{ink} ink chests of 1000`)
end)

H.finish("balance")
