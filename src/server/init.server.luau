--!strict
-- Ponto de entrada do servidor. A ordem importa:
-- serviços que reagem a "dados carregados" registram seus callbacks antes do DataService começar.

local Services = script.Services

local DataService = require(Services.DataService)
local RemoteGuard = require(Services.RemoteGuard)
local BaseService = require(Services.BaseService)
local HordeService = require(Services.HordeService)
local InventoryService = require(Services.InventoryService)
local AvatarService = require(Services.AvatarService)
local FactoryService = require(Services.FactoryService)

BaseService.Start() -- 1º: atribui a base ao jogador assim que os dados carregam
HordeService.Start() -- 2º: inicia a horda na base atribuída
FactoryService.Start() -- 3º: monta a fábrica na base atribuída
AvatarService.Start()
InventoryService.Start()
-- Comando de QA: só existe no Studio. Em servidores reais o remote responde "Indisponível".
if game:GetService("RunService"):IsStudio() then
	RemoteGuard.Handle("DevGiveCash", 5, 1, function(player, amount)
		if not RemoteGuard.IsInt(amount, 1, 1e9) then
			return RemoteGuard.Fail("Quantidade inválida")
		end
		DataService.AddCash(player, amount, false)
		return { Ok = true }
	end)
end

RemoteGuard.Start() -- cria os RemoteFunctions já com os handlers registrados
DataService.Start() -- por último: começa a carregar perfis

print("[Server] Robôs vs. Zumbis iniciado")
