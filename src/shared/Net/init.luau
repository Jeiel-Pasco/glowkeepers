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
	type: "any" | "boolean" | "number" | "integer" | "string" | "enum",
	min: number?,
	max: number?,
	maxLen: number?,
	values: { string }?,
	optional: boolean?,
}

export type Remote = {
	dir: "c2s" | "s2c",
	args: { ArgSchema }?, -- c2s only
	rate: { perSecond: number, burst: number }?, -- c2s only
	unreliable: boolean?,
}

local SETTING_KEYS = { "calm", "reducedFlash", "music", "sfx", "breakReminder" }

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

	-- Server → client
	PlayerState = { dir = "s2c" }, -- (full: boolean, data): a snapshot, then top-level patches
	Wallet = { dir = "s2c" }, -- (glow, perSec, serverTime, embers): the client extrapolates
	Toast = { dir = "s2c" }, -- (text, kind?)
	Announce = { dir = "s2c" }, -- (text)
} :: { [string]: Remote }

return Net
