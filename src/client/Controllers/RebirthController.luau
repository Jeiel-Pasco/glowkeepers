--!strict
-- The rebirth panel (GAME_SYSTEMS §15). A "Rebirth" button under "Storage" opens the progress
-- toward the next Star (Glow earned since the last rebirth, extrapolated from the Wallet), the
-- exact lists of what is lost and kept, and a hold-to-confirm button. The server checks
-- everything again (RebirthService).
--
-- Placeholder for UI: the panel (artists replace it in Phase 4), and no star-burst yet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local Rebirth = require(Shared:WaitForChild("Rebirth"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local StateController = require(script.Parent:WaitForChild("StateController"))

local PANEL = Color3.fromRGB(20, 24, 40)
local READY = Color3.fromRGB(150, 110, 230)
local DIM = Color3.fromRGB(60, 60, 70)
local HOLD_SECONDS = 2

local LOST = "Lost: Glow, Lantern, Boots, Slots (back to 8), display and storage Glowlings"
local KEPT = "Kept: the vault, your best other Glowling, Embers, Stars, Lock Charges, Glowdex"

local RebirthController = {}

local panel: Frame? = nil
local progress: TextLabel? = nil
local confirm: TextButton? = nil
local holdingSince: number? = nil

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, name: string, y: number, height: number, size: number, text: string): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Position = UDim2.fromOffset(12, y)
	l.Size = UDim2.new(1, -24, 0, height)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = size
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Text = text
	l.Parent = parent
	return l
end

local function refresh()
	local frame, text, button = panel, progress, confirm
	local data = StateController.get()
	if frame == nil or text == nil or button == nil or not frame.Visible or data == nil then
		return
	end
	local stars = data.stars or 0
	local need = Economy.rebirthRequirement(economy, stars)
	local since = StateController.sinceRebirthAt(workspace:GetServerTimeNow())
	local left = Rebirth.remaining(since, need)
	text.Text =
		`Star {stars} → {stars + 1}\n{EconomyMath.formatNumber(math.min(since, need))} / {EconomyMath.formatNumber(
			need
		)} Glow earned`
	local ready = left <= 0
	button.BackgroundColor3 = if ready then READY else DIM
	button.AutoButtonColor = ready
	local held = holdingSince
	if not ready then
		holdingSince = nil
		button.Text = `{EconomyMath.formatNumber(left)} Glow to go`
	elseif held ~= nil then
		local t = os.clock() - held
		if t >= HOLD_SECONDS then
			holdingSince = nil
			NetClient.send("Rebirth")
			frame.Visible = false
		else
			button.Text = string.format("Keep holding… %.1f", HOLD_SECONDS - t)
		end
	else
		button.Text = "Hold to rebirth"
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RebirthGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local toggle = Instance.new("TextButton")
	toggle.Name = "RebirthButton"
	toggle.AnchorPoint = Vector2.new(0, 0.5)
	toggle.Position = UDim2.new(0, 12, 0.5, 144) -- under "Storage"
	toggle.Size = UDim2.fromOffset(120, 40)
	toggle.BackgroundColor3 = PANEL
	toggle.BackgroundTransparency = 0.15
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 17
	toggle.TextColor3 = Color3.fromRGB(200, 170, 255)
	toggle.Text = "Rebirth"
	corner(toggle, 10)
	toggle.Parent = gui

	local frame = Instance.new("Frame")
	frame.Name = "Rebirth"
	frame.AnchorPoint = Vector2.new(0, 0.5)
	frame.Position = UDim2.new(0, 140, 0.5, 0)
	frame.Size = UDim2.fromOffset(340, 236)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.1
	frame.Visible = false
	corner(frame, 12)
	frame.Parent = gui
	panel = frame

	progress = label(frame, "Progress", 10, 44, 16, "")
	label(frame, "Gain", 58, 20, 14, "+1 Star: +35% income, +6% luck, +1 vault slot").TextColor3 =
		Color3.fromRGB(255, 221, 120)
	label(frame, "Lost", 82, 38, 13, LOST).TextColor3 = Color3.fromRGB(255, 140, 120)
	label(frame, "Kept", 122, 38, 13, KEPT).TextColor3 = Color3.fromRGB(150, 230, 160)

	local button = Instance.new("TextButton")
	button.Name = "Confirm"
	button.Position = UDim2.new(0, 12, 1, -58)
	button.Size = UDim2.new(1, -24, 0, 46)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 17
	button.TextColor3 = Color3.new(1, 1, 1)
	corner(button, 10)
	button.Parent = frame
	confirm = button
	button.MouseButton1Down:Connect(function()
		holdingSince = os.clock()
	end)
	local function letGo()
		holdingSince = nil
	end
	button.MouseButton1Up:Connect(letGo)
	button.MouseLeave:Connect(letGo)

	toggle.Activated:Connect(function()
		frame.Visible = not frame.Visible
		holdingSince = nil
		-- One panel at a time: close the others when this one opens.
		if frame.Visible then
			for _, pair in { { "UpgradeGui", "Upgrades" }, { "ShopGui", "Shop" }, { "StorageGui", "Storage" } } do
				local other = gui.Parent and gui.Parent:FindFirstChild(pair[1])
				local otherPanel = other and other:FindFirstChild(pair[2])
				if otherPanel ~= nil and otherPanel:IsA("GuiObject") then
					otherPanel.Visible = false
				end
			end
		end
		refresh()
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function RebirthController.Init() end

function RebirthController.Start()
	build()
	RunService.Heartbeat:Connect(refresh)
end

return RebirthController
