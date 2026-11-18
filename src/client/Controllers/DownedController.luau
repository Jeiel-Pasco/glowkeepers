--!strict
-- Downed and revive on the client (GAME_SYSTEMS §14). At night, next to a downed teammate,
-- the context button says "Revive": holding it sends ReviveStart, letting go sends
-- ReviveCancel. The server times the hold; the bar only follows the character's `ReviveUntil`.
-- Downed players are tinted and seen through walls, so teammates can find them; wisps are
-- see-through. The local player sees their bleed-out countdown, and after a revive by someone
-- who isn't a friend yet, Roblox's friend request prompt.
--
-- Placeholders for GS: the tint, the wisp look, the status label and the hold bar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))
local InputController = require(script.Parent:WaitForChild("InputController"))
local CycleFXController = require(script.Parent:WaitForChild("CycleFXController"))

local REVIVE = "Revive"
local PRIORITY = 40 -- a teammate's life comes before everything else
local CHECK_SECONDS = 0.15
local MARGIN = 1 -- studs inside the server's range, so the button never shows where the server says no
local DOWNED_FILL = Color3.fromRGB(25, 35, 80)
local DOWNED_OUTLINE = Color3.fromRGB(140, 180, 255)
local WISP_TRANSPARENCY = 0.75

local DownedController = {}

local target: Player? = nil
local holdStartedAt: number? = nil -- when this client first saw the current hold, for the bar
local bar: Frame? = nil
local fill: Frame? = nil
local status: TextLabel? = nil
local faded: { [Model]: boolean } = {} -- wisp characters this client made see-through

local function rootOf(character: Model?): BasePart?
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local function nearestDowned(position: Vector3): Player?
	local best: Player?, bestDistance = nil, economy.revive.range - MARGIN
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = rootOf(character)
		if player ~= Players.LocalPlayer and character ~= nil and root ~= nil then
			local distance = (root.Position - position).Magnitude
			if character:GetAttribute("Life") == "downed" and distance <= bestDistance then
				best, bestDistance = player, distance
			end
		end
	end
	return best
end

local function updateContext(character: Model?)
	local label: string? = nil
	target = nil
	local root = rootOf(character)
	local state = CycleFXController.state()
	if character ~= nil and root ~= nil then
		if character:GetAttribute("ReviveUntil") ~= nil then
			label = REVIVE -- keep the button while holding, so letting go still reaches us
		elseif state ~= nil and state.phase == "Night" and character:GetAttribute("Life") == nil then
			target = nearestDowned(root.Position)
			if target ~= nil then
				label = REVIVE
			end
		end
	end
	InputController.offer("Downed", label, PRIORITY)
end

local function setFaded(character: Model, on: boolean)
	if (faded[character] == true) == on then
		return
	end
	faded[character] = if on then true else nil
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") or part:IsA("Decal") then
			part.LocalTransparencyModifier = if on then WISP_TRANSPARENCY else 0
		end
	end
end

local function updateLooks()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character == nil then
			continue
		end
		local state = character:GetAttribute("Life")
		local mark = character:FindFirstChild("DownedMark")
		if state == "downed" then
			if mark == nil then
				local highlight = Instance.new("Highlight")
				highlight.Name = "DownedMark"
				highlight.FillColor = DOWNED_FILL
				highlight.OutlineColor = DOWNED_OUTLINE
				highlight.FillTransparency = 0.25
				highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				highlight.Parent = character
			end
		elseif mark ~= nil then
			mark:Destroy()
		end
		setFaded(character, state == "wisp")
	end
	for character in faded do
		if character.Parent == nil then
			faded[character] = nil
		end
	end
end

local function updateHud(character: Model?)
	local now = workspace:GetServerTimeNow()
	local holdBar, holdFill = bar, fill
	local untilTime = if character then character:GetAttribute("ReviveUntil") else nil
	if holdBar ~= nil and holdFill ~= nil then
		if type(untilTime) == "number" then
			local started = holdStartedAt or now
			holdStartedAt = started
			holdFill.Size = UDim2.fromScale(math.clamp((now - started) / math.max(untilTime - started, 0.01), 0, 1), 1)
			holdBar.Visible = true
		else
			holdStartedAt = nil
			holdBar.Visible = false
		end
	end
	local label = status
	if label == nil then
		return
	end
	local state = if character then character:GetAttribute("Life") else nil
	local bleed = if character then character:GetAttribute("BleedUntil") else nil
	if state == "downed" then
		label.Text = if type(bleed) == "number"
			then `Downed! {math.max(0, math.ceil(bleed - now))} s until you fade. A teammate can revive you`
			else "Being revived…"
		label.Visible = true
	elseif state == "wisp" then
		label.Text = "You're a wisp until dawn"
		label.Visible = true
	else
		label.Visible = false
	end
end

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Downed"
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local holdBar = Instance.new("Frame")
	holdBar.Name = "HoldBar"
	holdBar.AnchorPoint = Vector2.new(0.5, 1)
	holdBar.Position = UDim2.new(0.5, 0, 1, -140)
	holdBar.Size = UDim2.fromOffset(220, 14)
	holdBar.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	holdBar.BorderSizePixel = 0
	holdBar.Visible = false
	holdBar.Parent = gui
	local holdFill = Instance.new("Frame")
	holdFill.Name = "Fill"
	holdFill.Size = UDim2.fromScale(0, 1)
	holdFill.BackgroundColor3 = DOWNED_OUTLINE
	holdFill.BorderSizePixel = 0
	holdFill.Parent = holdBar

	local label = Instance.new("TextLabel")
	label.Name = "Status"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -170)
	label.Size = UDim2.new(1, -32, 0, 30)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 22
	label.TextColor3 = DOWNED_OUTLINE
	label.TextStrokeTransparency = 0.4
	label.TextWrapped = true
	label.Visible = false
	label.Parent = gui

	bar, fill, status = holdBar, holdFill, label
end

-- Offer a friend request to whoever revived us, unless we're friends already.
local function offerFriend(userId: number)
	local other = Players:GetPlayerByUserId(userId)
	if other == nil or userId <= 0 or Players.LocalPlayer.UserId <= 0 then
		return -- Studio test players are guests, and guests can't send friend requests
	end
	local ok, friends = pcall(Players.LocalPlayer.IsFriendsWith, Players.LocalPlayer, userId)
	if ok and not friends then
		pcall(StarterGui.SetCore, StarterGui, "PromptSendFriendRequest", other)
	end
end

function DownedController.Start()
	buildGui()

	InputController.Action:Connect(function(label: string, began: boolean)
		if label ~= REVIVE then
			return
		end
		local downed = target
		if began and downed ~= nil then
			NetClient.send("ReviveStart", downed.UserId)
		elseif not began then
			NetClient.send("ReviveCancel")
		end
	end)
	NetClient.on("Revived", function(byUserId: number)
		task.spawn(offerFriend, byUserId) -- IsFriendsWith yields
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		local character = Players.LocalPlayer.Character
		updateHud(character)
		elapsed += dt
		if elapsed < CHECK_SECONDS then
			return
		end
		elapsed = 0
		updateContext(character)
		updateLooks()
	end)
end

return DownedController
