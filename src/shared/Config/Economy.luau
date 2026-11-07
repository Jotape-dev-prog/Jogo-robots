--!strict
-- Valores de economia. Todos os números de balanceamento ficam aqui para a planilha de balanceamento.

local Rarity = require(script.Parent.Rarity)
local Items = require(script.Parent.Items)

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

-- Fábrica: 3 andares × 2 linhas. Linhas são compradas em ordem; andares altos multiplicam a renda.
Economy.Factory = {
	Floors = 3,
	LinesPerFloor = 2,
	LineBaseCost = 500,
	LineCostGrowth = 4, -- linha n custa Base × Growth^(n-1)
	FloorMultiplier = { 1, 3, 9 },
	BaseIncomePerSecond = 2, -- linha sem trabalhador
	-- peso de cada peça do trabalhador: renda × Multiplier(tier)^peso
	WorkerWeights = {
		Torso = 0.5, -- capacidade de carga
		Arms = 0.35, -- velocidade de montagem
		Legs = 0.25, -- velocidade de locomoção
		Head = 0.15, -- eficiência de navegação
	},
}

function Economy.FactoryLineIds(): { string }
	local ids = {}
	for floor = 1, Economy.Factory.Floors do
		for line = 1, Economy.Factory.LinesPerFloor do
			table.insert(ids, `{floor}-{line}`)
		end
	end
	return ids
end

function Economy.FactoryLineCost(lineId: string): number
	local ids = Economy.FactoryLineIds()
	local index = table.find(ids, lineId) or 1
	return math.floor(Economy.Factory.LineBaseCost * Economy.Factory.LineCostGrowth ^ (index - 1))
end

-- Renda por segundo de uma linha (sem rebirth). worker = { Head, Torso, Arms, Legs } com chaves de peças.
function Economy.LineIncome(lineId: string, worker: { [string]: any }): number
	if not worker.Unlocked then
		return 0
	end
	local floor = tonumber(string.match(lineId, "^(%d+)")) or 1
	local income = Economy.Factory.BaseIncomePerSecond * (Economy.Factory.FloorMultiplier[floor] or 1)
	for slot, weight in Economy.Factory.WorkerWeights do
		local item = Items.Parse(worker[slot])
		if item and item.Slot == slot then
			income *= Rarity.Multiplier(item.Tier) ^ weight
		end
	end
	return income
end

function Economy.FactoryIncome(lines: { [string]: any }): number
	local total = 0
	for lineId, worker in lines do
		total += Economy.LineIncome(lineId, worker)
	end
	return total
end

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
