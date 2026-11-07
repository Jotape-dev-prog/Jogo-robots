--!strict
-- Inventário: grade de itens (peças / armas), detalhes do item selecionado,
-- forja 3 → 1, venda e "equipar em" (avatar, pads ou linhas da fábrica).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local Economy = require(Shared.Config.Economy)

local Ui = require(script.Parent.Parent.Ui)
local State = require(script.Parent.Parent.State)
local Sound = require(script.Parent.Parent.SoundController)
local Common = require(script.Parent.Common)

local T = Ui.Theme

local Inventory = {}

local tab: "Part" | "Weapon" = "Part"
local selected: string? = nil
local tabsRow: Frame
local grid: ScrollingFrame
local detail: Frame

local function sortedKeys(data: any): { string }
	local keys = {}
	for key, count in data.Inventory do
		local item = Items.Parse(key)
		if item and item.Kind == tab and count > 0 then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(a, b)
		local ia, ib = Items.Parse(a) :: Items.ParsedItem, Items.Parse(b) :: Items.ParsedItem
		if ia.Tier ~= ib.Tier then
			return ia.Tier > ib.Tier
		end
		return a < b
	end)
	return keys
end

local function equipTargets(data: any, key: string): { { Label: string, Call: () -> () } }
	local item = Items.Parse(key) :: Items.ParsedItem
	local targets = {}
	if item.Kind == "Weapon" then
		table.insert(targets, {
			Label = "Avatar",
			Call = function()
				State.Call("EquipAvatarWeapon", key)
			end,
		})
	end
	for i = 1, Common.UnlockedPads(data) do
		local pad = tostring(i)
		table.insert(targets, {
			Label = `Pad {i}`,
			Call = function()
				State.Call("Equip", pad, item.Slot, key)
			end,
		})
	end
	if item.Kind == "Part" then
		for _, lineId in Economy.FactoryLineIds() do
			if data.Factory.Lines[lineId].Unlocked then
				table.insert(targets, {
					Label = `Linha {lineId}`,
					Call = function()
						State.Call("EquipWorker", lineId, item.Slot, key)
					end,
				})
			end
		end
	end
	return targets
end

local function renderDetail(data: any)
	Ui.Clear(detail)
	local key = selected
	if not key or (data.Inventory[key] or 0) <= 0 then
		Ui.Label(detail, "Selecione um item", UDim2.new(1, 0, 0, 30), { TextColor3 = T.TextDim })
		return
	end
	local item = Items.Parse(key) :: Items.ParsedItem
	local tier = Rarity.Get(item.Tier)
	local total = data.Inventory[key]
	local free = total - Common.EquippedCount(data, key)

	Ui.Label(
		detail,
		Items.DisplayName(key),
		UDim2.new(1, 0, 0, 30),
		{ Font = T.Font, TextColor3 = tier.Color }
	).LayoutOrder =
		1
	Ui.Label(detail, `Total {total} • Livres {free} • Em uso {total - free}`, UDim2.new(1, 0, 0, 22), {
		TextColor3 = T.TextDim,
	}).LayoutOrder =
		2
	Ui.Label(detail, Common.StatsText(key), UDim2.new(1, 0, 0, 44), { TextWrapped = true }).LayoutOrder = 3

	local actions = Ui.Frame(detail, UDim2.new(1, 0, 0, 40), T.Background, 1)
	actions.LayoutOrder = 4
	Ui.ListLayout(actions, true, 6)
	local nextKey = Items.NextTierKey(key)
	Ui.Button(actions, "Fundir 3→1", T.Purple, function()
		local r = State.Call("Fuse", key)
		if r and r.Ok then
			Sound.Play("Fuse")
			selected = r.Result
			Ui.Toast(`Criou {Items.DisplayName(r.Result)}!`, Common.TierColor(r.Result))
		end
	end, UDim2.fromOffset(110, 38), free >= 3 and nextKey ~= nil).LayoutOrder =
		1
	Ui.Button(actions, `Vender ({Economy.SellValue(item.Tier)})`, T.Bad, function()
		local r = State.Call("Sell", key, 1)
		if r and r.Ok then
			Sound.Play("Cash")
		end
	end, UDim2.fromOffset(120, 38), free >= 1).LayoutOrder =
		2

	Ui.Label(detail, "Equipar em:", UDim2.new(1, 0, 0, 22), { TextColor3 = T.Accent }).LayoutOrder = 5
	local targetsArea = Ui.Grid(detail, UDim2.new(1, 0, 1, -200), UDim2.fromOffset(92, 34), 6)
	targetsArea.LayoutOrder = 6
	local canEquip = free >= 1
	for i, target in equipTargets(data, key) do
		Ui.Button(targetsArea, target.Label, T.Good, function()
			target.Call()
			Sound.Play("Equip")
		end, nil, canEquip).LayoutOrder =
			i
	end
	if not canEquip then
		Ui.Label(
			detail,
			"Sem cópias livres (todas em uso)",
			UDim2.new(1, 0, 0, 20),
			{ TextColor3 = T.TextDim }
		).LayoutOrder =
			7
	end
end

local function refresh()
	local data = State.Data
	if not data then
		return
	end
	Ui.Clear(tabsRow)
	for i, entry in { { "Part", "Peças" }, { "Weapon", "Armas" } } do
		Ui.Button(tabsRow, entry[2], if tab == entry[1] then T.Accent else T.PanelLight, function()
			tab = entry[1] :: any
			selected = nil
			refresh()
		end, UDim2.fromOffset(120, 34)).LayoutOrder =
			i
	end
	Ui.Button(tabsRow, "Equipar melhores", T.Good, function()
		State.Call("EquipBest")
		Sound.Play("Equip")
	end, UDim2.fromOffset(160, 34)).LayoutOrder =
		3

	Ui.Clear(grid)
	local keys = sortedKeys(data)
	if #keys == 0 then
		Ui.Label(grid, "Nada aqui ainda — gire a roleta!", nil, { TextColor3 = T.TextDim })
	end
	for i, key in keys do
		local count = data.Inventory[key]
		local free = count - Common.EquippedCount(data, key)
		local item = Items.Parse(key) :: Items.ParsedItem
		local label =
			`<font size="12">{Rarity.Get(item.Tier).Name}</font>\n{Common.SlotNames[item.Slot] or ""}{if item.Kind
					== "Weapon"
				then "\n" .. Items.Weapons[item.Type].Name
				else ""}\n<font size="13">x{count} ({free} livres)</font>`
		local tile = Ui.Button(grid, label, T.Panel, function()
			selected = key
			renderDetail(data)
		end)
		tile.LayoutOrder = i
		tile.TextColor3 = T.Text
		Ui.Stroke(tile, Rarity.Get(item.Tier).Color, if key == selected then 4 else 2)
	end
	renderDetail(data)
end

function Inventory.Create(): Ui.Window
	local window = Ui.Window("Inventory", "🎒 Inventário", Vector2.new(820, 500))
	local body = window.Body

	tabsRow = Ui.Frame(body, UDim2.new(1, 0, 0, 36), T.Background, 1)
	Ui.ListLayout(tabsRow, true, 8)

	grid = Ui.Grid(body, UDim2.new(1, -330, 1, -46), UDim2.fromOffset(112, 96), 8)
	grid.Position = UDim2.fromOffset(0, 46)

	detail = Ui.Frame(body, UDim2.new(0, 316, 1, -46), T.Panel)
	detail.Position = UDim2.new(1, -316, 0, 46)
	Ui.Corner(detail, 10)
	Ui.Padding(detail, 10)
	Ui.ListLayout(detail, false, 6)

	window.OnOpen(refresh)
	State.OnChange(function()
		if window.IsOpen() then
			refresh()
		end
	end)
	return window
end

return Inventory
