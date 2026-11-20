--!strict
-- Combat rules shared by CombatService (server) and CombatController (its client mirror): what a
-- player's Gears and Grimoire passive add in a fight, the 4-hit M1 combo and its finishers,
-- Permafrost chill stacks, who may hit whom in PvP, and the PvP bounty. Pure, so the Lune tests
-- can check it.

-- In Roblox sibling ModuleScripts; under Lune (tests) paths.
-- selene: allow(incorrect_standard_library_use)
local Element = if script ~= nil then require(script.Parent:WaitForChild("Element")) :: any else require("./Element")
-- selene: allow(incorrect_standard_library_use)
local Gears = if script ~= nil then require(script.Parent:WaitForChild("Gears")) :: any else require("./Gears")

local CombatRules = {}

CombatRules.MAX_CDR = 0.4 -- cooldown reduction cap (Hat + passive)
CombatRules.MAX_DEFENSE = 0.5 -- damage-taken reduction cap (Robe + passive)
CombatRules.MIN_DASH_COOLDOWN = 1.4
CombatRules.PVP_DAMAGE = 0.5 -- player-vs-player damage scale, so ultimates don't one-shot

CombatRules.COMBO_HITS = 4
CombatRules.COMBO_WINDOW = 1.2 -- seconds between M1 clicks before the combo resets
CombatRules.FINISHER_DAMAGE = 1.5 -- the 4th M1 hit's damage multiplier
CombatRules.FINISHER_RADIUS = 1.5 -- and its projectile size

CombatRules.CHILL_STACKS = 3 -- Permafrost: Frost hits to Freeze
CombatRules.CHILL_DECAY = 4 -- seconds without a Frost hit before the stacks melt
CombatRules.FREEZE_SECONDS = 1.2

CombatRules.KILL_CREDIT_SECONDS = 10 -- a death this soon after a PvP hit credits that attacker
CombatRules.BOUNTY_BASE = 20 -- coins for any War Mode kill
CombatRules.BOUNTY_PER_POINT = 30 -- plus this per point of the victim's bounty

export type Effect = {
	burn: { dps: number, duration: number, type: string? }?,
	slow: { amount: number, duration: number }?,
	push: { speed: number, lift: number, duration: number }?,
	chill: number?, -- extra Permafrost stacks
	bonus: number?, -- extra damage fraction
}

-- The 4th M1 hit's effect, by Element.PASSIVE[type].m1Effect.
CombatRules.FINISHERS = {
	knockback = { push = { speed = 34, lift = 10, duration = 0.25 } },
	burn = { burn = { dps = 3, duration = 2 } },
	slow = { slow = { amount = 0.25, duration = 2 } },
	poison = { burn = { dps = 3, duration = 3, type = "Leaf" } },
	chill = { chill = 1 },
	shock = { bonus = 0.6 },
	pull = { push = { speed = -30, lift = 4, duration = 0.25 } },
} :: { [string]: Effect }

local function passive(bookType: string): any
	return Element.PASSIVE[bookType] or {}
end

-- Bonus damage fraction and cooldown reduction from the Wizard Hat and the Grimoire in hand.
function CombatRules.offense(gears: any, bookType: string): (number, number)
	local g = Gears.stats(gears)
	local p = passive(bookType)
	local cdr = math.clamp(g.cdr + (p.cdr or 0), 0, CombatRules.MAX_CDR)
	return g.power + (p.power or 0), cdr
end

-- Damage-taken reduction from the Robe and the Grimoire in hand (Earth: Titan's Poise).
function CombatRules.defense(gears: any, bookType: string): number
	return math.clamp(Gears.stats(gears).defense + (passive(bookType).defense or 0), 0, CombatRules.MAX_DEFENSE)
end

-- Out-of-combat regen multiplier (Leaf: Natural Grace).
function CombatRules.regenMult(bookType: string): number
	return 1 + (passive(bookType).regen or 0)
end

-- Q dash cooldown after the Boots' dash bonus.
function CombatRules.dashCooldown(base: number, gears: any): number
	return math.max(CombatRules.MIN_DASH_COOLDOWN, base - Gears.stats(gears).dashBonus)
end

-- The next combo count (1..COMBO_HITS) for an M1 click at `now`.
function CombatRules.comboStep(count: number, lastT: number, now: number): number
	if count >= CombatRules.COMBO_HITS or now - lastT > CombatRules.COMBO_WINDOW then
		return 1
	end
	return count + 1
end

-- The 4th-hit effect for a Grimoire type, or nil.
function CombatRules.finisher(bookType: string): Effect?
	local effect = passive(bookType).m1Effect
	return if effect then CombatRules.FINISHERS[effect] else nil
end

-- Adds `n` Permafrost stacks at `now`. Returns the stacks left and whether the target Freezes
-- (which spends the stacks).
function CombatRules.addChill(stacks: number, lastT: number, now: number, n: number): (number, boolean)
	if now - lastT > CombatRules.CHILL_DECAY then
		stacks = 0
	end
	stacks += n
	if stacks >= CombatRules.CHILL_STACKS then
		return 0, true
	end
	return stacks, false
end

export type Side = { safe: boolean, arena: boolean, war: boolean }

-- May one player damage another? Never in the camp courtyard. Both inside the Duel Arena Ring,
-- or both with War Mode on.
function CombatRules.canPvp(a: Side, b: Side): boolean
	if a.safe or b.safe then
		return false
	end
	return (a.arena and b.arena) or (a.war and b.war)
end

-- Coins a War Mode kill pays the killer.
function CombatRules.bountyReward(victimBounty: number): number
	return CombatRules.BOUNTY_BASE + CombatRules.BOUNTY_PER_POINT * math.max(0, victimBounty)
end

return CombatRules
