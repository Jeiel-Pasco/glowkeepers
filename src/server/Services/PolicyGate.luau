--!strict
-- PolicyService answers, cached per player (GAME_SYSTEMS §23, TECH_SPEC §4):
--   paidRandomRestricted: ArePaidRandomItemsRestricted (Server Luck is hidden and refused)
--   canTrade: IsPaidItemTradingAllowed (trading is turned off for players who may not trade)
-- A failed lookup is treated as restricted (the safe answer). Mirrored to player attributes
-- `PaidRandomRestricted` and `TradingAllowed` for the client.

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")

type Info = { paidRandomRestricted: boolean, canTrade: boolean }

local PolicyGate = {}

local cache: { [Player]: Info } = {}

local function fetch(player: Player)
	local info: Info = { paidRandomRestricted = true, canTrade = false }
	local ok, result = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if ok and type(result) == "table" then
		info.paidRandomRestricted = result.ArePaidRandomItemsRestricted == true
		info.canTrade = result.IsPaidItemTradingAllowed ~= false
	else
		warn(`[PolicyGate] policy lookup failed for {player.UserId}: {result}`)
	end
	cache[player] = info
	player:SetAttribute("PaidRandomRestricted", info.paidRandomRestricted)
	player:SetAttribute("TradingAllowed", info.canTrade)
end

function PolicyGate.paidRandomRestricted(player: Player): boolean
	local info = cache[player]
	return info == nil or info.paidRandomRestricted
end

function PolicyGate.canTrade(player: Player): boolean
	local info = cache[player]
	return info ~= nil and info.canTrade
end

function PolicyGate.Init()
	Players.PlayerAdded:Connect(fetch)
	for _, player in Players:GetPlayers() do
		task.spawn(fetch, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		cache[player] = nil
	end)
end

function PolicyGate.Start() end

return PolicyGate
