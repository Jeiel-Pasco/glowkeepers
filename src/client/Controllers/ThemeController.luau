--!strict
-- Skins every screen in PlayerGui with one look (Shared.UIStyle), so each controller can keep
-- building plain Frames and TextButtons:
--   - bold Gotham text becomes Fredoka One (titles, numbers, buttons); body text stays Gotham
--   - dark panels turn warm plum with a thin lantern-gold rim and a soft top sheen
--   - coloured buttons keep their colour and get a darker rim and the same sheen
--   - buttons dip to 94% when pressed
-- An element (and everything under it) with the attribute `NoSkin` is left alone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIStyle = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UIStyle"))

local MIN_SIZE = 20 -- pixels: smaller things (ring dots, swatches) are left alone
local BOLD = {
	[Enum.Font.GothamBold] = true,
	[Enum.Font.GothamBlack] = true,
}
local PRESS = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local ThemeController = {}

local function rgb(c: Color3): UIStyle.RGB
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

local function c3(v: UIStyle.RGB): Color3
	return Color3.fromRGB(v[1], v[2], v[3])
end

local function skipped(object: Instance): boolean
	local at: Instance? = object
	while at ~= nil and not at:IsA("PlayerGui") do
		if at:GetAttribute("NoSkin") ~= nil or at:IsA("SurfaceGui") or at:IsA("BillboardGui") then
			return true -- world boards and name tags keep their own look
		end
		at = at.Parent
	end
	return false
end

local function font(object: TextLabel | TextButton | TextBox)
	if BOLD[object.Font] then
		object.Font = Enum.Font.FredokaOne
	end
end

local function surface(object: GuiObject)
	local size = object.AbsoluteSize
	if object.BackgroundTransparency >= 0.9 or size.X < MIN_SIZE or size.Y < MIN_SIZE then
		return
	end
	local skin = UIStyle.skin(rgb(object.BackgroundColor3))
	object.BackgroundColor3 = c3(skin.fill)

	local stroke = object:FindFirstChild("SkinRim") :: UIStroke?
	if stroke == nil then
		local s = Instance.new("UIStroke")
		s.Name = "SkinRim"
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Thickness = UIStyle.RIM_THICKNESS
		s.Parent = object
		stroke = s
	end
	local rim = stroke :: UIStroke
	rim.Color = c3(skin.rim)
	rim.Transparency = skin.rimTransparency

	if object:FindFirstChildWhichIsA("UIGradient") == nil then
		local sheen = Instance.new("UIGradient")
		sheen.Name = "SkinSheen"
		sheen.Rotation = 90
		local top = Color3.new(1, 1, 1)
		local bottom = Color3.new(1 - UIStyle.SHEEN, 1 - UIStyle.SHEEN, 1 - UIStyle.SHEEN)
		sheen.Color = ColorSequence.new(top, bottom)
		sheen.Parent = object
	end
end

local function press(button: GuiButton)
	local scale = Instance.new("UIScale")
	scale.Name = "SkinPress"
	scale.Parent = button
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, PRESS, { Scale = UIStyle.PRESS_SCALE }):Play()
	end)
	local function release()
		TweenService:Create(scale, RELEASE, { Scale = 1 }):Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
end

local function skin(object: Instance)
	if not object:IsA("GuiObject") or object:GetAttribute("Skinned") or skipped(object) then
		return
	end
	object:SetAttribute("Skinned", true)
	if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
		font(object)
	end
	if object:IsA("GuiButton") and object:FindFirstChildWhichIsA("UIScale") == nil then
		press(object)
	end
	surface(object)
	-- A controller may recolour it later (a chosen row, a low fire): skin the new colour too.
	local busy = false
	object:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		if busy then
			return
		end
		busy = true
		surface(object)
		busy = false
	end)
	object:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if object:FindFirstChild("SkinRim") == nil then
			surface(object) -- laid out after it was added (AutomaticSize, a hidden panel)
		end
	end)
end

function ThemeController.Init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, object in playerGui:GetDescendants() do
		task.defer(skin, object)
	end
	playerGui.DescendantAdded:Connect(function(object: Instance)
		task.defer(skin, object) -- after the controller has set its colours
	end)
end

return ThemeController
