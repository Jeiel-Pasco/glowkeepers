--!strict
-- Levels, stats and the damage formula (GDD "Getting stronger", "Combat"). Pure.

local Level = {}

Level.CAP = 15 -- the slice's cap; the full game is 60
Level.POINTS_PER_LEVEL = 3
Level.STATS = { "health", "power", "defense" }
Level.BASE_HEALTH = 100
Level.HEALTH_PER_LEVEL = 10
Level.HEALTH_PER_POINT = 12
Level.POWER_PER_POINT = 0.02
Level.DEFENSE_PER_POINT = 0.02
Level.GROWTH = 0.1 -- a player's damage grows 10% per level; enemies grow at the same rate

-- The level part of a player's damage.
function Level.power(level: number): number
	return 1 + Level.GROWTH * (math.max(level, 1) - 1)
end

-- XP needed to go from `level` to `level + 1`.
function Level.xpToNext(level: number): number
	return math.floor(40 * level ^ 1.6)
end

-- Adds XP; returns the new level, the XP left over, and how many levels were gained.
function Level.addXp(level: number, xp: number, gained: number): (number, number, number)
	local ups = 0
	xp += math.max(0, gained)
	while level < Level.CAP and xp >= Level.xpToNext(level) do
		xp -= Level.xpToNext(level)
		level += 1
		ups += 1
	end
	if level >= Level.CAP then
		xp = 0
	end
	return level, xp, ups
end

function Level.maxHealth(level: number, healthPoints: number): number
	return Level.BASE_HEALTH + (level - 1) * Level.HEALTH_PER_LEVEL + healthPoints * Level.HEALTH_PER_POINT
end

-- Points spent so far must never exceed the points earned.
function Level.pointsEarned(level: number): number
	return (level - 1) * Level.POINTS_PER_LEVEL
end

-- The damage formula: base × spell level × power × type ÷ defense.
function Level.damage(base: number, levelScale: number, power: number, mult: number, defense: number): number
	return base * levelScale * (1 + power * Level.POWER_PER_POINT) * mult / (1 + defense * Level.DEFENSE_PER_POINT)
end

return Level
