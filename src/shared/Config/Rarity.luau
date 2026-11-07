--!strict
-- Tiers de raridade. Escala exponencial: cada tier multiplica os atributos por GROWTH.
-- Pesos da roleta somam 100 (são percentuais sem sorte aplicada).

export type Tier = {
	Index: number,
	Name: string,
	Color: Color3,
	Weight: number,
}

local GROWTH = 2.5
local MAX_LUCK = 25

local Tiers: { Tier } = {
	{ Index = 1, Name = "Comum", Color = Color3.fromRGB(150, 150, 150), Weight = 60 },
	{ Index = 2, Name = "Incomum", Color = Color3.fromRGB(80, 200, 90), Weight = 25 },
	{ Index = 3, Name = "Raro", Color = Color3.fromRGB(60, 140, 255), Weight = 10 },
	{ Index = 4, Name = "Ultrarraro", Color = Color3.fromRGB(0, 220, 220), Weight = 3.5 },
	{ Index = 5, Name = "Épico", Color = Color3.fromRGB(170, 70, 255), Weight = 1.1 },
	{ Index = 6, Name = "Lendário", Color = Color3.fromRGB(255, 170, 0), Weight = 0.3 },
	{ Index = 7, Name = "Mítico", Color = Color3.fromRGB(255, 60, 90), Weight = 0.08 },
	{ Index = 8, Name = "Primordial", Color = Color3.fromRGB(255, 255, 255), Weight = 0.015 },
	{ Index = 9, Name = "Galáctico", Color = Color3.fromRGB(255, 80, 220), Weight = 0.005 },
}

local Rarity = {}

Rarity.Tiers = Tiers
Rarity.Count = #Tiers
Rarity.Growth = GROWTH
Rarity.MaxLuck = MAX_LUCK

function Rarity.Get(index: number): Tier
	local tier = Tiers[index]
	assert(tier, "Tier inválido: " .. tostring(index))
	return tier
end

function Rarity.IsValid(index: any): boolean
	return type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #Tiers
end

-- Multiplicador de atributos (HP, dano, valor de venda) para o tier.
function Rarity.Multiplier(index: number): number
	return GROWTH ^ (index - 1)
end

-- Pesos com sorte aplicada: a sorte multiplica todos os tiers acima de Comum.
-- luck = 1 significa sem bônus. Limitado a MAX_LUCK.
function Rarity.WeightsWithLuck(luck: number): { number }
	local l = math.clamp(luck, 1, MAX_LUCK)
	local weights = table.create(#Tiers)
	for i, tier in Tiers do
		weights[i] = if i == 1 then tier.Weight else tier.Weight * l
	end
	return weights
end

-- Chances em % já com sorte aplicada (para exibir as odds na UI).
function Rarity.Odds(luck: number): { number }
	local weights = Rarity.WeightsWithLuck(luck)
	local total = 0
	for _, w in weights do
		total += w
	end
	local odds = table.create(#weights)
	for i, w in weights do
		odds[i] = w / total * 100
	end
	return odds
end

-- Sorteia um tier. `rng` deve ser um Random do servidor.
function Rarity.Roll(rng: Random, luck: number): number
	local weights = Rarity.WeightsWithLuck(luck)
	local total = 0
	for _, w in weights do
		total += w
	end
	local pick = rng:NextNumber() * total
	for i, w in weights do
		pick -= w
		if pick <= 0 then
			return i
		end
	end
	return 1
end

return Rarity
