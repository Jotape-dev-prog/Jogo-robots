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
local RebirthService = require(Services.RebirthService)
local SocialService = require(Services.SocialService)
local PvpService = require(Services.PvpService)
local WorldService = require(Services.WorldService)
local MapService = require(Services.MapService)

BaseService.Start() -- 1º: atribui a base ao jogador assim que os dados carregam
MapService.Start() -- caminhos de cada base até a arena (depende das bases)
HordeService.Start() -- 2º: inicia a horda na base atribuída
FactoryService.Start() -- 3º: monta a fábrica na base atribuída
AvatarService.Start()
InventoryService.Start()
RebirthService.Start()
SocialService.Start()
PvpService.Start()
WorldService.Start()
-- Comando de QA: só existe no Studio. Em servidores reais o remote responde "Indisponível".
if game:GetService("RunService"):IsStudio() then
	RemoteGuard.Handle("DevGiveCash", 5, 1, function(player, amount)
		if not RemoteGuard.IsInt(amount, 1, 1e9) then
			return RemoteGuard.Fail("Quantidade inválida")
		end
		DataService.AddCash(player, amount, false)
		return { Ok = true }
	end)
	RemoteGuard.Handle("DevSetHighestWave", 5, 1, function(player, wave)
		if not RemoteGuard.IsInt(wave, 1, 1000) then
			return RemoteGuard.Fail("Horda inválida")
		end
		DataService.Set(player, { "Horde", "Highest" }, wave)
		return { Ok = true }
	end)
end

RemoteGuard.Start() -- cria os RemoteFunctions já com os handlers registrados
require(script.Fx).Start() -- RemoteEvent dos efeitos visuais de combate
DataService.Start() -- por último: começa a carregar perfis

print("[Server] Robôs vs. Zumbis iniciado")
