--!strict
-- Estrutura salva de cada jogador (ProfileStore). Ao mudar, aumente DataVersion e trate a migração em DataService.
-- Regras do ProfileStore: sem tabelas numéricas com buracos, sem Instances/Vector3/funções.

local Economy = require(game:GetService("ReplicatedStorage").Shared.Config.Economy)

export type PadData = {
	Head: string,
	Torso: string,
	Arms: string,
	Legs: string,
	Weapon: string,
	Targeting: string, -- "Nearest" | "Boss" | "Ranged"
}

export type WorkerData = {
	Unlocked: boolean,
	Head: string,
	Torso: string,
	Arms: string,
	Legs: string,
}

export type PlayerData = {
	DataVersion: number,
	Cash: number,
	TotalEarned: number,
	Rebirths: number,
	Horde: {
		Current: number,
		Highest: number,
		HighestCheckpoint: number,
	},
	Inventory: { [string]: number }, -- chave do item → quantidade
	Pads: { [string]: PadData }, -- "1".."6"
	AvatarWeapon: string, -- arma equipada no avatar ("" = nenhuma)
	Factory: { Lines: { [string]: WorkerData } }, -- "1-1".."3-2"
	Upgrades: { [string]: number },
	Settings: {
		AutoFuse: boolean,
		AutoSellBelowTier: number, -- 0 = desligado; vende automaticamente itens com tier < valor
	},
	Stats: {
		Kills: number,
		Rolls: number,
		Defeats: number,
	},
}

local function emptyPad(): PadData
	return { Head = "", Torso = "", Arms = "", Legs = "", Weapon = "", Targeting = "Nearest" }
end

local pads: { [string]: PadData } = {}
for i = 1, Economy.MaxPads do
	pads[tostring(i)] = emptyPad()
end
-- Kit inicial no pad 1: robô de sucata com espada.
pads["1"] = {
	Head = "Part:Head:1",
	Torso = "Part:Torso:1",
	Arms = "Part:Arms:1",
	Legs = "Part:Legs:1",
	Weapon = "Weapon:Sword:1",
	Targeting = "Nearest",
}

local lines: { [string]: WorkerData } = {}
for _, id in Economy.FactoryLineIds() do
	lines[id] = { Unlocked = false, Head = "", Torso = "", Arms = "", Legs = "" }
end

local Template: PlayerData = {
	DataVersion = 1,
	Cash = Economy.StartingCash,
	TotalEarned = 0,
	Rebirths = 0,
	Horde = { Current = 1, Highest = 1, HighestCheckpoint = 1 },
	Inventory = {
		["Part:Head:1"] = 1,
		["Part:Torso:1"] = 1,
		["Part:Arms:1"] = 1,
		["Part:Legs:1"] = 1,
		["Weapon:Sword:1"] = 2, -- uma para o robô do pad 1, outra para o avatar
	},
	Pads = pads,
	AvatarWeapon = "Weapon:Sword:1",
	Factory = { Lines = lines },
	Upgrades = { KillValue = 0, Rolls = 0, Luck = 0, Pads = 0 },
	Settings = { AutoFuse = false, AutoSellBelowTier = 0 },
	Stats = { Kills = 0, Rolls = 0, Defeats = 0 },
}

return Template
