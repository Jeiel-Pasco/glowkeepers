--!strict
-- The quest chain (GDD "Tutorial" beats, then Emberfall), then repeatable bounties. Pure.
--
-- A step is done when its counter reaches `n`. Events the server reports:
--   write            a spell was written
--   kill <kindId>    an enemy died with this player's credit (counts by kind or by role)
-- Reward ink keyed "element" is ink of the player's element. Text may hold {zone} and {boss}.
--   raider           a raider that robbed this player was killed
--   bank             loot was banked at camp
--   element          the starter element was picked
--   level <level>    reached a level (counts as the level itself, not +1)

local Quests = {}

export type Step = {
	text: string,
	event: string,
	target: string?, -- the kind for "kill"
	n: number,
	reward: { xp: number, coins: number, ink: { [string]: number }? },
	hint: string?, -- where to go
	tutorial: boolean?,
}

Quests.STEPS = {
	{
		text = "Write your first spell at your desk",
		event = "write",
		n = 1,
		reward = { xp = 30, coins = 10 },
		hint = "desk",
		tutorial = true,
	},
	{
		text = "Defeat Ember Imps on the east trail",
		event = "kill",
		target = "ember_imp",
		n = 3,
		reward = { xp = 40, coins = 15, ink = { Neutral = 1 } },
		hint = "trail",
		tutorial = true,
	},
	{
		text = "Defeat the Ashling at the end of the trail",
		event = "kill",
		target = "ashling",
		n = 1,
		reward = { xp = 60, coins = 25 },
		hint = "ashling",
		tutorial = true,
	},
	{
		text = "A raider stole your loot! Chase it down",
		event = "raider",
		n = 1,
		reward = { xp = 40, coins = 20 },
		hint = "raider",
		tutorial = true,
	},
	{
		text = "Walk into your camp to bank your loot",
		event = "bank",
		n = 1,
		reward = { xp = 30, coins = 20 },
		hint = "camp",
		tutorial = true,
	},
	{
		text = "Pick your element grimoire at your desk",
		event = "element",
		n = 1,
		reward = { xp = 20, coins = 0, ink = { element = 1 } },
		hint = "desk",
		tutorial = true,
	},
	{
		text = "Defeat 8 monsters in {zone}",
		event = "kill",
		target = "minion",
		n = 8,
		reward = { xp = 120, coins = 40, ink = { element = 1 } },
		hint = "zone",
	},
	{
		text = "Defeat 5 casters deeper in {zone}",
		event = "kill",
		target = "caster",
		n = 5,
		reward = { xp = 200, coins = 60, ink = { element = 2 } },
		hint = "zone",
	},
	{ text = "Reach level 10", event = "level", n = 10, reward = { xp = 0, coins = 100 }, hint = "zone" },
	{
		text = "Defeat the {boss}",
		event = "kill",
		target = "boss",
		n = 1,
		reward = { xp = 400, coins = 150, ink = { element = 2 } },
		hint = "boss",
	},
} :: { Step }

-- After the chain: bounties, round and round.
Quests.REPEAT = {
	{
		text = "Bounty: defeat 12 monsters",
		event = "kill",
		target = "minion",
		n = 12,
		reward = { xp = 150, coins = 50, ink = { element = 1 } },
		hint = "zone",
	},
	{
		text = "Bounty: defeat 8 casters",
		event = "kill",
		target = "caster",
		n = 8,
		reward = { xp = 200, coins = 70, ink = { element = 1 } },
		hint = "zone",
	},
	{ text = "Bounty: defeat 3 raiders", event = "kill", target = "raider", n = 3, reward = { xp = 120, coins = 60 } },
	{
		text = "Bounty: defeat any zone boss",
		event = "kill",
		target = "boss",
		n = 1,
		reward = { xp = 400, coins = 150, ink = { element = 2 } },
		hint = "boss",
	},
} :: { Step }

Quests.TUTORIAL_STEPS = 6 -- steps 1–6; finishing step 6 unlocks the element pick reward

function Quests.step(index: number): Step
	if index <= #Quests.STEPS then
		return Quests.STEPS[index]
	end
	return Quests.REPEAT[(index - #Quests.STEPS - 1) % #Quests.REPEAT + 1]
end

-- New progress for `step` after an event, or nil if the event doesn't count. A kill matches the
-- step's target by kind id or by role (minion, caster, boss, raider).
function Quests.advance(step: Step, progress: number, event: string, arg: any, role: string?): number?
	if step.event ~= event then
		return nil
	end
	if event == "kill" then
		return if arg == step.target or (role ~= nil and role == step.target) then progress + 1 else nil
	elseif event == "level" then
		return math.max(progress, arg :: number)
	end
	return progress + 1
end

function Quests.inTutorial(index: number): boolean
	return index <= Quests.TUTORIAL_STEPS
end

return Quests
