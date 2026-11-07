--!strict
-- Fábrica: renda total, cada linha com andar/multiplicador, trabalhador (clique para tirar peça) e compra da próxima linha.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)

local Ui = require(script.Parent.Parent.Ui)
local State = require(script.Parent.Parent.State)
local Sound = require(script.Parent.Parent.SoundController)
local Common = require(script.Parent.Common)

local T = Ui.Theme

local Factory = {}

local list: ScrollingFrame

local function refresh()
	local data = State.Data
	if not data then
		return
	end
	Ui.Clear(list)
	local rebirthMult = 1 + data.Rebirths * 0.5
	local total = Economy.FactoryIncome(data.Factory.Lines) * rebirthMult

	local top = Ui.Frame(list, UDim2.new(1, -10, 0, 40), T.Background, 1)
	top.LayoutOrder = 0
	Ui.ListLayout(top, true, 10)
	Ui.Label(top, `Renda total: <b>+{Ui.FormatNumber(total)}/s</b>`, UDim2.fromOffset(250, 30), {
		TextColor3 = T.Good,
	})
	local nextId: string? = nil
	for _, id in Economy.FactoryLineIds() do
		if not data.Factory.Lines[id].Unlocked then
			nextId = id
			break
		end
	end
	if nextId then
		local cost = Economy.FactoryLineCost(nextId)
		Ui.Button(top, `Comprar linha {nextId} ({Ui.FormatNumber(cost)})`, T.Accent, function()
			local r = State.Call("BuyFactoryLine")
			if r and r.Ok then
				Sound.Play("Build")
				Ui.Toast(`Linha {r.Line} comprada!`, T.Good)
			end
		end, UDim2.fromOffset(260, 36), data.Cash >= cost)
	else
		Ui.Label(top, "Todas as linhas compradas ✔", UDim2.fromOffset(240, 30), { TextColor3 = T.TextDim })
	end

	for i, id in Economy.FactoryLineIds() do
		local line = data.Factory.Lines[id]
		local floor = tonumber(string.sub(id, 1, 1)) :: number
		local card = Ui.Frame(list, UDim2.new(1, -10, 0, if line.Unlocked then 92 else 40), T.Panel)
		card.LayoutOrder = i
		Ui.Corner(card, 10)
		Ui.Padding(card, 8)
		local mult = Economy.Factory.FloorMultiplier[floor]
		if not line.Unlocked then
			Ui.Label(
				card,
				`🔒 Linha {id} — andar {floor} (x{mult})`,
				UDim2.new(1, 0, 1, 0),
				{ TextColor3 = T.TextDim }
			)
			continue
		end
		local income = Economy.LineIncome(id, line) * rebirthMult
		Ui.Label(
			card,
			`<b>Linha {id}</b> • andar {floor} (x{mult}) • +{Ui.FormatNumber(income)}/s`,
			UDim2.new(1, 0, 0, 22)
		)
		local chips = Ui.Frame(card, UDim2.new(1, 0, 0, 48), T.Background, 1)
		chips.Position = UDim2.fromOffset(0, 26)
		Ui.ListLayout(chips, true, 6)
		for order, slot in { "Head", "Torso", "Arms", "Legs" } do
			local key = line[slot]
			Common.SlotChip(chips, slot, key, function()
				if key ~= "" then
					State.Call("EquipWorker", id, slot, "")
				end
			end).LayoutOrder =
				order
		end
	end
	Ui.Label(
		list,
		"Trabalhador: Torso = carga, Braços = montagem, Pernas = locomoção, Cabeça = navegação.",
		UDim2.new(1, -10, 0, 20),
		{
			TextColor3 = T.TextDim,
		}
	).LayoutOrder =
		99
end

function Factory.Create(): Ui.Window
	local window = Ui.Window("Factory", "🏭 Fábrica", Vector2.new(640, 540))
	list = Ui.Scroll(window.Body, UDim2.fromScale(1, 1), 8)
	window.OnOpen(refresh)
	State.OnChange(function()
		if window.IsOpen() then
			refresh()
		end
	end)
	return window
end

return Factory
