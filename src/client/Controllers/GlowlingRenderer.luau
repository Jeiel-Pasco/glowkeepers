--!strict
-- Builds Glowling models (Design & Asset Bible §2–3, D24) and animates them.
--
-- A Glowling is its species' sculpted chibi body (GlowlingBodies) on one of four rig sizes
-- (tiny / small / medium / large, from config/species.json), dressed by Shared.RarityLook for
-- its rarity: Form I–III, glow parts in its family colour, and the extras each tier adds, placed
-- from the body's anchors. Mutations: Golden (gold foil body), Rainbow (the glow cycles hue),
-- Moonlit (silver body and glow). If ReplicatedStorage.Assets.Species.<id> exists (an artist's
-- model), it replaces the sculpted body and the rarity extras go on top.
--
-- Model layout: an anchored "Body" root (the PrimaryPart) with every creature part welded to it,
-- ground pieces (halo, sigil) welded too, and an optional anchored "Orbit" root for the rune ring
-- and pearls. The pivot is the ground point under the feet; the creature faces -Z.
--
-- place(model, cframe) puts a model in the world and animates it (bob, orbit spin, hue);
-- attach(model, part, offset) welds it to a moving part instead (carried Glowlings).
-- This controller also draws the Glowling each character carries (CarrySp / CarryR / CarryM).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local RarityLook = require(Shared:WaitForChild("RarityLook"))
local GlowlingBodies = require(script.Parent:WaitForChild("GlowlingBodies"))
local economy = require(Config:WaitForChild("economy")) :: any
local speciesConfig = require(Config:WaitForChild("species")) :: any

export type Spec = {
	sp: string,
	r: number,
	m: number, -- mutation index into economy.mutations, 0 = none
	s: number, -- size roll
	light: boolean?, -- gets a PointLight (the caller enforces the per-plot cap)
	wild: boolean?, -- rarity hidden: Form I look whatever the tier
	carried: boolean?, -- no ground pieces or sky beam
	overcharged: boolean?, -- an Infuser's Overcharge (§31): a gold aura and a brighter light
}

type Live = {
	body: BasePart,
	bodyOffset: CFrame,
	orbit: BasePart?,
	orbitOffset: CFrame,
	glow: { BasePart },
	hue: boolean,
	base: CFrame?,
	phase: number,
	levitate: number,
}

local ANIMATE_RANGE = 160 -- studs from the camera
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local GlowlingRenderer = {}

local species: { [string]: any } = {}
for _, entry in speciesConfig.species do
	species[entry.id] = entry
end

local live: { [Model]: Live } = {}

local function c3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function newPart(
	model: Model,
	root: BasePart?,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	transparency: number?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Transparency = transparency or 0
	part.Anchored = root == nil
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if root ~= nil then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end
	part.Parent = model
	return part
end

local FLAT = CFrame.Angles(0, 0, math.pi / 2) -- turns a cylinder's axis from X to Y

local function sparkles(parent: BasePart, rate: number, color: Color3, size: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(1.2, 2.4)
	emitter.Speed = NumberRange.new(0.3, 0.9)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Parent = parent
	return emitter
end

-- Builds the model at the origin; place() or attach() puts it in the world.
function GlowlingRenderer.build(spec: Spec): Model
	local entry = species[spec.sp]
	local family = if entry ~= nil then entry.family else nil
	local rig = if entry ~= nil then entry.rig else "small"
	local look = RarityLook.look(if spec.wild then 1 else spec.r)
	local mutation = economy.mutations[spec.m]
	local mutationId = if mutation ~= nil then mutation.id else nil

	local H = (RarityLook.RIGS[rig] or RarityLook.RIGS.small) * look.scale * math.clamp(spec.s, 0.5, 2)
	local glowColor = c3(RarityLook.glow(family))
	local tint: Color3? = nil
	local material = Enum.Material.SmoothPlastic
	if mutationId == "Golden" then
		tint, material = c3(RarityLook.GOLD), Enum.Material.Foil
	elseif mutationId == "Moonlit" then
		tint, glowColor = c3(RarityLook.MOONLIT), c3(RarityLook.MOONLIT)
	end
	local up = look.levitate + (GlowlingBodies.FLOAT[spec.sp] or 0) * H

	local model = Instance.new("Model")
	model.Name = spec.sp
	local glow: { BasePart } = {}
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(x * H, y * H + up, z * H)
	end

	-- An invisible root every piece is welded to (the animated part).
	local body =
		newPart(model, nil, "Body", Enum.PartType.Ball, Vector3.one * 0.3 * H, at(0, 0.45, 0), glowColor, material, 1)
	body.PivotOffset = body.CFrame:Inverse() -- the model's pivot is the ground under its feet
	model.PrimaryPart = body
	local anchors: GlowlingBodies.Anchors =
		{ head = Vector3.new(0, 0.8, -0.2), top = 1.15, back = Vector3.new(0, 0.6, 0.14), width = 0.3 }
	local asset = ReplicatedStorage:FindFirstChild("Assets")
	local folder = if asset ~= nil then asset:FindFirstChild("Species") else nil
	local art = if folder ~= nil then folder:FindFirstChild(spec.sp) else nil
	if art ~= nil and art:IsA("Model") then
		-- An artist's model replaces the sculpted body; the rarity extras go on top.
		local clone = art:Clone()
		local _, extents = clone:GetBoundingBox()
		if extents.Y > 0 then
			clone:ScaleTo(clone:GetScale() * (1.1 * H) / extents.Y)
		end
		clone:PivotTo(at(0, 0.55, 0))
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = false
				d.CanCollide, d.CanTouch, d.CanQuery, d.Massless = false, false, false, true
				local weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1 = body, d
				weld.Parent = d
			end
		end
		clone.Parent = model
	else
		local accents: { BasePart } = {}
		anchors = GlowlingBodies.build(spec.sp, {
			model = model,
			root = body,
			H = H,
			up = up,
			glow = glowColor,
			glows = glow,
			accents = accents,
			tint = tint,
			mat = material,
		})
		-- Rarity on the accent zones (ears, wings, fins): a soft rim, then glass, then gold trim.
		for _, part in accents do
			if look.gold then
				part.Color, part.Material = part.Color:Lerp(c3(RarityLook.GOLD), 0.6), Enum.Material.Metal
			elseif look.glass or mutationId == "Moonlit" then
				part.Color, part.Material, part.Transparency = glowColor, Enum.Material.Glass, 0.25
				table.insert(glow, part)
			elseif look.rim then
				part.Color = part.Color:Lerp(glowColor, 0.45)
			end
		end
		if look.inlays then
			for _, side in { -1, 1 } do
				local back = anchors.back
				local stripe = newPart(
					model,
					body,
					"Inlay",
					Enum.PartType.Block,
					Vector3.new(0.05, 0.04, 0.3) * H,
					at(back.X + side * anchors.width * 0.35, back.Y + 0.01, back.Z) * CFrame.Angles(0, 0, side * 0.3),
					glowColor,
					Enum.Material.Neon
				)
				table.insert(glow, stripe)
			end
		end
	end

	local head, crownY, back = anchors.head, anchors.top, anchors.back
	if look.crown then
		for i, x in { -0.1, 0, 0.1 } do
			local tall = if i == 2 then 0.18 else 0.12
			local spike = newPart(
				model,
				body,
				"Crown",
				Enum.PartType.Block,
				Vector3.new(0.06, tall, 0.06) * H,
				at(head.X + x, crownY + 0.04 + tall / 2, head.Z),
				c3(RarityLook.GOLD),
				Enum.Material.Neon
			)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = spike
		end
		newPart(
			model,
			body,
			"CrownBand",
			Enum.PartType.Cylinder,
			Vector3.new(0.05, 0.3, 0.3) * H,
			at(head.X, crownY + 0.04, head.Z) * FLAT,
			c3(RarityLook.GOLD),
			Enum.Material.Metal
		)
	end
	for i = 1, look.wings do
		local side = if i % 2 == 1 then -1 else 1
		local pair = math.ceil(i / 2) -- 1 = main wings, 2 = the lower extra pair
		local size = if pair == 1 then Vector3.new(0.04, 0.5, 0.75) else Vector3.new(0.04, 0.35, 0.5)
		local wing = newPart(
			model,
			body,
			"Wing",
			Enum.PartType.Block,
			size * H,
			at(side * (anchors.width + 0.04 + pair * 0.04), back.Y + 0.14 - pair * 0.12, back.Z + pair * 0.06)
				* CFrame.Angles(0, side * 0.35, side * (0.45 + pair * 0.25)),
			glowColor,
			Enum.Material.Glass,
			0.35
		)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = wing
		table.insert(glow, wing)
	end
	local ground = not spec.carried
	if look.halo and ground then
		local halo = newPart(
			model,
			body,
			"Halo",
			Enum.PartType.Cylinder,
			Vector3.new(0.06, 1.5 * H, 1.5 * H),
			CFrame.new(0, 0.05, 0) * FLAT,
			glowColor,
			Enum.Material.Neon,
			0.7
		)
		table.insert(glow, halo)
	end
	if look.sigil and ground then
		local sigil = newPart(
			model,
			body,
			"Sigil",
			Enum.PartType.Cylinder,
			Vector3.new(0.04, 2.6 * H, 2.6 * H),
			CFrame.new(0, 0.03, 0) * FLAT,
			glowColor,
			Enum.Material.Neon,
			0.82
		)
		table.insert(glow, sigil)
	end

	local orbit: BasePart? = nil
	if look.runeRing or look.pearls > 0 then
		local hub = newPart(
			model,
			nil,
			"Orbit",
			Enum.PartType.Block,
			Vector3.one * 0.1,
			at(0, 0.6, 0),
			glowColor,
			Enum.Material.SmoothPlastic,
			1
		)
		orbit = hub
		if look.runeRing then
			for i = 1, 6 do
				local angle = i / 6 * 2 * math.pi
				local rune = newPart(
					model,
					hub,
					"Rune",
					Enum.PartType.Block,
					Vector3.new(0.12, 0.18, 0.03) * H,
					at(0, 0.6, 0) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -0.85 * H),
					glowColor,
					Enum.Material.Neon
				)
				table.insert(glow, rune)
			end
		end
		for i = 1, look.pearls do
			local angle = i / look.pearls * 2 * math.pi + 0.5
			newPart(
				model,
				hub,
				"Pearl",
				Enum.PartType.Ball,
				Vector3.one * 0.14 * H,
				at(0, 0.6 + 0.25 * math.sin(angle * 2), 0) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -0.62 * H),
				Color3.fromRGB(245, 240, 255),
				Enum.Material.Glass
			)
		end
	end

	local bodyAttachment = Instance.new("Attachment")
	bodyAttachment.Parent = body
	if look.motes > 0 or spec.wild then
		sparkles(body, if spec.wild then 2 else look.motes, glowColor, 0.12 * H + 0.05)
	end
	if look.starfield then
		local stars = sparkles(body, 10, Color3.new(1, 1, 1), 0.08)
		stars.Shape = Enum.ParticleEmitterShape.Sphere
		stars.Speed = NumberRange.new(0.05, 0.2)
	end
	if look.trail then
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Position, a1.Position = Vector3.new(0, 0.2 * H, 0.2 * H), Vector3.new(0, -0.2 * H, 0.2 * H)
		a0.Parent, a1.Parent = body, body
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.Lifetime = 0.5
		trail.Color = ColorSequence.new(glowColor)
		trail.Transparency = NumberSequence.new(0.4, 1)
		trail.LightEmission = 1
		trail.Parent = body
	end
	if look.skyBeam and ground then
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(0, 60, 0)
		top.Parent = body
		local beam = Instance.new("Beam")
		beam.Attachment0, beam.Attachment1 = bodyAttachment, top
		beam.Width0, beam.Width1 = 0.35 * H, 0.1 * H
		beam.Color = ColorSequence.new(glowColor)
		beam.Transparency = NumberSequence.new(0.75, 1)
		beam.LightEmission = 1
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Parent = body
	end
	if spec.overcharged then
		local aura = newPart(
			model,
			body,
			"Overcharge",
			Enum.PartType.Ball,
			Vector3.one * 1.25 * H,
			at(0, 0.6, 0),
			c3(RarityLook.GOLD),
			Enum.Material.ForceField,
			0.2
		)
		table.insert(glow, aura)
		local burst = sparkles(body, 12, c3(RarityLook.GOLD), 0.2 * H + 0.1)
		burst.Speed = NumberRange.new(1, 2.5)
	end
	if spec.light then -- Overcharge brightens a light but never adds one (8 per plot)
		local light = Instance.new("PointLight")
		light.Color = if spec.overcharged then c3(RarityLook.GOLD) else glowColor
		light.Brightness = look.light * (if spec.overcharged then 1.8 else 1)
		light.Range = 6 + 2 * H
		light.Shadows = false
		light.Parent = body
	end

	live[model] = {
		body = body,
		bodyOffset = body.CFrame,
		orbit = orbit,
		orbitOffset = if orbit ~= nil then orbit.CFrame else CFrame.identity,
		glow = glow,
		hue = look.prismatic or mutationId == "Rainbow",
		base = nil,
		phase = (RarityLook.hash(spec.sp) % 628) / 100,
		levitate = up,
	}
	model.Destroying:Connect(function()
		live[model] = nil
	end)
	return model
end

-- Puts the model with its feet at `cframe` and animates it there.
function GlowlingRenderer.place(model: Model, cframe: CFrame)
	local entry = live[model]
	model:PivotTo(cframe)
	if entry ~= nil then
		entry.base = cframe
	end
end

-- Welds the model to a moving part (no animation besides hue).
function GlowlingRenderer.attach(model: Model, part: BasePart, offset: CFrame)
	local entry = live[model]
	model:PivotTo(part.CFrame * offset)
	for _, root in { model.PrimaryPart, if entry ~= nil then entry.orbit else nil } do
		if root ~= nil then
			root.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = part, root
			weld.Parent = root
		end
	end
	if entry ~= nil then
		entry.base = nil
	end
end

local function animate()
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local eye = if camera ~= nil then camera.CFrame.Position else Vector3.zero
	for _, entry in live do
		if entry.hue then
			local color = Color3.fromHSV((now * 0.15 + entry.phase) % 1, 0.55, 1)
			for _, part in entry.glow do
				part.Color = color
			end
		end
		local base = entry.base
		if base ~= nil and (base.Position - eye).Magnitude < ANIMATE_RANGE then
			local bob = (0.08 + entry.levitate * 0.15) * math.sin(now * 2 + entry.phase)
			entry.body.CFrame = base * CFrame.new(0, bob, 0) * entry.bodyOffset
			local orbit = entry.orbit
			if orbit ~= nil then
				orbit.CFrame = base * CFrame.new(0, bob, 0) * entry.orbitOffset * CFrame.Angles(0, now * 0.9, 0)
			end
		end
	end
end

-- Carried Glowlings: one model above each carrying character's head.
local carried: { [Model]: Model } = {}

local function refreshCarry(character: Model)
	local old = carried[character]
	if old ~= nil then
		old:Destroy()
		carried[character] = nil
	end
	local sp = character:GetAttribute("CarrySp")
	local root = character:FindFirstChild("HumanoidRootPart")
	if type(sp) ~= "string" or root == nil or not root:IsA("BasePart") then
		return
	end
	local r = character:GetAttribute("CarryR")
	local m = character:GetAttribute("CarryM")
	local model = GlowlingRenderer.build({
		sp = sp,
		r = if type(r) == "number" then r else 1,
		m = if type(m) == "number" then m else 0,
		s = 0.8,
		light = true,
		carried = true,
	})
	model.Name = "Carried"
	GlowlingRenderer.attach(model, root, CFrame.new(0, 3.4, 0))
	model.Parent = character
	carried[character] = model
end

local function watchCharacter(character: Model)
	for _, name in { "CarrySp", "CarryR", "CarryM" } do
		character:GetAttributeChangedSignal(name):Connect(function()
			refreshCarry(character)
		end)
	end
	character.Destroying:Connect(function()
		carried[character] = nil
	end)
	refreshCarry(character)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character ~= nil then
		watchCharacter(player.Character)
	end
end

function GlowlingRenderer.Start()
	RunService.RenderStepped:Connect(animate)
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return GlowlingRenderer
