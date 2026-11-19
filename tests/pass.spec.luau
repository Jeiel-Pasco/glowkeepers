-- Night Pass (GAME_SYSTEMS §20).
local H = require("./harness")
local Pass = require("../src/shared/Pass")
local Decor = require("../src/shared/Decor")

local cfg = H.config()
local S1 = cfg.pass.s1Start
local WEEK = 7 * 86400

H.test("seasons: 8 weeks from s1Start, 0 before", function()
	H.eq(Pass.season(cfg, S1 - 1), 0)
	local season, start, finish = Pass.season(cfg, S1)
	H.eq(season, 1)
	H.eq(start, S1)
	H.eq(finish, S1 + 8 * WEEK)
	H.eq(Pass.season(cfg, S1 + 8 * WEEK), 2)
end)

H.test("catch-up: ×1.5 XP in the last 2 weeks", function()
	H.eq(Pass.xpFor(cfg, 100, S1), 100)
	H.eq(Pass.xpFor(cfg, 100, S1 + 6 * WEEK - 1), 100)
	H.eq(Pass.xpFor(cfg, 100, S1 + 6 * WEEK), 150)
	H.eq(Pass.xpFor(cfg, 25, S1 + 7 * WEEK), 37, "whole XP")
	H.eq(Pass.xpFor(cfg, 100, S1 - 1), 100, "no season: no bonus")
end)

H.test("tiers: 1,000 XP each, capped at 50", function()
	H.eq(Pass.tier(cfg, 999), 0)
	H.eq(Pass.tier(cfg, 1000), 1)
	H.eq(Pass.tier(cfg, 999999), 50)
end)

H.test("rewards: free every 2nd tier, premium every tier, ~1,500 premium Embers", function()
	H.eq(Pass.reward(cfg, "free", 1, 1), nil)
	H.eq((Pass.reward(cfg, "free", 2, 1) :: any).kind, "embers")
	H.eq((Pass.reward(cfg, "free", 6, 1) :: any).kind, "lure")
	H.eq((Pass.reward(cfg, "free", 20, 1) :: any).id, "pass_moth_banner")
	H.eq((Pass.reward(cfg, "prem", 5, 1) :: any).id, "s1_lantern_skin_5")
	H.eq((Pass.reward(cfg, "prem", 10, 2) :: any).id, "s2_base_banner_10")
	H.eq(Pass.reward(cfg, "prem", 51, 1), nil)
	H.near(Pass.premiumEmbersTotal(cfg), 1500, 100)
	for _, id in cfg.pass.free.decor do
		local item = Decor.item(cfg, id)
		H.ok(item ~= nil and item.exclusive, `{id} is an exclusive decoration`)
	end
end)

H.test("claim: locked, premium, claimed", function()
	local pass = Pass.fresh(1)
	pass.xp = 2500
	H.eq(select(2, Pass.canClaim(cfg, pass, "free", 4)), "locked")
	H.eq(select(2, Pass.canClaim(cfg, pass, "free", 1)), "no_reward")
	H.eq((Pass.canClaim(cfg, pass, "free", 2) :: any).kind, "embers")
	H.eq(select(2, Pass.canClaim(cfg, pass, "prem", 1)), "premium")
	pass.premium = true
	pass.free["2"] = true
	H.eq(select(2, Pass.canClaim(cfg, pass, "free", 2)), "claimed")
	local left = Pass.unclaimed(cfg, pass)
	H.eq(#left, 2, "prem 1 and prem 2")
	H.eq(left[1].track .. left[1].tier .. left[2].track .. left[2].tier, "prem1prem2")
end)

H.finish("pass")
