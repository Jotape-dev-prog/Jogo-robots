--!strict
-- Tutorial das primeiras hordas: um passo por vez, no canto direito.
-- Cada passo some sozinho quando o jogador faz o que ele pede (lido dos dados replicados),
-- então não precisa salvar nada. Some de vez a partir da horda 4 ou depois de um Rebirth.

local Ui = require(script.Parent.Ui)
local State = require(script.Parent.State)
local Sound = require(script.Parent.SoundController)

local T = Ui.Theme

type Step = { Text: string, Done: (data: any) -> boolean }

local STEPS: { Step } = {
	{
		Text = "🧟 Os zumbis saem da entrada da base e caçam seus robôs primeiro. Ajude: <b>clique</b> (ou <b>F</b>) para atacar.",
		Done = function(data)
			return data.Stats.Kills >= 3
		end,
	},
	{
		Text = "🎰 Use o dinheiro dos abates na <b>Roleta</b> para ganhar peças e armas.",
		Done = function(data)
			return data.Stats.Rolls >= 1
		end,
	},
	{
		Text = "🤖 Abra <b>Robôs</b> e toque em <b>Equipar melhores</b> — ou arraste robôs entre os hexágonos.",
		Done = function(data)
			local n = 0
			for _ in data.Grid do
				n += 1
			end
			return n >= 2
		end,
	},
	{
		Text = "🏭 Compre uma linha na <b>Fábrica</b>: ela rende dinheiro mesmo com as hordas pausadas.",
		Done = function(data)
			for _, line in data.Factory.Lines do
				if line.Unlocked then
					return true
				end
			end
			return false
		end,
	},
	{
		Text = "⚠ Robô quebrado <b>não volta</b> na horda seguinte — só depois de uma derrota. Proteja-os e chegue à horda 4!",
		Done = function(data)
			return data.Horde.Highest >= 4
		end,
	},
}

local TutorialController = {}

local panel: Frame
local label: TextLabel
local counter: TextLabel
local current = 0

local function refresh()
	local data = State.Data
	if not data then
		panel.Visible = false
		return
	end
	if data.Rebirths > 0 or data.Horde.Highest >= 4 then
		panel.Visible = false
		return
	end
	local index = 0
	for i, step in STEPS do
		if not step.Done(data) then
			index = i
			break
		end
	end
	if index == 0 then
		panel.Visible = false
		return
	end
	if current ~= 0 and index ~= current then
		Sound.Play("Cash") -- passo concluído
	end
	current = index
	panel.Visible = true
	counter.Text = `Tutorial {index}/{#STEPS}`
	label.Text = STEPS[index].Text
end

function TutorialController.Start()
	local gui = Ui.Screen()
	panel = Ui.Frame(gui, UDim2.fromOffset(300, 116), T.Background, 0.15)
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -12, 0.42, 0)
	panel.Visible = false
	Ui.Corner(panel, 12)
	Ui.Stroke(panel, T.Accent, 2)
	Ui.Padding(panel, 10)
	counter = Ui.Label(panel, "", UDim2.new(1, 0, 0, 18), { TextColor3 = T.Accent, Font = T.Font })
	label = Ui.Label(panel, "", UDim2.new(1, 0, 1, -22), {
		Position = UDim2.fromOffset(0, 22),
		TextWrapped = true,
		TextScaled = false,
		TextSize = 16,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	State.OnChange(refresh)
	refresh()
end

return TutorialController
