--!strict
-- Client side of the remote registry: send intents, listen for server pushes.
-- The server checks every argument again; nothing here is trusted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")) :: any
local folder = ReplicatedStorage:WaitForChild("Remotes")

local NetClient = {}

local function remote(name: string, dir: string): any
	local def = Net.remotes[name]
	assert(def ~= nil, `unknown remote {name}`)
	assert(def.dir == dir, `{name} can't be used in this direction`)
	return folder:WaitForChild(name)
end

function NetClient.send(name: string, ...: any)
	remote(name, "c2s"):FireServer(...)
end

function NetClient.on(name: string, fn: (...any) -> ()): RBXScriptConnection
	return remote(name, "s2c").OnClientEvent:Connect(fn)
end

return NetClient
