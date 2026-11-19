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
	optional: boolean?,
}

export type Remote = {
	dir: "c2s" | "s2c",
	args: { ArgSchema }?, -- c2s only
	rate: { perSecond: number, burst: number }?, -- c2s only
	unreliable: boolean?,
}

local SETTING_KEYS = { "calm", "reducedFlash", "music", "sfx", "breakReminder" }

-- HttpService:GenerateGUID(false) is 36 characters.
local GLOWLING_ID: ArgSchema = { type = "string", maxLen = 36 }
-- A pad number (the map's `Slot` attribute). 30 = upgrades.slots.max; the server checks the
-- player's unlocked pads, and tests/net.spec.luau checks this bound against the config.
local PAD: ArgSchema = { type = "integer", min = 1, max = 30 }
-- A plot id (the map's `PlotId` attribute): one plot per player, server.maxPlayers of them.
local PLOT: ArgSchema = { type = "integer", min = 1, max = 8 }

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
	FtueStep = { dir = "c2s", args = { { type = "integer", min = 1, max = 10 } }, rate = { perSecond = 2, burst = 4 } },
	Place = { dir = "c2s", args = { GLOWLING_ID, PAD }, rate = { perSecond = 10, burst = 10 } }, -- swaps if taken
	Unplace = { dir = "c2s", args = { GLOWLING_ID }, rate = { perSecond = 10, burst = 10 } }, -- back to storage
	PlaceBest = { dir = "c2s", args = {}, rate = { perSecond = 2, burst = 2 } },
	Release = {
		dir = "c2s",
		args = { { type = "list", of = GLOWLING_ID, maxCount = 20 } },
		rate = { perSecond = 2, burst = 4 },
	}, -- storage Glowlings → Glow (§7)
	PickupFuel = { dir = "c2s", args = { { type = "string", maxLen = 16 } }, rate = { perSecond = 4, burst = 4 } }, -- PileId
	FeedFire = { dir = "c2s", args = {}, rate = { perSecond = 4, burst = 4 } },
	-- Hold to steal: GrabStart when the hold begins, GrabCancel when it is let go early. The
	-- server times the hold itself; the client's progress ring is only cosmetic.
	GrabStart = { dir = "c2s", args = { PLOT, PAD }, rate = { perSecond = 2, burst = 4 } },
	GrabCancel = { dir = "c2s", args = {}, rate = { perSecond = 2, burst = 4 } },
	Rebirth = { dir = "c2s", args = {}, rate = { perSecond = 0.1, burst = 1 } }, -- +1 Star (§15); the client confirms with a hold
	-- Claim a reward: a Glowdex page tier (id = species id), milestone (id = its index), or
	-- today's daily gift (id unused), or a quest (id "d1".."d3" daily, "w1".."w3" weekly).
	-- Pass tiers join the enum in their phase.
	Claim = {
		dir = "c2s",
		args = {
			{ type = "enum", values = { "dex_page", "dex_milestone", "gift", "quest" } },
			{ type = "string", maxLen = 32 },
		},
		rate = { perSecond = 5, burst = 8 },
	},
	QuestReroll = {
		dir = "c2s",
		args = { { type = "integer", min = 1, max = 3 } },
		rate = { perSecond = 1, burst = 2 },
	}, -- the day's free reroll of daily quest N
	Lock = { dir = "c2s", args = {}, rate = { perSecond = 1, burst = 2 } }, -- Base Lock, or a Lock Charge to skip the recharge
	ShopBuy = {
		dir = "c2s",
		args = { { type = "enum", values = { "lure1", "lure2", "lure3", "lure4" } } },
		rate = { perSecond = 5, burst = 8 },
	}, -- a lure of rarity floor 1..4 (§8)
	UpgradeBuy = {
		dir = "c2s",
		args = { { type = "enum", values = { "lantern", "boots", "slots" } }, { type = "boolean", optional = true } },
		rate = { perSecond = 5, burst = 8 },
	}, -- (upgradeId, all): one level, or Buy max
	LockChargeBuy = {
		dir = "c2s",
		args = { { type = "enum", values = { "glow", "embers" } } },
		rate = { perSecond = 2, burst = 4 },
	},
	-- Decorations (§18): x and z are studs from the DecorZone centre; the server checks the rest.
	DecorBuy = { dir = "c2s", args = { { type = "string", maxLen = 32 } }, rate = { perSecond = 5, burst = 8 } },
	DecorPlace = {
		dir = "c2s",
		args = {
			{ type = "string", maxLen = 32 },
			{ type = "integer", min = -12, max = 12 },
			{ type = "integer", min = -12, max = 12 },
			{ type = "integer", min = 0, max = 3 },
		},
		rate = { perSecond = 10, burst = 10 },
	},
	DecorRemove = {
		dir = "c2s",
		args = {
			{ type = "string", maxLen = 32 },
			{ type = "integer", min = -12, max = 12 },
			{ type = "integer", min = -12, max = 12 },
		},
		rate = { perSecond = 10, burst = 10 },
	},
	SetBaseName = {
		dir = "c2s",
		args = { { type = "integer", min = 1, max = 64 }, { type = "integer", min = 1, max = 64 } },
		rate = { perSecond = 0.2, burst = 1 },
	}, -- preset adjective and noun indices
	DropShield = { dir = "c2s", args = {}, rate = { perSecond = 1, burst = 2 } }, -- ends the sender's new-player shield (they said yes to stealing)
	Catch = { dir = "c2s", args = { { type = "string", maxLen = 16 } }, rate = { perSecond = 4, burst = 4 } }, -- wildId
	-- Hold to revive a downed player (by userId; Studio test players have negative ids).
	-- The server times the hold; ReviveCancel lets go.
	ReviveStart = { dir = "c2s", args = { { type = "integer" } }, rate = { perSecond = 2, burst = 4 } },
	ReviveCancel = { dir = "c2s", args = {}, rate = { perSecond = 2, burst = 4 } },

	-- Server → client
	PlayerState = { dir = "s2c" }, -- (full: boolean, data): a snapshot, then top-level patches
	OfflineEarnings = { dir = "s2c" }, -- (amount: number, away: number seconds): the join popup
	Wallet = { dir = "s2c" }, -- (glow, perSec, serverTime, embers, glowSinceRebirth): the client extrapolates
	Toast = { dir = "s2c" }, -- (text, kind?)
	Announce = { dir = "s2c" }, -- (text)
	PlotSnapshot = { dir = "s2c" }, -- (views: { [plotId as string]: Plots.View }), once the client is ready
	PlotDelta = { dir = "s2c" }, -- (plotId, patch: Plots.Patch)
	RollResult = { dir = "s2c" }, -- (record: Types.Glowling, source: "lure" | "night" | ...)
	DawnResult = { dir = "s2c" }, -- ({ survived, fire, embers, glowLost, piecesFed, revives })
	WildSpawned = { dir = "s2c" }, -- ({ { id, sp, area, x, y, z } }): a wave, or every wild for a new client
	WildGone = { dir = "s2c" }, -- ({ wildId }): caught, or dawn
	Revived = { dir = "s2c" }, -- (byUserId): to the revived player, for the friend request prompt
} :: { [string]: Remote }

return Net
