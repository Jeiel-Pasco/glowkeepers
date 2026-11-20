--!strict
-- Enemy rigs (docs/ART_DIRECTION.md: a few chunky parts, muted with one glowing accent).
--
-- build(kindId) returns a Model: an invisible HumanoidRootPart, a Humanoid, and a `Body`
-- part held by a Weld named BodyWeld. Every other piece is welded to Body, so a client can
-- bob, lean and squash the whole look by changing BodyWeld.C0 locally (EnemyController).

local EnemyLooks = {}

local M = Enum.Material

type Spec = { hip: number, body: Vector3 }

local function piece(
	body: BasePart,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Size = size
	p.Shape = shape or Enum.PartType.Block
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = body.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = p
	weld.Parent = p
	p.Parent = body.Parent
	return p
end

local function glow(body: BasePart, size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = piece(body, size, offset, color, M.Neon, shape)
	return p
end

local function eyes(body: BasePart, y: number, z: number, spread: number, size: number, color: Color3)
	for _, x in { -spread, spread } do
		glow(body, Vector3.new(size, size, 0.2), CFrame.new(x, y, z), color)
	end
end

local BUILDERS: { [string]: (body: BasePart) -> () } = {}

-- Ember Imp: a squat ember-red body, stubby horns, glowing eyes and a flame tuft.
BUILDERS.ember_imp = function(body)
	local horn = Color3.fromRGB(58, 40, 36)
	piece(body, Vector3.new(1.9, 0.9, 1.6), CFrame.new(0, -0.9, 0), Color3.fromRGB(120, 46, 34))
	for _, x in { -0.6, 0.6 } do
		piece(body, Vector3.new(0.45, 0.8, 0.45), CFrame.new(x, 1.15, -0.1) * CFrame.Angles(0, 0, -x * 0.7), horn)
		piece(body, Vector3.new(0.6, 0.7, 0.7), CFrame.new(x * 1.1, -1.55, 0), Color3.fromRGB(96, 36, 28))
	end
	eyes(body, 0.25, -0.86, 0.38, 0.38, Color3.fromRGB(255, 214, 120))
	glow(
		body,
		Vector3.new(0.6, 0.9, 0.6),
		CFrame.new(0, 0.3, 0.95) * CFrame.Angles(0.6, 0, 0),
		Color3.fromRGB(255, 130, 50)
	)
	glow(body, Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 1.05, 0.2), Color3.fromRGB(255, 150, 60))
end

-- Cinder Caster: a hunched robed figure with a hood and a floating ember orb.
BUILDERS.cinder_caster = function(body)
	local robe = Color3.fromRGB(64, 50, 48)
	piece(body, Vector3.new(2.6, 1.6, 2.4), CFrame.new(0, -1.5, 0), robe)
	piece(body, Vector3.new(1.8, 1.4, 1.7), CFrame.new(0, 1.05, 0.1), Color3.fromRGB(52, 40, 40))
	piece(body, Vector3.new(1.2, 0.8, 0.2), CFrame.new(0, 0.95, -0.76), Color3.fromRGB(20, 16, 16))
	eyes(body, 1.0, -0.88, 0.28, 0.24, Color3.fromRGB(255, 170, 80))
	piece(body, Vector3.new(0.3, 3.6, 0.3), CFrame.new(1.35, -0.4, -0.4), Color3.fromRGB(90, 66, 46), M.Wood)
	glow(
		body,
		Vector3.new(0.9, 0.9, 0.9),
		CFrame.new(1.35, 1.7, -0.4),
		Color3.fromRGB(255, 120, 40),
		Enum.PartType.Ball
	)
	glow(body, Vector3.new(2.62, 0.25, 2.42), CFrame.new(0, -1.9, 0), Color3.fromRGB(200, 80, 40))
end

-- Ashling: a big ash-grey brute with ember cracks, the trail's mini-boss.
BUILDERS.ashling = function(body)
	local ash = Color3.fromRGB(110, 104, 100)
	piece(body, Vector3.new(4.2, 1.8, 3.4), CFrame.new(0, -1.7, 0), Color3.fromRGB(92, 86, 84))
	for _, x in { -1, 1 } do
		piece(body, Vector3.new(1.3, 2.6, 1.3), CFrame.new(x * 2.6, -0.6, -0.3) * CFrame.Angles(0, 0, x * 0.25), ash)
		piece(body, Vector3.new(1.5, 1.2, 1.5), CFrame.new(x * 2.9, -2, -0.4), Color3.fromRGB(86, 80, 78))
		piece(
			body,
			Vector3.new(0.7, 1.6, 0.7),
			CFrame.new(x * 1.1, 2.2, 0) * CFrame.Angles(0, 0, -x * 0.5),
			Color3.fromRGB(60, 54, 52)
		)
	end
	eyes(body, 0.7, -1.62, 0.7, 0.55, Color3.fromRGB(255, 200, 100))
	glow(
		body,
		Vector3.new(0.35, 1.8, 0.2),
		CFrame.new(-0.8, -0.2, -1.62) * CFrame.Angles(0, 0, 0.4),
		Color3.fromRGB(255, 120, 40)
	)
	glow(
		body,
		Vector3.new(0.35, 1.4, 0.2),
		CFrame.new(1.0, -0.6, -1.62) * CFrame.Angles(0, 0, -0.5),
		Color3.fromRGB(255, 120, 40)
	)
end

-- Cinder Golem: a hulking basalt body with a molten core and lava seams.
BUILDERS.cinder_golem = function(body)
	local stone = Color3.fromRGB(62, 54, 52)
	local dark = Color3.fromRGB(44, 38, 38)
	local lava = Color3.fromRGB(255, 110, 40)
	piece(body, Vector3.new(6, 3, 5), CFrame.new(0, 4.4, 0.4), dark, M.Slate) -- shoulders
	piece(body, Vector3.new(3, 2.4, 3), CFrame.new(0, 6.4, -0.2), stone, M.Slate) -- head
	eyes(body, 6.5, -1.72, 0.7, 0.6, Color3.fromRGB(255, 200, 90))
	glow(body, Vector3.new(2.6, 2.6, 0.4), CFrame.new(0, 1.4, -3.6), lava, Enum.PartType.Ball)
	for _, x in { -1, 1 } do
		piece(
			body,
			Vector3.new(2.4, 6, 2.4),
			CFrame.new(x * 4.6, 1, -0.2) * CFrame.Angles(0, 0, x * 0.15),
			stone,
			M.Slate
		)
		piece(body, Vector3.new(3.2, 2.6, 3.2), CFrame.new(x * 5, -2.6, -0.4), dark, M.Slate)
		piece(body, Vector3.new(2.6, 4, 2.8), CFrame.new(x * 1.8, -5, 0), dark, M.Slate)
		glow(body, Vector3.new(0.4, 3, 0.3), CFrame.new(x * 4.6, 1.4, -1.45), lava)
	end
	glow(body, Vector3.new(0.5, 3.4, 0.3), CFrame.new(-1.6, -0.6, -3.55) * CFrame.Angles(0, 0, 0.5), lava)
	glow(body, Vector3.new(0.5, 2.6, 0.3), CFrame.new(1.8, -0.2, -3.55) * CFrame.Angles(0, 0, -0.4), lava)
end

-- Raider: a hooded scavenger with a patched cloak, a mask and a loot sack.
BUILDERS.raider = function(body)
	local cloak = Color3.fromRGB(96, 78, 60)
	piece(body, Vector3.new(2, 1.3, 1.6), CFrame.new(0, -1.25, 0), cloak, M.Fabric)
	piece(body, Vector3.new(1.6, 1.3, 1.5), CFrame.new(0, 1.0, 0.05), Color3.fromRGB(80, 64, 50), M.Fabric)
	piece(body, Vector3.new(1.1, 0.5, 0.2), CFrame.new(0, 0.75, -0.72), Color3.fromRGB(40, 36, 34))
	eyes(body, 1.05, -0.74, 0.26, 0.22, Color3.fromRGB(240, 240, 220))
	piece(
		body,
		Vector3.new(1.6, 1.6, 1.4),
		CFrame.new(0.2, 0.2, 1.3),
		Color3.fromRGB(176, 150, 110),
		M.Fabric,
		Enum.PartType.Ball
	)
	for _, x in { -0.55, 0.55 } do
		piece(body, Vector3.new(0.6, 0.8, 0.7), CFrame.new(x, -2.15, 0), Color3.fromRGB(60, 50, 42))
	end
end

local SPECS: { [string]: Spec } = {
	ember_imp = { hip = 0.9, body = Vector3.new(2, 1.8, 1.7) },
	cinder_caster = { hip = 1.3, body = Vector3.new(2.2, 2, 2) },
	ashling = { hip = 1.6, body = Vector3.new(3.8, 3, 3.2) },
	cinder_golem = { hip = 6, body = Vector3.new(5.4, 5.6, 7) },
	raider = { hip = 1.55, body = Vector3.new(1.8, 1.8, 1.4) },
}

local BODY_COLORS: { [string]: Color3 } = {
	ember_imp = Color3.fromRGB(150, 58, 40),
	cinder_caster = Color3.fromRGB(70, 56, 54),
	ashling = Color3.fromRGB(120, 114, 110),
	cinder_golem = Color3.fromRGB(70, 60, 58),
	raider = Color3.fromRGB(110, 90, 70),
}

function EnemyLooks.build(kindId: string): Model
	local spec = SPECS[kindId] or SPECS.ember_imp
	local model = Instance.new("Model")
	model.Name = kindId

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(spec.body.X, 2, spec.body.Z)
	root.Transparency = 1
	root.CanCollide = false
	root.Parent = model
	model.PrimaryPart = root

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = spec.body
	body.Color = BODY_COLORS[kindId] or Color3.new(0.5, 0.5, 0.5)
	body.Material = if kindId == "cinder_golem" then M.Slate else M.SmoothPlastic
	body.CanCollide = false
	body.Massless = true
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.CFrame = root.CFrame
	body.Parent = model
	local weld = Instance.new("Weld")
	weld.Name = "BodyWeld"
	weld.Part0 = root
	weld.Part1 = body
	weld.Parent = root

	local builder = BUILDERS[kindId]
	if builder then
		builder(body)
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = spec.hip
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	-- Collide with the world only through the root: a hidden collider the size of the body.
	root.CanCollide = true
	return model
end

return EnemyLooks
