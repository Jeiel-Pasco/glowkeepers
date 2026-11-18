--!strict
-- Campfire maths (GAME_SYSTEMS §12, decision D1). Pure.
-- Levels are fractions: 0.6 = 60%. At 0 the night is Lost and feeding no longer helps.

local Fire = {}

export type Fuel = "wood" | "shard"
export type Feed = { t: number, kind: Fuel }
export type Outcome = { survived: boolean, level: number, lostAt: number? }

local function modifierValue(modifier: any?, key: string, default: number): number
	if modifier ~= nil and modifier[key] ~= nil then
		return modifier[key]
	end
	return default
end

function Fire.startLevel(cfg: any, modifier: any?): number
	return math.min(cfg.fire.max, modifierValue(modifier, "fireStart", cfg.fire.start))
end

-- Drain per second = (0.5% + 0.0375% × living players) × the night modifier's multiplier.
-- Downed players don't count as living.
function Fire.drainPerSecond(cfg: any, livingPlayers: number, modifier: any?): number
	local f = cfg.fire
	return (f.drainBase + f.drainPerPlayer * math.max(0, livingPlayers)) * modifierValue(modifier, "fireDrainMult", 1)
end

function Fire.feedAmount(cfg: any, kind: Fuel): number
	local amount = cfg.fire[kind]
	assert(type(amount) == "number", "unknown fuel kind")
	return amount
end

-- Advance the fire by dt seconds at a constant drain. Returns the new level (0 = lost).
function Fire.step(cfg: any, level: number, drainPerSecond: number, dt: number): number
	if level <= 0 then
		return 0
	end
	return math.clamp(level - drainPerSecond * dt, 0, cfg.fire.max)
end

function Fire.feed(cfg: any, level: number, kind: Fuel): number
	if level <= 0 then
		return 0
	end
	return math.min(cfg.fire.max, level + Fire.feedAmount(cfg, kind))
end

function Fire.secondsLeft(level: number, drainPerSecond: number): number
	if drainPerSecond <= 0 then
		return math.huge
	end
	return math.max(0, level) / drainPerSecond
end

-- Embers at dawn (GAME_SYSTEMS §14). Survived: 10 + floor(fire% / 10) + 5 × revives (max 4)
-- + 1 × pieces fed (max 6), times the friend bonus (+10% per friend in the server, max +30%).
-- Lost: the consolation 3, with no bonus.
function Fire.dawnEmbers(
	cfg: any,
	survived: boolean,
	level: number,
	revives: number,
	piecesFed: number,
	friends: number?
): number
	local e = cfg.embers
	if not survived then
		return e.failConsolation
	end
	local tenths = math.floor(math.clamp(level, 0, cfg.fire.max) * 10 + 1e-9) -- 0.7 * 10 is 7.000…01 or 6.999…
	local base = e.surviveBase
		+ e.perFireTenPct * tenths
		+ e.perRevive * math.min(math.max(0, revives), e.reviveCap)
		+ e.perPiece * math.min(math.max(0, piecesFed), e.pieceCap)
	local bonus = math.min(e.friendBonusPer * math.max(0, friends or 0), e.friendBonusCap)
	return math.floor(base * (1 + bonus) + 1e-9)
end

-- Plays one whole night exactly: constant drain between feeds, no time steps.
-- Used by the tests and for balance checks; sim/golden_odds.py mirrors it line for line.
function Fire.simulate(cfg: any, livingPlayers: number, feeds: { Feed }, modifier: any?, nightSeconds: number?): Outcome
	local duration = nightSeconds or cfg.cycle.nightSeconds
	local drain = Fire.drainPerSecond(cfg, livingPlayers, modifier)
	local ordered = table.clone(feeds)
	table.sort(ordered, function(a, b)
		return a.t < b.t
	end)

	local level = Fire.startLevel(cfg, modifier)
	local now = 0
	for _, feed in ordered do
		if feed.t > duration then
			break
		end
		local t = math.max(feed.t, now)
		local before = level - drain * (t - now)
		if before <= 0 then
			return { survived = false, level = 0, lostAt = now + level / drain }
		end
		level = math.min(cfg.fire.max, before + Fire.feedAmount(cfg, feed.kind))
		now = t
	end

	local final = level - drain * (duration - now)
	if final <= 0 then
		return { survived = false, level = 0, lostAt = now + level / drain }
	end
	return { survived = true, level = final }
end

return Fire
