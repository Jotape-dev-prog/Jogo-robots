--!strict
-- Tela de derrota e seletor de checkpoint. Aparece sozinha quando a base é invadida 3 vezes;
-- entre hordas pode ser aberta pelo botão "Checkpoints" para voltar a um checkpoint anterior.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HordeConfig = require(ReplicatedStorage.Shared.Config.Horde)

local Ui = require(script.Parent.Parent.Ui)
local State = require(script.Parent.Parent.State)

local T = Ui.Theme

local Defeat = {}

local overlay: Frame
local title: TextLabel
local subtitle: TextLabel
local buttons: Frame
local checkpointButton: TextButton
local manualOpen = false

local function checkpoints(highest: number): { number }
	local list = {}
	local wave = 1
	while wave <= highest do
		table.insert(list, wave)
		wave += HordeConfig.CheckpointEvery
	end
	return list
end

local function refresh()
	local data, horde = State.Data, State.Horde
	if not data or not horde then
		return
	end
	local defeated = horde.State == "Defeated"
	checkpointButton.Visible = (horde.State == "Intermission" or horde.State == "Paused")
		and data.Horde.HighestCheckpoint > 1
	overlay.Visible = defeated or (manualOpen and horde.State ~= "Active")
	if not overlay.Visible then
		manualOpen = false
		return
	end
	if defeated then
		title.Text = "💥 BASE INVADIDA!"
		title.TextColor3 = T.Bad
		subtitle.Text =
			`Você perdeu {Ui.FormatNumber(horde.LastLoss)} (10%). Recomeça do checkpoint {horde.Wave} em {horde.Timer}s — ou escolha outro:`
	else
		title.Text = "🚩 Checkpoints"
		title.TextColor3 = T.Accent
		subtitle.Text = "Volte para um checkpoint já desbloqueado:"
	end
	Ui.Clear(buttons)
	for i, wave in checkpoints(data.Horde.HighestCheckpoint) do
		Ui.Button(buttons, `Horda {wave}`, if wave == horde.Wave then T.Accent else T.Info, function()
			local r = State.Call("StartFromCheckpoint", wave)
			if r and r.Ok then
				manualOpen = false
				overlay.Visible = false
			end
		end, UDim2.fromOffset(110, 40)).LayoutOrder =
			i
	end
end

function Defeat.Create()
	local gui = Ui.Screen()
	overlay = Ui.Frame(gui, UDim2.fromOffset(560, 0), T.Background, 0.05)
	overlay.AutomaticSize = Enum.AutomaticSize.Y
	overlay.AnchorPoint = Vector2.new(0.5, 0.5)
	overlay.Position = UDim2.fromScale(0.5, 0.42)
	overlay.Visible = false
	overlay.ZIndex = 10
	Ui.Corner(overlay, 14)
	Ui.Stroke(overlay, T.Bad, 3)
	Ui.Padding(overlay, 14)
	Ui.ListLayout(overlay, false, 8)
	title = Ui.Label(
		overlay,
		"",
		UDim2.new(1, 0, 0, 40),
		{ Font = T.Font, TextXAlignment = Enum.TextXAlignment.Center }
	)
	subtitle = Ui.Label(overlay, "", UDim2.new(1, 0, 0, 48), {
		TextWrapped = true,
		TextColor3 = T.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	title.LayoutOrder = 1
	subtitle.LayoutOrder = 2
	buttons = Ui.Grid(overlay, UDim2.new(1, 0, 0, 92), UDim2.fromOffset(110, 40), 8)
	buttons.LayoutOrder = 5
	local close = Ui.Button(overlay, "Fechar", T.PanelLight, function()
		manualOpen = false
		overlay.Visible = false
	end, UDim2.fromOffset(110, 30))
	close.LayoutOrder = 10

	checkpointButton = Ui.Button(gui, "🚩 Checkpoints", T.Info, function()
		manualOpen = true
		refresh()
	end, UDim2.fromOffset(150, 36))
	checkpointButton.Position = UDim2.fromOffset(12, 196)
	checkpointButton.Visible = false

	State.OnChange(refresh)
end

return Defeat
