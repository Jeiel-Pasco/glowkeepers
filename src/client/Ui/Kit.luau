--!strict
-- Small builders for the slice's screens. ThemeController skins whatever these make (rims,
-- sheen, press scale, fonts), so they only set layout and colour.

local Players = game:GetService("Players")

local Kit = {}

Kit.PANEL = Color3.fromRGB(30, 24, 44)
Kit.PANEL_LIGHT = Color3.fromRGB(48, 40, 66)
Kit.TEXT = Color3.fromRGB(244, 236, 220)
Kit.MUTED = Color3.fromRGB(170, 160, 180)
Kit.GOLD = Color3.fromRGB(236, 190, 96)
Kit.GOOD = Color3.fromRGB(110, 190, 110)
Kit.BAD = Color3.fromRGB(210, 90, 80)

function Kit.rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

function Kit.screen(name: string, order: number?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = order or 0
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

function Kit.corner(object: GuiObject, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = object
end

function Kit.frame(parent: Instance, size: UDim2, position: UDim2, color: Color3?, anchor: Vector2?): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = position
	f.AnchorPoint = anchor or Vector2.zero
	f.BackgroundColor3 = color or Kit.PANEL
	f.BorderSizePixel = 0
	f.Parent = parent
	Kit.corner(f)
	return f
end

function Kit.label(
	parent: Instance,
	text: string,
	size: UDim2,
	position: UDim2,
	textSize: number?,
	color: Color3?
): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color or Kit.TEXT
	l.Font = Enum.Font.GothamBold
	l.TextSize = textSize or 16
	l.TextWrapped = true
	l.RichText = true
	l.Parent = parent
	return l
end

function Kit.button(
	parent: Instance,
	text: string,
	size: UDim2,
	position: UDim2,
	color: Color3?,
	onClick: (() -> ())?
): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = color or Kit.PANEL_LIGHT
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Text = text
	b.TextColor3 = Kit.TEXT
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.TextWrapped = true
	b.RichText = true
	b.Parent = parent
	Kit.corner(b, 8)
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

function Kit.list(parent: Instance, padding: number, horizontal: boolean?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, padding)
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.Parent = parent
	return l
end

function Kit.clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- A modal panel in the middle of the screen with a title and a close button.
function Kit.panel(gui: ScreenGui, title: string, size: Vector2, onClose: () -> ()): (Frame, Frame)
	local panel =
		Kit.frame(gui, UDim2.fromOffset(size.X, size.Y), UDim2.fromScale(0.5, 0.5), Kit.PANEL, Vector2.new(0.5, 0.5))
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(size.X, size.Y)
	constraint.Parent = panel
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local camera = workspace.CurrentCamera
	local function fit()
		local view = camera.ViewportSize
		scale.Scale = math.min(1, (view.X - 32) / size.X, (view.Y - 80) / size.Y)
	end
	fit()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	Kit.label(panel, title, UDim2.new(1, -80, 0, 40), UDim2.fromOffset(20, 8), 24, Kit.GOLD).TextXAlignment =
		Enum.TextXAlignment.Left
	Kit.button(panel, "✕", UDim2.fromOffset(36, 36), UDim2.new(1, -46, 0, 10), Kit.PANEL_LIGHT, onClose)
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, -32, 1, -64)
	body.Position = UDim2.fromOffset(16, 54)
	body.Parent = panel
	return panel, body
end

return Kit
