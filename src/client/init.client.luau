--!strict
-- Ponto de entrada do cliente: estado replicado, sons, telas e controles.

local State = require(script.State)
local Ui = require(script.Ui)
local SoundController = require(script.SoundController)
local Hud = require(script.Hud)
local CombatController = require(script.CombatController)
local GridController = require(script.GridController)
local PvpHud = require(script.PvpHud)
local TutorialController = require(script.TutorialController)
local MusicController = require(script.MusicController)
local FxController = require(script.FxController)
local AmbientController = require(script.AmbientController)
local AnimationController = require(script.AnimationController)
local RunController = require(script.RunController)

local Windows = script.Windows
local Roll = require(Windows.Roll)
local Inventory = require(Windows.Inventory)
local Robots = require(Windows.Robots)
local Factory = require(Windows.Factory)
local Upgrades = require(Windows.Upgrades)
local Defeat = require(Windows.Defeat)
local Social = require(Windows.Social)
local Trade = require(Windows.Trade)

State.SetErrorHandler(function(message)
	Ui.Toast(message, Ui.Theme.Bad)
end)

SoundController.Start()

local windows = {
	Roll = Roll.Create(),
	Inventory = Inventory.Create(),
	Robots = Robots.Create(),
	Factory = Factory.Create(),
	Upgrades = Upgrades.Create(),
	Social = Social.Create(),
}
local tradeWindow = Trade.Create()
Social.OpenTrade = tradeWindow.Open
Hud.Build(windows)
PvpHud.Build()
TutorialController.Start()
MusicController.Start()
FxController.Start()
AmbientController.Start()
AnimationController.Start()
RunController.Start()

-- Painéis da base (máquina da roleta, bancada da forja) abrem a janela correspondente.
game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt)
	local target = prompt:GetAttribute("OpensWindow")
	local window = if type(target) == "string" then (windows :: any)[target] else nil
	if window then
		window.Open()
	end
end)
Defeat.Create()
CombatController.Start()

-- Arrastar robôs no mundo 3D; clique simples abre o grid com o hexágono selecionado.
-- Com o estande aberto, clicar num hexágono do mundo seleciona ele na tela de montagem.
GridController.SetOnClickCell(function(cell)
	if windows.Robots.IsOpen() then
		Robots.Select(cell)
	else
		Ui.Toast(
			"🔧 Monte e edite robôs no Estande de Montagem (arrastar para mover funciona aqui)",
			Ui.Theme.TextDim
		)
	end
end)

-- A tela de montagem só fica aberta perto do estande.
task.spawn(function()
	local player = game:GetService("Players").LocalPlayer
	while true do
		task.wait(0.5)
		if windows.Robots.IsOpen() then
			local character = player.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
			local bases = workspace:FindFirstChild("Bases")
			local stand: BasePart? = nil
			for _, base in (if bases then bases:GetChildren() else {}) do
				if base:GetAttribute("OwnerUserId") == player.UserId then
					stand = base:FindFirstChild("AssemblyStand") :: BasePart?
				end
			end
			if root and stand and (root.Position - stand.Position).Magnitude > 26 then
				windows.Robots.Close()
			end
		end
	end
end)
GridController.Start()

State.Start() -- por último: começa a receber os dados do servidor
