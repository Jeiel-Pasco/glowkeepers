--!nocheck
-- Builder v2 for Layer One (docs/LAYER_ONE.md). Run once in Studio Edit, then save the place.
-- It rebuilds everything outside the camp (r ≥ Zones.CAMP_R) from Shared.Zones:
--   1. Clears the old world: Map.Zones, Map.WorldEdge, trees and props outside the camp, the camp's
--      floor decor (props, wood piles, flowers; the fireflies stay), and the last run's Map.Layer.
--   2. Writes a terrain heightmap with WriteVoxels in chunks: the lowland, a noisy cliff up to the
--      plateau with a ramp cut across it toward each zone, and the sheer outer cliff. Grass with a
--      few dirt patches; rock on the cliffs; faint dirt along the trails; each zone's material only
--      inside its circle. Camp voxels are kept.
--   3. An invisible wall at Zones.WORLD_R.
--   4. A mixed forest on a jitter grid (oaks, pines, birches, dead snags; varied muted greens),
--      clear of the zones, the raider camp sites, the cliff, the ramps and the trails. Canopies
--      neither collide nor block the camera (CanCollide/CanQuery off); trunks still collide.
--      Clusters of bushes, logs, stumps, rocks and mushrooms all through it; some mushrooms glow
--      at night (tag NightGlow, see CycleFXController).
--   5. Lanterns along each zone's trail (Zones.trail), lit at night.
--   6. Zone decor inside each circle, and the gates and signs in the camp ring.
-- It runs async: watch workspace's "BuildProgress" attribute (ends with "done").
-- Safe to run again. Run: copy to src/server/_tmp/, then in the command bar
--   task.spawn(loadstring(game.ServerScriptService.Server._tmp.BuildZones.Source))

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Zones = require(ReplicatedStorage.Shared.Zones)

local terrain = workspace.Terrain
local map = workspace.Map
local assets = ReplicatedStorage.WorldAssets.Forest
local FLOOR = Zones.FLOOR_Y
local M = Enum.Material
local TAU = math.pi * 2

local function progress(text)
	workspace:SetAttribute("BuildProgress", text)
end

local function part(parent, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.Anchored = true
	p.Shape = shape or Enum.PartType.Block
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function rngFor(seed)
	return Random.new(seed)
end

local function smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function angleGap(a, b)
	return math.abs((a - b + math.pi) % TAU - math.pi)
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function segmentDistance(p, a, b)
	local ab = b - a
	local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
	return (p - (a + ab * t)).Magnitude
end

-- A part that glows at night: Neon and its lights on (CycleFXController flips them).
local function nightGlow(p, color, range, brightness)
	p:SetAttribute("DayMaterial", p.Material.Name)
	CollectionService:AddTag(p, "NightGlow")
	if range then
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = range
		l.Brightness = brightness
		l.Shadows = false
		l.Enabled = false
		l.Parent = p
	end
end

-- Shape ---------------------------------------------------------------------------------------

local ZONE_MATERIAL = { emberfall = M.Basalt, mistfall = M.Sand, elderwood = M.LeafyGrass }
local CENTRES = {}
local TRAILS = {}
for _, zone in Zones.list do
	CENTRES[zone.id] = flat(Zones.toWorld(zone, Zones.ZONE_D, 0))
	local segs = {}
	local trail = Zones.trail(zone)
	for i = 2, #trail do
		table.insert(segs, { flat(trail[i - 1]), flat(trail[i]) })
	end
	TRAILS[zone.id] = { points = trail, segs = segs }
end
local SITES = Zones.campSites()
local RAMP_HALF = Zones.RAMP_WIDTH / 2

-- How far the cliff is pushed in or out at an angle: noisy, but calm where a ramp climbs.
local function cliffShift(a)
	local calm = 1
	for _, zone in Zones.list do
		calm = math.min(calm, smooth((angleGap(a, zone.angle) - Zones.RAMP_SPAN / 2 - math.rad(4)) / math.rad(5)))
	end
	local n = math.noise(math.cos(a) * 7, math.sin(a) * 7, 2.3)
		+ 0.5 * math.noise(math.cos(a) * 19, math.sin(a) * 19, 5.1)
	return n * 9 * calm
end

-- Flat distance from (x, z) to the nearest trail (only trails within 35° of it are checked).
local function trailDistance(x, z)
	local a = math.atan2(z, x)
	local p = Vector3.new(x, 0, z)
	local best = math.huge
	for _, zone in Zones.list do
		if angleGap(a, zone.angle) < math.rad(35) then
			for _, seg in TRAILS[zone.id].segs do
				best = math.min(best, segmentDistance(p, seg[1], seg[2]))
			end
		end
	end
	return best
end

-- How much of a zone's ramp is at (x, z) (0..1) and the ramp's height there.
local function rampAt(x, z)
	local bestWeight, bestY = 0, 0
	for _, zone in Zones.list do
		local t, off = Zones.rampFrame(zone, x, z)
		if t > -0.2 and t < 1.2 then
			local across = 1 - smooth((math.abs(off) - RAMP_HALF) / 10)
			local along = 1 - smooth(math.max(-t, t - 1) / 0.15)
			local weight = across * along
			if weight > bestWeight then
				bestWeight = weight
				bestY = FLOOR + Zones.CLIFF_HEIGHT * math.clamp(t, 0, 1)
			end
		end
	end
	return bestWeight, bestY
end

-- Ground height and material at (x, z), outside the camp.
local function ground(x, z)
	local r = math.sqrt(x * x + z * z)
	local a = math.atan2(z, x)
	local shift = cliffShift(a)
	local cliffIn = Zones.CLIFF_IN + shift
	local cliffOut = Zones.CLIFF_OUT + shift
	local hills = math.noise(x / 90, z / 90, 1.7) + 0.4 * math.noise(x / 31, z / 31, 3.9)
	-- The lowland: gentle, flat at the camp ring and at the cliff foot.
	local low = FLOOR + hills * 2.5 * smooth((r - Zones.GATE_D) / 40) * smooth((cliffIn - r) / 40)
	-- The plateau: a little rougher, flat at the cliff top and mostly flat inside the zones.
	local inZone = nil
	local zoneEdge = math.huge
	for _, zone in Zones.list do
		local c = CENTRES[zone.id]
		local d = Vector2.new(x - c.X, z - c.Z).Magnitude
		local edge = d - (Zones.ZONE_R + math.noise(x / 40, z / 40, 7.7) * 8)
		if edge < zoneEdge then
			zoneEdge = edge
			inZone = zone
		end
	end
	local high = Zones.PLATEAU_Y + hills * 3.5 * smooth((r - cliffOut) / 40) * (0.25 + 0.75 * smooth(zoneEdge / 30))
	local t = math.clamp((r - cliffIn) / (cliffOut - cliffIn), 0, 1)
	local h = low + (high - low) * t
	-- The ramps: a shelf cut diagonally across the cliff face.
	local ramp, rampY = 0, 0
	if r > Zones.CLIFF_IN - 40 and r < Zones.CLIFF_OUT + 40 then
		ramp, rampY = rampAt(x, z)
		h += (rampY - h) * ramp
	end
	-- The outer cliff: sheer, just inside the invisible wall.
	local outer = r - (Zones.WORLD_R - 8 + shift * 0.6)
	if outer > 0 then
		h += math.min(outer / 6, 1) * Zones.OUTER_CLIFF_HEIGHT + math.noise(x / 12, z / 12, 9.1) * 4
	end
	local material = M.Grass
	if (t > 0 and t < 1 and ramp < 0.3) or outer > -2 then
		material = M.Rock
	elseif zoneEdge < 0 and ramp <= 0.6 then
		material = ZONE_MATERIAL[inZone.id]
	else
		local trail = trailDistance(x, z) < 3 and math.noise(x / 9, z / 9, 4.4) > -0.25 -- faint, broken
		local patch = math.noise(x / 55, z / 55, 6.2) > 0.42 -- bare patches under the trees
		if ramp > 0.6 or trail or patch then
			material = M.Ground
		end
	end
	return h, material
end

-- 1. Clear --------------------------------------------------------------------------------------

progress("clearing")
for _, name in { "Zones", "WorldEdge", "Layer" } do
	local old = map:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end
local oldEmber = workspace:FindFirstChild("Emberfall")
if oldEmber then
	oldEmber:Destroy()
end
-- Trees outside the camp; all the camp's floor decor (but its fireflies).
for _, tree in map.Forest.Trees:GetChildren() do
	local pos = tree:GetPivot().Position
	if Vector2.new(pos.X, pos.Z).Magnitude > Zones.CAMP_R then
		tree:Destroy()
	end
end
for _, folder in { map.Forest.Props, map.Forest:FindFirstChild("WoodPiles"), map:FindFirstChild("Dressing") } do
	for _, thing in folder and folder:GetChildren() or {} do
		if thing.Name ~= "Fireflies" then
			thing:Destroy()
		end
	end
end
task.wait()

local layer = Instance.new("Folder")
layer.Name = "Layer"
layer.Parent = map
local function folderIn(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- 2. Terrain ------------------------------------------------------------------------------------

terrain:SetMaterialColor(M.Rock, Color3.fromRGB(104, 98, 90))
terrain:SetMaterialColor(M.Ground, Color3.fromRGB(106, 90, 70))
local RES = 4
local CHUNK = 128
local EXTENT = Zones.WORLD_R + 48 -- terrain ends here
local GRID = 1280 -- chunks tile -GRID..GRID, aligned to CHUNK
local BOTTOM = -24
local chunks = {}
for cx = -GRID, GRID - CHUNK, CHUNK do
	for cz = -GRID, GRID - CHUNK, CHUNK do
		local nx = math.clamp(0, cx, cx + CHUNK)
		local nz = math.clamp(0, cz, cz + CHUNK)
		local fx = math.max(math.abs(cx), math.abs(cx + CHUNK))
		local fz = math.max(math.abs(cz), math.abs(cz + CHUNK))
		if math.sqrt(fx * fx + fz * fz) > Zones.CAMP_R and math.sqrt(nx * nx + nz * nz) < EXTENT then
			table.insert(chunks, { cx, cz })
		end
	end
end
for i, c in chunks do
	progress(`terrain {i}/{#chunks}`)
	local cx, cz = c[1], c[2]
	local n = CHUNK / RES
	local heights, mats = {}, {}
	local top = 24
	for ix = 1, n do
		heights[ix], mats[ix] = {}, {}
		for iz = 1, n do
			local x, z = cx + (ix - 0.5) * RES, cz + (iz - 0.5) * RES
			local h, m = ground(x, z)
			heights[ix][iz], mats[ix][iz] = h, m
			top = math.max(top, h + 8)
		end
	end
	top = math.ceil(top / RES) * RES
	local region = Region3.new(Vector3.new(cx, BOTTOM, cz), Vector3.new(cx + CHUNK, top, cz + CHUNK))
	local voxMats, voxOcc = terrain:ReadVoxels(region, RES)
	local ny = (top - BOTTOM) / RES
	for ix = 1, n do
		local x = cx + (ix - 0.5) * RES
		for iz = 1, n do
			local z = cz + (iz - 0.5) * RES
			if math.sqrt(x * x + z * z) >= Zones.CAMP_R then
				local h, m = heights[ix][iz], mats[ix][iz]
				for iy = 1, ny do
					local occ = math.clamp((h - (BOTTOM + (iy - 1) * RES)) / RES, 0, 1)
					voxMats[ix][iy][iz] = if occ > 0 then m else M.Air
					voxOcc[ix][iy][iz] = occ
				end
			end
		end
	end
	terrain:WriteVoxels(region, RES, voxMats, voxOcc)
	task.wait()
end

-- 3. The edge -----------------------------------------------------------------------------------

local edge = folderIn(layer, "Edge")
local SEGMENTS = 96
for i = 1, SEGMENTS do
	local a = i / SEGMENTS * TAU
	local y = Zones.PLATEAU_Y + 100
	local pos = Vector3.new(math.cos(a) * Zones.WORLD_R, y, math.sin(a) * Zones.WORLD_R)
	local wall = part(
		edge,
		Vector3.new(TAU * Zones.WORLD_R / SEGMENTS + 2, 260, 2),
		CFrame.lookAt(pos, Vector3.new(0, y, 0)),
		Color3.new(),
		M.SmoothPlastic
	)
	wall.Transparency = 1
	wall.CanQuery = false
end
game:GetService("StarterPlayer").CharacterMaxSlopeAngle = 50 -- cliffs only by the ramps
task.wait()

-- 4. Forest -------------------------------------------------------------------------------------

local function clear(pos)
	local r = pos.Magnitude
	if r < Zones.CAMP_R + 8 or r > Zones.WORLD_R - 14 then
		return false
	end
	local shift = cliffShift(math.atan2(pos.Z, pos.X))
	if r > Zones.CLIFF_IN + shift - 8 and r < Zones.CLIFF_OUT + shift + 8 then
		return false
	end
	if r > Zones.CLIFF_IN - 30 and r < Zones.CLIFF_OUT + 30 and rampAt(pos.X, pos.Z) > 0.05 then
		return false
	end
	for _, c in CENTRES do
		if (pos - c).Magnitude < Zones.ZONE_R + 10 then
			return false
		end
	end
	for _, site in SITES do
		if (pos - flat(site)).Magnitude < Zones.CAMP_SITE_R + 8 then
			return false
		end
	end
	return trailDistance(pos.X, pos.Z) >= 6
end

-- Muted greens, a few olive and autumn ones.
local LEAVES = {
	Color3.fromRGB(70, 112, 60),
	Color3.fromRGB(84, 122, 64),
	Color3.fromRGB(98, 134, 70),
	Color3.fromRGB(62, 98, 70),
	Color3.fromRGB(112, 128, 72),
	Color3.fromRGB(128, 136, 78),
	Color3.fromRGB(146, 116, 70),
}
local function leafColor(rng)
	local i = rng:NextInteger(1, #LEAVES + 2) -- the first two twice as common
	return LEAVES[if i > #LEAVES then i - #LEAVES else i]
end

-- An asset tree (Trunk + Leaves), scaled and standing on the ground.
local function assetTree(name, min, max)
	return function(parent, rng, x, z)
		local tree = assets[name]:Clone()
		tree.Name = "Tree"
		tree:ScaleTo(rng:NextNumber(min, max))
		local cf, size = tree:GetBoundingBox()
		local base = cf.Position.Y - size.Y / 2
		local color = leafColor(rng)
		tree:PivotTo(
			CFrame.new(x, ground(x, z) - 1 + (tree:GetPivot().Position.Y - base), z)
				* CFrame.Angles(rng:NextNumber(-0.04, 0.04), rng:NextNumber(0, TAU), rng:NextNumber(-0.04, 0.04))
		)
		for _, p in tree:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = true
				if p.Name == "Leaves" then
					p.CanCollide = false
					p.CanQuery = false
					p.CanTouch = false
					p.Color = color
				end
			end
		end
		tree.Parent = parent
	end
end

local function canopyPart(model, size, cf, color)
	local p = part(model, size, cf, color, M.Grass)
	p.Name = "Leaves"
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- A birch: a tall pale trunk and a few chunky blocks of light leaves high up.
local function birch(parent, rng, x, z)
	local model = Instance.new("Model")
	model.Name = "Tree"
	local h = rng:NextNumber(30, 42)
	local w = rng:NextNumber(1.6, 2.4)
	local base = CFrame.new(x, ground(x, z) - 1, z) * CFrame.Angles(rng:NextNumber(-0.05, 0.05), 0, 0)
	local trunk =
		part(model, Vector3.new(w, h, w), base * CFrame.new(0, h / 2, 0), Color3.fromRGB(196, 190, 176), M.Wood)
	trunk.Name = "Trunk"
	local color = Color3.fromRGB(128, 146, 80):Lerp(Color3.fromRGB(104, 132, 72), rng:NextNumber())
	for k = 1, 3 do
		local a = rng:NextNumber(0, TAU)
		local s = rng:NextNumber(8, 12)
		canopyPart(
			model,
			Vector3.new(s, s * 0.7, s),
			base
				* CFrame.new(math.cos(a) * 3, h - 4 + k * 2.5, math.sin(a) * 3)
				* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, TAU), rng:NextNumber(-0.4, 0.4)),
			color
		)
	end
	model.Parent = parent
end

-- A dead snag: a bare grey trunk and a branch or two.
local function snag(parent, rng, x, z)
	local model = Instance.new("Model")
	model.Name = "Tree"
	local h = rng:NextNumber(16, 26)
	local w = rng:NextNumber(2, 3)
	local bark = Color3.fromRGB(96, 88, 80)
	local base = CFrame.new(x, ground(x, z) - 1, z)
		* CFrame.Angles(rng:NextNumber(-0.08, 0.08), rng:NextNumber(0, TAU), rng:NextNumber(-0.08, 0.08))
	local trunk = part(model, Vector3.new(w, h, w), base * CFrame.new(0, h / 2, 0), bark, M.Wood)
	trunk.Name = "Trunk"
	for k = 1, rng:NextInteger(1, 2) do
		local len = rng:NextNumber(5, 8)
		part(
			model,
			Vector3.new(len, w * 0.45, w * 0.45),
			base * CFrame.new(0, h * (0.55 + k * 0.15), 0) * CFrame.Angles(0, k * 2.4, 0.5) * CFrame.new(len / 2, 0, 0),
			bark,
			M.Wood
		)
	end
	model.Parent = parent
end

local TREES = {
	{ weight = 30, plant = assetTree("Tree_Oak_Tall", 2.6, 3.8) },
	{ weight = 22, plant = assetTree("Tree_Oak_Round", 1.2, 1.8) },
	{ weight = 14, plant = assetTree("Tree_Pine_Tall", 3.2, 4.5) },
	{ weight = 8, plant = assetTree("Tree_Pine_Classic", 4, 5.5) },
	{ weight = 16, plant = birch },
	{ weight = 6, plant = snag },
}
local PROPS = {
	{ name = "Bush_Round", weight = 6, collide = false, min = 1.2, max = 2 },
	{ name = "Bush_Wide", weight = 5, collide = false, min = 1.2, max = 2 },
	{ name = "Bush_Compact", weight = 5, collide = false, min = 1.2, max = 2 },
	{ name = "Bush_Berries", weight = 3, collide = false, min = 1, max = 1.6 },
	{ name = "Rock_Mossy", weight = 3, collide = true, min = 0.8, max = 1.6 },
	{ name = "Rock_Boulder", weight = 2, collide = true, min = 1, max = 2 },
	{ name = "Rock_Flat", weight = 2, collide = true, min = 1, max = 1.8 },
	{ name = "Rock_Pebble", weight = 2, collide = false, min = 1, max = 2 },
	{ name = "Log_Fallen", weight = 3, collide = true, min = 1, max = 1.5 },
	{ name = "Stump_Short", weight = 2, collide = true, min = 1, max = 1.5 },
	{ name = "Stump_Branch", weight = 2, collide = true, min = 1, max = 1.5 },
	{
		name = "Mushrooms_Brown_Cluster",
		weight = 3,
		collide = false,
		min = 1,
		max = 1.6,
		glow = Color3.fromRGB(200, 170, 120),
	},
	{
		name = "Mushrooms_Red_Cluster",
		weight = 2,
		collide = false,
		min = 1,
		max = 1.6,
		glow = Color3.fromRGB(220, 120, 100),
	},
	{
		name = "Mushrooms_Golden_Cluster",
		weight = 2,
		collide = false,
		min = 1,
		max = 1.6,
		glow = Color3.fromRGB(230, 200, 110),
	},
	{ name = "Mushroom_Brown", weight = 2, collide = false, min = 1, max = 1.8, glow = Color3.fromRGB(200, 170, 120) },
	{ name = "Mushroom_Red", weight = 1, collide = false, min = 1, max = 1.8, glow = Color3.fromRGB(220, 120, 100) },
	{ name = "Mushroom_Golden", weight = 1, collide = false, min = 1, max = 1.8, glow = Color3.fromRGB(230, 200, 110) },
}
local function pick(list, rng)
	local total = 0
	for _, item in list do
		total += item.weight
	end
	local roll = rng:NextNumber(0, total)
	for _, item in list do
		roll -= item.weight
		if roll <= 0 then
			return item
		end
	end
	return list[1]
end

local glowLights = 0
local MAX_GLOW_LIGHTS = 260

local function plantProp(parent, rng, x, z)
	local kind = pick(PROPS, rng)
	local prop = assets[kind.name]:Clone()
	local s = rng:NextNumber(kind.min, kind.max)
	local h = ground(x, z)
	local spin = CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
	local parts = {}
	if prop:IsA("Model") then
		prop:ScaleTo(s)
		local cf, size = prop:GetBoundingBox()
		local base = cf.Position.Y - size.Y / 2
		prop:PivotTo(CFrame.new(x, h - 0.4 + (prop:GetPivot().Position.Y - base), z) * spin)
		for _, p in prop:GetDescendants() do
			if p:IsA("BasePart") then
				table.insert(parts, p)
			end
		end
	else
		prop.Size *= s
		prop.CFrame = CFrame.new(x, h - 0.4 + prop.Size.Y / 2, z) * spin
		parts = { prop }
	end
	for _, p in parts do
		p.Anchored = true
		p.CanCollide = kind.collide
	end
	-- About half the mushrooms glow at night; some of those light the ground round them.
	if kind.glow and rng:NextNumber() < 0.5 then
		for i, p in parts do
			local lit = i == 1 and glowLights < MAX_GLOW_LIGHTS and rng:NextNumber() < 0.5
			if lit then
				glowLights += 1
			end
			nightGlow(p, kind.glow, if lit then 9 else nil, 0.6)
		end
	end
	prop.Parent = parent
end

local forest = folderIn(layer, "Forest")
local rng = rngFor(7)
local trees, props = 0, 0
local row = 0
-- Denser in the lowland; each band owns its side of the cliff.
for _, band in { { cell = 26, low = true }, { cell = 34, low = false } } do
	local cell = band.cell
	for gx = -Zones.WORLD_R, Zones.WORLD_R, cell do
		row += 1
		progress(`forest row {row} ({trees} trees, {props} props)`)
		local rowFolder = Instance.new("Folder")
		rowFolder.Name = `Row{row}`
		for gz = -Zones.WORLD_R, Zones.WORLD_R, cell do
			local x = gx + rng:NextNumber(0.15, 0.85) * cell
			local z = gz + rng:NextNumber(0.15, 0.85) * cell
			local pos = Vector3.new(x, 0, z)
			local mine = (pos.Magnitude < Zones.CLIFF_IN) == band.low
			if mine and rng:NextNumber() < 0.85 and clear(pos) then
				pick(TREES, rng).plant(rowFolder, rng, x, z)
				trees += 1
			end
			-- A small cluster of floor decor in most cells.
			local cx, cz = gx + rng:NextNumber() * cell, gz + rng:NextNumber() * cell
			if ((Vector3.new(cx, 0, cz).Magnitude < Zones.CLIFF_IN) == band.low) and rng:NextNumber() < 0.85 then
				for _ = 1, rng:NextInteger(1, 3) do
					local px, pz = cx + rng:NextNumber(-5, 5), cz + rng:NextNumber(-5, 5)
					if clear(Vector3.new(px, 0, pz)) then
						plantProp(rowFolder, rng, px, pz)
						props += 1
					end
				end
			end
		end
		rowFolder.Parent = forest
		task.wait()
	end
end
print(`[BuildZones] {trees} trees, {props} props, {glowLights} mushroom lights`)

-- 5. Lantern trails ---------------------------------------------------------------------------

progress("lanterns")
local lanterns = folderIn(layer, "Lanterns")
local lanternRng = rngFor(13)
local POST = Color3.fromRGB(78, 60, 46)
local function lantern(pos, facing)
	local model = Instance.new("Model")
	model.Name = "Lantern"
	local base = CFrame.lookAt(pos, pos + facing) * CFrame.Angles(0, 0, lanternRng:NextNumber(-0.05, 0.05))
	part(model, Vector3.new(0.5, 5, 0.5), base * CFrame.new(0, 2.5, 0), POST, M.Wood)
	part(model, Vector3.new(0.4, 0.4, 1.6), base * CFrame.new(0, 4.8, -0.6), POST, M.Wood)
	local glass =
		part(model, Vector3.new(0.9, 1.1, 0.9), base * CFrame.new(0, 3.9, -1.3), Color3.fromRGB(214, 168, 104), M.Glass)
	glass.Transparency = 0.2
	glass.CanCollide = false
	nightGlow(glass, Color3.fromRGB(255, 188, 120), 16, 0.9)
	part(model, Vector3.new(1.1, 0.3, 1.1), base * CFrame.new(0, 4.55, -1.3), POST, M.Wood).CanCollide = false
	model.Parent = lanterns
end
local lanternCount = 0
for _, zone in Zones.list do
	local points = TRAILS[zone.id].points
	for i = 2, #points - 1 do
		local p, nextP = points[i], points[i + 1]
		local along = flat(nextP - p)
		if along.Magnitude > 0.1 and lanternRng:NextNumber() < 0.8 then
			local side = Vector3.new(-along.Z, 0, along.X).Unit * (if i % 2 == 0 then 1 else -1)
			local r = flat(p).Magnitude
			local onRamp = r > Zones.RAMP_R0 - 1 and r < Zones.RAMP_R1 + 1
			if onRamp then
				side = flat(p).Unit -- the cliff side of the ramp
			end
			local at = flat(p) + side * (if onRamp then RAMP_HALF - 1.5 else 4)
			lantern(Vector3.new(at.X, ground(at.X, at.Z) - 0.5, at.Z), -side)
			lanternCount += 1
		end
	end
end
print(`[BuildZones] {lanternCount} lanterns`)
task.wait()

-- 6. Zones --------------------------------------------------------------------------------------

progress("zones")
local zonesFolder = folderIn(layer, "Zones")

-- A point in a zone's frame on the ground; `y` is a height as if the ground were at FLOOR.
local function at(zone, d, s, y)
	local p = Zones.toWorld(zone, d, s)
	return Vector3.new(p.X, ground(p.X, p.Z) + (y or FLOOR) - FLOOR, p.Z)
end

-- Scatter `count` points inside the zone circle, away from its enemy packs and the boss.
local function scatter(zone, seed, count, edgeBias, fn)
	local r = rngFor(seed)
	local placed = 0
	local tries = 0
	while placed < count and tries < count * 20 do
		tries += 1
		local a = r:NextNumber(0, TAU)
		local dist = Zones.ZONE_R * (if edgeBias then r:NextNumber(0.72, 0.95) else math.sqrt(r:NextNumber(0.06, 0.8)))
		local d, s = Zones.ZONE_D + math.cos(a) * dist, math.sin(a) * dist
		local clearOf = true
		for _, pack in Zones.PACKS do
			local keep = if pack.role == "boss" then 30 else 12
			if math.abs(pack.d - d) < keep and math.abs(pack.s - s) < keep then
				clearOf = false
			end
		end
		if clearOf then
			placed += 1
			fn(at(zone, d, s), r)
		end
	end
end

local function gate(zone, folder, color, glowColor, material)
	for _, s in { -24, 24 } do
		part(folder, Vector3.new(5, 22, 5), CFrame.new(at(zone, Zones.GATE_D, s, 10)), color, material)
		part(
			folder,
			Vector3.new(6.4, 2, 6.4),
			CFrame.new(at(zone, Zones.GATE_D, s, 21.6)),
			color:Lerp(Color3.new(), 0.25),
			material
		)
	end
	local beamCF = CFrame.lookAt(at(zone, Zones.GATE_D, 0, 23), at(zone, Zones.GATE_D, 30, 23))
	part(folder, Vector3.new(3, 2, 52), beamCF, color:Lerp(Color3.new(), 0.25), material)
	local lamp = part(folder, Vector3.new(2, 2.4, 2), CFrame.new(at(zone, Zones.GATE_D, 0, 19.6)), glowColor, M.Neon)
	local light = Instance.new("PointLight")
	light.Color = glowColor
	light.Range = 30
	light.Parent = lamp
	-- Sign beside the road, facing the camp.
	local signPos = at(zone, Zones.GATE_D - 6, -34, 5)
	local board = part(
		folder,
		Vector3.new(12, 4, 0.6),
		CFrame.lookAt(signPos, Vector3.new(0, 5, 0)),
		Color3.fromRGB(120, 84, 56),
		M.Wood
	)
	part(
		folder,
		Vector3.new(0.6, 6, 0.6),
		CFrame.new(signPos - Vector3.new(0, 3, 0)),
		Color3.fromRGB(96, 66, 46),
		M.Wood
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 30
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = `{string.upper(zone.name)}\n{zone.type} · Lv 1–15`
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(255, 236, 210)
	label.Parent = gui
	gui.Parent = board
end

local function light(parent, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1
	l.Parent = parent
end

local function emitter(parent, color, rate, size, speed, life)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Size = NumberSequence.new(size, 0)
	e.Lifetime = NumberRange.new(life * 0.6, life)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(30, 30)
	e.Rate = rate
	e.Parent = parent
	return e
end

-- Emberfall Ridge: basalt, lava seams, ash trees, ember vents, a caldera rim.
local function emberfall(zone, folder)
	terrain:SetMaterialColor(M.Basalt, Color3.fromRGB(70, 56, 52))
	scatter(zone, 21, 24, false, function(p, r)
		local cf = CFrame.new(p) * CFrame.Angles(0, r:NextNumber(0, 6.28), 0)
		terrain:FillBlock(
			cf * CFrame.new(0, -0.5, 0),
			Vector3.new(r:NextNumber(3, 5), 2, r:NextNumber(14, 30)),
			M.CrackedLava
		)
	end)
	scatter(zone, 22, 16, true, function(p, r)
		local s = r:NextNumber(1, 2)
		local cf = CFrame.new(p) * CFrame.Angles(0, r:NextNumber(0, 6.28), 0)
		part(folder, Vector3.new(6, 4, 5) * s, cf * CFrame.new(0, 1.6 * s, 0), Color3.fromRGB(74, 62, 58), M.Slate)
		part(
			folder,
			Vector3.new(3.5, 3, 3) * s,
			cf * CFrame.new(1.6 * s, 4 * s, 0.4 * s) * CFrame.Angles(0, 0.6, 0.2),
			Color3.fromRGB(52, 44, 42),
			M.Slate
		)
	end)
	scatter(zone, 23, 14, true, function(p, r)
		local h = r:NextNumber(14, 22)
		local base = CFrame.new(p) * CFrame.Angles(r:NextNumber(-0.1, 0.1), r:NextNumber(0, 6.28), 0)
		part(folder, Vector3.new(1.8, h, 1.8), base * CFrame.new(0, h / 2, 0), Color3.fromRGB(46, 38, 36), M.Wood)
		part(
			folder,
			Vector3.new(1, 6, 1),
			base * CFrame.new(1.8, h * 0.7, 0) * CFrame.Angles(0, 0, -0.8),
			Color3.fromRGB(46, 38, 36),
			M.Wood
		)
		part(folder, Vector3.new(7, 3, 7), base * CFrame.new(0, h + 1, 0), Color3.fromRGB(150, 140, 132), M.Slate)
		local ember = part(
			folder,
			Vector3.new(1.4, 1.4, 1.4),
			base * CFrame.new(-1.8, h + 0.4, -1.4),
			Color3.fromRGB(255, 120, 50),
			M.Neon
		)
		ember.CanCollide = false
	end)
	scatter(zone, 24, 10, false, function(p)
		local vent = part(
			folder,
			Vector3.new(3, 1, 3),
			CFrame.new(p + Vector3.new(0, 0.3, 0)),
			Color3.fromRGB(52, 44, 42),
			M.Basalt
		)
		emitter(vent, Color3.fromRGB(255, 140, 60), 6, 0.35, 5, 3)
		light(vent, Color3.fromRGB(255, 120, 50), 14, 1.4)
	end)
	local c = at(zone, Zones.BOSS_D, 0)
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		if math.cos(a) > -0.8 then -- leave the side facing camp open: that's the way in
			local dir = zone.angle + a
			terrain:FillBall(c + Vector3.new(math.cos(dir) * 62, 3, math.sin(dir) * 62), 12, M.Basalt)
		end
	end
	terrain:FillCylinder(CFrame.new(c + Vector3.new(0, -0.4, 0)), 1.4, 9, M.CrackedLava)
	gate(zone, folder, Color3.fromRGB(74, 62, 58), Color3.fromRGB(255, 120, 50), M.Slate)
end

-- Mistfall Basin: sand and mud, still pools with boardwalks, reeds, blue crystals, low mist.
local function mistfall(zone, folder)
	terrain:SetMaterialColor(M.Sand, Color3.fromRGB(196, 186, 156))
	terrain:SetMaterialColor(M.Mud, Color3.fromRGB(92, 98, 86))
	-- Pools in the gaps between the pack rings (`ring` out from the centre at `a` degrees).
	local pools = {}
	for _, pool in
		{
			{ ring = 125, a = 120, r = 15 },
			{ ring = 125, a = 240, r = 15 },
			{ ring = 140, a = 30, r = 16 },
			{ ring = 140, a = 330, r = 16 },
			{ ring = 70, a = 180, r = 12 },
		}
	do
		local a = math.rad(pool.a)
		table.insert(pools, { d = Zones.ZONE_D + math.cos(a) * pool.ring, s = math.sin(a) * pool.ring, r = pool.r })
	end
	for _, pool in pools do
		local p = at(zone, pool.d, pool.s)
		terrain:FillCylinder(CFrame.new(p + Vector3.new(0, -2, 0)), 8, pool.r + 5, M.Mud)
		terrain:FillCylinder(CFrame.new(p + Vector3.new(0, -3.5, 0)), 7, pool.r, M.Air)
		terrain:FillCylinder(CFrame.new(p + Vector3.new(0, -4.5, 0)), 5, pool.r, M.Water)
		-- A boardwalk across it.
		local across = CFrame.lookAt(p + Vector3.new(0, 0.2, 0), at(zone, pool.d + 1, pool.s, FLOOR + 0.2))
		part(folder, Vector3.new(5, 0.6, pool.r * 2 + 8), across, Color3.fromRGB(128, 98, 70), M.WoodPlanks)
		for _, side in { -1, 1 } do
			for k = -1, 1 do
				part(
					folder,
					Vector3.new(0.6, 3, 0.6),
					across * CFrame.new(side * 2.6, -0.8, k * pool.r * 0.8),
					Color3.fromRGB(96, 72, 52),
					M.Wood
				)
			end
		end
		local mist = part(
			folder,
			Vector3.new(pool.r * 1.6, 0.2, pool.r * 1.6),
			CFrame.new(p + Vector3.new(0, 0.5, 0)),
			Color3.new(),
			M.SmoothPlastic
		)
		mist.Transparency = 1
		mist.CanCollide = false
		mist.CanQuery = false
		local e = emitter(mist, Color3.fromRGB(210, 230, 240), 4, 6, 0.6, 6)
		e.LightEmission = 0.1
		e.Transparency = NumberSequence.new(0.75, 1)
		e.Size = NumberSequence.new(5, 9)
	end
	scatter(zone, 31, 30, true, function(p, r)
		for _ = 1, 4 do
			local h = r:NextNumber(3, 6)
			part(
				folder,
				Vector3.new(0.3, h, 0.3),
				CFrame.new(p + Vector3.new(r:NextNumber(-1.5, 1.5), h / 2, r:NextNumber(-1.5, 1.5)))
					* CFrame.Angles(r:NextNumber(-0.15, 0.15), 0, r:NextNumber(-0.15, 0.15)),
				Color3.fromRGB(120, 150, 90),
				M.Grass
			)
		end
	end)
	scatter(zone, 32, 14, true, function(p, r)
		local s = r:NextNumber(1, 1.8)
		local cf = CFrame.new(p) * CFrame.Angles(0, r:NextNumber(0, 6.28), 0)
		part(folder, Vector3.new(6, 3.5, 5) * s, cf * CFrame.new(0, 1.4 * s, 0), Color3.fromRGB(96, 110, 118), M.Slate)
		part(folder, Vector3.new(5, 0.8, 4) * s, cf * CFrame.new(0, 3.3 * s, 0), Color3.fromRGB(96, 130, 84), M.Grass)
	end)
	scatter(zone, 33, 10, false, function(p, r)
		local h = r:NextNumber(3, 6)
		local crystal = part(
			folder,
			Vector3.new(1.4, h, 1.4),
			CFrame.new(p + Vector3.new(0, h / 2 - 0.5, 0))
				* CFrame.Angles(r:NextNumber(-0.3, 0.3), r:NextNumber(0, 6.28), r:NextNumber(-0.3, 0.3)),
			Color3.fromRGB(110, 200, 240),
			M.Neon
		)
		crystal.Transparency = 0.2
		light(crystal, Color3.fromRGB(120, 210, 255), 14, 1)
	end)
	gate(zone, folder, Color3.fromRGB(96, 110, 118), Color3.fromRGB(120, 210, 255), M.Slate)
end

-- Elderwood: moss and leaves under giant trees whose canopies sit high above the camera.
local function elderwood(zone, folder)
	terrain:SetMaterialColor(M.LeafyGrass, Color3.fromRGB(86, 120, 62))
	scatter(zone, 41, 12, true, function(p, r)
		local h = r:NextNumber(55, 75)
		local w = r:NextNumber(6, 9)
		local bark = Color3.fromRGB(92, 70, 52)
		part(
			folder,
			Vector3.new(h, w, w),
			CFrame.new(p + Vector3.new(0, h / 2 - 1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			bark,
			M.Wood,
			Enum.PartType.Cylinder
		)
		for k = 0, 3 do
			local a = k / 4 * math.pi * 2 + r:NextNumber(0, 1)
			part(
				folder,
				Vector3.new(w * 1.2, 2.2, 2.4),
				CFrame.new(p + Vector3.new(math.cos(a) * w * 0.7, 0.4, math.sin(a) * w * 0.7))
					* CFrame.Angles(0, -a, 0.35),
				bark,
				M.Wood
			)
		end
		for k = 0, 2 do
			local a = k / 3 * math.pi * 2 + r:NextNumber(0, 1)
			part(
				folder,
				Vector3.new(24, 12, 24) * r:NextNumber(0.8, 1.2),
				CFrame.new(p + Vector3.new(math.cos(a) * 9, h + r:NextNumber(-4, 4), math.sin(a) * 9)),
				Color3.fromRGB(78, 124, 62):Lerp(Color3.fromRGB(110, 150, 70), r:NextNumber()),
				M.Grass,
				Enum.PartType.Ball
			)
		end
	end)
	scatter(zone, 42, 16, false, function(p, r)
		local s = r:NextNumber(0.8, 1.6)
		part(
			folder,
			Vector3.new(0.8, 2, 0.8) * s,
			CFrame.new(p + Vector3.new(0, s, 0)),
			Color3.fromRGB(226, 214, 190),
			M.SmoothPlastic
		)
		local cap = part(
			folder,
			Vector3.new(3, 1.2, 3) * s,
			CFrame.new(p + Vector3.new(0, 2.2 * s, 0)),
			Color3.fromRGB(150, 230, 120),
			M.Neon,
			Enum.PartType.Ball
		)
		cap.Transparency = 0.15
		light(cap, Color3.fromRGB(160, 240, 120), 10, 0.8)
	end)
	scatter(zone, 43, 8, true, function(p, r)
		local length = r:NextNumber(14, 22)
		part(
			folder,
			Vector3.new(length, 3, 3),
			CFrame.new(p + Vector3.new(0, 1, 0)) * CFrame.Angles(0, r:NextNumber(0, 6.28), 0),
			Color3.fromRGB(84, 64, 48),
			M.Wood,
			Enum.PartType.Cylinder
		)
	end)
	scatter(zone, 44, 8, false, function(p)
		local holder =
			part(folder, Vector3.new(16, 1, 16), CFrame.new(p + Vector3.new(0, 4, 0)), Color3.new(), M.SmoothPlastic)
		holder.Transparency = 1
		holder.CanCollide = false
		holder.CanQuery = false
		local e = emitter(holder, Color3.fromRGB(220, 255, 140), 3, 0.25, 1, 6)
		e.SpreadAngle = Vector2.new(180, 180)
	end)
	gate(zone, folder, Color3.fromRGB(92, 70, 52), Color3.fromRGB(170, 240, 110), M.Wood)
end

local BUILD = { emberfall = emberfall, mistfall = mistfall, elderwood = elderwood }
for _, zone in Zones.list do
	local folder = Instance.new("Folder")
	folder.Name = zone.name
	folder.Parent = zonesFolder
	BUILD[zone.id](zone, folder)
	task.wait()
end

-- The camp ring opens toward each zone (walls removed near the gates).
for _, wall in map.Boundary:GetChildren() do
	if wall:IsA("BasePart") then
		local a = math.atan2(wall.Position.Z, wall.Position.X)
		for _, zone in Zones.list do
			if angleGap(a, zone.angle) < Zones.GATE_HALF_ANGLE then
				wall:Destroy()
				break
			end
		end
	end
end

progress("done")
print("[BuildZones] done")
