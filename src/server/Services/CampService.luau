--!strict
-- Your camp plot (GDD "Loot, camp and risk"): assigns each player the lowest free plot, spawns
-- them there, and builds its desk (write spells, pick an element), shelf (equip grimoires) and
-- bank chest. The camp clearing is safe: enemies never follow you in.
--
-- Plots are the place's Map.Plots models: a `PlotId` attribute, a `Floor` part facing the
-- campfire and a `Zone` volume. The client opens the right screen from a prompt's `Action`
-- attribute, and only shows prompts on the plot whose `OwnerId` is its own.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local CampService = {}
CampService.Assigned = Signal.new() -- (player, plotId)

CampService.SAFE_RADIUS = 150 -- the camp clearing round the campfire: no enemies, no combat

type Plot = { id: number, model: Model, floor: BasePart, zone: BasePart }

local plots: { Plot } = {}
local owners: { [number]: Player } = {}
local plotOf: { [Player]: number } = {}

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
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = text
	pp.ObjectText = object
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 10
	pp.RequiresLineOfSight = false
	pp:SetAttribute("Action", action)
	pp.Parent = parent
end

local WOOD = Color3.fromRGB(120, 84, 56)
local WOOD_DARK = Color3.fromRGB(86, 60, 42)

-- The desk, shelf and bank chest, laid out on the plot's floor (local space: -Z faces camp).
local function furnish(plot: Plot)
	local old = plot.model:FindFirstChild("Camp")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Model")
	folder.Name = "Camp"
	local base = plot.floor.CFrame * CFrame.new(0, plot.floor.Size.Y / 2, 0)

	-- Desk: a chunky writing table, an open book and a candle.
	local desk = base * CFrame.new(-8, 0, 4)
	local top = part(folder, "Desk", Vector3.new(7, 0.8, 4), desk * CFrame.new(0, 3.2, 0), WOOD)
	for _, x in { -3, 3 } do
		for _, z in { -1.5, 1.5 } do
			part(folder, "Leg", Vector3.new(0.8, 2.8, 0.8), desk * CFrame.new(x, 1.4, z), WOOD_DARK)
		end
	end
	local pageColor = Color3.fromRGB(240, 228, 200)
	part(
		folder,
		"Page",
		Vector3.new(1.6, 0.2, 2.2),
		desk * CFrame.new(-0.85, 3.7, 0) * CFrame.Angles(0, 0, 0.12),
		pageColor,
		Enum.Material.SmoothPlastic
	)
	part(
		folder,
		"Page",
		Vector3.new(1.6, 0.2, 2.2),
		desk * CFrame.new(0.85, 3.7, 0) * CFrame.Angles(0, 0, -0.12),
		pageColor,
		Enum.Material.SmoothPlastic
	)
	local candle = part(
		folder,
		"Candle",
		Vector3.new(0.5, 1, 0.5),
		desk * CFrame.new(2.6, 4.1, -1),
		Color3.fromRGB(236, 224, 190),
		Enum.Material.SmoothPlastic
	)
	local flame = part(
		folder,
		"Flame",
		Vector3.new(0.3, 0.5, 0.3),
		candle.CFrame * CFrame.new(0, 0.75, 0),
		Color3.fromRGB(255, 190, 90),
		Enum.Material.Neon
	)
	flame.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 120)
	light.Range = 12
	light.Brightness = 1.2
	light.Parent = flame
	prompt(top, "desk", "Write spells", "Desk")

	-- Shelf: three planks of books.
	local shelf = base * CFrame.new(8, 0, 6)
	local back = part(folder, "Shelf", Vector3.new(6, 7, 0.6), shelf * CFrame.new(0, 3.5, 1.2), WOOD_DARK)
	for i = 0, 2 do
		part(folder, "Plank", Vector3.new(6, 0.4, 2.2), shelf * CFrame.new(0, 1 + i * 2.3, 0.2), WOOD)
		for b = 0, 4 do
			local hue = (b * 0.17 + i * 0.31) % 1
			part(
				folder,
				"Book",
				Vector3.new(0.7, 1.5, 1.6),
				shelf
					* CFrame.new(-2.2 + b * 1.05, 1.95 + i * 2.3, 0.2)
					* CFrame.Angles(0, 0, if b == 3 then 0.25 else 0),
				Color3.fromHSV(hue, 0.35, 0.6),
				Enum.Material.SmoothPlastic
			)
		end
	end
	prompt(back, "shelf", "Grimoires & stats", "Shelf")

	-- Bank chest: banking happens by walking in; the chest is where you see it.
	local chest = base * CFrame.new(0, 0, 10)
	local box = part(folder, "Chest", Vector3.new(4.5, 2.4, 3), chest * CFrame.new(0, 1.2, 0), WOOD)
	part(folder, "Lid", Vector3.new(4.7, 0.9, 3.2), chest * CFrame.new(0, 2.85, 0), WOOD_DARK)
	part(
		folder,
		"Band",
		Vector3.new(0.5, 3.4, 3.3),
		chest * CFrame.new(-1.4, 1.65, 0),
		Color3.fromRGB(196, 160, 80),
		Enum.Material.Metal
	)
	part(
		folder,
		"Band",
		Vector3.new(0.5, 3.4, 3.3),
		chest * CFrame.new(1.4, 1.65, 0),
		Color3.fromRGB(196, 160, 80),
		Enum.Material.Metal
	)
	prompt(box, "bank", "View bank", "Bank")

	folder.Parent = plot.model
end

local function setSign(plot: Plot, text: string)
	local sign = plot.model:FindFirstChild("Sign")
	if sign == nil then
		return
	end
	for _, d in sign:GetDescendants() do
		if d:IsA("TextLabel") then
			d.Text = text
		end
	end
end

local function discover()
	local map = workspace:WaitForChild("Map")
	for _, model in (map:WaitForChild("Plots") :: Instance):GetChildren() do
		local id = model:GetAttribute("PlotId")
		local floor = model:FindFirstChild("Floor")
		local zone = model:FindFirstChild("Zone")
		if
			type(id) == "number"
			and model:IsA("Model")
			and floor
			and floor:IsA("BasePart")
			and zone
			and zone:IsA("BasePart")
		then
			-- v1 leftovers: the Glowling pads and decor spots.
			for _, name in { "Slots", "DecorZone" } do
				local old = model:FindFirstChild(name)
				if old then
					old:Destroy()
				end
			end
			table.insert(plots, { id = id, model = model, floor = floor, zone = zone })
		end
	end
	table.sort(plots, function(a, b)
		return a.id < b.id
	end)
	-- v1 camp stations with nothing behind them now.
	local stations = map:FindFirstChild("Stations")
	if stations then
		for _, name in { "WispStash", "Leaderboards", "WhatsNew" } do
			local old = stations:FindFirstChild(name)
			if old then
				old:Destroy()
			end
		end
		local shop = stations:FindFirstChild("LanternShop")
		if shop and shop:IsA("Model") then
			shop.Name = "InkMerchant"
			for _, d in shop:GetDescendants() do
				if d:IsA("TextLabel") then
					d.Text = "Ink Merchant"
				end
			end
			local anchor = part(shop, "PromptAnchor", Vector3.new(4, 4, 4), shop:GetPivot() * CFrame.new(0, 3, 0), WOOD)
			anchor.Transparency = 1
			anchor.CanCollide = false
			prompt(anchor, "shop", "Buy ink", "Ink Merchant")
		end
	end
end

local function byId(id: number): Plot?
	for _, plot in plots do
		if plot.id == id then
			return plot
		end
	end
	return nil
end

function CampService.plotOf(player: Player): number?
	return plotOf[player]
end

-- Where a player spawns: on their plot, facing the campfire.
function CampService.spawnCFrame(player: Player): CFrame
	local plot = byId(plotOf[player] or 0)
	if plot == nil then
		return CFrame.new(18, 4, 0)
	end
	local pos = plot.floor.Position + Vector3.new(0, 4, 0)
	return CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0))
end

-- Is `position` on the player's own plot?
function CampService.atHome(player: Player, position: Vector3): boolean
	local plot = byId(plotOf[player] or 0)
	if plot == nil then
		return false
	end
	local rel = plot.zone.CFrame:PointToObjectSpace(position)
	local half = plot.zone.Size / 2 + Vector3.new(2, 8, 2)
	return math.abs(rel.X) <= half.X and math.abs(rel.Z) <= half.Z and math.abs(rel.Y) <= half.Y
end

-- Near the player's own desk (writes and equips happen there).
function CampService.atDesk(player: Player, position: Vector3): boolean
	local plot = byId(plotOf[player] or 0)
	return plot ~= nil and (plot.floor.Position - position).Magnitude < 34
end

function CampService.isSafe(position: Vector3): boolean
	return Vector2.new(position.X, position.Z).Magnitude < CampService.SAFE_RADIUS
end

local function spawnAtPlot(player: Player, character: Model)
	task.defer(function()
		if character.Parent ~= nil then
			character:PivotTo(CampService.spawnCFrame(player))
		end
	end)
end

local function assign(player: Player)
	if plotOf[player] ~= nil then
		return
	end
	for _, plot in plots do
		if owners[plot.id] == nil then
			owners[plot.id] = player
			plotOf[player] = plot.id
			plot.model:SetAttribute("OwnerId", player.UserId)
			furnish(plot)
			setSign(plot, `{player.DisplayName}'s camp`)
			player:SetAttribute("PlotId", plot.id)
			if player.Character then
				spawnAtPlot(player, player.Character)
			end
			CampService.Assigned:Fire(player, plot.id)
			return
		end
	end
	warn(`[CampService] No free plot for {player.Name}`)
end

local function release(player: Player)
	local id = plotOf[player]
	if id == nil then
		return
	end
	plotOf[player] = nil
	owners[id] = nil
	local plot = byId(id)
	if plot then
		plot.model:SetAttribute("OwnerId", nil)
		local camp = plot.model:FindFirstChild("Camp")
		if camp then
			camp:Destroy()
		end
		setSign(plot, "Free camp")
	end
end

function CampService.Init()
	Players.RespawnTime = 5
	discover()
	for _, plot in plots do
		setSign(plot, "Free camp")
	end
	DataService.PlayerReady:Connect(assign)
	DataService.PlayerLeaving:Connect(release)
	Players.PlayerRemoving:Connect(release)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			if plotOf[player] then
				spawnAtPlot(player, character)
			end
		end)
	end)
end

return CampService
