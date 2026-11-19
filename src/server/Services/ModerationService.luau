--!strict
-- Exploit flags and the graduated response (TECH_SPEC §8). The rules live in Shared.Moderation.
--
-- Listens to NetServer.Abuse (floods, invalid calls, rejected calls; StealService's carry
-- check fires it too, as "Carry"). Each one is logged in the profile's private `flags`, sent
-- to telemetry, and warned in the server log; once the recent points reach the threshold the
-- player is kicked with a message. Bans stay manual (admin tools, after review).
-- The player attribute ExploitFlags = flags raised this session (for QA and support).
--
-- DEV/BETA: workspace DebugKickAt = number overrides moderation.kickAt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Env = require(Shared:WaitForChild("Env"))
local Moderation = require(Shared:WaitForChild("Moderation"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))

local KICK_MESSAGE = "You were removed for unusual activity. If this was a mistake, please rejoin."
local NET_REASONS = { flood = true, invalid = true, rejected = true }

local ModerationService = {}

local function kickAt(): number?
	if Env.get().name == "PROD" then
		return nil
	end
	return tonumber(workspace:GetAttribute("DebugKickAt"))
end

-- Raises one flag (step 3) and kicks at the threshold (step 4).
function ModerationService.flag(player: Player, kind: string, detail: string)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute("ExploitFlags", (tonumber(player:GetAttribute("ExploitFlags")) or 0) + 1)
	warn(`[Moderation] {player.Name} ({player.UserId}) flagged: {kind} {detail}`)
	Telemetry.custom(player, "exploit_flag", nil, { kind })
	local data = DataService.get(player)
	if data == nil then
		return
	end
	if type(data.flags) ~= "table" then
		data.flags = {}
	end
	local action = Moderation.record(economy, data.flags, kind, detail, os.time(), kickAt())
	if action == "kick" then
		warn(`[Moderation] {player.Name} kicked (kick #{data.flags.kicks})`)
		Telemetry.custom(player, "exploit_kick", data.flags.kicks, { kind })
		DataService.save(player)
		player:Kick(KICK_MESSAGE)
	end
end

function ModerationService.Init()
	NetServer.Abuse:Connect(function(player: Player, name: string, reason: string)
		local kind = if NET_REASONS[reason] then reason else name
		ModerationService.flag(player, kind, `{name}:{reason}`)
	end)
end

function ModerationService.Start() end

return ModerationService
