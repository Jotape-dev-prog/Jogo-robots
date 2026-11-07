--!strict
-- Peças de robô e armas. Itens não têm atributos aleatórios além do tier,
-- então o inventário guarda apenas contagens por chave: "Part:Head:3", "Weapon:Rifle:5".

local Rarity = require(script.Parent.Rarity)

export type Slot = "Head" | "Torso" | "Arms" | "Legs" | "Weapon"
export type WeaponType = "Sword" | "Hammer" | "Rifle"

export type ParsedItem = {
	Kind: "Part" | "Weapon",
	Slot: Slot,
	Type: string, -- parte do robô ou tipo de arma
	Tier: number,
}

export type WeaponStats = {
	Name: string,
	Pattern: "Cone" | "Circle" | "Line",
	Range: number,
	Angle: number?, -- cone (graus)
	Damage: number, -- dano base (tier 1)
	Cooldown: number,
	MaxTargets: number, -- cone: alvos atingidos; linha: pierce
	Stun: number?,
}

local Items = {}

Items.PartSlots = { "Head", "Torso", "Arms", "Legs" } :: { Slot }
Items.WeaponTypes = { "Sword", "Hammer", "Rifle" } :: { WeaponType }

Items.PartNames = {
	Head = "Cabeça",
	Torso = "Torso",
	Arms = "Braços",
	Legs = "Pernas",
}

-- HP base de cada peça no tier 1. HP do robô = soma das peças × multiplicador do tier de cada uma.
Items.PartBaseHp = {
	Head = 15,
	Torso = 40,
	Arms = 20,
	Legs = 25,
}

Items.Weapons = {
	Sword = {
		Name = "Espada",
		Pattern = "Cone",
		Range = 14,
		Angle = 100,
		Damage = 10,
		Cooldown = 0.8,
		MaxTargets = 4,
	},
	Hammer = {
		Name = "Martelo e Escudo",
		Pattern = "Circle",
		Range = 11,
		Damage = 7,
		Cooldown = 1.4,
		MaxTargets = 8,
		Stun = 1.0,
	},
	Rifle = {
		Name = "Rifle",
		Pattern = "Line",
		Range = 45,
		Damage = 14,
		Cooldown = 1.0,
		MaxTargets = 2,
	},
} :: { [string]: WeaponStats }

-- Fatia da roleta: 80% peças, 20% armas.
Items.WeaponRollChance = 0.2

local partSet = { Head = true, Torso = true, Arms = true, Legs = true }

function Items.PartKey(slot: string, tier: number): string
	return `Part:{slot}:{tier}`
end

function Items.WeaponKey(weaponType: string, tier: number): string
	return `Weapon:{weaponType}:{tier}`
end

function Items.Parse(key: any): ParsedItem?
	if type(key) ~= "string" or #key > 32 then
		return nil
	end
	local kind, kindType, tierStr = string.match(key, "^(%a+):(%a+):(%d+)$")
	local tier = tonumber(tierStr)
	if not kind or not kindType or not tier or not Rarity.IsValid(tier) then
		return nil
	end
	if kind == "Part" and partSet[kindType] then
		return { Kind = "Part", Slot = kindType :: Slot, Type = kindType, Tier = tier }
	elseif kind == "Weapon" and Items.Weapons[kindType] then
		return { Kind = "Weapon", Slot = "Weapon", Type = kindType, Tier = tier }
	end
	return nil
end

function Items.DisplayName(key: string): string
	local item = Items.Parse(key)
	if not item then
		return "?"
	end
	local tierName = Rarity.Get(item.Tier).Name
	if item.Kind == "Weapon" then
		return `{Items.Weapons[item.Type].Name} {tierName}`
	end
	return `{(Items.PartNames :: any)[item.Type]} {tierName}`
end

-- Chave do tier seguinte (para a forja); nil se já for o último tier.
function Items.NextTierKey(key: string): string?
	local item = Items.Parse(key)
	if not item or item.Tier >= Rarity.Count then
		return nil
	end
	if item.Kind == "Weapon" then
		return Items.WeaponKey(item.Type, item.Tier + 1)
	end
	return Items.PartKey(item.Type, item.Tier + 1)
end

return Items
