--!strict
-- Camp Courtyard & Area Quest Giver screens:
--   desk   6-Tier Black Clover Grimoire Gacha (5★ Stars per roll, with Pity) & Fixed Z/X/C/V
--          skill unlocking/upgrading with Universal Ink
--   shelf  Equip up to 3 Grimoires (1/2/3) & allocate Stat Points
--   bank   Banked Coins, Universal Ink, ★ Stars, and PvP Bounty
--   shop   Gear & Ink Shop: buy the 4 Visible Gear Categories (Backpack, Robe, Hat, Boots) with Coins!
--   quest  Black Clover Storyline Area Quest Board (Elder Orsi, Scout Captain, Knight Envoy)

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Client = script.Parent.Parent
local Spells = require(Shared:WaitForChild("Spells")) :: any
local Element = require(Shared:WaitForChild("Element")) :: any
local Gears = require(Shared:WaitForChild("Gears")) :: any
local Level = require(Shared:WaitForChild("Level")) :: any
local Loot = require(Shared:WaitForChild("Loot")) :: any
local Quests = require(Shared:WaitForChild("Quests")) :: any
local Writing = require(Shared:WaitForChild("Writing")) :: any
local Zones = require(Shared:WaitForChild("Zones")) :: any
local NetClient = require(Client:WaitForChild("Net"):WaitForChild("NetClient"))
local Kit = require(Client:WaitForChild("Ui"):WaitForChild("Kit"))
local StateController = require(script.Parent:WaitForChild("StateController"))

local CampController = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local open: string? = nil
local panel: Frame? = nil
local body: Frame
local reveal: any = nil
local questArea: string = "area1"

local KEYS = { "Z", "X", "C", "V" }

local function typeColor(kind: string): Color3
	return Kit.rgb(Element.COLOR[kind] or Element.COLOR.Neutral)
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

-- Desk (Grimoire Gacha + Fixed Z/X/C/V Skill Unlocks & Upgrades) ------------------------------

local function renderDesk()
	local data = StateController.get()
	if data == nil then
		return
	end
	local totalInk = Loot.totalInk(data.bank)
	local stars = data.stars or 0
	local pity = data.pity or 0

	local gachaCard = Kit.frame(body, UDim2.new(1, 0, 0, 96), UDim2.fromOffset(0, 0), Kit.PANEL_LIGHT)
	Kit.label(
		gachaCard,
		`<b>★ Black Clover Grimoire Gacha</b>   ·   You have <b>{stars}★ Stars</b>   (Pity: {pity}/40)`,
		UDim2.new(1, -160, 0, 22),
		UDim2.fromOffset(10, 6),
		15,
		Kit.GOLD
	).TextXAlignment =
		Enum.TextXAlignment.Left
	Kit.label(
		gachaCard,
		"Common 48% (Fire/Water/Leaf) · Uncommon 26% (Wind/Earth) · Rare 14% (Frost)\nEpic 8% (Lightning) · Legendary 3% (Gravity) · Mythic 1% (4-Leaf Light / 5-Leaf Dark)",
		UDim2.new(1, -160, 0, 38),
		UDim2.fromOffset(10, 28),
		12,
		Kit.MUTED
	).TextXAlignment =
		Enum.TextXAlignment.Left

	if reveal then
		local book = data.books[reveal.book]
		local bType = if book then book.type else "Neutral"
		local clovers = Element.clovers(bType)
		local rTier = Element.RARITY[bType] or "Common"
		local spell = Spells.get(reveal.spell)
		local msg = if reveal.outcome == "rolled"
			then `NEW! [{rTier}] {clovers}-Leaf {bType} Grimoire!`
			elseif reveal.outcome == "dupe_book" then `Duplicate {bType} Grimoire → +3 Universal Ink!`
			else `{if spell then spell.name else ""}: {reveal.outcome}!`
		Kit.label(gachaCard, `<b>{msg}</b>`, UDim2.new(1, -160, 0, 20), UDim2.fromOffset(10, 70), 14, typeColor(bType)).TextXAlignment =
			Enum.TextXAlignment.Left
	end

	Kit.button(
		gachaCard,
		`<b>Roll Grimoire</b>\n<font size="12">{Element.STAR_ROLL_COST}★ Stars</font>`,
		UDim2.fromOffset(136, 72),
		UDim2.new(1, -146, 0, 12),
		if stars >= Element.STAR_ROLL_COST then Kit.GOLD else Kit.PANEL,
		function()
			NetClient.send("RollGrimoire")
		end
	)

	Kit.label(
		body,
		`<b>Your Grimoires</b> — Spend <b>Universal Ink ({totalInk} banked)</b> to unlock X → C → V & upgrade Lv 1–5`,
		UDim2.new(1, 0, 0, 22),
		UDim2.fromOffset(0, 102),
		14,
		Kit.TEXT
	).TextXAlignment =
		Enum.TextXAlignment.Left

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.Size = UDim2.new(1, 0, 1, -128)
	scroll.Position = UDim2.fromOffset(0, 128)
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = body
	Kit.list(scroll, 8)

	for index, book in data.books do
		local bType = book.type
		local clovers = Element.clovers(bType)
		local rTier = Element.RARITY[bType] or "Common"
		local passive = Element.PASSIVE[bType]
		local fixed = Spells.fixedFor(bType)
		local row = Kit.frame(scroll, UDim2.new(1, -10, 0, 104), UDim2.new(), Kit.PANEL_LIGHT)
		row.LayoutOrder = index

		Kit.label(
			row,
			`<b>{clovers}-Leaf {bType} Grimoire</b>  <font size="12">[{rTier}]</font>   ·   <font size="12">{if passive
				then passive.name .. ": " .. passive.blurb
				else ""}</font>`,
			UDim2.new(1, -16, 0, 22),
			UDim2.fromOffset(10, 4),
			14,
			typeColor(bType)
		).TextXAlignment =
			Enum.TextXAlignment.Left

		for slot = 1, 4 do
			local spellId = fixed[slot]
			local spell = spellId and Spells.get(spellId)
			local page = book.pages[slot]
			local cost, action = Writing.slotCost(book, slot)
			local btnTitle = if page and spell
				then `<b>[{KEYS[slot]}] {spell.name}</b>\n<font size="11">Lv {page.lv}/5 · {if cost
					then `Upgrade ({cost} Ink)`
					else "MAX"}</font>`
				elseif spell then `<b>[{KEYS[slot]}] {spell.name}</b>\n<font size="11">{if action == "unlock"
						and cost
					then `Unlock ({cost} Ink)`
					else "Unlock prev page"}</font>`
				else `[{KEYS[slot]}]`
			local canAfford = cost ~= nil and totalInk >= cost
			local btn = Kit.button(
				row,
				btnTitle,
				UDim2.fromOffset(124, 66),
				UDim2.fromOffset(8 + (slot - 1) * 130, 30),
				if page and page.lv >= 5
					then Kit.GOLD
					elseif canAfford then Kit.GOOD
					elseif page then Kit.PANEL
					else Color3.fromRGB(32, 28, 38),
				function()
					NetClient.send("UpgradeSkill", index, slot)
				end
			)
			btn.TextSize = 12
		end
	end
end

-- Shelf ---------------------------------------------------------------------------------------

local function renderShelf()
	local data = StateController.get()
	if data == nil then
		return
	end
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

	Kit.label(
		body,
		"<b>Grimoires</b>: equip up to 3 (keys 1 2 3 swap active book & defensive element)",
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
		local row = Kit.frame(scroll, UDim2.new(1, -10, 0, 52), UDim2.new(), Kit.PANEL_LIGHT)
		row.LayoutOrder = index
		local slot = table.find(data.equipped, index)
		local clovers = Element.clovers(book.type)
		local rTier = Element.RARITY[book.type] or "Common"
		Kit.label(
			row,
			`<b>{clovers}-Leaf {book.type}</b> [{rTier}]  ·  {#book.pages}/4 skills{if slot
				then `  ·  Slot {slot}`
				else ""}`,
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
				UDim2.new(1, -190 + (s - 1) * 62, 0, 11),
				if slot == s then Kit.GOLD else Kit.PANEL,
				function()
					NetClient.send("EquipBook", s, index)
				end
			).TextSize =
				13
		end
	end
end

-- Bank ---------------------------------------------------------------------------------------

local function renderBank()
	local data = StateController.get()
	if data == nil then
		return
	end
	local gStats = Gears.stats(data.gears)
	local lines = {
		`Coins: <b>{data.bank.coins}</b> Banked Coins  (for buying Gears)`,
		`Universal Ink: <b>{Loot.totalInk(data.bank)}</b> Banked Ink  (for unlocking/upgrading Z/X/C/V skills)`,
		`Stars: <b>{data.stars}★</b> Stars  (for rolling Grimoires at the Desk)`,
		`PvP Bounty: <b>{data.bounty or 0}</b>`,
		`Backpack Capacity: <b>{Loot.weight(data.carried)} / {gStats.capacity}</b>`,
	}
	Kit.label(body, table.concat(lines, "\n"), UDim2.new(1, 0, 1, -40), UDim2.new(), 16).TextYAlignment =
		Enum.TextYAlignment.Top
	Kit.label(
		body,
		"Walk a 100% Full Backpack through the Camp Gate for a +15% Coin Bonus!",
		UDim2.new(1, 0, 0, 30),
		UDim2.new(0, 0, 1, -30),
		13,
		Kit.GOLD
	)
end

-- Shop (4 Visible Gear Categories + Universal Ink) ------------------------------------------

local function renderShop()
	local data = StateController.get()
	if data == nil then
		return
	end
	local gears = data.gears or { backpack = 1, robe = 0, hat = 0, boots = 0 }
	Kit.label(
		body,
		`You have <b>{data.bank.coins} Banked Coins</b> — Upgrade your 4 Visible Wizard Gears!`,
		UDim2.new(1, 0, 0, 22),
		UDim2.new(),
		15,
		Kit.GOLD
	).TextXAlignment =
		Enum.TextXAlignment.Left

	for i, category in Gears.CATEGORIES do
		local curTier = gears[category] or 0
		local curItem = Gears.get(category, curTier)
		local nextItem = Gears.nextTier(category, curTier)
		local row = Kit.frame(body, UDim2.new(1, 0, 0, 64), UDim2.fromOffset(0, 28 + (i - 1) * 70), Kit.PANEL_LIGHT)

		local title =
			`<b>{Gears.LABELS[category]}</b>: {if curItem then `{curItem.name} (Tier {curTier})` else "None equipped"}`
		local sub = if nextItem
			then `Next: <b>{nextItem.name}</b> — {nextItem.blurb}`
			else `MAX TIER: {if curItem then curItem.blurb else ""}`
		Kit.label(row, title, UDim2.new(1, -150, 0, 22), UDim2.fromOffset(10, 6), 15).TextXAlignment =
			Enum.TextXAlignment.Left
		Kit.label(row, sub, UDim2.new(1, -150, 0, 30), UDim2.fromOffset(10, 28), 12, Kit.MUTED).TextXAlignment =
			Enum.TextXAlignment.Left

		Kit.button(
			row,
			if nextItem then `Buy\n<b>{nextItem.price} Coins</b>` else "MAXED",
			UDim2.fromOffset(124, 46),
			UDim2.new(1, -134, 0, 9),
			if nextItem and data.bank.coins >= nextItem.price
				then Kit.GOOD
				elseif nextItem == nil then Kit.GOLD
				else Kit.PANEL,
			function()
				if nextItem then
					NetClient.send("BuyGear", category)
				end
			end
		).TextSize =
			13
	end

	local inkRow = Kit.frame(body, UDim2.new(1, 0, 0, 48), UDim2.fromOffset(0, 310), Kit.PANEL_LIGHT)
	Kit.label(
		inkRow,
		"<b>Universal Magic Ink</b>  (Unlocks & upgrades Z/X/C/V skills on any Grimoire)",
		UDim2.new(1, -150, 1, 0),
		UDim2.fromOffset(10, 0),
		14
	).TextXAlignment =
		Enum.TextXAlignment.Left
	Kit.button(
		inkRow,
		"Buy 1 Ink\n<b>40 Coins</b>",
		UDim2.fromOffset(124, 36),
		UDim2.new(1, -134, 0, 6),
		if data.bank.coins >= 40 then Kit.GOOD else Kit.PANEL,
		function()
			NetClient.send("Buy", "ink_Neutral")
		end
	).TextSize =
		12
end

-- Quest Giver Board (Black Clover Storyline Arcs) ------------------------------------------

local function renderQuestBoard()
	local data = StateController.get()
	if data == nil then
		return
	end
	local npc = Quests.NPCS[questArea] or Quests.NPCS.area1
	local list = Quests.forArea(questArea)
	local activeId = data.activeQuest and data.activeQuest.id or ""

	Kit.label(
		body,
		`<b>{npc.name}</b>  ·  {npc.arc}  (Your Level: {data.level})`,
		UDim2.new(1, 0, 0, 22),
		UDim2.new(),
		15,
		Kit.GOLD
	).TextXAlignment =
		Enum.TextXAlignment.Left

	for i, q in list do
		local row = Kit.frame(body, UDim2.new(1, 0, 0, 96), UDim2.fromOffset(0, 30 + (i - 1) * 104), Kit.PANEL_LIGHT)
		local unlocked = data.level >= q.minLevel
		local isActive = activeId == q.id
		Kit.label(
			row,
			`<b>{q.title}</b>  <font size="12">(Lv {q.minLevel}+)</font>  ·  {q.text}`,
			UDim2.new(1, -140, 0, 22),
			UDim2.fromOffset(10, 6),
			14,
			if unlocked then Kit.TEXT else Kit.MUTED
		).TextXAlignment =
			Enum.TextXAlignment.Left
		Kit.label(row, q.story, UDim2.new(1, -140, 0, 32), UDim2.fromOffset(10, 28), 12, Kit.MUTED).TextXAlignment =
			Enum.TextXAlignment.Left
		Kit.label(
			row,
			`Reward: <b>{q.reward.xp} XP</b> · <b>{q.reward.coins} Coins</b> · <b>+{q.reward.stars}★ Stars</b>{if q.reward.ink
				then ` · +{q.reward.ink} Ink`
				else ""}`,
			UDim2.new(1, -140, 0, 20),
			UDim2.fromOffset(10, 66),
			12,
			Kit.GOLD
		).TextXAlignment =
			Enum.TextXAlignment.Left
		Kit.button(
			row,
			if isActive then "ACTIVE" elseif unlocked then "Accept" else `Lv {q.minLevel}`,
			UDim2.fromOffset(114, 48),
			UDim2.new(1, -124, 0, 24),
			if isActive then Kit.GOLD elseif unlocked then Kit.GOOD else Kit.PANEL,
			function()
				if unlocked and not isActive then
					NetClient.send("AcceptQuest", q.id)
				end
			end
		).TextSize =
			14
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
	elseif name == "quest" then
		renderQuestBoard()
	end
end

local TITLES = {
	desk = { "Scriptorium Desk: Grimoire Gacha & Skills", Vector2.new(560, 500) },
	shelf = { "Grimoire Shelf & Wizard Stats", Vector2.new(540, 430) },
	bank = { "Camp Bank Vault", Vector2.new(440, 310) },
	shop = { "Wizard Gear & Ink Merchant", Vector2.new(520, 410) },
	quest = { "Magic Knight Quest Board", Vector2.new(540, 400) },
} :: { [string]: { any } }

function CampController.Init()
	gui = Kit.screen("Camp", 5)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local action = prompt:GetAttribute("Action")
		local title = type(action) == "string" and TITLES[action]
		if title then
			if action == "desk" then
				reveal = nil
			elseif action == "quest" then
				questArea = tostring(prompt:GetAttribute("AreaId") or "area1")
			end
			show(action :: string, title[1], title[2])
		end
	end)
	StateController.Changed:Connect(function()
		if open then
			render(open)
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
	while true do
		task.wait(0.5)
		local character = player.Character
		if open and open ~= "quest" and character then
			local pos = character:GetPivot().Position
			if Vector2.new(pos.X, pos.Z).Magnitude > Zones.CAMP_R + 10 then
				close()
			end
		end
	end
end

return CampController
