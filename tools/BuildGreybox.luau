-- Builds the Phase 1 greybox of the Clearing (CONTENT_AND_LIVEOPS §A2) into Workspace.Map.
--
-- Run it in Studio in Edit mode: paste the whole file into the command bar, or run it through
-- Studio MCP. Every number is in LAYOUT; change one and rerun to try another layout. The same
-- seed always gives the same forest.
--
-- It only rebuilds a Map it made itself (attribute GeneratedBy). Once someone edits the map by
-- hand, set the Map's HandEdited attribute to true and the script refuses to overwrite it.
-- On its first run it moves the template's Baseplate and SpawnLocation into
-- ServerStorage.ReplacedByGreybox; nothing is deleted.
--
-- Code finds the map by tag and attribute, never by position (TECH_SPEC §6a):
--   Plot        Model, PlotId 1–8. Children: Floor, Zone, Gate, DecorZone, Slots (pads with Slot 1–30), Sign
--   Campfire    Model, LightRadius, FeedRadius
--   WoodPile    Model, PileId "W01"…
--   WildSpawn   Part, Area "Forest" | "Deepwood"
--   ShardSpawn  Part
--   Station     Model, Kind "LanternShop" | "WispStash" | "Leaderboards" | "WhatsNew"
-- The Map folder carries the ring radii as attributes.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")

-- Lighting the mood pass needs (Bible §1, OD-1); CycleFXController moves the rest through the
-- day. Lighting.Technology must be Future: plugin and MCP scripts may not set it, so set it by
-- hand in the Properties panel if this warns.
do
	local lighting: any = Lighting
	if not pcall(function()
		lighting.Technology = Enum.Technology.Future
	end) then
		warn("[BuildGreybox] Set Lighting.Technology = Future by hand (Properties panel).")
	end
	lighting.GlobalShadows = true
	lighting.ShadowSoftness = 0.25
	lighting.EnvironmentDiffuseScale = 1
	lighting.EnvironmentSpecularScale = 1
end

local GENERATOR = "tools/BuildGreybox.luau"

local LAYOUT = {
	seed = 20261118,
	fireLightRadius = 30, -- safe from the Stalker; marked by a stone circle
	fireFeedRadius = 10,
	fireLightHeight = 7,
	plotCount = 8, -- plots sit in the gaps' middles; gaps alternate trail, station
	plotRingRadius = 75, -- plot centres: gates at 55, backs at 95
	plotWidth = 36,
	plotDepth = 40,
	decorSize = 24,
	stationRadius = 42,
	clearingRadius = 100,
	forestOuter = 160, -- forest ring: wood piles and 60% of wild spawns
	mapRadius = 260, -- deepwood: shards and 40% of wild spawns; an invisible wall stands here
	woodPileRadii = { 118, 140 },
	woodPiles = 16,
	forestSpawns = 24,
	deepwoodSpawns = 16,
	shardSpawns = 12,
	trails = 4,
	pathWidth = 8,
	trailWidth = 6,
	runSpeed = 22,
	carryMult = 0.85,
}

local STATIONS = {
	{ kind = "LanternShop", label = "Lantern Shop" },
	{ kind = "WispStash", label = "Wisp's Stash" },
	{ kind = "Leaderboards", label = "Leaderboards" },
	{ kind = "WhatsNew", label = "What's New" },
}

local STATION_HEIGHT = { LanternShop = 12, WispStash = 14, WhatsNew = 10, Leaderboards = 17 }

local COLORS = {
	outer = Color3.fromRGB(34, 40, 32),
	deepwood = Color3.fromRGB(48, 58, 40),
	forest = Color3.fromRGB(62, 78, 48),
	clearing = Color3.fromRGB(92, 118, 64),
	path = Color3.fromRGB(140, 120, 90),
	stone = Color3.fromRGB(110, 108, 104),
	plot = Color3.fromRGB(150, 112, 78), -- plank decks
	pad = Color3.fromRGB(196, 188, 170), -- pale stone pads
	decor = Color3.fromRGB(120, 170, 90), -- a mossy patch
	wood = Color3.fromRGB(105, 75, 50),
	trunk = Color3.fromRGB(80, 60, 45),
	leaves = Color3.fromRGB(45, 80, 45),
	deepLeaves = Color3.fromRGB(30, 55, 38),
	fire = Color3.fromRGB(255, 150, 60),
	gold = Color3.fromRGB(230, 190, 80),
	sign = Color3.fromRGB(245, 235, 210),
}

local TERRAIN_COLORS = {
	[Enum.Material.Grass] = Color3.fromRGB(98, 128, 62),
	[Enum.Material.LeafyGrass] = Color3.fromRGB(66, 88, 48),
	[Enum.Material.Ground] = Color3.fromRGB(64, 56, 42),
	[Enum.Material.Mud] = Color3.fromRGB(40, 36, 30),
	[Enum.Material.Sand] = Color3.fromRGB(150, 124, 88),
}

-- Glow colours for the forest's own lights (Bible §1: cyan and gold pools at night).
local GLOW = {
	Color3.fromRGB(80, 230, 220),
	Color3.fromRGB(120, 200, 255),
	Color3.fromRGB(180, 140, 255),
}

local TAU = 2 * math.pi
local TERRAIN_OCCUPANCY = 0.4 -- of the top voxel layer (-4..0): the surface sits at about y = -0.4
local MAX_GLOW_LIGHTS = 40 -- PointLights in the whole forest (mushrooms); keep phones fast
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- stands a cylinder's X axis up
local ORIGIN = Vector3.zero
local rng = Random.new(LAYOUT.seed)

-- Helpers -------------------------------------------------------------------------------------

local function polar(r: number, angle: number, y: number?): Vector3
	return Vector3.new(r * math.cos(angle), y or 0, r * math.sin(angle))
end

local function angleGap(a: number, b: number): number
	local d = (a - b) % TAU
	return math.min(d, TAU - d)
end

-- True when the point at radius r and angle a is within halfWidth of a radial line at one of angles.
local function onRadial(a: number, r: number, angles: { number }, halfWidth: number): boolean
	for _, phi in angles do
		local gap = angleGap(a, phi)
		if gap < math.pi / 2 and r * math.sin(gap) < halfWidth then
			return true
		end
	end
	return false
end

local function part(parent, name, shape, size, cframe, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props or {} do
		p[key] = value
	end
	p.Parent = parent
	return p
end

local GHOST = { Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false }
local DECOR = { CanCollide = false, CanTouch = false, CanQuery = false }

-- Mesh props (the "Stylized Forest Pack - 25 Props" from the Creator Store, kept in
-- ServerStorage.MapAssets in the place file). Without them the map falls back to primitives.
local ASSETS = ServerStorage:FindFirstChild("MapAssets")

local function hasAsset(name: string): boolean
	return ASSETS ~= nil and ASSETS:FindFirstChild(name) ~= nil
end

-- A clone of the mesh `name`, scaled so it is `height` tall, standing on `base` (a ground-level
-- CFrame that also carries the yaw).
local function heightOf(name: string): number
	local template = (ASSETS :: Folder):FindFirstChild(name) :: Instance
	if template:IsA("Model") then
		local _, size = template:GetBoundingBox()
		return size.Y
	end
	return (template :: BasePart).Size.Y
end

-- Props come as one MeshPart, or as a Model of MeshParts split by material (Trunk/Leaves,
-- Rock/Moss, Stem/Cap) with matte Wood, Grass, Rock and Fabric surfaces, pivoted at the
-- bottom centre. Every part gets `props`; plain rock parts get a slightly varied stone colour.
local function asset(parent, name: string, height: number, base: CFrame, props): Instance
	local template = (ASSETS :: Folder):FindFirstChild(name) :: Instance
	local clone = template:Clone()
	local parts: { BasePart } = {}
	if clone:IsA("Model") then
		clone:ScaleTo(clone:GetScale() * height / heightOf(name))
		clone:PivotTo(base * CFrame.new(0, -0.3, 0))
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
	else
		local p = clone :: BasePart
		p.Size = p.Size * (height / p.Size.Y)
		p.CFrame = base * CFrame.new(0, p.Size.Y / 2 - 0.3, 0)
		table.insert(parts, p)
	end
	for _, p in parts do
		p.Anchored = true
		if p.Material == Enum.Material.Rock then
			p.Color = COLORS.stone:Lerp(Color3.fromRGB(120, 112, 130), rng:NextNumber(0, 0.5))
		end
		for key, value in props or {} do
			(p :: any)[key] = value
		end
	end
	clone.Parent = parent
	return clone
end

local MESH_TREES = hasAsset("Tree_Oak_Round") and hasAsset("Tree_Pine_Tall")

-- Generated hand-painted models (stations, campfire, lamp posts, homes, decorations), kept in
-- ReplicatedStorage.WorldAssets in the place file, pivoted at their bottom centre, front -Z.
local WORLD = game:GetService("ReplicatedStorage"):FindFirstChild("WorldAssets")

local function world(group: string, name: string): Model?
	local folder = if WORLD ~= nil then WORLD:FindFirstChild(group) else nil
	local found = if folder ~= nil then folder:FindFirstChild(name) else nil
	return if found ~= nil and found:IsA("Model") then found else nil
end

-- A clone of a WorldAssets model, `height` tall, standing on `at`.
local function placeWorld(source: Model, height: number, at: CFrame, parent: Instance, collide: boolean): Model
	local m = source:Clone()
	local _, size = m:GetBoundingBox()
	m:ScaleTo(m:GetScale() * height / size.Y)
	m:PivotTo(at)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = collide
			d.CanTouch = false
			d.CanQuery = collide
		end
	end
	m.Parent = parent
	return m
end

-- A lamp post with a warm light (none without the model).
local function lampPost(parent: Instance, at: CFrame)
	local source = world("Tiers", "LampPost")
	if source == nil then
		return
	end
	local lamp = placeWorld(source, 9, at, parent, false)
	lamp.Name = "LampPost"
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 196, 120)
	light.Range = 18
	light.Brightness = 1.2
	light.Parent = lamp:FindFirstChildWhichIsA("BasePart", true)
end

local function pick(list: { string }): string
	return list[rng:NextInteger(1, #list)]
end

local function marker(parent, name, size, cframe)
	return part(parent, name, nil, size, cframe, Color3.new(1, 0, 1), nil, GHOST)
end

local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function model(name, parent)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function sign(target, text)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.5
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = COLORS.sign
	label.Text = text
	label.Parent = gui
	gui.Parent = target
end

-- Layout maths ---------------------------------------------------------------------------------

local plotStep = TAU / LAYOUT.plotCount
local function plotAngle(i: number): number
	return (i - 0.5) * plotStep -- plots in the middle of each step, so gaps fall on whole steps
end
local function plotCFrame(i: number): CFrame
	return CFrame.lookAt(polar(LAYOUT.plotRingRadius, plotAngle(i)), ORIGIN) -- local -Z faces the fire
end

local trailAngles = {}
for k = 0, LAYOUT.trails - 1 do
	table.insert(trailAngles, k * TAU / LAYOUT.trails)
end
local stationAngles = {} -- the gaps between plots that have no trail
for j = 0, LAYOUT.plotCount - 1 do
	local a = j * plotStep
	local isTrail = false
	for _, t in trailAngles do
		isTrail = isTrail or angleGap(a, t) < 1e-6
	end
	if not isTrail then
		table.insert(stationAngles, a)
	end
end
local pathAngles = {}
for i = 1, LAYOUT.plotCount do
	table.insert(pathAngles, plotAngle(i))
end
local allPathAngles = table.clone(pathAngles)
for _, a in trailAngles do
	table.insert(allPathAngles, a)
end

local W, D = LAYOUT.plotWidth, LAYOUT.plotDepth
local gateRadius = LAYOUT.plotRingRadius - D / 2

-- Spots trees keep clear of.
local reserved = {}
local function reserve(pos: Vector3, radius: number)
	table.insert(reserved, { pos = Vector3.new(pos.X, 0, pos.Z), radius = radius })
end

-- Start ----------------------------------------------------------------------------------------

local old = workspace:FindFirstChild("Map")
if old ~= nil then
	if old:GetAttribute("GeneratedBy") ~= GENERATOR or old:GetAttribute("HandEdited") == true then
		error("[Greybox] Workspace.Map was edited by hand or not made by this script; not overwriting it")
	end
	old:Destroy()
end

local moved = {}
for _, name in { "Baseplate", "SpawnLocation" } do
	local template = workspace:FindFirstChild(name)
	if template ~= nil then
		local holding = ServerStorage:FindFirstChild("ReplacedByGreybox") or folder("ReplacedByGreybox", ServerStorage)
		template.Parent = holding
		table.insert(moved, name)
	end
end

local map = Instance.new("Folder")
map.Name = "Map"
map:SetAttribute("GeneratedBy", GENERATOR)
map:SetAttribute("Seed", LAYOUT.seed)
map:SetAttribute("FireLightRadius", LAYOUT.fireLightRadius)
map:SetAttribute("PlotRingRadius", LAYOUT.plotRingRadius)
map:SetAttribute("ClearingRadius", LAYOUT.clearingRadius)
map:SetAttribute("ForestOuter", LAYOUT.forestOuter)
map:SetAttribute("MapRadius", LAYOUT.mapRadius)
map.Parent = workspace

-- Ground: Terrain with its top just under y = 0 (smooth terrain draws its surface a little above
-- the fill, so a fill to 0 would hide the floors and paths) (Bible §4: soft grass clearing, darker leafy forest, a
-- brown deepwood floor). Rebuilding clears all Terrain, so only hand-made terrain on a
-- HandEdited map is safe (the check above refuses those). Paths are parts on top: rotated
-- terrain fills leave half-covered voxels in the old material.
do
	local terrain = workspace.Terrain
	terrain:Clear()
	for material, color in TERRAIN_COLORS do
		terrain:SetMaterialColor(material, color)
	end
	pcall(function()
		-- Grass blades poke through plot floors and hide small Glowlings and pads.
		(terrain :: any).Decoration = false
	end)
	-- One column per 4-stud voxel: two full layers under a partial top layer, whose occupancy sets
	-- the surface height. The ring edges wobble with noise so they don't read as circles.
	local RES = 4
	local half = 620
	local cells = math.ceil(half * 2 / RES)
	local seedOffset = (LAYOUT.seed % 1000) / 7
	local function materialAt(x: number, z: number): Enum.Material
		local r = math.sqrt(x * x + z * z)
		local wobble = math.noise(x / 40, z / 40, seedOffset) * 10
		if r < LAYOUT.fireFeedRadius + 3 then
			return Enum.Material.Ground
		elseif r + wobble < LAYOUT.clearingRadius then
			return Enum.Material.Grass
		elseif r + wobble < LAYOUT.forestOuter then
			return Enum.Material.LeafyGrass
		elseif r + wobble < LAYOUT.mapRadius + 20 then
			return Enum.Material.Ground
		end
		return Enum.Material.Mud
	end
	local ROWS = 32
	for x0 = 0, cells - 1, ROWS do
		local rows = math.min(ROWS, cells - x0)
		local materials, occupancy = {}, {}
		for ix = 1, rows do
			local mx, ox = {}, {}
			for iy = 1, 3 do
				mx[iy], ox[iy] = {}, {}
			end
			local x = -half + (x0 + ix - 0.5) * RES
			for iz = 1, cells do
				local material = materialAt(x, -half + (iz - 0.5) * RES)
				for iy = 1, 3 do
					mx[iy][iz] = material
					ox[iy][iz] = if iy == 3 then TERRAIN_OCCUPANCY else 1
				end
			end
			materials[ix], occupancy[ix] = mx, ox
		end
		local corner = Vector3.new(-half + x0 * RES, -12, -half)
		terrain:WriteVoxels(
			Region3.new(corner, corner + Vector3.new(rows * RES, 12, cells * RES)),
			RES,
			materials,
			occupancy
		)
		task.wait()
	end
end
task.wait()

-- Mountains: a ring of peaks round the whole forest, so the world ends in rock and snow instead
-- of a flat edge, and nothing beyond it can be seen from any spot or camera angle. The foot starts
-- just past the boundary wall of trees; the ridge line wobbles and breaks into peaks with noise.
-- Grassy foothills, grey-violet rock, snow above a wavy snow line. Heightmap columns written with
-- WriteVoxels; the top voxel's occupancy smooths each column's height.
do
	local terrain = workspace.Terrain
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(112, 108, 130)) -- one calm rock, no slate patches
	terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(78, 80, 96))
	terrain:SetMaterialColor(Enum.Material.Limestone, Color3.fromRGB(78, 104, 64)) -- steep foothill moss
	terrain:SetMaterialColor(Enum.Material.Snow, Color3.fromRGB(232, 238, 248))
	local RES = 4
	local half = 620
	local cells = math.ceil(half * 2 / RES)
	local TOP = 420 -- highest voxel written
	local layers = TOP // RES
	local FOOT = LAYOUT.mapRadius + 20 -- foothills rise behind the tree wall
	local VALLEY = FOOT + 110 -- a hazy valley behind the foothills
	local RANGE = FOOT + 170 -- the main range starts rising here
	local PEAKS = FOOT + 320 -- and is at full height from here outwards
	local s = (LAYOUT.seed % 997) / 13

	local function smooth(a: number, b: number, x: number): number
		local t = math.clamp((x - a) / (b - a), 0, 1)
		return t * t * (3 - 2 * t)
	end
	-- Ridged noise in 0..1: sharp crests where plain noise crosses zero.
	local function ridged(x: number, z: number, scale: number, k: number): number
		return 1 - math.abs(math.noise(x / scale, z / scale, s + k))
	end
	-- Two tiers, so the haze layers them: green foothills, a valley, then the snowy main range.
	local function heightAt(x: number, z: number): number
		local r = math.sqrt(x * x + z * z) + math.noise(x / 90, z / 90, s) * 30
		local hills = smooth(FOOT, FOOT + 60, r) * (1 - 0.55 * smooth(VALLEY - 30, VALLEY + 20, r))
		local hillHeight = 55 + 75 * ridged(x, z, 140, 6)
		local range = smooth(RANGE, PEAKS, r)
		local peaks = 0.55 * ridged(x, z, 260, 1) + 0.3 * ridged(x, z, 110, 2) + 0.15 * ridged(x, z, 45, 3)
		local h = math.max(hills * hillHeight, range * (190 + 210 * peaks))
		if h <= 0 then
			return 0
		end
		return h + math.noise(x / 55, z / 55, s + 4) * 4 -- gentle bumps (more reads as chunky facets)
	end
	local function materialFor(y: number, h: number, x: number, z: number): Enum.Material
		local snowLine = 270 + math.noise(x / 70, z / 70, s + 5) * 30 -- caps on the peaks only
		if y >= snowLine then
			return Enum.Material.Snow
		elseif h < 150 + math.noise(x / 60, z / 60, s + 7) * 12 then
			-- Green foothills, by the column's height. Grass shows a dirt side on every voxel
			-- step, which stripes steep slopes, so those take a moss-green Limestone instead.
			local steep = math.abs(heightAt(x + 4, z) - heightAt(x - 4, z))
				+ math.abs(heightAt(x, z + 4) - heightAt(x, z - 4))
			return if steep > 6 then Enum.Material.Limestone else Enum.Material.LeafyGrass
		end
		return Enum.Material.Rock
	end

	local ROWS = 6
	for x0 = 0, cells - 1, ROWS do
		local rows = math.min(ROWS, cells - x0)
		local materials, occupancy = {}, {}
		local any = false
		for ix = 1, rows do
			local x = -half + (x0 + ix - 0.5) * RES
			local mx, ox = {}, {}
			for iy = 1, layers do
				mx[iy], ox[iy] = {}, {}
			end
			for iz = 1, cells do
				local z = -half + (iz - 0.5) * RES
				local h = heightAt(x, z)
				if h > 0 then
					any = true
				end
				for iy = 1, layers do
					local y0 = (iy - 1) * RES
					local fill = math.clamp((h - y0) / RES, 0, 1)
					if fill > 0.05 then
						mx[iy][iz] = materialFor(y0, h, x, z)
						ox[iy][iz] = fill
					else
						mx[iy][iz] = Enum.Material.Air
						ox[iy][iz] = 0
					end
				end
			end
			materials[ix], occupancy[ix] = mx, ox
		end
		if any then
			local corner = Vector3.new(-half + x0 * RES, 0, -half)
			terrain:WriteVoxels(
				Region3.new(corner, corner + Vector3.new(rows * RES, layers * RES, cells * RES)),
				RES,
				materials,
				occupancy
			)
		end
		task.wait()
	end
end
task.wait()

-- Paths: fire to every gate, and trails out through the gaps into the deepwood.
do
	local paths = folder("Paths")
	-- Cobbled lanes to the plots and a cobbled plaza round the fire; packed-earth trails into
	-- the forest, with lamp posts along them while they're still near the camp.
	local COBBLE = Color3.fromRGB(150, 136, 118)
	local function strip(name: string, from: number, to: number, a: number, width: number, cobbled: boolean)
		local cf = CFrame.lookAt(polar((from + to) / 2, a, 0.05), Vector3.new(0, 0.05, 0))
		local color = if cobbled then COBBLE else COLORS.path
		local material = if cobbled then Enum.Material.Cobblestone else Enum.Material.Ground
		part(paths, name, nil, Vector3.new(width, 0.1, to - from), cf, color, material)
		for _, side in { -1, 1 } do -- curbs: darker edges
			part(
				paths,
				`{name}Edge`,
				nil,
				Vector3.new(1, if cobbled then 0.3 else 0.08, to - from),
				cf * CFrame.new(side * (width / 2 + 0.5), if cobbled then 0.05 else -0.01, 0),
				if cobbled then Color3.fromRGB(112, 104, 96) else COLORS.path:Lerp(COLORS.clearing, 0.5),
				if cobbled then Enum.Material.Slate else Enum.Material.Ground
			)
		end
	end
	part(
		paths,
		"Plaza",
		Enum.PartType.Cylinder,
		Vector3.new(0.1, 34, 34),
		CFrame.new(0, 0.06, 0) * UPRIGHT,
		COBBLE,
		Enum.Material.Cobblestone
	)
	for i, a in pathAngles do
		strip(`PathToPlot{i}`, 16, gateRadius, a, LAYOUT.pathWidth, true)
		for _, side in { -1, 1 } do -- a lamp either side of the gate
			lampPost(
				paths,
				CFrame.lookAt(polar(gateRadius - 3, a), ORIGIN) * CFrame.new(side * (LAYOUT.pathWidth / 2 + 1.5), 0, 0)
			)
		end
	end
	for k, a in trailAngles do
		strip(`Trail{k}`, LAYOUT.fireLightRadius, LAYOUT.mapRadius - 30, a, LAYOUT.trailWidth, false)
		for n, r in { 50, 90, 130, 170 } do
			local side = if n % 2 == 0 then 1 else -1
			lampPost(paths, CFrame.lookAt(polar(r, a), ORIGIN) * CFrame.new(side * (LAYOUT.trailWidth / 2 + 1.5), 0, 0))
		end
	end
	paths.Parent = map
end
task.wait()

-- Campfire: pit, logs, flame with the light, and a stone circle on the safe radius.
do
	local fire = model("Campfire")
	local pit = part(
		fire,
		"Pit",
		Enum.PartType.Cylinder,
		Vector3.new(1, 10, 10),
		CFrame.new(0, 0.5, 0) * UPRIGHT,
		COLORS.stone,
		Enum.Material.Slate,
		{ CastShadow = false }
	)
	local pitModel = world("Stations", "Campfire")
	if pitModel ~= nil then
		-- The hand-painted pit (rune stones and stacked logs); the Pit part stays as the base.
		pit.Transparency = 1
		placeWorld(pitModel, 6.5, CFrame.new(0, 0, 0), fire, false).Name = "PitModel"
	end
	for k = 0, 2 do
		local cf = CFrame.new(0, 1.4, 0) * CFrame.Angles(0, k * math.pi / 3, 0.25)
		if pitModel ~= nil then
			break
		elseif hasAsset("Log_Fallen") then
			asset(fire, "Log_Fallen", 1.8, CFrame.new(0, 0.9, 0) * CFrame.Angles(0, k * math.pi / 3, 0.25), {
				CanCollide = false,
				CanTouch = false,
				CanQuery = false,
				CastShadow = false,
			})
			continue
		end
		part(fire, "Log", Enum.PartType.Cylinder, Vector3.new(6, 1.2, 1.2), cf, COLORS.wood, Enum.Material.Wood, {
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			CastShadow = false,
		})
	end
	local flame = part(
		fire,
		"Flame",
		Enum.PartType.Ball,
		Vector3.new(2.5, 2.5, 2.5),
		CFrame.new(0, 2, 0),
		COLORS.fire,
		Enum.Material.Neon,
		{
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		}
	)
	-- The light hangs above the logs: inside the flame, the logs and pit shadowed most of it.
	-- Its range runs past the safe radius so the pool is still visibly lit at the stone circle.
	local lightPoint = Instance.new("Attachment")
	lightPoint.Name = "LightPoint"
	lightPoint.Position = Vector3.new(LAYOUT.fireLightHeight - 0.5, 0, 0) -- the pit is an upright cylinder: local X is up
	lightPoint.Parent = pit
	local light = Instance.new("PointLight")
	light.Range = LAYOUT.fireLightRadius + 10
	light.Brightness = 4
	light.Color = Color3.fromRGB(255, 170, 90)
	light.Shadows = true
	light.Parent = lightPoint
	local flames = Instance.new("Fire")
	flames.Size = 6
	flames.Heat = 10
	flames.Parent = flame

	local r = LAYOUT.fireLightRadius
	local radius = part(
		fire,
		"LightRadius",
		Enum.PartType.Cylinder,
		Vector3.new(0.1, r * 2, r * 2),
		CFrame.new(0, 0.05, 0) * UPRIGHT,
		COLORS.fire,
		nil,
		GHOST
	)
	radius:SetAttribute("Note", "Marks the safe radius for code; the visible edge is the stone circle")
	local stones = folder("SafeCircle", fire)
	local count = 32
	for k = 0, count - 1 do
		local a = k * TAU / count
		if not onRadial(a, r, allPathAngles, LAYOUT.pathWidth / 2 + 1.5) then
			local cf = CFrame.lookAt(polar(r, a, 0.4), Vector3.new(0, 0.4, 0))
				* CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0)
			if hasAsset("Rock_Pebble") then
				asset(stones, "Rock_Pebble", 1.3, cf * CFrame.new(0, -0.4, 0), DECOR).Name = "Stone"
			else
				part(stones, "Stone", nil, Vector3.new(2.2, 1, 1.6), cf, COLORS.stone, Enum.Material.Slate, DECOR)
			end
			-- A thin Neon rune on top; CampfireController lights it by the fire's state.
			local rune = part(
				stones,
				"Rune",
				nil,
				Vector3.new(1.4, 0.06, 0.5),
				cf * CFrame.new(0, 0.53, 0),
				Color3.fromRGB(40, 36, 32),
				Enum.Material.Neon,
				{ CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false, Transparency = 0.85 }
			)
			CollectionService:AddTag(rune, "SafeRune")
		end
	end

	fire:SetAttribute("LightRadius", LAYOUT.fireLightRadius)
	fire:SetAttribute("FeedRadius", LAYOUT.fireFeedRadius)
	fire.PrimaryPart = pit
	CollectionService:AddTag(fire, "Campfire")
	fire.Parent = map
end
task.wait()

-- Plots: floor, zone, gate facing the fire, 30 slot pads, decoration zone.
-- Slot order: 1–6 in the side strips from the back (the vault pedestals are the first ones),
-- then 7–30 in three rows in front of the decoration zone, back row first.
local gatePositions = {}
do
	local plots = folder("Plots")
	for i = 1, LAYOUT.plotCount do
		local cf = plotCFrame(i)
		local plot = model(`Plot{i}`, plots)
		plot:SetAttribute("PlotId", i)

		local floor = part(plot, "Floor", nil, Vector3.new(W, 0.6, D), cf, COLORS.plot, Enum.Material.WoodPlanks)
		plot.PrimaryPart = floor
		marker(plot, "Zone", Vector3.new(W, 20, D), cf * CFrame.new(0, 10, 0))
		local decorCF = cf * CFrame.new(0, 0.32, D / 2 - LAYOUT.decorSize / 2)
		local decorSize = Vector3.new(LAYOUT.decorSize, 0.05, LAYOUT.decorSize)
		part(
			plot,
			"DecorZone",
			nil,
			decorSize,
			decorCF,
			COLORS.decor,
			nil,
			{ Transparency = 0.9, CanCollide = false, CanTouch = false, CanQuery = false }
		)

		local gateZ = -D / 2
		marker(plot, "Gate", Vector3.new(11, 10, 2), cf * CFrame.new(0, 5, gateZ))
		for _, x in { -6, 6 } do
			part(
				plot,
				"GatePost",
				nil,
				Vector3.new(1, 10, 1),
				cf * CFrame.new(x, 5.3, gateZ),
				COLORS.wood,
				Enum.Material.Wood
			)
		end
		local lintel = part(
			plot,
			"Sign",
			nil,
			Vector3.new(13, 1.8, 1),
			cf * CFrame.new(0, 11.2, gateZ),
			COLORS.wood,
			Enum.Material.Wood
		)
		sign(lintel, `Plot {i}`)

		local slots = folder("Slots", plot)
		local n = 0
		local function pad(x: number, z: number)
			n += 1
			local p = part(
				slots,
				string.format("Slot%02d", n),
				nil,
				Vector3.new(3, 0.2, 3),
				cf * CFrame.new(x, 0.4, z),
				COLORS.pad,
				Enum.Material.Slate
			)
			p:SetAttribute("Slot", n)
		end
		for _, z in { 8, 4, 0 } do
			pad(-15, z)
			pad(15, z)
		end
		for _, z in { -8, -12, -16 } do
			for x = -14, 14, 4 do
				pad(x, z)
			end
		end

		-- Homestead dressing (decor only: no collision, so stealing and the gate rules are
		-- unchanged): darker edge beams, a low picket fence with a gap at the gate, lanterns on
		-- the gate posts, and moss creeping in at the back corners.
		local dressing = folder("Dressing", plot)
		local trim = COLORS.wood:Lerp(Color3.new(0, 0, 0), 0.25)
		for _, beam in
			{
				{ Vector3.new(W + 0.6, 0.8, 1), CFrame.new(0, 0.1, -D / 2) },
				{ Vector3.new(W + 0.6, 0.8, 1), CFrame.new(0, 0.1, D / 2) },
				{ Vector3.new(1, 0.8, D), CFrame.new(-W / 2, 0.1, 0) },
				{ Vector3.new(1, 0.8, D), CFrame.new(W / 2, 0.1, 0) },
			}
		do
			part(dressing, "Trim", nil, beam[1], cf * beam[2], trim, Enum.Material.Wood, DECOR)
		end
		-- The fence, the home behind the plot and its lamps grow with the base: the client
		-- dresses them (BaseDresser) from the owner's pads.
		local hw, hd = W / 2 - 0.3, D / 2 - 0.3
		for _, corner in { { -1, 1 }, { 1, 1 } } do
			for m = 1, 3 do
				local size = Vector3.new(rng:NextNumber(2.5, 5), 0.12, rng:NextNumber(2, 4))
				local at = Vector3.new(
					corner[1] * (hw - size.X / 2 - rng:NextNumber(0, 3)),
					0.33,
					hd - size.Z / 2 - rng:NextNumber(0, 4 * m)
				)
				part(
					dressing,
					"Moss",
					nil,
					size,
					cf * CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0),
					Color3.fromRGB(86, 120, 58):Lerp(Color3.fromRGB(110, 140, 70), rng:NextNumber()),
					Enum.Material.Grass,
					DECOR
				)
			end
		end

		CollectionService:AddTag(plot, "Plot")
		gatePositions[i] = (cf * CFrame.new(0, 0, gateZ)).Position
		reserve(cf.Position, math.sqrt((W / 2) ^ 2 + (D / 2) ^ 2) + 2)
		reserve((cf * CFrame.new(0, 0, D / 2 + 14)).Position, 17) -- room for the home
	end
	plots.Parent = map
end
task.wait()

-- Stations on the inner ring, in the gaps without trails.
local stationPositions = {}
do
	local stations = folder("Stations")
	for k, info in STATIONS do
		local a = stationAngles[k]
		if a == nil then
			break
		end
		local pos = polar(LAYOUT.stationRadius, a)
		local cf = CFrame.lookAt(pos, ORIGIN)
		local station = model(info.kind, stations)
		station:SetAttribute("Kind", info.kind)
		local look = world("Stations", info.kind)
		local base = part(
			station,
			"Base",
			nil,
			Vector3.new(12, 0.6, 9),
			cf * CFrame.new(0, 0.3, 0),
			COLORS.wood,
			Enum.Material.WoodPlanks,
			if look ~= nil then { Transparency = 1 } else nil
		)
		local signHeight = 7.4
		if look ~= nil then
			-- A hand-painted building; the sign hangs above its front.
			local height = STATION_HEIGHT[info.kind] or 12
			placeWorld(look, height, cf, station, true).Name = "Building"
			signHeight = height + 1.6
			if info.kind == "Leaderboards" then
				-- The flat face the board's SurfaceGui draws on (LeaderboardController).
				part(
					station,
					"BoardFace",
					nil,
					Vector3.new(height * 0.72, height * 0.5, 0.2),
					cf * CFrame.new(0, height * 0.46, -1.7),
					Color3.fromRGB(46, 36, 30),
					Enum.Material.Wood,
					DECOR
				)
				signHeight = height + 1
			end
		else
			part(
				station,
				"Counter",
				nil,
				Vector3.new(10, 3, 1.5),
				cf * CFrame.new(0, 2.1, -2.5),
				COLORS.wood,
				Enum.Material.Wood
			)
			for _, x in { -5.5, 5.5 } do
				part(
					station,
					"Post",
					nil,
					Vector3.new(0.8, 8, 0.8),
					cf * CFrame.new(x, 4.6, 3.8),
					COLORS.wood,
					Enum.Material.Wood
				)
			end
			part(
				station,
				"Roof",
				nil,
				Vector3.new(13, 0.6, 10),
				cf * CFrame.new(0, 8.9, 0),
				COLORS.wood,
				Enum.Material.WoodPlanks
			)
		end
		local board = part(
			station,
			"Sign",
			nil,
			Vector3.new(10, 2, 0.4),
			cf * CFrame.new(0, signHeight, -4.6),
			COLORS.wood,
			Enum.Material.Wood
		)
		sign(board, info.label)
		station.PrimaryPart = base
		CollectionService:AddTag(station, "Station")
		table.insert(stationPositions, pos)
	end
	stations.Parent = map
end
task.wait()

-- Forest: wood piles, wild spawn points, shard spawn points.
local forest = folder("Forest")
do
	local piles = folder("WoodPiles", forest)
	for i = 1, LAYOUT.woodPiles do
		local a = (i - 0.5) * TAU / LAYOUT.woodPiles + rng:NextNumber(-0.06, 0.06)
		local r = LAYOUT.woodPileRadii[(i - 1) % #LAYOUT.woodPileRadii + 1]
		local pos = polar(r, a)
		local cf = CFrame.lookAt(pos, ORIGIN)
		local pile = model(string.format("WoodPile%02d", i), piles)
		pile:SetAttribute("PileId", string.format("W%02d", i))
		for k, offset in { Vector3.new(-0.8, 0.7, 0), Vector3.new(0.8, 0.7, 0), Vector3.new(0, 1.9, 0) } do
			local log = if hasAsset("Log_Fallen")
				then asset(
					pile,
					"Log_Fallen",
					2.4,
					cf * CFrame.new(offset - Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, math.pi / 2 + k * 0.3, 0)
				)
				else part(
					pile,
					"Log",
					Enum.PartType.Cylinder,
					Vector3.new(6, 1.4, 1.4),
					cf * CFrame.new(offset) * CFrame.Angles(0, math.pi / 2, 0),
					COLORS.wood,
					Enum.Material.Wood
				)
			if k == 1 then
				pile.PrimaryPart = log
			end
		end
		CollectionService:AddTag(pile, "WoodPile")
		reserve(pos, 9)
	end

	local function points(
		folderName: string,
		prefix: string,
		tag: string,
		count: number,
		rMin: number,
		rMax: number,
		area: string?
	)
		local f = folder(folderName, forest)
		for i = 1, count do
			local a = (i - 0.5) * TAU / count + rng:NextNumber(-0.05, 0.05)
			local pos = polar(rng:NextNumber(rMin, rMax), a, 2)
			local p = marker(f, string.format("%s%02d", prefix, i), Vector3.new(2, 2, 2), CFrame.new(pos))
			if area ~= nil then
				p:SetAttribute("Area", area)
			end
			CollectionService:AddTag(p, tag)
			reserve(pos, 6)
		end
	end
	points(
		"ForestSpawns",
		"Forest",
		"WildSpawn",
		LAYOUT.forestSpawns,
		LAYOUT.clearingRadius + 8,
		LAYOUT.forestOuter - 8,
		"Forest"
	)
	points(
		"DeepwoodSpawns",
		"Deepwood",
		"WildSpawn",
		LAYOUT.deepwoodSpawns,
		LAYOUT.forestOuter + 15,
		LAYOUT.mapRadius - 20,
		"Deepwood"
	)
	points(
		"ShardSpawns",
		"Shard",
		"ShardSpawn",
		LAYOUT.shardSpawns,
		LAYOUT.forestOuter + 15,
		LAYOUT.mapRadius - 20,
		nil
	)
	forest.Parent = map
end
task.wait()

-- Trees: forest ring, a denser deepwood, and a wall of trees on the boundary.
local treeCount = 0
do
	local CELL = 14 -- at least the largest gap, so only neighbouring cells need checking
	local grid = {}
	local function key(x: number, z: number): number
		return math.floor(x / CELL) * 1000 + math.floor(z / CELL)
	end
	local function nearTree(pos: Vector3, gap: number): boolean
		local cx, cz = math.floor(pos.X / CELL), math.floor(pos.Z / CELL)
		for dx = -1, 1 do
			for dz = -1, 1 do
				for _, other in grid[(cx + dx) * 1000 + (cz + dz)] or {} do
					if (pos - other).Magnitude < gap then
						return true
					end
				end
			end
		end
		return false
	end
	local function free(pos: Vector3, gap: number): boolean
		for _, spot in reserved do
			if (pos - spot.pos).Magnitude < spot.radius then
				return false
			end
		end
		local r = pos.Magnitude
		if
			r < LAYOUT.mapRadius - 25 and onRadial(math.atan2(pos.Z, pos.X), r, trailAngles, LAYOUT.trailWidth / 2 + 4)
		then
			return false
		end
		return not nearTree(pos, gap)
	end

	local spots = {}
	local function scatter(count: number, rMin: number, rMax: number, gap: number, deep: boolean)
		local placed, tries = 0, 0
		while placed < count and tries < count * 30 do
			tries += 1
			local r = math.sqrt(rng:NextNumber(rMin * rMin, rMax * rMax)) -- even by area
			local pos = polar(r, rng:NextNumber(0, TAU))
			if free(pos, gap) then
				local k = key(pos.X, pos.Z)
				grid[k] = grid[k] or {}
				table.insert(grid[k], pos)
				table.insert(spots, { pos = pos, deep = deep })
				placed += 1
			end
		end
	end
	scatter(130, LAYOUT.clearingRadius + 2, LAYOUT.forestOuter, 13, false)
	scatter(420, LAYOUT.forestOuter, LAYOUT.mapRadius - 12, 11, true)
	scatter(260, LAYOUT.mapRadius - 14, LAYOUT.mapRadius + 16, 7, true)

	local trees = folder("Trees", forest)
	local batch = {}
	local function flush()
		for _, t in batch do
			t.Parent = trees
		end
		table.clear(batch)
		task.wait()
	end
	local glowLights = 0
	for _, spot in spots do
		local deep = spot.deep
		-- Three kinds (Bible §4: a storybook forest, not a lollipop grid): broad oaks with 3–5
		-- lobes, layered pines (most of the deepwood and the boundary wall), and a rare pale
		-- "spirit tree" with a teal or lilac canopy.
		local edge = spot.pos.Magnitude > LAYOUT.mapRadius - 16
		local roll = rng:NextNumber()
		local kind = if roll < 0.06
			then "spirit"
			elseif roll < (if edge then 0.75 elseif deep then 0.45 else 0.15) then "pine"
			else "oak"
		local height = if deep then rng:NextNumber(28, 42) else rng:NextNumber(20, 30)
		local width = if deep then rng:NextNumber(4, 6) else rng:NextNumber(3, 4.5)
		local crown = if deep then rng:NextNumber(18, 26) else rng:NextNumber(13, 19)
		if kind == "pine" then
			height *= 0.55
			width *= 0.7
		end
		local tree = model("Tree")
		tree:SetAttribute("Kind", kind)
		local base = spot.pos
		local turn = CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
		local bark = if kind == "spirit" then Color3.fromRGB(205, 200, 215) else COLORS.trunk
		if MESH_TREES then
			-- One low-poly mesh per tree, plus an invisible trunk so players can't walk through it.
			local total = if deep then rng:NextNumber(40, 56) else rng:NextNumber(30, 40)
			if edge then
				total *= 1.15
			end
			local name = if kind == "pine"
				then pick({ "Tree_Pine_Classic", "Tree_Pine_Tall", "Tree_Pine_Tall", "Tree_Pine_Young" })
				else pick({ "Tree_Oak_Round", "Tree_Oak_Small", "Tree_Oak_Tall" })
			local mesh = asset(tree, name, total, CFrame.new(base) * turn, DECOR)
			mesh.Name = "Crown"
			-- Each tree's leaves get their own shade; spirit trees glow pale teal or lilac.
			local leafColor = if kind == "spirit"
				then (if rng:NextNumber() < 0.5 then Color3.fromRGB(150, 225, 215) else Color3.fromRGB(200, 180, 240))
				elseif kind == "pine" then Color3.fromRGB(44, 88, 64)
					:Lerp(Color3.fromRGB(70, 110, 70), rng:NextNumber(0, 0.5))
				else (if deep then COLORS.deepLeaves else COLORS.leaves):Lerp(
					Color3.fromRGB(90, 120, 60),
					rng:NextNumber(0, 0.35)
				)
			for _, d in mesh:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Leaves" then
					d.Color = leafColor
				elseif d:IsA("BasePart") and d.Name == "Trunk" then
					d.Color = bark
				end
			end
			part(
				tree,
				"Trunk",
				Enum.PartType.Cylinder,
				Vector3.new(total * 0.45, width * 0.6, width * 0.6),
				CFrame.new(base + Vector3.new(0, total * 0.225, 0)) * UPRIGHT,
				bark,
				nil,
				{ Transparency = 1, CastShadow = false }
			)
		else
			part(
				tree,
				"Trunk",
				Enum.PartType.Cylinder,
				Vector3.new(height, width, width),
				CFrame.new(base + Vector3.new(0, height / 2, 0)) * UPRIGHT,
				bark,
				Enum.Material.Wood
			)
			part(
				tree,
				"Roots",
				Enum.PartType.Cylinder,
				Vector3.new(2, width * 1.6, width * 1.6),
				CFrame.new(base + Vector3.new(0, 0.6, 0)) * UPRIGHT,
				bark,
				Enum.Material.Wood,
				DECOR
			)
			local leaves = if deep then COLORS.deepLeaves else COLORS.leaves
			local shade = leaves:Lerp(Color3.fromRGB(90, 120, 60), rng:NextNumber(0, 0.35))
			if kind == "pine" then
				-- Stacked tiers that narrow to a tip: a stylised fir.
				local tiers = rng:NextInteger(4, 5)
				local spread = crown * rng:NextNumber(0.75, 0.95)
				local tierH = crown * 0.32
				local pineColor = Color3.fromRGB(38, 70, 58):Lerp(shade, 0.3)
				for t = 1, tiers do
					local f = 1 - (t - 1) / tiers
					part(
						tree,
						if t == 1 then "Crown" else "Tier",
						Enum.PartType.Cylinder,
						Vector3.new(tierH, spread * f, spread * f),
						CFrame.new(base + Vector3.new(0, height + (t - 1) * tierH * 0.72, 0)) * turn * UPRIGHT,
						pineColor:Lerp(Color3.new(0, 0, 0), 0.08 * (tiers - t)),
						Enum.Material.LeafyGrass,
						DECOR
					)
				end
			else
				if kind == "spirit" then
					shade = if rng:NextNumber() < 0.5
						then Color3.fromRGB(96, 170, 160)
						else Color3.fromRGB(150, 128, 190)
				end
				-- A main crown and 2–4 lower lobes, so the canopy reads as a cloud, not a ball.
				local lobes = {
					{ 0, 0, 0, 1 },
					{ 0.32, -0.28, 0.1, 0.72 },
					{ -0.3, -0.22, -0.18, 0.66 },
					{ 0.05, 0.22, -0.3, 0.6 },
					{ -0.12, -0.32, 0.34, 0.58 },
				}
				local count = rng:NextInteger(3, 5)
				for k = 1, count do
					local lobe = lobes[k]
					local size = crown * lobe[4] * rng:NextNumber(0.9, 1.1)
					local offset = (turn * Vector3.new(lobe[1], 0, lobe[3])) * crown
					part(
						tree,
						if k == 1 then "Crown" else "Lobe",
						Enum.PartType.Ball,
						Vector3.one * size,
						CFrame.new(base + Vector3.new(offset.X, height + lobe[2] * crown, offset.Z)),
						if k == 1 then shade else shade:Lerp(Color3.new(0, 0, 0), 0.08 + 0.04 * k),
						Enum.Material.LeafyGrass,
						DECOR
					)
				end
			end
		end
		-- Deepwood trees sometimes grow a ring of glow mushrooms at the roots.
		if deep and rng:NextNumber() < 0.18 then
			local glow = GLOW[rng:NextInteger(1, #GLOW)]
			for m = 1, 3 do
				local at = base + turn * Vector3.new(math.cos(m * 2.1), 0, math.sin(m * 2.1)) * (width * 0.8 + 1)
				local stem = rng:NextNumber(0.8, 1.6)
				if hasAsset("Mushroom_Red") then
					-- A low-poly mushroom lit from inside: no texture, Neon in the glow colour.
					local shroom = asset(
						tree,
						pick({ "Mushroom_Red", "Mushroom_Brown", "Mushroom_Golden" }),
						stem * 1.4,
						CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0),
						DECOR
					)
					shroom.TextureID = ""
					shroom.Color = glow
					shroom.Material = Enum.Material.Neon
					if m == 1 and glowLights < MAX_GLOW_LIGHTS then
						glowLights += 1
						local light = Instance.new("PointLight")
						light.Color = glow
						light.Range = 12
						light.Brightness = 1.2
						light.Parent = shroom
					end
					continue
				end
				part(
					tree,
					"MushroomStem",
					Enum.PartType.Cylinder,
					Vector3.new(stem, 0.35, 0.35),
					CFrame.new(at + Vector3.new(0, stem / 2, 0)) * UPRIGHT,
					Color3.fromRGB(220, 220, 205),
					Enum.Material.SmoothPlastic,
					DECOR
				)
				local cap = part(
					tree,
					"MushroomCap",
					Enum.PartType.Cylinder,
					Vector3.new(0.4, stem * 1.1, stem * 1.1),
					CFrame.new(at + Vector3.new(0, stem, 0)) * UPRIGHT,
					glow,
					Enum.Material.Neon,
					DECOR
				)
				if m == 1 and glowLights < MAX_GLOW_LIGHTS then
					glowLights += 1
					local light = Instance.new("PointLight")
					light.Color = glow
					light.Range = 12
					light.Brightness = 1.2
					light.Parent = cap
				end
			end
		end
		table.insert(batch, tree)
		treeCount += 1
		if #batch >= 150 then
			flush()
		end
	end
	flush()

	-- Undergrowth: bushes and mossy rocks between the trees, firefly swarms in the forest ring.
	local props = folder("Props", forest)
	local function spotIn(rMin: number, rMax: number, gap: number): Vector3?
		for _ = 1, 30 do
			local r = math.sqrt(rng:NextNumber(rMin * rMin, rMax * rMax))
			local pos = polar(r, rng:NextNumber(0, TAU))
			if free(pos, gap) then
				return pos
			end
		end
		return nil
	end
	for n = 1, 220 do
		local pos = spotIn(LAYOUT.clearingRadius - 4, LAYOUT.mapRadius - 14, 4)
		if pos ~= nil and hasAsset("Bush_Round") then
			asset(
				props,
				pick({ "Bush_Round", "Bush_Wide", "Bush_Compact", "Bush_Berries" }),
				rng:NextNumber(2.6, 5),
				CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0),
				DECOR
			).Name =
				"Bush"
		elseif pos ~= nil then
			local bush = model("Bush", props)
			local size = rng:NextNumber(3, 6)
			local color = COLORS.leaves:Lerp(Color3.fromRGB(100, 130, 60), rng:NextNumber(0, 0.5))
			for k = 1, 2 do
				local offset = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * size * 0.4
				part(
					bush,
					"Leaves",
					Enum.PartType.Ball,
					Vector3.one * size * (if k == 1 then 1 else 0.75),
					CFrame.new(pos + offset + Vector3.new(0, size * 0.3, 0)),
					color,
					Enum.Material.LeafyGrass,
					DECOR
				)
			end
		end
		if n % 60 == 0 then
			task.wait()
		end
	end
	for _ = 1, 90 do
		local pos = spotIn(LAYOUT.clearingRadius - 6, LAYOUT.mapRadius - 14, 5)
		if pos ~= nil and hasAsset("Rock_Mossy") then
			local name =
				pick({ "Rock_Mossy", "Rock_Mossy", "Rock_Boulder", "Rock_Stack", "Rock_Standing", "Rock_Flat" })
			asset(
				props,
				name,
				heightOf(name) * rng:NextNumber(0.8, 1.5),
				CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
			).Name =
				"Rock"
		elseif pos ~= nil then
			local size = Vector3.new(rng:NextNumber(3, 7), rng:NextNumber(2, 4), rng:NextNumber(3, 6))
			local rock = part(
				props,
				"Rock",
				nil,
				size,
				CFrame.new(pos + Vector3.new(0, size.Y * 0.3, 0))
					* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, TAU), rng:NextNumber(-0.3, 0.3)),
				COLORS.stone,
				Enum.Material.Slate
			)
			part(
				props,
				"Moss",
				nil,
				Vector3.new(size.X * 0.8, 0.4, size.Z * 0.8),
				rock.CFrame * CFrame.new(0, size.Y / 2, 0),
				Color3.fromRGB(80, 110, 55),
				Enum.Material.Grass,
				DECOR
			)
		end
	end
	-- Forest-floor clutter (mesh props only): stumps, fallen logs, mushroom clusters, pebbles.
	if hasAsset("Stump_Short") then
		local clutter = {
			{ "Stump_Short", 3 },
			{ "Stump_Branch", 3.6 },
			{ "Log_Fallen", 3 },
			{ "Mushrooms_Brown_Cluster", 2.2 },
			{ "Mushrooms_Red_Cluster", 1.8 },
			{ "Mushrooms_Golden_Cluster", 2 },
			{ "Rock_Pebble", 1.4 },
		}
		for n = 1, 160 do
			local pos = spotIn(LAYOUT.clearingRadius + 4, LAYOUT.mapRadius - 14, 4)
			if pos ~= nil then
				local what = clutter[rng:NextInteger(1, #clutter)]
				asset(
					props,
					what[1],
					what[2] * rng:NextNumber(0.8, 1.3),
					CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0),
					DECOR
				)
			end
			if n % 60 == 0 then
				task.wait()
			end
		end
	end
	for _ = 1, 24 do
		local pos = spotIn(LAYOUT.clearingRadius + 6, LAYOUT.mapRadius - 20, 6)
		if pos ~= nil then
			local swarm = part(
				props,
				"Fireflies",
				nil,
				Vector3.new(16, 6, 16),
				CFrame.new(pos + Vector3.new(0, 4, 0)),
				Color3.new(),
				nil,
				GHOST
			)
			local emitter = Instance.new("ParticleEmitter")
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Rate = 4
			emitter.Lifetime = NumberRange.new(3, 6)
			emitter.Speed = NumberRange.new(0.2, 0.8)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Acceleration = Vector3.new(0, 0.1, 0)
			emitter.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.25),
				NumberSequenceKeypoint.new(1, 0),
			})
			emitter.Color = ColorSequence.new(Color3.fromRGB(220, 255, 140))
			emitter.LightEmission = 1
			emitter.Parent = swarm
		end
	end
end

-- Clearing dressing: wildflowers in the grass (and plain lantern posts by the paths when the
-- generated lamp posts are missing).
do
	local dressing = folder("Dressing")
	if world("Tiers", "LampPost") == nil then -- the paths have generated lamp posts otherwise
		for i, a in pathAngles do
			local side = if i % 2 == 0 then 1 else -1
			local cf = CFrame.lookAt(polar(gateRadius - 6, a, 0), ORIGIN)
				* CFrame.new(side * (LAYOUT.pathWidth / 2 + 1.5), 0, 0)
			local post = model(`LanternPost{i}`, dressing)
			part(
				post,
				"Post",
				Enum.PartType.Cylinder,
				Vector3.new(8, 0.6, 0.6),
				cf * CFrame.new(0, 4, 0) * UPRIGHT,
				COLORS.wood,
				Enum.Material.Wood
			)
			part(
				post,
				"Arm",
				nil,
				Vector3.new(0.4, 0.4, 2),
				cf * CFrame.new(0, 7.8, -0.8),
				COLORS.wood,
				Enum.Material.Wood,
				DECOR
			)
			local lantern = part(
				post,
				"Lantern",
				nil,
				Vector3.new(1, 1.3, 1),
				cf * CFrame.new(0, 6.9, -1.6),
				COLORS.gold,
				Enum.Material.Neon,
				DECOR
			)
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 190, 110)
			light.Range = 14
			light.Brightness = 1.2
			light.Parent = lantern
		end
	end
	local petals = {
		Color3.fromRGB(250, 235, 150),
		Color3.fromRGB(240, 170, 200),
		Color3.fromRGB(190, 200, 255),
		Color3.fromRGB(255, 255, 240),
	}
	local stations = {}
	for _, a in stationAngles do
		table.insert(stations, polar(LAYOUT.stationRadius, a))
	end
	local placed = 0
	for _ = 1, 600 do
		if placed >= 160 then
			break
		end
		local r = rng:NextNumber(LAYOUT.fireLightRadius + 4, LAYOUT.clearingRadius - 3)
		local a = rng:NextNumber(0, TAU)
		local pos = polar(r, a)
		local clear = not onRadial(a, r, allPathAngles, LAYOUT.pathWidth / 2 + 1.5)
		for _, spot in reserved do
			clear = clear and (pos - spot.pos).Magnitude >= spot.radius
		end
		for _, at in stations do
			clear = clear and (pos - at).Magnitude >= 12
		end
		if clear then
			placed += 1
			local color = petals[rng:NextInteger(1, #petals)]
			for k = 1, 3 do
				local at = pos + Vector3.new(rng:NextNumber(-1.2, 1.2), 0, rng:NextNumber(-1.2, 1.2))
				part(
					dressing,
					"Flower",
					Enum.PartType.Ball,
					Vector3.one * 0.5,
					CFrame.new(at + Vector3.new(0, 0.35 + k * 0.05, 0)),
					color,
					Enum.Material.SmoothPlastic,
					DECOR
				)
			end
		end
	end
	dressing.Parent = map
end

-- Boundary wall and the spawn.
do
	local boundary = folder("Boundary")
	local segments = 36
	local R = LAYOUT.mapRadius
	local length = TAU * R / segments + 2
	for k = 0, segments - 1 do
		local cf = CFrame.lookAt(polar(R, k * TAU / segments, 40), Vector3.new(0, 40, 0))
		part(
			boundary,
			"Wall",
			nil,
			Vector3.new(length, 80, 2),
			cf,
			Color3.new(0, 0, 0),
			nil,
			{ Transparency = 1, CanQuery = false, CastShadow = false }
		)
	end
	boundary.Parent = map

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = CFrame.lookAt(polar(18, trailAngles[1], 0.2), Vector3.new(0, 0.2, 0))
	spawn.Color = COLORS.stone
	spawn.Material = Enum.Material.Slate
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = map
end

-- Measured metrics, for CONTENT_AND_LIVEOPS §A2.
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end
local function innerCorners(i: number): { Vector3 }
	local cf = plotCFrame(i)
	return { (cf * CFrame.new(-W / 2, 0, -D / 2)).Position, (cf * CFrame.new(W / 2, 0, -D / 2)).Position }
end
local narrowest = math.huge
for _, a in innerCorners(1) do
	for _, b in innerCorners(2) do
		narrowest = math.min(narrowest, (a - b).Magnitude)
	end
end
local stationWorst = 0
for _, s in stationPositions do
	for _, g in gatePositions do
		stationWorst = math.max(stationWorst, (flat(s) - flat(g)).Magnitude)
	end
end
local run = LAYOUT.runSpeed
local carry = run * LAYOUT.carryMult
local gateToFire = flat(gatePositions[1]).Magnitude
local neighbour = (plotCFrame(1).Position - plotCFrame(2).Position).Magnitude
local across = (flat(gatePositions[1]) - flat(gatePositions[1 + LAYOUT.plotCount // 2])).Magnitude
local partCount = 0
for _, d in map:GetDescendants() do
	if d:IsA("BasePart") then
		partCount += 1
	end
end

local lines = {
	"[Greybox] Built Workspace.Map",
	string.format(
		"Gate to fire centre: %.1f studs (%.1f s at run speed); to the safe edge: %.1f",
		gateToFire,
		gateToFire / run,
		gateToFire - LAYOUT.fireLightRadius
	),
	string.format("Neighbouring plots, centre to centre: %.1f studs", neighbour),
	string.format("Narrowest gap between neighbouring plots (inner corners): %.1f studs", narrowest),
	string.format(
		"Gate to opposite gate: %.1f studs (%.1f s carrying, %.1f s running)",
		across,
		across / carry,
		across / run
	),
	string.format("Farthest gate from a station: %.1f studs (%.1f s)", stationWorst, stationWorst / run),
	string.format("Trees: %d; parts: %d", treeCount, partCount),
	if #moved > 0 then "Moved to ServerStorage.ReplacedByGreybox: " .. table.concat(moved, ", ") else "Nothing moved",
}
local summary = table.concat(lines, "\n")
print(summary)
return summary
