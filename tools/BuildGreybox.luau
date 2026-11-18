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
--   Plot        Model, PlotId 1–8. Children: Floor, Zone, Gate, DecorZone, Slots (pads with Slot 1–30), Trophy, Sign
--   Campfire    Model, LightRadius, FeedRadius
--   WoodPile    Model, PileId "W01"…
--   WildSpawn   Part, Area "Forest" | "Deepwood"
--   ShardSpawn  Part
--   Station     Model, Kind "LanternShop" | "WispStash" | "Leaderboards" | "WhatsNew"
-- The Map folder carries the ring radii as attributes.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

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

local COLORS = {
	outer = Color3.fromRGB(34, 40, 32),
	deepwood = Color3.fromRGB(48, 58, 40),
	forest = Color3.fromRGB(62, 78, 48),
	clearing = Color3.fromRGB(92, 118, 64),
	path = Color3.fromRGB(140, 120, 90),
	stone = Color3.fromRGB(110, 108, 104),
	plot = Color3.fromRGB(150, 150, 145),
	pad = Color3.fromRGB(200, 196, 180),
	decor = Color3.fromRGB(120, 160, 200),
	wood = Color3.fromRGB(105, 75, 50),
	trunk = Color3.fromRGB(80, 60, 45),
	leaves = Color3.fromRGB(45, 80, 45),
	deepLeaves = Color3.fromRGB(30, 55, 38),
	fire = Color3.fromRGB(255, 150, 60),
	gold = Color3.fromRGB(230, 190, 80),
	sign = Color3.fromRGB(245, 235, 210),
}

local TAU = 2 * math.pi
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

local function marker(parent, name, size, cframe)
	return part(parent, name, nil, size, cframe, Color3.new(1, 0, 1), nil, GHOST)
end

local function disc(parent, name, radius, topY, color, material)
	local thickness = 4
	local size = Vector3.new(thickness, radius * 2, radius * 2)
	return part(
		parent,
		name,
		Enum.PartType.Cylinder,
		size,
		CFrame.new(0, topY - thickness / 2, 0) * UPRIGHT,
		color,
		material
	)
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

-- Ground: stacked discs, each a hair above the one under it.
do
	local ground = folder("Ground")
	disc(ground, "Outer", 600, -0.15, COLORS.outer, Enum.Material.Ground)
	disc(ground, "Deepwood", LAYOUT.mapRadius + 20, -0.1, COLORS.deepwood, Enum.Material.Grass)
	disc(ground, "Forest", LAYOUT.forestOuter, -0.05, COLORS.forest, Enum.Material.Grass)
	disc(ground, "Clearing", LAYOUT.clearingRadius, 0, COLORS.clearing, Enum.Material.Grass)
	ground.Parent = map
end
task.wait()

-- Paths: fire to every gate, and trails out through the gaps into the deepwood.
do
	local paths = folder("Paths")
	for i, a in pathAngles do
		local from, to = 5, gateRadius
		local cf = CFrame.lookAt(polar((from + to) / 2, a, 0.01), Vector3.new(0, 0.01, 0))
		part(
			paths,
			`PathToPlot{i}`,
			nil,
			Vector3.new(LAYOUT.pathWidth, 0.1, to - from),
			cf,
			COLORS.path,
			Enum.Material.Ground
		)
	end
	for k, a in trailAngles do
		local from, to = LAYOUT.fireLightRadius, LAYOUT.mapRadius - 30
		local cf = CFrame.lookAt(polar((from + to) / 2, a, 0.01), Vector3.new(0, 0.01, 0))
		part(
			paths,
			`Trail{k}`,
			nil,
			Vector3.new(LAYOUT.trailWidth, 0.1, to - from),
			cf,
			COLORS.path,
			Enum.Material.Ground
		)
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
	for k = 0, 2 do
		local cf = CFrame.new(0, 1.4, 0) * CFrame.Angles(0, k * math.pi / 3, 0.25)
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
			part(stones, "Stone", nil, Vector3.new(2.2, 1, 1.6), cf, COLORS.stone, Enum.Material.Slate, DECOR)
		end
	end

	fire:SetAttribute("LightRadius", LAYOUT.fireLightRadius)
	fire:SetAttribute("FeedRadius", LAYOUT.fireFeedRadius)
	fire.PrimaryPart = pit
	CollectionService:AddTag(fire, "Campfire")
	fire.Parent = map
end
task.wait()

-- Plots: floor, zone, gate facing the fire, 30 slot pads, decoration zone, trophy.
-- Slot order: 1–6 in the side strips from the back (the vault pedestals are the first ones),
-- then 7–30 in three rows in front of the decoration zone, back row first.
local gatePositions = {}
do
	local plots = folder("Plots")
	for i = 1, LAYOUT.plotCount do
		local cf = plotCFrame(i)
		local plot = model(`Plot{i}`, plots)
		plot:SetAttribute("PlotId", i)

		local floor = part(plot, "Floor", nil, Vector3.new(W, 0.6, D), cf, COLORS.plot, Enum.Material.Concrete)
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
			{ Transparency = 0.6, CanCollide = false, CanTouch = false, CanQuery = false }
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
				COLORS.pad
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

		local trophy = model("Trophy", plot)
		part(
			trophy,
			"Pedestal",
			nil,
			Vector3.new(3, 2, 3),
			cf * CFrame.new(15, 1.3, 15),
			COLORS.stone,
			Enum.Material.Marble
		)
		part(
			trophy,
			"Cup",
			Enum.PartType.Ball,
			Vector3.new(1.6, 1.6, 1.6),
			cf * CFrame.new(15, 3.1, 15),
			COLORS.gold,
			Enum.Material.Metal
		)

		CollectionService:AddTag(plot, "Plot")
		gatePositions[i] = (cf * CFrame.new(0, 0, gateZ)).Position
		reserve(cf.Position, math.sqrt((W / 2) ^ 2 + (D / 2) ^ 2) + 2)
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
		local base = part(
			station,
			"Base",
			nil,
			Vector3.new(12, 0.6, 9),
			cf * CFrame.new(0, 0.3, 0),
			COLORS.wood,
			Enum.Material.WoodPlanks
		)
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
		local board = part(
			station,
			"Sign",
			nil,
			Vector3.new(10, 2, 0.4),
			cf * CFrame.new(0, 7.4, -4.6),
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
			local log = part(
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
	for _, spot in spots do
		local deep = spot.deep
		local height = if deep then rng:NextNumber(28, 42) else rng:NextNumber(20, 30)
		local width = if deep then rng:NextNumber(4, 6) else rng:NextNumber(3, 4.5)
		local crown = if deep then rng:NextNumber(20, 30) else rng:NextNumber(14, 22)
		local tree = model("Tree")
		local base = spot.pos
		part(
			tree,
			"Trunk",
			Enum.PartType.Cylinder,
			Vector3.new(height, width, width),
			CFrame.new(base + Vector3.new(0, height / 2, 0)) * UPRIGHT,
			COLORS.trunk,
			Enum.Material.Wood
		)
		local leaves = if deep then COLORS.deepLeaves else COLORS.leaves
		part(
			tree,
			"Crown",
			Enum.PartType.Ball,
			Vector3.new(crown, crown, crown),
			CFrame.new(base + Vector3.new(0, height, 0)),
			leaves,
			Enum.Material.Grass,
			DECOR
		)
		table.insert(batch, tree)
		treeCount += 1
		if #batch >= 150 then
			flush()
		end
	end
	flush()
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
