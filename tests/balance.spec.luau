-- Balance: the numbers behind "fair at every level" (Shared.Enemies header).
-- The model player clicks their basic attack and casts one Common bolt on cooldown, with no
-- stat points spent. Enemies grow 10% per level, the same as the player's level power, so
-- on-level fights should take the same time at level 2 and level 12.
local H = require("./harness")
local Spells = require("../src/shared/Spells")
local Level = require("../src/shared/Level")
local Enemies = require("../src/shared/Enemies")
local Zones = require("../src/shared/Zones")

local function kitDps(level: number, kind: string): number
	local basic = Spells.BASIC[kind]
	local bolt =
		Spells.byId[({ Neutral = "arcane_bolt", Fire = "ember_shot", Water = "tide_bolt", Leaf = "thorn_dart" })[kind]]
	return (basic.damage / basic.cooldown + bolt.damage / bolt.cooldown) * Level.power(level)
end

local function clickDps(level: number): number
	local basic = Spells.BASIC.Neutral
	return basic.damage / basic.cooldown * Level.power(level)
end

local function enemyDps(kind: any, level: number): number
	return Enemies.damage(kind, level) / kind.cooldown
end

for _, level in { 2, 7, 12 } do
	H.test(`on-level minions and casters at level {level}`, function()
		for id, kind in Enemies.kinds do
			if kind.role == "minion" then
				local ttk = Enemies.maxHp(kind, level) / kitDps(level, "Fire")
				H.ok(ttk >= 1.5 and ttk <= 3, `{id} kit kill {ttk}s`)
				local clicks = Enemies.maxHp(kind, level) / clickDps(level)
				H.ok(clicks >= 3 and clicks <= 6, `{id} click-only kill {clicks}s`)
				local survive = Level.maxHealth(level, 0) / enemyDps(kind, level)
				H.ok(survive >= 15 and survive <= 30, `{id} kills an idle player in {survive}s`)
			elseif kind.role == "caster" then
				local ttk = Enemies.maxHp(kind, level) / kitDps(level, "Fire")
				H.ok(ttk >= 1 and ttk <= 2.5, `{id} kit kill {ttk}s`)
			end
		end
	end)
end

H.test("a solo on-level boss fight lasts about a minute", function()
	for id, kind in Enemies.kinds do
		if kind.role == "boss" then
			local ttk = Enemies.maxHp(kind, 12) / kitDps(12, kind.type == "Fire" and "Water" or "Fire")
			H.ok(ttk >= 45 and ttk <= 90, `{id} solo {ttk}s`)
		end
	end
end)

H.test("the tutorial Ashling takes 10–25 s with the first spell", function()
	local ashling = Enemies.kinds.ashling
	local ttk = Enemies.maxHp(ashling, 3) / kitDps(3, "Neutral")
	H.ok(ttk >= 10 and ttk <= 25, `ashling {ttk}s`)
end)

H.test("levelling 1 → 15 on on-level minions takes 45–150 minutes", function()
	local seconds = 0
	local kind = Enemies.kinds.ember_imp
	for level = 1, Level.CAP - 1 do
		local kills = Level.xpToNext(level) / Enemies.xp(kind, level)
		local perKill = Enemies.maxHp(kind, level) / kitDps(level, "Fire") + 6 -- 6 s to find the next one
		seconds += kills * perKill
	end
	local minutes = seconds / 60
	H.ok(minutes >= 45 and minutes <= 150, `{minutes} minutes`)
end)

H.test("every zone pack has a real enemy kind; zones sit apart and inside the world", function()
	local count = 0
	for _, spawn in Zones.spawns() do
		H.ok(Enemies.kinds[spawn.kind], `kind {spawn.kind}`)
		H.ok(spawn.pos.Magnitude < Zones.WORLD_R - 40, `{spawn.kind} inside the world`)
		count += 1
	end
	H.ok(count <= 50, `{count} enemies in the world`)
	-- Packs at least 12 studs apart, so one pull is one pack.
	for _, zone in Zones.list do
		for i, a in Zones.PACKS do
			for j, b in Zones.PACKS do
				if i < j then
					local d = (Zones.toWorld(zone, a.d, a.s) - Zones.toWorld(zone, b.d, b.s)).Magnitude
					H.ok(d >= 12, `{zone.id} packs {i},{j} {d}`)
				end
			end
		end
	end
end)

H.finish("balance")
