--!strict
-- The HUD:
--   * Bottom bar: Grimoire tabs (showing 3-Leaf / 4-Leaf / 5-Leaf + Passive), 4 fixed skill slots
--     (Z, X, C, V) with cooldowns, Health, XP, and Q Dash
--   * Top-left card: Capped Backpack Bar (glows gold when FULL!), carried Coins & Ink, Banked
--     Coins & Ink, ★ Stars, PvP Bounty, and the War Mode (PvP Toggle) button
--   * Top-right card: Active Area Quest tracker + hub guide beam

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Client = script.Parent.Parent
local Spells = require(Shared:WaitForChild("Spells")) :: any
local Element = require(Shared:WaitForChild("Element")) :: any
local Gears = require(Shared:WaitForChild("Gears")) :: any
local Level = require(Shared:WaitForChild("Level")) :: any
local Loot = require(Shared:WaitForChild("Loot")) :: any
local Zones = require(Shared:WaitForChild("Zones")) :: any
local NetClient = require(Client:WaitForChild("Net"):WaitForChild("NetClient"))
local Kit = require(Client:WaitForChild("Ui"):WaitForChild("Kit"))
local StateController = require(script.Parent:WaitForChild("StateController"))
local CombatController = require(script.Parent:WaitForChild("CombatController"))

local HUDController = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local hpFill: Frame
local hpText: TextLabel
local xpFill: Frame
local levelText: TextLabel
local tabs: Frame
local slots: { { frame: TextButton, name: TextLabel, cd: Frame, cdText: TextLabel, key: string } } = {}
local dashCd: Frame
local bagFill: Frame
local bagText: TextLabel
local lootText: TextLabel
local warBtn: TextButton
local questTitle: TextLabel
local questText: TextLabel
local questFrame: Frame
local recallFrame: Frame
local recallFill: Frame
local toastList: Frame
local recallEnds: number? = nil
local recallDuration = 5
local quest: any = nil

local KEYS = { "Z", "X", "C", "V" }

local function typeColor(kind: string): Color3
	return Kit.rgb(Element.COLOR[kind] or Element.COLOR.Neutral)
end

local function bar(parent: Instance, size: UDim2, position: UDim2, color: Color3): (Frame, Frame)
	local track = Kit.frame(parent, size, position, Color3.fromRGB(24, 20, 30))
	track:SetAttribute("NoSkin", true)
	local fill = Kit.frame(track, UDim2.fromScale(1, 1), UDim2.new(), color)
	fill:SetAttribute("NoSkin", true)
	return track, fill
end

-- Toasts -------------------------------------------------------------------------------------

local TOAST_COLORS = {
	loot = Color3.fromRGB(70, 60, 40),
	bank = Color3.fromRGB(46, 80, 56),
	warn = Color3.fromRGB(110, 46, 40),
	quest = Color3.fromRGB(90, 70, 30),
	level = Color3.fromRGB(96, 80, 30),
} :: { [string]: Color3 }

local function toast(text: string, kind: string?)
	local f = Kit.frame(toastList, UDim2.fromOffset(400, 34), UDim2.new(), TOAST_COLORS[kind or ""] or Kit.PANEL)
	f.LayoutOrder = -math.floor(os.clock() * 100)
	f.BackgroundTransparency = 0.1
	Kit.label(f, text, UDim2.new(1, -16, 1, 0), UDim2.fromOffset(8, 0), 14)
	task.delay(3.2, function()
		TweenService:Create(f, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		for _, d in f:GetDescendants() do
			if d:IsA("TextLabel") then
				TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			end
		end
		task.wait(0.35)
		f:Destroy()
	end)
	local count = 0
	for _, child in toastList:GetChildren() do
		if child:IsA("Frame") then
			count += 1
		end
	end
	if count > 4 then
		local oldest, order = nil, -math.huge
		for _, child in toastList:GetChildren() do
			if child:IsA("Frame") and child.LayoutOrder > order then
				oldest, order = child, child.LayoutOrder
			end
		end
		if oldest then
			oldest:Destroy()
		end
	end
end
HUDController.toast = toast

-- Book tabs and the spell bar ----------------------------------------------------------------

local function refreshBooks()
	local data = StateController.get()
	if data == nil then
		return
	end
	Kit.clear(tabs)
	Kit.list(tabs, 6, true)
	for slot, index in data.equipped do
		local book = data.books[index]
		if book then
			local active = data.active == slot
			local clovers = Element.clovers(book.type)
			local b = Kit.button(
				tabs,
				`{slot} · {clovers}♣ {book.type}`,
				UDim2.fromOffset(128, 28),
				UDim2.new(),
				if active then typeColor(book.type) else Kit.PANEL,
				function()
					NetClient.send("SwapBook", slot)
				end
			)
			b.TextSize = 13
			b.LayoutOrder = slot
			if active then
				b.TextColor3 = Color3.fromRGB(30, 24, 30)
			end
		end
	end
	local book = data.books[data.equipped[data.active]]
	local fixed = if book then Spells.fixedFor(book.type) else Spells.fixedFor("Neutral")
	for i, s in slots do
		local page = book and book.pages[i]
		local spell = page and Spells.get(page.sp)
		local lockedSpell = Spells.get(fixed[i])
		if spell and page then
			s.name.Text = `<b>{spell.name}</b>\n<font size="11">Lv {page.lv}</font>`
			s.frame.BackgroundColor3 = Kit.rgb(Spells.RARITY_COLOR[spell.rarity]):Lerp(Kit.PANEL, 0.55)
			s.key = `{book.type}:{spell.id}:{i}`
		else
			local lockedName = if lockedSpell then lockedSpell.name else "Locked"
			s.name.Text = `<font color="#8a8296">{lockedName}\n<font size="10">Unlock at Desk</font></font>`
			s.frame.BackgroundColor3 = Kit.PANEL
			s.key = ""
		end
	end
end

local function refreshLoot()
	local data = StateController.get()
	if data == nil then
		return
	end
	local gStats = Gears.stats(data.gears)
	local cap = gStats.capacity
	local weight = Loot.weight(data.carried)
	local full = weight >= cap
	bagFill.Size = UDim2.fromScale(math.clamp(weight / math.max(1, cap), 0, 1), 1)
	bagFill.BackgroundColor3 = if full then Color3.fromRGB(255, 200, 70) else Color3.fromRGB(130, 185, 115)
	bagText.Text = if full
		then `BACKPACK FULL ({weight}/{cap}) — Walk to Camp for +15%!`
		else `Backpack: {weight} / {cap}   ({data.carried.coins} Coins · {Loot.totalInk(data.carried)} Ink)`
	lootText.Text =
		`<font color="#9fd6a4"><b>Banked</b>  Coins {data.bank.coins}  ·  Ink {Loot.totalInk(data.bank)}</font>   <font color="#ffd970"><b>★ {data.stars}</b></font>   <font color="#ff9d80">⚔ {data.bounty or 0}</font>`
end

local function refreshWarMode()
	local on = player:GetAttribute("WarMode") == true
	warBtn.Text = if on then "⚔ War Mode: ON (+25% Coins)" else "🛡 War Mode: OFF (Safe)"
	warBtn.BackgroundColor3 = if on then Color3.fromRGB(175, 62, 54) else Kit.PANEL
end

local function refreshLevel()
	local data = StateController.get()
	if data == nil then
		return
	end
	local need = Level.xpToNext(data.level)
	levelText.Text = if data.level >= Level.CAP
		then `Lv {data.level} (max)`
		else `Lv {data.level}   {data.xp} / {need} XP`
	xpFill.Size = UDim2.fromScale(if data.level >= Level.CAP then 1 else math.clamp(data.xp / need, 0, 1), 1)
end

local function refreshQuest()
	if quest == nil then
		questFrame.Visible = false
		return
	end
	questFrame.Visible = true
	questTitle.Text = if quest.title
		then quest.title
		elseif quest.tutorial then `Tutorial {quest.index}/6`
		else "Area Quest (★ Stars + Coins)"
	questText.Text = if quest.n > 1 then `{quest.text}  ({quest.progress}/{quest.n})` else quest.text
end

-- Guide line (inside the hub courtyard only, for tutorial desk/camp hints) -----------------

local guideBeam: Beam
local guideFrom: Attachment
local guideTo: Attachment
local guidePart: Part

local function hintTarget(): Vector3?
	if quest == nil or quest.hint == nil then
		return nil
	end
	local hint = quest.hint
	if hint == "desk" then
		return Zones.DESK_POS + Vector3.new(0, 3, 0)
	elseif hint == "camp" then
		return Zones.BANK_POS + Vector3.new(0, 2, 0)
	end
	return nil
end

local function updateGuide()
	local me = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local target = hintTarget()
	if
		me == nil
		or not me:IsA("BasePart")
		or target == nil
		or Vector2.new(me.Position.X, me.Position.Z).Magnitude > Zones.CAMP_R
		or (target - me.Position).Magnitude < 8
	then
		guideBeam.Enabled = false
		return
	end
	if guideFrom.Parent ~= me then
		guideFrom.Parent = me
	end
	guidePart.Position = target
	guideBeam.Enabled = true
end

-- Build ------------------------------------------------------------------------------------

local function build()
	gui = Kit.screen("HUD", 1)

	-- Bottom centre: health, XP, tabs, spells.
	local bottom = Instance.new("Frame")
	bottom.BackgroundTransparency = 1
	bottom.Size = UDim2.fromOffset(520, 170)
	bottom.Position = UDim2.new(0.5, 0, 1, -12)
	bottom.AnchorPoint = Vector2.new(0.5, 1)
	bottom.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = bottom
	local function fit()
		scale.Scale = math.min(1, (workspace.CurrentCamera.ViewportSize.X - 24) / 520)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.new(1, 0, 0, 28)
	tabs.Position = UDim2.fromOffset(0, 0)
	tabs.Parent = bottom

	for i = 1, 4 do
		local frame = Kit.button(
			bottom,
			"",
			UDim2.fromOffset(122, 58),
			UDim2.fromOffset((i - 1) * 130, 36),
			Kit.PANEL,
			function()
				CombatController.cast(i)
			end
		)
		local key = Kit.label(frame, KEYS[i], UDim2.fromOffset(22, 22), UDim2.fromOffset(4, 3), 14, Kit.GOLD)
		key.TextXAlignment = Enum.TextXAlignment.Left
		local name = Kit.label(frame, "", UDim2.new(1, -8, 1, -6), UDim2.fromOffset(4, 4), 13)
		local cd =
			Kit.frame(frame, UDim2.fromScale(1, 0), UDim2.fromScale(0, 1), Color3.new(0, 0, 0), Vector2.new(0, 1))
		cd.BackgroundTransparency = 0.4
		cd:SetAttribute("NoSkin", true)
		local cdText = Kit.label(frame, "", UDim2.fromScale(1, 1), UDim2.new(), 20, Kit.TEXT)
		cdText.ZIndex = 3
		slots[i] = { frame = frame, name = name, cd = cd, cdText = cdText, key = "" }
	end

	local hpTrack
	hpTrack, hpFill = bar(bottom, UDim2.fromOffset(392, 22), UDim2.fromOffset(0, 102), Color3.fromRGB(200, 70, 60))
	hpText = Kit.label(hpTrack, "", UDim2.fromScale(1, 1), UDim2.new(), 14)
	hpText.ZIndex = 3
	local _xpTrack
	_xpTrack, xpFill = bar(bottom, UDim2.fromOffset(392, 10), UDim2.fromOffset(0, 128), Color3.fromRGB(236, 190, 96))
	levelText = Kit.label(bottom, "", UDim2.fromOffset(392, 18), UDim2.fromOffset(0, 140), 13, Kit.MUTED)
	local dash = Kit.frame(bottom, UDim2.fromOffset(122, 36), UDim2.fromOffset(398, 102), Kit.PANEL)
	Kit.label(dash, "Q  Dash", UDim2.fromScale(1, 1), UDim2.new(), 14)
	dashCd = Kit.frame(dash, UDim2.fromScale(0, 1), UDim2.new(), Color3.new(0, 0, 0))
	dashCd.BackgroundTransparency = 0.4
	dashCd:SetAttribute("NoSkin", true)

	-- Top left: Backpack fullness bar, Banked currencies, Stars, Bounty & War Mode Toggle.
	local loot = Kit.frame(gui, UDim2.fromOffset(365, 86), UDim2.fromOffset(12, 12), Kit.PANEL)
	loot.BackgroundTransparency = 0.15
	local bagTrack
	bagTrack, bagFill = bar(loot, UDim2.new(1, -16, 0, 20), UDim2.fromOffset(8, 8), Color3.fromRGB(130, 185, 115))
	bagText = Kit.label(bagTrack, "", UDim2.fromScale(1, 1), UDim2.new(), 12)
	bagText.ZIndex = 3
	lootText = Kit.label(loot, "", UDim2.new(1, -16, 0, 22), UDim2.fromOffset(8, 32), 13)
	lootText.TextXAlignment = Enum.TextXAlignment.Left
	warBtn = Kit.button(
		loot,
		"🛡 War Mode: OFF (Safe)",
		UDim2.fromOffset(210, 24),
		UDim2.fromOffset(8, 56),
		Kit.PANEL,
		function()
			NetClient.send("TogglePvp")
		end
	)
	warBtn.TextSize = 12

	-- Top right: quest.
	questFrame = Kit.frame(gui, UDim2.fromOffset(310, 74), UDim2.new(1, -12, 0, 12), Kit.PANEL, Vector2.new(1, 0))
	questFrame.BackgroundTransparency = 0.15
	questTitle = Kit.label(questFrame, "", UDim2.new(1, -16, 0, 20), UDim2.fromOffset(8, 4), 14, Kit.GOLD)
	questTitle.TextXAlignment = Enum.TextXAlignment.Left
	questText = Kit.label(questFrame, "", UDim2.new(1, -16, 1, -28), UDim2.fromOffset(8, 24), 14)
	questText.TextXAlignment = Enum.TextXAlignment.Left
	questText.TextYAlignment = Enum.TextYAlignment.Top

	-- Toasts under the boss bar.
	toastList = Instance.new("Frame")
	toastList.BackgroundTransparency = 1
	toastList.Size = UDim2.fromOffset(400, 200)
	toastList.Position = UDim2.new(0.5, 0, 0, 70)
	toastList.AnchorPoint = Vector2.new(0.5, 0)
	toastList.Parent = gui
	Kit.list(toastList, 6)

	-- Recall bar.
	recallFrame =
		Kit.frame(gui, UDim2.fromOffset(260, 40), UDim2.new(0.5, 0, 0.62, 0), Kit.PANEL, Vector2.new(0.5, 0.5))
	recallFrame.Visible = false
	Kit.label(recallFrame, "Recalling to camp…  (R to cancel)", UDim2.new(1, 0, 0, 20), UDim2.fromOffset(0, 2), 14)
	local _recallTrack
	_recallTrack, recallFill =
		bar(recallFrame, UDim2.new(1, -20, 0, 8), UDim2.fromOffset(10, 25), Color3.fromRGB(140, 190, 255))

	-- Controls card, bottom left.
	local help = Kit.frame(gui, UDim2.fromOffset(216, 118), UDim2.new(0, 12, 1, -12), Kit.PANEL, Vector2.new(0, 1))
	help.BackgroundTransparency = 0.25
	local helpText = Kit.label(
		help,
		"<b>Click</b> 4-hit M1 combo\n<b>Z X C V</b> Grimoire skills\n<b>Q</b> dash   <b>1 2 3</b> swap books\n<b>R</b> recall   <b>E</b> interact\nWalk Full Bag to Camp: +15%",
		UDim2.new(1, -16, 1, -8),
		UDim2.fromOffset(8, 4),
		13,
		Kit.MUTED
	)
	helpText.TextXAlignment = Enum.TextXAlignment.Left

	-- Guide line.
	guidePart = Instance.new("Part")
	guidePart.Anchored = true
	guidePart.CanCollide = false
	guidePart.CanQuery = false
	guidePart.Transparency = 1
	guidePart.Size = Vector3.one
	guidePart.Parent = workspace
	guideTo = Instance.new("Attachment")
	guideTo.Parent = guidePart
	guideFrom = Instance.new("Attachment")
	guideFrom.Position = Vector3.new(0, -2.4, 0)
	guideBeam = Instance.new("Beam")
	guideBeam.Attachment0 = guideFrom
	guideBeam.Attachment1 = guideTo
	guideBeam.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140))
	guideBeam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(0.15, 0.45),
		NumberSequenceKeypoint.new(1, 0.6),
	})
	guideBeam.LightEmission = 0.6
	guideBeam.Width0 = 0.6
	guideBeam.Width1 = 0.6
	guideBeam.FaceCamera = true
	guideBeam.Segments = 20
	guideBeam.Enabled = false
	guideBeam.Parent = guidePart
end

function HUDController.Init()
	build()
	StateController.Changed:Connect(function(key: string)
		if key == "books" or key == "equipped" or key == "active" then
			refreshBooks()
		elseif key == "carried" or key == "bank" or key == "stars" or key == "gears" or key == "bounty" then
			refreshLoot()
		elseif key == "level" or key == "xp" then
			refreshLevel()
		end
	end)
	player:GetAttributeChangedSignal("WarMode"):Connect(refreshWarMode)
	NetClient.on("Toast", toast)
	NetClient.on("Quest", function(view: any)
		quest = view
		refreshQuest()
	end)
	NetClient.on("RecallState", function(endsAt: number?, totalSec: number?)
		recallEnds = endsAt
		recallDuration = totalSec or 5
		recallFrame.Visible = endsAt ~= nil
	end)
end

function HUDController.Start()
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			hpFill.Size = UDim2.fromScale(math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1), 1)
			hpText.Text = `{math.ceil(humanoid.Health)} / {math.ceil(humanoid.MaxHealth)}`
		end
		local now = os.clock()
		for _, s in slots do
			local readyAt, duration = CombatController.readyAt(s.key)
			local left = if s.key ~= "" then readyAt - now else 0
			if left > 0 then
				s.cd.Size = UDim2.fromScale(1, math.clamp(left / duration, 0.05, 1))
				s.cdText.Text = string.format("%.1f", left)
			else
				s.cd.Size = UDim2.fromScale(1, 0)
				s.cdText.Text = ""
			end
		end
		local dashReady, dashDur = CombatController.readyAt("dash")
		local dashLeft = dashReady - now
		dashCd.Size = UDim2.fromScale(math.clamp(dashLeft / math.max(1, dashDur), 0, 1), 1)
		if recallEnds then
			local left = recallEnds - workspace:GetServerTimeNow()
			recallFill.Size = UDim2.fromScale(math.clamp(1 - left / recallDuration, 0, 1), 1)
		end
		updateGuide()
	end)
	local function all()
		refreshBooks()
		refreshLoot()
		refreshLevel()
		refreshWarMode()
	end
	if StateController.isLoaded() then
		all()
	end
	StateController.Loaded:Connect(all)
end

return HUDController
