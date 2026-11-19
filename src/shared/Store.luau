--!strict
-- Store rules (GAME_SYSTEMS §23). Pure: no requires and no engine calls.
--
-- Passes and developer products are defined in economy.store; their Roblox ids per
-- environment are in config/products.json (0 = not created yet: the item can't be bought).
-- Daily caps (per capGroup) are checked before prompting; a receipt that still arrives is
-- always granted. `daily = { day, buys }` in the profile counts today's buys per capGroup.

local Store = {}

local DAY = 86400

function Store.pass(cfg: any, key: string): any?
	for _, p in cfg.store.passes do
		if p.key == key then
			return p
		end
	end
	return nil
end

function Store.product(cfg: any, key: string): any?
	for _, p in cfg.store.products do
		if p.key == key then
			return p
		end
	end
	return nil
end

-- Every pass and product key, for the PromptProduct enum.
function Store.keys(cfg: any): { string }
	local keys = {}
	for _, p in cfg.store.passes do
		table.insert(keys, p.key)
	end
	for _, p in cfg.store.products do
		table.insert(keys, p.key)
	end
	return keys
end

-- Restarts the daily counts on a new UTC day.
function Store.rollDay(daily: any, unix: number)
	local day = unix // DAY
	if daily.day ~= day then
		daily.day = day
		daily.buys = {}
	end
end

function Store.boughtToday(daily: any, group: string): number
	return tonumber(daily.buys[group]) or 0
end

function Store.countBuy(daily: any, group: string?)
	if group ~= nil then
		daily.buys[group] = Store.boughtToday(daily, group) + 1
	end
end

export type PromptCheck = {
	key: string,
	id: number, -- the Roblox id in this environment (0 = none)
	killed: boolean, -- live config switched this product off
	paidRandomRestricted: boolean, -- PolicyService
	owned: boolean, -- a pass the player has
	daily: any, -- profile `daily`, already rolled to today
	carrying: boolean, -- mid-theft (thief carrying, or their own Glowling is being carried)
	now: number,
	lostGlowlingAt: number, -- server time; 0 = never
	lostNightAt: number,
	season: number, -- Night Pass season (0 = none)
	premium: boolean,
}

-- nil if the client may be prompted, else a reason: unknown, owned, unavailable, policy, cap,
-- busy (no prompts mid-theft or right after a loss, D6), no_season, premium_owned.
function Store.canPrompt(cfg: any, check: PromptCheck): string?
	local pass = Store.pass(cfg, check.key)
	local product = Store.product(cfg, check.key)
	if pass == nil and product == nil then
		return "unknown"
	elseif pass ~= nil and check.owned then
		return "owned"
	elseif check.id <= 0 or check.killed then
		return "unavailable"
	elseif product ~= nil and product.paidRandom and check.paidRandomRestricted then
		return "policy"
	end
	if product ~= nil and product.capGroup ~= nil then
		local cap = cfg.store.dailyCaps[product.capGroup]
		if cap ~= nil and Store.boughtToday(check.daily, product.capGroup) >= cap then
			return "cap"
		end
	end
	if
		check.carrying
		or check.now - check.lostGlowlingAt < cfg.store.lostGlowlingQuietSeconds
		or check.now - check.lostNightAt < cfg.store.lostNightQuietSeconds
	then
		return "busy"
	end
	if product ~= nil and product.kind == "passPremium" then
		if check.season <= 0 then
			return "no_season"
		elseif check.premium then
			return "premium_owned"
		end
	end
	return nil
end

-- Records a granted PurchaseId; keeps the newest `keep`. Returns false if it was already there.
function Store.recordReceipt(receipts: { [string]: number }, purchaseId: string, now: number, keep: number): boolean
	if receipts[purchaseId] ~= nil then
		return false
	end
	receipts[purchaseId] = now
	local ids = {}
	for id in receipts do
		table.insert(ids, id)
	end
	if #ids > keep then
		table.sort(ids, function(a, b)
			return receipts[a] < receipts[b]
		end)
		for i = 1, #ids - keep do
			receipts[ids[i]] = nil
		end
	end
	return true
end

-- When Server Luck ends after one more purchase: +minutes from now or from the current end,
-- whichever is later, never more than maxMinutes from now.
function Store.extendLuck(cfg: any, currentEnd: number, now: number): number
	local base = math.max(currentEnd, now)
	local luck = cfg.store.serverLuck
	return math.min(base + luck.minutes * 60, now + luck.maxMinutes * 60)
end

-- The luck multiplier from Server Luck at `now`.
function Store.serverLuckMult(cfg: any, endsAt: number, now: number): number
	return if endsAt > now then cfg.store.serverLuck.mult else 1
end

return Store
