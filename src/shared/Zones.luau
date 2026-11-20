--!strict
-- The world layout (GDD "World"): the camp in the middle, three element zones around it, open
-- wilds between them, and the world edge. Pure geometry plus the spawn table, shared by the map
-- builder (tools/BuildZones.luau), EnemyService and the client's quest guide.
--
-- Each zone is described in its own frame: `d` is the distance out from the campfire along the
-- zone's angle, `s` is sideways. A zone runs from its gate in the camp ring (d ≈ 262) out to its
-- boss arena (d ≈ 610).

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

Zones.GATE_D = 262 -- the camp ring
Zones.BOSS_D = 610
Zones.WORLD_R = 700 -- invisible wall; the tree wall stands just past it
Zones.FLOOR_Y = -1
Zones.GATE_HALF_ANGLE = math.rad(15) -- camp ring walls removed within this of a zone's angle

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

-- The zone's floor: centre points along it and their radius.
Zones.PATH = {
	{ d = 270, s = 0, r = 48 },
	{ d = 320, s = 10, r = 70 },
	{ d = 385, s = 12, r = 82 },
	{ d = 455, s = -10, r = 80 },
	{ d = 530, s = 0, r = 72 },
	{ d = 610, s = 0, r = 70 },
}

-- Four packs of enemies, each well apart, then the boss. Level grows with distance.
Zones.PACKS = {
	{ role = "minion", d = 305, s = -16, level = 2 },
	{ role = "minion", d = 318, s = 18, level = 3 },
	{ role = "minion", d = 378, s = 34, level = 4 },
	{ role = "minion", d = 392, s = -8, level = 5 },
	{ role = "caster", d = 404, s = 40, level = 5 },
	{ role = "minion", d = 448, s = -38, level = 7 },
	{ role = "caster", d = 466, s = -16, level = 7 },
	{ role = "minion", d = 470, s = 30, level = 8 },
	{ role = "minion", d = 524, s = 12, level = 9 },
	{ role = "caster", d = 540, s = -30, level = 10 },
	{ role = "caster", d = 548, s = 34, level = 10 },
	{ role = "minion", d = 556, s = -2, level = 11 },
	{ role = "boss", d = Zones.BOSS_D, s = 0, level = 12 },
}

-- The tutorial trail, east of the campfire inside the camp ring (before your element pick).
Zones.TRAIL = {
	{ kind = "ember_imp", x = 172, z = 22, level = 1 },
	{ kind = "ember_imp", x = 190, z = -22, level = 1 },
	{ kind = "ember_imp", x = 212, z = 16, level = 2 },
	{ kind = "ashling", x = 238, z = 0, level = 3, wander = 6 },
}

-- Raiders roam the wilds between the zones.
Zones.RAIDERS = {
	{ angle = math.rad(60), r = 340, level = 3 },
	{ angle = math.rad(180), r = 360, level = 6 },
	{ angle = math.rad(300), r = 380, level = 9 },
}

function Zones.toWorld(zone: Zone, d: number, s: number): Vector3
	local c, n = math.cos(zone.angle), math.sin(zone.angle)
	return Vector3.new(d * c - s * n, Zones.FLOOR_Y, d * n + s * c)
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
			pos = Vector3.new(math.cos(raider.angle) * raider.r, 0, math.sin(raider.angle) * raider.r),
			level = raider.level,
			wander = 50,
		})
	end
	return out
end

return Zones
