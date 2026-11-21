--!strict
-- The shared Wizard Camp Courtyard (r < Zones.CAMP_R): everyone spawns round the central
-- campfire, shares the Scriptorium Desk (write spells, pick an element), Grimoire Shelf (equip
-- books & stats), Bank Vault chest, and Ink Merchant stall. Stepping anywhere inside the
-- courtyard banks carried loot; enemies never follow you in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Zones = require(Shared:WaitForChild("Zones")) :: any
local DataService = require(script.Parent:WaitForChild("DataService"))

local CampService = {}
CampService.Assigned = Signal.new() -- (player, slotId)

CampService.SAFE_RADIUS = Zones.CAMP_R -- the Wizard Camp Courtyard: no enemies, no combat

local slotOf: { [Player]: number } = {}
local nextSlot = 0

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Wood
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function prompt(parent: BasePart, action: string, text: string, object: string)
	local existing = parent:FindFirstChildOfClass("ProximityPrompt")
	if existing then
		existing:Destroy()
	end
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = text
	pp.ObjectText = object
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp:SetAttribute("Action", action)
	pp.Parent = parent
end

local WOOD = Color3.fromRGB(120, 84, 56)
local WOOD_DARK = Color3.fromRGB(86, 60, 42)
local STONE = Color3.fromRGB(118, 114, 112)
local CLOTH_EMBER = Color3.fromRGB(168, 102, 70)

-- Builds (or refreshes) the shared stations in workspace.Map.Sanctuary so the hub always works
-- even before running tools/BuildZones.luau.
local function buildSanctuary()
	local map = workspace:FindFirstChild("Map")
	if map == nil then
		local f = Instance.new("Folder")
		f.Name = "Map"
		f.Parent = workspace
		map = f
	end
	assert(map ~= nil, "Map folder missing")
	-- Remove any legacy v1 plot/station folders if still present in an old place save.
	for _, oldName in { "Plots", "Stations" } do
		local old = map:FindFirstChild(oldName)
		if old then
			old:Destroy()
		end
	end
	local oldSanctuary = map:FindFirstChild("Sanctuary")
	if oldSanctuary then
		oldSanctuary:Destroy()
	end

	local folder = Instance.new("Model")
	folder.Name = "Sanctuary"

	-- Desk: chunky writing table, open grimoire pages and a lit candle.
	local deskBase = CFrame.lookAt(Zones.DESK_POS, Vector3.new(0, Zones.FLOOR_Y, 0))
	local top = part(folder, "Desk", Vector3.new(8, 0.8, 4.4), deskBase * CFrame.new(0, 3.2, 0), WOOD)
	for _, x in { -3.4, 3.4 } do
		for _, z in { -1.6, 1.6 } do
			part(folder, "Leg", Vector3.new(0.8, 2.8, 0.8), deskBase * CFrame.new(x, 1.4, z), WOOD_DARK)
		end
	end
	local pageColor = Color3.fromRGB(240, 228, 200)
	part(
		folder,
		"Page",
		Vector3.new(1.8, 0.2, 2.4),
		deskBase * CFrame.new(-0.95, 3.7, 0) * CFrame.Angles(0, 0, 0.12),
		pageColor,
		Enum.Material.SmoothPlastic
	)
	part(
		folder,
		"Page",
		Vector3.new(1.8, 0.2, 2.4),
		deskBase * CFrame.new(0.95, 3.7, 0) * CFrame.Angles(0, 0, -0.12),
		pageColor,
		Enum.Material.SmoothPlastic
	)
	local candle = part(
		folder,
		"Candle",
		Vector3.new(0.5, 1.1, 0.5),
		deskBase * CFrame.new(3, 4.15, -1.1),
		Color3.fromRGB(236, 224, 190),
		Enum.Material.SmoothPlastic
	)
	local flame = part(
		folder,
		"Flame",
		Vector3.new(0.3, 0.5, 0.3),
		candle.CFrame * CFrame.new(0, 0.8, 0),
		Color3.fromRGB(255, 190, 90),
		Enum.Material.Neon
	)
	flame.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 120)
	light.Range = 16
	light.Brightness = 1.2
	light.Parent = flame
	prompt(top, "desk", "Write spells", "Scriptorium Desk")

	-- Shelf: three planks of grimoires next to the desk.
	local shelfBase = CFrame.lookAt(Zones.SHELF_POS, Vector3.new(0, Zones.FLOOR_Y, 0))
	local back = part(folder, "Shelf", Vector3.new(7, 7.5, 0.7), shelfBase * CFrame.new(0, 3.75, -1.2), WOOD_DARK)
	for i = 0, 2 do
		part(folder, "Plank", Vector3.new(7, 0.4, 2.2), shelfBase * CFrame.new(0, 1 + i * 2.3, -0.2), WOOD)
		for b = 0, 4 do
			local hue = (b * 0.17 + i * 0.31) % 1
			part(
				folder,
				"Book",
				Vector3.new(0.7, 1.5, 1.6),
				shelfBase
					* CFrame.new(-2.2 + b * 1.1, 1.95 + i * 2.3, -0.2)
					* CFrame.Angles(0, 0, if b == 3 then 0.25 else 0),
				Color3.fromHSV(hue, 0.35, 0.6),
				Enum.Material.SmoothPlastic
			)
		end
	end
	prompt(back, "shelf", "Grimoires & stats", "Grimoire Shelf")

	-- Bank Vault chest: stepping into the courtyard banks automatically; the chest inspects it.
	local bankBase = CFrame.lookAt(Zones.BANK_POS, Vector3.new(0, Zones.FLOOR_Y, 0))
	part(folder, "Dais", Vector3.new(7, 0.6, 5), bankBase * CFrame.new(0, 0.3, 0), STONE, Enum.Material.Slate)
	local box = part(folder, "Bank", Vector3.new(5, 2.6, 3.2), bankBase * CFrame.new(0, 1.9, 0), WOOD)
	part(folder, "Lid", Vector3.new(5.2, 0.9, 3.4), bankBase * CFrame.new(0, 3.65, 0), WOOD_DARK)
	for _, x in { -1.6, 1.6 } do
		part(
			folder,
			"Band",
			Vector3.new(0.5, 3.6, 3.5),
			bankBase * CFrame.new(x, 2.35, 0),
			Color3.fromRGB(196, 160, 80),
			Enum.Material.Metal
		)
	end
	prompt(box, "bank", "View bank", "Camp Bank")

	-- Ink Merchant stall: counter, posts and ember awning.
	local shopBase = CFrame.lookAt(Zones.SHOP_POS, Vector3.new(0, Zones.FLOOR_Y, 0))
	local counter = part(folder, "InkMerchant", Vector3.new(9, 3.2, 2.4), shopBase * CFrame.new(0, 1.6, 1.8), WOOD)
	part(folder, "CounterTop", Vector3.new(9.4, 0.35, 2.8), shopBase * CFrame.new(0, 3.35, 1.8), WOOD_DARK)
	for _, x in { -4.2, 4.2 } do
		for _, z in { -2.2, 2.2 } do
			part(folder, "Post", Vector3.new(0.6, 8.5, 0.6), shopBase * CFrame.new(x, 4.25, z), WOOD_DARK)
		end
	end
	part(
		folder,
		"Awning",
		Vector3.new(10, 1.2, 6),
		shopBase * CFrame.new(0, 8.8, 0) * CFrame.Angles(0.12, 0, 0),
		CLOTH_EMBER,
		Enum.Material.Fabric
	)
	prompt(counter, "shop", "Buy Gears & Ink", "Wizard Gear Shop")

	-- Duel Arena Ring right outside the South Camp Courtyard (r = 114, radius 24): stepping inside
	-- enables instant 1v1 / free-for-all dueling right in view of the Camp Hub!
	local arenaCenter = Vector3.new(Zones.ARENA_X, Zones.FLOOR_Y, Zones.ARENA_Z)
	local arenaR = Zones.ARENA_R
	local terrainParams = RaycastParams.new()
	terrainParams.FilterType = Enum.RaycastFilterType.Include
	terrainParams.FilterDescendantsInstances = { workspace.Terrain }
	local function onGround(p: Vector3): Vector3
		local hit = workspace:Raycast(p + Vector3.new(0, 40, 0), Vector3.new(0, -100, 0), terrainParams)
		return if hit then Vector3.new(p.X, hit.Position.Y + 0.4, p.Z) else p
	end
	for k = 0, 23 do
		local a = k / 24 * math.pi * 2
		local nextA = (k + 1) / 24 * math.pi * 2
		local p1 = onGround(arenaCenter + Vector3.new(math.cos(a) * arenaR, 0, math.sin(a) * arenaR))
		local p2 = onGround(arenaCenter + Vector3.new(math.cos(nextA) * arenaR, 0, math.sin(nextA) * arenaR))
		local seg = (p2 - p1).Magnitude + 0.4
		part(
			folder,
			"ArenaRim",
			Vector3.new(1.4, 0.8, seg),
			CFrame.lookAt((p1 + p2) * 0.5, p2),
			Color3.fromRGB(185, 75, 65),
			Enum.Material.Slate
		)
	end
	local arenaSign = part(
		folder,
		"ArenaSign",
		Vector3.new(10, 3.2, 0.6),
		CFrame.new(0, Zones.FLOOR_Y + 4.5, 88),
		WOOD,
		Enum.Material.Wood
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 30
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "⚔ DUEL ARENA RING\nStep inside to PvP!"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(255, 220, 140)
	label.Parent = gui
	gui.Parent = arenaSign

	-- 3 Black Clover Storyline Quest Giver NPCs at the entrance of each Level-Tiered Area.
	local npcFolder = Instance.new("Folder")
	npcFolder.Name = "QuestGivers"
	npcFolder.Parent = folder
	-- Stand NPCs on the built terrain: its bumps sit above the Zones.groundY formula.
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Include
	groundParams.FilterDescendantsInstances = { workspace.Terrain }
	for _, qg in Zones.QUEST_GIVERS do
		local pos = Zones.polar(qg.angle, qg.r)
		local ground = workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -150, 0), groundParams)
		if ground then
			pos = Vector3.new(pos.X, ground.Position.Y, pos.Z)
		end
		local look = CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0))
		local npc = Instance.new("Model")
		npc.Name = qg.npcName
		npc.Parent = npcFolder
		part(npc, "Pedestal", Vector3.new(4, 0.8, 4), look * CFrame.new(0, 0.4, 0), STONE, Enum.Material.Slate)
		local torso = part(
			npc,
			"Torso",
			Vector3.new(2.2, 2.6, 1.3),
			look * CFrame.new(0, 2.4, 0),
			Color3.fromRGB(66, 78, 120),
			Enum.Material.Fabric
		)
		part(
			npc,
			"Head",
			Vector3.new(1.5, 1.5, 1.5),
			look * CFrame.new(0, 4.4, 0),
			Color3.fromRGB(235, 200, 170),
			Enum.Material.SmoothPlastic
		)
		part(
			npc,
			"Cloak",
			Vector3.new(2.5, 2.4, 0.4),
			look * CFrame.new(0, 2.3, 0.7),
			CLOTH_EMBER,
			Enum.Material.Fabric
		)
		local orb = part(
			npc,
			"QuestMark",
			Vector3.new(0.8, 0.8, 0.8),
			look * CFrame.new(0, 6.2, 0),
			Color3.fromRGB(255, 215, 90),
			Enum.Material.Neon
		)
		orb.CanCollide = false
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(180, 40)
		bb.StudsOffset = Vector3.new(0, 3.6, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 90
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextScaled = true
		lbl.TextColor3 = Color3.fromRGB(255, 225, 130)
		lbl.TextStrokeTransparency = 0.3
		lbl.Text = `! {qg.npcName}`
		lbl.Parent = bb
		bb.Parent = torso
		local pp = Instance.new("ProximityPrompt")
		pp.ActionText = "Area Quests"
		pp.ObjectText = qg.npcName
		pp.KeyboardKeyCode = Enum.KeyCode.E
		pp.HoldDuration = 0
		pp.MaxActivationDistance = 12
		pp.RequiresLineOfSight = false
		pp:SetAttribute("Action", "quest")
		pp:SetAttribute("AreaId", qg.areaId)
		pp.Parent = torso
	end

	folder.Parent = map
end

function CampService.plotOf(player: Player): number?
	return slotOf[player]
end

-- Where a player spawns: in a circle round the central campfire, facing the stations.
function CampService.spawnCFrame(player: Player): CFrame
	local slot = slotOf[player] or 1
	local angle = ((slot - 1) % 8) / 8 * math.pi * 2
	local r = 14
	local pos = Vector3.new(math.cos(angle) * r, Zones.FLOOR_Y + 4, math.sin(angle) * r)
	return CFrame.lookAt(pos, Vector3.new(0, pos.Y, -20))
end

-- Anywhere inside the Wizard Camp Courtyard counts as home (banks carried loot).
function CampService.atHome(_player: Player, position: Vector3): boolean
	return CampService.isSafe(position)
end

-- Inside the courtyard (near the shared desk and shelf).
function CampService.atDesk(_player: Player, position: Vector3): boolean
	return CampService.isSafe(position)
end

function CampService.isSafe(position: Vector3): boolean
	return Vector2.new(position.X, position.Z).Magnitude < CampService.SAFE_RADIUS
end

local function spawnAtHub(player: Player, character: Model)
	task.defer(function()
		if character.Parent ~= nil then
			character:PivotTo(CampService.spawnCFrame(player))
		end
	end)
end

local function assign(player: Player)
	if slotOf[player] ~= nil then
		return
	end
	nextSlot += 1
	slotOf[player] = nextSlot
	player:SetAttribute("PlotId", nextSlot)
	if player.Character then
		spawnAtHub(player, player.Character)
	end
	CampService.Assigned:Fire(player, nextSlot)
end

local function release(player: Player)
	slotOf[player] = nil
end

function CampService.Init()
	Players.RespawnTime = 5
	buildSanctuary()
	DataService.PlayerReady:Connect(assign)
	DataService.PlayerLeaving:Connect(release)
	Players.PlayerRemoving:Connect(release)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			if slotOf[player] then
				spawnAtHub(player, character)
			end
		end)
	end)
end

return CampService
