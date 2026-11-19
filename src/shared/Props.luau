--!strict
-- Low-poly world props (docs/ART_DIRECTION.md): homes, fences, lamp posts, stations, the
-- campfire pit and every decoration, built from a few chunky parts in Shared.Palette plus the
-- forest pack's meshes (ReplicatedStorage.WorldAssets.Forest, kept in the place file).
--
-- Props.get(name) returns a template Model (built once, cached): pivot at the bottom centre,
-- front facing -Z, at its natural size in studs. Callers clone and scale it. nil = unknown name.
-- Names: Tent, Cabin, Cottage, Treehouse, Sanctuary, FenceRope, FenceWood, FenceStone, LampPost,
-- LanternShop, WispStash, WhatsNew, Leaderboards, Campfire, and every decor item id.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(script.Parent:WaitForChild("Palette"))

local Props = {}

local M = Enum.Material
local BLOCK = Enum.PartType.Block
local WEDGE = "wedge"

type Builder = (Model) -> ()

-- Adds a part. `kind` is nil (block), "wedge", or a PartType. `cf` is relative to the origin.
local function piece(m: Model, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, kind: any?): BasePart
	local p: BasePart
	if kind == WEDGE then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		part.Shape = kind or BLOCK
		p = part
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.Plastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = m
	return p
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- A gable roof of two wedges over a box `w` wide (x) and `d` deep (z), eaves at `y`.
local function gable(m: Model, w: number, d: number, y: number, rise: number, color: Color3, material: Enum.Material)
	local half = w / 2 + 0.6
	piece(
		m,
		Vector3.new(d + 1.2, rise, half),
		at(-half / 2, y + rise / 2, 0) * CFrame.Angles(0, math.pi / 2, 0),
		color,
		material,
		WEDGE
	)
	piece(
		m,
		Vector3.new(d + 1.2, rise, half),
		at(half / 2, y + rise / 2, 0) * CFrame.Angles(0, -math.pi / 2, 0),
		color,
		material,
		WEDGE
	)
end

-- A small glowing pane (the only Neon a prop gets).
local function glow(m: Model, size: Vector3, cf: CFrame, color: Color3?)
	piece(m, size, cf, color or Palette.lantern, M.Neon)
end

-- A clone of a forest-pack mesh, `height` tall, standing on `cf`.
local function forest(m: Model, name: string, height: number, cf: CFrame, recolor: { [string]: Color3 }?): Instance?
	local root = ReplicatedStorage:FindFirstChild("WorldAssets")
	local folder = if root ~= nil then root:FindFirstChild("Forest") else nil
	local source = if folder ~= nil then folder:FindFirstChild(name) else nil
	if source == nil then
		return nil
	end
	local clone = source:Clone()
	if clone:IsA("Model") then
		local _, size = clone:GetBoundingBox()
		clone:ScaleTo(clone:GetScale() * height / size.Y)
		clone:PivotTo(cf)
	elseif clone:IsA("BasePart") then
		clone.Size = clone.Size * (height / clone.Size.Y)
		clone.CFrame = cf * CFrame.new(0, clone.Size.Y / 2, 0)
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") and recolor ~= nil and recolor[d.Name] ~= nil then
			d.Color = recolor[d.Name]
		end
	end
	if clone:IsA("BasePart") and recolor ~= nil and recolor.self ~= nil then
		clone.Color = recolor.self
	end
	clone.Parent = m
	return clone
end

local function post(m: Model, x: number, z: number, height: number, width: number?)
	local w = width or 0.6
	piece(m, Vector3.new(w, height, w), at(x, height / 2, z), Palette.bark, M.Wood)
end

local function lantern(m: Model, cf: CFrame, scale: number?)
	local s = scale or 1
	piece(m, Vector3.new(0.9, 0.2, 0.9) * s, cf * at(0, 0.6 * s, 0), Palette.bark, M.Wood)
	glow(m, Vector3.new(0.6, 0.9, 0.6) * s, cf)
	piece(m, Vector3.new(0.9, 0.2, 0.9) * s, cf * at(0, -0.55 * s, 0), Palette.bark, M.Wood)
end

local function banner(color: Color3, emblem: Color3): Builder
	return function(m)
		post(m, -1, 0, 7.5, 0.4)
		piece(m, Vector3.new(2.8, 0.3, 0.3), at(0.2, 7.2, 0), Palette.bark, M.Wood)
		piece(m, Vector3.new(2.2, 4, 0.15), at(0.3, 5, 0), color, M.Fabric)
		piece(
			m,
			Vector3.new(2.2, 0.8, 0.15),
			at(0.3, 2.6, 0) * CFrame.Angles(0, 0, 0),
			color:Lerp(Color3.new(), 0.15),
			M.Fabric
		)
		piece(m, Vector3.new(0.8, 0.8, 0.17), at(0.3, 5.2, 0) * CFrame.Angles(0, 0, math.pi / 4), emblem, M.Fabric)
	end
end

local function fenceBuilder(kind: string): Builder
	return function(m)
		if kind == "rope" then
			for _, x in { -3.7, 0, 3.7 } do
				piece(
					m,
					Vector3.new(0.45, 2.2, 0.45),
					at(x, 1.1, 0) * CFrame.Angles(0, 0, x * 0.01),
					Palette.bark,
					M.Wood
				)
			end
			piece(m, Vector3.new(7.6, 0.18, 0.18), at(0, 1.7, 0), Palette.thatch, M.Fabric)
			piece(m, Vector3.new(7.6, 0.18, 0.18), at(0, 1.0, 0), Palette.thatch, M.Fabric)
		elseif kind == "wood" then
			for _, x in { -3.7, 3.7 } do
				piece(m, Vector3.new(0.5, 3, 0.5), at(x, 1.5, 0), Palette.bark, M.Wood)
			end
			piece(m, Vector3.new(7.6, 0.3, 0.2), at(0, 2.3, -0.1), Palette.plank, M.Wood)
			piece(m, Vector3.new(7.6, 0.3, 0.2), at(0, 1.0, -0.1), Palette.plank, M.Wood)
			for x = -2.7, 2.8, 1.35 do
				piece(m, Vector3.new(0.7, 2.6, 0.15), at(x, 1.35, -0.25), Palette.plankLight, M.Wood)
			end
		else -- stone
			local shades = { Palette.stone, Palette.stoneLight, Palette.stone:Lerp(Palette.bark, 0.15) }
			for k, x in { -2.9, -0.3, 2.4 } do
				piece(m, Vector3.new(2.7, 1.3, 1.4), at(x, 0.65, 0) * CFrame.Angles(0, k * 0.05, 0), shades[k], M.Slate)
			end
			for k, x in { -1.6, 1.3 } do
				piece(
					m,
					Vector3.new(2.5, 1.0, 1.3),
					at(x, 1.75, 0) * CFrame.Angles(0, -k * 0.06, 0),
					shades[k + 1],
					M.Slate
				)
			end
			piece(m, Vector3.new(3, 0.25, 1.2), at(-1.2, 2.35, 0), Palette.leaf, M.Grass)
		end
	end
end

-- A small house body: walls, door, two lit windows, gable roof. Returns the eave height.
local function house(
	m: Model,
	w: number,
	d: number,
	h: number,
	wall: Color3,
	wallMat: Enum.Material,
	roof: Color3,
	roofMat: Enum.Material,
	base: number?
)
	local y0 = base or 0
	piece(m, Vector3.new(w, h, d), at(0, y0 + h / 2, 0), wall, wallMat)
	piece(m, Vector3.new(w * 0.22, h * 0.6, 0.3), at(0, y0 + h * 0.3, -d / 2 - 0.1), Palette.bark, M.Wood)
	for _, x in { -w * 0.3, w * 0.3 } do
		glow(m, Vector3.new(w * 0.14, h * 0.22, 0.2), at(x, y0 + h * 0.62, -d / 2 - 0.05))
	end
	gable(m, w, d, y0 + h, w * 0.42, roof, roofMat)
	return y0 + h
end

local BUILDERS: { [string]: Builder } = {
	-- Homes, by tier ---------------------------------------------------------------------------
	Tent = function(m)
		piece(
			m,
			Vector3.new(7, 4.5, 3.6),
			at(-1.8, 2.25, 0) * CFrame.Angles(0, math.pi / 2, 0),
			Palette.thatch,
			M.Fabric,
			WEDGE
		)
		piece(
			m,
			Vector3.new(7, 4.5, 3.6),
			at(1.8, 2.25, 0) * CFrame.Angles(0, -math.pi / 2, 0),
			Palette.thatch:Lerp(Palette.bark, 0.12),
			M.Fabric,
			WEDGE
		)
		piece(m, Vector3.new(1.6, 2.6, 0.2), at(0, 1.3, -3.55), Palette.bark, M.Fabric) -- the open flap
		post(m, 0, -3.8, 5.2, 0.3)
		lantern(m, at(0.8, 3.6, -4.2), 0.7)
		forest(m, "Stump_Short", 1.2, at(2.6, 0, -4.4))
	end,
	Cabin = function(m)
		house(m, 10, 8, 5.5, Palette.bark, M.Wood, Palette.roof, M.Wood)
		piece(m, Vector3.new(1.4, 4, 1.4), at(3, 7.5, 1.5), Palette.stone, M.Slate) -- chimney
		piece(m, Vector3.new(3, 1, 1.2), at(-4, 0.5, -4.8), Palette.plank, M.Wood) -- firewood
	end,
	Cottage = function(m)
		piece(m, Vector3.new(12, 4, 10), at(0, 2, 0), Palette.stone, M.Slate)
		house(m, 12, 10, 4.5, Palette.plankLight, M.Wood, Palette.thatch, M.Fabric, 4)
		piece(m, Vector3.new(5, 0.4, 3), at(0, 4.2, -6.4), Palette.thatch, M.Fabric) -- porch roof
		post(m, -2.2, -7.6, 4.2, 0.4)
		post(m, 2.2, -7.6, 4.2, 0.4)
		lantern(m, at(2.2, 3.3, -7.9), 0.8)
		forest(m, "Bush_Round", 2.4, at(-5, 0, -5.8))
		forest(m, "Bush_Wide", 2.2, at(5, 0, -5.6))
	end,
	Treehouse = function(m)
		forest(m, "Tree_Oak_Tall", 30, at(0, 0, 0))
		piece(m, Vector3.new(11, 0.8, 11), at(0, 13, 0), Palette.plank, M.Wood)
		house(m, 7, 6, 4, Palette.bark, M.Wood, Palette.roof, M.Wood, 13.4)
		for k = 0, 6 do -- a ladder
			piece(m, Vector3.new(1.6, 0.25, 0.25), at(0, 1 + k * 1.8, -5.8), Palette.plankLight, M.Wood)
		end
		post(m, -0.9, -5.8, 13, 0.3)
		post(m, 0.9, -5.8, 13, 0.3)
		lantern(m, at(4.6, 12.2, -5), 0.8)
	end,
	Sanctuary = function(m)
		forest(
			m,
			"Tree_Oak_Round",
			40,
			at(0, 0, 2),
			{ Leaves = Palette.spirit:Lerp(Palette.leaf, 0.4), Trunk = Palette.stoneLight }
		)
		piece(m, Vector3.new(18, 0.8, 18), at(0, 0.4, 0), Palette.stoneLight, M.Slate)
		house(m, 9, 7, 5, Palette.stoneLight, M.Slate, Palette.clothLilac, M.Slate, 0.8)
		for k, x in { -7, 7, -6, 6 } do -- spirit crystals round the base
			local z = if k <= 2 then -6 else 6
			piece(
				m,
				Vector3.new(1.2, 3 + k * 0.4, 1.2),
				at(x, 1.8, z) * CFrame.Angles(0.15, k, 0.1),
				Palette.spirit,
				M.Slate
			)
			glow(m, Vector3.new(0.6, 0.8, 0.6), at(x, 3.6 + k * 0.2, z) * CFrame.Angles(0.15, k, 0.1), Palette.spirit)
		end
	end,

	-- Fences (8 studs along X) and lamps ------------------------------------------------------
	FenceRope = fenceBuilder("rope"),
	FenceWood = fenceBuilder("wood"),
	FenceStone = fenceBuilder("stone"),
	LampPost = function(m)
		post(m, 0, 0, 8, 0.6)
		piece(m, Vector3.new(0.3, 0.3, 1.8), at(0, 7.6, -0.8), Palette.bark, M.Wood)
		lantern(m, at(0, 6.7, -1.5))
		piece(m, Vector3.new(1.2, 0.6, 1.2), at(0, 0.3, 0), Palette.stone, M.Slate)
	end,

	-- Stations ---------------------------------------------------------------------------------
	LanternShop = function(m)
		piece(m, Vector3.new(10, 3, 2), at(0, 1.5, -2.5), Palette.plank, M.Wood)
		piece(m, Vector3.new(10.4, 0.3, 2.4), at(0, 3.1, -2.5), Palette.plankLight, M.Wood)
		for _, x in { -4.8, 4.8 } do
			post(m, x, -3.4, 8)
			post(m, x, 3, 9)
		end
		piece(
			m,
			Vector3.new(11, 1.6, 8),
			at(0, 8.6, -0.2) * CFrame.Angles(0, math.pi, 0),
			Palette.clothEmber,
			M.Fabric,
			WEDGE
		)
		for k, x in { -3, 0, 3 } do
			lantern(m, at(x, 6.6 - (k % 2) * 0.5, -3.6), 1.1)
		end
	end,
	WispStash = function(m)
		-- A stepped mushroom house: one stem, a wide cap, a door and a window.
		piece(m, Vector3.new(4.4, 6, 4.4), at(0, 3, 0), Palette.plankLight, M.Wood)
		piece(m, Vector3.new(11, 2, 11), at(0, 7, 0), Palette.roof, M.Fabric)
		piece(m, Vector3.new(7.5, 1.6, 7.5), at(0, 8.8, 0) * CFrame.Angles(0, math.pi / 4, 0), Palette.roof, M.Fabric)
		piece(m, Vector3.new(3.5, 1.2, 3.5), at(0, 10.2, 0), Palette.roof, M.Fabric)
		for _, xz in { { -3.2, -2.5 }, { 2.6, 3 }, { 1, -4.6 } } do -- pale spots
			piece(m, Vector3.new(1.4, 0.2, 1.4), at(xz[1], 8.05, xz[2]), Palette.plankLight, M.Fabric)
		end
		piece(m, Vector3.new(2.2, 3.4, 0.4), at(0, 1.7, -2.4), Palette.bark, M.Wood)
		glow(m, Vector3.new(0.9, 0.9, 0.2), at(1.8, 4.2, -2.2), Palette.spirit)
		for k, x in { -3.6, -2.4 } do -- wisp jars
			piece(
				m,
				Vector3.new(0.9, 1.2, 0.9),
				at(x, 0.6, -3.2),
				Palette.spirit:Lerp(Color3.new(1, 1, 1), 0.3),
				M.Glass
			).Transparency =
				0.3
			glow(m, Vector3.new(0.35, 0.35, 0.35), at(x, 0.6 + k * 0.05, -3.2), Palette.spirit)
		end
	end,
	WhatsNew = function(m)
		post(m, -3.6, 0, 7.5, 0.6)
		post(m, 3.6, 0, 7.5, 0.6)
		piece(m, Vector3.new(7, 4.2, 0.4), at(0, 4.4, 0), Palette.plankLight, M.Wood)
		gable(m, 8, 1.6, 7.3, 1.2, Palette.roof, M.Wood)
		for k, x in { -2.2, 0.2, 2.1 } do
			piece(
				m,
				Vector3.new(1.4, 1.7, 0.05),
				at(x, 4.6 + (k % 2) * 0.5, -0.23) * CFrame.Angles(0, 0, (k - 2) * 0.08),
				Color3.fromRGB(226, 214, 186),
				M.Fabric
			)
		end
	end,
	Leaderboards = function(m)
		post(m, -6.6, 0, 14, 1.4)
		post(m, 6.6, 0, 14, 1.4)
		piece(m, Vector3.new(15.6, 1.2, 1.6), at(0, 13.4, 0), Palette.bark, M.Wood)
		gable(m, 15, 2, 14, 1.6, Palette.roof, M.Wood)
		lantern(m, at(-6.6, 15.1, -1), 1.1)
		lantern(m, at(6.6, 15.1, -1), 1.1)
		piece(m, Vector3.new(12, 0.6, 1.2), at(0, 2.4, 0), Palette.plank, M.Wood)
	end,
	Campfire = function(m)
		for k = 0, 9 do
			local a = k * math.pi / 5
			forest(
				m,
				"Rock_Pebble",
				1.4,
				at(math.cos(a) * 3.6, 0, math.sin(a) * 3.6) * CFrame.Angles(0, -a, 0),
				{ self = Palette.stone }
			)
		end
		for k = 0, 3 do
			local a = k * math.pi / 2
			piece(
				m,
				Vector3.new(0.9, 4, 0.9),
				CFrame.Angles(0, a, 0) * at(0, 1.6, -1) * CFrame.Angles(-0.45, 0, 0),
				Palette.bark,
				M.Wood
			)
		end
	end,

	-- Decorations ------------------------------------------------------------------------------
	string_lights = function(m)
		post(m, -3.5, 0, 5, 0.35)
		post(m, 3.5, 0, 5, 0.35)
		for k = -3, 3 do
			local x = k
			local y = 4.6 - (1 - (x / 3.5) ^ 2) * 0.9
			glow(m, Vector3.new(0.3, 0.4, 0.3), at(x, y, 0))
		end
		piece(m, Vector3.new(7, 0.08, 0.08), at(0, 4.2, 0), Palette.bark, M.Fabric)
	end,
	paper_lanterns = function(m)
		post(m, 0, 0, 5.5, 0.35)
		piece(m, Vector3.new(3.4, 0.25, 0.25), at(0, 5.2, 0), Palette.bark, M.Wood)
		for k, x in { -1.4, 0, 1.4 } do
			local c = ({ Palette.clothEmber, Palette.thatch, Palette.clothLilac })[k]
			piece(m, Vector3.new(0.9, 1.1, 0.9), at(x, 4.2 - (k % 2) * 0.3, 0), c, M.Fabric)
			glow(m, Vector3.new(0.5, 0.2, 0.5), at(x, 3.6 - (k % 2) * 0.3, 0))
		end
	end,
	glow_mushrooms = function(m)
		forest(m, "Mushrooms_Brown_Cluster", 1.8, at(0, 0, 0), { Cap = Palette.spirit })
	end,
	crystal_lamp = function(m)
		piece(m, Vector3.new(2.2, 1.4, 2.2), at(0, 0.7, 0), Palette.stone, M.Slate)
		for k, a in { 0, 2.1, 4.2 } do
			local tilt = CFrame.Angles(0.25 * math.cos(a), a, 0.25 * math.sin(a))
			piece(m, Vector3.new(0.7, 2 + k * 0.4, 0.7), at(0, 2.2, 0) * tilt * at(0.3, 0, 0), Palette.spirit, M.Slate)
		end
		glow(m, Vector3.new(0.6, 0.6, 0.6), at(0, 3.5, 0), Palette.spirit)
	end,
	banner_moss = banner(Palette.clothMoss, Palette.plankLight),
	banner_ember = banner(Palette.clothEmber, Palette.thatch),
	banner_star = banner(Palette.clothDusk, Palette.stoneLight),
	pass_moth_banner = banner(Palette.clothLilac, Palette.plankLight),
	stepping_stones = function(m)
		for k, z in { -1.2, 0, 1.2 } do
			piece(
				m,
				Vector3.new(1.2, 0.25, 1),
				at((k - 2) * 0.25, 0.12, z) * CFrame.Angles(0, k, 0),
				Palette.stoneLight,
				M.Slate
			)
		end
	end,
	moss_path = function(m)
		piece(m, Vector3.new(2, 0.15, 4), at(0, 0.07, 0), Palette.leaf:Lerp(Palette.stone, 0.4), M.Grass)
		for k, z in { -1.3, 0, 1.3 } do
			piece(m, Vector3.new(1.3, 0.22, 1), at((k - 2) * 0.2, 0.12, z), Palette.stoneLight, M.Slate)
		end
	end,
	plank_path = function(m)
		for k = 0, 4 do
			piece(
				m,
				Vector3.new(2, 0.2, 0.7),
				at(0, 0.1, -1.6 + k * 0.8) * CFrame.Angles(0, (k % 2 - 0.5) * 0.06, 0),
				Palette.plank,
				M.Wood
			)
		end
	end,
	fence_wood = fenceBuilder("wood"),
	fence_stone = fenceBuilder("stone"),
	hedge = function(m)
		forest(m, "Bush_Wide", 3, at(-1, 0, 0), { self = Palette.leafDeep })
		forest(m, "Bush_Wide", 2.8, at(1.2, 0, 0) * CFrame.Angles(0, 1.2, 0), { self = Palette.leafDeep })
	end,
	flower_bed = function(m)
		piece(m, Vector3.new(4, 0.9, 2), at(0, 0.45, 0), Palette.plank, M.Wood)
		piece(m, Vector3.new(3.6, 0.2, 1.6), at(0, 0.95, 0), Palette.bark, M.Ground)
		local petals = { Color3.fromRGB(200, 150, 160), Color3.fromRGB(214, 192, 120), Color3.fromRGB(170, 160, 200) }
		for k = 0, 5 do
			local x, z = -1.4 + k * 0.56, ((k % 2) - 0.5) * 0.7
			piece(m, Vector3.new(0.1, 0.6, 0.1), at(x, 1.3, z), Palette.leaf, M.Grass)
			piece(m, Vector3.new(0.45, 0.3, 0.45), at(x, 1.65, z), petals[k % 3 + 1], M.Fabric)
		end
	end,
	stump_seat = function(m)
		forest(m, "Stump_Short", 1.8, at(0, 0, 0))
	end,
	log_bench = function(m)
		piece(m, Vector3.new(4, 0.6, 1.2), at(0, 1.5, 0), Palette.plank, M.Wood)
		forest(m, "Stump_Short", 1.2, at(-1.4, 0, 0))
		forest(m, "Stump_Short", 1.2, at(1.4, 0, 0))
	end,
	pond = function(m)
		for k = 0, 11 do
			local a = k * math.pi / 6
			forest(
				m,
				"Rock_Pebble",
				0.9,
				at(math.cos(a) * 2.6, 0, math.sin(a) * 1.7) * CFrame.Angles(0, a, 0),
				{ self = Palette.stone }
			)
		end
		piece(
			m,
			Vector3.new(0.2, 3.4, 5.2),
			at(0, 0.15, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(86, 120, 128),
			M.Plastic,
			Enum.PartType.Cylinder
		).Transparency =
			0.15
		for k, x in { -1, 0.8 } do
			piece(
				m,
				Vector3.new(0.05, 0.8, 0.8),
				at(x, 0.27, (k - 1.5) * 0.6) * CFrame.Angles(0, 0, math.pi / 2),
				Palette.leaf,
				M.Grass,
				Enum.PartType.Cylinder
			)
		end
	end,
	little_bridge = function(m)
		for k = -2, 2 do
			local y = 1 - (k / 2.5) ^ 2 * 0.8
			piece(
				m,
				Vector3.new(0.8, 0.25, 1.8),
				at(k * 0.8, y, 0) * CFrame.Angles(0, 0, -k * 0.12),
				Palette.plank,
				M.Wood
			)
		end
		for _, z in { -0.9, 0.9 } do
			post(m, -1.8, z, 1.8, 0.2)
			post(m, 1.8, z, 1.8, 0.2)
			piece(m, Vector3.new(3.6, 0.12, 0.12), at(0, 1.75, z), Palette.thatch, M.Fabric)
		end
	end,
	glowling_statue = function(m)
		piece(m, Vector3.new(2, 1, 2), at(0, 0.5, 0), Palette.stone, M.Slate)
		piece(m, Vector3.new(1.6, 1.6, 1.4), at(0, 1.8, 0), Palette.stoneLight, M.Slate)
		piece(m, Vector3.new(1.2, 1.1, 1.1), at(0, 3.1, -0.05), Palette.stoneLight, M.Slate)
		for _, x in { -0.45, 0.45 } do
			piece(
				m,
				Vector3.new(0.2, 0.8, 0.4),
				at(x, 3.9, 0) * CFrame.Angles(0, 0, -x * 0.6),
				Palette.leaf,
				M.Grass,
				WEDGE
			)
		end
		piece(m, Vector3.new(2, 0.2, 2), at(0, 1.05, 0), Palette.leaf, M.Grass)
	end,
	owl_totem = function(m)
		for k = 0, 2 do
			local y = 1 + k * 1.8
			piece(m, Vector3.new(1.4, 1.7, 1.3), at(0, y, 0), Palette.bark:Lerp(Palette.plank, k * 0.25), M.Wood)
			for _, x in { -0.35, 0.35 } do
				piece(m, Vector3.new(0.35, 0.35, 0.1), at(x, y + 0.2, -0.68), Palette.plankLight, M.Wood)
			end
			piece(m, Vector3.new(0.25, 0.3, 0.2), at(0, y - 0.15, -0.7), Palette.thatch, M.Wood, WEDGE)
		end
		for _, x in { -0.5, 0.5 } do
			piece(m, Vector3.new(0.3, 0.7, 0.5), at(x, 5.85, 0), Palette.bark, M.Wood, WEDGE)
		end
	end,
	firefly_jar = function(m)
		forest(m, "Stump_Short", 1, at(0, 0, 0))
		piece(m, Vector3.new(1, 1.3, 1), at(0, 1.65, 0), Color3.fromRGB(200, 214, 200), M.Glass).Transparency = 0.45
		piece(m, Vector3.new(0.8, 0.2, 0.8), at(0, 2.4, 0), Palette.plankLight, M.Wood)
		for k = 0, 3 do
			glow(
				m,
				Vector3.new(0.12, 0.12, 0.12),
				at(math.cos(k * 1.7) * 0.25, 1.4 + k * 0.18, math.sin(k * 1.7) * 0.25),
				Color3.fromRGB(236, 220, 140)
			)
		end
	end,
	star_arch = function(m)
		post(m, -3, 0, 6, 0.5)
		post(m, 3, 0, 6, 0.5)
		piece(m, Vector3.new(3.4, 0.5, 0.5), at(-1.6, 6.5, 0) * CFrame.Angles(0, 0, 0.3), Palette.stoneLight, M.Wood)
		piece(m, Vector3.new(3.4, 0.5, 0.5), at(1.6, 6.5, 0) * CFrame.Angles(0, 0, -0.3), Palette.stoneLight, M.Wood)
		glow(m, Vector3.new(0.8, 0.8, 0.3), at(0, 7.4, 0) * CFrame.Angles(0, 0, math.pi / 4), Palette.lantern)
	end,
	welcome_sign = function(m)
		post(m, 0, 0, 3.6, 0.35)
		piece(m, Vector3.new(2.6, 1.3, 0.25), at(0, 3, -0.3) * CFrame.Angles(0, 0, 0.04), Palette.plankLight, M.Wood)
		piece(m, Vector3.new(1.8, 0.15, 0.27), at(0, 3, -0.3), Palette.bark, M.Wood)
	end,
	fire_bowl = function(m)
		forest(m, "Rock_Boulder", 1.6, at(0, 0, 0), { self = Palette.stone:Lerp(Palette.bark, 0.3) })
		glow(m, Vector3.new(1, 0.25, 1), at(0, 1.55, 0), Palette.clothEmber:Lerp(Palette.lantern, 0.4))
	end,
	gift_lantern_arch = function(m)
		post(m, -3, 0, 6.5, 0.55)
		post(m, 3, 0, 6.5, 0.55)
		piece(m, Vector3.new(7, 0.55, 0.6), at(0, 6.5, 0), Palette.bark, M.Wood)
		for _, x in { -1.8, 0, 1.8 } do
			lantern(m, at(x, 5.4, 0), 0.6)
		end
		forest(m, "Bush_Round", 1.4, at(-3, 6.2, 0), { self = Palette.leaf })
	end,
	pass_star_lamp = function(m)
		post(m, 0, 0, 6, 0.45)
		piece(m, Vector3.new(1.3, 0.25, 1.3), at(0, 6.1, 0), Palette.stoneLight, M.Slate)
		glow(m, Vector3.new(0.9, 0.9, 0.3), at(0, 6.8, 0) * CFrame.Angles(0, 0, math.pi / 4), Palette.lantern)
		piece(m, Vector3.new(1.2, 0.5, 1.2), at(0, 0.25, 0), Palette.stone, M.Slate)
	end,
}

local cache: { [string]: Model } = {}

function Props.get(name: string): Model?
	local cached = cache[name]
	if cached ~= nil then
		return cached
	end
	local build = BUILDERS[name]
	if build == nil then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = name
	build(m)
	m.WorldPivot = CFrame.new()
	cache[name] = m
	return m
end

function Props.has(name: string): boolean
	return BUILDERS[name] ~= nil
end

return Props
