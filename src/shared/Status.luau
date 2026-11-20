--!strict
-- Player status effects from enemy attacks (docs/LAYER_ONE.md step 5). Pure rules, shared by
-- the server (CombatService sets them) and the client (MovementController obeys them).
--
-- Slow and root live on the character as attributes, in server time
-- (workspace:GetServerTimeNow()), so they replicate on their own and survive nothing past a
-- respawn: SlowUntil + SlowFactor (walk/run speed × factor), RootUntil (no moving, jumping,
-- dashing or blinking). Knockback and pull are a "push" Fx the owning client applies with a
-- LinearVelocity. Poison is a burn of the Leaf type (CombatService.poisonPlayer).

-- Vector3 is a Roblox global; under Lune (tests) it comes from @lune/roblox.
-- selene: allow(incorrect_standard_library_use, shadowing)
local Vector3 = if script ~= nil then Vector3 else (require("@lune/roblox") :: any).Vector3

local Status = {}

Status.MIN_SLOW = 0.3 -- the strongest slow; slows never stop you outright (that's root)

export type Attrs = { SlowUntil: number?, SlowFactor: number?, RootUntil: number? }

-- Speed multiplier at `now`: 0 while rooted, the slow factor while slowed, else 1.
function Status.speedFactor(attrs: Attrs, now: number): number
	if (attrs.RootUntil or 0) > now then
		return 0
	end
	if (attrs.SlowUntil or 0) > now then
		return math.clamp(attrs.SlowFactor or 1, Status.MIN_SLOW, 1)
	end
	return 1
end

function Status.rooted(attrs: Attrs, now: number): boolean
	return (attrs.RootUntil or 0) > now
end

-- A new slow on top of the current one: the stronger factor, the later end.
function Status.addSlow(attrs: Attrs, now: number, factor: number, duration: number): (number, number)
	factor = math.clamp(factor, Status.MIN_SLOW, 1)
	if (attrs.SlowUntil or 0) > now then
		return math.min(factor, attrs.SlowFactor or 1), math.max(attrs.SlowUntil or 0, now + duration)
	end
	return factor, now + duration
end

-- Knockback from `from` (flat, plus a little lift) or a pull toward it (negative speed).
function Status.pushVelocity(from: Vector3, target: Vector3, speed: number, lift: number): Vector3
	local d = target - from
	local flat = Vector3.new(d.X, 0, d.Z)
	local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(1, 0, 0)
	return dir * speed + Vector3.new(0, lift, 0)
end

-- Is `p` inside the line telegraph from `origin` along flat unit `dir`?
function Status.inLine(origin: Vector3, dir: Vector3, length: number, width: number, p: Vector3): boolean
	local d = Vector3.new(p.X - origin.X, 0, p.Z - origin.Z)
	local along = d:Dot(dir)
	if along < 0 or along > length then
		return false
	end
	local across = (d - dir * along).Magnitude
	return across <= width / 2
end

return Status
