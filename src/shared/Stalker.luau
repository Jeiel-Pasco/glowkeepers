--!strict
-- The Stalker's brain (GAME_SYSTEMS §13). Pure: no requires and no engine calls; positions are
-- flat x/z pairs. StalkerService senses the world, calls step, and moves the model.
--
--   Dormant  the first cycle.stalkerGraceSeconds of the night
--   Prowl    wanders outside the fire's light; picks the nearest lone target
--   Stalk    follows the target; after stalker.stalkSeconds with the target still lone: Lunge.
--            The whole Stalk is the telegraph, so every lunge has at least telegraphSeconds.
--   Lunge    a burst at the target for lungeSeconds: a touch downs them, else a miss
--   Retreat  backs off for retreatSeconds, then prowls again
--
-- Repelled (from Prowl, Stalk or Lunge into Retreat) inside the lit fire's radius, or near a
-- group of repelGroupSize players. A lone target has nobody within loneRadius and is outside
-- the lit fire's radius. Once the fire is out, its radius protects nobody.

local Stalker = {}

export type State = "Dormant" | "Prowl" | "Stalk" | "Lunge" | "Retreat"
export type Brain = { state: State, since: number, target: number? }
export type Point = { x: number, z: number }
export type Fire = { x: number, z: number, radius: number, lit: boolean }

export type Sense = {
	now: number,
	nightElapsed: number, -- seconds since night began
	repelled: boolean, -- see Stalker.repelled
	candidate: number?, -- the nearest lone target, if any (Stalker.pickTarget)
	targetLone: boolean, -- the current target is still living and lone
	touched: boolean, -- the current target is within touch range
}

local function distance(a: Point, b: Point): number
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end
Stalker.distance = distance

function Stalker.inFire(fire: Fire?, p: Point): boolean
	return fire ~= nil and fire.lit and distance(fire, p) < fire.radius
end

-- How many of `players` are within `radius` of `p`.
function Stalker.countNear(p: Point, players: { Point }, radius: number): number
	local n = 0
	for _, other in players do
		if distance(p, other) <= radius then
			n += 1
		end
	end
	return n
end

-- `others` are the other living players (not the target).
function Stalker.isLone(cfg: any, target: Point, others: { Point }, fire: Fire?): boolean
	return not Stalker.inFire(fire, target) and Stalker.countNear(target, others, cfg.stalker.loneRadius) == 0
end

-- `living` are all living players' positions.
function Stalker.repelled(cfg: any, at: Point, living: { Point }, fire: Fire?): boolean
	return Stalker.inFire(fire, at)
		or Stalker.countNear(at, living, cfg.stalker.repelGroupRadius) >= cfg.stalker.repelGroupSize
end

-- The index of the nearest lone player in `living` (all living players), or nil.
function Stalker.pickTarget(cfg: any, at: Point, living: { Point }, fire: Fire?): number?
	local best: number?, bestDistance = nil, math.huge
	for i, p in living do
		local others = table.clone(living)
		table.remove(others, i)
		local d = distance(at, p)
		if d < bestDistance and Stalker.isLone(cfg, p, others, fire) then
			best, bestDistance = i, d
		end
	end
	return best
end

-- Movement speed in studs/s. `targetSpeed` is the target's flat speed; a target standing still
-- counts as walking, so the Stalker still closes in.
function Stalker.speed(cfg: any, state: State, targetSpeed: number): number
	local base = math.max(targetSpeed, cfg.movement.walk)
	if state == "Stalk" then
		return base * cfg.stalker.stalkSpeedMult
	elseif state == "Lunge" then
		return base * cfg.stalker.lungeSpeedMult
	elseif state == "Dormant" then
		return 0
	end
	return cfg.stalker.prowlSpeed
end

-- One tick. Returns the next brain and an event: "prowl", "stalk", "lost", "lunge", "down",
-- "miss", "repelled", or nil when nothing changed.
function Stalker.step(cfg: any, b: Brain, s: Sense): (Brain, string?)
	local c = cfg.stalker
	local held = s.now - b.since
	if b.state == "Dormant" then
		if s.nightElapsed >= cfg.cycle.stalkerGraceSeconds then
			return { state = "Prowl", since = s.now }, "prowl"
		end
		return b, nil
	elseif b.state == "Retreat" then
		if held >= c.retreatSeconds then
			return { state = "Prowl", since = s.now }, "prowl"
		end
		return b, nil
	elseif s.repelled then
		return { state = "Retreat", since = s.now, target = b.target }, "repelled"
	elseif b.state == "Prowl" then
		if s.candidate ~= nil then
			return { state = "Stalk", since = s.now, target = s.candidate }, "stalk"
		end
		return b, nil
	elseif b.state == "Stalk" then
		if not s.targetLone then
			return { state = "Prowl", since = s.now }, "lost"
		elseif held >= c.stalkSeconds then
			return { state = "Lunge", since = s.now, target = b.target }, "lunge"
		end
		return b, nil
	end
	-- Lunge
	if s.touched then
		return { state = "Retreat", since = s.now, target = b.target }, "down"
	elseif held >= c.lungeSeconds then
		return { state = "Retreat", since = s.now, target = b.target }, "miss"
	end
	return b, nil
end

return Stalker
