--!strict
-- Stalker cues on the client (GAME_SYSTEMS §13, TECH_SPEC §8). Reads the server's `Stalker`
-- model: `State`, `Target` (userId) and `LungeAt` (server time). A dark screen-edge vignette
-- grows while the Stalker stalks this player, peaks at the lunge, and shows faintly whenever it
-- is near. Calm mode (settings.calm) halves it.
--
-- Placeholders for SD/GS: no heartbeat sound yet (it needs the asset), no eye-glint effect.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local economy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("economy")) :: any
local StateController = require(script.Parent:WaitForChild("StateController"))

local NEAR_STUDS = 40 -- the faint cue starts this close
local NEAR_MAX = 0.25
local STALK_FROM = 0.35
local LERP_PER_SECOND = 6
local COLOR = Color3.fromRGB(28, 0, 10)

local StalkerFXController = {}

local stroke: UIStroke? = nil
local shown = 0

local function intensity(now: number): number
	local model = workspace:FindFirstChild("Stalker")
	local body = if model ~= nil then model:FindFirstChild("Body") else nil
	if model == nil or body == nil or not body:IsA("BasePart") then
		return 0
	end
	local value = 0
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root ~= nil and root:IsA("BasePart") then
		local distance = (root.Position - body.Position).Magnitude
		value = NEAR_MAX * math.clamp(1 - distance / NEAR_STUDS, 0, 1)
	end
	if model:GetAttribute("Target") == Players.LocalPlayer.UserId then
		local state = model:GetAttribute("State")
		local lungeAt = model:GetAttribute("LungeAt")
		if state == "Lunge" then
			value = 1
		elseif state == "Stalk" and type(lungeAt) == "number" then
			local progress = 1 - math.clamp((lungeAt - now) / economy.stalker.stalkSeconds, 0, 1)
			value = math.max(value, STALK_FROM + (1 - STALK_FROM) * progress)
		end
	end
	local data = StateController.get()
	if data ~= nil and data.settings ~= nil and data.settings.calm then
		value *= 0.5
	end
	return value
end

function StalkerFXController.Init() end

function StalkerFXController.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "StalkerFX"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -1 -- under the HUD
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Color = COLOR
	edge.Thickness = 90
	edge.Transparency = 1
	edge.Parent = frame
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	stroke = edge

	RunService.RenderStepped:Connect(function(dt: number)
		local goal = intensity(workspace:GetServerTimeNow())
		shown += (goal - shown) * math.min(1, dt * LERP_PER_SECOND)
		local s = stroke
		if s ~= nil then
			s.Transparency = 1 - 0.85 * shown
		end
	end)
end

return StalkerFXController
