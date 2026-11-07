--!strict
-- Estado do cliente: guarda as replicas (PlayerData e HordeState) e avisa as telas quando algo muda.
-- Também centraliza as chamadas ao servidor (State.Call) com aviso de erro.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ReplicaClient = require(ReplicatedStorage.ReplicaClient)
local Net = require(ReplicatedStorage.Shared.Net)

local State = {}

State.Data = nil :: any -- PlayerData (somente leitura)
State.Horde = nil :: any -- HordeState (somente leitura)

local listeners: { () -> () } = {}
local hordeEventListeners: { (path: { any }, value: any) -> () } = {}
local errorHandler: ((string) -> ())? = nil
local scheduled = false

-- Agrupa várias mudanças no mesmo frame numa única atualização das telas.
local function notify()
	if scheduled then
		return
	end
	scheduled = true
	task.defer(function()
		scheduled = false
		for _, listener in listeners do
			task.spawn(listener)
		end
	end)
end

function State.OnChange(listener: () -> ())
	table.insert(listeners, listener)
end

-- Mudanças pontuais da horda (para sons e avisos): recebe o caminho e o novo valor.
function State.OnHordeEvent(listener: (path: { any }, value: any) -> ())
	table.insert(hordeEventListeners, listener)
end

function State.SetErrorHandler(handler: (string) -> ())
	errorHandler = handler
end

-- Chama um remote; mostra o erro (exceto os silenciosos) e devolve o resultado.
function State.Call(name: string, ...: any): any
	local remote = Net.Function(name)
	local ok, result = pcall(remote.InvokeServer, remote, ...)
	if not ok or type(result) ~= "table" then
		if errorHandler then
			errorHandler("Falha de conexão")
		end
		return nil
	end
	if not result.Ok and not result.Silent and errorHandler then
		errorHandler(result.Error or "Erro")
	end
	return result
end

function State.Start()
	ReplicaClient.OnNew("PlayerData", function(replica)
		State.Data = replica.Data
		replica:OnChange(notify)
		notify()
	end)
	ReplicaClient.OnNew("HordeState", function(replica)
		State.Horde = replica.Data
		replica:OnChange(function(_, path, value)
			for _, listener in hordeEventListeners do
				task.spawn(listener, path, value)
			end
			notify()
		end)
		notify()
	end)
	ReplicaClient.RequestData()
end

return State
