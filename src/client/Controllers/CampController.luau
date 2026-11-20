--!strict
-- Your camp's screens, opened from its prompts (CampService builds them):
--   desk   write spells into a grimoire (and pick your element after the tutorial)
--   shelf  choose the 3 equipped grimoires, and spend stat points
--   bank   what's safely banked
--   shop   the Ink Merchant (shared, by the campfire)
-- Prompts on other players' plots are hidden.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Client = script.Parent.Parent
local Spells = require(Shared:WaitForChild("Spells")) :: any
local Element = require(Shared:WaitForChild("Element")) :: any
local Level = require(Shared:WaitForChild("Level")) :: any
local Writing = require(Shared:WaitForChild("Writing")) :: any
local NetClient = require(Client:WaitForChild("Net"):WaitForChild("NetClient"))
local Kit = require(Client:WaitForChild("Ui"):WaitForChild("Kit"))
local StateController = require(script.Parent:WaitForChild("StateController"))

local CampController = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local open: string? = nil
local panel: Frame? = nil
local body: Frame
local quest: any = nil
local boosted = false
local reveal: any = nil -- the last WriteResult, shown on the desk

local function typeColor(kind: string): Color3
	return Kit.rgb(Element.COLOR[kind] or Element.COLOR.Neutral)
end

local function rarityColor(rarity: string): Color3
	return Kit.rgb(Spells.RARITY_COLOR[rarity] or Spells.RARITY_COLOR.Common)
end

local function close()
	if panel then
		panel:Destroy()
	end
	panel = nil
	open = nil
end

local render: (string) -> ()

local function show(name: string, title: string, size: Vector2)
	if panel then
		panel:Destroy()
	end
	open = name
	panel, body = Kit.panel(gui, title, size, close)
	render(name)
end

local function spellLine(page: any): string
	local spell = Spells.get(page.sp)
	if spell == nil then
		return "?"
	end
	local c = rarityColor(spell.rarity)
	return `<font color="#{c:ToHex()}"><b>{spell.name}</b></font> Lv {page.lv}`
end

-- Desk ----------------------------------------------------------------------------------------

local function renderReveal(data: any)
	local spell = reveal and Spells.get(reveal.spell)
	if spell == nil then
		return
	end
	local card =
		Kit.frame(body, UDim2.new(1, 0, 0, 128), UDim2.fromOffset(0, 0), rarityColor(spell.rarity):Lerp(Kit.PANEL, 0.6))
	local outcome = reveal.outcome
	local headline = ({
		added = "New spell written!",
		level = "Spell levelled up!",
		maxed = "Already at max level: ink refunded",
		choose = "Your book is full. Replace a page, or tear this one out",
		replaced = "Page replaced",
		torn = `Torn out (+15 coins)`,
	} :: any)[outcome] or ""
	Kit.label(
		card,
		`<b>{spell.rarity}</b> · {spell.type}`,
		UDim2.new(1, -16, 0, 20),
		UDim2.fromOffset(8, 6),
		14,
		rarityColor(spell.rarity)
	)
	Kit.label(card, `<b>{spell.name}</b>`, UDim2.new(1, -16, 0, 30), UDim2.fromOffset(8, 26), 26)
	Kit.label(card, spell.blurb, UDim2.new(1, -16, 0, 20), UDim2.fromOffset(8, 58), 14, Kit.MUTED)
	Kit.label(card, headline, UDim2.new(1, -16, 0, 20), UDim2.fromOffset(8, 80), 15, Kit.GOLD)
	if outcome == "choose" then
		local book = data.books[reveal.book]
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, -16, 0, 26)
		row.Position = UDim2.fromOffset(8, 100)
		row.Parent = card
		Kit.list(row, 4, true)
		for i, page in book.pages do
			local s = Spells.get(page.sp)
			Kit.button(
				row,
				`Replace {s and s.name or "?"}`,
				UDim2.fromOffset(104, 24),
				UDim2.new(),
				Kit.PANEL,
				function()
					NetClient.send("WriteResolve", i)
				end
			).TextSize =
				11
		end
		Kit.button(row, "Tear out", UDim2.fromOffset(70, 24), UDim2.new(), Kit.BAD, function()
			NetClient.send("WriteResolve", 0)
		end).TextSize =
			12
	end
end

local function renderDesk()
	local data = StateController.get()
	if data == nil then
		return
	end
	local y = 0
	if reveal then
		renderReveal(data)
		y = 136
	end
	-- The element pick, once the tutorial reaches it.
	if data.element == "" and quest and quest.index == 6 then
		Kit.label(
			body,
			"<b>Pick your element grimoire</b> (it comes with its first spell)",
			UDim2.new(1, 0, 0, 22),
			UDim2.fromOffset(0, y),
			16,
			Kit.GOLD
		)
		for i, kind in { "Fire", "Water", "Leaf" } do
			local ready = true
			local b = Kit.button(
				body,
				if ready then `<b>{kind}</b>` else `{kind}\n<font size="11">coming soon</font>`,
				UDim2.fromOffset(150, 48),
				UDim2.fromOffset((i - 1) * 160, y + 26),
				if ready then typeColor(kind) else Kit.PANEL_LIGHT,
				function()
					NetClient.send("PickElement", kind)
				end
			)
			if ready then
				b.TextColor3 = Color3.fromRGB(30, 22, 20)
			end
		end
		y += 84
	end
	local boost = Kit.button(
		body,
		if boosted
			then `★ Boosted odds ON ({Writing.STAR_COST}★ per write)`
			else `Boosted odds off  (you have {data.stars}★)`,
		UDim2.fromOffset(330, 28),
		UDim2.fromOffset(0, y),
		if boosted then Kit.GOLD else Kit.PANEL_LIGHT,
		function()
			boosted = not boosted
			render("desk")
		end
	)
	boost.TextSize = 13
	y += 36
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.Size = UDim2.new(1, 0, 1, -y)
	scroll.Position = UDim2.fromOffset(0, y)
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = body
	Kit.list(scroll, 6)
	for index, book in data.books do
		local row = Kit.frame(scroll, UDim2.new(1, -10, 0, 74), UDim2.new(), Kit.PANEL_LIGHT)
		row.LayoutOrder = index
		local ink = data.bank.ink[book.type] or 0
		Kit.label(
			row,
			`<b>{book.type} grimoire</b>  ·  {ink} ink banked`,
			UDim2.new(1, -150, 0, 20),
			UDim2.fromOffset(10, 4),
			15,
			typeColor(book.type)
		).TextXAlignment =
			Enum.TextXAlignment.Left
		local pages = {}
		for _, page in book.pages do
			table.insert(pages, spellLine(page))
		end
		for _ = #book.pages + 1, Writing.PAGES do
			table.insert(pages, '<font color="#7a7288">blank</font>')
		end
		local list = Kit.label(row, table.concat(pages, "   "), UDim2.new(1, -150, 0, 44), UDim2.fromOffset(10, 26), 13)
		list.TextXAlignment = Enum.TextXAlignment.Left
		list.TextYAlignment = Enum.TextYAlignment.Top
		Kit.button(
			row,
			if ink > 0 then 'Write\n<font size="11">1 ink</font>' else "No ink",
			UDim2.fromOffset(120, 54),
			UDim2.new(1, -130, 0, 10),
			if ink > 0 then Kit.GOOD else Kit.PANEL,
			function()
				NetClient.send("Write", index, boosted)
			end
		)
	end
end

-- Shelf ---------------------------------------------------------------------------------------

local function renderShelf()
	local data = StateController.get()
	if data == nil then
		return
	end
	-- Stats.
	local spent = data.stats.health + data.stats.power + data.stats.defense
	local free = Level.pointsEarned(data.level) - spent
	Kit.label(body, `<b>Stat points</b>: {free} free`, UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, 0), 16, Kit.GOLD).TextXAlignment =
		Enum.TextXAlignment.Left
	local STATS = {
		{ "health", "Health", `+{Level.HEALTH_PER_POINT} max HP` },
		{ "power", "Power", "+2% damage" },
		{ "defense", "Defense", "-2% damage taken" },
	}
	for i, stat in STATS do
		local x = (i - 1) * 168
		local card = Kit.frame(body, UDim2.fromOffset(160, 70), UDim2.fromOffset(x, 26), Kit.PANEL_LIGHT)
		Kit.label(card, `<b>{stat[2]}</b>  {data.stats[stat[1]]}`, UDim2.new(1, -10, 0, 20), UDim2.fromOffset(6, 4), 15)
		Kit.label(card, stat[3], UDim2.new(1, -10, 0, 16), UDim2.fromOffset(6, 24), 12, Kit.MUTED)
		Kit.button(
			card,
			"+1",
			UDim2.fromOffset(46, 22),
			UDim2.fromOffset(6, 44),
			if free > 0 then Kit.GOOD else Kit.PANEL,
			function()
				NetClient.send("AllocateStat", stat[1], 1)
			end
		).TextSize =
			13
		Kit.button(
			card,
			"+5",
			UDim2.fromOffset(46, 22),
			UDim2.fromOffset(56, 44),
			if free > 0 then Kit.GOOD else Kit.PANEL,
			function()
				NetClient.send("AllocateStat", stat[1], 5)
			end
		).TextSize =
			13
	end
	Kit.button(body, "Reset (free)", UDim2.fromOffset(110, 26), UDim2.new(1, -110, 0, 0), Kit.PANEL_LIGHT, function()
		NetClient.send("ResetStats")
	end).TextSize =
		13

	-- Grimoires.
	Kit.label(
		body,
		"<b>Grimoires</b>: equip up to 3 (keys 1 2 3 swap between them)",
		UDim2.new(1, 0, 0, 22),
		UDim2.fromOffset(0, 106),
		15,
		Kit.GOLD
	).TextXAlignment =
		Enum.TextXAlignment.Left
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.Size = UDim2.new(1, 0, 1, -132)
	scroll.Position = UDim2.fromOffset(0, 132)
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = body
	Kit.list(scroll, 6)
	for index, book in data.books do
		local row = Kit.frame(scroll, UDim2.new(1, -10, 0, 50), UDim2.new(), Kit.PANEL_LIGHT)
		row.LayoutOrder = index
		local slot = table.find(data.equipped, index)
		Kit.label(
			row,
			`<b>{book.type}</b>  {#book.pages}/4 pages{if slot then `  ·  slot {slot}` else ""}`,
			UDim2.new(1, -200, 1, 0),
			UDim2.fromOffset(10, 0),
			15,
			typeColor(book.type)
		).TextXAlignment =
			Enum.TextXAlignment.Left
		for s = 1, #data.equipped do
			Kit.button(
				row,
				`Slot {s}`,
				UDim2.fromOffset(58, 30),
				UDim2.new(1, -190 + (s - 1) * 62, 0, 10),
				if slot == s then Kit.GOLD else Kit.PANEL,
				function()
					NetClient.send("EquipBook", s, index)
				end
			).TextSize =
				13
		end
	end
end

-- Bank and shop ---------------------------------------------------------------------------------

local function renderBank()
	local data = StateController.get()
	if data == nil then
		return
	end
	local lines = { `Coins <b>{data.bank.coins}</b> coins`, `★ <b>{data.stars}</b> stars` }
	for kind, n in data.bank.ink do
		if n > 0 then
			table.insert(lines, `<b>{n}</b> {kind} ink`)
		end
	end
	for kind, n in data.bank.frag do
		if n > 0 then
			table.insert(
				lines,
				`<b>{n}</b> {kind} binding fragment{if n == 1 then "" else "s"} (binding arrives later)`
			)
		end
	end
	Kit.label(body, table.concat(lines, "\n"), UDim2.new(1, 0, 1, -40), UDim2.new(), 16).TextYAlignment =
		Enum.TextYAlignment.Top
	Kit.label(
		body,
		"Banked loot is safe. Carried loot can be dropped or stolen.",
		UDim2.new(1, 0, 0, 30),
		UDim2.new(0, 0, 1, -30),
		13,
		Kit.MUTED
	)
end

local function renderShop()
	local data = StateController.get()
	if data == nil then
		return
	end
	Kit.label(body, `You have Coins <b>{data.bank.coins}</b> banked coins`, UDim2.new(1, 0, 0, 22), UDim2.new(), 16)
	local items = {
		{ "ink_Neutral", "Neutral ink", 40, true },
		{ "ink_Fire", "Fire ink", 80, data.element == "Fire" },
		{ "ink_Water", "Water ink", 80, data.element == "Water" },
		{ "ink_Leaf", "Leaf ink", 80, data.element == "Leaf" },
	}
	for i, item in items do
		local row = Kit.frame(body, UDim2.new(1, 0, 0, 50), UDim2.fromOffset(0, 30 + (i - 1) * 58), Kit.PANEL_LIGHT)
		Kit.label(
			row,
			`<b>{item[2]}</b>{if item[4] then "" else "  (your element only)"}`,
			UDim2.new(1, -140, 1, 0),
			UDim2.fromOffset(10, 0),
			15
		).TextXAlignment =
			Enum.TextXAlignment.Left
		Kit.button(
			row,
			`Coins {item[3]}`,
			UDim2.fromOffset(110, 34),
			UDim2.new(1, -120, 0, 8),
			if item[4] and data.bank.coins >= item[3] then Kit.GOOD else Kit.PANEL,
			function()
				NetClient.send("Buy", item[1])
			end
		)
	end
end

render = function(name: string)
	if panel == nil then
		return
	end
	Kit.clear(body)
	if name == "desk" then
		renderDesk()
	elseif name == "shelf" then
		renderShelf()
	elseif name == "bank" then
		renderBank()
	elseif name == "shop" then
		renderShop()
	end
end

local TITLES = {
	desk = { "Writing desk", Vector2.new(520, 470) },
	shelf = { "Shelf: grimoires & stats", Vector2.new(520, 420) },
	bank = { "Bank", Vector2.new(400, 300) },
	shop = { "Ink Merchant", Vector2.new(400, 320) },
} :: { [string]: { any } }

-- Prompts on plots that aren't yours stay hidden.
local function gate(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	local plot: Instance? = prompt.Parent
	while plot and plot:GetAttribute("PlotId") == nil do
		plot = plot.Parent
	end
	if plot then
		prompt.Enabled = plot:GetAttribute("OwnerId") == player.UserId
	end
end

function CampController.Init()
	gui = Kit.screen("Camp", 5)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local action = prompt:GetAttribute("Action")
		local title = type(action) == "string" and TITLES[action]
		if title then
			if action == "desk" then
				reveal = nil
			end
			show(action :: string, title[1], title[2])
		end
	end)
	StateController.Changed:Connect(function()
		if open then
			render(open)
		end
	end)
	NetClient.on("Quest", function(view: any)
		quest = view
		if open == "desk" then
			render("desk")
		end
	end)
	NetClient.on("WriteResult", function(outcome: string, spell: string, book: number)
		reveal = { outcome = outcome, spell = spell, book = book }
		if open == "desk" then
			render("desk")
		end
	end)
end

function CampController.Start()
	local plots = workspace:WaitForChild("Map"):WaitForChild("Plots")
	for _, d in plots:GetDescendants() do
		gate(d)
	end
	plots.DescendantAdded:Connect(function(d)
		task.defer(gate, d)
	end)
	for _, plot in plots:GetChildren() do
		plot:GetAttributeChangedSignal("OwnerId"):Connect(function()
			for _, d in plot:GetDescendants() do
				gate(d)
			end
		end)
	end
	-- Walking away closes the panel.
	while true do
		task.wait(0.5)
		local character = player.Character
		if open and character then
			local pos = character:GetPivot().Position
			if Vector2.new(pos.X, pos.Z).Magnitude > 150 then
				close()
			end
		end
	end
end

return CampController
