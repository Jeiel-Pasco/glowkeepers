--!strict
-- DEV/BETA exploit fuzzer (IMPLEMENTATION_PLAN §7, TECH_SPEC §8). Never runs in PROD.
-- Setting the workspace attribute DebugFuzz (any new value) makes every client fire bad
-- calls straight at the remotes, skipping NetClient. Each must be dropped and logged, and the
-- server should raise these flags (player attribute ExploitFlags):
--   Place   wrong types ×10      → invalid
--   Unplace someone else's id    → rejected
--   Release ids not owned        → rejected
--   PlaceBest ×400 in a burst    → flood
-- Also sent (dropped, not flagged on their own): Release(123), TradeOffer("x"), an unknown
-- product, an out-of-range pad, and, while carrying, three 60-stud teleports (the carry check
-- snaps the Glowling home and flags "Carry").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Env = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Env"))

local FAKE_ID = "00000000-0000-0000-0000-000000000000"

local FuzzController = {}

local function fire(name: string, ...: any)
	local remote: any = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild(name)
	if remote ~= nil then
		remote:FireServer(...)
	end
end

local function run()
	print("[Fuzz] start")
	for _ = 1, 10 do
		fire("Place", "x", "y")
	end
	fire("Release", 123)
	fire("TradeOffer", "x")
	fire("PromptProduct", "fake_product")
	task.wait(1.1)
	fire("Place", FAKE_ID, 9999)
	fire("Unplace", FAKE_ID)
	fire("Release", { FAKE_ID })
	for _ = 1, 400 do
		fire("PlaceBest")
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if character ~= nil and root ~= nil and character:GetAttribute("CarrySp") ~= nil then
		for _ = 1, 3 do
			root.CFrame += Vector3.new(60, 0, 0)
			task.wait(0.15)
		end
	end
	print("[Fuzz] done")
end

function FuzzController.Init() end

function FuzzController.Start()
	if Env.get().name == "PROD" then
		return
	end
	workspace:GetAttributeChangedSignal("DebugFuzz"):Connect(function()
		if workspace:GetAttribute("DebugFuzz") ~= nil then
			task.spawn(run)
		end
	end)
end

return FuzzController
