--!strict
-- HUD skeleton (Phase 1): the Glow counter (extrapolated from the Wallet), Embers, the cycle
-- ring with its countdown, the phase banner, and a loading cover until the first PlayerState.
--
-- If the place has StarterGui.HUD (laid out by artists in Studio; set ResetOnSpawn off), this
-- binds to its descendants by name: Glow, Embers, Ring (with Dot1..DotN children), Countdown,
-- PhaseLabel, Banner, Loading. Any of them may be missing. Without a StarterGui.HUD it builds
-- a plain placeholder with the same names.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Cycle = require(Shared:WaitForChild("Cycle"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local economy = require(Config:WaitForChild("economy")) :: any
local speciesConfig = require(Config:WaitForChild("species")) :: any
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local StateController = require(script.Parent:WaitForChild("StateController"))
local CycleFXController = require(script.Parent:WaitForChild("CycleFXController"))

local RING_DOTS = 48
local REFRESH_SECONDS = 0.1
local BANNER_SECONDS = 4

local DAY_DOT = Color3.fromRGB(255, 205, 110)
local NIGHT_DOT = Color3.fromRGB(120, 150, 255)
local PANEL = Color3.fromRGB(16, 18, 32)

local MODIFIER_NAMES = {
	Fog = "Fog",
	FireflyBloom = "Firefly Bloom",
	Gusty = "Gusty Night",
	Starfall = "Starfall",
}

local BANNERS = {
	Day = "Dawn! Your Glowlings are safe.",
	Dusk = "Night is coming. Head for the fire!",
	Night = "Night has fallen. Feed the fire and catch Glowlings.",
}

type Parts = {
	glow: TextLabel?,
	embers: TextLabel?,
	dots: { GuiObject },
	countdown: TextLabel?,
	phaseLabel: TextLabel?,
	banner: TextLabel?,
	loading: GuiObject?,
}

local HUDController = {}

local parts: Parts = { dots = {} }
local bannerToken = 0

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function makeLabel(name: string, parent: Instance, textSize: number, color: Color3): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.AutomaticSize = Enum.AutomaticSize.X
	text.Size = UDim2.fromOffset(0, 36)
	text.BackgroundColor3 = PANEL
	text.BackgroundTransparency = 0.35
	text.Font = Enum.Font.GothamBold
	text.TextSize = textSize
	text.TextColor3 = color
	text.Text = ""
	corner(text, UDim.new(0, 10))
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = text
	text.Parent = parent
	return text
end

local function buildPlaceholder(playerGui: PlayerGui): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local top = Instance.new("Frame")
	top.Name = "TopBar"
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 8)
	top.Size = UDim2.fromOffset(0, 36)
	top.AutomaticSize = Enum.AutomaticSize.X
	top.BackgroundTransparency = 1
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 10)
	list.Parent = top
	top.Parent = gui
	makeLabel("Glow", top, 22, Color3.fromRGB(255, 221, 120)).LayoutOrder = 1
	makeLabel("Embers", top, 22, Color3.fromRGB(255, 150, 90)).LayoutOrder = 2

	-- Cycle ring: dots around a circle. Day dots are warm and night dots blue; passed dots dim.
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(1, 0)
	ring.Position = UDim2.new(1, -12, 0, 8)
	ring.Size = UDim2.fromOffset(96, 96)
	ring.BackgroundColor3 = PANEL
	ring.BackgroundTransparency = 0.5
	corner(ring, UDim.new(1, 0))
	ring.Parent = gui
	for i = 1, RING_DOTS do
		local angle = (i - 0.5) / RING_DOTS * 2 * math.pi
		local dot = Instance.new("Frame")
		dot.Name = `Dot{i}`
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5 + 0.42 * math.sin(angle), 0.5 - 0.42 * math.cos(angle))
		dot.Size = UDim2.fromOffset(6, 6)
		dot.BorderSizePixel = 0
		corner(dot, UDim.new(1, 0))
		dot.Parent = ring
	end

	local phaseLabel = Instance.new("TextLabel")
	phaseLabel.Name = "PhaseLabel"
	phaseLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	phaseLabel.Position = UDim2.fromScale(0.5, 0.36)
	phaseLabel.Size = UDim2.fromOffset(70, 14)
	phaseLabel.BackgroundTransparency = 1
	phaseLabel.Font = Enum.Font.GothamMedium
	phaseLabel.TextSize = 12
	phaseLabel.TextColor3 = Color3.fromRGB(210, 210, 230)
	phaseLabel.Text = "" -- not Roblox's default "Label" before the first refresh
	phaseLabel.Parent = ring

	local countdown = Instance.new("TextLabel")
	countdown.Name = "Countdown"
	countdown.AnchorPoint = Vector2.new(0.5, 0.5)
	countdown.Position = UDim2.fromScale(0.5, 0.58)
	countdown.Size = UDim2.fromOffset(70, 24)
	countdown.BackgroundTransparency = 1
	countdown.Font = Enum.Font.GothamBold
	countdown.TextSize = 20
	countdown.TextColor3 = Color3.new(1, 1, 1)
	countdown.Text = ""
	countdown.Parent = ring

	local banner = makeLabel("Banner", gui, 22, Color3.new(1, 1, 1))
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 56)
	banner.Size = UDim2.fromOffset(0, 44)
	banner.Visible = false

	local cover = Instance.new("ScreenGui")
	cover.Name = "LoadingCover"
	cover.ResetOnSpawn = false
	cover.IgnoreGuiInset = true
	cover.DisplayOrder = 100
	local loading = Instance.new("TextLabel")
	loading.Name = "Loading"
	loading.Size = UDim2.fromScale(1, 1)
	loading.BackgroundColor3 = Color3.fromRGB(8, 10, 20)
	loading.Font = Enum.Font.GothamBold
	loading.TextSize = 24
	loading.TextColor3 = Color3.fromRGB(255, 221, 120)
	loading.Text = "Lighting the lanterns…"
	loading.Parent = cover
	cover.Parent = playerGui

	gui.Parent = playerGui
	return gui
end

local function find(root: Instance, name: string, className: string): any
	local found = root:FindFirstChild(name, true)
	if found ~= nil and found:IsA(className) then
		return found
	end
	return nil
end

local function bind(playerGui: PlayerGui)
	local root: Instance
	if StarterGui:FindFirstChild("HUD") ~= nil then
		root = playerGui:WaitForChild("HUD")
	else
		root = buildPlaceholder(playerGui)
	end

	parts.glow = find(root, "Glow", "TextLabel")
	parts.embers = find(root, "Embers", "TextLabel")
	parts.countdown = find(root, "Countdown", "TextLabel")
	parts.phaseLabel = find(root, "PhaseLabel", "TextLabel")
	parts.banner = find(root, "Banner", "TextLabel")
	parts.loading = find(root, "Loading", "GuiObject") or find(playerGui, "Loading", "GuiObject")

	local ring = find(root, "Ring", "GuiObject")
	if ring ~= nil then
		for i = 1, math.huge do
			local dot = ring:FindFirstChild(`Dot{i}`)
			if dot == nil or not dot:IsA("GuiObject") then
				break
			end
			table.insert(parts.dots, dot)
		end
	end
end

local function showBanner(text: string)
	local banner = parts.banner
	if banner == nil then
		return
	end
	bannerToken += 1
	local token = bannerToken
	banner.Text = text
	banner.Visible = true
	task.delay(BANNER_SECONDS, function()
		if token == bannerToken then
			banner.Visible = false
		end
	end)
end

-- Placeholder roll reveal until RollRevealController (GS): "You got a Rare Golden Mothlet!"
local function rollText(record: any): string
	local name = record.sp
	for _, species in speciesConfig.species do
		if species.id == record.sp then
			name = species.name
			break
		end
	end
	local rarity = economy.rarities[record.r]
	local mutation = if record.m > 0 then economy.mutations[record.m] else nil
	local words = { if rarity then rarity.id else "?" }
	if mutation then
		table.insert(words, mutation.id)
	end
	table.insert(words, name)
	return `You got a {table.concat(words, " ")}!`
end

local function duskText(): string
	local id = workspace:GetAttribute("NightModifier")
	local name = if type(id) == "string" then MODIFIER_NAMES[id] or id else nil
	return if name ~= nil then `{BANNERS.Dusk}  Tonight: {name}` else BANNERS.Dusk
end

local function refresh()
	local now = workspace:GetServerTimeNow()
	if parts.glow ~= nil then
		parts.glow.Text = `Glow {EconomyMath.formatNumber(StateController.glowAt(now))}`
	end
	if parts.embers ~= nil then
		parts.embers.Text = `Embers {EconomyMath.formatNumber(StateController.wallet().embers)}`
	end

	local state = CycleFXController.state()
	if state == nil then
		return
	end
	local atNight = state.phase == "Night"
	if parts.phaseLabel ~= nil then
		parts.phaseLabel.Text = if atNight then "Dawn in" else "Night in"
	end
	if parts.countdown ~= nil then
		parts.countdown.Text = Cycle.formatClock(if atNight then state.untilDawn else state.untilNight)
	end

	local count = #parts.dots
	if count > 0 then
		local c = CycleFXController.cycleConfig()
		local dayShare = c.daySeconds / state.length
		local progress = state.t / state.length
		for i, dot in parts.dots do
			local f = (i - 0.5) / count
			dot.BackgroundColor3 = if f < dayShare then DAY_DOT else NIGHT_DOT
			dot.BackgroundTransparency = if f < progress then 0.75 else 0
		end
	end
end

function HUDController.Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	bind(playerGui)

	local function hideLoading()
		if parts.loading ~= nil then
			parts.loading.Visible = false
		end
	end
	if StateController.isLoaded() then
		hideLoading()
	else
		StateController.Loaded:Connect(hideLoading)
	end

	CycleFXController.PhaseChanged:Connect(function(phase: string, _state: Cycle.State, initial: boolean)
		if initial then
			return
		end
		showBanner(if phase == "Dusk" then duskText() else BANNERS[phase])
	end)

	NetClient.on("RollResult", function(record: any)
		showBanner(rollText(record))
	end)

	workspace:GetAttributeChangedSignal("NightModifier"):Connect(function()
		local state = CycleFXController.state()
		if state ~= nil and state.phase == "Dusk" and workspace:GetAttribute("NightModifier") ~= nil then
			showBanner(duskText())
		end
	end)

	local elapsed = REFRESH_SECONDS
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= REFRESH_SECONDS then
			elapsed = 0
			refresh()
		end
	end)
end

return HUDController
