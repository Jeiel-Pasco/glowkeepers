--!strict
-- The local player's own state, as DataService replicates it: one snapshot (PlayerState with
-- full = true), then top-level patches. Also holds the Wallet, from which the HUD extrapolates
-- the ticking Glow counter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))

-- `since` is Glow earned since the last rebirth (it ticks with income, like `glow`).
export type Wallet = { glow: number, perSec: number, t: number, embers: number, since: number }

local StateController = {}
StateController.Loaded = Signal.new() -- (): the first snapshot arrived
StateController.Changed = Signal.new() -- (key: string, value: any)
StateController.WalletChanged = Signal.new() -- (wallet: Wallet)

local data: { [string]: any }? = nil
local wallet: Wallet = { glow = 0, perSec = 0, t = 0, embers = 0, since = 0 }

function StateController.get(): { [string]: any }?
	return data
end

function StateController.isLoaded(): boolean
	return data ~= nil
end

function StateController.wallet(): Wallet
	return wallet
end

-- Glow at server time `now`, extrapolated from the last Wallet.
function StateController.glowAt(now: number): number
	return wallet.glow + wallet.perSec * math.max(0, now - wallet.t)
end

-- Glow earned since the last rebirth at server time `now` (the rebirth progress bar).
function StateController.sinceRebirthAt(now: number): number
	return wallet.since + wallet.perSec * math.max(0, now - wallet.t)
end

function StateController.Init()
	NetClient.on("PlayerState", function(full: boolean, patch: { [string]: any })
		if full or data == nil then
			local first = data == nil
			data = patch
			if first then
				StateController.Loaded:Fire()
			end
		else
			local current = data :: { [string]: any }
			for key, value in patch do
				current[key] = value
			end
		end
		for key, value in patch do
			StateController.Changed:Fire(key, value)
		end
	end)

	NetClient.on("Wallet", function(glow: number, perSec: number, serverTime: number, embers: number, since: number?)
		wallet = { glow = glow, perSec = perSec, t = serverTime, embers = embers, since = since or 0 }
		StateController.WalletChanged:Fire(wallet)
	end)
end

return StateController
