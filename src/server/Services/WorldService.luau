--!strict
-- Builds Emberfall Ridge (GDD "World") at server start: carves a valley through the eastern
-- mountains, floors it with basalt and lava cracks, dresses it with rocks and ash trees, and
-- opens the camp boundary toward it. Built from code so the place file needs no hand edits.
--
-- Layout, along +X from the camp gate (the boundary ring at r ≈ 260):
--   x 160–250  the east trail: tutorial imps and the Ashling (inside the ring, on grass)
--   x 270–370  the ridge mouth: Ember Imps
--   x 370–480  the ash fields: Cinder Casters and imps
--   x 480–560  the cinder steps
--   x 560–640  the Golem's caldera

local WorldService = {}

WorldService.GATE_X = 262
WorldService.CALDERA = Vector3.new(600, 0, 0)
WorldService.FLOOR_Y = -1

-- Valley path: centre points and widths (radius of the carved round section).
local PATH = {
	{ x = 250, z = 0, r = 46 },
	{ x = 290, z = 0, r = 62 },
	{ x = 340, z = 18, r = 80 },
	{ x = 400, z = 10, r = 90 },
	{ x = 460, z = -14, r = 88 },
	{ x = 515, z = -6, r = 74 },
	{ x = 560, z = 0, r = 66 },
	{ x = 600, z = 0, r = 74 },
}

local ROCK = Color3.fromRGB(74, 62, 58)
local ROCK_DARK = Color3.fromRGB(52, 44, 42)
local ASH = Color3.fromRGB(150, 140, 132)
local EMBER = Color3.fromRGB(255, 120, 50)

local function part(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.Shape = shape or Enum.PartType.Block
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function carve(terrain: Terrain)
	for i, point in PATH do
		local centre = Vector3.new(point.x, 0, point.z)
		-- Air: a tall cylinder per point, plus a joint to the next so the valley is continuous.
		terrain:FillCylinder(CFrame.new(centre + Vector3.new(0, 90, 0)), 190, point.r, Enum.Material.Air)
		local nextPoint = PATH[i + 1]
		if nextPoint then
			local other = Vector3.new(nextPoint.x, 0, nextPoint.z)
			local mid = (centre + other) / 2
			local length = (other - centre).Magnitude
			local width = math.min(point.r, nextPoint.r) * 1.6
			terrain:FillBlock(
				CFrame.lookAt(mid + Vector3.new(0, 90, 0), other + Vector3.new(0, 90, 0)),
				Vector3.new(width, 190, length),
				Enum.Material.Air
			)
		end
	end
	-- Floor: basalt, slightly below the camp grass so the gate reads as a threshold.
	for i, point in PATH do
		local centre = Vector3.new(point.x, WorldService.FLOOR_Y - 6, point.z)
		terrain:FillCylinder(
			CFrame.new(centre),
			12,
			point.r + 6,
			if i == 1 then Enum.Material.Ground else Enum.Material.Basalt
		)
		local nextPoint = PATH[i + 1]
		if nextPoint then
			local other = Vector3.new(nextPoint.x, WorldService.FLOOR_Y - 6, nextPoint.z)
			local mid = (centre + other) / 2
			terrain:FillBlock(
				CFrame.lookAt(mid, other),
				Vector3.new(math.min(point.r, nextPoint.r) * 1.8, 12, (other - centre).Magnitude),
				Enum.Material.Basalt
			)
		end
	end
	-- Lava cracks: thin glowing seams in the floor, away from the main lanes.
	local rng = Random.new(7)
	for _ = 1, 26 do
		local t = rng:NextNumber(0.15, 1)
		local i = math.clamp(math.floor(t * (#PATH - 1)) + 1, 1, #PATH - 1)
		local a, b = PATH[i], PATH[i + 1]
		local f = rng:NextNumber()
		local x = a.x + (b.x - a.x) * f
		local z = a.z + (b.z - a.z) * f + rng:NextNumber(-0.7, 0.7) * a.r
		local cf = CFrame.new(x, WorldService.FLOOR_Y - 0.5, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		terrain:FillBlock(cf, Vector3.new(rng:NextNumber(3, 5), 2, rng:NextNumber(16, 34)), Enum.Material.CrackedLava)
	end
	-- The caldera: a raised rim of basalt round the boss floor.
	local c = WorldService.CALDERA
	for k = 0, 11 do
		local angle = k / 12 * math.pi * 2
		if math.abs(math.cos(angle) + 1) > 0.25 then -- leave the west side open: that's the way in
			local pos = c + Vector3.new(math.cos(angle) * 70, 4, math.sin(angle) * 70)
			terrain:FillBall(pos, 14, Enum.Material.Basalt)
		end
	end
	terrain:FillCylinder(
		CFrame.new(c + Vector3.new(0, WorldService.FLOOR_Y - 0.4, 0)),
		1.4,
		9,
		Enum.Material.CrackedLava
	)
end

local function rock(folder: Instance, pos: Vector3, scale: number, rng: Random)
	local cf = CFrame.new(pos)
		* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3))
	part(folder, Vector3.new(6, 4, 5) * scale, cf * CFrame.new(0, 1.2 * scale, 0), ROCK, Enum.Material.Slate)
	part(
		folder,
		Vector3.new(3.5, 3, 3) * scale,
		cf * CFrame.new(1.6 * scale, 3.6 * scale, 0.4 * scale) * CFrame.Angles(0, 0.6, 0.2),
		ROCK_DARK,
		Enum.Material.Slate
	)
end

local function ashTree(folder: Instance, pos: Vector3, rng: Random)
	local h = rng:NextNumber(9, 14)
	local lean = CFrame.Angles(rng:NextNumber(-0.12, 0.12), rng:NextNumber(0, 6.28), rng:NextNumber(-0.12, 0.12))
	local base = CFrame.new(pos) * lean
	part(
		folder,
		Vector3.new(1.6, h, 1.6),
		base * CFrame.new(0, h / 2, 0),
		Color3.fromRGB(46, 38, 36),
		Enum.Material.Wood
	)
	part(
		folder,
		Vector3.new(1, 5, 1),
		base * CFrame.new(1.6, h * 0.65, 0) * CFrame.Angles(0, 0, -0.8),
		Color3.fromRGB(46, 38, 36),
		Enum.Material.Wood
	)
	-- A sparse grey canopy with a few ember leaves.
	part(
		folder,
		Vector3.new(6, 3, 6),
		base * CFrame.new(0, h + 1, 0) * CFrame.Angles(0, 0.4, 0),
		ASH,
		Enum.Material.Slate
	)
	part(
		folder,
		Vector3.new(4, 2.4, 4),
		base * CFrame.new(2.4, h - 0.6, 1) * CFrame.Angles(0, 1.1, 0),
		ASH,
		Enum.Material.Slate
	)
	if rng:NextNumber() < 0.5 then
		local leaf =
			part(folder, Vector3.new(1.4, 1.4, 1.4), base * CFrame.new(-1.8, h + 0.2, -1.4), EMBER, Enum.Material.Neon)
		leaf.CanCollide = false
	end
end

local function emberVent(folder: Instance, pos: Vector3)
	local vent =
		part(folder, Vector3.new(3, 1, 3), CFrame.new(pos + Vector3.new(0, 0.3, 0)), ROCK_DARK, Enum.Material.Basalt)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 170, 80), Color3.fromRGB(255, 80, 30))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.35, 0)
	emitter.Lifetime = NumberRange.new(2, 3.5)
	emitter.Speed = NumberRange.new(3, 6)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.Rate = 6
	emitter.Parent = vent
	local light = Instance.new("PointLight")
	light.Color = EMBER
	light.Range = 14
	light.Brightness = 1.4
	light.Parent = vent
end

local function dress(folder: Instance)
	local rng = Random.new(11)
	for i = 2, #PATH do
		local a = PATH[i]
		for _ = 1, 7 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local dist = a.r * rng:NextNumber(0.6, 0.92)
			local pos = Vector3.new(a.x + math.cos(angle) * dist, WorldService.FLOOR_Y, a.z + math.sin(angle) * dist)
			if rng:NextNumber() < 0.55 then
				rock(folder, pos, rng:NextNumber(0.8, 1.8), rng)
			else
				ashTree(folder, pos, rng)
			end
		end
		for _ = 1, 2 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local dist = a.r * rng:NextNumber(0.3, 0.6)
			emberVent(
				folder,
				Vector3.new(a.x + math.cos(angle) * dist, WorldService.FLOOR_Y, a.z + math.sin(angle) * dist)
			)
		end
	end
	-- The gate: two basalt pillars and a hanging ember lantern at the boundary.
	for _, z in { -24, 24 } do
		part(folder, Vector3.new(5, 22, 5), CFrame.new(WorldService.GATE_X, 10, z), ROCK, Enum.Material.Slate)
		part(folder, Vector3.new(6.4, 2, 6.4), CFrame.new(WorldService.GATE_X, 21.6, z), ROCK_DARK, Enum.Material.Slate)
	end
	part(folder, Vector3.new(3, 2, 52), CFrame.new(WorldService.GATE_X, 23, 0), ROCK_DARK, Enum.Material.Slate)
	local lantern =
		part(folder, Vector3.new(2, 2.4, 2), CFrame.new(WorldService.GATE_X, 19.6, 0), EMBER, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = EMBER
	light.Range = 30
	light.Parent = lantern
	-- A sign facing camp.
	local board = part(
		folder,
		Vector3.new(0.6, 4, 12),
		CFrame.new(WorldService.GATE_X - 4, 5, -34),
		Color3.fromRGB(120, 84, 56),
		Enum.Material.Wood
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Left
	gui.PixelsPerStud = 30
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "EMBERFALL RIDGE\nLv 1–15"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(255, 220, 180)
	label.Parent = gui
	gui.Parent = board
end

local function openBoundary()
	local map = workspace:FindFirstChild("Map")
	local boundary = map and map:FindFirstChild("Boundary")
	if boundary == nil then
		return
	end
	for _, wall in boundary:GetChildren() do
		if wall:IsA("BasePart") then
			local angle = math.deg(math.atan2(wall.Position.Z, wall.Position.X))
			if math.abs(angle) < 15 then
				wall:Destroy()
			end
		end
	end
end

function WorldService.Init()
	openBoundary()
end

function WorldService.Start()
	local folder = Instance.new("Folder")
	folder.Name = "Emberfall"
	workspace.Terrain:SetMaterialColor(Enum.Material.Basalt, Color3.fromRGB(70, 56, 52))
	carve(workspace.Terrain)
	dress(folder)
	folder.Parent = workspace
end

return WorldService
