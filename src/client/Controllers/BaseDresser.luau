--!strict
-- Dresses a plot for its tier (Shared.BaseTier) and draws its placed decorations, from the
-- models in ReplicatedStorage.WorldAssets (kept in the place file):
--   Tiers/   Tent, Cabin, Cottage, Treehouse, Sanctuary, FenceRope, FenceWood, FenceStone, LampPost
--   Decor/   one model per decoration id (config decor.items)
-- Every model is pivoted at its bottom centre with its front facing -Z. Without WorldAssets the
-- plot keeps its plain floor and decorations fall back to blocks.
--
-- Everything here is local and cosmetic: no collision, no queries, nothing the server reads.
-- (Not a controller: PlotController calls it while it draws a plot.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseTier = require(Shared:WaitForChild("BaseTier"))
local Decor = require(Shared:WaitForChild("Decor"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any

local BaseDresser = {}

local DECOR_FALLBACK = Color3.fromRGB(170, 140, 100)
local GATE_HALF = 6.6 -- the fence stops this far either side of the gate's centre
local LAMP_LIGHT = Color3.fromRGB(255, 196, 120)

-- Target height (studs) for decorations that stand up; the rest fill their footprint.
local DECOR_HEIGHT: { [string]: number } = {
	string_lights = 5,
	paper_lanterns = 5,
	glow_mushrooms = 1.8,
	crystal_lamp = 4.5,
	banner_moss = 7,
	banner_ember = 7,
	banner_star = 7,
	stump_seat = 1.8,
	log_bench = 2.4,
	glowling_statue = 4.5,
	owl_totem = 6,
	firefly_jar = 3,
	star_arch = 7.5,
	welcome_sign = 4,
	fire_bowl = 2.8,
	gift_lantern_arch = 7.5,
	pass_moth_banner = 7,
	pass_star_lamp = 6.5,
}
local GLOWING: { [string]: Color3 } = {
	crystal_lamp = Color3.fromRGB(120, 230, 220),
	glow_mushrooms = Color3.fromRGB(110, 230, 220),
	paper_lanterns = Color3.fromRGB(255, 180, 120),
	firefly_jar = Color3.fromRGB(255, 230, 120),
	fire_bowl = Color3.fromRGB(255, 150, 70),
	pass_star_lamp = Color3.fromRGB(255, 220, 130),
	string_lights = Color3.fromRGB(255, 210, 140),
}

local function assets(group: string): Folder?
	local root = ReplicatedStorage:FindFirstChild("WorldAssets")
	return if root ~= nil then root:FindFirstChild(group) :: Folder? else nil
end

local function template(group: string, name: string): Model?
	local folder = assets(group)
	local found = if folder ~= nil then folder:FindFirstChild(name) else nil
	return if found ~= nil and found:IsA("Model") then found else nil
end

local function cosmetic(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
end

-- A clone of `source` scaled by `scale`, its bottom centre at `at`.
local function place(source: Model, scale: number, at: CFrame, parent: Instance): Model
	local model = source:Clone()
	model:ScaleTo(model:GetScale() * scale)
	model:PivotTo(at)
	cosmetic(model)
	model.Parent = parent
	return model
end

local function size(source: Model): Vector3
	local _, extents = source:GetBoundingBox()
	return extents
end

local function light(model: Model, color: Color3, range: number)
	local part = model:FindFirstChildWhichIsA("BasePart", true)
	if part ~= nil then
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = range
		l.Brightness = 1.2
		l.Shadows = false
		l.Parent = part
	end
end

-- A fence along `from` → `to` (plot-local, on the floor), tiled from the template.
local function fence(source: Model, plotCF: CFrame, from: Vector3, to: Vector3, parent: Instance)
	local span = to - from
	local length = span.Magnitude
	local unit = size(source).X
	local count = math.max(1, math.round(length / unit))
	local scale = (length / count) / unit
	local dir = span.Unit
	for k = 0, count - 1 do
		local mid = from + dir * ((k + 0.5) * length / count)
		local cf = plotCF * CFrame.lookAt(mid, mid + dir) * CFrame.Angles(0, math.pi / 2, 0)
		place(source, scale, cf, parent)
	end
end

-- Dresses one plot. `plot` is the Plot model, `owned` whether anyone has it.
function BaseDresser.dress(plot: Instance, slots: number, owned: boolean, parent: Instance)
	local floor = plot:FindFirstChild("Floor")
	if floor == nil or not floor:IsA("BasePart") or assets("Tiers") == nil then
		return
	end
	local look = BaseTier.look(slots, owned)
	local W, D = floor.Size.X, floor.Size.Z
	local top = floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0)
	local c = look.floorColor
	floor.Material = (Enum.Material :: any)[look.floor]
	floor.Color = Color3.fromRGB(c[1], c[2], c[3])

	local dressing = Instance.new("Folder")
	dressing.Name = "Dressing"

	local fenceModel = template("Tiers", look.fence)
	if fenceModel ~= nil then
		local hw, hd = W / 2 - 0.4, D / 2 - 0.4
		fence(fenceModel, top, Vector3.new(-hw, 0, -hd), Vector3.new(-hw, 0, hd), dressing)
		fence(fenceModel, top, Vector3.new(hw, 0, hd), Vector3.new(hw, 0, -hd), dressing)
		fence(fenceModel, top, Vector3.new(-hw, 0, hd), Vector3.new(hw, 0, hd), dressing)
		fence(fenceModel, top, Vector3.new(-hw, 0, -hd), Vector3.new(-GATE_HALF, 0, -hd), dressing)
		fence(fenceModel, top, Vector3.new(GATE_HALF, 0, -hd), Vector3.new(hw, 0, -hd), dressing)
	end

	-- The home stands behind the plot, its door toward the fire.
	local home = if look.home ~= nil then template("Tiers", look.home) else nil
	if home ~= nil then
		local s = size(home)
		local scale = look.homeHeight / s.Y
		local depth = s.Z * scale
		place(home, scale, top * CFrame.new(0, -0.3, D / 2 + depth / 2 + 1), dressing)
	end

	local lamp = if look.lamps ~= nil then template("Tiers", look.lamps) or template("Decor", look.lamps) else nil
	if lamp ~= nil then
		local glow = if look.lamps == "crystal_lamp" then Color3.fromRGB(120, 230, 220) else LAMP_LIGHT
		for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			local at = top * CFrame.new(corner[1] * (W / 2 - 1.6), 0, corner[2] * (D / 2 - 1.6))
			local m = place(lamp, 8 / size(lamp).Y, at, dressing)
			light(m, glow, 16)
		end
	end

	if look.banners then
		for k, x in { -9, 9 } do
			local banner = template("Decor", if k == 1 then "banner_moss" else "banner_star")
			if banner ~= nil then
				place(banner, 8 / size(banner).Y, top * CFrame.new(x, 0, -D / 2 + 1.2), dressing)
			end
		end
	end

	local arch = if look.arch ~= nil then template("Decor", look.arch) else nil
	if arch ~= nil then
		-- Over the way from the plot to the home.
		place(arch, 11 / size(arch).Y, top * CFrame.new(0, 0, D / 2 - 0.6), dressing)
	end

	dressing.Parent = parent
end

-- Draws the plot's placed decorations on its DecorZone.
function BaseDresser.decor(zone: BasePart, placed: { any }, parent: Instance)
	for i, d in placed do
		local item = Decor.item(economy, d.id)
		if item == nil then
			continue
		end
		local at = zone.CFrame * CFrame.new(d.x, zone.Size.Y / 2, d.z) * CFrame.Angles(0, d.rot * math.pi / 2, 0)
		local source = template("Decor", d.id)
		if source == nil then
			local block = Instance.new("Part")
			block.Name = `Decor{i}`
			block.Size = Vector3.new(item.w - 0.2, 1, item.d - 0.2)
			block.CFrame = at * CFrame.new(0, 0.5, 0)
			block.Color = DECOR_FALLBACK
			block.Anchored = true
			block.CanCollide = false
			block.CanTouch = false
			block.CanQuery = false
			block.Parent = parent
			continue
		end
		local s = size(source)
		local height = DECOR_HEIGHT[d.id]
		local scale = if height ~= nil then height / s.Y else math.min(item.w / s.X, item.d / s.Z)
		local model = place(source, scale, at, parent)
		model.Name = `Decor{i}`
		local glow = GLOWING[d.id]
		if glow ~= nil and i <= 12 then -- a few lights per plot keep phones fast
			light(model, glow, 10)
		end
	end
end

return BaseDresser
