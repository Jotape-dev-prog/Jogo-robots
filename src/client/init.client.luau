--!strict
-- Ponto de entrada do cliente: recebe os dados replicados e monta o HUD provisório.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ReplicaClient = require(ReplicatedStorage.ReplicaClient)
local Hud = require(script.Hud)
local CombatController = require(script.CombatController)

ReplicaClient.OnNew("PlayerData", function(replica)
	Hud.BindPlayerData(replica)
end)

ReplicaClient.OnNew("HordeState", function(replica)
	Hud.BindHordeState(replica)
end)

Hud.Build()
CombatController.Start()
ReplicaClient.RequestData() -- avisa o servidor que o cliente está pronto para receber replicas
