--!strict
-- Black Clover Storyline & Level-Tiered Area Quests (Lv 1–15 Whispering Woods → Lv 15–30 Raider
-- Wilds → Lv 30–50 Highland Dungeon Ruins). Pure data & helpers.

local Quests = {}

export type AreaQuest = {
	id: string,
	area: string, -- "area1" | "area2" | "area3"
	areaName: string,
	npcName: string,
	minLevel: number,
	title: string,
	story: string,
	text: string,
	event: string,
	target: string?,
	n: number,
	reward: { xp: number, coins: number, stars: number, ink: number? },
}

export type Step = {
	text: string,
	event: string,
	target: string?,
	n: number,
	reward: { xp: number, coins: number, stars: number?, ink: { [string]: number }? },
	hint: string?,
	tutorial: boolean?,
	area: string?,
}

Quests.NPCS = {
	area1 = {
		id = "area1",
		name = "Elder Orsi",
		title = "Whispering Woods (Lv 1–15)",
		arc = "Arc 1 · Hage Outskirts Trial",
	},
	area2 = {
		id = "area2",
		name = "Scout Captain",
		title = "Raider Wilds (Lv 15–30)",
		arc = "Arc 2 · Sosshi Frontier Mission",
	},
	area3 = {
		id = "area3",
		name = "Knight Envoy",
		title = "Highland Ruins (Lv 30–50)",
		arc = "Arc 3 · Midnight Sun Dungeon",
	},
} :: { [string]: { id: string, name: string, title: string, arc: string } }

Quests.BOARD = {
	-- Area 1: Whispering Woods (Lv 1–15)
	{
		id = "a1_wisps",
		area = "area1",
		areaName = "Whispering Woods",
		npcName = "Elder Orsi",
		minLevel = 1,
		title = "Grimoire Trial",
		story = "Prove your new Grimoire by clearing wild Mana Wisps along the forest outskirts.",
		text = "Defeat 4 Forest Wisps (Lv 1–5)",
		event = "kill",
		target = "forest_wisp",
		n = 4,
		reward = { xp = 65, coins = 45, stars = 2, ink = 2 },
	},
	{
		id = "a1_sprouts",
		area = "area1",
		areaName = "Whispering Woods",
		npcName = "Elder Orsi",
		minLevel = 6,
		title = "Forest Hunt",
		story = "Thorny Briar Sprouts are overrunning the eastern woods. Drive them back!",
		text = "Defeat 5 Thorn Sprouts (Lv 6–11)",
		event = "kill",
		target = "thorn_sprout",
		n = 5,
		reward = { xp = 160, coins = 95, stars = 2, ink = 2 },
	},
	{
		id = "a1_brute",
		area = "area1",
		areaName = "Whispering Woods",
		npcName = "Elder Orsi",
		minLevel = 11,
		title = "Rogue Poacher",
		story = "A hulking Runestone Brute is hoarding stolen Grimoires deep in the woods.",
		text = "Defeat the Runestone Brute (Lv 15 Boss)",
		event = "kill",
		target = "ashling",
		n = 1,
		reward = { xp = 380, coins = 180, stars = 4, ink = 3 },
	},

	-- Area 2: Raider Wilds (Lv 15–30)
	{
		id = "a2_raiders",
		area = "area2",
		areaName = "Raider Wilds",
		npcName = "Scout Captain",
		minLevel = 15,
		title = "Bandit Sweep",
		story = "Your first Magic Knight mission: break the Raider palisades in the wild frontier.",
		text = "Defeat 6 Raiders or Camp Guards (Lv 15–22)",
		event = "kill",
		target = "raider",
		n = 6,
		reward = { xp = 520, coins = 240, stars = 3, ink = 3 },
	},
	{
		id = "a2_mages",
		area = "area2",
		areaName = "Raider Wilds",
		npcName = "Scout Captain",
		minLevel = 21,
		title = "Rogue Mist Mages",
		story = "Rogue Mist Callers are conjuring blinding fog over the Sosshi frontier.",
		text = "Defeat 5 Mist Callers (Lv 22–26)",
		event = "kill",
		target = "mist_caster",
		n = 5,
		reward = { xp = 780, coins = 340, stars = 3, ink = 4 },
	},
	{
		id = "a2_treant",
		area = "area2",
		areaName = "Raider Wilds",
		npcName = "Scout Captain",
		minLevel = 26,
		title = "Frontier Guardian",
		story = "An ancient corrupted Elder Treant blocks the pass to the Highland Ruins.",
		text = "Defeat the Elder Treant (Lv 30 Boss)",
		event = "kill",
		target = "elder_treant",
		n = 1,
		reward = { xp = 1350, coins = 520, stars = 5, ink = 5 },
	},

	-- Area 3: Highland Dungeon Ruins (Lv 30–50)
	{
		id = "a3_sentinels",
		area = "area3",
		areaName = "Highland Ruins",
		npcName = "Knight Envoy",
		minLevel = 30,
		title = "Dungeon Sentinels",
		story = "Climb into the ancient mana dungeon and shatter its awakened Ruin Sentinels.",
		text = "Defeat 6 Ruin Sentinels (Lv 31–38)",
		event = "kill",
		target = "ember_imp",
		n = 6,
		reward = { xp = 1600, coins = 540, stars = 4, ink = 4 },
	},
	{
		id = "a3_cultists",
		area = "area3",
		areaName = "Highland Ruins",
		npcName = "Knight Envoy",
		minLevel = 39,
		title = "Midnight Sun Mages",
		story = "Midnight Sun casters are siphoning the dungeon's magic. Stop their ritual!",
		text = "Defeat 6 Midnight Sun Casters (Lv 40–46)",
		event = "kill",
		target = "cinder_caster",
		n = 6,
		reward = { xp = 2400, coins = 720, stars = 4, ink = 5 },
	},
	{
		id = "a3_golem",
		area = "area3",
		areaName = "Highland Ruins",
		npcName = "Knight Envoy",
		minLevel = 45,
		title = "Dungeon Titan",
		story = "Face the Ancient Mineral Golem guarding the heart of the Highland Ruins.",
		text = "Defeat the Ancient Mineral Golem (Lv 50 Boss)",
		event = "kill",
		target = "cinder_golem",
		n = 1,
		reward = { xp = 4000, coins = 1100, stars = 6, ink = 6 },
	},
} :: { AreaQuest }

Quests.BOARD_BY_ID = {} :: { [string]: AreaQuest }
for _, q in Quests.BOARD do
	Quests.BOARD_BY_ID[q.id] = q
end

function Quests.forArea(areaId: string): { AreaQuest }
	local out = {}
	for _, q in Quests.BOARD do
		if q.area == areaId then
			table.insert(out, q)
		end
	end
	return out
end

-- Legacy sequential steps kept for tests & new-player hub onboarding.
Quests.STEPS = {
	{
		text = "Roll a Grimoire (5★) or unlock a skill at the Desk",
		event = "write",
		n = 1,
		reward = { xp = 35, coins = 30, stars = 1 },
		hint = "desk",
		tutorial = true,
	},
	{
		text = "Area 1 (Lv 1–15): Defeat 3 Forest Wisps in Whispering Woods",
		event = "kill",
		target = "forest_wisp",
		n = 3,
		reward = { xp = 55, coins = 45, stars = 2, ink = { Universal = 2 } },
		tutorial = true,
	},
	{
		text = "Area 1 Boss: Defeat the Runestone Brute in Whispering Woods",
		event = "kill",
		target = "ashling",
		n = 1,
		reward = { xp = 120, coins = 85, stars = 3, ink = { Universal = 2 } },
		tutorial = true,
	},
	{
		text = "A raider stole your loot! Chase it down",
		event = "raider",
		n = 1,
		reward = { xp = 60, coins = 60, stars = 2 },
		tutorial = true,
	},
	{
		text = "Return to the Camp Courtyard to bank your Backpack",
		event = "bank",
		n = 1,
		reward = { xp = 45, coins = 50, stars = 2 },
		hint = "camp",
		tutorial = true,
	},
	{
		text = "Roll or upgrade a Grimoire at the Scriptorium Desk",
		event = "element",
		n = 1,
		reward = { xp = 50, coins = 50, stars = 2, ink = { Universal = 2 } },
		hint = "desk",
		tutorial = true,
	},
} :: { Step }

Quests.REPEAT = {
	{
		text = "Area Quest: Defeat 10 monsters (+3★ Stars & Coins)",
		event = "kill",
		target = "minion",
		n = 10,
		reward = { xp = 200, coins = 130, stars = 3, ink = { Universal = 2 } },
	},
} :: { Step }

Quests.TUTORIAL_STEPS = 6

function Quests.step(index: number): Step
	if index <= #Quests.STEPS then
		return Quests.STEPS[index]
	end
	return Quests.REPEAT[(index - #Quests.STEPS - 1) % #Quests.REPEAT + 1]
end

function Quests.advance(
	step: { event: string, target: string? },
	progress: number,
	event: string,
	arg: any,
	role: string?
): number?
	if step.event ~= event then
		return nil
	end
	if event == "kill" then
		local roleMatch = role ~= nil and (role == step.target or (step.target == "raider" and role == "guard"))
		return if arg == step.target or roleMatch then progress + 1 else nil
	elseif event == "level" then
		return math.max(progress, arg :: number)
	end
	return progress + 1
end

function Quests.inTutorial(index: number): boolean
	return index <= Quests.TUTORIAL_STEPS
end

return Quests
