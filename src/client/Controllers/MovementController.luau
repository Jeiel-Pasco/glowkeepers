--!strict
-- Auto-sprint (GAME_SYSTEMS §9): walk at 16 studs/s, run after 0.5 s of moving.
--
-- The run speed comes from the character's `RunSpeed` attribute, which the server sets from
-- Boots, Swift Boots and carrying (Phase 2); until then it's config movement.run. Movement is
-- client-owned in Roblox, so the server checks carry speed itself (TECH_SPEC §8).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any

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
		if humanoid.WalkSpeed ~= target then
			humanoid.WalkSpeed = target
		end
	end)
end

return MovementController
