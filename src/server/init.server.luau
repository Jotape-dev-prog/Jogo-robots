--!strict
-- Ponto de entrada do servidor. A ordem importa:
-- serviços que reagem a "dados carregados" registram seus callbacks antes do DataService começar.

local Services = script.Services

local DataService = require(Services.DataService)
local RemoteGuard = require(Services.RemoteGuard)
local BaseService = require(Services.BaseService)
local HordeService = require(Services.HordeService)
local InventoryService = require(Services.InventoryService)

BaseService.Start() -- 1º: atribui a base ao jogador assim que os dados carregam
HordeService.Start() -- 2º: inicia a horda na base atribuída
InventoryService.Start()
RemoteGuard.Start() -- cria os RemoteFunctions já com os handlers registrados
DataService.Start() -- por último: começa a carregar perfis

print("[Server] Robôs vs. Zumbis iniciado")
