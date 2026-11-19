--!strict
-- Rebirth rules (GAME_SYSTEMS §15, D3). Pure: no requires and no engine calls. Callers pass in
-- what depends on config (the requirement from Economy.rebirthRequirement, and `valueOf`).
--
-- Wiped: Glow, Lantern, Boots, Slots (back to 8), and display and storage Glowlings.
-- Kept: the vault, the single best Glowling outside the vault (it goes to storage), Embers,
-- Stars (+1), decorations, the Glowdex, the Night Pass, Lock Charges and quests.

local Rebirth = {}

export type Check = {
	glowSinceRebirth: number,
	requirement: number, -- Economy.rebirthRequirement(cfg, stars)
	carrying: boolean, -- carrying a stolen Glowling
	busy: boolean, -- any of this player's Glowlings is held (grabbed by a thief, or in a trade)
}

export type Result = {
	removed: { string }, -- ids wiped
	best: string?, -- the best Glowling outside the vault, kept in storage
}

function Rebirth.canRebirth(c: Check): (boolean, string?)
	if c.glowSinceRebirth < c.requirement then
		return false, "too_early"
	elseif c.carrying then
		return false, "carrying"
	elseif c.busy then
		return false, "busy"
	end
	return true, nil
end

-- Glow still to earn for the next Star (0 when it's ready).
function Rebirth.remaining(glowSinceRebirth: number, requirement: number): number
	return math.max(0, requirement - glowSinceRebirth)
end

-- The best Glowling outside the vault (by value, then oldest, then id), or nil.
function Rebirth.bestOutsideVault(data: any, valueOf: (record: any) -> number): string?
	local inVault = {}
	for _, id in data.vault do
		inVault[id] = true
	end
	local bestId, bestValue = nil, -math.huge
	for id, record in data.glowlings do
		if inVault[id] then
			continue
		end
		local value = valueOf(record)
		local better = value > bestValue
		if not better and value == bestValue and bestId ~= nil then
			local held = data.glowlings[bestId]
			better = record.at < held.at or (record.at == held.at and id < bestId)
		end
		if better then
			bestId, bestValue = id, value
		end
	end
	return bestId
end

-- Applies a rebirth to the profile in place. The caller checks canRebirth first.
function Rebirth.apply(data: any, valueOf: (record: any) -> number): Result
	local best = Rebirth.bestOutsideVault(data, valueOf)
	local keep = {}
	for _, id in data.vault do
		keep[id] = true
	end
	if best ~= nil then
		keep[best] = true
	end
	local removed = {}
	for id in data.glowlings do
		if not keep[id] then
			table.insert(removed, id)
		end
	end
	table.sort(removed)
	for _, id in removed do
		data.glowlings[id] = nil
	end
	data.display = {}
	data.glow = 0
	data.glowSinceRebirth = 0
	data.up = { lantern = 0, boots = 0, slots = 0 }
	data.stars += 1
	if type(data.stats) == "table" then
		data.stats.rebirths = (tonumber(data.stats.rebirths) or 0) + 1
	end
	return { removed = removed, best = best }
end

return Rebirth
