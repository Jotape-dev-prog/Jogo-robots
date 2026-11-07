--!strict
-- Camada única de entrada do cliente. Cada RemoteFunction passa por:
--   1. dados do jogador carregados
--   2. rate limit por jogador e por remote
--   3. pcall (um erro no handler não derruba nada e não vaza detalhes)
-- Os handlers validam os argumentos com os helpers Is* abaixo — nunca confie no cliente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local DataService = require(script.Parent.DataService)

export type Result = { Ok: boolean, Error: string?, [string]: any }
type Handler = (player: Player, ...any) -> Result

type RateState = { Tokens: number, Last: number }

local RemoteGuard = {}

local handlers: { [string]: Handler } = {}
local limits: { [string]: { Max: number, PerSecond: number } } = {}
local rateStates: { [Player]: { [string]: RateState } } = {}

local function allow(player: Player, name: string): boolean
	local limit = limits[name]
	local perPlayer = rateStates[player]
	if not perPlayer then
		perPlayer = {}
		rateStates[player] = perPlayer
	end
	local now = os.clock()
	local state = perPlayer[name]
	if not state then
		state = { Tokens = limit.Max, Last = now }
		perPlayer[name] = state
	end
	state.Tokens = math.min(limit.Max, state.Tokens + (now - state.Last) * limit.PerSecond)
	state.Last = now
	if state.Tokens < 1 then
		return false
	end
	state.Tokens -= 1
	return true
end

-- Registra o handler de um remote. maxBurst/perSecond = token bucket.
function RemoteGuard.Handle(name: string, maxBurst: number, perSecond: number, handler: Handler)
	assert(table.find(Net.Functions, name), `Remote não declarado em Net.Functions: {name}`)
	handlers[name] = handler
	limits[name] = { Max = maxBurst, PerSecond = perSecond }
end

function RemoteGuard.Start()
	local folder = Net.Folder()
	for _, name in Net.Functions do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.OnServerInvoke = function(player: Player, ...): Result
			local handler = handlers[name]
			if not handler then
				return { Ok = false, Error = "Indisponível" }
			end
			if not DataService.IsLoaded(player) then
				return { Ok = false, Error = "Carregando dados" }
			end
			if not allow(player, name) then
				return { Ok = false, Error = "Muitas tentativas, aguarde" }
			end
			local ok, result = pcall(handler, player, ...)
			if not ok then
				warn(`[RemoteGuard] {name} falhou para {player.UserId}: {result}`)
				return { Ok = false, Error = "Erro interno" }
			end
			return result
		end
		remote.Parent = folder
	end
	Players.PlayerRemoving:Connect(function(player)
		rateStates[player] = nil
	end)
end

--------------------------------------------------------------------------------
-- Validação
--------------------------------------------------------------------------------

function RemoteGuard.IsInt(value: any, min: number, max: number): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= min and value <= max
end

function RemoteGuard.IsString(value: any, maxLength: number): boolean
	return type(value) == "string" and #value <= maxLength
end

function RemoteGuard.IsOneOf(value: any, options: { any }): boolean
	return table.find(options, value) ~= nil
end

function RemoteGuard.Fail(message: string): Result
	return { Ok = false, Error = message }
end

return RemoteGuard
