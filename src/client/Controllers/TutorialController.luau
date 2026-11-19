--!strict
-- The new-player tutorial on screen (GAME_SYSTEMS §22). TutorialService picks the step and
-- publishes it as the Player attribute `FtueStep`; this draws it:
--   a banner at the bottom with what to do (it pulses after HINT_SECONDS without progress),
--   a guide Wisp that floats ahead of you toward the target, with a soft beam to it,
--   the Free Lure (step 1): a lantern by you; the context button says "Open"
--   the Wisp's Stash grab (step 5): next to the stash the context button says "Take"; hold it
--   for HOLD_SECONDS, then run home (the server carries it on your character).
-- Purely cosmetic and local; the server checks everything again.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared:WaitForChild("Palette"))
local Economy = require(Shared:WaitForChild("Economy"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local InputController = require(script.Parent:WaitForChild("InputController"))
local PlotController = require(script.Parent:WaitForChild("PlotController"))

local OPEN = "Open"
local TAKE = "Take"
local PRIORITY = 35 -- above Grab, Catch and Feed; below Revive
local HINT_SECONDS = 20
local HOLD_SECONDS = 1
local STASH_REACH = 12
local LURE_REACH = 12
local LURE_FIRE_CLEAR = 10 -- studs from the fire's centre
local WISP_LEAD = 5

local TutorialController = {}

local lurePrice = Economy.lureCost(economy, 1)

-- What each step says. Functions get whether the player is carrying something.
local TEXT: { [number]: string | (boolean) -> string } = {
	"A Free Lure! Walk up and open it",
	"Your first Glowling! It earns Glow while it wanders your yard",
	`Your Glowlings earn Glow. Save up {lurePrice} Glow`,
	"Buy a lure at the Lantern Shop",
	function(carrying: boolean)
		return if carrying then "Run it home to your base!" else "Steal one from the Wisp's Stash! Hold Take"
	end,
	"Tap Lock to keep thieves out of your base for a while",
	"Night is coming. Stick together by the fire",
	function(carrying: boolean)
		return if carrying then "Bring it to the fire!" else "Grab wood from a pile and feed the fire"
	end,
	"A Rare Glowling by the fire, just for you. Catch it!",
	"You survived the night! Next goal: Rebirth at 250K Glow ⭐",
}

local banner: TextLabel? = nil
local bannerScale: UIScale? = nil
local wisp: Part? = nil
local beam: Beam? = nil
local toAttach: Attachment? = nil
local lure: Model? = nil
local lureBase: CFrame? = nil
local shownStep: number? = nil
local shownAt = 0
local holdStarted: number? = nil
local pulse: Tween? = nil

local function step(): number?
	local n = Players.LocalPlayer:GetAttribute("FtueStep")
	return if type(n) == "number" and n >= 1 then n else nil
end

local function root(): BasePart?
	local character = Players.LocalPlayer.Character
	local part = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return if part ~= nil and part:IsA("BasePart") then part else nil
end

local function carrying(): boolean
	local character = Players.LocalPlayer.Character
	return character ~= nil and (character:GetAttribute("CarrySp") ~= nil or character:GetAttribute("CarryFuel") ~= nil)
end

local function station(kind: string): BasePart?
	local map = workspace:FindFirstChild("Map")
	local stations = if map ~= nil then map:FindFirstChild("Stations") else nil
	for _, s in if stations ~= nil then stations:GetChildren() else {} do
		if s:GetAttribute("Kind") == kind then
			local base = s:FindFirstChild("Base")
			return if base ~= nil and base:IsA("BasePart") then base else nil
		end
	end
	return nil
end

local function campfire(): Vector3?
	local map = workspace:FindFirstChild("Map")
	local fire = if map ~= nil then map:FindFirstChild("Campfire") else nil
	return if fire ~= nil and fire:IsA("Model") then fire:GetPivot().Position else nil
end

local function myPlot(): Vector3?
	local id = PlotController.mine()
	for _, model in CollectionService:GetTagged("Plot") do
		if model:GetAttribute("PlotId") == id then
			local floor = model:FindFirstChild("Floor")
			return if floor ~= nil and floor:IsA("BasePart") then floor.Position else nil
		end
	end
	return nil
end

local function nearestPile(from: Vector3): Vector3?
	local best: Vector3?, bestDistance = nil, math.huge
	for _, pile in CollectionService:GetTagged("WoodPile") do
		local at = if pile:IsA("Model")
			then pile:GetPivot().Position
			elseif pile:IsA("BasePart") then pile.Position
			else nil
		if at ~= nil and (at - from).Magnitude < bestDistance then
			best, bestDistance = at, (at - from).Magnitude
		end
	end
	return best
end

-- Where the guide points for this step, or nil.
local function target(n: number, from: Vector3): Vector3?
	if n == 1 then
		return if lure ~= nil then lure:GetPivot().Position else nil
	elseif n == 2 or n == 3 then
		return myPlot()
	elseif n == 4 then
		local shop = station("LanternShop")
		return if shop ~= nil then shop.Position else nil
	elseif n == 5 then
		if carrying() then
			return myPlot()
		end
		local stash = station("WispStash")
		return if stash ~= nil then stash.Position else nil
	elseif n == 7 then
		return campfire()
	elseif n == 8 then
		return if carrying() then campfire() else nearestPile(from)
	elseif n == 9 then
		local id = Players.LocalPlayer:GetAttribute("FtueWild")
		local wilds = workspace:FindFirstChild("Wilds")
		local wild = if wilds ~= nil and id ~= nil then wilds:FindFirstChild(`Wild{id}`) else nil
		return if wild ~= nil and wild:IsA("Model") then wild:GetPivot().Position else nil
	end
	return nil
end

-- The Free Lure: a small glowing lantern on a stump, a few studs in front of the player.
local function buildLure(at: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "FreeLure"
	local function piece(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material)
		local p = Instance.new("Part")
		p.Size, p.CFrame, p.Color, p.Material = size, at * cf, color, material
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		p.Parent = m
		return p
	end
	piece(Vector3.new(1.6, 1, 1.6), CFrame.new(0, 0.5, 0), Palette.bark, Enum.Material.Wood)
	piece(Vector3.new(1.2, 0.25, 1.2), CFrame.new(0, 1.1, 0), Palette.bark, Enum.Material.Wood)
	local pane = piece(Vector3.new(0.9, 1.1, 0.9), CFrame.new(0, 1.8, 0), Palette.lantern, Enum.Material.Neon)
	piece(Vector3.new(1.2, 0.25, 1.2), CFrame.new(0, 2.45, 0), Palette.bark, Enum.Material.Wood)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = Palette.lantern, 12, 1.5
	light.Parent = pane
	m.PrimaryPart = pane
	pane.PivotOffset = pane.CFrame:ToObjectSpace(at) -- the pivot stays on the ground
	m.Parent = workspace
	return m
end

-- The personal Rare is hard to spot in the dark: a soft spirit light on it.
local function lightWild()
	local id = Players.LocalPlayer:GetAttribute("FtueWild")
	local wilds = workspace:FindFirstChild("Wilds")
	local wild = if wilds ~= nil and id ~= nil then wilds:FindFirstChild(`Wild{id}`) else nil
	local part = if wild ~= nil then wild:FindFirstChildWhichIsA("BasePart", true) else nil
	if part ~= nil and part:FindFirstChild("FtueLight") == nil then
		local light = Instance.new("PointLight")
		light.Name = "FtueLight"
		light.Color, light.Range, light.Brightness = Palette.spirit, 14, 1.6
		light.Parent = part
	end
end

local function clearLure()
	if lure ~= nil then
		lure:Destroy()
		lure = nil
	end
end

local function buildWorld()
	local orb = Instance.new("Part")
	orb.Name = "GuideWisp"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.one * 0.9
	orb.Color = Palette.spirit
	orb.Material = Enum.Material.Neon
	orb.Anchored, orb.CanCollide, orb.CanQuery, orb.CanTouch, orb.CastShadow = true, false, false, false, false
	orb.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = Palette.spirit, 10, 1
	light.Parent = orb
	local a0 = Instance.new("Attachment")
	a0.Parent = orb
	local holder = Instance.new("Part")
	holder.Name = "GuideTarget"
	holder.Size = Vector3.one * 0.2
	holder.Transparency = 1
	holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch = true, false, false, false
	holder.Parent = orb
	local a1 = Instance.new("Attachment")
	a1.Parent = holder
	local b = Instance.new("Beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.Color = ColorSequence.new(Palette.spirit)
	b.Transparency = NumberSequence.new(0.35, 0.9)
	b.Width0, b.Width1 = 0.5, 0.15
	b.LightEmission = 1
	b.FaceCamera = true
	b.TextureSpeed = 1
	b.Enabled = false
	b.Parent = orb
	orb.Parent = workspace
	wisp, beam, toAttach = orb, b, a1
end

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TutorialGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local label = Instance.new("TextLabel")
	label.Name = "Banner"
	label.AnchorPoint = Vector2.new(0.5, 1)
	-- At the bottom, under the character and the hold bars (y -140), clear of the touch
	-- buttons on the right.
	label.Position = UDim2.new(0.5, 0, 1, -24)
	label.Size = UDim2.new(0.62, 0, 0, 40)
	label.BackgroundColor3 = Color3.fromRGB(28, 34, 30)
	label.BackgroundTransparency = 0.25
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(240, 232, 210)
	label.Visible = false
	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize = 22
	size.Parent = label
	local maxWidth = Instance.new("UISizeConstraint")
	maxWidth.MaxSize = Vector2.new(620, 40)
	maxWidth.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	padding.Parent = label
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.lantern
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Parent = label
	label.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	banner, bannerScale = label, scale
end

local function setPulse(on: boolean)
	if pulse ~= nil then
		pulse:Cancel()
		pulse = nil
	end
	local scale = bannerScale
	if scale == nil then
		return
	end
	scale.Scale = 1
	if on then
		pulse = TweenService:Create(
			scale,
			TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 1.08 }
		)
		pulse:Play()
	end
end

local function update()
	local n = step()
	local r = root()
	if n ~= shownStep then
		shownStep, shownAt, holdStarted = n, os.clock(), nil
		setPulse(false)
		if n ~= 1 then
			clearLure()
		end
	end
	if n == 1 and lure == nil and r ~= nil then
		-- Ahead and to the right, and never in the fire pit (players spawn facing the fire).
		local spot = (r.CFrame * CFrame.new(5, -3, -4)).Position
		local fire = campfire()
		if fire ~= nil then
			local away = Vector3.new(spot.X - fire.X, 0, spot.Z - fire.Z)
			if away.Magnitude < LURE_FIRE_CLEAR then
				local dir = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
				spot = Vector3.new(fire.X, spot.Y, fire.Z) + dir * LURE_FIRE_CLEAR
			end
		end
		lureBase = CFrame.new(spot) * CFrame.Angles(0, math.rad(r.Orientation.Y), 0)
		lure = buildLure(lureBase :: CFrame)
	end
	if lure ~= nil and lureBase ~= nil then -- a slow bob and turn, so it reads as a pickup
		local t = os.clock()
		lure:PivotTo(
			(lureBase :: CFrame) * CFrame.new(0, 0.25 + math.sin(t * 2) * 0.25, 0) * CFrame.Angles(0, t * 0.6, 0)
		)
	end
	if n == 9 then
		lightWild()
	end
	if n ~= nil and pulse == nil and os.clock() - shownAt > HINT_SECONDS then
		setPulse(true)
	end

	local label = banner
	if label ~= nil then
		local text = if n ~= nil then TEXT[n] else nil
		label.Visible = text ~= nil
		if type(text) == "function" then
			label.Text = text(carrying())
		elseif text ~= nil then
			label.Text = text
		end
	end

	-- The context button: Open the Free Lure, Take from the Wisp's Stash.
	local offer: string? = nil
	if n == 1 and r ~= nil and lure ~= nil and (lure:GetPivot().Position - r.Position).Magnitude <= LURE_REACH then
		offer = OPEN
	elseif n == 5 and r ~= nil and not carrying() then
		local stash = station("WispStash")
		if stash ~= nil and (stash.Position - r.Position).Magnitude <= STASH_REACH then
			offer = TAKE
		end
	end
	InputController.offer("Tutorial", offer, PRIORITY)
	if holdStarted ~= nil and offer == TAKE and os.clock() - holdStarted >= HOLD_SECONDS then
		holdStarted = nil
		NetClient.send("FtueAction", "stash")
	end

	-- The guide Wisp leads toward the target and draws a beam to it.
	local orb, b, to = wisp, beam, toAttach
	local goal = if n ~= nil and r ~= nil then target(n, r.Position) else nil
	if orb ~= nil and b ~= nil and to ~= nil then
		if goal == nil or r == nil then
			orb.Transparency = 1
			b.Enabled = false
		else
			local flat = Vector3.new(goal.X - r.Position.X, 0, goal.Z - r.Position.Z)
			local lead = if flat.Magnitude > 0.1 then flat.Unit * math.min(WISP_LEAD, flat.Magnitude) else Vector3.zero
			local bob = math.sin(os.clock() * 3) * 0.4
			local want = r.Position + lead + Vector3.new(0, 2.5 + bob, 0)
			orb.CFrame = orb.CFrame:Lerp(CFrame.new(want), 0.15)
			orb.Transparency = 0.1
			to.WorldPosition = goal + Vector3.new(0, 1.5, 0)
			b.Enabled = flat.Magnitude > 6
		end
	end
end

function TutorialController.Init() end

function TutorialController.Start()
	buildGui()
	buildWorld()
	InputController.Action:Connect(function(label: string, began: boolean)
		if label == OPEN and began then
			NetClient.send("FtueAction", "lure")
		elseif label == TAKE then
			holdStarted = if began then os.clock() else nil
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return TutorialController
