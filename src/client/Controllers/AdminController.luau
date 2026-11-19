--!strict
-- The admin panel (TECH_SPEC §13). Only for players the server marked IsAdmin: an "Admin"
-- button bottom-left opens a panel with a command row, a target user id, an argument box,
-- Run, and the server's answer (AdminResult). The server checks everything again
-- (AdminService, Server.Admin.Commands). Placeholder UI.

local Players = game:GetService("Players")

local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))

local PANEL = Color3.fromRGB(30, 18, 24)
local DIM = Color3.fromRGB(70, 50, 60)
local PICKED = Color3.fromRGB(190, 90, 90)

local COMMANDS = {
	{ "lookup", "" },
	{ "flags", "" },
	{ "embers", "<amount> <reason>" },
	{ "glowling", "<species> <rarity 1-7> <reason>" },
	{ "kick", "<reason>" },
	{ "ban", "<days | -1 | next> <reason>" },
	{ "unban", "" },
	{ "erase", "<request id>" },
	{ "versions", "[unix time]" },
	{ "rollback", "<unix time> <reason>" },
	{ "live_get", "" },
	{ "live_set", "<json>" },
	{ "live_confirm", "" },
}

local AdminController = {}

local output: TextLabel? = nil

local function box(parent: Instance, name: string, placeholder: string, pos: UDim2, size: UDim2): TextBox
	local b = Instance.new("TextBox")
	b.Name = name
	b.PlaceholderText = placeholder
	b.Text = ""
	b.ClearTextOnFocus = false
	b.Font = Enum.Font.Gotham
	b.TextSize = 13
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = DIM
	b.Position = pos
	b.Size = size
	b.Parent = parent
	return b
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "AdminGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local toggle = Instance.new("TextButton")
	toggle.Name = "AdminButton"
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 12, 1, -12)
	toggle.Size = UDim2.fromOffset(80, 30)
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 14
	toggle.TextColor3 = Color3.new(1, 1, 1)
	toggle.BackgroundColor3 = PICKED
	toggle.Text = "Admin"
	toggle.Parent = gui

	local frame = Instance.new("Frame")
	frame.Name = "Admin"
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.new(0, 12, 1, -50)
	frame.Size = UDim2.fromOffset(460, 330)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.05
	frame.Visible = false
	frame.Parent = gui

	local chosen = COMMANDS[1][1]
	local buttons: { [string]: TextButton } = {}
	local arg = box(frame, "Arg", "", UDim2.fromOffset(150, 120), UDim2.fromOffset(298, 26))
	local target = box(frame, "Target", "target user id", UDim2.fromOffset(8, 120), UDim2.fromOffset(136, 26))
	local function pick(name: string, hint: string)
		chosen = name
		arg.PlaceholderText = hint
		for key, b in buttons do
			b.BackgroundColor3 = if key == name then PICKED else DIM
		end
	end
	for i, entry in COMMANDS do
		local name, hint = entry[1], entry[2]
		local b = Instance.new("TextButton")
		b.Name = name
		b.Text = name
		b.Font = Enum.Font.GothamBold
		b.TextSize = 12
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Position = UDim2.fromOffset(8 + ((i - 1) % 4) * 112, 8 + math.floor((i - 1) / 4) * 28)
		b.Size = UDim2.fromOffset(106, 24)
		b.Parent = frame
		b.Activated:Connect(function()
			pick(name, hint)
		end)
		buttons[name] = b
	end
	pick(chosen, COMMANDS[1][2])

	local run = Instance.new("TextButton")
	run.Name = "Run"
	run.Text = "Run"
	run.Font = Enum.Font.GothamBold
	run.TextSize = 14
	run.TextColor3 = Color3.new(1, 1, 1)
	run.BackgroundColor3 = Color3.fromRGB(60, 140, 90)
	run.Position = UDim2.fromOffset(8, 152)
	run.Size = UDim2.fromOffset(80, 26)
	run.Parent = frame
	run.Activated:Connect(function()
		NetClient.send("AdminCommand", chosen, tonumber(target.Text) or 0, arg.Text)
	end)

	local out = Instance.new("TextLabel")
	out.Name = "Output"
	out.Position = UDim2.fromOffset(8, 186)
	out.Size = UDim2.new(1, -16, 1, -194)
	out.BackgroundTransparency = 1
	out.Font = Enum.Font.Code
	out.TextSize = 12
	out.TextWrapped = true
	out.TextXAlignment = Enum.TextXAlignment.Left
	out.TextYAlignment = Enum.TextYAlignment.Top
	out.TextColor3 = Color3.new(1, 1, 1)
	out.Text = ""
	out.Parent = frame
	output = out

	toggle.Activated:Connect(function()
		frame.Visible = not frame.Visible
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function AdminController.Init()
	NetClient.on("AdminResult", function(text: string)
		if output ~= nil then
			output.Text = text
		end
	end)
end

function AdminController.Start()
	local player = Players.LocalPlayer
	if player:GetAttribute("IsAdmin") == true then
		build()
		return
	end
	local connection: RBXScriptConnection
	connection = player:GetAttributeChangedSignal("IsAdmin"):Connect(function()
		if player:GetAttribute("IsAdmin") == true and output == nil then
			connection:Disconnect()
			build()
		end
	end)
end

return AdminController
