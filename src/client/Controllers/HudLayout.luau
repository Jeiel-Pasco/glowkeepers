--!strict
-- Where the HUD's always-on buttons sit, on every screen size (not a controller: required by
-- the ones that own the buttons).
--
--   left dock    Upgrades, Shop, Storage, Rebirth, Glowdex, Gift, Quests (Admin last)
--   right dock   under the cycle ring: Lock, the shield label, Decor, Store, Trade, Companion
--
-- Each dock is one column (a UIListLayout). When its buttons don't fit the screen's height (a
-- phone in landscape), the dock shrinks with a UIScale, never below MIN_SCALE. Hidden buttons
-- take no room. Panels keep their own places beside the docks.

local Players = game:GetService("Players")

local HudLayout = {}

HudLayout.LEFT_WIDTH = 120
HudLayout.RIGHT_WIDTH = 170
HudLayout.RIGHT_TOP = 112 -- under the cycle ring
HudLayout.GAP = 6

local LEFT_TOP = 56 -- under the top bar
local MIN_SCALE = 0.7

local docks: { [string]: Frame } = {}

local function fit(dock: Frame)
	local scale = dock:FindFirstChildWhichIsA("UIScale") :: UIScale
	local parent = dock.Parent :: ScreenGui
	local available = parent.AbsoluteSize.Y - dock.Position.Y.Offset - 8
	local needed, count = 0, 0
	for _, child in dock:GetChildren() do
		if child:IsA("GuiObject") and child.Visible then
			needed += child.Size.Y.Offset
			count += 1
		end
	end
	needed += math.max(0, count - 1) * HudLayout.GAP
	scale.Scale = if needed > 0 and available > 0 then math.clamp(available / needed, MIN_SCALE, 1) else 1
end

local function dockFor(side: string): Frame
	local existing = docks[side]
	if existing ~= nil then
		return existing
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = `Dock{side}`
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local left = side == "left"
	local dock = Instance.new("Frame")
	dock.Name = "Dock"
	dock.BackgroundTransparency = 1
	dock.AnchorPoint = Vector2.new(if left then 0 else 1, 0)
	dock.Position = if left then UDim2.new(0, 12, 0, LEFT_TOP) else UDim2.new(1, -12, 0, HudLayout.RIGHT_TOP)
	dock.Size = UDim2.new(0, if left then HudLayout.LEFT_WIDTH else HudLayout.RIGHT_WIDTH, 1, -dock.Position.Y.Offset)
	dock.Parent = gui

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, HudLayout.GAP)
	list.HorizontalAlignment = if left then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Right
	list.Parent = dock

	local scale = Instance.new("UIScale")
	scale.Parent = dock

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		fit(dock)
	end)
	dock.ChildAdded:Connect(function(child: Instance)
		if child:IsA("GuiObject") then
			child:GetPropertyChangedSignal("Visible"):Connect(function()
				fit(dock)
			end)
		end
		task.defer(fit, dock)
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	docks[side] = dock
	return dock
end

-- Puts an always-on button (or label) into a dock, `order` from the top.
function HudLayout.dock(side: "left" | "right", object: GuiObject, order: number)
	object.LayoutOrder = order
	object.Parent = dockFor(side)
end

-- Shrinks `object` (centred at the top) so it fits between `reserve` pixels on each side.
function HudLayout.fitWidth(object: GuiObject, reserve: number)
	local scale = object:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale")
	scale.Parent = object
	local function refit()
		local gui = object:FindFirstAncestorWhichIsA("ScreenGui")
		if gui == nil then
			return
		end
		local width = object.AbsoluteSize.X / math.max((scale :: UIScale).Scale, 0.01)
		local available = gui.AbsoluteSize.X - 2 * reserve;
		(scale :: UIScale).Scale = if width > 0 then math.clamp(available / width, MIN_SCALE, 1) else 1
	end
	object:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(refit)
	end)
	object.AncestryChanged:Connect(function()
		task.defer(refit)
	end)
	task.defer(refit)
end

return HudLayout
