--!strict
-- The world layout: Compact Wizard Hub + 3 Black Clover Level-Tiered Areas (Lv 1–50).
--   r 0–80       WIZARD CAMP COURTYARD (safe hub at y=-1: campfire, desk, shelf, bank, gear shop)
--   r 82         three courtyard gates at 0° (Area 1), 120° (Area 2), 240° (Area 3)
--   r 82–270     LOWLAND WILD FOREST: random Neutral Forest Wisps, Raider Camps, Quest Giver 1
--   r 270–290    VALLEY THRESHOLD (~28 studs high) with smooth lantern trail ramps
--   r 290–620    THREE LEVEL-TIERED AREAS (all cohesive Forest & Ancient Ruins):
--                  * Area 1 (0°):   Whispering Woods (Lv 1–15, Boss: Runestone Brute)
--                  * Area 2 (120°): Raider Wilds (Lv 15–30, Boss: Elder Treant)
--                  * Area 3 (240°): Highland Ruins (Lv 30–50, Boss: Ancient Mineral Golem)
--   r 700        outer mountain rim and invisible wall (WORLD_R)

-- Vector3 is a Roblox global; under Lune (tests) it comes from @lune/roblox.
-- selene: allow(incorrect_standard_library_use, shadowing)
local Vector3 = if script ~= nil then Vector3 else (require("@lune/roblox") :: any).Vector3

local Zones = {}

export type Zone = {
	id: string,
	areaId: string,
	name: string,
	type: string,
	levelRange: string,
	minLevel: number,
	maxLevel: number,
	angle: number, -- radians, from +X toward +Z
	minion: string,
	caster: string,
	boss: string,
}

Zones.FLOOR_Y = -1
Zones.CAMP_R = 80
Zones.GATE_D = 82
Zones.GATE_HALF_ANGLE = math.rad(16)

-- South Duel Arena Ring, just outside the courtyard: anyone inside may duel anyone else inside.
Zones.ARENA_X = 0
Zones.ARENA_Z = 114
Zones.ARENA_R = 24

function Zones.inArena(pos: Vector3): boolean
	local dx, dz = pos.X - Zones.ARENA_X, pos.Z - Zones.ARENA_Z
	return dx * dx + dz * dz < Zones.ARENA_R * Zones.ARENA_R
end

-- Shared station positions inside the Wizard Camp Courtyard (r < CAMP_R).
Zones.DESK_POS = Vector3.new(-24, Zones.FLOOR_Y, -16)
Zones.SHELF_POS = Vector3.new(-14, Zones.FLOOR_Y, -24)
Zones.BANK_POS = Vector3.new(0, Zones.FLOOR_Y, -28)
Zones.SHOP_POS = Vector3.new(24, Zones.FLOOR_Y, -16)

Zones.CLIFF_IN = 270
Zones.CLIFF_OUT = 290
Zones.CLIFF_HEIGHT = 28
Zones.PLATEAU_Y = Zones.FLOOR_Y + Zones.CLIFF_HEIGHT
Zones.WORLD_R = 700
Zones.OUTER_CLIFF_HEIGHT = 65

Zones.ZONE_D = 460
Zones.ZONE_R = 160
Zones.BOSS_D = 565

Zones.RAMP_SPAN = math.rad(16)
Zones.RAMP_WIDTH = 16
Zones.RAMP_R0 = Zones.CLIFF_IN - 4
Zones.RAMP_R1 = Zones.CLIFF_OUT + 4

-- Raider camps sit in the 3 wild forest wedges between the valleys (60°, 180°, 300°).
Zones.CAMP_SITE_R = 24
Zones.CAMP_SITES = {} :: { { angle: number, r: number } }
for _, gap in { 60, 180, 300 } do
	table.insert(Zones.CAMP_SITES, { angle = math.rad(gap - 19), r = 185 })
	table.insert(Zones.CAMP_SITES, { angle = math.rad(gap), r = 135 })
	table.insert(Zones.CAMP_SITES, { angle = math.rad(gap + 19), r = 225 })
end

Zones.list = {
	{
		id = "emberfall",
		areaId = "area1",
		name = "Whispering Woods",
		type = "Leaf",
		levelRange = "Lv 1–15",
		minLevel = 1,
		maxLevel = 15,
		angle = 0,
		minion = "thorn_sprout",
		caster = "spore_caster",
		boss = "ashling",
	},
	{
		id = "mistfall",
		areaId = "area2",
		name = "Raider Wilds",
		type = "Water",
		levelRange = "Lv 15–30",
		minLevel = 15,
		maxLevel = 30,
		angle = math.rad(120),
		minion = "raider_brute",
		caster = "mist_caster",
		boss = "elder_treant",
	},
	{
		id = "elderwood",
		areaId = "area3",
		name = "Highland Ruins",
		type = "Fire",
		levelRange = "Lv 30–50",
		minLevel = 30,
		maxLevel = 50,
		angle = math.rad(240),
		minion = "ember_imp",
		caster = "cinder_caster",
		boss = "cinder_golem",
	},
} :: { Zone }

-- Quest Giver NPC locations at the entrance of each Area.
Zones.QUEST_GIVERS = {
	{ areaId = "area1", npcName = "Elder Orsi", angle = 0, r = 104 },
	{ areaId = "area2", npcName = "Scout Captain", angle = math.rad(120), r = 304 },
	{ areaId = "area3", npcName = "Knight Envoy", angle = math.rad(240), r = 304 },
}

-- Relative pack layout front-to-back up each valley (`t` in 0..1 scales from zone.minLevel..maxLevel).
-- The front pack sits near the area's entry level, so a player who just reached it has on-level foes.
Zones.PACKS = {
	{ role = "minion", d = 345, s = 0, t = 0.05 },
	{ role = "minion", d = 360, s = -55, t = 0.12 },
	{ role = "minion", d = 360, s = 55, t = 0.18 },
	{ role = "minion", d = 395, s = -95, t = 0.27 },
	{ role = "caster", d = 395, s = 95, t = 0.31 },
	{ role = "minion", d = 425, s = -35, t = 0.44 },
	{ role = "caster", d = 425, s = 35, t = 0.51 },
	{ role = "minion", d = 465, s = -85, t = 0.64 },
	{ role = "minion", d = 465, s = 85, t = 0.70 },
	{ role = "caster", d = 505, s = -50, t = 0.80 },
	{ role = "caster", d = 505, s = 50, t = 0.85 },
	{ role = "minion", d = 515, s = 0, t = 0.90 },
	{ role = "boss", d = Zones.BOSS_D, s = 0, t = 1.0 },
} :: { { role: string, d: number, s: number, t: number } }

-- Wild Neutral creatures in the lowland forest outside the gates (Area 1: Lv 1–5).
Zones.WILD_COUNTS = {
	{ kind = "forest_wisp", level = 1, count = 4, wander = 18 },
	{ kind = "forest_wisp", level = 3, count = 3, wander = 18 },
	{ kind = "ashling", level = 5, count = 1, wander = 14 },
}

-- Raiders roam the outer lowland forest wedges between the valleys.
Zones.RAIDER_WANDER = 16
Zones.RAIDERS = {
	{ angle = math.rad(60), r = 248, level = 15 },
	{ angle = math.rad(180), r = 248, level = 18 },
	{ angle = math.rad(300), r = 248, level = 22 },
}

function Zones.groundY(r: number): number
	local t = math.clamp((r - Zones.CLIFF_IN) / (Zones.CLIFF_OUT - Zones.CLIFF_IN), 0, 1)
	return Zones.FLOOR_Y + t * Zones.CLIFF_HEIGHT
end

function Zones.polar(angle: number, r: number): Vector3
	return Vector3.new(math.cos(angle) * r, Zones.groundY(r), math.sin(angle) * r)
end

function Zones.toWorld(zone: Zone, d: number, s: number): Vector3
	local c, n = math.cos(zone.angle), math.sin(zone.angle)
	local x, z = d * c - s * n, d * n + s * c
	return Vector3.new(x, Zones.groundY(math.sqrt(x * x + z * z)), z)
end

function Zones.byType(kind: string): Zone?
	for _, zone in Zones.list do
		if zone.type == kind then
			return zone
		end
	end
	return nil
end

function Zones.forElement(element: string): Zone
	return Zones.byType(element) or Zones.list[1]
end

function Zones.rampAt(zone: Zone, t: number): Vector3
	local a = zone.angle + (t - 0.5) * Zones.RAMP_SPAN
	local r = Zones.RAMP_R0 + (Zones.RAMP_R1 - Zones.RAMP_R0) * t
	return Vector3.new(math.cos(a) * r, Zones.FLOOR_Y + Zones.CLIFF_HEIGHT * t, math.sin(a) * r)
end

function Zones.rampFrame(zone: Zone, x: number, z: number): (number, number)
	local gap = (math.atan2(z, x) - zone.angle + math.pi) % (2 * math.pi) - math.pi
	local t = gap / Zones.RAMP_SPAN + 0.5
	local r = math.sqrt(x * x + z * z)
	return t, r - (Zones.RAMP_R0 + (Zones.RAMP_R1 - Zones.RAMP_R0) * math.clamp(t, 0, 1))
end

local function wiggle(from: Vector3, to: Vector3, steps: number, amp: number, phase: number, out: { Vector3 })
	local side = Vector3.new(-(to.Z - from.Z), 0, to.X - from.X).Unit
	for i = 1, steps do
		local p = from:Lerp(to, i / steps)
		if i < steps then
			p += side * math.sin(i * 1.9 + phase) * amp
		end
		table.insert(out, Vector3.new(p.X, Zones.groundY(math.sqrt(p.X * p.X + p.Z * p.Z)), p.Z))
	end
end

function Zones.trail(zone: Zone): { Vector3 }
	local phase = zone.angle * 3
	local out = { Zones.polar(zone.angle, Zones.GATE_D + 6) }
	local bottom = Zones.rampAt(zone, 0)
	local foot = Vector3.new(bottom.X, 0, bottom.Z).Unit * (Zones.RAMP_R0 - 12)
	wiggle(out[1], foot, 6, 8, phase, out)
	for i = 0, 6 do
		table.insert(out, Zones.rampAt(zone, i / 6))
	end
	local top = Zones.rampAt(zone, 1)
	local rim = Vector3.new(top.X, 0, top.Z).Unit * (Zones.RAMP_R1 + 12)
	table.insert(out, Zones.polar(math.atan2(rim.Z, rim.X), rim.Magnitude))
	wiggle(out[#out], Zones.entry(zone), 2, 5, phase + 1, out)
	return out
end

function Zones.campSites(): { Vector3 }
	local out = {}
	for _, site in Zones.CAMP_SITES do
		table.insert(out, Zones.polar(site.angle, site.r))
	end
	return out
end

function Zones.entry(zone: Zone): Vector3
	return Zones.toWorld(zone, Zones.ZONE_D - Zones.ZONE_R + 25, 0)
end

function Zones.randomWildPos(rand: (() -> number)?): Vector3
	local nextNum = rand or math.random
	local sites = Zones.campSites()
	for _ = 1, 30 do
		local angle = nextNum() * math.pi * 2
		local r = Zones.GATE_D + 22 + nextNum() * (Zones.CLIFF_IN - Zones.GATE_D - 34)
		local p = Zones.polar(angle, r)
		local ok = true
		for _, site in sites do
			if (p - site).Magnitude < Zones.CAMP_SITE_R + 12 then
				ok = false
				break
			end
		end
		if ok then
			return p
		end
	end
	return Zones.polar(nextNum() * math.pi * 2, (Zones.GATE_D + Zones.CLIFF_IN) * 0.5)
end

local function flatR(v: Vector3): number
	return math.sqrt(v.X * v.X + v.Z * v.Z)
end

local function gateToward(angle: number, outside: boolean): Vector3
	local best, bestGap = Zones.list[1], math.huge
	for _, zone in Zones.list do
		local gap = math.abs((angle - zone.angle + math.pi) % (2 * math.pi) - math.pi)
		if gap < bestGap then
			best, bestGap = zone, gap
		end
	end
	return Zones.polar(best.angle, Zones.GATE_D + (if outside then 16 else -16))
end

local guideTrails: { { Vector3 } }? = nil
function Zones.guide(from: Vector3, target: Vector3): Vector3
	local fromR, targetR = flatR(from), flatR(target)
	local point = target
	if targetR > Zones.CLIFF_OUT and from.Y - 3 < Zones.PLATEAU_Y - 4 and fromR < Zones.CLIFF_OUT + 10 then
		if guideTrails == nil then
			local trails = {}
			for _, zone in Zones.list do
				table.insert(trails, Zones.trail(zone))
			end
			guideTrails = trails
		end
		local best, bestEnd = nil, math.huge
		for _, trail in guideTrails :: { { Vector3 } } do
			local d = (trail[#trail] - target).Magnitude
			if d < bestEnd then
				best, bestEnd = trail, d
			end
		end
		assert(best, "no trails")
		local near, nearD, rampFoot = 1, math.huge, 1
		for i, p in best do
			local d = (p - from).Magnitude
			if d < nearD then
				near, nearD = i, d
			end
			if rampFoot == 1 and flatR(p) >= Zones.RAMP_R0 - 0.5 then
				rampFoot = i
			end
		end
		point = if nearD > 40 then best[rampFoot] else best[math.min(near + 2, #best)]
	end
	local pointR = flatR(point)
	if fromR < Zones.GATE_D and pointR > Zones.GATE_D then
		return gateToward(math.atan2(point.Z, point.X), true)
	elseif fromR > Zones.GATE_D and pointR < Zones.GATE_D and fromR < Zones.CLIFF_IN then
		return gateToward(math.atan2(from.Z, from.X), false)
	end
	return point
end

export type Spawn = { kind: string, pos: Vector3, level: number, wander: number?, wild: boolean? }

function Zones.spawns(): { Spawn }
	local out: { Spawn } = {}
	local i = 0
	local totalWild = 0
	for _, group in Zones.WILD_COUNTS do
		totalWild += group.count
	end
	for _, group in Zones.WILD_COUNTS do
		for _ = 1, group.count do
			i += 1
			local a = (i - 0.5) / totalWild * math.pi * 2 + 0.35
			local r = Zones.GATE_D + 26 + ((i * 37) % 60)
			table.insert(out, {
				kind = group.kind,
				pos = Zones.polar(a, r),
				level = group.level,
				wander = group.wander,
				wild = true,
			})
		end
	end
	for _, zone in Zones.list do
		for _, pack in Zones.PACKS do
			local kind = (zone :: any)[pack.role]
			local lv = math.floor(zone.minLevel + (zone.maxLevel - zone.minLevel) * pack.t + 0.5)
			table.insert(out, {
				kind = kind,
				pos = Zones.toWorld(zone, pack.d, pack.s),
				level = lv,
				wander = if pack.role == "boss" then 0 else nil,
			})
		end
	end
	for _, raider in Zones.RAIDERS do
		table.insert(out, {
			kind = "raider",
			pos = Zones.polar(raider.angle, raider.r),
			level = raider.level,
			wander = Zones.RAIDER_WANDER,
		})
	end
	return out
end

return Zones
