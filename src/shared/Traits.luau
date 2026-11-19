--!strict
-- Pet traits on placed Glowlings (GAME_SYSTEMS §31, D20–D23). Pure: callers pass config and
-- which species sits on which pad, so the server, the client and Lune all run the same rules.
--
-- v1: family link, Harmonizer (neighbours, or the whole plot for Skywhale Calf and Lunadrake),
-- the ×cap on the combined Glow/s multiplier, and Guardian grab time (Elder Sapling: every
-- display pad). Infuser Overcharge, Forager pouches and the night companion traits come later.
--
-- Pads use the map's Slot numbers (Inventory, TECH_SPEC §6a). PAD_POS mirrors
-- tools/BuildGreybox.luau: pads 1–6 in two side strips, pads 7–30 in three rows of eight, 4 studs
-- apart; two pads are neighbours when they share an edge (4 studs apart).

local Traits = {}

export type Species = { id: string, family: string?, trait: string?, minRarity: string? }
export type Placed = { [number]: string } -- pad → species id

local PAD_POS: { { number } } = {}
for _, z in { 8, 4, 0 } do
	table.insert(PAD_POS, { -15, z })
	table.insert(PAD_POS, { 15, z })
end
for _, z in { -8, -12, -16 } do
	for x = -14, 14, 4 do
		table.insert(PAD_POS, { x, z })
	end
end
Traits.PAD_POS = PAD_POS

local neighbourCache: { [number]: { number } } = {}

-- Pads that share an edge with `pad`.
function Traits.neighbours(pad: number): { number }
	local cached = neighbourCache[pad]
	if cached ~= nil then
		return cached
	end
	local list = {}
	local at = PAD_POS[pad]
	if at ~= nil then
		for other, pos in PAD_POS do
			local dx, dz = math.abs(pos[1] - at[1]), math.abs(pos[2] - at[2])
			if other ~= pad and dx + dz > 3.9 and dx + dz < 4.1 then
				table.insert(list, other)
			end
		end
	end
	neighbourCache[pad] = list
	return list
end

-- Rarity index of a species' floor (1 = Common when unset).
function Traits.floor(cfg: any, species: Species?): number
	local id = if species ~= nil then species.minRarity else nil
	if id ~= nil then
		for i, rarity in cfg.rarities do
			if rarity.id == id then
				return i
			end
		end
	end
	return 1
end

local function apex(cfg: any, speciesId: string): any
	return cfg.traits.apex[speciesId]
end

-- The Glow/s multiplier of every occupied pad: family link × Harmonizer × whole-plot bonus,
-- at most cfg.traits.cap.
function Traits.multipliers(cfg: any, species: { [string]: Species }, placed: Placed): { [number]: number }
	local t = cfg.traits
	local plotGlow = 0 -- whole-plot bonuses don't stack: the highest counts
	for _, id in placed do
		local a = apex(cfg, id)
		if a ~= nil and a.plotGlow ~= nil then
			plotGlow = math.max(plotGlow, a.plotGlow)
		end
	end
	local result = {}
	for pad, id in placed do
		local mine = species[id]
		local family = if mine ~= nil then mine.family else nil
		local same, harmonized = 0, false
		for _, n in Traits.neighbours(pad) do
			local other = placed[n]
			local theirs = if other ~= nil then species[other] else nil
			if theirs ~= nil and family ~= nil and theirs.family == family then
				same += 1
				-- An apex Harmonizer works on the whole plot instead of its neighbours.
				if theirs.trait == "Harmonizer" and apex(cfg, other :: string) == nil then
					harmonized = true
				end
			end
		end
		local link = 1 + math.min(t.familyLinkMax, t.familyLinkPer * same)
		local harmony = if harmonized then 1 + t.harmonizer else 1
		result[pad] = math.min(t.cap, link * harmony * (1 + plotGlow))
	end
	return result
end

-- Extra grab seconds on `pad` from Guardians: the best one on the pad or next to it (+more for a
-- floor of Rare or higher), plus the best whole-plot bonus on display pads; at most guardianMax.
function Traits.grabBonus(
	cfg: any,
	species: { [string]: Species },
	placed: Placed,
	pad: number,
	display: boolean
): number
	local t = cfg.traits
	local rare = 3
	local localBonus = 0
	local function consider(id: string?)
		local s = if id ~= nil then species[id] else nil
		if s ~= nil and s.trait == "Guardian" and apex(cfg, s.id) == nil then
			local bonus = if Traits.floor(cfg, s) >= rare then t.guardianHigh else t.guardian
			localBonus = math.max(localBonus, bonus)
		end
	end
	consider(placed[pad])
	for _, n in Traits.neighbours(pad) do
		consider(placed[n])
	end
	local plotBonus = 0
	if display then
		for _, id in placed do
			local a = apex(cfg, id)
			if a ~= nil and a.plotGrab ~= nil then
				plotBonus = math.max(plotBonus, a.plotGrab)
			end
		end
	end
	return math.min(t.guardianMax, localBonus + plotBonus)
end

return Traits
