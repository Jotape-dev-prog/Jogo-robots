--!strict
-- Robôs: um cartão por Pad de Defesa com HP, peças equipadas (clique para remover) e modo de mira.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)

local Ui = require(script.Parent.Parent.Ui)
local State = require(script.Parent.Parent.State)
local Sound = require(script.Parent.Parent.SoundController)
local Common = require(script.Parent.Common)

local T = Ui.Theme

local Robots = {}

local list: ScrollingFrame

local function refresh()
	local data, horde = State.Data, State.Horde
	if not data then
		return
	end
	Ui.Clear(list)
	local unlocked = Common.UnlockedPads(data)

	local top = Ui.Frame(list, UDim2.new(1, -10, 0, 40), T.Background, 1)
	top.LayoutOrder = 0
	Ui.ListLayout(top, true, 8)
	Ui.Button(top, "Equipar melhores", T.Good, function()
		State.Call("EquipBest")
		Sound.Play("Equip")
	end, UDim2.fromOffset(170, 36))
	Ui.Label(
		top,
		"Clique numa peça para tirá-la. Equipe peças pelo Inventário.",
		UDim2.fromOffset(460, 22),
		{
			TextColor3 = T.TextDim,
		}
	)

	for i = 1, Economy.MaxPads do
		local pad = tostring(i)
		local card = Ui.Frame(list, UDim2.new(1, -10, 0, 96), T.Panel)
		card.LayoutOrder = i
		Ui.Corner(card, 10)
		Ui.Padding(card, 8)
		if i > unlocked then
			Ui.Label(
				card,
				`🔒 Pad {i} — libere em Upgrades`,
				UDim2.new(1, 0, 1, 0),
				{ TextColor3 = T.TextDim }
			)
			card.Size = UDim2.new(1, -10, 0, 44)
			continue
		end
		local padData = data.Pads[pad]
		local hp = horde and horde.Pads and horde.Pads[pad]
		local hpText = if hp then `HP {Ui.FormatNumber(hp.Hp)}/{Ui.FormatNumber(hp.MaxHp)}` else ""
		local broken = hp and hp.Hp <= 0
		Ui.Label(
			card,
			`<b>Pad {i}</b>  {hpText}{if broken
				then "  <font color='#ff6050'>QUEBRADO até a próxima horda</font>"
				else ""}`,
			UDim2.new(1, -170, 0, 22)
		)
		Ui.Button(card, `🎯 {Common.TargetingNames[padData.Targeting]}`, T.Info, function()
			State.Call("SetTargeting", pad, Common.TargetingCycle[padData.Targeting])
		end, UDim2.fromOffset(160, 26)).Position =
			UDim2.new(1, -160, 0, -2)

		local chips = Ui.Frame(card, UDim2.new(1, 0, 0, 48), T.Background, 1)
		chips.Position = UDim2.fromOffset(0, 28)
		Ui.ListLayout(chips, true, 6)
		for order, slot in Common.SlotOrder do
			local key = padData[slot]
			Common.SlotChip(chips, slot, key, function()
				if key ~= "" then
					State.Call("Equip", pad, slot, "")
				end
			end).LayoutOrder =
				order
		end
	end
end

function Robots.Create(): Ui.Window
	local window = Ui.Window("Robots", "🤖 Robôs de Defesa", Vector2.new(640, 520))
	list = Ui.Scroll(window.Body, UDim2.fromScale(1, 1), 8)
	window.OnOpen(refresh)
	State.OnChange(function()
		if window.IsOpen() then
			refresh()
		end
	end)
	return window
end

return Robots
