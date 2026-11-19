--!strict
-- Trading rules (GAME_SYSTEMS §17, D12). Pure: no requires and no engine calls.
--
-- Unlock: Stars ≥ trade.minStars, trade.minPlayDays play days, account age ≥
-- trade.minAccountAgeDays, PolicyService allows trading, and the kill switch is off (both
-- players). Each side offers up to trade.maxPerSide Glowlings from storage (not on a pad, not
-- held, not trade-locked). Only Glowlings: no Glow, no Embers. Confirm unlocks
-- trade.confirmDelay s after the last change; the receiver pays a fee per Glowling received
-- (trade.feeByRarity). Traded Glowlings are locked for trade.tradeLockHours.

local Trade = {}

export type Unlock = { stars: number, playDays: number, accountAge: number, policy: boolean, killed: boolean }

-- nil if this player may trade, else: killed, policy, stars, days, account.
function Trade.unlockReason(cfg: any, u: Unlock): string?
	if u.killed then
		return "killed"
	elseif not u.policy then
		return "policy"
	elseif u.stars < cfg.trade.minStars then
		return "stars"
	elseif u.playDays < cfg.trade.minPlayDays then
		return "days"
	elseif u.accountAge < cfg.trade.minAccountAgeDays then
		return "account"
	end
	return nil
end

local function placed(data: any): { [string]: boolean }
	local set = {}
	for _, map in { data.vault, data.display } do
		for _, id in map do
			set[id] = true
		end
	end
	return set
end

-- nil if `ids` is a valid offer, else: too_many, duplicate, not_owned, placed, held, trade_locked.
-- An empty offer is valid (a gift trade).
function Trade.offerReason(cfg: any, data: any, ids: { string }, held: { [string]: boolean }?, unix: number): string?
	if #ids > cfg.trade.maxPerSide then
		return "too_many"
	end
	local onPad = placed(data)
	local seen = {}
	for _, id in ids do
		local record = data.glowlings[id]
		if seen[id] then
			return "duplicate"
		elseif record == nil then
			return "not_owned"
		elseif onPad[id] then
			return "placed"
		elseif held ~= nil and held[id] then
			return "held"
		elseif (tonumber(record.tradeLockUntil) or 0) > unix then
			return "trade_locked"
		end
		seen[id] = true
	end
	return nil
end

-- Embers the receiver of these records pays.
function Trade.fee(cfg: any, records: { any }): number
	local total = 0
	for _, record in records do
		total += cfg.trade.feeByRarity[record.r] or 0
	end
	return total
end

-- "This trade looks uneven": one side's income value is 5× or more the other's.
function Trade.uneven(a: number, b: number): boolean
	local low, high = math.min(a, b), math.max(a, b)
	if high <= 0 then
		return false
	end
	return high >= 5 * low
end

-- nil if this side may confirm, else: wait (confirm unlocks confirmDelay s after the last
-- change), fee (can't pay for what they receive).
function Trade.confirmReason(cfg: any, lastChange: number, now: number, embers: number, fee: number): string?
	if now < lastChange + cfg.trade.confirmDelay then
		return "wait"
	elseif embers < fee then
		return "fee"
	end
	return nil
end

-- Whether storage holds what this side ends up with: storage now + received − given ≤ size.
function Trade.roomFor(stored: number, received: number, given: number, size: number): boolean
	return stored + received - given <= size
end

return Trade
