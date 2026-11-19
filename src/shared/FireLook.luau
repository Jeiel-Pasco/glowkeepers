--!strict
-- How the campfire looks at each fire level (Design & Asset Bible §5B, CONTENT §A2).
-- Pure: no requires and no engine types beyond Color3.
--
-- States by the workspace `Fire` level (0..1, nil by day):
--   Roaring    ≥ 0.75   tall gold-white column, ember swirl, gold runes, full light
--   Steady     ≥ 0.40   medium orange flames, steady sparks, amber runes
--   Flickering ≥ 0.15   low red-orange, smoke puffs, runes pulse warning red, light shrinks
--   Dying      >  0     coal bed, a few sparks, runes dim red
--   Cold       =  0     no flame, ash-blue coals, runes dark
--   Day        nil      a calm cooking fire; runes off

local FireLook = {}

export type State = "Day" | "Roaring" | "Steady" | "Flickering" | "Dying" | "Cold"

export type Look = {
	flameSize: number, -- Fire.Size
	heat: number, -- Fire.Heat
	flameColor: Color3,
	flameSecondary: Color3,
	coreScale: number, -- the Neon flame ball, × its built size (0 hides it)
	coreColor: Color3,
	lightRange: number,
	lightBrightness: number,
	lightColor: Color3,
	embers: number, -- ember particles per second
	smoke: number, -- Smoke.Opacity (0 = off)
	runeColor: Color3,
	runeGlow: number, -- 0 dark … 1 full glow
	runePulse: boolean, -- pulse the rune glow (warning)
	flicker: number, -- light flicker amplitude, 0..1
}

local Color3Type: any = Color3 -- nil under Lune, where the tests get plain tables instead

local function rgb(r: number, g: number, b: number): Color3
	if Color3Type == nil then
		return { R = r / 255, G = g / 255, B = b / 255 } :: any
	end
	return Color3Type.fromRGB(r, g, b)
end

-- stylua: ignore
FireLook.LOOKS = {
	Day        = { flameSize = 5,  heat = 9,  flameColor = rgb(255, 150, 60), flameSecondary = rgb(255, 80, 30),  coreScale = 0.8, coreColor = rgb(255, 140, 50),  lightRange = 24, lightBrightness = 1.5, lightColor = rgb(255, 175, 100), embers = 4,  smoke = 0,    runeColor = rgb(120, 100, 80), runeGlow = 0,    runePulse = false, flicker = 0.05 },
	Roaring    = { flameSize = 11, heat = 16, flameColor = rgb(255, 230, 150), flameSecondary = rgb(255, 140, 40), coreScale = 1.3, coreColor = rgb(255, 170, 60), lightRange = 42, lightBrightness = 5,   lightColor = rgb(255, 190, 110), embers = 30, smoke = 0,    runeColor = rgb(255, 170, 60), runeGlow = 1,    runePulse = false, flicker = 0.08 },
	Steady     = { flameSize = 7,  heat = 11, flameColor = rgb(255, 165, 70), flameSecondary = rgb(255, 90, 30),  coreScale = 1.0, coreColor = rgb(255, 130, 40),  lightRange = 38, lightBrightness = 4,   lightColor = rgb(255, 175, 95),  embers = 14, smoke = 0,    runeColor = rgb(255, 140, 40), runeGlow = 0.7,  runePulse = false, flicker = 0.1 },
	Flickering = { flameSize = 4,  heat = 7,  flameColor = rgb(255, 110, 40), flameSecondary = rgb(200, 40, 20),  coreScale = 0.6, coreColor = rgb(255, 90, 30),  lightRange = 30, lightBrightness = 2.6, lightColor = rgb(255, 130, 70),  embers = 6,  smoke = 0.25, runeColor = rgb(255, 70, 50),  runeGlow = 0.8,  runePulse = true,  flicker = 0.25 },
	Dying      = { flameSize = 1.5, heat = 3, flameColor = rgb(220, 70, 30),  flameSecondary = rgb(120, 20, 10),  coreScale = 0.35, coreColor = rgb(200, 50, 20), lightRange = 24, lightBrightness = 1.4, lightColor = rgb(255, 100, 60),  embers = 2,  smoke = 0.4,  runeColor = rgb(200, 40, 40),  runeGlow = 0.45, runePulse = true,  flicker = 0.35 },
	Cold       = { flameSize = 0,  heat = 0,  flameColor = rgb(120, 150, 200), flameSecondary = rgb(60, 80, 120), coreScale = 0,   coreColor = rgb(90, 110, 150),  lightRange = 20, lightBrightness = 0.8, lightColor = rgb(120, 150, 220), embers = 0,  smoke = 0.15, runeColor = rgb(40, 45, 60),   runeGlow = 0,    runePulse = false, flicker = 0 },
} :: { [State]: Look }

-- The state for a fire level (0..1), or "Day" for nil.
function FireLook.state(level: number?): State
	if level == nil then
		return "Day"
	elseif level >= 0.75 then
		return "Roaring"
	elseif level >= 0.40 then
		return "Steady"
	elseif level >= 0.15 then
		return "Flickering"
	elseif level > 0 then
		return "Dying"
	end
	return "Cold"
end

function FireLook.look(level: number?): Look
	return FireLook.LOOKS[FireLook.state(level)]
end

-- The rune glow (0..1) at time `t` seconds: pulsing states swing between 30% and 100% of
-- their glow about once a second.
function FireLook.runeGlow(look: Look, t: number): number
	if not look.runePulse then
		return look.runeGlow
	end
	return look.runeGlow * (0.65 + 0.35 * math.sin(t * 2 * math.pi * 1.1))
end

return FireLook
