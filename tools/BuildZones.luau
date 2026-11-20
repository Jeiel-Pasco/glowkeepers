--!nocheck
-- Rebuilds the world round the camp for GDD v2 (run once in Studio Edit, then save the place):
--   1. Flattens the mountain ring and lays open meadow out to the world edge.
--   2. Thins the camp forest (a sixth of the trees, none near the zone roads), makes the kept
--      trees taller, and moves the rest out to a tree wall at the world edge.
--   3. Opens the camp ring toward each zone and builds an invisible wall at the world edge.
--   4. Builds the three element zones from Shared.Zones: Emberfall Ridge (Fire), Mistfall Basin
--      (Water) and Elderwood (Leaf): floors, landmarks, a gate and a sign each.
-- Safe to run again: it clears what it built last time (Map.Zones, Map.WorldEdge) first.
-- Run: copy to src/server/_tmp/, then in the command bar
--   loadstring(game.ServerScriptService.Server._tmp.BuildZones.Source)()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Zones = require(ReplicatedStorage.Shared.Zones)

local terrain = workspace.Terrain
local map = workspace.Map
local FLOOR = Zones.FLOOR_Y
local M = Enum.Material

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

-- 1. Flatten -----------------------------------------------------------------------------------

for x = -660, 660, 330 do
	for z = -660, 660, 330 do
		terrain:FillBlock(CFrame.new(x, 2 + 220, z), Vector3.new(332, 440, 332), M.Air)
		task.wait()
	end
end
for x = -800, 800, 80 do
	for z = -800, 800, 80 do
		if math.sqrt(x * x + z * z) > 320 then
			terrain:FillBlock(CFrame.new(x, FLOOR + 200, z), Vector3.new(80, 400, 80), M.Air) -- mountain stubs
			terrain:FillBlock(CFrame.new(x, FLOOR - 3, z), Vector3.new(80, 6, 80), M.Grass)
		end
	end
	task.wait()
end

-- 2. Forest ------------------------------------------------------------------------------------

local function nearRoad(pos)
	local r = Vector2.new(pos.X, pos.Z).Magnitude
	if r < 150 then
		return false
	end
	local a = math.atan2(pos.Z, pos.X)
	for _, zone in Zones.list do
		local diff = math.abs((a - zone.angle + math.pi) % (2 * math.pi) - math.pi)
		if diff * r < 34 then
			return true
		end
	end
	return false
end

local trees = map.Forest.Trees:GetChildren()
table.sort(trees, function(a, b)
	return a:GetPivot().Position.X < b:GetPivot().Position.X
end)
local spare = {}
for i, tree in trees do
	local pos = tree:GetPivot().Position
	local r = Vector2.new(pos.X, pos.Z).Magnitude
	if tree:GetAttribute("Placed") then
		continue -- an earlier run already placed it
	end
	tree:SetAttribute("Placed", true)
	local keep = r > 165 and i % 6 == 0 and not nearRoad(pos)
	if keep then
		tree:ScaleTo(1.2)
	else
		table.insert(spare, tree)
	end
end
-- The tree wall at the world edge, from the spare trees.
local wallCount = math.min(#spare, 300)
local rng = rngFor(3)
for i = 1, #spare do
	local tree = spare[i]
	if i <= wallCount then
		local a = i / wallCount * math.pi * 2 + rng:NextNumber(-0.01, 0.01)
		local r = Zones.WORLD_R + 15 + rng:NextNumber(0, 50)
		tree:PivotTo(CFrame.new(math.cos(a) * r, FLOOR, math.sin(a) * r) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0))
		tree:ScaleTo(1.7 + rng:NextNumber(0, 0.4))
	else
		tree:Destroy()
	end
end
-- Props (bushes, rocks): half of them, none on the roads.
for i, prop in map.Forest.Props:GetChildren() do
	if prop:GetAttribute("Placed") then
		continue
	end
	prop:SetAttribute("Placed", true)
	local ok, pos = pcall(function()
		return prop:GetPivot().Position
	end)
	if not ok or i % 2 == 0 or nearRoad(pos) then
		prop:Destroy()
	end
end
for _, name in { "ForestSpawns", "DeepwoodSpawns", "ShardSpawns" } do
	local old = map.Forest:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

-- 3. Walls ---------------------------------------------------------------------------------------

for _, wall in map.Boundary:GetChildren() do
	if wall:IsA("BasePart") then
		local a = math.atan2(wall.Position.Z, wall.Position.X)
		for _, zone in Zones.list do
			local diff = math.abs((a - zone.angle + math.pi) % (2 * math.pi) - math.pi)
			if diff < Zones.GATE_HALF_ANGLE then
				wall:Destroy()
				break
			end
		end
	end
end
local old = map:FindFirstChild("WorldEdge")
if old then
	old:Destroy()
end
local edge = Instance.new("Folder")
edge.Name = "WorldEdge"
edge.Parent = map
local SEGMENTS = 64
for i = 1, SEGMENTS do
	local a = i / SEGMENTS * math.pi * 2
	local pos = Vector3.new(math.cos(a) * Zones.WORLD_R, 60, math.sin(a) * Zones.WORLD_R)
	local wall = part(
		edge,
		Vector3.new(2 * math.pi * Zones.WORLD_R / SEGMENTS + 2, 140, 2),
		CFrame.lookAt(pos, Vector3.new(0, 60, 0)),
		Color3.new(),
		M.SmoothPlastic
	)
	wall.Transparency = 1
	wall.CanQuery = false
end

-- 4. Zones -----------------------------------------------------------------------------------------

old = map:FindFirstChild("Zones")
if old then
	old:Destroy()
end
local zonesFolder = Instance.new("Folder")
zonesFolder.Name = "Zones"
zonesFolder.Parent = map
-- Last run's Emberfall (built at runtime before this tool).
local oldEmber = workspace:FindFirstChild("Emberfall")
if oldEmber then
	oldEmber:Destroy()
end

local function at(zone, d, s, y)
	local p = Zones.toWorld(zone, d, s)
	return Vector3.new(p.X, y or FLOOR, p.Z)
end

local function floor(zone, material)
	for i, point in Zones.PATH do
		local centre = at(zone, point.d, point.s, FLOOR - 3)
		terrain:FillCylinder(CFrame.new(centre), 6, point.r, material)
		local nextPoint = Zones.PATH[i + 1]
		if nextPoint then
			local other = at(zone, nextPoint.d, nextPoint.s, FLOOR - 3)
			terrain:FillBlock(
				CFrame.lookAt((centre + other) / 2, other),
				Vector3.new(math.min(point.r, nextPoint.r) * 1.6, 6, (other - centre).Magnitude),
				material
			)
		end
	end
	-- Clear anything sticking up from the meadow inside the zone.
	for _, point in Zones.PATH do
		terrain:FillCylinder(CFrame.new(at(zone, point.d, point.s, FLOOR + 40)), 80, point.r, M.Air)
	end
end

-- Scatter `count` points inside the zone, away from its enemy packs.
local function scatter(zone, seed, count, edgeBias, fn)
	local r = rngFor(seed)
	local placed = 0
	local tries = 0
	while placed < count and tries < count * 20 do
		tries += 1
		local i = r:NextInteger(2, #Zones.PATH)
		local point = Zones.PATH[i]
		local a = r:NextNumber(0, math.pi * 2)
		local dist = point.r * (edgeBias and r:NextNumber(0.65, 0.95) or r:NextNumber(0.2, 0.9))
		local d, s = point.d + math.cos(a) * dist, point.s + math.sin(a) * dist
		local clear = true
		for _, pack in Zones.PACKS do
			if math.abs(pack.d - d) < 10 and math.abs(pack.s - s) < 10 then
				clear = false
			end
		end
		if clear and d < Zones.BOSS_D - 20 or (clear and edgeBias) then
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
	floor(zone, M.Basalt)
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
	floor(zone, M.Sand)
	local pools = {
		{ d = 345, s = -58, r = 16 },
		{ d = 420, s = 66, r = 18 },
		{ d = 490, s = -60, r = 15 },
		{ d = 520, s = 58, r = 13 },
		{ d = 600, s = -52, r = 12 },
		{ d = 600, s = 52, r = 12 },
	}
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
	floor(zone, M.LeafyGrass)
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

print("[BuildZones] done")
