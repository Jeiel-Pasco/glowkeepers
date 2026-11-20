--!strict
-- The world layout (Layer One, docs/LAYER_ONE.md). Rings out from the campfire:
--   r 0–260      the camp clearing, forest ring and ring wall (gates at GATE_D)
--   r 260–510    the LOWLAND: forest at FLOOR_Y, raider camps, roaming raiders
--   r 510–530    the CLIFF up to the plateau, climbed by parkour ledge routes
--   r 530–1150   the PLATEAU at PLATEAU_Y: forest and the three circle zones
--   r 1150       the sheer outer cliff and invisible wall (WORLD_R; layer two later)
-- Pure geometry plus the spawn table, shared by the map builder (tools/BuildZones.luau),
-- EnemyService and the client's quest guide.
--
-- Each zone is described in its own frame: `d` is the distance out from the campfire along the
-- zone's angle, `s` is sideways. A zone is a circle of ZONE_R round (ZONE_D, 0); its boss stands
-- at the centre (BOSS_D = ZONE_D).

-- Vector3 is a Roblox global; under Lune (tests) it comes from @lune/roblox.
-- selene: allow(incorrect_standard_library_use, shadowing)
local Vector3 = if script ~= nil then Vector3 else (require("@lune/roblox") :: any).Vector3

local Zones = {}

export type Zone = {
	id: string,
	name: string,
	type: string,
	angle: number, -- radians, from +X toward +Z
	minion: string,
	caster: string,
	boss: string,
}

Zones.FLOOR_Y = -1 -- the camp and the lowland
Zones.GATE_D = 262 -- the camp ring
Zones.GATE_HALF_ANGLE = math.rad(15) -- camp ring walls removed within this of a zone's angle
Zones.CAMP_R = 255 -- the builder leaves the camp terrain alone inside this

Zones.CLIFF_IN = 510 -- the lowland ends at the cliff foot
Zones.CLIFF_OUT = 530 -- the plateau starts at the cliff top
Zones.CLIFF_HEIGHT = 60
Zones.PLATEAU_Y = Zones.FLOOR_Y + Zones.CLIFF_HEIGHT
Zones.WORLD_R = 1150 -- the outer cliff and invisible wall
Zones.OUTER_CLIFF_HEIGHT = 80 -- sheer, unclimbable until layer two

Zones.ZONE_D = 820 -- zone circle centre
Zones.ZONE_R = 180
Zones.BOSS_D = Zones.ZONE_D

-- Parkour: two ledge routes per zone, at its angle ±ROUTE_OFFSET. Each route is a staircase of
-- rock ledges along the cliff face, LEDGE_RISE up and LEDGE_STEP sideways each (JumpHeight 7.2).
Zones.ROUTE_OFFSET = math.rad(20)
Zones.LEDGE_RISE = 5
Zones.LEDGE_STEP = 7
Zones.LEDGE_SIZE = Vector3.new(4, 1, 4)

-- Raider camps: a few of these sites are used per server (step 4). All in the lowland, between
-- the zones and clear of the ledge routes.
Zones.CAMP_SITE_R = 30
Zones.CAMP_SITES = {} :: { { angle: number, r: number } }
for _, gap in { 60, 180, 300 } do
	table.insert(Zones.CAMP_SITES, { angle = math.rad(gap - 18), r = 380 })
	table.insert(Zones.CAMP_SITES, { angle = math.rad(gap), r = 330 })
	table.insert(Zones.CAMP_SITES, { angle = math.rad(gap + 18), r = 440 })
end

Zones.list = {
	{
		id = "emberfall",
		name = "Emberfall Ridge",
		type = "Fire",
		angle = 0,
		minion = "ember_imp",
		caster = "cinder_caster",
		boss = "cinder_golem",
	},
	{
		id = "mistfall",
		name = "Mistfall Basin",
		type = "Water",
		angle = math.rad(120),
		minion = "tide_crab",
		caster = "mist_caster",
		boss = "tide_warden",
	},
	{
		id = "elderwood",
		name = "Elderwood",
		type = "Leaf",
		angle = math.rad(240),
		minion = "thorn_sprout",
		caster = "spore_caster",
		boss = "elder_treant",
	},
} :: { Zone }

-- Packs in rings round the zone centre: `ring` studs out, at `a` degrees (180 faces the camp,
-- where players come in). Outer ring L2–5, middle L6–9, inner L10–11, the boss at the centre.
-- `d`/`s` are filled in below from `ring`/`a`.
Zones.PACKS = {
	{ role = "minion", ring = 145, a = 180, level = 2 },
	{ role = "minion", ring = 145, a = 140, level = 3 },
	{ role = "minion", ring = 145, a = 220, level = 4 },
	{ role = "minion", ring = 145, a = 100, level = 5 },
	{ role = "caster", ring = 145, a = 260, level = 5 },
	{ role = "minion", ring = 100, a = 150, level = 6 },
	{ role = "caster", ring = 100, a = 210, level = 7 },
	{ role = "minion", ring = 100, a = 90, level = 8 },
	{ role = "minion", ring = 100, a = 270, level = 9 },
	{ role = "caster", ring = 45, a = 120, level = 10 },
	{ role = "caster", ring = 45, a = 240, level = 10 },
	{ role = "minion", ring = 45, a = 0, level = 11 },
	{ role = "boss", ring = 0, a = 0, level = 12 },
} :: { { role: string, ring: number, a: number, level: number, d: number, s: number } }
for _, pack in Zones.PACKS do
	pack.d = Zones.ZONE_D + pack.ring * math.cos(math.rad(pack.a))
	pack.s = pack.ring * math.sin(math.rad(pack.a))
end

-- The tutorial trail, east of the campfire inside the camp ring (before your element pick).
Zones.TRAIL = {
	{ kind = "ember_imp", x = 172, z = 22, level = 1 },
	{ kind = "ember_imp", x = 190, z = -22, level = 1 },
	{ kind = "ember_imp", x = 212, z = 16, level = 2 },
	{ kind = "ashling", x = 238, z = 0, level = 3, wander = 6 },
}

-- Raiders roam the lowland between the zones, outside the camp sites.
Zones.RAIDER_WANDER = 40
Zones.RAIDERS = {
	{ angle = math.rad(60), r = 470, level = 3 },
	{ angle = math.rad(180), r = 470, level = 6 },
	{ angle = math.rad(300), r = 470, level = 9 },
}

-- Ground height at a distance from the campfire (the cliff as a straight ramp; the builder adds
-- noise on top).
function Zones.groundY(r: number): number
	local t = math.clamp((r - Zones.CLIFF_IN) / (Zones.CLIFF_OUT - Zones.CLIFF_IN), 0, 1)
	return Zones.FLOOR_Y + t * Zones.CLIFF_HEIGHT
end

-- A point on the ground at an angle and distance from the campfire.
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

-- The zone a player's quests point at: their element's, or Emberfall before the pick.
function Zones.forElement(element: string): Zone
	return Zones.byType(element) or Zones.list[1]
end

export type Route = { zone: Zone, angle: number, ledges: { Vector3 } }

-- The parkour routes up the cliff. Each ledge is the centre of its TOP face (the builder puts a
-- LEDGE_SIZE rock just below it), sticking out of the face where the cliff is that high.
function Zones.routes(): { Route }
	local out: { Route } = {}
	local count = math.ceil(Zones.CLIFF_HEIGHT / Zones.LEDGE_RISE) - 1
	for _, zone in Zones.list do
		for _, side in { -1, 1 } do
			local angle = zone.angle + side * Zones.ROUTE_OFFSET
			local ledges = {}
			for i = 1, count do
				local h = i * Zones.LEDGE_RISE
				local face = Zones.CLIFF_IN + (Zones.CLIFF_OUT - Zones.CLIFF_IN) * h / Zones.CLIFF_HEIGHT
				local r = face - Zones.LEDGE_SIZE.Z / 2
				-- climb toward the zone's angle, away from the raider camps
				local along = -side * (i - 1) * Zones.LEDGE_STEP
				local a = angle + along / r
				table.insert(ledges, Vector3.new(math.cos(a) * r, Zones.FLOOR_Y + h, math.sin(a) * r))
			end
			table.insert(out, { zone = zone, angle = angle, ledges = ledges })
		end
	end
	return out
end

-- Raider camp candidate centres, on the ground.
function Zones.campSites(): { Vector3 }
	local out = {}
	for _, site in Zones.CAMP_SITES do
		table.insert(out, Zones.polar(site.angle, site.r))
	end
	return out
end

-- Where a player heading for a zone walks in: just inside the circle, on the side facing camp.
function Zones.entry(zone: Zone): Vector3
	return Zones.toWorld(zone, Zones.ZONE_D - Zones.ZONE_R + 25, 0)
end

local function flatR(v: Vector3): number
	return math.sqrt(v.X * v.X + v.Z * v.Z)
end

-- The nearest camp ring gate to an angle, just past the ring on the inside or outside.
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

-- The next point for the quest guide on the way from `from` (a HumanoidRootPart position) to
-- `target`: through a camp ring gate, then up the nearest ledge route to reach the plateau.
local guideRoutes: { Route }? = nil -- built once; the guide runs every frame
function Zones.guide(from: Vector3, target: Vector3): Vector3
	local fromR, targetR = flatR(from), flatR(target)
	local point = target
	local feet = from.Y - 3
	if targetR > Zones.CLIFF_OUT and feet < Zones.PLATEAU_Y - 4 and fromR < Zones.CLIFF_OUT + 10 then
		local best, bestCost = nil, math.huge
		guideRoutes = guideRoutes or Zones.routes()
		for _, route in guideRoutes :: { Route } do
			local first, last = route.ledges[1], route.ledges[#route.ledges]
			local cost = (Vector3.new(from.X, 0, from.Z) - Vector3.new(first.X, 0, first.Z)).Magnitude
				+ (target - last).Magnitude
			if cost < bestCost then
				best, bestCost = route, cost
			end
		end
		assert(best, "no routes")
		point = target
		for _, ledge in best.ledges do
			if ledge.Y > feet + 1 then
				point = ledge
				break
			end
		end
	end
	local pointR = flatR(point)
	if fromR < Zones.GATE_D and pointR > Zones.GATE_D then
		return gateToward(math.atan2(point.Z, point.X), true)
	elseif fromR > Zones.GATE_D and pointR < Zones.GATE_D and fromR < Zones.CLIFF_IN then
		return gateToward(math.atan2(from.Z, from.X), false)
	end
	return point
end

export type Spawn = { kind: string, pos: Vector3, level: number, wander: number? }

function Zones.spawns(): { Spawn }
	local out: { Spawn } = {}
	for _, t in Zones.TRAIL do
		table.insert(
			out,
			{ kind = t.kind, pos = Vector3.new(t.x, 0, t.z), level = t.level, wander = (t :: any).wander }
		)
	end
	for _, zone in Zones.list do
		for _, pack in Zones.PACKS do
			local kind = (zone :: any)[pack.role]
			table.insert(out, {
				kind = kind,
				pos = Zones.toWorld(zone, pack.d, pack.s),
				level = pack.level,
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
