--!strict
-- Ponto de entrada do cliente: estado replicado, sons, telas e controles.

local State = require(script.State)
local Ui = require(script.Ui)
local SoundController = require(script.SoundController)
local Hud = require(script.Hud)
local CombatController = require(script.CombatController)

local Windows = script.Windows
local Roll = require(Windows.Roll)
local Inventory = require(Windows.Inventory)
local Robots = require(Windows.Robots)
local Factory = require(Windows.Factory)
local Upgrades = require(Windows.Upgrades)
local Defeat = require(Windows.Defeat)

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
}
Hud.Build(windows)

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

State.Start() -- por último: começa a receber os dados do servidor
