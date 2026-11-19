--!strict
-- Game events that count toward goals (quests now; the goal tracker and Night Pass later).
-- Listed early in Main's ORDER (it has no Init or Start): services call Progress.add where
-- things happen, and listeners connect to Progress.Event.
--
-- Events: "feed" (a fuel piece fed), "revive", "survive" (a night survived), "lure" (bought),
-- "place" (a Glowling placed by hand), "glow" (Glow earned from income), "steal" (delivered),
-- "star" (a rebirth), "bronze" (a Bronze Glowdex page claimed). Catches come from
-- GlowlingService.Added.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))

local Progress = {}
Progress.Event = Signal.new() -- (player, event: string, amount: number)

function Progress.add(player: Player, event: string, amount: number?)
	Progress.Event:Fire(player, event, amount or 1)
end

return Progress
