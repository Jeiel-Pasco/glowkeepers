--!strict
-- Shared data types (TECH_SPEC §5). Type-only module: `require` it and use `Types.Profile`.
--
-- Slot maps (display, vault, pass tiers) use string keys ("1", "2", ...). DataStores save tables
-- as JSON, and a number-keyed table with gaps is not stored reliably, so never key saved data
-- by sparse numbers.

export type Rarity = number -- 1 Common .. 7 Secret
export type Mutation = number -- 0 none, 1 Golden, 2 Rainbow, 3 Moonlit

export type Glowling = {
	id: string, -- HttpService:GenerateGUID(false)
	sp: string, -- species id, e.g. "glimmermouse"
	r: Rarity,
	m: Mutation,
	s: number, -- size 0.80–1.30, 2 decimal places
	src: string, -- "lure" | "night" | "steal" | "trade" | "event" | "tutorial" | "fuse"
	at: number, -- os.time() when acquired
	by: number, -- userId of the original catcher
	tradeLockUntil: number?,
}

export type Settings = {
	calm: boolean,
	reducedFlash: boolean,
	music: number, -- 0..1
	sfx: number, -- 0..1
	breakReminder: boolean,
}

export type Profile = {
	v: number,
	glow: number,
	glowSinceRebirth: number,
	lifetimeGlow: number,
	embers: number,
	embersBoughtLifetime: number,
	stars: number,
	up: { lantern: number, boots: number, slots: number }, -- slots = levels bought beyond 8
	lockCharges: number,
	shop: { window: number, bought: { number } }, -- lures bought per floor in restock window `window`
	glowlings: { [string]: Glowling }, -- every owned record, keyed by id
	display: { [string]: string }, -- display slot "1".."n" → Glowling id (stealable)
	vault: { [string]: string }, -- vault slot "1".."n" → id (never stealable, kept on rebirth)
	pity: { sinceLegendary: number },
	dex: { [string]: { r: number, m: number } }, -- bitmasks per species
	dexClaimed: { [string]: number }, -- page tier claimed per species
	decor: { owned: { [string]: number }, placed: { { id: string, x: number, z: number, rot: number } } },
	baseName: { a: number, n: number }, -- indices into preset word lists, 0 = default
	quests: { day: number, daily: { any }, week: number, weekly: { any }, rerollDay: number },
	gift: { claimed: number, lastDay: number },
	pass: { season: number, xp: number, premium: boolean, free: { [string]: boolean }, prem: { [string]: boolean } },
	firstJoin: number,
	lastSeen: number,
	lastIncomePerSec: number,
	playDays: number,
	lastPlayDay: number,
	shield: { active: boolean, playSeconds: number },
	ftue: { step: number, path: string?, done: boolean },
	stats: {
		catches: number,
		steals: number,
		stolenFrom: number,
		revives: number,
		nightsSurvived: number,
		firesLost: number,
		rebirths: number,
		trades: number,
		piecesFed: number,
	},
	daily: { day: number, buys: { [string]: number } }, -- purchase caps
	receipts: { [string]: number }, -- PurchaseId → time (the last 200)
	settings: Settings,
	notifyOptIn: boolean,
	crewId: string?,
	flags: { [string]: any }, -- moderation and exploit flags
}

return {}
