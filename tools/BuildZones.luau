--!nocheck
-- Unified World Builder for Glowkeepers v2 (docs/LAYER_ONE.md).
-- Run once in Studio Edit, then save the place.
-- It builds the entire world (r = 0..Zones.WORLD_R) from Shared.Zones, replacing both the old
-- v1 BuildGreybox camp (8 plots) and the old outer rings:
--   1. Clears all old world folders (Plots, Stations, Boundary, Forest, Dressing, Zones, WorldEdge, Layer).
--   2. Writes the terrain heightmap with WriteVoxels in chunks from r = 0 to EXTENT:
--      - r 0..80:    Wizard Camp Courtyard at FLOOR_Y with stone/ground paths to stations & gates
--      - r 80..210:  Lowland Wild Forest (random Neutral Wisps, Ashlings, Raider Camps)
--      - r 210..230: Valley threshold & smooth trail ramps climbing into the 3 Elemental Valleys
--      - r 230..580: Stepped Elemental Valleys (Emberfall, Mistfall, Elderwood) framed by rocky ridges
--      - r 650:      Sheer outer mountain rim + invisible wall
--   3. Builds the Wizard Camp Courtyard (Map.Campfire, Map.Boundary courtyard wall with 3 gates,
--      Map.Sanctuary shared Scriptorium pavilion with Desk & Shelf, Bank Vault, Ink Merchant, lanterns).
--   4. Plants the mixed forest (oaks, pines, birches, dead snags, floor decor, NightGlow mushrooms)
--      clear of the courtyard, trails, ramps, raider camp sites, and elemental valleys.
--   5. Places NightGlow lantern trails from each courtyard gate into its elemental valley.
--   6. Builds the 3 elemental gate arches, signs, and biome landmarks inside each valley.
-- Runs async: watch workspace's "BuildProgress" attribute (ends with "done").

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Zones = require(ReplicatedStorage.Shared.Zones)

local terrain = workspace.Terrain
local map = workspace:FindFirstChild("Map")
if map == nil then
	map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace
end
local worldAssets = ReplicatedStorage:FindFirstChild("WorldAssets")
local assets = worldAssets and worldAssets:FindFirstChild("Forest")
local FLOOR = Zones.FLOOR_Y
local M = Enum.Material
local TAU = math.pi * 2

do
	local lighting: any = Lighting
	pcall(function()
		lighting.Technology = Enum.Technology.Future
	end)
	lighting.GlobalShadows = true
	lighting.ShadowSoftness = 0.25
	lighting.EnvironmentDiffuseScale = 1
	lighting.EnvironmentSpecularScale = 1
end

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

local ZONE_MATERIAL = { emberfall = M.LeafyGrass, mistfall = M.Grass, elderwood = M.Slate }
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

local function cliffShift(a)
	local calm = 1
	for _, zone in Zones.list do
		calm = math.min(calm, smooth((angleGap(a, zone.angle) - Zones.RAMP_SPAN / 2 - math.rad(4)) / math.rad(5)))
	end
	local n = math.noise(math.cos(a) * 7, math.sin(a) * 7, 2.3)
		+ 0.5 * math.noise(math.cos(a) * 19, math.sin(a) * 19, 5.1)
	return n * 6 * calm
end

local function trailDistance(x, z)
	local a = math.atan2(z, x)
	local p = Vector3.new(x, 0, z)
	local best = math.huge
	for _, zone in Zones.list do
		if angleGap(a, zone.angle) < math.rad(40) then
			for _, seg in TRAILS[zone.id].segs do
				best = math.min(best, segmentDistance(p, seg[1], seg[2]))
			end
		end
	end
	return best
end

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

-- Ground height and material at (x, z) across the whole world (r = 0..EXTENT).
local function ground(x, z)
	local r = math.sqrt(x * x + z * z)
	if r < Zones.CAMP_R + 4 then
		-- Inside the Wizard Camp Courtyard: flat floor with stone/ground paths to stations & gates.
		local a = math.atan2(z, x)
		local onGateRoad = false
		for _, zone in Zones.list do
			if angleGap(a, zone.angle) < math.rad(8) and r > 10 then
				onGateRoad = true
				break
			end
		end
		local nearCenter = r < 14 or (r > 22 and r < 34 and z < 0)
		local mat = if nearCenter or onGateRoad then M.Ground else M.Grass
		return FLOOR, mat
	end
	local a = math.atan2(z, x)
	local shift = cliffShift(a)
	local cliffIn = Zones.CLIFF_IN + shift
	local cliffOut = Zones.CLIFF_OUT + shift
	local hills = math.noise(x / 80, z / 80, 1.7) + 0.4 * math.noise(x / 28, z / 28, 3.9)
	local low = FLOOR + hills * 2.0 * smooth((r - Zones.GATE_D) / 25) * smooth((cliffIn - r) / 25)
	local inZone = nil
	local zoneEdge = math.huge
	for _, zone in Zones.list do
		local c = CENTRES[zone.id]
		local d = Vector2.new(x - c.X, z - c.Z).Magnitude
		local edge = d - (Zones.ZONE_R + math.noise(x / 36, z / 36, 7.7) * 7)
		if edge < zoneEdge then
			zoneEdge = edge
			inZone = zone
		end
	end
	local high = Zones.PLATEAU_Y + hills * 3.0 * smooth((r - cliffOut) / 30) * (0.25 + 0.75 * smooth(zoneEdge / 25))
	local t = math.clamp((r - cliffIn) / (cliffOut - cliffIn), 0, 1)
	local h = low + (high - low) * t
	local ramp, rampY = 0, 0
	if r > Zones.CLIFF_IN - 32 and r < Zones.CLIFF_OUT + 32 then
		ramp, rampY = rampAt(x, z)
		h += (rampY - h) * ramp
	end
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
		local trail = trailDistance(x, z) < 3.5 and math.noise(x / 9, z / 9, 4.4) > -0.25
		local patch = math.noise(x / 50, z / 50, 6.2) > 0.42
		if ramp > 0.6 or trail or patch then
			material = M.Ground
		end
	end
	return h, material
end

-- 1. Clear all old world folders ----------------------------------------------------------------

progress("clearing")
for _, child in map:GetChildren() do
	child:Destroy()
end
local oldEmber = workspace:FindFirstChild("Emberfall")
if oldEmber then
	oldEmber:Destroy()
end
terrain:Clear()
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

-- 2. Terrain (r = 0..EXTENT) --------------------------------------------------------------------

terrain:SetMaterialColor(M.Grass, Color3.fromRGB(92, 122, 62))
terrain:SetMaterialColor(M.Rock, Color3.fromRGB(104, 98, 90))
terrain:SetMaterialColor(M.Ground, Color3.fromRGB(106, 90, 70))
local RES = 4
local CHUNK = 128
local EXTENT = Zones.WORLD_R + 48
local GRID = 768
local BOTTOM = -20
local chunks = {}
for cx = -GRID, GRID - CHUNK, CHUNK do
	for cz = -GRID, GRID - CHUNK, CHUNK do
		local nx = math.clamp(0, cx, cx + CHUNK)
		local nz = math.clamp(0, cz, cz + CHUNK)
		if math.sqrt(nx * nx + nz * nz) < EXTENT then
			table.insert(chunks, { cx, cz })
		end
	end
end
for i, c in chunks do
	progress(`terrain {i}/{#chunks}`)
	local cx, cz = c[1], c[2]
	local n = CHUNK / RES
	local heights, mats = {}, {}
	local top = 20
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
		for iz = 1, n do
			local h, m = heights[ix][iz], mats[ix][iz]
			for iy = 1, ny do
				local occ = math.clamp((h - (BOTTOM + (iy - 1) * RES)) / RES, 0, 1)
				voxMats[ix][iy][iz] = if occ > 0 then m else M.Air
				voxOcc[ix][iy][iz] = occ
			end
		end
	end
	terrain:WriteVoxels(region, RES, voxMats, voxOcc)
	task.wait()
end

-- 3. Wizard Camp Courtyard & Outer Edge ---------------------------------------------------------

progress("courtyard")
local campfire = Instance.new("Model")
campfire.Name = "Campfire"
campfire.Parent = map
for k = 0, 11 do
	local a = k / 12 * TAU
	part(
		campfire,
		Vector3.new(2.2, 1.4, 1.8),
		CFrame.new(math.cos(a) * 4.5, FLOOR + 0.5, math.sin(a) * 4.5) * CFrame.Angles(0, -a, 0),
		Color3.fromRGB(118, 114, 112),
		M.Slate
	)
end
for k = 0, 3 do
	local a = k * math.pi / 2
	part(
		campfire,
		Vector3.new(0.9, 4.2, 0.9),
		CFrame.new(0, FLOOR, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 1.6, -1) * CFrame.Angles(-0.45, 0, 0),
		Color3.fromRGB(105, 72, 50),
		M.Wood
	)
end
local hearth = part(
	campfire,
	Vector3.new(2.2, 1.2, 2.2),
	CFrame.new(0, FLOOR + 1.2, 0),
	Color3.fromRGB(255, 160, 70),
	M.Neon,
	Enum.PartType.Ball
)
hearth.CanCollide = false
local fireLight = Instance.new("PointLight")
fireLight.Color = Color3.fromRGB(255, 175, 95)
fireLight.Range = 42
fireLight.Brightness = 1.8
fireLight.Shadows = true
fireLight.Parent = hearth
local fireEmitter = Instance.new("Fire")
fireEmitter.Size = 7
fireEmitter.Heat = 9
fireEmitter.Parent = hearth

-- Shared courtyard stations (Sanctuary preview in Edit mode; CampService wires live prompts on play).
local sanctuary = Instance.new("Model")
sanctuary.Name = "Sanctuary"
sanctuary.Parent = map
local WOOD = Color3.fromRGB(120, 84, 56)
local WOOD_DARK = Color3.fromRGB(86, 60, 42)
local STONE = Color3.fromRGB(118, 114, 112)
local CLOTH_EMBER = Color3.fromRGB(168, 102, 70)
do
	local deskBase = CFrame.lookAt(Zones.DESK_POS, Vector3.new(0, FLOOR, 0))
	part(sanctuary, Vector3.new(8, 0.8, 4.4), deskBase * CFrame.new(0, 3.2, 0), WOOD, M.Wood).Name = "Desk"
	for _, x in { -3.4, 3.4 } do
		for _, z in { -1.6, 1.6 } do
			part(sanctuary, Vector3.new(0.8, 2.8, 0.8), deskBase * CFrame.new(x, 1.4, z), WOOD_DARK, M.Wood)
		end
	end
	local shelfBase = CFrame.lookAt(Zones.SHELF_POS, Vector3.new(0, FLOOR, 0))
	part(sanctuary, Vector3.new(7, 7.5, 0.7), shelfBase * CFrame.new(0, 3.75, -1.2), WOOD_DARK, M.Wood).Name = "Shelf"
	for i = 0, 2 do
		part(sanctuary, Vector3.new(7, 0.4, 2.2), shelfBase * CFrame.new(0, 1 + i * 2.3, -0.2), WOOD, M.Wood)
	end
	local bankBase = CFrame.lookAt(Zones.BANK_POS, Vector3.new(0, FLOOR, 0))
	part(sanctuary, Vector3.new(7, 0.6, 5), bankBase * CFrame.new(0, 0.3, 0), STONE, M.Slate)
	part(sanctuary, Vector3.new(5, 2.6, 3.2), bankBase * CFrame.new(0, 1.9, 0), WOOD, M.Wood).Name = "Bank"
	part(sanctuary, Vector3.new(5.2, 0.9, 3.4), bankBase * CFrame.new(0, 3.65, 0), WOOD_DARK, M.Wood)
	local shopBase = CFrame.lookAt(Zones.SHOP_POS, Vector3.new(0, FLOOR, 0))
	part(sanctuary, Vector3.new(9, 3.2, 2.4), shopBase * CFrame.new(0, 1.6, 1.8), WOOD, M.Wood).Name = "InkMerchant"
	part(sanctuary, Vector3.new(9.4, 0.35, 2.8), shopBase * CFrame.new(0, 3.35, 1.8), WOOD_DARK, M.Wood)
	for _, x in { -4.2, 4.2 } do
		for _, z in { -2.2, 2.2 } do
			part(sanctuary, Vector3.new(0.6, 8.5, 0.6), shopBase * CFrame.new(x, 4.25, z), WOOD_DARK, M.Wood)
		end
	end
	part(
		sanctuary,
		Vector3.new(10, 1.2, 6),
		shopBase * CFrame.new(0, 8.8, 0) * CFrame.Angles(0.12, 0, 0),
		CLOTH_EMBER,
		M.Fabric
	)
end

-- Low stone courtyard perimeter ring at r = Zones.GATE_D, open at the 3 gates.
local boundary = folderIn(map, "Boundary")
local RING_SEGMENTS = 48
for i = 1, RING_SEGMENTS do
	local a = (i - 0.5) / RING_SEGMENTS * TAU
	local inGate = false
	for _, zone in Zones.list do
		if angleGap(a, zone.angle) < Zones.GATE_HALF_ANGLE then
			inGate = true
			break
		end
	end
	if not inGate then
		local pos = Vector3.new(math.cos(a) * Zones.GATE_D, FLOOR + 2, math.sin(a) * Zones.GATE_D)
		local segLen = TAU * Zones.GATE_D / RING_SEGMENTS + 0.6
		part(
			boundary,
			Vector3.new(2.4, 4.2, segLen),
			CFrame.lookAt(pos, Vector3.new(0, FLOOR + 2, 0)) * CFrame.Angles(0, math.pi / 2, 0),
			Color3.fromRGB(118, 114, 112),
			M.Slate
		)
	end
end

-- Outer world boundary wall.
local edge = folderIn(layer, "Edge")
local SEGMENTS = 72
for i = 1, SEGMENTS do
	local a = i / SEGMENTS * TAU
	local y = Zones.PLATEAU_Y + 80
	local pos = Vector3.new(math.cos(a) * Zones.WORLD_R, y, math.sin(a) * Zones.WORLD_R)
	local wall = part(
		edge,
		Vector3.new(TAU * Zones.WORLD_R / SEGMENTS + 2, 220, 2),
		CFrame.lookAt(pos, Vector3.new(0, y, 0)),
		Color3.new(),
		M.SmoothPlastic
	)
	wall.Transparency = 1
	wall.CanQuery = false
end
game:GetService("StarterPlayer").CharacterMaxSlopeAngle = 50
task.wait()

-- 4. Forest -------------------------------------------------------------------------------------

local function clear(pos)
	local r = pos.Magnitude
	if r < Zones.GATE_D + 10 or r > Zones.WORLD_R - 14 then
		return false
	end
	local shift = cliffShift(math.atan2(pos.Z, pos.X))
	if r > Zones.CLIFF_IN + shift - 8 and r < Zones.CLIFF_OUT + shift + 8 then
		return false
	end
	if r > Zones.CLIFF_IN - 24 and r < Zones.CLIFF_OUT + 24 and rampAt(pos.X, pos.Z) > 0.05 then
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
	local i = rng:NextInteger(1, #LEAVES + 2)
	return LEAVES[if i > #LEAVES then i - #LEAVES else i]
end

local function canopyPart(model, size, cf, color)
	local p = part(model, size, cf, color, M.Grass)
	p.Name = "Leaves"
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

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

local function assetTree(name, min, max)
	return function(parent, rng, x, z)
		if assets == nil or assets:FindFirstChild(name) == nil then
			birch(parent, rng, x, z)
			return
		end
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
local MAX_GLOW_LIGHTS = 220

local function plantProp(parent, rng, x, z)
	local kind = pick(PROPS, rng)
	if assets == nil or assets:FindFirstChild(kind.name) == nil then
		return
	end
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
	if kind.glow and rng:NextNumber() < 0.55 then
		for i, p in parts do
			local lit = i == 1 and glowLights < MAX_GLOW_LIGHTS and rng:NextNumber() < 0.55
			if lit then
				glowLights += 1
			end
			nightGlow(p, kind.glow, if lit then 10 else nil, 0.65)
		end
	end
	prop.Parent = parent
end

local forest = folderIn(layer, "Forest")
local rng = rngFor(7)
local trees, props = 0, 0
local row = 0
for _, band in { { cell = 24, low = true }, { cell = 32, low = false } } do
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

-- 5. Lantern trails & Courtyard lanterns --------------------------------------------------------

progress("lanterns")
local lanterns = folderIn(layer, "Lanterns")
local lanternRng = rngFor(13)
local POST = Color3.fromRGB(78, 60, 46)
local function lantern(pos, facing)
	local model = Instance.new("Model")
	model.Name = "Lantern"
	local base = CFrame.lookAt(pos, pos + facing) * CFrame.Angles(0, 0, lanternRng:NextNumber(-0.04, 0.04))
	part(model, Vector3.new(0.5, 5, 0.5), base * CFrame.new(0, 2.5, 0), POST, M.Wood)
	part(model, Vector3.new(0.4, 0.4, 1.6), base * CFrame.new(0, 4.8, -0.6), POST, M.Wood)
	local glass =
		part(model, Vector3.new(0.9, 1.1, 0.9), base * CFrame.new(0, 3.9, -1.3), Color3.fromRGB(214, 168, 104), M.Glass)
	glass.Transparency = 0.2
	glass.CanCollide = false
	nightGlow(glass, Color3.fromRGB(255, 188, 120), 18, 0.95)
	part(model, Vector3.new(1.1, 0.3, 1.1), base * CFrame.new(0, 4.55, -1.3), POST, M.Wood).CanCollide = false
	model.Parent = lanterns
end

local lanternCount = 0
for k = 0, 5 do
	local a = (k + 0.5) / 6 * TAU
	local p = Vector3.new(math.cos(a) * 44, FLOOR, math.sin(a) * 44)
	lantern(p, -p.Unit)
	lanternCount += 1
end
for _, zone in Zones.list do
	local points = TRAILS[zone.id].points
	for i = 2, #points - 1 do
		local p, nextP = points[i], points[i + 1]
		local along = flat(nextP - p)
		if along.Magnitude > 0.1 and lanternRng:NextNumber() < 0.85 then
			local side = Vector3.new(-along.Z, 0, along.X).Unit * (if i % 2 == 0 then 1 else -1)
			local r = flat(p).Magnitude
			local onRamp = r > Zones.RAMP_R0 - 1 and r < Zones.RAMP_R1 + 1
			if onRamp then
				side = flat(p).Unit
			end
			local at = flat(p) + side * (if onRamp then RAMP_HALF - 1.5 else 4)
			lantern(Vector3.new(at.X, ground(at.X, at.Z) - 0.5, at.Z), -side)
			lanternCount += 1
		end
	end
end
print(`[BuildZones] {lanternCount} lanterns`)
task.wait()

-- 6. Elemental Valleys & Gates ------------------------------------------------------------------

progress("zones")
local zonesFolder = folderIn(layer, "Zones")

local function at(zone, d, s, y)
	local p = Zones.toWorld(zone, d, s)
	return Vector3.new(p.X, ground(p.X, p.Z) + (y or FLOOR) - FLOOR, p.Z)
end

local function scatter(zone, seed, count, edgeBias, fn)
	local r = rngFor(seed)
	local placed = 0
	local tries = 0
	while placed < count and tries < count * 20 do
		tries += 1
		local a = r:NextNumber(0, TAU)
		local dist = Zones.ZONE_R * (if edgeBias then r:NextNumber(0.7, 0.95) else math.sqrt(r:NextNumber(0.06, 0.8)))
		local d, s = Zones.ZONE_D + math.cos(a) * dist, math.sin(a) * dist
		local clearOf = true
		for _, pack in Zones.PACKS do
			local keep = if pack.role == "boss" then 28 else 12
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
	for _, s in { -18, 18 } do
		part(folder, Vector3.new(4.5, 20, 4.5), CFrame.new(at(zone, Zones.GATE_D, s, 9)), color, material)
		part(
			folder,
			Vector3.new(5.8, 2, 5.8),
			CFrame.new(at(zone, Zones.GATE_D, s, 19.6)),
			color:Lerp(Color3.new(), 0.25),
			material
		)
	end
	local beamCF = CFrame.lookAt(at(zone, Zones.GATE_D, 0, 21), at(zone, Zones.GATE_D, 24, 21))
	part(folder, Vector3.new(2.8, 2, 40), beamCF, color:Lerp(Color3.new(), 0.25), material)
	local lamp = part(folder, Vector3.new(2, 2.4, 2), CFrame.new(at(zone, Zones.GATE_D, 0, 17.8)), glowColor, M.Neon)
	local light = Instance.new("PointLight")
	light.Color = glowColor
	light.Range = 28
	light.Parent = lamp
	local signPos = at(zone, Zones.GATE_D - 5, -26, 5)
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
	label.Text = `{string.upper(zone.name)}\n{zone.levelRange}`
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

-- Area 1 (Whispering Woods, Lv 1–15): giant spirit-lit oaks, mossy stones, glowing mushrooms.
local function emberfall(zone, folder)
	terrain:SetMaterialColor(M.LeafyGrass, Color3.fromRGB(78, 114, 58))
	scatter(zone, 21, 14, true, function(p, r)
		local h = r:NextNumber(45, 65)
		local w = r:NextNumber(5, 8)
		local bark = Color3.fromRGB(92, 70, 52)
		part(
			folder,
			Vector3.new(h, w, w),
			CFrame.new(p + Vector3.new(0, h / 2 - 1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			bark,
			M.Wood,
			Enum.PartType.Cylinder
		)
		for k = 0, 2 do
			local a = k / 3 * math.pi * 2 + r:NextNumber(0, 1)
			part(
				folder,
				Vector3.new(22, 11, 22) * r:NextNumber(0.8, 1.2),
				CFrame.new(p + Vector3.new(math.cos(a) * 8, h + r:NextNumber(-3, 3), math.sin(a) * 8)),
				Color3.fromRGB(78, 124, 62):Lerp(Color3.fromRGB(110, 150, 70), r:NextNumber()),
				M.Grass,
				Enum.PartType.Ball
			)
		end
	end)
	scatter(zone, 22, 16, false, function(p, r)
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
	gate(zone, folder, Color3.fromRGB(92, 70, 52), Color3.fromRGB(170, 240, 110), M.Wood)
end

-- Area 2 (Raider Wilds, Lv 15–30): mossy boulders, wooden watchtowers, and frontier campfires.
local function mistfall(zone, folder)
	scatter(zone, 31, 16, true, function(p, r)
		local s = r:NextNumber(1, 1.8)
		local cf = CFrame.new(p) * CFrame.Angles(0, r:NextNumber(0, 6.28), 0)
		part(folder, Vector3.new(6, 3.5, 5) * s, cf * CFrame.new(0, 1.4 * s, 0), Color3.fromRGB(96, 110, 118), M.Slate)
		part(folder, Vector3.new(5, 0.8, 4) * s, cf * CFrame.new(0, 3.3 * s, 0), Color3.fromRGB(96, 130, 84), M.Grass)
	end)
	scatter(zone, 32, 10, true, function(p, r)
		local cf = CFrame.new(p) * CFrame.Angles(0, r:NextNumber(0, 6.28), 0)
		part(folder, Vector3.new(12, 2.4, 2.4), cf * CFrame.new(0, 1, 0), Color3.fromRGB(96, 72, 52), M.Wood)
	end)
	scatter(zone, 33, 8, false, function(p)
		local brazier = part(
			folder,
			Vector3.new(2.4, 2, 2.4),
			CFrame.new(p + Vector3.new(0, 1, 0)),
			Color3.fromRGB(80, 74, 72),
			M.Slate
		)
		local ember = part(
			folder,
			Vector3.new(1.4, 0.6, 1.4),
			CFrame.new(p + Vector3.new(0, 2.2, 0)),
			Color3.fromRGB(255, 160, 70),
			M.Neon
		)
		ember.CanCollide = false
		light(brazier, Color3.fromRGB(255, 160, 80), 18, 1.1)
	end)
	gate(zone, folder, Color3.fromRGB(105, 72, 50), Color3.fromRGB(240, 180, 90), M.Wood)
end

-- Area 3 (Highland Dungeon Ruins, Lv 30–50): ancient stone obelisks, shattered arches, and mana crystals.
local function elderwood(zone, folder)
	terrain:SetMaterialColor(M.Slate, Color3.fromRGB(84, 86, 94))
	scatter(zone, 41, 18, true, function(p, r)
		local h = r:NextNumber(12, 22)
		local cf = CFrame.new(p) * CFrame.Angles(r:NextNumber(-0.08, 0.08), r:NextNumber(0, 6.28), 0)
		part(folder, Vector3.new(4, h, 4), cf * CFrame.new(0, h / 2, 0), Color3.fromRGB(96, 98, 108), M.Slate)
		part(folder, Vector3.new(5, 1.4, 5), cf * CFrame.new(0, h + 0.5, 0), Color3.fromRGB(120, 122, 132), M.Slate)
	end)
	scatter(zone, 42, 12, false, function(p, r)
		local h = r:NextNumber(4, 7)
		local crystal = part(
			folder,
			Vector3.new(1.6, h, 1.6),
			CFrame.new(p + Vector3.new(0, h / 2 - 0.5, 0))
				* CFrame.Angles(r:NextNumber(-0.25, 0.25), r:NextNumber(0, 6.28), r:NextNumber(-0.25, 0.25)),
			Color3.fromRGB(150, 110, 235),
			M.Neon
		)
		crystal.Transparency = 0.2
		light(crystal, Color3.fromRGB(160, 120, 255), 16, 1.1)
	end)
	local c = at(zone, Zones.BOSS_D, 0)
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		if math.cos(a) > -0.6 then
			local dir = zone.angle + a
			local p = c + Vector3.new(math.cos(dir) * 42, 8, math.sin(dir) * 42)
			part(folder, Vector3.new(4, 18, 4), CFrame.new(p), Color3.fromRGB(92, 94, 104), M.Slate)
		end
	end
	gate(zone, folder, Color3.fromRGB(96, 98, 108), Color3.fromRGB(170, 130, 255), M.Slate)
end

local BUILD = { emberfall = emberfall, mistfall = mistfall, elderwood = elderwood }
for _, zone in Zones.list do
	local folder = Instance.new("Folder")
	folder.Name = zone.name
	folder.Parent = zonesFolder
	BUILD[zone.id](zone, folder)
	task.wait()
end

progress("done")
print("[BuildZones] done")
