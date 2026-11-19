--!strict
-- New-player shield on the client (GAME_SYSTEMS §11). Shows "Protected · N min" under the Lock
-- button while the Player attribute `Shielded` is set (`ShieldEndsAt` is when it ends if they
-- stay online). Before a shielded player's grab, StealController asks allowGrab(): it opens
-- "This ends your protection. Steal anyway?"; yes sends DropShield, and the next hold steals.
-- PlotController draws the bubble over shielded plots.
--
-- Placeholders for UI: the label and the dialog (artists replace them in Phase 3).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))

local PANEL = Color3.fromRGB(20, 24, 40)
local SHIELD_COLOR = Color3.fromRGB(150, 220, 255)

local ShieldController = {}

local label: TextLabel? = nil
local dialog: Frame? = nil

local function shielded(): boolean
	return Players.LocalPlayer:GetAttribute("Shielded") == true
end

-- True when a grab may start now. A shielded player gets the confirm dialog instead.
function ShieldController.allowGrab(): boolean
	if not shielded() then
		return true
	end
	local frame = dialog
	if frame ~= nil then
		frame.Visible = true
	end
	return false
end

local function corner(parent: Instance)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = parent
end

local function button(text: string, color: Color3, x: number, parent: Instance): TextButton
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(x, 0, 1, -14)
	b.Size = UDim2.fromOffset(150, 40)
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextSize = 18
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	corner(b)
	b.Parent = parent
	return b
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShieldGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local status = Instance.new("TextLabel")
	status.Name = "Protected"
	status.AnchorPoint = Vector2.new(1, 0)
	status.Position = UDim2.new(1, -12, 0, 158) -- under the Lock button
	status.Size = UDim2.fromOffset(170, 30)
	status.BackgroundColor3 = PANEL
	status.BackgroundTransparency = 0.35
	status.Font = Enum.Font.GothamBold
	status.TextSize = 16
	status.TextColor3 = SHIELD_COLOR
	status.Visible = false
	corner(status)
	status.Parent = gui
	label = status

	local frame = Instance.new("Frame")
	frame.Name = "Confirm"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(360, 150)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.1
	frame.Visible = false
	corner(frame)
	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, -24, 0, 80)
	text.Position = UDim2.fromOffset(12, 6)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = 20
	text.TextWrapped = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Text = "This ends your protection. Steal anyway?"
	text.Parent = frame
	local yes = button("Steal anyway", Color3.fromRGB(200, 80, 60), 0.27, frame)
	yes.Name = "Yes"
	local no = button("Keep it", Color3.fromRGB(70, 140, 220), 0.73, frame)
	no.Name = "No"
	yes.Activated:Connect(function()
		frame.Visible = false
		NetClient.send("DropShield")
	end)
	no.Activated:Connect(function()
		frame.Visible = false
	end)
	frame.Parent = gui
	dialog = frame

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function refresh()
	local status = label
	if status == nil then
		return
	end
	local endsAt = Players.LocalPlayer:GetAttribute("ShieldEndsAt")
	if not shielded() or type(endsAt) ~= "number" then
		status.Visible = false
		if dialog ~= nil then
			dialog.Visible = false
		end
		return
	end
	local left = math.max(0, endsAt - workspace:GetServerTimeNow())
	status.Text = if left >= 60 then `Protected · {math.ceil(left / 60)} min` else `Protected · {math.ceil(left)} s`
	status.Visible = true
end

function ShieldController.Init() end

function ShieldController.Start()
	build()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= 0.5 then
			elapsed = 0
			refresh()
		end
	end)
end

return ShieldController
