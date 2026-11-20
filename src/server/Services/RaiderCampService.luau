--!strict
-- Raider camps (docs/LAYER_ONE.md step 4; rules in Shared.RaiderCamps).
--
-- On start it picks this server's camps (one per gap between zones), builds each at runtime
-- (palisade with an entrance facing the campfire, tents, a fire, crates and a chest) and spawns
-- its guards through EnemyService. The chest is locked while any guard lives. When the last
-- guard falls the camp is cleared: each player may open the chest once for that clear (coins,
-- or a low chance of ink, into the carried bag). RaiderCamps.RESPAWN seconds later the guards
-- come back and the chest locks again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RaiderCamps = require(Shared:WaitForChild("RaiderCamps")) :: any
local Zones = require(Shared:WaitForChild("Zones")) :: any
local NetServer = require(script.Parent.Parent:WaitForChild("Net"):WaitForChild("NetServer"))
local EnemyService = require(script.Parent:WaitForChild("EnemyService"))
local LootService = require(script.Parent:WaitForChild("LootService"))

local RaiderCampService = {}

local M = Enum.Material
local WOOD = Color3.fromRGB(104, 80, 58)
local WOOD_DARK = Color3.fromRGB(78, 60, 46)
local CLOTH = { Color3.fromRGB(128, 112, 88), Color3.fromRGB(112, 96, 80), Color3.fromRGB(96, 104, 86) }

type Camp = {
	id: number,
	centre: Vector3,
	entrance: Vector3, -- unit, flat: from the centre toward the campfire
	level: number,
	guards: { Model },
	clear: number, -- how many times it has been cleared; 0 while guarded the first time
	cleared: boolean,
	opened: { [Player]: number }, -- the clear each player last opened the chest in
	prompt: ProximityPrompt,
	lid: BasePart,
}

local camps: { Camp } = {}

local function groundAt(x: number, z: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local top = Zones.groundY(math.sqrt(x * x + z * z)) + 80
	local ray = workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -200, 0), params)
	return if ray then ray.Position else Vector3.new(x, Zones.groundY(math.sqrt(x * x + z * z)), z)
end

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.Wood
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- An A-frame tent: two sloped cloth panels and a ridge pole.
local function tent(parent: Instance, at: Vector3, facing: Vector3, color: Color3)
	local base = CFrame.lookAt(at, at + facing)
	for _, side in { -1, 1 } do
		part(
			parent,
			Vector3.new(0.3, 6.4, 8),
			base * CFrame.new(side * 2.1, 2.2, 0) * CFrame.Angles(0, 0, side * 0.62),
			color,
			M.Fabric
		)
	end
	part(parent, Vector3.new(0.4, 0.4, 8.6), base * CFrame.new(0, 4.9, 0), WOOD_DARK)
end

local function build(camp: Camp, rng: Random): Model
	local model = Instance.new("Model")
	model.Name = `RaiderCamp{camp.id}`
	local c = camp.centre
	local entrance = camp.entrance
	-- Palisade: leaning stakes round the wall, with a gap toward the campfire.
	local stakes = math.floor(2 * math.pi * RaiderCamps.WALL_R / 2.6)
	local entranceAngle = math.atan2(entrance.Z, entrance.X)
	for i = 1, stakes do
		local a = i / stakes * 2 * math.pi
		local gap = math.abs((a - entranceAngle + math.pi) % (2 * math.pi) - math.pi)
		if gap > math.rad(14) then
			local x, z = c.X + math.cos(a) * RaiderCamps.WALL_R, c.Z + math.sin(a) * RaiderCamps.WALL_R
			local g = groundAt(x, z)
			local h = rng:NextNumber(6, 8.5)
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			part(
				model,
				Vector3.new(1.4, h, 1.4),
				CFrame.lookAt(g, g + out)
					* CFrame.new(0, h / 2 - 1, 0)
					* CFrame.Angles(-0.12, 0, rng:NextNumber(-0.06, 0.06)),
				WOOD:Lerp(WOOD_DARK, rng:NextNumber())
			)
		end
	end
	-- Gate posts with a skull-less banner rag.
	for _, side in { -1, 1 } do
		local a = entranceAngle + side * math.rad(16)
		local g = groundAt(c.X + math.cos(a) * RaiderCamps.WALL_R, c.Z + math.sin(a) * RaiderCamps.WALL_R)
		part(model, Vector3.new(1.8, 11, 1.8), CFrame.new(g + Vector3.new(0, 4.5, 0)), WOOD_DARK)
		part(
			model,
			Vector3.new(0.2, 3, 1.6),
			CFrame.new(g + Vector3.new(0, 8, 0)) * CFrame.Angles(0, a, 0),
			Color3.fromRGB(120, 54, 44),
			M.Fabric
		)
	end
	-- Tents at the back.
	local back = -entrance
	local side = Vector3.new(-back.Z, 0, back.X)
	for k, offset in { -9, 0, 9 } do
		local p = c + back * 13 + side * offset
		tent(model, groundAt(p.X, p.Z), entrance, CLOTH[k])
	end
	-- The fire.
	local fire = groundAt(c.X, c.Z) + side * 4
	for k = 0, 3 do
		local a = k / 4 * math.pi
		part(
			model,
			Vector3.new(0.7, 0.7, 3.6),
			CFrame.new(fire + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, a, 0),
			WOOD_DARK
		)
	end
	local ember = part(
		model,
		Vector3.new(1.4, 0.6, 1.4),
		CFrame.new(fire + Vector3.new(0, 0.6, 0)),
		Color3.fromRGB(230, 120, 60),
		M.Neon
	)
	ember.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 90)
	light.Range = 22
	light.Brightness = 1.2
	light.Parent = ember
	local flame = Instance.new("Fire")
	flame.Size = 4
	flame.Heat = 6
	flame.Parent = ember
	-- Crates by the tents.
	for _, offset in { -14, 14 } do
		local p = c + back * 4 + side * offset
		local g = groundAt(p.X, p.Z)
		part(
			model,
			Vector3.new(3, 3, 3),
			CFrame.new(g + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
			WOOD
		)
	end
	-- The chest, behind the fire.
	local chestPos = groundAt(c.X, c.Z) + back * 5 - side * 3
	local chestCF = CFrame.lookAt(chestPos, chestPos + entrance)
	local box = part(model, Vector3.new(4.5, 2.4, 3), chestCF * CFrame.new(0, 1.1, 0), WOOD)
	box.Name = "Chest"
	camp.lid = part(model, Vector3.new(4.7, 0.9, 3.2), chestCF * CFrame.new(0, 2.75, 0), WOOD_DARK)
	for _, x in { -1.4, 1.4 } do
		part(model, Vector3.new(0.4, 2.6, 3.2), chestCF * CFrame.new(x, 1.2, 0), Color3.fromRGB(70, 70, 72), M.Metal)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Raider chest"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = box
	camp.prompt = prompt
	model:SetAttribute("CampId", camp.id)
	return model
end

local function setLocked(camp: Camp, locked: boolean)
	camp.cleared = not locked
	camp.prompt.ActionText = if locked then "Locked: defeat the guards" else "Open"
	camp.lid.Color = if locked then WOOD_DARK else Color3.fromRGB(120, 92, 64)
end

local function spawnGuards(camp: Camp)
	table.clear(camp.guards)
	for _, guard in RaiderCamps.GUARDS do
		local pos = RaiderCamps.guardPos(camp.centre, camp.entrance, guard)
		table.insert(camp.guards, EnemyService.spawnGuard(guard.kind, camp.level, pos, camp.centre, camp.id))
	end
	setLocked(camp, true)
end

local function guardsAlive(camp: Camp): number
	local n = 0
	for _, model in camp.guards do
		local humanoid = model.Parent and model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			n += 1
		end
	end
	return n
end

local function open(camp: Camp, player: Player)
	if not camp.cleared then
		NetServer.send(player, "Toast", "The raiders still guard this chest", "warn")
		return
	end
	if camp.opened[player] == camp.clear then
		NetServer.send(player, "Toast", "You already emptied this chest. The raiders will be back", "warn")
		return
	end
	camp.opened[player] = camp.clear
	LootService.give(player, RaiderCamps.chestBag(camp.level, math.random(), math.random()))
end

function RaiderCampService.Init()
	Players.PlayerRemoving:Connect(function(player)
		for _, camp in camps do
			camp.opened[player] = nil
		end
	end)
end

function RaiderCampService.Start()
	local rng = Random.new()
	local folder = Instance.new("Folder")
	folder.Name = "RaiderCamps"
	folder.Parent = workspace
	for id, index in
		RaiderCamps.pick(function(n)
			return rng:NextInteger(1, n)
		end)
	do
		local site = Zones.CAMP_SITES[index]
		local centre = Zones.polar(site.angle, site.r)
		local camp: Camp = {
			id = id,
			centre = groundAt(centre.X, centre.Z),
			entrance = -Vector3.new(centre.X, 0, centre.Z).Unit,
			level = RaiderCamps.level(site),
			guards = {},
			clear = 0,
			cleared = false,
			opened = {},
			prompt = nil :: any,
			lid = nil :: any,
		}
		build(camp, rng).Parent = folder
		camp.prompt.Triggered:Connect(function(player)
			open(camp, player)
		end)
		spawnGuards(camp)
		table.insert(camps, camp)
	end
	while true do
		task.wait(1)
		for _, camp in camps do
			if not camp.cleared and guardsAlive(camp) == 0 then
				camp.clear += 1
				setLocked(camp, false)
				local clear = camp.clear
				task.delay(RaiderCamps.RESPAWN, function()
					if camp.clear == clear then
						spawnGuards(camp)
					end
				end)
			end
		end
	end
end

return RaiderCampService
