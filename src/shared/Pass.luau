--!strict
-- Night Pass rules (GAME_SYSTEMS §20). Pure: no requires and no engine calls.
--
-- Seasons are pass.seasonWeeks long, numbered from 1 at pass.s1Start (0 before it). 50 tiers
-- of 1,000 XP. In the last pass.catchUpWeeks of a season, XP counts ×pass.catchUpMult.
-- The profile keeps `pass = { season, xp, premium, free, prem }`; `free`/`prem` map a tier
-- (as a string, TECH_SPEC §5) to true once claimed.
--
-- Free track: every 2nd tier (Embers, a lure every pass.free.lureEvery free tiers, a few
-- decorations). Premium: every tier (Embers, and a cosmetic every pass.premium.cosmeticEvery
-- tiers). Premium is bought per season: a developer product (Phase 5) or pass.premiumEmbers.

local Pass = {}

local WEEK = 7 * 86400

export type Reward = { kind: string, amount: number?, floor: number?, id: string? }

-- The season at `unix` (0 = before season 1), and when it started and ends.
function Pass.season(cfg: any, unix: number): (number, number, number)
	local length = cfg.pass.seasonWeeks * WEEK
	if unix < cfg.pass.s1Start then
		return 0, 0, cfg.pass.s1Start
	end
	local index = (unix - cfg.pass.s1Start) // length
	local start = cfg.pass.s1Start + index * length
	return index + 1, start, start + length
end

function Pass.multiplier(cfg: any, unix: number): number
	local season, _, finish = Pass.season(cfg, unix)
	if season > 0 and finish - unix <= cfg.pass.catchUpWeeks * WEEK then
		return cfg.pass.catchUpMult
	end
	return 1
end

-- XP actually added for `amount` at `unix` (whole numbers).
function Pass.xpFor(cfg: any, amount: number, unix: number): number
	return math.floor(amount * Pass.multiplier(cfg, unix))
end

function Pass.tier(cfg: any, xp: number): number
	return math.min(cfg.pass.tiers, xp // cfg.pass.xpPerTier)
end

function Pass.fresh(season: number): any
	return { season = season, xp = 0, premium = false, free = {}, prem = {} }
end

-- The reward on a track ("free" | "prem") at a tier, or nil (free has only even tiers).
function Pass.reward(cfg: any, track: string, tier: number, season: number): Reward?
	if tier < 1 or tier > cfg.pass.tiers or tier ~= math.floor(tier) then
		return nil
	end
	if track == "free" then
		if tier % 2 == 1 then
			return nil
		end
		local free = cfg.pass.free
		local decor = free.decor[tostring(tier)]
		if decor ~= nil then
			return { kind = "decor", id = decor }
		elseif (tier // 2) % free.lureEvery == 0 then
			return { kind = "lure", floor = free.lureFloor }
		end
		return { kind = "embers", amount = free.embers }
	elseif track == "prem" then
		local prem = cfg.pass.premium
		if tier % prem.cosmeticEvery == 0 then
			local list = prem.cosmetics
			local name = list[(tier // prem.cosmeticEvery - 1) % #list + 1]
			return { kind = "cosmetic", id = `s{season}_{name}_{tier}` }
		end
		return { kind = "embers", amount = prem.embers }
	end
	return nil
end

-- The reward to claim, or nil and a reason: no_reward, locked (tier not reached), premium
-- (premium track without premium), claimed.
function Pass.canClaim(cfg: any, pass: any, track: string, tier: number): (Reward?, string?)
	local reward = Pass.reward(cfg, track, tier, pass.season)
	if reward == nil then
		return nil, "no_reward"
	elseif tier > Pass.tier(cfg, pass.xp) then
		return nil, "locked"
	elseif track == "prem" and not pass.premium then
		return nil, "premium"
	end
	local claimed = if track == "free" then pass.free else pass.prem
	if claimed[tostring(tier)] then
		return nil, "claimed"
	end
	return reward, nil
end

-- Every reached, unclaimed { track, tier } (the end-of-season auto-claim), in tier order.
function Pass.unclaimed(cfg: any, pass: any): { { track: string, tier: number } }
	local out = {}
	for tier = 1, Pass.tier(cfg, pass.xp) do
		for _, track in { "free", "prem" } do
			if Pass.canClaim(cfg, pass, track, tier) ~= nil then
				table.insert(out, { track = track, tier = tier })
			end
		end
	end
	return out
end

-- Embers over the whole premium track (GAME_SYSTEMS §20: about 1,500).
function Pass.premiumEmbersTotal(cfg: any): number
	local total = 0
	for tier = 1, cfg.pass.tiers do
		local reward = Pass.reward(cfg, "prem", tier, 1)
		if reward and reward.kind == "embers" then
			total += reward.amount :: number
		end
	end
	return total
end

return Pass
