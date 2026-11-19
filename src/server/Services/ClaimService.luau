--!strict
-- Owns the Claim remote (TECH_SPEC §7): Claim(kind, id). Each kind is handled by the service
-- that owns it, which registers itself in its Init: GlowdexService ("dex_page",
-- "dex_milestone") and DailyGiftService ("gift"). Quests and pass tiers join later.

local Server = script.Parent.Parent
local NetServer = require(Server:WaitForChild("Net"):WaitForChild("NetServer"))

type Handler = (player: Player, id: string) -> ()

local ClaimService = {}

local handlers: { [string]: Handler } = {}

function ClaimService.register(kind: string, handler: Handler)
	assert(handlers[kind] == nil, `Claim kind {kind} already has a handler`)
	handlers[kind] = handler
end

function ClaimService.Init()
	NetServer.on("Claim", function(player: Player, kind: string, id: string)
		local handler = handlers[kind]
		if handler ~= nil then
			handler(player, id)
		end
	end)
end

function ClaimService.Start() end

return ClaimService
