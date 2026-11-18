--!strict
-- Which environment this server or client is running in (TECH_SPEC §2).
--
-- config/environments.json lists the game ids (universe ids, `game.GameId`) of each experience:
--   { "DEV": [id], "BETA": [id], "PROD": [id] }
-- An unknown id, such as an unpublished Studio file, runs as DEV with `known = false`, and
-- purchases stay off.

local Env = {}

export type Name = "DEV" | "BETA" | "PROD"
export type Info = { name: Name, known: boolean, studio: boolean }

-- Pure, so Lune can test it.
function Env.resolve(envConfig: any, gameId: number, isStudio: boolean): Info
	for _, name in { "PROD", "BETA", "DEV" } do
		local ids = envConfig[name]
		if type(ids) == "table" and table.find(ids, gameId) ~= nil then
			return { name = (name :: any) :: Name, known = true, studio = isStudio }
		end
	end
	return { name = "DEV", known = false, studio = isStudio }
end

local cached: Info? = nil

-- Roblox only: reads game.GameId and the Config folder next to this module.
function Env.get(): Info
	if cached == nil then
		local RunService = game:GetService("RunService")
		local envConfig = require(script.Parent.Config.environments) :: any
		cached = Env.resolve(envConfig, game.GameId, RunService:IsStudio())
	end
	return cached :: Info
end

return Env
