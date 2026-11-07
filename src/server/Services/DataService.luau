--!strict
-- Carrega/salva os dados do jogador com ProfileStore (session lock contra dupe) e
-- replica para o próprio jogador com Replica. Toda escrita em dados salvos passa por aqui,
-- para que o perfil e o cliente nunca fiquem dessincronizados.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ProfileStore)
local Replica = require(ServerScriptService.ReplicaServer)
local Template = require(script.Parent.Parent.Data.Template)

type PlayerData = Template.PlayerData

local STORE_NAME = "PlayerData_v1"
-- No Studio os testes gravam num DataStore separado, para nunca tocar nos dados reais dos jogadores.
-- Sem "Enable Studio Access to API Services", o ProfileStore usa um DataStore simulado sozinho.
local storeName = if RunService:IsStudio() then STORE_NAME .. "_Studio" else STORE_NAME
local store = ProfileStore.New(storeName, Template)

local PlayerDataToken = Replica.Token("PlayerData")

local profiles: { [Player]: any } = {}
local replicas: { [Player]: any } = {}
local loadedCallbacks: { (Player) -> () } = {}
local releasingCallbacks: { (Player) -> () } = {}

local DataService = {}

--------------------------------------------------------------------------------
-- Migrações de versão
--------------------------------------------------------------------------------

local CURRENT_VERSION = Template.DataVersion

local function migrate(data: PlayerData)
	-- Exemplo para o futuro:
	-- if data.DataVersion < 2 then ... data.DataVersion = 2 end
	data.DataVersion = CURRENT_VERSION
end

--------------------------------------------------------------------------------
-- Ciclo de vida
--------------------------------------------------------------------------------

local function subscribeWhenReady(player: Player, replica: any)
	if Replica.ReadyPlayers[player] then
		replica:Subscribe(player)
		return
	end
	local connection
	connection = Replica.NewReadyPlayer:Connect(function(readyPlayer: Player)
		if readyPlayer == player then
			connection:Disconnect()
			if replica:IsActive() then
				replica:Subscribe(player)
			end
		end
	end)
end

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		player:Kick("Não foi possível carregar seus dados. Tente entrar novamente.")
		return
	end

	profile:AddUserId(player.UserId) -- GDPR
	profile:Reconcile()
	migrate(profile.Data)

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		local replica = replicas[player]
		replicas[player] = nil
		if replica then
			replica:Destroy()
		end
		player:Kick("Sua sessão foi encerrada (você entrou em outro servidor?).")
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	local replica = Replica.New({
		Token = PlayerDataToken,
		Tags = { UserId = player.UserId },
		Data = profile.Data,
	})

	profiles[player] = profile
	replicas[player] = replica
	subscribeWhenReady(player, replica)

	for _, callback in loadedCallbacks do
		task.spawn(callback, player)
	end
end

local function onPlayerRemoving(player: Player)
	for _, callback in releasingCallbacks do
		local ok, err = pcall(callback, player)
		if not ok then
			warn("[DataService] erro ao liberar jogador:", err)
		end
	end
	local profile = profiles[player]
	if profile then
		profile:EndSession()
	end
end

function DataService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

-- Chamado quando os dados do jogador estão prontos (inclui jogadores já carregados).
function DataService.OnLoaded(callback: (Player) -> ())
	table.insert(loadedCallbacks, callback)
	for player in profiles do
		task.spawn(callback, player)
	end
end

-- Chamado antes de o perfil ser salvo e liberado (jogador saindo).
function DataService.OnReleasing(callback: (Player) -> ())
	table.insert(releasingCallbacks, callback)
end

--------------------------------------------------------------------------------
-- Leitura
--------------------------------------------------------------------------------

function DataService.IsLoaded(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile:IsActive()
end

-- Retorna os dados para LEITURA. Para escrever, use as funções abaixo.
function DataService.Get(player: Player): PlayerData?
	local profile = profiles[player]
	if profile and profile:IsActive() then
		return profile.Data
	end
	return nil
end

function DataService.GetProfile(player: Player): any
	return profiles[player]
end

--------------------------------------------------------------------------------
-- Escrita (sempre via Replica → atualiza o perfil e o cliente juntos)
--------------------------------------------------------------------------------

function DataService.Set(player: Player, path: { string }, value: any): boolean
	local replica = replicas[player]
	if not replica or not DataService.IsLoaded(player) then
		return false
	end
	replica:Set(path, value)
	return true
end

function DataService.Increment(player: Player, path: { string }, delta: number): boolean
	local data = DataService.Get(player)
	if not data then
		return false
	end
	local pointer: any = data
	for i = 1, #path - 1 do
		pointer = pointer[path[i]]
	end
	local current = pointer[path[#path]] or 0
	return DataService.Set(player, path, current + delta)
end

local function cashMultiplier(data: PlayerData): number
	return 1 + data.Rebirths * 0.5
end

-- Adiciona dinheiro. applyMultipliers aplica rebirth (use em recompensas, não em reembolsos).
function DataService.AddCash(player: Player, amount: number, applyMultipliers: boolean?): number
	local data = DataService.Get(player)
	if not data or amount <= 0 then
		return 0
	end
	local final = if applyMultipliers then math.floor(amount * cashMultiplier(data)) else math.floor(amount)
	DataService.Set(player, { "Cash" }, data.Cash + final)
	DataService.Set(player, { "TotalEarned" }, data.TotalEarned + final)
	return final
end

function DataService.SpendCash(player: Player, amount: number): boolean
	local data = DataService.Get(player)
	if not data or amount < 0 or data.Cash < amount then
		return false
	end
	return DataService.Set(player, { "Cash" }, data.Cash - amount)
end

-- Remove uma porcentagem do dinheiro atual (derrota, morte no PvP). Retorna o valor perdido.
function DataService.LosePercent(player: Player, percent: number): number
	local data = DataService.Get(player)
	if not data then
		return 0
	end
	local loss = math.floor(data.Cash * percent)
	DataService.Set(player, { "Cash" }, data.Cash - loss)
	return loss
end

--------------------------------------------------------------------------------
-- Inventário
--------------------------------------------------------------------------------

function DataService.ItemCount(player: Player, key: string): number
	local data = DataService.Get(player)
	return if data then data.Inventory[key] or 0 else 0
end

-- Quantas cópias do item estão em uso (pads, avatar e trabalhadores da fábrica).
function DataService.EquippedCount(player: Player, key: string): number
	local data = DataService.Get(player)
	if not data then
		return 0
	end
	local count = if data.AvatarWeapon == key then 1 else 0
	for _, pad in data.Pads do
		for _, slotKey in pad :: any do
			if slotKey == key then
				count += 1
			end
		end
	end
	for _, worker in data.Factory.Lines do
		for _, slotKey in worker :: any do
			if slotKey == key then
				count += 1
			end
		end
	end
	return count
end

-- Cópias livres (não equipadas).
function DataService.AvailableCount(player: Player, key: string): number
	return DataService.ItemCount(player, key) - DataService.EquippedCount(player, key)
end

function DataService.AddItem(player: Player, key: string, amount: number): boolean
	if amount <= 0 then
		return false
	end
	return DataService.Set(player, { "Inventory", key }, DataService.ItemCount(player, key) + amount)
end

-- Remove apenas cópias livres. Nunca remove itens equipados.
function DataService.RemoveItem(player: Player, key: string, amount: number): boolean
	if amount <= 0 or DataService.AvailableCount(player, key) < amount then
		return false
	end
	local remaining = DataService.ItemCount(player, key) - amount
	return DataService.Set(player, { "Inventory", key }, if remaining > 0 then remaining else nil)
end

return DataService
