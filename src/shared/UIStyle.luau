--!strict
-- The HUD look (lantern-lit wood at night): tokens and colour maths for ThemeController.
-- Pure: colours are { r, g, b } in 0..255 so Lune can test them.
--
--   panel     warm plum-night, the background of every dark panel and button
--   rim       lantern gold, a thin border round dark panels
--   accent    a coloured button keeps its colour and gets a rim one shade darker

local UIStyle = {}

export type RGB = { number }

UIStyle.PANEL = { 30, 24, 44 } :: RGB
UIStyle.RIM = { 236, 190, 96 } :: RGB
UIStyle.RIM_TRANSPARENCY = 0.45
UIStyle.RIM_THICKNESS = 1.5
UIStyle.SHEEN = 0.12 -- how much lighter the top of a panel is than its bottom
UIStyle.PRESS_SCALE = 0.94
UIStyle.DARK_BELOW = 0.22 -- luminance under this counts as a dark panel

function UIStyle.luminance(rgb: RGB): number
	return (0.2126 * rgb[1] + 0.7152 * rgb[2] + 0.0722 * rgb[3]) / 255
end

function UIStyle.isDark(rgb: RGB): boolean
	return UIStyle.luminance(rgb) < UIStyle.DARK_BELOW
end

-- `rgb` moved toward black (amount < 0) or white (amount > 0), amount in -1..1.
function UIStyle.shade(rgb: RGB, amount: number): RGB
	local out = {}
	for i = 1, 3 do
		local c = rgb[i]
		local target = if amount < 0 then 0 else 255
		out[i] = math.floor(c + (target - c) * math.abs(amount) + 0.5)
	end
	return out
end

-- How a background is skinned: dark panels take the panel colour and a gold rim; coloured
-- buttons keep their colour and get a darker rim of their own.
function UIStyle.skin(background: RGB): { fill: RGB, rim: RGB, rimTransparency: number }
	if UIStyle.isDark(background) then
		return { fill = UIStyle.PANEL, rim = UIStyle.RIM, rimTransparency = UIStyle.RIM_TRANSPARENCY }
	end
	return { fill = background, rim = UIStyle.shade(background, -0.45), rimTransparency = 0.1 }
end

return UIStyle
