--!strict
-- Enemies on the client: name, level and health over each one, the boss bar, and a little life
-- in their bodies: a bob while idle, a waddle while walking, a lean back on wind-up (with a red
-- flash, the cue to dodge) and a lunge on the strike. All local, through each rig's BodyWeld.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Client = script.Parent.Parent
local Element = require(Shared:WaitForChild("Element")) :: any
local NetClient = require(Client:WaitForChild("Net"):WaitForChild("NetClient"))
local Kit = require(Client:WaitForChild("Ui"):WaitForChild("Kit"))

local EnemyController = {}

type Tracked = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	weld: Weld?,
	bar: Frame,
	fill: Frame,
	windupUntil: number,
	windupLength: number,
	lungeUntil: number,
	phase: number,
	highlight: Highlight?,
	boss: boolean,
}

local tracked: { [Model]: Tracked } = {}
local bossGui: ScreenGui
local bossFrame: Frame
local bossFill: Frame
local bossLabel: TextLabel
local player = Players.LocalPlayer

local function track(model: Instance)
	if not model:IsA("Model") or tracked[model] then
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 5)
	local humanoid = model:WaitForChild("Humanoid", 5)
	if root == nil or humanoid == nil or not root:IsA("BasePart") or not humanoid:IsA("Humanoid") then
		return
	end
	local boss = model:GetAttribute("Boss") == true
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(if boss then 200 else 130, 38)
	gui.StudsOffsetWorldSpace =
		Vector3.new(0, root.Size.Y / 2 + (humanoid :: Humanoid).HipHeight * 0.4 + (if boss then 6 else 3), 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = if boss then 200 else 110
	gui.Adornee = root
	local kind = model:GetAttribute("Type") or "Neutral"
	local color = Element.COLOR[kind] or Element.COLOR.Neutral
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0, 18)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextStrokeTransparency = 0.4
	name.TextColor3 = Color3.fromRGB(255, 240, 220)
	name.Text = `{model:GetAttribute("Name") or model.Name}  Lv {model:GetAttribute("Level") or 1}`
	name.Parent = gui
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 10)
	bar.Position = UDim2.fromOffset(0, 22)
	bar.BackgroundColor3 = Color3.fromRGB(30, 24, 30)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	Kit.corner(bar, 4)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(color[1], color[2], color[3])
	fill.BorderSizePixel = 0
	fill.Parent = bar
	Kit.corner(fill, 4)
	gui.Parent = root
	local weld = root:FindFirstChild("BodyWeld")
	tracked[model] = {
		model = model,
		root = root,
		humanoid = humanoid :: Humanoid,
		weld = if weld and weld:IsA("Weld") then weld else nil,
		bar = bar,
		fill = fill,
		windupUntil = 0,
		windupLength = 1,
		lungeUntil = 0,
		phase = math.random() * 10,
		boss = boss,
	}
end

local function onFx(kind: string, model: any, a: any, _b: any)
	if kind ~= "windup" and kind ~= "slash" then
		return
	end
	local t = tracked[model]
	if t == nil then
		return
	end
	if kind == "windup" then
		t.windupLength = a
		t.windupUntil = os.clock() + a
		if t.highlight == nil then
			local h = Instance.new("Highlight")
			h.FillColor = Color3.fromRGB(255, 60, 40)
			h.OutlineTransparency = 1
			h.FillTransparency = 1
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Parent = t.model
			t.highlight = h
		end
	else
		t.lungeUntil = os.clock() + 0.18
	end
end

local function animate(t: Tracked, now: number)
	local weld = t.weld
	if weld == nil then
		return
	end
	local speed = t.root.AssemblyLinearVelocity.Magnitude
	local moving = speed > 1
	local cf
	if t.highlight and now >= t.windupUntil then
		t.highlight.FillTransparency = 1
	end
	if now < t.windupUntil then
		local p = 1 - (t.windupUntil - now) / t.windupLength
		cf = CFrame.new(0, -0.15 * p, 0.3 * p) * CFrame.Angles(-0.35 * p, 0, 0)
		if t.highlight then
			t.highlight.FillTransparency = 1 - 0.55 * p
		end
	elseif now < t.lungeUntil then
		cf = CFrame.new(0, 0, -0.8) * CFrame.Angles(0.3, 0, 0)
	elseif moving then
		local w = now * 10 + t.phase
		cf = CFrame.new(0, math.abs(math.sin(w)) * 0.35, 0) * CFrame.Angles(0, 0, math.sin(w) * 0.12)
	else
		local w = now * 2.2 + t.phase
		cf = CFrame.new(0, math.sin(w) * 0.12, 0)
	end
	weld.C0 = cf
	local ratio = math.clamp(t.humanoid.Health / math.max(1, t.humanoid.MaxHealth), 0, 1)
	t.fill.Size = UDim2.fromScale(ratio, 1)
end

function EnemyController.Init()
	bossGui = Kit.screen("BossBar", 2)
	bossFrame = Kit.frame(bossGui, UDim2.fromOffset(420, 46), UDim2.new(0.5, 0, 0, 12), Kit.PANEL, Vector2.new(0.5, 0))
	bossFrame.Visible = false
	bossLabel = Kit.label(bossFrame, "", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 2), 16, Kit.GOLD)
	local bossTrack =
		Kit.frame(bossFrame, UDim2.new(1, -20, 0, 14), UDim2.fromOffset(10, 25), Color3.fromRGB(20, 16, 20))
	bossTrack:SetAttribute("NoSkin", true)
	bossFill = Kit.frame(bossTrack, UDim2.fromScale(1, 1), UDim2.new(), Color3.fromRGB(230, 90, 50))
	bossFill:SetAttribute("NoSkin", true)
	NetClient.on("Fx", onFx)
end

function EnemyController.Start()
	local folder = workspace:WaitForChild("Enemies")
	for _, model in folder:GetChildren() do
		task.spawn(track, model)
	end
	folder.ChildAdded:Connect(function(model)
		task.spawn(track, model)
	end)
	folder.ChildRemoved:Connect(function(model)
		tracked[model :: Model] = nil
	end)
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local character = player.Character
		local me = character and character:FindFirstChild("HumanoidRootPart")
		local nearestBoss: Tracked? = nil
		local nearestD = 120
		for model, t in tracked do
			if model.Parent == nil then
				tracked[model] = nil
				continue
			end
			animate(t, now)
			if t.boss and me and me:IsA("BasePart") and t.humanoid.Health > 0 then
				local d = (t.root.Position - me.Position).Magnitude
				if d < nearestD then
					nearestBoss, nearestD = t, d
				end
			end
		end
		if nearestBoss then
			bossFrame.Visible = true
			bossLabel.Text =
				`{nearestBoss.model:GetAttribute("Name")}  Lv {nearestBoss.model:GetAttribute("Level")}  ·  {math.ceil(
					nearestBoss.humanoid.Health
				)} / {math.ceil(nearestBoss.humanoid.MaxHealth)}`
			bossFill.Size =
				UDim2.fromScale(math.clamp(nearestBoss.humanoid.Health / nearestBoss.humanoid.MaxHealth, 0, 1), 1)
		else
			bossFrame.Visible = false
		end
	end)
end

return EnemyController
