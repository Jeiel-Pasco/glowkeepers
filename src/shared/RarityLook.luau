--!strict
-- How a Glowling looks at each rarity (Design & Asset Bible §2–3, CONTENT §A1 look ladder, D24).
-- Pure: no requires and no engine types; colours are { r, g, b } in 0..255 so Lune can test them.
-- GlowlingRenderer turns a Look into parts.
--
--   1 Common     Form I    matte body, a Neon tip
--   2 Uncommon   Form I    two-tone body, a rim accent
--   3 Rare       Form I    Neon inlays, Glass accents, a few motes
--   4 Epic       Form II   ground halo, glass wings, a trail
--   5 Legendary  Form II   ×1.08, gold trim, a crown, a sky beam
--   6 Mythic     Form III  ×1.15, orbiting rune ring, extra wings, levitates, a ground sigil
--   7 Secret     Form III  ×1.25, starfield, orbiting pearls, prismatic edges

local RarityLook = {}

export type RGB = { number }

export type Look = {
	form: number, -- 1..3
	scale: number, -- × the rig size
	smooth: boolean, -- SmoothPlastic body instead of matte
	twoTone: boolean, -- a lighter belly
	rim: boolean, -- a glowing collar
	inlays: boolean, -- Neon stripes on the back
	glass: boolean, -- Glass ears
	motes: number, -- sparkle particles per second
	halo: boolean, -- a glowing disc under the feet
	wings: number, -- 0, 2 or 4
	trail: boolean,
	gold: boolean, -- gold trim instead of the family colour on the collar
	crown: boolean,
	skyBeam: boolean,
	runeRing: boolean, -- orbits the body
	levitate: number, -- studs above the pad
	sigil: boolean, -- a large rune disc on the ground
	starfield: boolean,
	pearls: number, -- orbiting pearls
	prismatic: boolean, -- the glow parts cycle through hues
	light: number, -- PointLight brightness when the Glowling gets a light
}

local BASE: Look = {
	form = 1,
	scale = 1,
	smooth = false,
	twoTone = false,
	rim = false,
	inlays = false,
	glass = false,
	motes = 0,
	halo = false,
	wings = 0,
	trail = false,
	gold = false,
	crown = false,
	skyBeam = false,
	runeRing = false,
	levitate = 0,
	sigil = false,
	starfield = false,
	pearls = 0,
	prismatic = false,
	light = 0.8,
}

local function with(base: Look, changes: { [string]: any }): Look
	local look = table.clone(base) :: any
	for key, value in changes do
		look[key] = value
	end
	return look
end

local common = BASE
local uncommon = with(common, { smooth = true, twoTone = true, rim = true, light = 1 })
local rare = with(uncommon, { inlays = true, glass = true, motes = 2, light = 1.2 })
local epic = with(rare, { form = 2, halo = true, wings = 2, trail = true, motes = 4, light = 1.5 })
local legendary = with(epic, { scale = 1.08, gold = true, crown = true, skyBeam = true, light = 1.8 })
local mythic = with(legendary, {
	form = 3,
	scale = 1.15,
	runeRing = true,
	wings = 4,
	levitate = 1.2,
	sigil = true,
	motes = 6,
	light = 2.2,
})
local secret = with(mythic, { scale = 1.25, starfield = true, pearls = 3, prismatic = true, light = 2.6 })

RarityLook.LOOKS = { common, uncommon, rare, epic, legendary, mythic, secret } :: { Look }

-- Family glow colours (Design & Asset Bible §3).
RarityLook.FAMILY_GLOW = {
	Lantern = { 255, 200, 90 },
	Ember = { 255, 120, 50 },
	Crystal = { 90, 230, 255 },
	Grove = { 100, 235, 140 },
	Celestial = { 185, 135, 255 },
	Shadow = { 120, 105, 235 },
} :: { [string]: RGB }

-- Body height in studs per rig.
RarityLook.RIGS = { tiny = 1.1, small = 1.6, medium = 2.2, large = 3.0 } :: { [string]: number }

-- Soft body tones; each species gets one by a stable hash of its id.
RarityLook.TONES = {
	{ 226, 196, 150 }, -- cream
	{ 186, 132, 92 }, -- fawn
	{ 124, 90, 66 }, -- bark
	{ 140, 172, 200 }, -- mist
	{ 96, 106, 138 }, -- slate
	{ 200, 128, 156 }, -- rose
	{ 128, 166, 104 }, -- moss
	{ 78, 76, 116 }, -- dusk
} :: { RGB }

RarityLook.GOLD = { 255, 200, 70 } :: RGB
RarityLook.MOONLIT = { 205, 220, 255 } :: RGB

-- The Look for rarity tier `r` (clamped to 1..7).
function RarityLook.look(r: number): Look
	return RarityLook.LOOKS[math.clamp(math.floor(r), 1, #RarityLook.LOOKS)]
end

-- 32-bit FNV-1a of a string: the same on every client and in Lune.
function RarityLook.hash(text: string): number
	local h = 2166136261
	for i = 1, #text do
		h = bit32.bxor(h, string.byte(text, i))
		-- × 16777619 (= 2^24 + 403) mod 2^32, split so it stays exact in doubles
		h = (bit32.lshift(h, 24) + h * 403) % 4294967296
	end
	return h
end

function RarityLook.tone(speciesId: string): RGB
	return RarityLook.TONES[RarityLook.hash(speciesId) % #RarityLook.TONES + 1]
end

function RarityLook.glow(family: string?): RGB
	return RarityLook.FAMILY_GLOW[family or ""] or RarityLook.FAMILY_GLOW.Lantern
end

-- Which pads get a PointLight: the `cap` rarest, ties to the lower pad number.
function RarityLook.lightPicks(pads: { [string]: { r: number } }, cap: number): { [string]: boolean }
	local keys = {}
	for key in pads do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		local ra, rb = pads[a].r, pads[b].r
		if ra ~= rb then
			return ra > rb
		end
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	local picks = {}
	for i = 1, math.min(cap, #keys) do
		picks[keys[i]] = true
	end
	return picks
end

return RarityLook
