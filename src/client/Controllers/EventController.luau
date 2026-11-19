--!strict
-- The event strip (GAME_SYSTEMS §21): under the top bar, the running event and its time left
-- (workspace LiveEventId / LiveEventEnds) and today's featured Deepwood species
-- (workspace FeaturedSpecies). Refreshed once a second.
--
-- Placeholder for UI (GS replaces it in Phase 4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local species = require(Shared:WaitForChild("Config"):WaitForChild("species")) :: any

local EventController = {}

local names: { [string]: string } = {}
for _, s in species.species do
	names[s.id] = s.name
end

local function title(id: string): string
	local words = {}
	for word in string.gmatch(id, "[^_]+") do
		table.insert(words, string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2))
	end
	return table.concat(words, " ")
end

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 3600 then
		return string.format("%dh %02dm", s // 3600, (s % 3600) // 60)
	end
	return string.format("%d:%02d", s // 60, s % 60)
end

function EventController.Init() end

function EventController.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "EventGui"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local label = Instance.new("TextLabel")
	label.Name = "Strip"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 58) -- under the top bar
	label.Size = UDim2.fromOffset(460, 24)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = Color3.fromRGB(255, 200, 140)
	label.TextStrokeTransparency = 0.5
	label.Text = ""
	label.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	task.spawn(function()
		while true do
			local parts = {}
			local id = workspace:GetAttribute("LiveEventId")
			local ends = workspace:GetAttribute("LiveEventEnds")
			if type(id) == "string" and type(ends) == "number" then
				table.insert(parts, `{title(id)} · {clock(ends - workspace:GetServerTimeNow())} left`)
			end
			local featured = workspace:GetAttribute("FeaturedSpecies")
			if type(featured) == "string" then
				table.insert(parts, `Featured: {names[featured] or featured}`)
			end
			label.Text = table.concat(parts, "   ·   ")
			task.wait(1)
		end
	end)
end

return EventController
