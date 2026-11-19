--!strict
-- Badges (GAME_SYSTEMS §24): the 15 launch badges, earned from the profile (Boards.badgesEarned),
-- so one missed while offline or before this build is awarded on the next join.
--
-- Checked on join, on every Progress event and after a new Glowling. A badge awarded once is
-- kept in `badges[key]`, so it's never asked of Roblox again. Badge asset ids are per
-- environment in economy.badges[].ids; 0 = not created yet (only recorded and logged).
-- `stats.fireSaves` counts feeds while the fire was below fire.saveBelow (CampfireService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxBadges = game:GetService("BadgeService")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Boards = require(Shared:WaitForChild("Boards"))
local Env = require(Shared:WaitForChild("Env"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local GlowlingService = require(script.Parent:WaitForChild("GlowlingService"))

local BadgeService = {}

local byKey: { [string]: any } = {}
for _, badge in economy.badges do
	byKey[badge.key] = badge
end

local function award(player: Player, badge: any)
	local id = tonumber(badge.ids[Env.get().name]) or 0
	if id <= 0 then
		return
	end
	local ok, err = pcall(function()
		RobloxBadges:AwardBadge(player.UserId, id)
	end)
	if not ok then
		warn(`[BadgeService] award {badge.key} failed: {err}`)
	end
end

function BadgeService.check(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	for _, key in Boards.badgesEarned(economy, data) do
		if not data.badges[key] then
			data.badges[key] = true
			local badge = byKey[key]
			Telemetry.custom(player, "badge", nil, { key })
			if key ~= "welcome" and player.Parent == Players then
				NetServer.send(player, "Toast", `Badge: {badge.name}`, "good")
			end
			task.spawn(award, player, badge)
		end
	end
end

function BadgeService.Init()
	DataService.PlayerReady:Connect(function(player: Player)
		BadgeService.check(player)
	end)
	Progress.Event:Connect(function(player: Player, event: string)
		if event ~= "glow" then -- income ticks change no badge
			task.defer(BadgeService.check, player)
		end
	end)
	GlowlingService.Added:Connect(function(player: Player)
		task.defer(BadgeService.check, player) -- after GlowdexService records it
	end)
end

function BadgeService.Start() end

return BadgeService
