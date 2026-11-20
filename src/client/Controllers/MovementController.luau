--!strict
-- Auto-sprint (GAME_SYSTEMS §9): walk at 16 studs/s, run after 0.5 s of moving.
--
-- The run speed comes from the character's `RunSpeed` attribute, which the server sets from
-- Boots, Swift Boots and carrying (Phase 2); until then it's config movement.run. Movement is
-- client-owned in Roblox, so the server checks carry speed itself (TECH_SPEC §8).
-- Slow and root (Shared.Status character attributes) scale the speed and, while rooted, stop
-- jumping too.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any
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
		local attrs = {
			SlowUntil = character:GetAttribute("SlowUntil"),
			SlowFactor = character:GetAttribute("SlowFactor"),
			RootUntil = character:GetAttribute("RootUntil"),
		}
		local now = workspace:GetServerTimeNow()
		target *= Status.speedFactor(attrs, now)
		if humanoid.WalkSpeed ~= target then
			humanoid.WalkSpeed = target
		end
		local rooted = Status.rooted(attrs, now)
		if rooted and humanoid.JumpHeight > 0 then
			character:SetAttribute("FreeJumpHeight", humanoid.JumpHeight)
			humanoid.JumpHeight = 0
		elseif not rooted and humanoid.JumpHeight == 0 then
			local free = character:GetAttribute("FreeJumpHeight")
			humanoid.JumpHeight = if type(free) == "number" then free else 7.2
		end
	end)
end

return MovementController
