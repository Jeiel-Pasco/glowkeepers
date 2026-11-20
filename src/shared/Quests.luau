--!strict
-- The quest chain (GDD "Tutorial" beats, then Emberfall), then repeatable bounties. Pure.
--
-- A step is done when its counter reaches `n`. Events the server reports:
--   write            a spell was written
--   kill <kindId>    an enemy of that kind died with this player's credit
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
		reward = { xp = 20, coins = 0, ink = { Fire = 1 } },
		hint = "desk",
		tutorial = true,
	},
	{
		text = "Enter Emberfall Ridge and defeat Ember Imps",
		event = "kill",
		target = "ember_imp",
		n = 8,
		reward = { xp = 120, coins = 40, ink = { Fire = 1 } },
		hint = "emberfall",
	},
	{
		text = "Defeat Cinder Casters deeper in the ridge",
		event = "kill",
		target = "cinder_caster",
		n = 6,
		reward = { xp = 200, coins = 60, ink = { Fire = 2 } },
		hint = "emberfall",
	},
	{ text = "Reach level 10", event = "level", n = 10, reward = { xp = 0, coins = 100 }, hint = "emberfall" },
	{
		text = "Defeat the Cinder Golem",
		event = "kill",
		target = "cinder_golem",
		n = 1,
		reward = { xp = 400, coins = 150, ink = { Fire = 2 } },
		hint = "golem",
	},
} :: { Step }

-- After the chain: bounties, round and round.
Quests.REPEAT = {
	{
		text = "Bounty: defeat 12 Ember Imps",
		event = "kill",
		target = "ember_imp",
		n = 12,
		reward = { xp = 150, coins = 50, ink = { Fire = 1 } },
	},
	{
		text = "Bounty: defeat 8 Cinder Casters",
		event = "kill",
		target = "cinder_caster",
		n = 8,
		reward = { xp = 200, coins = 70, ink = { Fire = 1 } },
	},
	{ text = "Bounty: defeat 3 raiders", event = "kill", target = "raider", n = 3, reward = { xp = 120, coins = 60 } },
	{
		text = "Bounty: defeat the Cinder Golem",
		event = "kill",
		target = "cinder_golem",
		n = 1,
		reward = { xp = 400, coins = 150, ink = { Fire = 2 } },
	},
} :: { Step }

Quests.TUTORIAL_STEPS = 6 -- steps 1–6; finishing step 6 unlocks the element pick reward

function Quests.step(index: number): Step
	if index <= #Quests.STEPS then
		return Quests.STEPS[index]
	end
	return Quests.REPEAT[(index - #Quests.STEPS - 1) % #Quests.REPEAT + 1]
end

-- New progress for `step` after an event, or nil if the event doesn't count.
function Quests.advance(step: Step, progress: number, event: string, arg: any): number?
	if step.event ~= event then
		return nil
	end
	if event == "kill" then
		return if arg == step.target then progress + 1 else nil
	elseif event == "level" then
		return math.max(progress, arg :: number)
	end
	return progress + 1
end

function Quests.inTutorial(index: number): boolean
	return index <= Quests.TUTORIAL_STEPS
end

return Quests
