--!strict
-- Auto-sprint + Boots Gear speed + Active Grimoire Passive speed & jump height + Status slow/root.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
local Element = require(Shared:WaitForChild("Element")) :: any
local Gears = require(Shared:WaitForChild("Gears")) :: any
local Status = require(Shared:WaitForChild("Status")) :: any

local MovementController = {}

function MovementController.Start()
	local player = Players.LocalPlayer
	local movement = economy.movement
	local movingFor = 0

	RunService.Heartbeat:Connect(function(dt: number)
		local character = player.Character
		if character == nil then
			movingFor = 0
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid == nil or humanoid.Health <= 0 then
			movingFor = 0
			return
		end

		if humanoid.MoveDirection.Magnitude > 0.1 then
			movingFor += dt
		else
			movingFor = 0
		end

		local target = movement.walk
		if movingFor >= movement.autoSprintAfter then
			local run = character:GetAttribute("RunSpeed")
			target = if type(run) == "number" then run else movement.run
		end

		-- Active Grimoire passive speed & jump + Boots Gear speed + temporary spell speed boost.
		local activeBook = character:GetAttribute("ActiveBook")
		local passive = if type(activeBook) == "string" then Element.PASSIVE[activeBook] else nil
		local bootsTier = character:GetAttribute("GearBoots")
		local boots = if type(bootsTier) == "number" then Gears.get("boots", bootsTier) else nil
		local now = workspace:GetServerTimeNow()
		local boostUntil = character:GetAttribute("SpeedBoostUntil")
		local boostMult = if type(boostUntil) == "number" and boostUntil > now
			then (character:GetAttribute("SpeedBoostMult") or 1.2)
			else 1

		local speedMult = 1
			+ (if passive and passive.speed then passive.speed else 0)
			+ (if boots and boots.speed then boots.speed else 0)
		target = target * speedMult * boostMult

		local attrs = {
			SlowUntil = character:GetAttribute("SlowUntil"),
			SlowFactor = character:GetAttribute("SlowFactor"),
			RootUntil = character:GetAttribute("RootUntil"),
		}
		target *= Status.speedFactor(attrs, now)
		if math.abs(humanoid.WalkSpeed - target) > 0.05 then
			humanoid.WalkSpeed = target
		end

		local baseJump = 7.2 * (1 + (if passive and passive.jump then passive.jump else 0))
		local rooted = Status.rooted(attrs, now)
		if rooted then
			if humanoid.JumpHeight > 0 then
				humanoid.JumpHeight = 0
			end
		elseif math.abs(humanoid.JumpHeight - baseJump) > 0.05 then
			humanoid.JumpHeight = baseJump
		end
	end)
end

return MovementController
