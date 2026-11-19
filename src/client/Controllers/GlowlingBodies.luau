--!strict
-- The Glowling bodies (Design & Asset Bible §3, figures 3.1–3.2): one chibi creature per species,
-- sculpted from smooth ellipsoids. Every body shares the same face (big glossy eyes with two
-- highlights, a tiny mouth, blush) and has one signature glowing feature (a bulb tail, a candle,
-- a mushroom cap, lanterns on antlers, ...). GlowlingRenderer adds the rarity extras on top,
-- placed from the anchors a body returns.
--
-- Units: 1 = the rig height H; y = 0 is the ground under the feet; the creature faces -Z.

local Bodies = {}

export type Anchors = {
	head: Vector3, -- head centre
	top: number, -- y of the top of the head (crowns sit here)
	back: Vector3, -- middle of the back (wings and inlays)
	width: number, -- half the body width (wing and inlay spread)
}

export type Ctx = {
	model: Model,
	root: BasePart,
	H: number,
	up: number,
	glow: Color3,
	glows: { BasePart }, -- glowing parts (the renderer cycles their hue for Rainbow / Secret)
	accents: { BasePart }, -- ears, wing edges, fins: the rarity rim and glass dress these
	tint: Color3?, -- a mutation's colour (Golden, Moonlit) over the whole body
	mat: Enum.Material,
}

local V = Vector3.new
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local function rot(x: number?, y: number?, z: number?): CFrame
	return CFrame.Angles(x or 0, y or 0, z or 0)
end

local EYE = rgb(28, 22, 30)
local WHITE = rgb(255, 255, 255)
local BLUSH = rgb(255, 150, 160)
local PINK = rgb(240, 170, 172)
local NOSE = rgb(52, 36, 40)

-- Below Roblox's 0.05 minimum, a mesh scale keeps small pieces (highlights, antennae) small.
local MIN = 0.05

type Kit = {
	ctx: Ctx,
	part: (
		name: string,
		kind: string,
		size: Vector3,
		pos: Vector3,
		r: CFrame?,
		color: Color3,
		mat: Enum.Material?,
		alpha: number?
	) -> BasePart,
	ball: (name: string, size: Vector3, pos: Vector3, r: CFrame?, color: Color3) -> BasePart,
	glowBall: (name: string, size: Vector3, pos: Vector3, r: CFrame?, alpha: number?) -> BasePart,
	glass: (name: string, size: Vector3, pos: Vector3, r: CFrame?, color: Color3?) -> BasePart,
	accent: (part: BasePart) -> BasePart,
	skin: (color: Color3) -> Color3,
}

local function newKit(ctx: Ctx): Kit
	local H = ctx.H
	local k = {} :: Kit
	k.ctx = ctx

	function k.skin(color: Color3): Color3
		local tint = ctx.tint
		return if tint ~= nil then tint:Lerp(color, 0.2) else color
	end

	function k.part(
		name: string,
		kind: string,
		size: Vector3,
		pos: Vector3,
		r: CFrame?,
		color: Color3,
		mat: Enum.Material?,
		alpha: number?
	): BasePart
		local want = size * H
		local real = V(math.max(want.X, MIN), math.max(want.Y, MIN), math.max(want.Z, MIN))
		local part: BasePart
		if kind == "wedge" then
			part = Instance.new("WedgePart")
		else
			local p = Instance.new("Part")
			if kind == "cyl" then
				p.Shape = Enum.PartType.Cylinder
			end
			part = p
		end
		part.Name = name
		part.Size = real
		if kind == "ball" or (kind == "wedge" and real ~= want) then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = if kind == "ball" then Enum.MeshType.Sphere else Enum.MeshType.Wedge
			mesh.Scale = want / real
			mesh.Parent = part
		end
		part.CFrame = CFrame.new(pos.X * H, pos.Y * H + ctx.up, pos.Z * H) * (r or CFrame.identity)
		part.Color = color
		part.Material = mat or Enum.Material.SmoothPlastic
		part.Transparency = alpha or 0
		part.Anchored = false
		part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
		part.Massless = true
		part.CastShadow = false
		part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = ctx.root, part
		weld.Parent = part
		part.Parent = ctx.model
		return part
	end

	-- A body piece: the species colour (or the mutation's), in the body material.
	function k.ball(name: string, size: Vector3, pos: Vector3, r: CFrame?, color: Color3): BasePart
		return k.part(name, "ball", size, pos, r, k.skin(color), ctx.mat)
	end

	function k.glowBall(name: string, size: Vector3, pos: Vector3, r: CFrame?, alpha: number?): BasePart
		local part = k.part(name, "ball", size, pos, r, ctx.glow, Enum.Material.Neon, alpha)
		table.insert(ctx.glows, part)
		return part
	end

	function k.glass(name: string, size: Vector3, pos: Vector3, r: CFrame?, color: Color3?): BasePart
		local part = k.part(name, "ball", size, pos, r, color or ctx.glow, Enum.Material.Glass, 0.35)
		table.insert(ctx.glows, part)
		return part
	end

	function k.accent(part: BasePart): BasePart
		table.insert(ctx.accents, part)
		return part
	end

	return k
end

-- A point on an ellipsoid's front (-Z) surface, at (u, v) of its half-axes, and the normal there.
local function surface(c: Vector3, r: Vector3, u: number, v: number): (Vector3, Vector3)
	local w = math.sqrt(math.max(0.02, 1 - u * u - v * v))
	local p = V(c.X + u * r.X, c.Y + v * r.Y, c.Z - w * r.Z)
	local n = V(u / r.X, v / r.Y, -w / r.Z).Unit
	return p, n
end

local function facing(n: Vector3): CFrame
	return CFrame.lookAt(Vector3.zero, n)
end

type FaceOpts = {
	spread: number?, -- eye distance from the middle, in half-widths
	v: number?, -- eye height, in half-heights
	eye: number?, -- eye size, in half-widths
	eyeColor: Color3?,
	glowEyes: boolean?,
	snout: Color3?,
	snoutScale: number?,
	nose: Color3?,
	blush: boolean?,
	mouth: boolean?,
	beak: Color3?,
}

-- The shared Glowling face on the head ellipsoid (centre c, half-axes r).
local function face(k: Kit, c: Vector3, r: Vector3, o: FaceOpts?)
	local opts: FaceOpts = o or {}
	local spread = opts.spread or 0.4
	local ev = opts.v or -0.02
	local e = (opts.eye or 0.5) * r.X
	for _, side in { -1, 1 } do
		local p, n = surface(c, r, side * spread, ev)
		local turn = facing(n)
		local at = p - n * e * 0.1
		if opts.glowEyes then
			k.glowBall("Eye", V(e * 0.9, e * 0.7, e * 0.4), at, turn)
		else
			k.part("Eye", "ball", V(e * 0.84, e, e * 0.45), at, turn, opts.eyeColor or EYE, Enum.Material.SmoothPlastic)
			if opts.eyeColor ~= nil then
				k.part(
					"Pupil",
					"ball",
					V(e * 0.42, e * 0.6, e * 0.2),
					at + turn:VectorToWorldSpace(V(0, 0, -e * 0.2)),
					turn,
					EYE
				)
			end
		end
		k.part(
			"Shine",
			"ball",
			V(e * 0.34, e * 0.34, e * 0.14),
			at + turn:VectorToWorldSpace(V(-0.16 * e, 0.2 * e, -0.22 * e)),
			turn,
			WHITE,
			Enum.Material.Neon
		)
		k.part(
			"Shine",
			"ball",
			V(e * 0.15, e * 0.15, e * 0.08),
			at + turn:VectorToWorldSpace(V(0.14 * e, -0.2 * e, -0.21 * e)),
			turn,
			WHITE,
			Enum.Material.Neon
		)
		if opts.blush ~= false then
			local bp, bn = surface(c, r, side * (spread + 0.22), ev - 0.32)
			k.part(
				"Blush",
				"ball",
				V(e * 0.62, e * 0.34, e * 0.18),
				bp - bn * e * 0.04,
				facing(bn),
				BLUSH,
				Enum.Material.SmoothPlastic,
				0.3
			)
		end
	end
	local mouthV = ev - 0.36
	local snout = opts.snout
	if opts.beak ~= nil then
		local bp, bn = surface(c, r, 0, ev - 0.28)
		k.part(
			"Beak",
			"ball",
			V(r.X * 0.34, r.Y * 0.22, r.X * 0.4),
			bp + bn * r.X * 0.08,
			facing(bn),
			opts.beak,
			Enum.Material.SmoothPlastic
		)
		return
	end
	if snout ~= nil then
		local sp, sn = surface(c, r, 0, ev - 0.34)
		local size = V(r.X * 0.66, r.Y * 0.44, r.Z * 0.5) * (opts.snoutScale or 1)
		k.ball("Snout", size, sp + sn * size.Z * 0.12, facing(sn), snout)
		local tip = sp + sn * size.Z * 0.42 + V(0, size.Y * 0.18, 0)
		k.part(
			"Nose",
			"ball",
			V(r.X * 0.2, r.X * 0.14, r.X * 0.12),
			tip,
			facing(sn),
			opts.nose or NOSE,
			Enum.Material.SmoothPlastic
		)
		mouthV = ev - 0.5
	end
	if opts.mouth ~= false then
		local mp, mn = surface(c, r, 0, mouthV)
		local turn = facing(mn)
		for _, side in { -1, 1 } do
			k.part(
				"Mouth",
				"ball",
				V(r.X * 0.13, r.X * 0.04, r.X * 0.04),
				mp + turn:VectorToWorldSpace(V(side * r.X * 0.05, 0, (if snout ~= nil then -r.Z * 0.16 else 0))),
				turn * rot(0, 0, side * 0.5),
				NOSE,
				Enum.Material.SmoothPlastic
			)
		end
	end
end

-- Ears on a head (centre c, half-axes r).
local function ears(k: Kit, kind: string, c: Vector3, head: Vector3, color: Color3, inner: Color3?, scale: number?)
	local r = head * (scale or 1)
	c += V(0, (head.Y - r.Y) * 0.8, 0)
	for _, side in { -1, 1 } do
		if kind == "pointy" or kind == "tufted" then
			-- A wide base and a narrow dark tip read as a pointed ear.
			local at = c + V(side * r.X * 0.54, r.Y * 0.8, r.Z * 0.12)
			local tilt = rot(0, 0, -side * 0.3)
			local up = tilt:VectorToWorldSpace(V(0, 1, 0))
			k.accent(k.ball("Ear", V(r.X * 0.5, r.Y * 0.62, r.X * 0.22), at, tilt, color))
			k.accent(
				k.ball("EarTip", V(r.X * 0.24, r.Y * 0.5, r.X * 0.16), at + up * r.Y * 0.4, tilt, color:Lerp(EYE, 0.35))
			)
			k.part(
				"EarIn",
				"ball",
				V(r.X * 0.26, r.Y * 0.46, r.X * 0.1),
				at + up * r.Y * 0.06 + V(0, 0, -r.X * 0.09),
				tilt,
				inner or PINK
			)
			if kind == "tufted" then
				k.ball("Tuft", V(r.X * 0.08, r.Y * 0.36, r.X * 0.08), at + up * r.Y * 0.78, tilt, color:Lerp(EYE, 0.6))
			end
		elseif kind == "round" then
			local at = c + V(side * r.X * 0.66, r.Y * 0.72, r.Z * 0.1)
			k.accent(k.ball("Ear", V(r.X * 0.5, r.X * 0.5, r.X * 0.2), at, rot(0, 0, -side * 0.3), color))
			k.part(
				"EarIn",
				"ball",
				V(r.X * 0.32, r.X * 0.32, r.X * 0.1),
				at + V(0, 0, -r.X * 0.07),
				rot(0, 0, -side * 0.3),
				inner or PINK
			)
		elseif kind == "mouse" then
			local at = c + V(side * r.X * 0.72, r.Y * 0.66, r.Z * 0.15)
			k.accent(k.ball("Ear", V(r.X * 0.7, r.X * 0.7, r.X * 0.18), at, rot(0, side * 0.3, -side * 0.35), color))
			k.part(
				"EarIn",
				"ball",
				V(r.X * 0.46, r.X * 0.46, r.X * 0.1),
				at + V(0, 0, -r.X * 0.06),
				rot(0, side * 0.3, -side * 0.35),
				inner or PINK
			)
		elseif kind == "floppy" then
			local at = c + V(side * r.X * 0.92, r.Y * 0.28, r.Z * 0.05)
			k.accent(k.ball("Ear", V(r.X * 0.34, r.Y * 0.8, r.X * 0.3), at, rot(0, 0, side * 0.42), color))
		elseif kind == "long" then
			local at = c + V(side * r.X * 0.34, r.Y * 1.3, r.Z * 0.15)
			local tilt = rot(-0.12, 0, -side * 0.16)
			k.accent(k.ball("Ear", V(r.X * 0.38, r.Y * 1.25, r.X * 0.22), at, tilt, color))
			k.part(
				"EarIn",
				"ball",
				V(r.X * 0.22, r.Y * 0.95, r.X * 0.1),
				at + V(0, 0, -r.X * 0.08),
				tilt,
				inner or PINK
			)
		end
	end
end

-- Little round feet under a round body.
local function feet(k: Kit, x: number, z: number, color: Color3)
	for _, side in { -1, 1 } do
		k.ball("Foot", V(0.2, 0.12, 0.24), V(side * x, 0.05, z), nil, color)
	end
end

-- Overlapping puffs round a centre: a fluffy silhouette.
local function fluff(k: Kit, c: Vector3, radius: number, color: Color3, puffs: number)
	k.ball("Fluff", V(radius * 2, radius * 1.9, radius * 2), c, nil, color)
	for i = 1, puffs do
		local a = i / puffs * math.pi * 2
		if math.sin(a) < -0.55 then
			continue -- keep the face clear
		end
		local y = if i % 2 == 0 then 0.32 else -0.18
		local p = c + V(math.cos(a) * radius * 0.78, y * radius, math.sin(a) * radius * 0.78)
		k.ball("Fluff", V(radius, radius * 0.9, radius), p, nil, color:Lerp(WHITE, if i % 2 == 0 then 0.08 else 0))
	end
end

type QuadOpts = {
	body: Color3,
	belly: Color3?,
	legs: Color3?,
	hs: number?, -- head scale
	long: number?, -- body length scale
	legH: number?, -- leg length (0.26 = stubby)
	ears: string,
	inner: Color3?,
	snout: Color3?,
	snoutScale: number?,
	earScale: number?,
	tail: string?,
	eye: number?,
	eyeColor: Color3?,
	glowEyes: boolean?,
}

type Built = { anchors: Anchors, tail: Vector3, head: Vector3, r: Vector3 }

-- The four-legged chibi: a big head on a small round body, stubby legs.
local function quad(k: Kit, o: QuadOpts): Built
	local legH = o.legH or 0.24
	local lift = legH - 0.24
	local long = o.long or 1
	local hs = o.hs or 1
	local bodyC = V(0, 0.36 + lift, 0.14)
	k.ball("Body", V(0.58, 0.5, 0.7 * long), bodyC, nil, o.body)
	if o.belly ~= nil then
		k.ball("Belly", V(0.42, 0.36, 0.4), bodyC + V(0, -0.03, -0.18 * long), nil, o.belly)
	end
	local legColor = o.legs or o.body
	for _, side in { -1, 1 } do
		for _, z in { bodyC.Z - 0.22 * long, bodyC.Z + 0.22 * long } do
			k.ball("Leg", V(0.17, legH + 0.08, 0.17), V(side * 0.17, (legH + 0.08) / 2, z), nil, legColor)
			k.ball("Paw", V(0.18, 0.09, 0.2), V(side * 0.17, 0.04, z - 0.02), nil, legColor:Lerp(WHITE, 0.15))
		end
	end
	local size = V(0.8, 0.72, 0.68) * hs
	local r = size / 2
	local head = V(0, 0.78 + lift + (hs - 1) * 0.3, bodyC.Z - 0.36 * long)
	k.ball("Head", size, head, nil, o.body)
	face(
		k,
		head,
		r,
		{ snout = o.snout, snoutScale = o.snoutScale, eye = o.eye, eyeColor = o.eyeColor, glowEyes = o.glowEyes }
	)
	ears(k, o.ears, head, r, o.body, o.inner, o.earScale)
	local tail = bodyC + V(0, 0.1, 0.36 * long)
	local kind = o.tail or "nub"
	if kind == "fluffy" then
		k.ball("Tail", V(0.28, 0.3, 0.56), tail + V(0, 0.16, 0.12), rot(-0.8), o.body)
		k.ball("TailTip", V(0.22, 0.2, 0.26), tail + V(0, 0.38, 0.3), rot(-0.8), (o.belly or o.body):Lerp(WHITE, 0.4))
		tail += V(0, 0.42, 0.36)
	elseif kind == "thin" then
		for i = 1, 4 do
			local t = i / 4
			k.ball("Tail", V(0.08, 0.08, 0.14), tail + V(0, t * 0.34, 0.06 + t * 0.12), nil, o.body)
		end
		tail += V(0, 0.4, 0.2)
	else
		k.ball("Tail", V(0.18, 0.18, 0.18), tail, nil, o.body)
	end
	return {
		anchors = { head = head, top = head.Y + r.Y, back = bodyC + V(0, 0.22, 0), width = 0.3 },
		tail = tail,
		head = head,
		r = r,
	}
end

type RoundOpts = { body: Color3, belly: Color3?, feet: Color3?, size: Vector3?, eye: number?, glass: boolean? }

-- A round-bodied creature (slime, puff, chick): the body is the head.
local function round(k: Kit, o: RoundOpts): Built
	local size = o.size or V(0.86, 0.8, 0.82)
	local r = size / 2
	local c = V(0, r.Y + 0.04, 0)
	if o.glass then
		k.part("Body", "ball", size, c, nil, k.skin(o.body), Enum.Material.Glass, 0.3)
	else
		k.ball("Body", size, c, nil, o.body)
	end
	if o.belly ~= nil then
		k.ball("Belly", V(r.X * 1.2, r.Y * 1.0, r.Z * 0.6), c + V(0, -r.Y * 0.3, -r.Z * 0.62), nil, o.belly)
	end
	if o.feet ~= nil then
		feet(k, r.X * 0.45, -r.Z * 0.2, o.feet)
	end
	face(k, c, r, { eye = o.eye or 0.42, v = 0.02 })
	return {
		anchors = { head = c, top = c.Y + r.Y, back = c + V(0, r.Y * 0.6, r.Z * 0.5), width = r.X },
		tail = c + V(0, 0, r.Z),
		head = c,
		r = r,
	}
end

type BirdOpts = {
	body: Color3,
	belly: Color3,
	beak: Color3,
	legs: Color3?,
	size: number?,
	wing: Color3?,
	eyes: FaceOpts?,
}

local function bird(k: Kit, o: BirdOpts): Built
	local s = o.size or 1
	local size = V(0.78, 0.8, 0.76) * s
	local r = size / 2
	local c = V(0, r.Y + 0.1, 0)
	k.ball("Body", size, c, nil, o.body)
	k.ball("Belly", V(r.X * 1.3, r.Y * 1.2, r.Z * 0.6), c + V(0, -r.Y * 0.3, -r.Z * 0.56), nil, o.belly)
	local wing = o.wing or o.body:Lerp(EYE, 0.15)
	for _, side in { -1, 1 } do
		k.accent(
			k.ball(
				"Wing",
				V(0.1, r.Y * 0.75, r.Z * 1.25),
				c + V(side * r.X * 0.92, -r.Y * 0.22, r.Z * 0.3),
				rot(-0.45, 0, side * 0.12),
				wing
			)
		)
		k.ball("Leg", V(0.06, 0.16, 0.06), V(side * 0.12, 0.08, 0), nil, o.legs or o.beak)
		k.ball("Toe", V(0.14, 0.05, 0.18), V(side * 0.12, 0.02, -0.06), nil, o.legs or o.beak)
	end
	k.ball("TailFeather", V(0.3, 0.1, 0.3), c + V(0, -r.Y * 0.2, r.Z * 1.05), rot(0.5), wing)
	local eyes: FaceOpts = o.eyes or { eye = 0.42, v = 0.12 }
	eyes.beak = o.beak
	face(k, c, r, eyes)
	return {
		anchors = { head = c, top = c.Y + r.Y, back = c + V(0, r.Y * 0.4, r.Z * 0.6), width = r.X },
		tail = c + V(0, -r.Y * 0.1, r.Z * 1.2),
		head = c,
		r = r,
	}
end

type BugOpts = { shell: Color3, head: Color3, legs: Color3, glowShell: boolean?, glassShell: boolean?, size: number? }

local function bug(k: Kit, o: BugOpts): Built
	local s = o.size or 1
	local shellC = V(0, 0.38 * s, 0.14 * s)
	local shellSize = V(0.78, 0.6, 0.86) * s
	if o.glowShell then
		k.glowBall("Shell", shellSize, shellC)
		k.part("ShellGlass", "ball", shellSize * 1.04, shellC, nil, k.skin(o.shell), Enum.Material.Glass, 0.55)
	elseif o.glassShell then
		k.glowBall("Core", shellSize * 0.6, shellC)
		k.part("Shell", "ball", shellSize, shellC, nil, k.skin(o.shell), Enum.Material.Glass, 0.3)
	else
		k.ball("Shell", shellSize, shellC, nil, o.shell)
	end
	k.ball("Seam", V(0.03, shellSize.Y * 0.98, shellSize.Z * 0.98), shellC + V(0, 0.01, 0), nil, o.head)
	local hs = V(0.56, 0.5, 0.48) * s
	local head = V(0, 0.4 * s, -0.3 * s)
	k.ball("Head", hs, head, nil, o.head)
	face(k, head, hs / 2, { eye = 0.62, spread = 0.42, v = 0.05 })
	for _, side in { -1, 1 } do
		for i, z in { -0.12, 0.08, 0.28 } do
			k.ball(
				"Leg",
				V(0.07, 0.07, 0.28) * s,
				V(side * 0.38, 0.12, z) * s,
				rot(0, side * (i - 2) * 0.5, side * 0.6) * rot(0, math.pi / 2, 0),
				o.legs
			)
		end
		local base = head + V(side * 0.12 * s, hs.Y * 0.42, 0)
		k.ball(
			"Antenna",
			V(0.04, 0.3, 0.04) * s,
			base + V(side * 0.06, 0.13, -0.04) * s,
			rot(-0.4, 0, -side * 0.45),
			o.legs
		)
		k.ball("AntennaTip", V(0.08, 0.08, 0.08) * s, base + V(side * 0.13, 0.27, -0.1) * s, nil, o.legs)
	end
	return {
		anchors = {
			head = head,
			top = head.Y + hs.Y / 2,
			back = shellC + V(0, shellSize.Y * 0.4, 0),
			width = shellSize.X / 2,
		},
		tail = shellC + V(0, 0, shellSize.Z / 2),
		head = head,
		r = hs / 2,
	}
end

type FrogOpts = { body: Color3, belly: Color3, size: number? }

local function frog(k: Kit, o: FrogOpts): Built
	local s = o.size or 1
	local size = V(0.92, 0.58, 0.8) * s
	local r = size / 2
	local c = V(0, r.Y + 0.05, 0.05)
	k.ball("Body", size, c, nil, o.body)
	k.ball("Belly", V(r.X * 1.4, r.Y * 1.1, r.Z * 0.5), c + V(0, -r.Y * 0.25, -r.Z * 0.62), nil, o.belly)
	for _, side in { -1, 1 } do
		local bump = c + V(side * r.X * 0.48, r.Y * 0.82, -r.Z * 0.42)
		k.ball("EyeBump", V(0.28, 0.26, 0.26) * s, bump, nil, o.body)
		face(k, bump, V(0.14, 0.13, 0.13) * s, { eye = 1.15, spread = 0, v = 0.05, blush = false, mouth = false })
		k.ball("Haunch", V(0.3, 0.26, 0.42) * s, c + V(side * r.X * 0.82, -r.Y * 0.45, r.Z * 0.3), nil, o.body)
		k.ball("Hand", V(0.16, 0.08, 0.2) * s, c + V(side * r.X * 0.5, -r.Y * 0.95, -r.Z * 0.75), nil, o.body)
		k.part(
			"Blush",
			"ball",
			V(0.16, 0.08, 0.04) * s,
			c + V(side * r.X * 0.62, -r.Y * 0.05, -r.Z * 0.88),
			rot(0, side * 0.6, 0),
			BLUSH,
			Enum.Material.SmoothPlastic,
			0.3
		)
	end
	k.part("Mouth", "ball", V(0.4, 0.03, 0.04) * s, c + V(0, -r.Y * 0.18, -r.Z * 0.98), nil, NOSE)
	return {
		anchors = { head = c, top = c.Y + r.Y + 0.12 * s, back = c + V(0, r.Y * 0.7, r.Z * 0.3), width = r.X },
		tail = c + V(0, 0, r.Z),
		head = c,
		r = r,
	}
end

-- Moth wings spread wide behind the body, facing forward, each with a glowing eyespot.
local function mothWings(k: Kit, c: Vector3, fore: Color3, hind: Color3, s: number)
	for _, side in { -1, 1 } do
		local tilt = rot(0.2, -side * 0.25, -side * 0.35)
		local wing = c + V(side * 0.36 * s, 0.2 * s, 0.24)
		k.accent(k.part("Wing", "ball", V(0.56, 0.62, 0.05) * s, wing, tilt, k.skin(fore), Enum.Material.SmoothPlastic))
		k.glowBall("WingSpot", V(0.2, 0.22, 0.06) * s, wing + V(side * 0.06, 0.04, -0.02) * s, tilt, 0.05)
		k.accent(
			k.part(
				"Hindwing",
				"ball",
				V(0.36, 0.4, 0.05) * s,
				c + V(side * 0.3 * s, -0.16 * s, 0.26),
				rot(0.2, -side * 0.25, side * 0.4),
				k.skin(hind),
				Enum.Material.SmoothPlastic
			)
		)
	end
end

type Builder = (k: Kit) -> Anchors

local B: { [string]: Builder } = {}

-- Clearing (figure 3.1) ------------------------------------------------------------------------

B.glimmermouse = function(k)
	local b = round(
		k,
		{ body = rgb(238, 226, 206), belly = rgb(250, 242, 228), feet = rgb(232, 176, 168), size = V(0.84, 0.72, 0.9) }
	)
	k.ball("Patch", V(0.36, 0.3, 0.3), b.head + V(-0.24, 0.16, 0.12), nil, rgb(196, 156, 116))
	k.ball("Patch", V(0.3, 0.24, 0.3), b.head + V(0.22, 0.04, 0.26), nil, rgb(196, 156, 116))
	ears(k, "mouse", b.head + V(0, 0.02, 0), b.r, rgb(196, 156, 116))
	k.ball("Nose", V(0.07, 0.06, 0.06), b.head + V(0, -0.08, -b.r.Z - 0.01), nil, rgb(232, 140, 150))
	for _, side in { -1, 1 } do
		for _, dy in { -0.02, 0.03 } do
			k.part(
				"Whisker",
				"ball",
				V(0.18, 0.012, 0.012),
				b.head + V(side * 0.3, -0.06 + dy, -b.r.Z * 0.82),
				rot(0, side * 0.3, side * dy * 4),
				NOSE
			)
		end
	end
	-- The tail curls up and over to a lightbulb.
	local tail = b.tail
	for i = 1, 6 do
		local t = i / 6
		local p = tail + V(0.04 * t, 0.62 * math.sin(t * 1.6), 0.18 * math.sin(t * 2.6))
		k.ball("Tail", V(0.06, 0.06, 0.06), p, nil, rgb(230, 170, 160))
	end
	local bulb = tail + V(0.04, 0.72, -0.02)
	k.glowBall("Bulb", V(0.18, 0.2, 0.18), bulb)
	k.glass("BulbGlass", V(0.26, 0.3, 0.26), bulb + V(0, 0.02, 0), nil, rgb(255, 240, 200))
	k.part(
		"BulbCap",
		"cyl",
		V(0.08, 0.12, 0.12),
		bulb + V(0, -0.15, 0),
		rot(0, 0, math.pi / 2),
		rgb(150, 116, 80),
		Enum.Material.Metal
	)
	return b.anchors
end

B.puffwick = function(k)
	local cream = rgb(234, 216, 186)
	local c = V(0, 0.44, 0)
	fluff(k, c, 0.38, cream, 8)
	feet(k, 0.16, -0.08, rgb(150, 112, 82))
	face(k, c, V(0.4, 0.38, 0.4), { eye = 0.42, v = 0.02 })
	k.part("Candle", "cyl", V(0.24, 0.2, 0.2), c + V(0, 0.46, 0.02), rot(0, 0, math.pi / 2), k.skin(rgb(246, 238, 220)))
	k.part("Drip", "ball", V(0.08, 0.12, 0.06), c + V(0.08, 0.4, -0.08), nil, k.skin(rgb(246, 238, 220)))
	k.part("Wick", "cyl", V(0.06, 0.02, 0.02), c + V(0, 0.6, 0.02), rot(0, 0, math.pi / 2), NOSE)
	k.glowBall("Flame", V(0.12, 0.2, 0.12), c + V(0, 0.7, 0.02))
	k.glowBall("FlameCore", V(0.07, 0.1, 0.07), c + V(0, 0.66, 0.02), nil)
	return { head = c, top = c.Y + 0.8, back = c + V(0, 0.3, 0.2), width = 0.38 }
end

B.mothlet = function(k)
	local fur = rgb(214, 186, 142)
	local b = round(k, { body = fur, size = V(0.66, 0.68, 0.66), eye = 0.48 })
	fluff(k, b.head + V(0, -0.3, 0.02), 0.2, rgb(242, 228, 200), 6)
	feet(k, 0.12, -0.04, rgb(150, 112, 82))
	mothWings(k, b.head, rgb(222, 150, 70), rgb(196, 120, 66), 1)
	for _, side in { -1, 1 } do
		k.ball(
			"Antenna",
			V(0.1, 0.26, 0.05),
			b.head + V(side * 0.12, 0.38, -0.1),
			rot(-0.3, 0, -side * 0.35),
			rgb(120, 92, 70)
		)
	end
	return b.anchors
end

B.dewdropslime = function(k)
	local water = rgb(120, 214, 214)
	local c = V(0, 0.34, 0)
	k.part("Body", "ball", V(0.8, 0.66, 0.78), c, nil, k.skin(water), Enum.Material.Glass, 0.25)
	k.part("Upper", "ball", V(0.52, 0.5, 0.52), c + V(0, 0.28, 0.02), nil, k.skin(water), Enum.Material.Glass, 0.25)
	k.part(
		"Peak",
		"ball",
		V(0.22, 0.34, 0.22),
		c + V(0, 0.56, 0.04),
		rot(-0.15),
		k.skin(water),
		Enum.Material.Glass,
		0.25
	)
	k.part(
		"Shade",
		"ball",
		V(0.72, 0.4, 0.7),
		c + V(0, -0.08, 0),
		nil,
		k.skin(water:Lerp(EYE, 0.25)),
		Enum.Material.SmoothPlastic,
		0.45
	)
	-- The star inside.
	local star = c + V(0, 0.1, 0.06)
	k.glowBall("Star", V(0.16, 0.16, 0.1), star)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		k.glowBall("StarPoint", V(0.07, 0.15, 0.07), star + V(math.sin(a) * 0.1, math.cos(a) * 0.1, 0), rot(0, 0, -a))
	end
	face(k, c + V(0, 0.02, 0), V(0.4, 0.33, 0.39), { eye = 0.4, v = 0.1 })
	k.part(
		"Gleam",
		"ball",
		V(0.1, 0.18, 0.06),
		c + V(-0.22, 0.32, -0.2),
		rot(0, 0, 0.4),
		WHITE,
		Enum.Material.Neon,
		0.4
	)
	return { head = c, top = c.Y + 0.72, back = c + V(0, 0.3, 0.2), width = 0.4 }
end

B.lanternbug = function(k)
	return bug(k, { shell = rgb(236, 170, 90), head = rgb(110, 72, 52), legs = rgb(80, 54, 42), glassShell = true }).anchors
end

B.sparkhop = function(k)
	local b = frog(k, { body = rgb(118, 168, 92), belly = rgb(200, 220, 150) })
	for i, p in { V(-0.18, 0.16, 0.04), V(0.12, 0.2, 0.14), V(0.26, 0.12, -0.06) } do
		k.glowBall("Spark", V(0.05, 0.03, 0.26), b.head + p, rot(0, i * 0.9, 0.2))
	end
	return b.anchors
end

B.pebblepup = function(k)
	local stone = rgb(134, 136, 142)
	local b =
		quad(k, { body = stone, legs = rgb(112, 114, 120), ears = "floppy", snout = rgb(158, 160, 164), tail = "nub" })
	for i, p in { V(-0.2, 0.08, -0.05), V(0.18, 0.12, 0.1), V(0.0, 0.2, 0.2), V(-0.12, 0.26, 0.42) } do
		k.glowBall("Crack", V(0.04, 0.04, 0.22), V(0, 0.36, 0.14) + p + V(0, 0.08, 0), rot(0.3, i * 0.7, 0.2))
	end
	k.glowBall("Crack", V(0.04, 0.04, 0.16), b.head + V(0.2, 0.18, -0.18), rot(0.2, 0.5, 0.4))
	k.ball("Pebble", V(0.14, 0.1, 0.12), b.head + V(-0.16, 0.34, 0.06), nil, stone:Lerp(WHITE, 0.15))
	return b.anchors
end

B.fuzzlight = function(k)
	local c = V(0, 0.42, 0)
	fluff(k, c, 0.36, rgb(246, 226, 160), 9)
	face(k, c, V(0.38, 0.36, 0.38), { eye = 0.44 })
	feet(k, 0.14, -0.06, rgb(196, 160, 96))
	k.ball("Stalk", V(0.04, 0.24, 0.04), c + V(0, 0.44, 0), rot(0, 0, 0.2), rgb(150, 120, 70))
	k.glowBall("Orb", V(0.16, 0.16, 0.16), c + V(-0.03, 0.58, 0))
	k.glass("OrbGlass", V(0.24, 0.24, 0.24), c + V(-0.03, 0.58, 0), nil, rgb(255, 240, 190))
	return { head = c, top = c.Y + 0.66, back = c + V(0, 0.3, 0.2), width = 0.36 }
end

B.bloomkit = function(k)
	local orange = rgb(222, 128, 72)
	local b = quad(k, {
		body = orange,
		belly = rgb(250, 236, 220),
		legs = rgb(92, 60, 48),
		ears = "pointy",
		inner = rgb(250, 226, 210),
		snout = rgb(250, 236, 220),
		snoutScale = 0.75,
		earScale = 1.4,
		tail = "fluffy",
	})
	-- A lotus on the tail.
	local lotus = b.tail + V(0, 0.02, 0)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		k.accent(
			k.part(
				"Petal",
				"ball",
				V(0.1, 0.24, 0.06),
				lotus + V(math.sin(a) * 0.1, 0.06, math.cos(a) * 0.1),
				rot(0, a, 0) * rot(-0.5),
				k.skin(rgb(242, 178, 196)),
				Enum.Material.SmoothPlastic
			)
		)
	end
	k.glowBall("Bloom", V(0.12, 0.1, 0.12), lotus + V(0, 0.06, 0))
	return b.anchors
end

B.snailspark = function(k)
	local skin = rgb(236, 200, 160)
	k.ball("Foot", V(0.42, 0.24, 1.0), V(0, 0.12, 0.08), nil, skin)
	local head = V(0, 0.44, -0.34)
	k.ball("Neck", V(0.32, 0.4, 0.3), V(0, 0.28, -0.34), nil, skin)
	k.ball("Head", V(0.42, 0.38, 0.36), head, nil, skin)
	face(k, head, V(0.21, 0.19, 0.18), { eye = 0.5, spread = 0.38 })
	for _, side in { -1, 1 } do
		k.ball("Stalk", V(0.05, 0.22, 0.05), head + V(side * 0.08, 0.26, 0.02), rot(0, 0, -side * 0.3), skin)
		k.ball("StalkTip", V(0.08, 0.08, 0.08), head + V(side * 0.12, 0.37, 0.02), nil, skin)
	end
	-- A spiral shell of shrinking whorls, with crystals growing out of it.
	local shell = rgb(150, 160, 170)
	local centre = V(0, 0.54, 0.24)
	for i = 0, 3 do
		local a = i * 1.4
		local s = 0.62 - i * 0.12
		k.ball(
			"Whorl",
			V(0.36, s, s),
			centre + V(0, math.sin(a) * 0.06 * i, math.cos(a) * 0.05 * i),
			nil,
			shell:Lerp(WHITE, i * 0.08)
		)
	end
	for i, p in { V(-0.06, 0.34, 0.18), V(0.08, 0.38, 0.28), V(0.0, 0.32, 0.04), V(-0.08, 0.24, 0.4) } do
		k.glowBall(
			"Crystal",
			V(0.1, 0.28 - i * 0.03, 0.1),
			centre + p - V(0, 0.08, 0),
			rot(-0.3 + i * 0.2, 0, (i - 2.5) * 0.3),
			0.15
		)
	end
	return { head = head, top = head.Y + 0.2, back = centre + V(0, 0.3, 0), width = 0.18 }
end

B.cinderchick = function(k)
	local b = bird(k, { body = rgb(214, 102, 62), belly = rgb(240, 170, 104), beak = rgb(240, 186, 70), size = 0.92 })
	for i, x in { -0.08, 0.02, 0.1 } do
		k.glowBall("Flame", V(0.1, 0.24 - i * 0.03, 0.1), b.head + V(x, b.r.Y + 0.06, 0.02), rot(0, 0, -x * 4))
	end
	return b.anchors
end

B.moonbun = function(k)
	local lilac = rgb(168, 160, 214)
	local b =
		quad(k, { body = lilac, belly = rgb(214, 210, 240), ears = "long", inner = rgb(232, 196, 222), tail = "nub" })
	for _, side in { -1, 1 } do
		local tip = b.head + V(side * b.r.X * 0.4, b.r.Y * 2.05, b.r.Z * 0.15)
		k.glowBall("Moon", V(0.06, 0.18, 0.06), tip + V(side * 0.03, 0, 0), rot(0, 0, side * 0.6))
		k.glowBall("Moon", V(0.06, 0.12, 0.06), tip + V(-side * 0.04, 0.05, 0), rot(0, 0, -side * 0.8))
	end
	for _, p in { V(-0.2, 0.5, 0.2), V(0.18, 0.46, 0.34), V(0.05, 0.6, 0.08) } do
		k.glowBall("Star", V(0.05, 0.05, 0.05), p)
	end
	return b.anchors
end

B.acornimp = function(k)
	local b = round(
		k,
		{ body = rgb(184, 128, 80), belly = rgb(220, 178, 128), feet = rgb(120, 84, 56), size = V(0.74, 0.8, 0.72) }
	)
	local cap = b.head + V(0, b.r.Y * 0.62, 0)
	k.ball("Cap", V(0.86, 0.36, 0.84), cap, nil, rgb(112, 80, 56))
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		k.ball(
			"CapBump",
			V(0.12, 0.08, 0.12),
			cap + V(math.sin(a) * 0.3, 0.06, math.cos(a) * 0.3),
			nil,
			rgb(132, 96, 66)
		)
	end
	k.ball("Stem", V(0.06, 0.16, 0.06), cap + V(0, 0.22, 0), rot(0, 0, 0.3), rgb(96, 70, 50))
	k.glowBall("StemGlow", V(0.1, 0.1, 0.1), cap + V(0.03, 0.31, 0))
	return { head = b.head, top = cap.Y + 0.3, back = b.anchors.back, width = b.anchors.width }
end

B.fireflypip = function(k)
	local b = bug(k, { shell = rgb(70, 64, 92), head = rgb(90, 82, 114), legs = rgb(52, 46, 66), size = 0.9 })
	k.glowBall("Abdomen", V(0.42, 0.38, 0.42), b.tail + V(0, -0.02, 0.06))
	for _, side in { -1, 1 } do
		k.accent(
			k.part(
				"Wing",
				"ball",
				V(0.04, 0.22, 0.5),
				b.anchors.back + V(side * 0.22, 0.12, 0.08),
				rot(0.2, side * 0.2, -side * 0.7),
				rgb(220, 230, 255),
				Enum.Material.Glass,
				0.45
			)
		)
	end
	return b.anchors
end

B.sproutling = function(k)
	local b = round(
		k,
		{ body = rgb(132, 180, 102), belly = rgb(196, 222, 160), feet = rgb(96, 136, 76), size = V(0.78, 0.72, 0.76) }
	)
	local top = b.head + V(0, b.r.Y, 0)
	k.ball("Stem", V(0.05, 0.2, 0.05), top + V(0, 0.08, 0), nil, rgb(96, 136, 76))
	for _, side in { -1, 1 } do
		k.accent(
			k.ball("Leaf", V(0.3, 0.06, 0.16), top + V(side * 0.16, 0.18, 0), rot(0, 0, side * 0.4), rgb(110, 170, 86))
		)
	end
	k.glowBall("Bud", V(0.12, 0.14, 0.12), top + V(0, 0.22, 0))
	return { head = b.head, top = top.Y + 0.3, back = b.anchors.back, width = b.anchors.width }
end

B.mushpup = function(k)
	local tan = rgb(206, 170, 130)
	local b = quad(k, {
		body = tan,
		belly = rgb(240, 222, 196),
		ears = "floppy",
		snout = rgb(240, 222, 196),
		tail = "nub",
		legs = rgb(190, 152, 114),
	})
	k.ball("Spot", V(0.26, 0.24, 0.2), b.head + V(0.22, 0.12, -0.18), nil, rgb(150, 104, 72))
	k.ball("Spot", V(0.26, 0.2, 0.3), V(-0.18, 0.5, 0.26), nil, rgb(150, 104, 72))
	-- The mushroom cap with glowing spots.
	local cap = b.head + V(0, b.r.Y * 0.9, 0.02)
	k.ball("Stalk", V(0.22, 0.2, 0.22), cap + V(0, -0.02, 0), nil, rgb(232, 224, 210))
	local capC, capR = cap + V(0, 0.14, 0), V(0.52, 0.32, 0.48)
	k.ball("Cap", capR * 2, capC, nil, rgb(110, 150, 170))
	k.ball("Gills", V(0.9, 0.08, 0.84), capC + V(0, -0.1, 0), nil, rgb(214, 220, 222))
	-- Glowing spots on the dome: a ring and a crown.
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2 + 0.3
		local e = if i % 2 == 0 then 0.55 else 0.95
		local n = V(math.cos(e) * math.sin(a), math.sin(e), math.cos(e) * math.cos(a))
		local p = capC + V(n.X * capR.X, n.Y * capR.Y, n.Z * capR.Z)
		k.glowBall("CapSpot", V(0.12, 0.12, 0.05), p, CFrame.lookAt(Vector3.zero, n))
	end
	k.glowBall("CapSpot", V(0.13, 0.05, 0.13), capC + V(0, capR.Y * 0.98, 0))
	return { head = b.head, top = cap.Y + 0.48, back = b.anchors.back, width = b.anchors.width }
end

-- Deepwood (figure 3.2) ------------------------------------------------------------------------

B.wispfox = function(k)
	local spirit = rgb(150, 220, 210)
	local b = quad(k, {
		body = spirit,
		belly = rgb(214, 244, 236),
		ears = "pointy",
		inner = rgb(190, 240, 230),
		snout = rgb(214, 244, 236),
		snoutScale = 0.8,
		earScale = 1.35,
		hs = 0.9,
		legH = 0.34,
		tail = "nub",
		eyeColor = rgb(250, 220, 120),
	})
	-- A smoky tail: wisps that rise and fade.
	for i = 1, 7 do
		local t = i / 7
		local size = 0.34 - t * 0.2
		k.glowBall(
			"Wisp",
			V(size, size, size),
			b.tail + V(math.sin(t * 5) * 0.1, t * 0.5, 0.05 + t * 0.2),
			nil,
			0.25 + t * 0.45
		)
	end
	return b.anchors
end

B.owlumen = function(k)
	local brown = rgb(96, 76, 66)
	local b = bird(k, {
		body = brown,
		belly = rgb(170, 146, 120),
		beak = rgb(220, 170, 80),
		size = 1.05,
		eyes = { eye = 0.56, spread = 0.36, v = 0.14, eyeColor = rgb(250, 196, 70), blush = false },
	})
	k.ball(
		"FaceDisc",
		V(b.r.X * 1.5, b.r.Y * 0.9, 0.08),
		b.head + V(0, b.r.Y * 0.12, -b.r.Z * 0.8),
		nil,
		rgb(200, 178, 150)
	)
	for _, side in { -1, 1 } do
		k.ball(
			"EarTuft",
			V(0.12, 0.3, 0.1),
			b.head + V(side * b.r.X * 0.62, b.r.Y * 0.95, 0),
			rot(0, 0, -side * 0.35),
			brown
		)
		-- A little lantern hanging from each wing.
		local lantern = b.head + V(side * (b.r.X + 0.18), -0.12, -0.08)
		k.part("Handle", "ball", V(0.03, 0.16, 0.03), lantern + V(0, 0.16, 0), nil, rgb(60, 48, 40))
		k.glowBall("Lantern", V(0.13, 0.17, 0.13), lantern)
		k.part(
			"LanternTop",
			"cyl",
			V(0.04, 0.17, 0.17),
			lantern + V(0, 0.1, 0),
			rot(0, 0, math.pi / 2),
			rgb(70, 56, 46),
			Enum.Material.Metal
		)
	end
	for _, p in { V(-0.12, -0.12, -0.38), V(0.08, -0.2, -0.38), V(0.16, -0.04, -0.36), V(-0.02, -0.3, -0.35) } do
		k.glowBall("StarDot", V(0.04, 0.04, 0.04), b.head + p)
	end
	return b.anchors
end

B.lumoth = function(k)
	local fur = rgb(196, 190, 226)
	local b = round(k, { body = fur, size = V(0.6, 0.64, 0.6), eye = 0.5 })
	fluff(k, b.head + V(0, -0.28, 0.04), 0.2, rgb(236, 232, 250), 6)
	feet(k, 0.1, -0.02, rgb(130, 120, 170))
	mothWings(k, b.head, rgb(150, 140, 206), rgb(126, 116, 186), 1.3)
	for _, side in { -1, 1 } do
		k.ball(
			"Antenna",
			V(0.14, 0.32, 0.05),
			b.head + V(side * 0.12, 0.38, -0.08),
			rot(-0.3, 0, -side * 0.35),
			rgb(236, 232, 250)
		)
	end
	return b.anchors
end

B.fawnfire = function(k)
	local fawn = rgb(196, 130, 86)
	local b = quad(k, {
		body = fawn,
		belly = rgb(244, 224, 200),
		legs = rgb(170, 110, 72),
		legH = 0.42,
		ears = "pointy",
		inner = rgb(244, 210, 196),
		snout = rgb(244, 224, 200),
		tail = "nub",
	})
	for _, p in { V(-0.16, 0.66, 0.08), V(0.12, 0.7, 0.2), V(-0.06, 0.68, 0.34), V(0.18, 0.64, 0.0) } do
		k.ball("Dapple", V(0.08, 0.04, 0.08), p, nil, rgb(250, 236, 220))
	end
	for _, side in { -1, 1 } do
		k.ball(
			"Antler",
			V(0.06, 0.16, 0.06),
			b.head + V(side * 0.14, b.r.Y + 0.04, 0.04),
			rot(0, 0, -side * 0.3),
			rgb(230, 210, 180)
		)
	end
	k.glowBall("TailFlame", V(0.14, 0.22, 0.14), b.tail + V(0, 0.08, 0.02), rot(-0.4))
	k.glowBall("TailFlame", V(0.08, 0.14, 0.08), b.tail + V(0, 0.2, 0.06), rot(-0.4), 0.2)
	return b.anchors
end

B.mossbear = function(k)
	local fur = rgb(128, 94, 70)
	local b = quad(k, {
		body = fur,
		belly = rgb(196, 160, 120),
		ears = "round",
		inner = rgb(196, 160, 120),
		snout = rgb(206, 176, 140),
		long = 1.15,
		tail = "nub",
	})
	local back = b.anchors.back
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		k.ball(
			"Moss",
			V(0.22, 0.12, 0.22),
			back + V(math.sin(a) * 0.16, 0.02, math.cos(a) * 0.2),
			nil,
			rgb(100, 150, 80)
		)
	end
	k.ball("Moss", V(0.32, 0.12, 0.42), back + V(0, 0.03, 0), nil, rgb(112, 160, 88))
	for i, p in { V(-0.1, 0.1, -0.06), V(0.1, 0.12, 0.12) } do
		k.ball("ShroomStem", V(0.04, 0.1, 0.04), back + p, nil, rgb(232, 224, 210))
		k.glowBall("ShroomCap", V(0.12 - i * 0.02, 0.06, 0.12 - i * 0.02), back + p + V(0, 0.06, 0))
	end
	k.ball("Moss", V(0.22, 0.08, 0.18), b.head + V(0.1, b.r.Y * 0.9, 0.04), nil, rgb(100, 150, 80))
	return { head = b.head, top = b.anchors.top, back = back + V(0, 0.1, 0), width = b.anchors.width }
end

B.otterglow = function(k)
	local brown = rgb(140, 98, 70)
	-- Sits up, holding a glowing pebble.
	local body = V(0, 0.36, 0.06)
	k.ball("Body", V(0.56, 0.7, 0.5), body, nil, brown)
	k.ball("Belly", V(0.4, 0.5, 0.2), body + V(0, -0.02, -0.18), nil, rgb(232, 206, 170))
	local head = V(0, 0.82, -0.02)
	local r = V(0.32, 0.28, 0.28)
	k.ball("Head", r * 2, head, nil, brown)
	face(k, head, r, { snout = rgb(232, 206, 170), eye = 0.46 })
	ears(k, "round", head + V(0, -0.06, 0), r * 0.8, brown, rgb(232, 206, 170))
	feet(k, 0.14, -0.1, rgb(110, 76, 56))
	for _, side in { -1, 1 } do
		k.ball("Arm", V(0.12, 0.2, 0.12), body + V(side * 0.14, 0.06, -0.24), rot(0.6, 0, side * 0.3), brown)
	end
	k.glowBall("Pebble", V(0.18, 0.14, 0.14), body + V(0, 0.02, -0.34))
	k.ball("Tail", V(0.16, 0.1, 0.42), V(0, 0.06, 0.42), rot(0.2), brown)
	return { head = head, top = head.Y + r.Y, back = body + V(0, 0.2, 0.2), width = 0.28 }
end

B.embercat = function(k)
	local coal = rgb(70, 64, 70)
	local b = quad(k, {
		body = coal,
		belly = rgb(110, 100, 104),
		ears = "pointy",
		inner = rgb(200, 110, 80),
		earScale = 1.3,
		legH = 0.3,
		tail = "thin",
		eyeColor = rgb(250, 170, 70),
	})
	for i, p in { V(-0.18, 0.56, 0.04), V(0.18, 0.56, 0.14), V(0, 0.62, 0.3), V(-0.16, 0.54, 0.38) } do
		k.glowBall("Ember", V(0.05, 0.04, 0.2), p, rot(0, i * 0.4, 0.3))
	end
	k.glowBall("TailFlame", V(0.14, 0.24, 0.14), b.tail + V(0, 0.08, 0))
	k.glowBall("TailFlame", V(0.07, 0.14, 0.07), b.tail + V(0, 0.22, 0), nil, 0.2)
	return b.anchors
end

B.shadebat = function(k)
	local dark = rgb(70, 60, 88)
	local b = round(k, { body = dark, belly = rgb(110, 98, 132), size = V(0.66, 0.66, 0.6), eye = 0.46 })
	ears(k, "pointy", b.head + V(0, 0.02, 0), b.r * V(1.3, 1.1, 1), dark, rgb(170, 120, 170))
	feet(k, 0.1, 0, rgb(50, 42, 62))
	for _, side in { -1, 1 } do
		-- Stained-glass wing membranes on finger bones.
		local shoulder = b.head + V(side * 0.3, 0.06, 0.1)
		for i, a in { 0.5, 0.95, 1.4 } do
			k.ball(
				"Finger",
				V(0.04, 0.04, 0.62 - i * 0.08),
				shoulder + V(side * 0.26, 0.06 + (2 - i) * 0.12, 0.04),
				rot(0, side * math.pi / 2, 0) * rot(-(a - 0.95) * side, 0, 0),
				dark
			)
		end
		k.accent(
			k.glass(
				"Membrane",
				V(0.03, 0.42, 0.56),
				shoulder + V(side * 0.26, 0.04, 0.06),
				rot(0, side * 0.2, side * 0.25) * rot(0, math.pi / 2, 0),
				rgb(186, 120, 220)
			)
		)
		k.part("Fang", "wedge", V(0.03, 0.05, 0.03), b.head + V(side * 0.04, -0.14, -0.31), rot(0, 0, math.pi), WHITE)
	end
	return b.anchors
end

B.prismbeetle = function(k)
	return bug(k, {
		shell = rgb(210, 220, 240),
		head = rgb(120, 118, 150),
		legs = rgb(96, 94, 124),
		glassShell = true,
		size = 1.05,
	}).anchors
end

B.thornhog = function(k)
	local spine = rgb(120, 90, 70)
	local b = round(k, {
		body = rgb(170, 130, 96),
		belly = rgb(236, 214, 182),
		feet = rgb(110, 80, 60),
		size = V(0.82, 0.68, 0.86),
		eye = 0.38,
	})
	k.ball("Snout", V(0.18, 0.14, 0.2), b.head + V(0, -0.1, -b.r.Z - 0.02), nil, rgb(236, 214, 182))
	k.part("Nose", "ball", V(0.08, 0.06, 0.06), b.head + V(0, -0.07, -b.r.Z - 0.12), nil, NOSE)
	local n = 0
	for row = 0, 3 do
		for i = -3, 3 do
			n += 1
			local a = i * 0.38 + (row % 2) * 0.19
			local up = 1.05 - row * 0.3
			local dir = V(math.sin(a) * math.cos(up), math.sin(up), math.cos(a) * math.cos(up) + 0.25).Unit
			local base = b.head + V(dir.X * b.r.X * 0.92, dir.Y * b.r.Y * 0.92 + 0.02, dir.Z * b.r.Z * 0.8 + 0.06)
			local cf = CFrame.lookAt(Vector3.zero, dir)
			if n % 4 == 0 then
				k.glowBall("Thorn", V(0.08, 0.08, 0.32), base + dir * 0.08, cf)
			else
				k.ball("Thorn", V(0.09, 0.09, 0.32), base + dir * 0.08, cf, spine)
			end
		end
	end
	return b.anchors
end

B.bramblepup = function(k)
	local b = quad(k, {
		body = rgb(104, 120, 84),
		belly = rgb(170, 180, 130),
		ears = "floppy",
		snout = rgb(170, 180, 130),
		legH = 0.3,
		tail = "nub",
		legs = rgb(86, 100, 70),
	})
	local vine = rgb(70, 82, 56)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		k.ball(
			"Vine",
			V(0.06, 0.06, 0.24),
			b.anchors.back + V(math.sin(a) * 0.18, 0.02, math.cos(a) * 0.22),
			rot(0, a + 0.8, 0.2),
			vine
		)
		k.part(
			"Thorn",
			"wedge",
			V(0.03, 0.08, 0.05),
			b.anchors.back + V(math.sin(a) * 0.2, 0.08, math.cos(a) * 0.24),
			rot(0, a, 0),
			vine
		)
	end
	for _, p in { V(-0.14, 0.08, -0.06), V(0.16, 0.06, 0.14), V(0.0, 0.1, 0.24) } do
		k.glowBall("Berry", V(0.1, 0.1, 0.1), b.anchors.back + p)
	end
	k.glowBall("Berry", V(0.08, 0.08, 0.08), b.head + V(-0.18, b.r.Y * 0.86, 0))
	k.ball("Leaf", V(0.18, 0.04, 0.1), b.head + V(-0.1, b.r.Y * 0.92, 0.02), rot(0, 0.4, 0.3), rgb(110, 160, 80))
	return b.anchors
end

B.sporetoad = function(k)
	local b = frog(k, { body = rgb(150, 120, 140), belly = rgb(214, 196, 200), size = 1.05 })
	for _, p in
		{ V(-0.24, 0.24, 0.06), V(0.2, 0.26, 0.16), V(0.0, 0.3, 0.24), V(0.3, 0.16, -0.04), V(-0.32, 0.12, 0.2) }
	do
		k.glowBall("Spore", V(0.08, 0.05, 0.08), b.head + p)
	end
	local top = b.head + V(0.06, b.r.Y + 0.02, 0.12)
	k.ball("ShroomStem", V(0.08, 0.16, 0.08), top, nil, rgb(232, 224, 210))
	k.ball("ShroomCap", V(0.28, 0.12, 0.26), top + V(0, 0.1, 0), rot(0, 0, -0.2), rgb(200, 120, 110))
	k.glowBall("CapSpot", V(0.06, 0.03, 0.06), top + V(0.04, 0.16, -0.04))
	return b.anchors
end

B.lightjelly = function(k)
	local bell = V(0, 0.82, 0)
	k.glowBall("Core", V(0.44, 0.32, 0.44), bell + V(0, -0.02, 0), nil, 0.25)
	k.part("Bell", "ball", V(0.78, 0.6, 0.78), bell, nil, k.skin(rgb(150, 200, 230)), Enum.Material.Glass, 0.25)
	k.part(
		"Rim",
		"ball",
		V(0.82, 0.12, 0.82),
		bell + V(0, -0.24, 0),
		nil,
		k.skin(rgb(180, 150, 220)),
		Enum.Material.Glass,
		0.3
	)
	face(k, bell + V(0, -0.06, 0), V(0.39, 0.3, 0.39), { eye = 0.4, v = 0.0 })
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2
		local base = bell + V(math.sin(a) * 0.24, -0.3, math.cos(a) * 0.24)
		for j = 1, 4 do
			local p = base + V(math.sin(j * 1.3 + i) * 0.04, -j * 0.12, 0)
			if j == 4 then
				k.glowBall("Tentacle", V(0.06, 0.12, 0.06), p, nil, 0.1)
			else
				k.part(
					"Tentacle",
					"ball",
					V(0.07, 0.16, 0.07),
					p,
					nil,
					k.skin(rgb(170, 160, 226)),
					Enum.Material.Glass,
					0.3
				)
			end
		end
	end
	return { head = bell, top = bell.Y + 0.3, back = bell + V(0, 0.1, 0.2), width = 0.38 }
end

B.rootling = function(k)
	local bark = rgb(132, 98, 70)
	local c = V(0, 0.42, 0)
	k.part("Trunk", "cyl", V(0.6, 0.62, 0.62), c, rot(0, 0, math.pi / 2), k.skin(bark), k.ctx.mat)
	k.ball("Top", V(0.62, 0.2, 0.62), c + V(0, 0.3, 0), nil, rgb(150, 116, 84))
	k.ball("Ring", V(0.4, 0.06, 0.4), c + V(0, 0.38, 0), nil, rgb(190, 156, 116))
	face(k, c + V(0, 0.02, 0), V(0.32, 0.3, 0.32), { eye = 0.5 })
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2 + 0.3
		k.ball(
			"Root",
			V(0.12, 0.1, 0.3),
			V(math.sin(a) * 0.3, 0.06, math.cos(a) * 0.3),
			rot(0, a, 0),
			bark:Lerp(EYE, 0.15)
		)
	end
	for _, p in { V(-0.12, 0.42, 0.06), V(0.14, 0.44, -0.06), V(0.0, 0.46, 0.14) } do
		k.ball("Moss", V(0.16, 0.08, 0.16), c + p, nil, rgb(110, 160, 86))
	end
	k.glowBall("Bud", V(0.1, 0.12, 0.1), c + V(0.04, 0.54, 0))
	k.ball("Sprout", V(0.18, 0.04, 0.08), c + V(-0.06, 0.52, 0), rot(0, 0, 0.4), rgb(110, 170, 86))
	return { head = c, top = c.Y + 0.56, back = c + V(0, 0.3, 0.2), width = 0.32 }
end

B.lumingale = function(k)
	local b = bird(k, { body = rgb(120, 136, 180), belly = rgb(214, 220, 240), beak = rgb(230, 200, 120), size = 0.9 })
	k.ball("Crest", V(0.06, 0.18, 0.14), b.head + V(0, b.r.Y + 0.04, 0.04), rot(-0.4), rgb(120, 136, 180))
	for i = -1, 1 do
		local p = b.tail + V(i * 0.1, 0.06 + math.abs(i) * -0.04, 0.12)
		k.ball("Plume", V(0.06, 0.04, 0.34), p, rot(0.4, i * 0.3, 0), rgb(140, 156, 200))
		k.glowBall("StarTip", V(0.1, 0.1, 0.1), p + V(i * 0.06, 0.08, 0.16))
	end
	return b.anchors
end

B.antlerlight = function(k)
	local hide = rgb(140, 166, 150)
	local b = quad(k, {
		body = hide,
		belly = rgb(214, 226, 214),
		legs = rgb(110, 132, 120),
		legH = 0.48,
		ears = "pointy",
		inner = rgb(214, 226, 214),
		snout = rgb(214, 226, 214),
		tail = "nub",
		hs = 0.92,
	})
	local bone = rgb(226, 220, 200)
	for _, side in { -1, 1 } do
		local base = b.head + V(side * 0.14, b.r.Y * 0.9, 0.04)
		k.ball("Antler", V(0.06, 0.4, 0.06), base + V(side * 0.08, 0.18, 0), rot(0, 0, -side * 0.4), bone)
		local fork = base + V(side * 0.18, 0.36, 0)
		k.ball("Antler", V(0.05, 0.3, 0.05), fork + V(side * 0.1, 0.1, 0), rot(0, 0, -side * 0.9), bone)
		k.ball("Antler", V(0.05, 0.28, 0.05), fork + V(0, 0.16, 0.02), rot(0.2, 0, side * 0.1), bone)
		for _, tip in { fork + V(side * 0.22, 0.12, 0), fork + V(side * 0.02, 0.28, 0.02) } do
			k.part("String", "ball", V(0.015, 0.1, 0.015), tip + V(0, -0.06, 0), nil, rgb(60, 50, 40))
			k.glowBall("Lantern", V(0.08, 0.1, 0.08), tip + V(0, -0.14, 0))
		end
	end
	return { head = b.head, top = b.anchors.top + 0.5, back = b.anchors.back, width = b.anchors.width }
end

B.cometferret = function(k)
	local navy = rgb(80, 86, 128)
	local b = quad(k, {
		body = navy,
		belly = rgb(236, 228, 214),
		legs = rgb(60, 64, 100),
		long = 1.4,
		ears = "round",
		inner = rgb(236, 228, 214),
		snout = rgb(236, 228, 214),
		tail = "nub",
		hs = 0.86,
	})
	k.ball("Mask", V(0.5, 0.14, 0.1), b.head + V(0, 0.04, -b.r.Z * 0.9), nil, rgb(236, 228, 214))
	-- The comet tail: a bright head that trails off into sparks.
	for i = 0, 5 do
		local t = i / 5
		k.glowBall(
			"Comet",
			V(0.22 - t * 0.14, 0.22 - t * 0.14, 0.26 - t * 0.14),
			b.tail + V(math.sin(t * 3) * 0.06, t * 0.22, 0.06 + t * 0.4),
			nil,
			t * 0.6
		)
	end
	return b.anchors
end

B.gloomraven = function(k)
	local b = bird(k, {
		body = rgb(56, 52, 70),
		belly = rgb(84, 78, 104),
		beak = rgb(90, 86, 100),
		legs = rgb(60, 56, 70),
		size = 1.05,
		eyes = { glowEyes = true, eye = 0.44, spread = 0.4, v = 0.12, blush = false },
	})
	for i = 0, 2 do
		k.ball(
			"Crest",
			V(0.05, 0.2 - i * 0.03, 0.12),
			b.head + V(0, b.r.Y + 0.02, 0.04 + i * 0.07),
			rot(-0.6 - i * 0.2),
			rgb(56, 52, 70)
		)
	end
	for _, side in { -1, 1 } do
		k.glowBall(
			"WingRune",
			V(0.03, 0.14, 0.14),
			b.head + V(side * (b.r.X + 0.07), -0.02, 0.06),
			rot(0, 0, side * 0.2)
		)
	end
	return b.anchors
end

B.glowwormwyrm = function(k)
	local hide = rgb(132, 150, 176)
	local n = 6
	for i = n, 1, -1 do
		local t = (i - 1) / (n - 1)
		local s = 0.5 - t * 0.24
		local p = V(math.sin(t * 4) * 0.26, s / 2 + 0.02, -0.2 + t * 1.3)
		k.ball("Segment", V(s, s, s * 1.05), p, nil, hide:Lerp(WHITE, (i % 2) * 0.08))
		k.glowBall("Belly", V(s * 0.5, s * 0.2, s * 0.5), p + V(0, -s * 0.38, 0), nil, 0.2)
		k.glass("Crystal", V(0.08, 0.2, 0.08), p + V(0, s * 0.5, 0), rot(0, 0, (i - 3) * 0.2), rgb(170, 220, 240))
	end
	local head = V(0, 0.52, -0.36)
	local r = V(0.32, 0.3, 0.3)
	k.ball("Head", r * 2, head, nil, hide)
	face(k, head, r, { eye = 0.48 })
	for _, side in { -1, 1 } do
		k.ball(
			"Horn",
			V(0.06, 0.2, 0.06),
			head + V(side * 0.14, 0.3, 0.06),
			rot(-0.3, 0, -side * 0.3),
			rgb(226, 220, 200)
		)
	end
	return { head = head, top = head.Y + r.Y, back = V(0, 0.5, 0.2), width = 0.26 }
end

B.auroralynx = function(k)
	local teal = rgb(96, 150, 140)
	local b = quad(k, {
		body = teal,
		belly = rgb(214, 232, 222),
		legs = rgb(80, 128, 120),
		legH = 0.36,
		ears = "tufted",
		inner = rgb(214, 232, 222),
		snout = rgb(214, 232, 222),
		tail = "nub",
		eyeColor = rgb(240, 210, 110),
	})
	for _, side in { -1, 1 } do
		k.ball(
			"Cheek",
			V(0.2, 0.22, 0.2),
			b.head + V(side * b.r.X * 0.92, -b.r.Y * 0.4, 0),
			rot(0, 0, side * 0.5),
			rgb(214, 232, 222)
		)
	end
	-- Aurora ribbons streaming from the mane.
	for i = 0, 3 do
		local x = (i - 1.5) * 0.08
		k.glass(
			"Aurora",
			V(0.05, 0.42, 0.26),
			b.head + V(x, b.r.Y * 0.6 + 0.12, 0.3 + i * 0.04),
			rot(-0.8, 0, x * 2),
			if i % 2 == 0 then rgb(130, 230, 190) else rgb(170, 140, 230)
		)
	end
	return b.anchors
end

B.skywhalecalf = function(k)
	local navy = rgb(70, 92, 140)
	local c = V(0, 0.5, 0.1)
	k.ball("Body", V(0.9, 0.78, 1.4), c, nil, navy)
	k.ball("Belly", V(0.74, 0.5, 1.2), c + V(0, -0.18, -0.04), nil, rgb(214, 226, 240))
	local head = c + V(0, 0.04, -0.4)
	face(k, c, V(0.45, 0.39, 0.7), { eye = 0.34, spread = 0.5, v = 0.08 })
	for _, side in { -1, 1 } do
		k.accent(
			k.ball(
				"Flipper",
				V(0.36, 0.06, 0.2),
				c + V(side * 0.48, -0.16, -0.16),
				rot(0, side * 0.4, side * 0.5),
				navy
			)
		)
		k.accent(
			k.ball("Fluke", V(0.42, 0.06, 0.24), c + V(side * 0.2, 0.22, 0.86), rot(0, -side * 0.6, -side * 0.3), navy)
		)
	end
	k.ball("Tail", V(0.32, 0.3, 0.5), c + V(0, 0.1, 0.66), rot(0.3), navy)
	for _, p in { V(-0.2, 0.36, -0.1), V(0.1, 0.4, 0.1), V(0.22, 0.32, 0.3), V(-0.06, 0.38, 0.36), V(0.0, 0.34, -0.26) } do
		k.glowBall("Star", V(0.06, 0.06, 0.06), c + p)
	end
	k.part("Cloud", "ball", V(0.5, 0.2, 0.4), c + V(0.3, -0.36, 0.4), nil, WHITE, Enum.Material.SmoothPlastic, 0.3)
	return { head = head, top = c.Y + 0.4, back = c + V(0, 0.36, 0.1), width = 0.44 }
end

B.eldersapling = function(k)
	local bark = rgb(120, 92, 70)
	local trunk = V(0, 0.4, 0.04)
	k.ball("Trunk", V(0.46, 0.72, 0.42), trunk, nil, bark)
	face(k, trunk + V(0, 0.08, 0), V(0.23, 0.36, 0.21), { eye = 0.66, spread = 0.38 })
	for _, side in { -1, 1 } do
		k.ball("Root", V(0.14, 0.12, 0.3), V(side * 0.16, 0.06, -0.02), rot(0, side * 0.3, 0), bark:Lerp(EYE, 0.15))
		k.ball("Branch", V(0.08, 0.3, 0.08), trunk + V(side * 0.26, 0.22, 0), rot(0, 0, -side * 0.9), bark)
	end
	-- The canopy, hung with glowing fruit.
	local canopy = trunk + V(0, 0.5, 0.04)
	k.ball("Neck", V(0.3, 0.3, 0.28), trunk + V(0, 0.34, 0.02), nil, bark)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		k.ball(
			"Leaves",
			V(0.42, 0.34, 0.42),
			canopy + V(math.sin(a) * 0.28, (i % 2) * 0.1, math.cos(a) * 0.24),
			nil,
			rgb(96, 150, 86):Lerp(rgb(130, 176, 100), (i % 3) / 3)
		)
	end
	k.ball("Leaves", V(0.6, 0.46, 0.56), canopy + V(0, 0.12, 0), nil, rgb(110, 164, 92))
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2 + 0.4
		k.glowBall(
			"Fruit",
			V(0.09, 0.1, 0.09),
			canopy + V(math.sin(a) * 0.4, -0.1 + (i % 2) * 0.12, math.cos(a) * 0.32)
		)
	end
	return { head = trunk, top = canopy.Y + 0.38, back = trunk + V(0, 0.3, 0.2), width = 0.3 }
end

B.emberwing = function(k)
	local b = bird(k, {
		body = rgb(226, 120, 56),
		belly = rgb(250, 200, 110),
		beak = rgb(250, 210, 110),
		size = 1.0,
		wing = rgb(236, 150, 60),
	})
	for i = -1, 1 do
		k.glowBall(
			"Crest",
			V(0.06, 0.22 - math.abs(i) * 0.06, 0.1),
			b.head + V(i * 0.06, b.r.Y + 0.08, 0.04 + math.abs(i) * 0.04),
			rot(-0.3, 0, -i * 0.4)
		)
	end
	for i = -2, 2 do
		local p = b.tail + V(i * 0.07, -0.04, 0.16)
		k.glowBall(
			"Plume",
			V(0.08, 0.06, 0.44 - math.abs(i) * 0.08),
			p + V(0, 0, 0.12),
			rot(0.4, i * 0.25, 0),
			0.05 + math.abs(i) * 0.12
		)
	end
	-- Raised wings that burn at the tips.
	for _, side in { -1, 1 } do
		local tilt = rot(0.3, 0, -side * 0.75)
		local base = b.head + V(side * (b.r.X + 0.12), 0.18, 0.12)
		k.accent(k.ball("BigWing", V(0.36, 0.6, 0.1), base, tilt, rgb(236, 150, 60)))
		local tip = base + tilt:VectorToWorldSpace(V(0, 0.3, 0))
		for f = -1, 1 do
			k.glowBall(
				"WingFlame",
				V(0.07, 0.24, 0.1),
				tip + V(side * 0.04, 0.06, f * 0.1),
				tilt * rot(f * 0.3, 0, 0),
				0.05
			)
		end
	end
	return b.anchors
end

B.lunadrake = function(k)
	local purple = rgb(120, 106, 176)
	local b = quad(k, {
		body = purple,
		belly = rgb(200, 190, 232),
		legs = rgb(100, 88, 150),
		long = 1.2,
		legH = 0.3,
		ears = "none",
		tail = "nub",
		snout = rgb(170, 160, 214),
		eye = 0.46,
	})
	for _, side in { -1, 1 } do
		k.ball(
			"Horn",
			V(0.08, 0.3, 0.08),
			b.head + V(side * 0.18, b.r.Y + 0.08, 0.06),
			rot(-0.5, 0, -side * 0.35),
			rgb(236, 230, 214)
		)
		k.glowBall(
			"Crescent",
			V(0.05, 0.16, 0.05),
			b.head + V(side * 0.3, b.r.Y + 0.14, 0.12),
			rot(-0.3, 0, side * 0.9)
		)
		local shoulder = b.anchors.back + V(side * 0.2, 0.06, -0.04)
		k.ball(
			"WingArm",
			V(0.05, 0.05, 0.6),
			shoulder + V(side * 0.26, 0.22, 0.04),
			rot(0, side * math.pi / 2, 0) * rot(-side * 0.5, 0, 0),
			purple
		)
		k.accent(
			k.glass(
				"Membrane",
				V(0.03, 0.42, 0.56),
				shoulder + V(side * 0.28, 0.06, 0.12),
				rot(0, side * 0.25, side * 0.35) * rot(0, math.pi / 2, 0),
				rgb(150, 120, 220)
			)
		)
	end
	for i = 1, 5 do
		local t = i / 5
		k.ball(
			"Tail",
			V(0.18 - t * 0.1, 0.18 - t * 0.1, 0.24),
			b.tail + V(math.sin(t * 3) * 0.1, -0.06 * t, t * 0.5),
			nil,
			purple
		)
	end
	k.glowBall("TailOrb", V(0.12, 0.12, 0.12), b.tail + V(math.sin(3) * 0.1, 0, 0.6))
	return b.anchors
end

-- Builds the species' body into ctx.model (welded to ctx.root); returns where extras attach.
-- An unknown species gets a Mushpup-shaped stand-in.
function Bodies.build(sp: string, ctx: Ctx): Anchors
	local k = newKit(ctx)
	local builder = B[sp] or B.mushpup
	return builder(k)
end

-- Species that float above the ground.
Bodies.FLOAT = { lightjelly = 0.25, skywhalecalf = 0.35 } :: { [string]: number }

function Bodies.has(sp: string): boolean
	return B[sp] ~= nil
end

return Bodies
