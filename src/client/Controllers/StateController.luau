--!strict
-- The local player's own state, as DataService replicates it: one snapshot (PlayerState with
-- full = true), then top-level patches.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local NetClient = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetClient"))

local StateController = {}
StateController.Loaded = Signal.new() -- (): the first snapshot arrived
StateController.Changed = Signal.new() -- (key: string, value: any)

local data: { [string]: any }? = nil

function StateController.get(): { [string]: any }?
	return data
end

function StateController.isLoaded(): boolean
	return data ~= nil
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
end

return StateController
