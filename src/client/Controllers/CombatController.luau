--!strict
-- Combat on the client: input, aim, the movement half of dash and blink, and every combat
-- effect the server's Fx describes. Damage itself is the server's (CombatService).
--
--   Click (hold)   the book's basic attack toward the mouse
--   Z X C V        the book's four spells
--   Q              dodge dash (brief invulnerability)
--   1 2 3          swap the book in hand
--   R              Recall to camp (5 s, broken by damage)
--
-- Your own bolts are drawn the moment you click (the server's copy of them is skipped), so
-- shots feel instant; everything else is drawn when the server's Fx arrives.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Client = script.Parent.Parent
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Spells = require(Shared:WaitForChild("Spells")) :: any
local Element = require(Shared:WaitForChild("Element")) :: any
local NetClient = require(Client:WaitForChild("Net"):WaitForChild("NetClient"))
local StateController = require(script.Parent:WaitForChild("StateController"))

local CombatController = {}
CombatController.Cast = Signal.new() -- (slot, readyAt): a spell went on cooldown (the HUD's bar)
CombatController.Dashed = Signal.new() -- (readyAt)

CombatController.SPELL_KEYS = { Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C, Enum.KeyCode.V }
CombatController.BOOK_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }
CombatController.DASH_COOLDOWN = 2.4

local player = Players.LocalPlayer
local fxFolder: Folder
local ready: { [string]: number } = {}
local durations: { [string]: number } = {}
local mouseDown = false
local shake = 0

local function typeColor(kind: string): Color3
	local c = Element.COLOR[kind] or Element.COLOR.Neutral
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function root(): BasePart?
	local character = player.Character
	local r = character and character:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function humanoid(): Humanoid?
	local character = player.Character
	local h = character and character:FindFirstChildOfClass("Humanoid")
	return if h and h.Health > 0 then h else nil
end

local function activeBook(): any?
	local data = StateController.get()
	if data == nil then
		return nil
	end
	return data.books[data.equipped[data.active]]
end

-- Aim: where the mouse points in the world (enemies count, your own character doesn't).
local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
local function aimPoint(): Vector3
	local camera = workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local exclude: { Instance } = { fxFolder }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	aimParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 400, aimParams)
	return if hit then hit.Position else ray.Origin + ray.Direction * 400
end

-- Effects ------------------------------------------------------------------------------------

local function fxPart(size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?, transparency: number?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.Shape = shape or Enum.PartType.Block
	p.CFrame = cf
	p.Transparency = transparency or 0
	p.Parent = fxFolder
	return p
end

local function fade(p: BasePart, seconds: number, grow: Vector3?)
	local goal: { [string]: any } = { Transparency = 1 }
	if grow then
		goal.Size = grow
	end
	TweenService:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(p, seconds + 0.05)
end

local SOUNDS = {
	cast = "rbxasset://sounds/swordlunge.wav",
	hit = "rbxasset://sounds/swordslash.wav",
	boom = "rbxasset://sounds/Rocket shot.wav",
	level = "rbxasset://sounds/electronicpingshort.wav",
}
local function sound(name: string, at: Vector3?, volume: number?)
	local s = Instance.new("Sound")
	s.SoundId = SOUNDS[name] or ""
	s.Volume = volume or 0.5
	s.PlaybackSpeed = 0.9 + math.random() * 0.2
	if at then
		local holder = fxPart(Vector3.one, CFrame.new(at), Color3.new(), nil, 1)
		s.Parent = holder
		Debris:AddItem(holder, 3)
	else
		s.Parent = workspace.CurrentCamera
		Debris:AddItem(s, 3)
	end
	s:Play()
end

local function sparks(at: Vector3, color: Color3, count: number, speed: number)
	local holder = fxPart(Vector3.one * 0.2, CFrame.new(at), color, nil, 1)
	local attachment = Instance.new("Attachment")
	attachment.Parent = holder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.Lifetime = NumberRange.new(0.25, 0.5)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(count)
	Debris:AddItem(holder, 1)
end

local function addShake(amount: number, at: Vector3?)
	local r = root()
	if at and r then
		local d = (r.Position - at).Magnitude
		amount *= math.clamp(1 - d / 80, 0, 1)
	end
	shake = math.max(shake, amount)
end

local function impact(at: Vector3, color: Color3, size: number)
	local ball = fxPart(Vector3.one * size, CFrame.new(at), color, Enum.PartType.Ball, 0.1)
	fade(ball, 0.25, Vector3.one * size * 3)
	sparks(at, color, 8, 22)
end

-- A travelling bolt, drawn locally; it stops at the first thing it touches.
local boltParams = RaycastParams.new()
boltParams.FilterType = Enum.RaycastFilterType.Exclude
local function drawBolt(
	casterId: number,
	origin: Vector3,
	dir: Vector3,
	speed: number,
	range: number,
	kind: string,
	radius: number
)
	local color = typeColor(kind)
	local size = math.max(0.8, radius * 1.3)
	local ball = fxPart(Vector3.one * size, CFrame.new(origin), color, Enum.PartType.Ball)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, size * 0.3, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -size * 0.3, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color)
	trail.LightEmission = 1
	trail.Lifetime = 0.18
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Parent = ball
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 8
	light.Parent = ball
	local exclude: { Instance } = { fxFolder }
	local caster = Players:GetPlayerByUserId(casterId)
	if caster and caster.Character then
		table.insert(exclude, caster.Character)
	end
	if casterId == 0 then
		local enemies = workspace:FindFirstChild("Enemies")
		if enemies then
			table.insert(exclude, enemies)
		end
	end
	local emberfall = workspace:FindFirstChild("Emberfall")
	if emberfall then
		table.insert(exclude, emberfall)
	end
	boltParams.FilterDescendantsInstances = exclude
	local params = boltParams
	local travelled = 0
	local pos = origin
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		local step = math.min(speed * dt, range - travelled)
		local hit = workspace:Spherecast(pos, radius * 0.8, dir * step, params)
		if hit then
			connection:Disconnect()
			ball:Destroy()
			impact(hit.Position, color, size)
			return
		end
		pos += dir * step
		travelled += step
		ball.CFrame = CFrame.new(pos)
		if travelled >= range then
			connection:Disconnect()
			fade(ball, 0.1)
		end
	end)
end

local function disc(at: Vector3, radius: number, color: Color3, transparency: number): Part
	return fxPart(
		Vector3.new(0.3, radius * 2, radius * 2),
		CFrame.new(at + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		Enum.PartType.Cylinder,
		transparency
	)
end

local function blast(at: Vector3, radius: number, color: Color3)
	local ball = fxPart(Vector3.one * radius * 0.6, CFrame.new(at), color, Enum.PartType.Ball, 0.15)
	fade(ball, 0.45, Vector3.one * radius * 2.2)
	local ring = disc(at, radius * 0.4, color, 0.2)
	fade(ring, 0.5, Vector3.new(0.3, radius * 2.4, radius * 2.4))
	sparks(at + Vector3.new(0, 1, 0), color, 24, 40)
	sound("boom", at, 0.6)
	addShake(0.6, at)
end

-- A telegraph: a faint disc whose bright ring fills in over `delay`.
local function telegraph(at: Vector3, radius: number, delay: number, color: Color3)
	local base = disc(at, radius, color, 0.75)
	local fill = disc(at + Vector3.new(0, 0.05, 0), 0.5, color, 0.4)
	TweenService
		:Create(
			fill,
			TweenInfo.new(delay, Enum.EasingStyle.Linear),
			{ Size = Vector3.new(0.3, radius * 2, radius * 2) }
		)
		:Play()
	Debris:AddItem(base, delay)
	Debris:AddItem(fill, delay)
end

local function characterOf(userId: number): Model?
	local who = Players:GetPlayerByUserId(userId)
	return who and who.Character
end

local function aura(userId: number, color: Color3, seconds: number, name: string)
	local character = characterOf(userId)
	local r = character and character:FindFirstChild("HumanoidRootPart")
	if r == nil or not r:IsA("BasePart") then
		return
	end
	local old = r:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = r
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.6, 0)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 30
	emitter.Parent = attachment
	Debris:AddItem(attachment, seconds)
end

local function shieldBubble(userId: number, color: Color3, seconds: number)
	local character = characterOf(userId)
	local r = character and character:FindFirstChild("HumanoidRootPart")
	if r == nil or not r:IsA("BasePart") then
		return
	end
	local old = fxFolder:FindFirstChild(`Shield{userId}`)
	if old then
		old:Destroy()
	end
	local bubble = fxPart(Vector3.one * 7, r.CFrame, color, Enum.PartType.Ball, 0.78)
	bubble.Name = `Shield{userId}`
	bubble.Material = Enum.Material.ForceField
	local untilT = os.clock() + seconds
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if bubble.Parent == nil or os.clock() > untilT or r.Parent == nil then
			connection:Disconnect()
			bubble:Destroy()
			return
		end
		bubble.CFrame = r.CFrame
	end)
end

local function dashTrail(userId: number, color: Color3)
	local character = characterOf(userId)
	local r = character and character:FindFirstChild("HumanoidRootPart")
	if r == nil or not r:IsA("BasePart") then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1.2, 0)
	a0.Parent = r
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1.6, 0)
	a1.Parent = r
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color)
	trail.LightEmission = 0.8
	trail.Lifetime = 0.3
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Parent = r
	Debris:AddItem(trail, 0.5)
	Debris:AddItem(a0, 0.5)
	Debris:AddItem(a1, 0.5)
end

local function onFx(kind: string, ...: any)
	local a = { ... }
	if kind == "bolt" then
		if a[1] == player.UserId then
			return -- drawn already
		end
		drawBolt(a[1], Vector3.new(a[2], a[3], a[4]), Vector3.new(a[5], a[6], a[7]), a[8], a[9], a[10], a[11])
	elseif kind == "impact" then
		local at = Vector3.new(a[1], a[2], a[3])
		impact(at, typeColor(a[4]), math.max(0.8, a[5] * 1.3))
		sound("hit", at, 0.35)
	elseif kind == "burst" then
		local at = Vector3.new(a[1], a[2] - 2.5, a[3])
		local color = typeColor(a[5])
		local ring = disc(at, 1, color, 0.15)
		fade(ring, 0.35, Vector3.new(0.3, a[4] * 2, a[4] * 2))
		local ball = fxPart(Vector3.one * 3, CFrame.new(at + Vector3.new(0, 2.5, 0)), color, Enum.PartType.Ball, 0.3)
		fade(ball, 0.3, Vector3.one * a[4] * 1.4)
		sparks(at + Vector3.new(0, 2, 0), color, 20, 36)
		sound("boom", at, 0.4)
		addShake(0.3, at)
	elseif kind == "area" then
		local at = Vector3.new(a[1], a[2], a[3])
		local color = typeColor(a[5])
		telegraph(at, a[4], a[6], color)
		-- A meteor falling in on time.
		local rock = fxPart(Vector3.one * 5, CFrame.new(at + Vector3.new(-20, 80, 0)), color, Enum.PartType.Ball)
		local fire = Instance.new("Fire")
		fire.Size = 10
		fire.Heat = 0
		fire.Color = color
		fire.Parent = rock
		TweenService
			:Create(
				rock,
				TweenInfo.new(a[6], Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ CFrame = CFrame.new(at) }
			)
			:Play()
		Debris:AddItem(rock, a[6])
	elseif kind == "blast" then
		blast(Vector3.new(a[1], a[2], a[3]), a[4], typeColor(a[5]))
	elseif kind == "ring" then
		telegraph(Vector3.new(a[1], a[2], a[3]), a[4], a[5], Color3.fromRGB(255, 70, 40))
	elseif kind == "beam" then
		local from, to = Vector3.new(a[1], a[2], a[3]), Vector3.new(a[4], a[5], a[6])
		local length = (to - from).Magnitude
		local color = typeColor(a[7])
		local beam = fxPart(Vector3.new(a[8], a[8], length), CFrame.lookAt((from + to) / 2, to), color, nil, 0.1)
		fade(beam, 0.35, Vector3.new(0.2, 0.2, length))
		impact(to, color, 3)
		sound("boom", from, 0.4)
	elseif kind == "shield" then
		shieldBubble(a[1], typeColor(a[2]), a[3])
	elseif kind == "shieldBreak" then
		local bubble = fxFolder:FindFirstChild(`Shield{a[1]}`)
		if bubble and bubble:IsA("BasePart") then
			sparks(bubble.Position, bubble.Color, 20, 30)
			bubble:Destroy()
		end
	elseif kind == "heal" then
		aura(a[1], Color3.fromRGB(140, 230, 140), a[2], "HealAura")
	elseif kind == "buff" then
		aura(a[1], typeColor(a[2]), a[3], "BuffAura")
	elseif kind == "dash" then
		dashTrail(a[1], typeColor(a[2]))
	elseif kind == "blink" then
		local at = Vector3.new(a[2], a[3], a[4])
		local puff = fxPart(Vector3.one * 4, CFrame.new(at), typeColor(a[5]), Enum.PartType.Ball, 0.3)
		fade(puff, 0.4, Vector3.one * 8)
	elseif kind == "slash" then
		local model = a[1]
		local r = model and model.PrimaryPart
		if r then
			local reach = a[2]
			local arc = fxPart(
				Vector3.new(reach * 1.6, 0.4, reach),
				r.CFrame * CFrame.new(0, 0, -reach * 0.6),
				Color3.fromRGB(255, 200, 160),
				nil,
				0.35
			)
			fade(arc, 0.2)
		end
	elseif kind == "death" then
		local at = Vector3.new(a[1], a[2], a[3])
		local color = typeColor(a[4])
		local poof = fxPart(Vector3.one * a[5] * 2, CFrame.new(at), Color3.fromRGB(80, 72, 70), Enum.PartType.Ball, 0.2)
		poof.Material = Enum.Material.SmoothPlastic
		fade(poof, 0.6, Vector3.one * a[5] * 5)
		sparks(at, color, 30, 30)
	elseif kind == "levelup" then
		local character = characterOf(a[1])
		local r = character and character:FindFirstChild("HumanoidRootPart")
		if r and r:IsA("BasePart") then
			local column = fxPart(
				Vector3.new(30, 6, 6),
				CFrame.new(r.Position) * CFrame.Angles(0, 0, math.pi / 2),
				Color3.fromRGB(255, 220, 120),
				Enum.PartType.Cylinder,
				0.3
			)
			fade(column, 0.9, Vector3.new(60, 10, 10))
			sparks(r.Position, Color3.fromRGB(255, 220, 120), 40, 30)
			if a[1] == player.UserId then
				sound("level", nil, 0.8)
			end
		end
	end
end

-- Damage numbers ---------------------------------------------------------------------------

local function damageNumber(target: Instance, amount: number, mult: number)
	local model = if target:IsA("Model") then target else nil
	local r = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
	if r == nil or not r:IsA("BasePart") then
		return
	end
	local mine = model == player.Character
	local holder = fxPart(
		Vector3.one * 0.2,
		CFrame.new(r.Position + Vector3.new(math.random(-15, 15) / 10, 2.5, 0)),
		Color3.new(),
		nil,
		1
	)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 44)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 160
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextStrokeTransparency = 0.3
	label.Text = tostring(amount)
	label.TextColor3 = if mine
		then Color3.fromRGB(255, 90, 80)
		elseif mult > 1 then Color3.fromRGB(255, 170, 60)
		elseif mult < 1 then Color3.fromRGB(170, 170, 170)
		else Color3.fromRGB(255, 245, 220)
	if mult > 1 and not mine then
		label.Text = `{amount}!`
		gui.Size = UDim2.fromOffset(150, 54)
	end
	label.Parent = gui
	gui.Parent = holder
	TweenService:Create(
		holder,
		TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = holder.CFrame + Vector3.new(0, 3, 0) }
	):Play()
	TweenService:Create(
		label,
		TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()
	Debris:AddItem(holder, 0.75)
	if mine then
		addShake(0.35)
	else
		sound("hit", r.Position, 0.25)
	end
end

-- Movement spells --------------------------------------------------------------------------

local function push(direction: Vector3, speed: number, seconds: number)
	local r = root()
	if r == nil then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = r
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.MaxForce = math.huge
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VectorVelocity = direction * speed
	velocity.Parent = r
	Debris:AddItem(velocity, seconds)
	Debris:AddItem(attachment, seconds)
end

local function flatAim(): Vector3
	local r = root() :: BasePart
	local d = aimPoint() - r.Position
	local flat = Vector3.new(d.X, 0, d.Z)
	return if flat.Magnitude > 0.1 then flat.Unit else r.CFrame.LookVector
end

local function moveDirection(): Vector3
	local h = humanoid()
	if h and h.MoveDirection.Magnitude > 0.1 then
		return h.MoveDirection.Unit
	end
	local cam = workspace.CurrentCamera.CFrame.LookVector
	local flat = Vector3.new(cam.X, 0, cam.Z)
	return if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis
end

local function blink(distance: number)
	local r = root()
	local character = player.Character
	if r == nil or character == nil then
		return
	end
	local dir = flatAim()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, fxFolder }
	local hit = workspace:Raycast(r.Position, dir * distance, params)
	local travel = if hit then math.max(0, hit.Distance - 2) else distance
	character:PivotTo(CFrame.lookAt(r.Position + dir * travel, r.Position + dir * (travel + 1)))
end

-- Input ----------------------------------------------------------------------------------

local function tryReady(key: string, cooldown: number): boolean
	local now = os.clock()
	if (ready[key] or 0) > now then
		return false
	end
	ready[key] = now + cooldown
	durations[key] = cooldown
	return true
end

-- When `key` is ready again, and how long its cooldown is.
function CombatController.readyAt(key: string): (number, number)
	return ready[key] or 0, durations[key] or 1
end

local function basic()
	local r = root()
	if r == nil or humanoid() == nil then
		return
	end
	local book = activeBook()
	local kind = if book then book.type else "Neutral"
	local spec = Spells.BASIC[kind] or Spells.BASIC.Neutral
	if not tryReady("basic", spec.cooldown) then
		return
	end
	local target = aimPoint()
	NetClient.send("Basic", target.X, target.Y, target.Z)
	local origin = r.Position + Vector3.new(0, 1.2, 0)
	local dir = (target - origin).Unit
	dir = Vector3.new(dir.X, math.clamp(dir.Y, -0.35, 0.35), dir.Z).Unit
	drawBolt(player.UserId, origin + dir * 1.5, dir, spec.speed, spec.range, kind, spec.radius)
	sound("cast", nil, 0.25)
end

local function cast(slot: number)
	local r = root()
	local book = activeBook()
	if r == nil or humanoid() == nil or book == nil then
		return
	end
	local page = book.pages[slot]
	local spell = page and Spells.get(page.sp)
	if spell == nil then
		return
	end
	local key = `{book.type}:{spell.id}:{slot}`
	local cooldown = Spells.cooldownAt(spell, page.lv)
	if not tryReady(key, cooldown) then
		return
	end
	local target = aimPoint()
	NetClient.send("Cast", slot, target.X, target.Y, target.Z)
	CombatController.Cast:Fire(slot, ready[key], cooldown)
	sound("cast", nil, 0.45)
	if spell.kind == "bolt" then
		local origin = r.Position + Vector3.new(0, 1.2, 0)
		local dir = (target - origin).Unit
		dir = Vector3.new(dir.X, math.clamp(dir.Y, -0.35, 0.35), dir.Z).Unit
		drawBolt(player.UserId, origin + dir * 1.5, dir, spell.speed, spell.range, spell.type, spell.radius)
	elseif spell.kind == "dash" then
		push(flatAim(), spell.distance / 0.3, 0.3)
	elseif spell.kind == "blink" then
		blink(spell.distance)
	end
end

local function dash()
	if humanoid() == nil or not tryReady("dash", CombatController.DASH_COOLDOWN) then
		return
	end
	NetClient.send("Dash")
	push(moveDirection(), 70, 0.2)
	CombatController.Dashed:Fire(ready.dash)
end

function CombatController.cast(slot: number)
	cast(slot)
end

function CombatController.Init()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "CombatFx"
	fxFolder.Parent = workspace

	NetClient.on("Fx", onFx)
	NetClient.on("Hit", damageNumber)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseDown = true
			basic()
			return
		end
		for slot, key in CombatController.SPELL_KEYS do
			if input.KeyCode == key then
				cast(slot)
				return
			end
		end
		for slot, key in CombatController.BOOK_KEYS do
			if input.KeyCode == key then
				NetClient.send("SwapBook", slot)
				return
			end
		end
		if input.KeyCode == Enum.KeyCode.Q then
			dash()
		elseif input.KeyCode == Enum.KeyCode.R then
			NetClient.send("Recall")
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseDown = false
		end
	end)
end

function CombatController.Start()
	RunService.RenderStepped:Connect(function(dt)
		if mouseDown then
			basic()
		end
		if shake > 0.01 then
			local camera = workspace.CurrentCamera
			local s = shake
			camera.CFrame *= CFrame.Angles(
				math.rad((math.random() - 0.5) * s * 2),
				math.rad((math.random() - 0.5) * s * 2),
				0
			)
			shake = math.max(0, shake - dt * 3)
		end
	end)
end

return CombatController
