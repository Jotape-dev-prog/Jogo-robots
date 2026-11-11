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
GridController.SetOnClickCell(function(cell)
	Robots.Select(cell)
	windows.Robots.Open()
	Robots.Select(cell)
end)
GridController.Start()

State.Start() -- por último: começa a receber os dados do servidor
