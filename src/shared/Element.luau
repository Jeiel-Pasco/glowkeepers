--!strict
-- The type chart (GDD "Types"). Pure.
--   Fire > Leaf > Water > Fire (1.5×, the other way 0.67×); Neutral is 1× both ways;
--   Light and Dark hit each other for 1.5× and everything else for 1.25×.
-- A player's defending type is their equipped grimoire's type.

local Element = {}

export type Type = "Neutral" | "Fire" | "Water" | "Leaf" | "Light" | "Dark"

Element.TYPES = { "Neutral", "Fire", "Water", "Leaf", "Light", "Dark" } :: { Type }
Element.ELEMENTS = { "Fire", "Water", "Leaf" } :: { Type } -- the starter picks
Element.STRONG = 1.5
Element.WEAK = 0.67
Element.MYTHIC = 1.25

local BEATS: { [string]: string } = { Fire = "Leaf", Leaf = "Water", Water = "Fire" }

-- Colours for UI and spell effects (muted enough for the forest, bright enough to read).
Element.COLOR = {
	Neutral = { 196, 188, 230 },
	Fire = { 255, 136, 60 },
	Water = { 92, 180, 255 },
	Leaf = { 120, 210, 96 },
	Light = { 255, 232, 150 },
	Dark = { 150, 96, 220 },
} :: { [string]: { number } }

function Element.isType(value: any): boolean
	return type(value) == "string" and table.find(Element.TYPES, value :: any) ~= nil
end

-- Damage multiplier for an attack of type `attack` on a defender of type `defend`.
function Element.mult(attack: string, defend: string): number
	if attack == "Light" or attack == "Dark" then
		if (attack == "Light" and defend == "Dark") or (attack == "Dark" and defend == "Light") then
			return Element.STRONG
		elseif defend == "Light" or defend == "Dark" then
			return 1
		end
		return Element.MYTHIC
	end
	if attack == "Neutral" or defend == "Neutral" or defend == "Light" or defend == "Dark" then
		return 1
	end
	if BEATS[attack] == defend then
		return Element.STRONG
	elseif BEATS[defend] == attack then
		return Element.WEAK
	end
	return 1
end

return Element
