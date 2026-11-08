--!strict
-- Upgrades base (valor por abate, giros simultâneos, sorte, colunas do grid) e o Rebirth,
-- com confirmação mostrando exatamente o que se perde, o que fica e o que se ganha.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Grid = require(ReplicatedStorage.Shared.Config.Grid)
local Rarity = require(ReplicatedStorage.Shared.Config.Rarity)

local Ui = require(script.Parent.Parent.Ui)
local State = require(script.Parent.Parent.State)
local Sound = require(script.Parent.Parent.SoundController)

local T = Ui.Theme

local Upgrades = {}

local DEFS = {
	{
		Name = "KillValue",
		Title = "💀 Valor por abate",
		Effect = function(l: number)
			return `+{l * 10}% dinheiro por zumbi`
		end,
	},
	{
		Name = "Rolls",
		Title = "🎰 Giros simultâneos",
		Effect = function(l: number)
			return `{1 + l} giros por vez`
		end,
	},
	{
		Name = "Luck",
		Title = "🍀 Sorte",
		Effect = function(l: number)
			return string.format("sorte x%.1f", 1 + l * 0.1)
		end,
	},
	{
		Name = "Grid",
		Title = "🗺 Colunas do grid",
		Effect = function(l: number)
			local columns = Grid.Columns(l)
			return `{columns} colunas ({columns * #Grid.Rows} robôs)`
		end,
	},
}

local list: ScrollingFrame
local confirm: Frame

local function doRebirth()
	confirm.Visible = false
	local r = State.Call("Rebirth")
	if not r or not r.Ok then
		return
	end
	Sound.Play("Build")
	local best = 1
	for _, result in r.Results or {} do
		best = math.max(best, result.Tier)
	end
	local tier = Rarity.Get(best)
	Ui.Toast(
		`♻ Rebirth {r.Rebirths}! {#(r.Results or {})} giros grátis — melhor: <font color="{Ui.Hex(
			tier.Color
		)}">{tier.Name}</font>`,
		T.Good
	)
end

local function showConfirm()
	local data = State.Data
	if not data then
		return
	end
	Ui.Clear(confirm)
	local nextMult = Economy.CashMultiplier(data.Rebirths + 1)
	local rolls = Economy.RebirthBonusRolls(data.Rebirths)
	local lines = {
		`<b><font color="#ff8a5a">♻ Confirmar Rebirth {data.Rebirths + 1}?</font></b>`,
		`<font color="#ff6050"><b>Você perde:</b></font> todo o dinheiro, hordas e checkpoints (volta à horda 1), upgrades (inclusive colunas do grid) e a fábrica.`,
		`<font color="#9fb0c0"><b>Você mantém:</b></font> inventário, robôs das 2 primeiras colunas (os outros voltam ao inventário), arma do avatar.`,
		`<font color="#7fd08f"><b>Você ganha:</b></font> dinheiro x{string.format("%.1f", nextMult)} para sempre e {rolls} giros grátis com sorte x{Economy.Rebirth.BonusLuck}.`,
	}
	for i, text in lines do
		local label = Ui.Label(confirm, text, UDim2.new(1, 0, 0, if i == 1 then 30 else 44), {
			TextWrapped = true,
			TextScaled = false,
			TextSize = if i == 1 then 20 else 15,
		})
		label.LayoutOrder = i
	end
	local row = Ui.Frame(confirm, UDim2.new(1, 0, 0, 46), T.Background, 1)
	row.LayoutOrder = 10
	local layout = Ui.ListLayout(row, true, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	Ui.Button(row, "Fazer Rebirth", T.Accent, doRebirth, UDim2.fromOffset(200, 44)).LayoutOrder = 1
	Ui.Button(row, "Cancelar", T.PanelLight, function()
		confirm.Visible = false
	end, UDim2.fromOffset(160, 44)).LayoutOrder =
		2
	confirm.Visible = true
end

local function rebirthCard(data: any)
	local wave, cost = Economy.RebirthRequirement(data.Rebirths)
	local ready = data.Horde.Highest >= wave and data.Cash >= cost
	local card = Ui.Frame(list, UDim2.new(1, -10, 0, 84), Color3.fromRGB(60, 40, 30))
	card.LayoutOrder = 0
	Ui.Corner(card, 10)
	Ui.Stroke(card, T.Accent, 2)
	Ui.Padding(card, 10)
	Ui.Label(
		card,
		`<b>♻ Rebirth</b>  <font color="#aaa08f">feitos: {data.Rebirths} • dinheiro x{string.format(
			"%.1f",
			Economy.CashMultiplier(data.Rebirths)
		)}</font>`,
		UDim2.new(1, -190, 0, 24)
	)
	local waveOk = data.Horde.Highest >= wave
	local cashOk = data.Cash >= cost
	Ui.Label(
		card,
		`{if waveOk then "✅" else "❌"} Horda {wave}   {if cashOk then "✅" else "❌"} {Ui.FormatNumber(
			cost
		)} de dinheiro`,
		UDim2.new(1, -190, 0, 22),
		{ Position = UDim2.fromOffset(0, 28), TextColor3 = T.TextDim }
	)
	local button = Ui.Button(card, "Rebirth…", T.Accent, showConfirm, UDim2.fromOffset(170, 50), ready)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, 0, 0.5, 0)
end

local lastSignature = ""

-- Só o que aparece na tela: níveis, o que dá para comprar e o estado do Rebirth.
-- (O dinheiro muda a cada abate; reconstruir os botões toda hora fazia o clique se perder.)
local function signature(data: any): string
	local parts = { tostring(data.Rebirths) }
	local wave, cost = Economy.RebirthRequirement(data.Rebirths)
	table.insert(parts, tostring(data.Horde.Highest >= wave))
	table.insert(parts, tostring(data.Cash >= cost))
	for _, def in DEFS do
		local level = data.Upgrades[def.Name] or 0
		local upgradeCost = Economy.UpgradeCost(def.Name, level)
		table.insert(parts, `{level}:{upgradeCost ~= nil and data.Cash >= (upgradeCost or 0)}`)
	end
	return table.concat(parts, "|")
end

local function refresh(force: boolean?)
	local data = State.Data
	if not data then
		return
	end
	local sig = signature(data)
	if not force and sig == lastSignature then
		return
	end
	lastSignature = sig
	Ui.Clear(list)
	rebirthCard(data)
	for i, def in DEFS do
		local level = data.Upgrades[def.Name] or 0
		local max = (Economy.Upgrades :: any)[def.Name].Max
		local cost = Economy.UpgradeCost(def.Name, level)
		local card = Ui.Frame(list, UDim2.new(1, -10, 0, 70), T.Panel)
		card.LayoutOrder = i
		Ui.Corner(card, 10)
		Ui.Padding(card, 10)
		Ui.Label(
			card,
			`<b>{def.Title}</b>  <font color="#aaa08f">nível {level}/{max}</font>`,
			UDim2.new(1, -190, 0, 24)
		)
		local nextText = if cost
			then `{def.Effect(level)}  →  <font color="#7fd08f">{def.Effect(level + 1)}</font>`
			else def.Effect(level)
		Ui.Label(
			card,
			nextText,
			UDim2.new(1, -190, 0, 22),
			{ Position = UDim2.fromOffset(0, 26), TextColor3 = T.TextDim }
		)
		local button = Ui.Button(
			card,
			if cost then `Comprar\n{Ui.FormatNumber(cost)}` else "MÁXIMO",
			T.Purple,
			function()
				local r = State.Call("BuyUpgrade", def.Name)
				if r and r.Ok then
					Sound.Play("Build")
				end
			end,
			UDim2.fromOffset(170, 50),
			cost ~= nil and data.Cash >= (cost or 0)
		)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, 0, 0.5, 0)
	end
end

function Upgrades.Create(): Ui.Window
	local window = Ui.Window("Upgrades", "⬆ Upgrades e Rebirth", Vector2.new(620, 470))
	list = Ui.Scroll(window.Body, UDim2.fromScale(1, 1), 8)
	confirm = Ui.Frame(window.Body, UDim2.new(1, 0, 0, 270), T.Background, 0.02)
	confirm.AnchorPoint = Vector2.new(0.5, 0.5)
	confirm.Position = UDim2.fromScale(0.5, 0.5)
	confirm.ZIndex = 10
	confirm.Visible = false
	Ui.Corner(confirm, 12)
	Ui.Stroke(confirm, T.Accent, 3)
	Ui.Padding(confirm, 14)
	Ui.ListLayout(confirm, false, 6)
	window.OnOpen(function()
		confirm.Visible = false
		refresh(true)
	end)
	State.OnChange(function()
		if window.IsOpen() then
			refresh()
		end
	end)
	return window
end

return Upgrades
