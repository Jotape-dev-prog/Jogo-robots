--!strict
-- Rebirth: troca o progresso da base por um multiplicador permanente de dinheiro e loot extra.
--   Zera: dinheiro (volta ao inicial), hordas e checkpoints, upgrades (inclusive colunas do grid)
--         e a fábrica (linhas compradas e trabalhadores).
--   Mantém: inventário, robôs que cabem no grid inicial, arma do avatar, configurações e estatísticas.
--   Ganha: +50% de dinheiro para sempre (acumula) e giros grátis com sorte ×3.
--   Robôs quebrados são consertados.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Economy = require(Shared.Config.Economy)
local Grid = require(Shared.Config.Grid)

local DataService = require(script.Parent.DataService)
local RemoteGuard = require(script.Parent.RemoteGuard)
local RobotService = require(script.Parent.RobotService)
local HordeService = require(script.Parent.HordeService)
local FactoryService = require(script.Parent.FactoryService)
local InventoryService = require(script.Parent.InventoryService)

local RebirthService = {}

local function handleRebirth(player: Player): RemoteGuard.Result
	local data = DataService.Get(player)
	if not data then
		return RemoteGuard.Fail("Sem dados")
	end
	local wave, cost = Economy.RebirthRequirement(data.Rebirths)
	if data.Horde.Highest < wave then
		return RemoteGuard.Fail(`Chegue à horda {wave} para fazer Rebirth`)
	end
	if data.Cash < cost then
		return RemoteGuard.Fail("Dinheiro insuficiente para o Rebirth")
	end

	local previous = data.Rebirths

	-- Horda volta para a 1 (zumbis da horda atual somem).
	HordeService.ResetProgress(player)

	DataService.Set(player, { "Cash" }, Economy.StartingCash)
	DataService.Set(player, { "Horde" }, { Current = 1, Highest = 1, HighestCheckpoint = 1 })
	local upgrades = {}
	for name in data.Upgrades do
		upgrades[name] = 0
	end
	DataService.Set(player, { "Upgrades" }, upgrades)

	-- Robôs fora das colunas iniciais voltam para o inventário (as peças continuam suas).
	local startColumns = Grid.Columns(0)
	local grid = {}
	for cell, robot in data.Grid :: any do
		if Grid.IsUnlocked(cell, startColumns) then
			grid[cell] = robot
		end
	end
	DataService.Set(player, { "Grid" }, grid)
	DataService.Set(player, { "RobotHp" }, {})

	local lines = {}
	for _, id in Economy.FactoryLineIds() do
		lines[id] = { Unlocked = false, Head = "", Torso = "", Arms = "", Legs = "" }
	end
	DataService.Set(player, { "Factory", "Lines" }, lines)

	DataService.Set(player, { "Rebirths" }, previous + 1)

	RobotService.Clear(player)
	RobotService.RefreshAll(player)
	RobotService.HealAll(player)
	FactoryService.Refresh(player)

	local results =
		InventoryService.GrantRolls(player, Economy.RebirthBonusRolls(previous), Economy.Rebirth.BonusLuck)
	return { Ok = true, Rebirths = previous + 1, Results = results }
end

function RebirthService.Start()
	RemoteGuard.Handle("Rebirth", 2, 0.2, handleRebirth)
end

return RebirthService
