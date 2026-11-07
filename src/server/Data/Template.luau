--!strict
-- Estrutura salva de cada jogador (ProfileStore). Ao mudar, aumente DataVersion e trate a migração em DataService.
-- Regras do ProfileStore: sem tabelas numéricas com buracos, sem Instances/Vector3/funções.

local Economy = require(game:GetService("ReplicatedStorage").Shared.Config.Economy)

export type RobotData = {
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
	Grid: { [string]: RobotData }, -- hexágono ("A1".."D7") → robô; só hexágonos ocupados
	RobotHp: { [string]: number }, -- hexágono → fração de vida (0 = quebrado); ausente = vida cheia
	AvatarWeapon: string, -- arma equipada no avatar ("" = nenhuma)
	Factory: { Lines: { [string]: WorkerData } }, -- "1-1".."3-2"
	Upgrades: { [string]: number },
	Settings: {
		AutoFuse: boolean,
		AutoSellBelowTier: number, -- 0 = desligado; vende automaticamente itens com tier < valor
		HordePaused: boolean, -- jogador pausou as hordas para focar no tycoon
	},
	Stats: {
		Kills: number,
		Rolls: number,
		Defeats: number,
	},
}

-- Kit inicial: robô de sucata com espada na fileira da frente.
local starterRobot: RobotData = {
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
	DataVersion = 2,
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
	Grid = { A1 = starterRobot },
	RobotHp = {},
	AvatarWeapon = "Weapon:Sword:1",
	Factory = { Lines = lines },
	Upgrades = { KillValue = 0, Rolls = 0, Luck = 0, Grid = 0 },
	Settings = { AutoFuse = false, AutoSellBelowTier = 0, HordePaused = false },
	Stats = { Kills = 0, Rolls = 0, Defeats = 0 },
}

return Template
