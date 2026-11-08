--!strict
-- Alianças e trocas entre jogadores do mesmo servidor.
--
-- Alianças (só valem nesta sessão do servidor):
--   convite → aceite; aliados não causam dano entre si no PvP. Na zona do King of the Hill
--   aliados também contestam (regra do GDD).
--
-- Trocas (liberadas quando os dois chegaram à horda 20):
--   convite → aceite → cada um monta sua oferta (só cópias livres, não equipadas)
--   → os dois marcam "Pronto" → contagem de 5 s → os dois confirmam → troca atômica.
--   Qualquer mudança na oferta desfaz o "Pronto" e a confirmação dos dois (anti-golpe).
--   Antes de executar, tudo é validado de novo; a troca acontece sem yield, nos dois perfis
--   ao mesmo tempo, e fica registrada no TradeLog de cada jogador.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Pvp = require(Shared.Config.Pvp)
local Replica = require(ServerScriptService.ReplicaServer)

local DataService = require(script.Parent.DataService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local SocialToken = Replica.Token("Social")

type Trade = {
	A: Player,
	B: Player,
	Offers: { [Player]: { [string]: number } },
	Ready: { [Player]: boolean },
	Confirmed: { [Player]: boolean },
	CountdownEnds: number, -- os.clock(); 0 = sem contagem
	Done: boolean,
}

local SocialService = {}

local replicas: { [Player]: any } = {}
local allies: { [Player]: { [Player]: boolean } } = {}
-- convites pendentes: [quem recebe][quem enviou] = expira em (os.clock)
local allyInvites: { [Player]: { [Player]: number } } = {}
local tradeInvites: { [Player]: { [Player]: number } } = {}
local trades: { [Player]: Trade } = {}

local function key(player: Player): string
	return tostring(player.UserId)
end

local function set(player: Player, path: { string }, value: any)
	local replica = replicas[player]
	if replica and replica:IsActive() then
		replica:Set(path, value)
	end
end

local function byUserId(userId: any): Player?
	if typeof(userId) ~= "number" then
		return nil
	end
	local player = Players:GetPlayerByUserId(userId)
	if player and replicas[player] then
		return player
	end
	return nil
end

-- Aviso pontual para o jogador (o cliente mostra como toast).
function SocialService.Notify(player: Player, text: string)
	set(player, { "Notice" }, { Text = text, At = os.clock() })
end

--------------------------------------------------------------------------------
-- Alianças
--------------------------------------------------------------------------------

function SocialService.IsAllied(a: Player, b: Player): boolean
	local list = allies[a]
	return list ~= nil and list[b] == true
end

local function syncAllies(player: Player)
	local names = {}
	for ally in allies[player] or {} do
		names[key(ally)] = ally.DisplayName
	end
	set(player, { "Allies" }, names)
end

local function syncInvites(player: Player)
	local now = os.clock()
	local ally, trade = {}, {}
	for from, expires in allyInvites[player] or {} do
		if expires > now and from.Parent == Players then
			ally[key(from)] = from.DisplayName
		end
	end
	for from, expires in tradeInvites[player] or {} do
		if expires > now and from.Parent == Players then
			trade[key(from)] = from.DisplayName
		end
	end
	set(player, { "AllyInvites" }, ally)
	set(player, { "TradeInvites" }, trade)
end

local function handleAllyRequest(player: Player, userId: any): RemoteGuard.Result
	local target = byUserId(userId)
	if not target or target == player then
		return RemoteGuard.Fail("Jogador não encontrado")
	end
	if SocialService.IsAllied(player, target) then
		return RemoteGuard.Fail("Vocês já são aliados")
	end
	-- Se o outro já tinha convidado, aceitar direto.
	local mine = allyInvites[player]
	if mine and mine[target] and mine[target] > os.clock() then
		return SocialService.AcceptAlly(player, target)
	end
	allyInvites[target] = allyInvites[target] or {};
	(allyInvites[target] :: any)[player] = os.clock() + Pvp.RequestSeconds
	syncInvites(target)
	return { Ok = true }
end

function SocialService.AcceptAlly(player: Player, from: Player): RemoteGuard.Result
	local pending = allyInvites[player]
	if not pending or not pending[from] or pending[from] < os.clock() then
		return RemoteGuard.Fail("Convite expirado")
	end
	pending[from] = nil
	allies[player] = allies[player] or {}
	allies[from] = allies[from] or {};
	(allies[player] :: any)[from] = true;
	(allies[from] :: any)[player] = true
	syncInvites(player)
	syncAllies(player)
	syncAllies(from)
	return { Ok = true }
end

local function handleAllyRespond(player: Player, userId: any, accept: any): RemoteGuard.Result
	local from = byUserId(userId)
	if not from or typeof(accept) ~= "boolean" then
		return RemoteGuard.Fail("Convite inválido")
	end
	if accept then
		return SocialService.AcceptAlly(player, from)
	end
	local pending = allyInvites[player]
	if pending then
		pending[from] = nil
	end
	syncInvites(player)
	return { Ok = true }
end

local function breakAlliance(a: Player, b: Player)
	if allies[a] then
		(allies[a] :: any)[b] = nil
	end
	if allies[b] then
		(allies[b] :: any)[a] = nil
	end
	syncAllies(a)
	syncAllies(b)
end

local function handleAllyLeave(player: Player, userId: any): RemoteGuard.Result
	local other = byUserId(userId)
	if not other or not SocialService.IsAllied(player, other) then
		return RemoteGuard.Fail("Vocês não são aliados")
	end
	breakAlliance(player, other)
	return { Ok = true }
end

--------------------------------------------------------------------------------
-- Trocas
--------------------------------------------------------------------------------

local function canTrade(player: Player): boolean
	local data = DataService.Get(player)
	return data ~= nil and data.Horde.Highest >= Pvp.TradeMinWave
end

-- Estado da troca como cada lado enxerga (Minha oferta / oferta do outro).
local function syncTrade(trade: Trade)
	for _, me in { trade.A, trade.B } do
		local other = if me == trade.A then trade.B else trade.A
		set(me, { "Trade" }, {
			PartnerId = other.UserId,
			PartnerName = other.DisplayName,
			Mine = table.clone(trade.Offers[me]),
			Theirs = table.clone(trade.Offers[other]),
			MyReady = trade.Ready[me] == true,
			TheirReady = trade.Ready[other] == true,
			MyConfirmed = trade.Confirmed[me] == true,
			TheirConfirmed = trade.Confirmed[other] == true,
			-- segundos que faltam para poder confirmar (servidor e cliente usam relógios diferentes)
			Countdown = if trade.CountdownEnds > 0
				then math.max(0, math.ceil(trade.CountdownEnds - os.clock()))
				else -1,
		})
	end
end

local function endTrade(trade: Trade, message: string?)
	trade.Done = true
	for _, p in { trade.A, trade.B } do
		if trades[p] == trade then
			trades[p] = nil
		end
		set(p, { "Trade" }, false)
		if message then
			set(p, { "Notice" }, { Text = message, At = os.clock() })
		end
	end
end

local function resetAgreement(trade: Trade)
	table.clear(trade.Ready)
	table.clear(trade.Confirmed)
	trade.CountdownEnds = 0
end

local function handleTradeRequest(player: Player, userId: any): RemoteGuard.Result
	local target = byUserId(userId)
	if not target or target == player then
		return RemoteGuard.Fail("Jogador não encontrado")
	end
	if not canTrade(player) then
		return RemoteGuard.Fail(`Trocas liberam na horda {Pvp.TradeMinWave}`)
	end
	if not canTrade(target) then
		return RemoteGuard.Fail(`{target.DisplayName} ainda não chegou à horda {Pvp.TradeMinWave}`)
	end
	if trades[player] or trades[target] then
		return RemoteGuard.Fail("Um de vocês já está em uma troca")
	end
	tradeInvites[target] = tradeInvites[target] or {};
	(tradeInvites[target] :: any)[player] = os.clock() + Pvp.RequestSeconds
	syncInvites(target)
	return { Ok = true }
end

local function handleTradeRespond(player: Player, userId: any, accept: any): RemoteGuard.Result
	local from = byUserId(userId)
	local pending = tradeInvites[player]
	if not from or typeof(accept) ~= "boolean" or not pending or not pending[from] then
		return RemoteGuard.Fail("Convite inválido")
	end
	local valid = pending[from] > os.clock()
	pending[from] = nil
	syncInvites(player)
	if not accept then
		return { Ok = true }
	end
	if not valid then
		return RemoteGuard.Fail("Convite expirado")
	end
	if trades[player] or trades[from] then
		return RemoteGuard.Fail("Um de vocês já está em uma troca")
	end
	if not canTrade(player) or not canTrade(from) then
		return RemoteGuard.Fail(`Trocas liberam na horda {Pvp.TradeMinWave}`)
	end
	local trade: Trade = {
		A = from,
		B = player,
		Offers = { [from] = {}, [player] = {} },
		Ready = {},
		Confirmed = {},
		CountdownEnds = 0,
		Done = false,
	}
	trades[from] = trade
	trades[player] = trade
	syncTrade(trade)
	return { Ok = true }
end

-- Define quantas cópias de um item entram na oferta (0 remove).
local function handleTradeSetItem(player: Player, itemKey: any, amount: any): RemoteGuard.Result
	local trade = trades[player]
	if not trade then
		return RemoteGuard.Fail("Você não está em uma troca")
	end
	if not Items.Parse(itemKey) or not RemoteGuard.IsInt(amount, 0, 1e6) then
		return RemoteGuard.Fail("Item inválido")
	end
	local offer = trade.Offers[player]
	if amount > DataService.AvailableCount(player, itemKey) then
		return RemoteGuard.Fail("Você não tem tantas cópias livres (itens equipados não entram)")
	end
	if amount > 0 and not offer[itemKey] then
		local types = 0
		for _ in offer do
			types += 1
		end
		if types >= Pvp.TradeMaxItemTypes then
			return RemoteGuard.Fail(`Máximo de {Pvp.TradeMaxItemTypes} tipos de item por troca`)
		end
	end
	offer[itemKey] = if amount > 0 then amount else nil
	resetAgreement(trade) -- mudou a oferta: os dois precisam conferir de novo
	syncTrade(trade)
	return { Ok = true }
end

local function handleTradeReady(player: Player, ready: any): RemoteGuard.Result
	local trade = trades[player]
	if not trade or typeof(ready) ~= "boolean" then
		return RemoteGuard.Fail("Você não está em uma troca")
	end
	trade.Ready[player] = ready or nil
	table.clear(trade.Confirmed)
	if trade.Ready[trade.A] and trade.Ready[trade.B] then
		trade.CountdownEnds = os.clock() + Pvp.TradeCountdown
	else
		trade.CountdownEnds = 0
	end
	syncTrade(trade)
	return { Ok = true }
end

-- Confere se cada jogador ainda tem as cópias livres que ofereceu.
local function offersStillValid(trade: Trade): boolean
	for _, p in { trade.A, trade.B } do
		if not DataService.Get(p) then
			return false
		end
		for itemKey, amount in trade.Offers[p] do
			if DataService.AvailableCount(p, itemKey) < amount then
				return false
			end
		end
	end
	return true
end

local function logTrade(player: Player, other: Player, gave: { [string]: number }, got: { [string]: number })
	local data = DataService.Get(player)
	if not data then
		return
	end
	local log = table.clone((data :: any).TradeLog or {})
	table.insert(log, { T = os.time(), With = other.UserId, Gave = gave, Got = got })
	while #log > 20 do
		table.remove(log, 1)
	end
	DataService.Set(player, { "TradeLog" }, log)
end

-- Execução atômica: nenhuma chamada abaixo faz yield, então ninguém altera os perfis no meio.
local function execute(trade: Trade)
	if not offersStillValid(trade) then
		endTrade(trade, "Troca cancelada: itens mudaram")
		return
	end
	local a, b = trade.A, trade.B
	local fromA, fromB = trade.Offers[a], trade.Offers[b]
	for itemKey, amount in fromA do
		DataService.RemoveItem(a, itemKey, amount)
		DataService.AddItem(b, itemKey, amount)
	end
	for itemKey, amount in fromB do
		DataService.RemoveItem(b, itemKey, amount)
		DataService.AddItem(a, itemKey, amount)
	end
	logTrade(a, b, fromA, fromB)
	logTrade(b, a, fromB, fromA)
	endTrade(trade, "✅ Troca concluída!")
end

local function handleTradeConfirm(player: Player): RemoteGuard.Result
	local trade = trades[player]
	if not trade then
		return RemoteGuard.Fail("Você não está em uma troca")
	end
	if not (trade.Ready[trade.A] and trade.Ready[trade.B]) then
		return RemoteGuard.Fail("Os dois precisam marcar Pronto")
	end
	if trade.CountdownEnds == 0 or os.clock() < trade.CountdownEnds then
		return RemoteGuard.Fail("Aguarde a contagem")
	end
	trade.Confirmed[player] = true
	if trade.Confirmed[trade.A] and trade.Confirmed[trade.B] then
		execute(trade)
	else
		syncTrade(trade)
	end
	return { Ok = true }
end

local function handleTradeCancel(player: Player): RemoteGuard.Result
	local trade = trades[player]
	if trade then
		endTrade(trade, `Troca cancelada por {player.DisplayName}`)
	end
	return { Ok = true }
end

--------------------------------------------------------------------------------
-- Ciclo de vida
--------------------------------------------------------------------------------

local function begin(player: Player)
	local replica = Replica.New({
		Token = SocialToken,
		Tags = { UserId = player.UserId },
		Data = {
			Allies = {}, -- [userId] = nome
			AllyInvites = {},
			TradeInvites = {},
			Trade = false, -- tabela quando há troca em andamento
			Notice = false, -- aviso pontual { Text, At } (troca concluída, perda no PvP...)
		},
	})
	replicas[player] = replica
	if Replica.ReadyPlayers[player] then
		replica:Subscribe(player)
	else
		local connection
		connection = Replica.NewReadyPlayer:Connect(function(ready)
			if ready == player then
				connection:Disconnect()
				if replica:IsActive() then
					replica:Subscribe(player)
				end
			end
		end)
	end
end

local function finish(player: Player)
	local trade = trades[player]
	if trade then
		endTrade(trade, `{player.DisplayName} saiu do jogo — troca cancelada`)
	end
	for other in allies[player] or {} do
		breakAlliance(player, other)
	end
	allies[player] = nil
	allyInvites[player] = nil
	tradeInvites[player] = nil
	for _, list in { allyInvites, tradeInvites } do
		for target, pending in list do
			if pending[player] then
				pending[player] = nil
				syncInvites(target)
			end
		end
	end
	local replica = replicas[player]
	replicas[player] = nil
	if replica then
		replica:Destroy()
	end
end

function SocialService.Start()
	RemoteGuard.Handle("AllyRequest", 5, 0.5, handleAllyRequest)
	RemoteGuard.Handle("AllyRespond", 5, 1, handleAllyRespond)
	RemoteGuard.Handle("AllyLeave", 5, 0.5, handleAllyLeave)
	RemoteGuard.Handle("TradeRequest", 5, 0.5, handleTradeRequest)
	RemoteGuard.Handle("TradeRespond", 5, 1, handleTradeRespond)
	RemoteGuard.Handle("TradeSetItem", 20, 6, handleTradeSetItem)
	RemoteGuard.Handle("TradeReady", 10, 3, handleTradeReady)
	RemoteGuard.Handle("TradeConfirm", 10, 3, handleTradeConfirm)
	RemoteGuard.Handle("TradeCancel", 5, 2, handleTradeCancel)

	DataService.OnLoaded(begin)
	DataService.OnReleasing(finish)

	-- Atualiza a contagem das trocas e limpa convites vencidos.
	task.spawn(function()
		while true do
			task.wait(0.5)
			local seen: { [Trade]: boolean } = {}
			for _, trade in trades do
				if not seen[trade] and not trade.Done and trade.CountdownEnds > 0 then
					seen[trade] = true
					syncTrade(trade)
				end
			end
			local now = os.clock()
			for _, list in { allyInvites, tradeInvites } do
				for target, pending in list do
					local changed = false
					for from, expires in pending do
						if expires < now then
							pending[from] = nil
							changed = true
						end
					end
					if changed then
						syncInvites(target)
					end
				end
			end
		end
	end)
end

return SocialService
