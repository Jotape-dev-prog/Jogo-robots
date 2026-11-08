--!strict
-- Ciclo de PvP (King of the Hill) e trocas. Valores do GDD 2.5.

local Pvp = {}

Pvp.HordeSeconds = 20 * 60 -- hordas rodando entre uma janela de PvP e outra
Pvp.OpenSeconds = 10 * 60 -- centro aberto
Pvp.MinPlayers = 2 -- com menos jogadores o centro não abre (as hordas seguem)

Pvp.Center = Vector3.new(0, 0, 0)
Pvp.ArenaRadius = 70 -- quem está dentro deste raio está "na arena"
Pvp.ZoneRadius = 12 -- zona de captura
Pvp.CaptureSeconds = 30 -- tempo ininterrupto sozinho na zona

Pvp.WinBonus = 1.15 -- +15% dinheiro e sorte para quem captura
Pvp.WinBonusSeconds = 20 * 60 -- até a próxima janela de PvP
Pvp.DeathCashLossPercent = 0.05
Pvp.RespawnSeconds = 5
Pvp.DamageFactor = 1.6 -- dano no PvP = dano base × tier^0.75 × fator (HP do avatar escala igual)

Pvp.TradeMinWave = 20 -- trocas liberadas após a horda 20
Pvp.TradeMaxItemTypes = 12
Pvp.TradeCountdown = 5 -- segundos entre "Pronto" dos dois e poder confirmar
Pvp.RequestSeconds = 30 -- convites (aliança/troca) expiram

return Pvp
