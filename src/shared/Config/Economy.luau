--!strict
-- Valores de economia. Todos os números de balanceamento ficam aqui para a planilha de balanceamento.

local Rarity = require(script.Parent.Rarity)

local Economy = {}

Economy.StartingCash = 250
Economy.RollCost = 100 -- custo por giro da roleta
Economy.MaxSimultaneousRolls = 5
Economy.SellBaseValue = 20 -- valor de venda no tier 1 (× multiplicador do tier)

Economy.StartPads = 2 -- pads de defesa liberados no início
Economy.MaxPads = 6

Economy.DefeatCashLossPercent = 0.10 -- perda ao sofrer 3 invasões
Economy.PvpDeathCashLossPercent = 0.05

-- Upgrades base: custo = Base × Growth^nível
Economy.Upgrades = {
	KillValue = { Base = 300, Growth = 1.6, Max = 50, PerLevel = 0.10 }, -- +10% valor por abate
	Rolls = { Base = 1500, Growth = 4, Max = 4, PerLevel = 1 }, -- +1 giro simultâneo (1 → 5)
	Luck = { Base = 1000, Growth = 1.8, Max = 30, PerLevel = 0.10 }, -- +10% sorte
	Pads = { Base = 800, Growth = 2.5, Max = 4, PerLevel = 1 }, -- +1 pad (2 → 6)
}

Economy.RebirthCashMultiplier = 0.5 -- +50% moeda por rebirth

function Economy.SellValue(tier: number): number
	return math.floor(Economy.SellBaseValue * Rarity.Multiplier(tier))
end

function Economy.UpgradeCost(name: string, level: number): number?
	local def = (Economy.Upgrades :: any)[name]
	if not def or level >= def.Max then
		return nil
	end
	return math.floor(def.Base * def.Growth ^ level)
end

return Economy
