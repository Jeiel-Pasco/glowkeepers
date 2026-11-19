--!strict
-- The daily gift panel (GAME_SYSTEMS §19). A "Gift" button under "Glowdex" reads "Gift!" when
-- today's step is ready. The panel shows the step (Day N of 28), its reward and Claim, or the
-- time until the next UTC day. The server checks the claim again (DailyGiftService).
--
-- Placeholder for UI: the panel (artists replace it in Phase 4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gift = require(Shared:WaitForChild("Gift"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local StateController = require(script.Parent:WaitForChild("StateController"))

local PANEL = Color3.fromRGB(20, 24, 40)
local READY = Color3.fromRGB(90, 170, 110)
local DIM = Color3.fromRGB(60, 60, 70)

local HudLayout = require(script.Parent:WaitForChild("HudLayout"))

local GiftController = {}

local toggle: TextButton? = nil
local panel: Frame? = nil
local info: TextLabel? = nil
local claim: TextButton? = nil

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function describe(reward: any): string
	if reward.kind == "embers" then
		return `{reward.amount} Embers`
	elseif reward.kind == "lure" then
		return `A {economy.rarities[reward.floor].id} lure`
	elseif reward.kind == "lockCharge" then
		return `{reward.amount} Lock Charge{if reward.amount == 1 then "" else "s"}`
	end
	return "An exclusive decoration"
end

local function refresh()
	local button, frame, text, claimButton = toggle, panel, info, claim
	local data = StateController.get()
	if button == nil or frame == nil or text == nil or claimButton == nil or data == nil or data.gift == nil then
		return
	end
	local now = math.floor(workspace:GetServerTimeNow())
	local ready = Gift.canClaim(data.gift, Gift.day(now))
	button.Text = if ready then "Gift!" else "Gift"
	if not frame.Visible then
		return
	end
	local step, reward = Gift.next(economy, data.gift)
	if ready then
		text.Text = `Day {step} of {#economy.gift.steps}\n{describe(reward)}`
		claimButton.Text = "Claim"
	else
		local left = Gift.secondsToNextDay(now)
		text.Text = `Day {step} of {#economy.gift.steps} tomorrow\n{describe(reward)}`
		claimButton.Text = string.format("Next in %d:%02d", left // 3600, left % 3600 // 60)
	end
	claimButton.BackgroundColor3 = if ready then READY else DIM
	claimButton.AutoButtonColor = ready
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "GiftGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local button = Instance.new("TextButton")
	button.Name = "GiftButton"
	button.Size = UDim2.fromOffset(120, 40)
	button.BackgroundColor3 = PANEL
	button.BackgroundTransparency = 0.15
	button.Font = Enum.Font.GothamBold
	button.TextSize = 17
	button.TextColor3 = Color3.fromRGB(255, 190, 120)
	button.Text = "Gift"
	corner(button, 10)
	HudLayout.dock("left", button, 6)
	toggle = button

	local frame = Instance.new("Frame")
	frame.Name = "Gift"
	frame.AnchorPoint = Vector2.new(0, 0.5)
	frame.Position = UDim2.new(0, 140, 0.5, 0)
	frame.Size = UDim2.fromOffset(260, 130)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.1
	frame.Visible = false
	corner(frame, 12)
	frame.Parent = gui
	panel = frame

	local text = Instance.new("TextLabel")
	text.Name = "Info"
	text.Position = UDim2.fromOffset(12, 10)
	text.Size = UDim2.new(1, -24, 0, 50)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = 16
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Parent = frame
	info = text

	local claimButton = Instance.new("TextButton")
	claimButton.Name = "Claim"
	claimButton.Position = UDim2.new(0, 12, 1, -54)
	claimButton.Size = UDim2.new(1, -24, 0, 42)
	claimButton.Font = Enum.Font.GothamBold
	claimButton.TextSize = 17
	claimButton.TextColor3 = Color3.new(1, 1, 1)
	corner(claimButton, 10)
	claimButton.Parent = frame
	claim = claimButton
	claimButton.Activated:Connect(function()
		NetClient.send("Claim", "gift", "today")
	end)

	button.Activated:Connect(function()
		frame.Visible = not frame.Visible
		-- One panel at a time: close the others when this one opens.
		if frame.Visible then
			local others = {
				{ "UpgradeGui", "Upgrades" },
				{ "ShopGui", "Shop" },
				{ "StorageGui", "Storage" },
				{ "RebirthGui", "Rebirth" },
				{ "GlowdexGui", "Glowdex" },
			}
			for _, pair in others do
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

function GiftController.Init() end

function GiftController.Start()
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

return GiftController
