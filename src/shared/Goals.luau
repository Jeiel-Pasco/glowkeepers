--!strict
-- Goal tracker rules (GAME_SYSTEMS §19 †). Pure: no requires and no engine calls; the caller
-- passes config and whatever it already computed (upgrade prices, rebirth requirement).
--
-- Candidates get an estimate in seconds from current income. One cycle is day + night. Bands:
--   Next     within 1 cycle
--   Session  1 to 5 cycles
--   Long     more than 5 cycles (a Glowdex page or a weekly quest)
-- Each band shows its closest candidate. A band with none borrows the unused candidate nearest
-- its range, so the tracker always shows 3 goals (when there are 3 candidates at all).
-- Estimates are rough: Glow goals = Glow left / income; a weekly quest = its pace so far this
-- week; a Glowdex page = one night per missing rarity.

local Goals = {}

local DAY = 86400
Goals.SESSION_CYCLES = 5

export type Goal = {
	kind: string, -- "upgrade" | "rebirth" | "quest" | "dex"
	name: string, -- "Lantern 5", "Rebirth", quest text, species name
	need: number?, -- Glow still to earn (Glow goals)
	pct: number?, -- 0..1 progress (rebirth, quest, dex)
	seconds: number, -- estimate; 0 = ready now, math.huge = no estimate
}

export type Input = {
	glow: number,
	since: number, -- Glow earned since the last rebirth
	perSec: number,
	unix: number, -- os.time(), for the weekly pace
	upgrades: { { name: string, cost: number? } }, -- next level name and price (nil = maxed)
	rebirthRequirement: number,
	weekly: { any }?, -- data.quests.weekly
	questName: ((event: string) -> string)?,
	dex: { [string]: any }?, -- data.dex
	dexClaimed: { [string]: any }?, -- data.dexClaimed
	species: { { id: string, name: string } }?,
}

function Goals.cycleSeconds(cfg: any): number
	return cfg.cycle.daySeconds + cfg.cycle.nightSeconds
end

local function glowSeconds(left: number, perSec: number): number
	if left <= 0 then
		return 0
	elseif perSec <= 0 then
		return math.huge
	end
	return left / perSec
end

-- Seconds since Monday 00:00 UTC.
function Goals.weekElapsed(unix: number): number
	return ((unix // DAY + 3) % 7) * DAY + unix % DAY
end

local function popcount(mask: number): number
	local n = 0
	while mask ~= 0 do
		mask = bit32.band(mask, mask - 1)
		n += 1
	end
	return n
end

-- Rarities missing for the next unclaimed page tier of one species (nil = all tiers claimed).
function Goals.dexMissing(cfg: any, entry: any, claimed: number): number?
	local tier = cfg.glowdex.tiers[claimed + 1]
	if tier == nil then
		return nil
	end
	local mask = if type(entry) == "table" then tonumber(entry.r) or 0 else 0
	local want = bit32.lshift(1, tier.needs) - 1
	return tier.needs - popcount(bit32.band(mask, want))
end

function Goals.candidates(cfg: any, input: Input): { Goal }
	local list: { Goal } = {}
	for _, up in input.upgrades do
		if up.cost ~= nil then
			local need = math.max(0, up.cost - input.glow)
			table.insert(list, {
				kind = "upgrade",
				name = up.name,
				need = need,
				seconds = glowSeconds(need, input.perSec),
			})
		end
	end

	local req = input.rebirthRequirement
	if req > 0 then
		table.insert(list, {
			kind = "rebirth",
			name = "Rebirth",
			pct = math.clamp(input.since / req, 0, 1),
			seconds = glowSeconds(req - input.since, input.perSec),
		})
	end

	local elapsed = math.max(1, Goals.weekElapsed(input.unix))
	for _, q in input.weekly or {} do
		local n, target = tonumber(q.n) or 0, tonumber(q.target) or 0
		if q.claimed or target <= 0 then
			continue
		end
		local seconds
		if n >= target then
			seconds = 0
		elseif q.event == "glow" then
			seconds = glowSeconds(target - n, input.perSec)
		elseif n > 0 then
			seconds = (target - n) * elapsed / n
		else
			seconds = math.huge
		end
		table.insert(list, {
			kind = "quest",
			name = if input.questName then input.questName(q.event) else q.event,
			pct = math.clamp(n / target, 0, 1),
			seconds = seconds,
		})
	end

	-- The species page closest to its next tier.
	local best: Goal? = nil
	local dex, claimed = input.dex or {}, input.dexClaimed or {}
	for _, sp in input.species or {} do
		local done = tonumber(claimed[sp.id]) or 0
		local missing = Goals.dexMissing(cfg, dex[sp.id], done)
		if missing ~= nil then
			local needs = cfg.glowdex.tiers[done + 1].needs
			local seconds = missing * Goals.cycleSeconds(cfg)
			if best == nil or seconds < best.seconds then
				best = {
					kind = "dex",
					name = `{sp.name} {cfg.glowdex.tiers[done + 1].id}`,
					pct = (needs - missing) / needs,
					seconds = seconds,
				}
			end
		end
	end
	if best ~= nil then
		table.insert(list, best)
	end
	return list
end

-- Band ranges in seconds: { lo, hi } (lo exclusive except Next).
local function bands(cfg: any): { { number } }
	local c = Goals.cycleSeconds(cfg)
	return { { -1, c }, { c, Goals.SESSION_CYCLES * c }, { Goals.SESSION_CYCLES * c, math.huge } }
end

local function distance(seconds: number, band: { number }): number
	if seconds <= band[1] then
		return band[1] - seconds
	elseif seconds > band[2] then
		return seconds - band[2]
	end
	return 0
end

-- The 3 goals { next, session, long }; an entry is nil only when candidates ran out.
function Goals.pick(cfg: any, list: { Goal }): { Goal? }
	local used: { [Goal]: boolean } = {}
	local out: { Goal? } = {}
	local ranges = bands(cfg)
	-- First pass: the closest candidate inside each band.
	for i, band in ranges do
		local pick: Goal? = nil
		for _, g in list do
			if distance(g.seconds, band) == 0 and (pick == nil or g.seconds < pick.seconds) then
				pick = g
			end
		end
		if pick ~= nil then
			used[pick] = true
			out[i] = pick
		end
	end
	-- Second pass: empty bands borrow the nearest unused candidate.
	for i, band in ranges do
		if out[i] == nil then
			local pick: Goal? = nil
			for _, g in list do
				if not used[g] and (pick == nil or distance(g.seconds, band) < distance(pick.seconds, band)) then
					pick = g
				end
			end
			if pick ~= nil then
				used[pick] = true
				out[i] = pick
			end
		end
	end
	return out
end

-- "now", "<1 night", "~3 nights" or "?" (no income or no pace yet).
function Goals.eta(cfg: any, seconds: number): string
	if seconds <= 0 then
		return "now"
	elseif seconds == math.huge then
		return "?"
	end
	local nights = seconds / Goals.cycleSeconds(cfg)
	if nights < 1 then
		return "<1 night"
	end
	local n = math.floor(nights + 0.5)
	return if n == 1 then "~1 night" else `~{n} nights`
end

-- The tracker line. `fmt` formats Glow amounts (EconomyMath.formatNumber on the client).
function Goals.text(cfg: any, goal: Goal, fmt: (number) -> string): string
	local eta = Goals.eta(cfg, goal.seconds)
	if goal.need ~= nil then
		if goal.need <= 0 then
			return `{goal.name}: ready to buy`
		end
		return `{goal.name}: {fmt(goal.need)} Glow to go ({eta})`
	end
	local pct = math.floor((goal.pct or 0) * 100)
	if goal.seconds <= 0 then
		return `{goal.name}: ready!`
	end
	return `{goal.name}: {pct}% ({eta})`
end

return Goals
