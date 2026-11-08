--!strict
-- Janela de troca. Abre sozinha quando uma troca começa e fecha quando termina.
--   Esquerda: seus itens livres (clique = +1 na oferta).
--   Centro: sua oferta (clique = -1).  Direita: a oferta do outro jogador.
--   Embaixo: Pronto → contagem de 5 s → Confirmar. Qualquer mudança desfaz o Pronto dos dois.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Config.Items)

local Ui = require(script.Parent.Parent.Ui)
local State = require(script.Parent.Parent.State)
local Sound = require(script.Parent.Parent.SoundController)
local Common = require(script.Parent.Common)

local T = Ui.Theme

local Trade = {}

local window: Ui.Window
local inventoryGrid: ScrollingFrame
local mineGrid: ScrollingFrame
local theirsGrid: ScrollingFrame
local theirsTitle: TextLabel
local status: TextLabel
local readyButton: TextButton
local confirmButton: TextButton
local wasTrading = false

local function sortedKeys(map: { [string]: number }): { string }
	local keys = {}
	for key, count in map do
		if count > 0 and Items.Parse(key) then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(a, b)
		local ta, tb = (Items.Parse(a) :: any).Tier, (Items.Parse(b) :: any).Tier
		if ta ~= tb then
			return ta > tb
		end
		return a < b
	end)
	return keys
end

local function itemButton(parent: Instance, key: string, count: number, onClick: (() -> ())?)
	local text = `{Items.DisplayName(key)}\n<b>x{count}</b>`
	local b = Ui.Button(parent, text, Common.TierColor(key), onClick or function() end)
	b.AutoButtonColor = onClick ~= nil
	return b
end

local function refresh()
	local social, data = State.Social, State.Data
	local trade = if social then social.Trade else nil
	if not trade or not data then
		return
	end
	theirsTitle.Text = `Oferta de <b>{trade.PartnerName}</b>`

	Ui.Clear(inventoryGrid)
	for i, key in sortedKeys(data.Inventory) do
		local free = (data.Inventory[key] or 0) - Common.EquippedCount(data, key) - (trade.Mine[key] or 0)
		if free > 0 then
			itemButton(inventoryGrid, key, free, function()
				State.Call("TradeSetItem", key, (trade.Mine[key] or 0) + 1)
			end).LayoutOrder =
				i
		end
	end
	Ui.Clear(mineGrid)
	for i, key in sortedKeys(trade.Mine) do
		itemButton(mineGrid, key, trade.Mine[key], function()
			State.Call("TradeSetItem", key, trade.Mine[key] - 1)
		end).LayoutOrder =
			i
	end
	Ui.Clear(theirsGrid)
	for i, key in sortedKeys(trade.Theirs) do
		itemButton(theirsGrid, key, trade.Theirs[key], nil).LayoutOrder = i
	end

	local both = trade.MyReady and trade.TheirReady
	if trade.MyConfirmed and not trade.TheirConfirmed then
		status.Text = "✅ Você confirmou. Esperando o outro jogador…"
	elseif trade.TheirConfirmed and not trade.MyConfirmed then
		status.Text = "O outro jogador confirmou — confira e confirme também."
	elseif both and trade.Countdown > 0 then
		status.Text = `Os dois estão prontos. Confira as ofertas: {trade.Countdown}s…`
	elseif both then
		status.Text = "Pode confirmar."
	else
		status.Text =
			`Você: {if trade.MyReady then "✅ pronto" else "montando"}   •   {trade.PartnerName}: {if trade.TheirReady
				then "✅ pronto"
				else "montando"}`
	end
	readyButton.Text = if trade.MyReady then "Desmarcar" else "Pronto"
	readyButton.BackgroundColor3 = if trade.MyReady then T.PanelLight else T.Good
	local canConfirm = both and trade.Countdown == 0 and not trade.MyConfirmed
	confirmButton.Active = canConfirm
	confirmButton.AutoButtonColor = canConfirm
	confirmButton.BackgroundColor3 = if canConfirm then T.Accent else T.PanelLight
end

local function column(parent: Instance, title: string, x: number, width: number): (TextLabel, ScrollingFrame)
	local label = Ui.Label(parent, title, UDim2.fromOffset(width, 24), {
		Position = UDim2.fromOffset(x, 0),
		Font = T.Font,
	})
	local grid = Ui.Grid(parent, UDim2.fromOffset(width, 300), UDim2.fromOffset(104, 52), 6)
	grid.Position = UDim2.fromOffset(x, 28)
	return label, grid
end

function Trade.Create(): Ui.Window
	window = Ui.Window("Trade", "🔄 Troca", Vector2.new(780, 470))
	local body = window.Body
	local _, inv = column(body, "Seus itens livres (clique para oferecer)", 0, 330)
	inventoryGrid = inv
	local _, mine = column(body, "Sua oferta", 342, 214)
	mineGrid = mine
	local title, theirs = column(body, "Oferta", 568, 214)
	theirsTitle = title
	theirsGrid = theirs

	status = Ui.Label(body, "", UDim2.new(1, 0, 0, 24), {
		Position = UDim2.new(0, 0, 1, -76),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local buttons = Ui.Frame(body, UDim2.new(1, 0, 0, 44), T.Background, 1)
	buttons.Position = UDim2.new(0, 0, 1, -46)
	local layout = Ui.ListLayout(buttons, true, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	readyButton = Ui.Button(buttons, "Pronto", T.Good, function()
		local trade = State.Social and State.Social.Trade
		if trade then
			State.Call("TradeReady", not trade.MyReady)
		end
	end, UDim2.fromOffset(170, 42))
	readyButton.LayoutOrder = 1
	confirmButton = Ui.Button(buttons, "Confirmar troca", T.PanelLight, function()
		if confirmButton.Active then
			State.Call("TradeConfirm")
		end
	end, UDim2.fromOffset(190, 42))
	confirmButton.LayoutOrder = 2
	Ui.Button(buttons, "Cancelar", T.Bad, function()
		State.Call("TradeCancel")
	end, UDim2.fromOffset(150, 42)).LayoutOrder =
		3

	State.OnChange(function()
		local social = State.Social
		local trading = social ~= nil and social.Trade ~= false and social.Trade ~= nil
		if trading and not wasTrading then
			window.Open()
			Sound.Play("Equip")
		elseif not trading and wasTrading then
			window.Close()
		end
		wasTrading = trading
		if trading then
			refresh()
		end
	end)
	window.OnOpen(refresh)
	return window
end

return Trade
