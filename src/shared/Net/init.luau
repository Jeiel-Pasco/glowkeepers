--!strict
-- Every remote, declared once (TECH_SPEC §7).
--
-- NetServer builds one RemoteEvent per entry and rejects a client call that has the wrong
-- argument types or count, or is over the rate limit, before the handler runs.
-- Clients send intents only: never amounts, prices, rolls or results.
-- Gameplay remotes (Catch, GrabStart, ShopBuy, ...) are added here in the phase that builds them.
--
-- Pure data, so the Lune tests can check it.

export type ArgSchema = {
	type: "any" | "boolean" | "number" | "integer" | "string" | "enum" | "list",
	min: number?,
	max: number?,
	maxLen: number?,
	values: { string }?,
	of: ArgSchema?, -- "list": the schema of each item
	maxCount: number?, -- "list": at most this many items
	minCount: number?, -- "list": at least this many (default 1)
	optional: boolean?,
}

export type Remote = {
	dir: "c2s" | "s2c",
	args: { ArgSchema }?, -- c2s only
	rate: { perSecond: number, burst: number }?, -- c2s only
	unreliable: boolean?,
}

local SETTING_KEYS = { "calm", "reducedFlash", "music", "sfx", "breakReminder" }

-- A world coordinate the client aims at; the server clamps every spell to its range anyway.
local COORD: ArgSchema = { type = "number", min = -5000, max = 5000 }
local BOOK: ArgSchema = { type = "integer", min = 1, max = 30 } -- index into data.books

local Net = {}

-- Allowed value for each SetSetting key (GAME_SYSTEMS §26).
Net.settings = {
	calm = { type = "boolean" },
	reducedFlash = { type = "boolean" },
	music = { type = "number", min = 0, max = 1 },
	sfx = { type = "number", min = 0, max = 1 },
	breakReminder = { type = "boolean" },
} :: { [string]: ArgSchema }

Net.remotes = {
	-- Client → server
	ClientReady = { dir = "c2s", args = {}, rate = { perSecond = 0.2, burst = 2 } },
	SetSetting = {
		dir = "c2s",
		args = { { type = "enum", values = SETTING_KEYS }, { type = "any" } },
		rate = { perSecond = 10, burst = 10 },
	},
	-- Combat: the click attack and the equipped book's spells, aimed at a point.
	Basic = { dir = "c2s", args = { COORD, COORD, COORD }, rate = { perSecond = 6, burst = 6 } },
	Cast = {
		dir = "c2s",
		args = { { type = "integer", min = 1, max = 4 }, COORD, COORD, COORD },
		rate = { perSecond = 6, burst = 8 },
	},
	Dash = { dir = "c2s", args = {}, rate = { perSecond = 2, burst = 3 } },
	SwapBook = { dir = "c2s", args = { { type = "integer", min = 1, max = 4 } }, rate = { perSecond = 4, burst = 4 } },
	Recall = { dir = "c2s", args = {}, rate = { perSecond = 1, burst = 2 } },
	-- Grimoires & Gears (at your camp desk and shop).
	Write = { dir = "c2s", args = { BOOK, { type = "boolean" } }, rate = { perSecond = 3, burst = 4 } },
	WriteResolve = {
		dir = "c2s",
		args = { { type = "integer", min = 0, max = 4 } },
		rate = { perSecond = 3, burst = 4 },
	},
	RollGrimoire = { dir = "c2s", args = {}, rate = { perSecond = 2, burst = 4 } },
	UpgradeSkill = {
		dir = "c2s",
		args = { BOOK, { type = "integer", min = 1, max = 4 } },
		rate = { perSecond = 4, burst = 6 },
	},
	EquipBook = {
		dir = "c2s",
		args = { { type = "integer", min = 1, max = 4 }, BOOK },
		rate = { perSecond = 4, burst = 6 },
	},
	PickElement = {
		dir = "c2s",
		args = { { type = "enum", values = { "Fire", "Water", "Leaf" } } },
		rate = { perSecond = 1, burst = 2 },
	},
	AllocateStat = {
		dir = "c2s",
		args = { { type = "enum", values = { "health", "power", "defense" } }, { type = "integer", min = 1, max = 99 } },
		rate = { perSecond = 5, burst = 8 },
	},
	Buy = {
		dir = "c2s",
		args = { { type = "enum", values = { "ink_Neutral", "ink_Fire", "ink_Water", "ink_Leaf" } } },
		rate = { perSecond = 3, burst = 5 },
	},
	BuyGear = {
		dir = "c2s",
		args = { { type = "enum", values = { "backpack", "robe", "hat", "boots" } } },
		rate = { perSecond = 3, burst = 5 },
	},
	TogglePvp = { dir = "c2s", args = {}, rate = { perSecond = 1, burst = 2 } },
	AcceptQuest = {
		dir = "c2s",
		args = { { type = "string", maxLen = 32 } },
		rate = { perSecond = 2, burst = 4 },
	},
	ResetStats = { dir = "c2s", args = {}, rate = { perSecond = 0.5, burst = 1 } },

	-- Server → client
	PlayerState = { dir = "s2c" }, -- (full: boolean, data): a snapshot, then top-level patches
	Toast = { dir = "s2c" }, -- (text, kind?)
	Announce = { dir = "s2c" }, -- (text)
	Fx = { dir = "s2c", unreliable = true }, -- (kind, a, b, c, ...): a spell or attack to draw (CombatFx)
	Hit = { dir = "s2c", unreliable = true }, -- (target: Instance, amount, mult, kind?): a damage number
	RecallState = { dir = "s2c" }, -- (endsAt: number | nil): the channel started, or stopped
	WriteResult = { dir = "s2c" }, -- (outcome, spellId, bookIndex, page?): the desk's reveal
	Quest = { dir = "s2c" }, -- (view | nil): the tracked quest
} :: { [string]: Remote }

return Net
