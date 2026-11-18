-- Env: place id or game id → environment (TECH_SPEC §2).
local H = require("./harness")
local Env = require("../src/shared/Env")

local config = { DEV = { 111 }, BETA = { 222 }, PROD = { 333 } }

H.test("a listed place id or game id maps to its environment", function()
	local prod = Env.resolve(config, 9, 333, false)
	H.eq(prod.name, "PROD", "PROD by place id")
	H.ok(prod.known, "known")
	H.eq(Env.resolve(config, 333, 9, false).name, "PROD", "PROD by game id")
	local beta = Env.resolve(config, 9, 222, true)
	H.eq(beta.name, "BETA", "BETA")
	H.ok(beta.studio, "studio flag passes through")
	H.eq(Env.resolve(config, 9, 111, false).name, "DEV", "DEV")
end)

H.test("unknown ids (an unpublished Studio file is 0) run as DEV, not known", function()
	local unknown = Env.resolve(config, 0, 0, true)
	H.eq(unknown.name, "DEV", "DEV")
	H.ok(not unknown.known, "not known, so purchases stay off")
	H.eq(Env.resolve({}, 333, 333, false).name, "DEV", "empty config")
end)

H.test("the committed environments.json resolves all three experiences", function()
	local real = H.json("config/environments.json")
	for _, name in { "DEV", "BETA", "PROD" } do
		local id = real[name][1]
		H.ok(id ~= nil, `{name} has an id`)
		local info = Env.resolve(real, 0, id, false)
		H.eq(info.name, name, `{name} id {id}`)
		H.ok(info.known, `{name} is known`)
	end
end)

H.finish("env")
