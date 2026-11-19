--!strict
-- The offline-earnings popup (GAME_SYSTEMS §6). The server pays on join and sends
-- OfflineEarnings (amount, seconds away) once this client is ready: "While you were away your
-- Glowlings made 1.2M Glow". The Wallet already includes the payout.
--
-- Placeholder for UI: the panel (artists replace it in Phase 3).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))

local PANEL = Color3.fromRGB(20, 24, 40)
local GLOW = Color3.fromRGB(255, 221, 120)

local OfflineController = {}

-- "3 h 20 min", "12 min", "40 s"
local function awayText(seconds: number): string
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	if hours > 0 then
		return if minutes > 0 then `{hours} h {minutes} min` else `{hours} h`
	elseif minutes > 0 then
		return `{minutes} min`
	end
	return `{math.floor(seconds)} s`
end

local function show(amount: number, away: number)
	local gui = Instance.new("ScreenGui")
	gui.Name = "OfflinePopup"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(380, 190)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.05
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame
	frame.Parent = gui

	local text = Instance.new("TextLabel")
	text.Name = "Message"
	text.Position = UDim2.fromOffset(16, 12)
	text.Size = UDim2.new(1, -32, 0, 90)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = 22
	text.TextWrapped = true
	text.TextColor3 = GLOW
	text.Text = `While you were away your Glowlings made {EconomyMath.formatNumber(amount)} Glow`
	text.Parent = frame

	local capped = away >= economy.income.offlineCapHours * 3600
	local detail = Instance.new("TextLabel")
	detail.Name = "Away"
	detail.Position = UDim2.fromOffset(16, 100)
	detail.Size = UDim2.new(1, -32, 0, 22)
	detail.BackgroundTransparency = 1
	detail.Font = Enum.Font.Gotham
	detail.TextSize = 16
	detail.TextColor3 = Color3.fromRGB(200, 205, 220)
	detail.Text = if capped
		then `Away {awayText(away)} (pays up to {economy.income.offlineCapHours} h)`
		else `Away {awayText(away)}`
	detail.Parent = frame

	local ok = Instance.new("TextButton")
	ok.Name = "Collect"
	ok.AnchorPoint = Vector2.new(0.5, 1)
	ok.Position = UDim2.new(0.5, 0, 1, -14)
	ok.Size = UDim2.fromOffset(160, 40)
	ok.BackgroundColor3 = Color3.fromRGB(70, 140, 220)
	ok.Font = Enum.Font.GothamBold
	ok.TextSize = 18
	ok.TextColor3 = Color3.new(1, 1, 1)
	ok.Text = "Nice!"
	local okCorner = Instance.new("UICorner")
	okCorner.CornerRadius = UDim.new(0, 10)
	okCorner.Parent = ok
	ok.Parent = frame
	ok.Activated:Connect(function()
		gui:Destroy()
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function OfflineController.Init()
	NetClient.on("OfflineEarnings", function(amount: number, away: number)
		show(amount, away)
	end)
end

function OfflineController.Start() end

return OfflineController
