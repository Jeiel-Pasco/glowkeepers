-- Env: game id → environment (TECH_SPEC §2).
local H = require("./harness")
local Env = require("../src/shared/Env")

local config = { DEV = { 111 }, BETA = { 222 }, PROD = { 333 } }

H.test("known ids map to their environment", function()
	local prod = Env.resolve(config, 333, false)
	H.eq(prod.name, "PROD", "PROD")
	H.ok(prod.known, "known")
	local beta = Env.resolve(config, 222, true)
	H.eq(beta.name, "BETA", "BETA")
	H.ok(beta.studio, "studio flag passes through")
	H.eq(Env.resolve(config, 111, false).name, "DEV", "DEV")
end)

H.test("unknown ids (an unpublished Studio file is 0) run as DEV, not known", function()
	local unknown = Env.resolve(config, 0, true)
	H.eq(unknown.name, "DEV", "DEV")
	H.ok(not unknown.known, "not known, so purchases stay off")
	H.eq(Env.resolve({}, 333, false).name, "DEV", "empty config")
end)

H.finish("env")
