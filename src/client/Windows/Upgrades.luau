--!strict
-- Upgrades base: valor por abate, giros simultâneos, sorte e pads de defesa.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)

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
		Name = "Pads",
		Title = "🛡 Pads de defesa",
		Effect = function(l: number)
			return `{Economy.StartPads + l} pads`
		end,
	},
}

local list: ScrollingFrame

local function refresh()
	local data = State.Data
	if not data then
		return
	end
	Ui.Clear(list)
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
	local window = Ui.Window("Upgrades", "⬆ Upgrades", Vector2.new(620, 380))
	list = Ui.Scroll(window.Body, UDim2.fromScale(1, 1), 8)
	window.OnOpen(refresh)
	State.OnChange(function()
		if window.IsOpen() then
			refresh()
		end
	end)
	return window
end

return Upgrades
