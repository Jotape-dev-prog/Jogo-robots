--!strict
-- Roleta gacha, forja (3 → 1), venda, equipar pads, Auto-Fundir/Auto-Vender e upgrades.
-- Tudo é decidido no servidor; o cliente só pede.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Items = require(Shared.Config.Items)
local Economy = require(Shared.Config.Economy)
local Grid = require(Shared.Config.Grid)

local DataService = require(script.Parent.DataService)
local RemoteGuard = require(script.Parent.RemoteGuard)
local RobotService = require(script.Parent.RobotService)
local AvatarService = require(script.Parent.AvatarService)
local FactoryService = require(script.Parent.FactoryService)

local rng = Random.new()
local globalLuckMultiplier = 1 -- eventos globais (ex.: 5x sorte) alteram isto

local TARGETING_MODES = { "Nearest", "Boss", "Ranged" }
local EQUIP_SLOTS = { "Head", "Torso", "Arms", "Legs", "Weapon" }

local InventoryService = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

function InventoryService.Columns(player: Player): number
	local data = DataService.Get(player)
	return Grid.Columns(if data then data.Upgrades.Grid else 0)
end

function InventoryService.MaxRolls(player: Player): number
	local data = DataService.Get(player)
	if not data then
		return 1
	end
	return math.min(1 + (data.Upgrades.Rolls or 0), Economy.MaxSimultaneousRolls)
end

function InventoryService.Luck(player: Player): number
	local data = DataService.Get(player)
	local upgrade = if data then (data.Upgrades.Luck or 0) * Economy.Upgrades.Luck.PerLevel else 0
	return (1 + upgrade) * globalLuckMultiplier
end

function InventoryService.SetGlobalLuckMultiplier(multiplier: number)
	globalLuckMultiplier = math.max(1, multiplier)
end

local function isValidCell(player: Player, cell: any): boolean
	return Grid.IsUnlocked(cell, InventoryService.Columns(player))
end

local function emptyLoadout(): { [string]: string }
	return { Head = "", Torso = "", Arms = "", Legs = "", Weapon = "", Targeting = "Nearest" }
end

local function isEmpty(loadout: { [string]: string }): boolean
	for _, slot in EQUIP_SLOTS do
		if loadout[slot] ~= "" then
			return false
		end
	end
	return true
end

-- Funde tudo o que for possível, em cascata (Comum → Incomum → ...). Retorna quantas fusões fez.
local function autoFuse(player: Player): number
	local data = DataService.Get(player)
	if not data then
		return 0
	end
	local fused = 0
	local changed = true
	while changed do
		changed = false
		for key in table.clone(data.Inventory) do
			local nextKey = Items.NextTierKey(key)
			while nextKey and DataService.AvailableCount(player, key) >= 3 do
				DataService.RemoveItem(player, key, 3)
				DataService.AddItem(player, nextKey, 1)
				fused += 1
				changed = true
			end
		end
	end
	return fused
end

--------------------------------------------------------------------------------
-- Roleta
--------------------------------------------------------------------------------

local function rollOne(player: Player): string
	local tier = Rarity.Roll(rng, InventoryService.Luck(player))
	if rng:NextNumber() < Items.WeaponRollChance then
		local weaponType = Items.WeaponTypes[rng:NextInteger(1, #Items.WeaponTypes)]
		return Items.WeaponKey(weaponType, tier)
	end
	local slot = Items.PartSlots[rng:NextInteger(1, #Items.PartSlots)]
	return Items.PartKey(slot, tier)
end

local function handleRoll(player: Player, count: any): RemoteGuard.Result
	if not RemoteGuard.IsInt(count, 1, InventoryService.MaxRolls(player)) then
		return RemoteGuard.Fail("Quantidade inválida")
	end
	local data = DataService.Get(player)
	if not data then
		return RemoteGuard.Fail("Sem dados")
	end
	local cost = count * Economy.RollCost
	if not DataService.SpendCash(player, cost) then
		return RemoteGuard.Fail("Dinheiro insuficiente")
	end

	local results = {}
	local autoSellBelow = data.Settings.AutoSellBelowTier
	for _ = 1, count do
		local key = rollOne(player)
		local item = Items.Parse(key) :: Items.ParsedItem
		local sold = autoSellBelow > 0 and item.Tier < autoSellBelow
		if sold then
			DataService.AddCash(player, Economy.SellValue(item.Tier), false)
		else
			DataService.AddItem(player, key, 1)
		end
		table.insert(results, { Key = key, Tier = item.Tier, Sold = sold })
	end
	DataService.Increment(player, { "Stats", "Rolls" }, count)

	local fused = if data.Settings.AutoFuse then autoFuse(player) else 0
	return { Ok = true, Results = results, Fused = fused }
end

--------------------------------------------------------------------------------
-- Forja e venda
--------------------------------------------------------------------------------

local function handleFuse(player: Player, key: any): RemoteGuard.Result
	if not Items.Parse(key) then
		return RemoteGuard.Fail("Item inválido")
	end
	local nextKey = Items.NextTierKey(key)
	if not nextKey then
		return RemoteGuard.Fail("Já está no tier máximo")
	end
	if not DataService.RemoveItem(player, key, 3) then
		return RemoteGuard.Fail("Precisa de 3 cópias livres (não equipadas)")
	end
	DataService.AddItem(player, nextKey, 1)
	return { Ok = true, Result = nextKey }
end

local function handleSell(player: Player, key: any, amount: any): RemoteGuard.Result
	local item = Items.Parse(key)
	if not item then
		return RemoteGuard.Fail("Item inválido")
	end
	if not RemoteGuard.IsInt(amount, 1, 1e6) then
		return RemoteGuard.Fail("Quantidade inválida")
	end
	if not DataService.RemoveItem(player, key, amount) then
		return RemoteGuard.Fail("Cópias livres insuficientes")
	end
	local earned = DataService.AddCash(player, Economy.SellValue(item.Tier) * amount, false)
	return { Ok = true, Earned = earned }
end

local function handleAutoSettings(player: Player, autoFuseOn: any, sellBelow: any): RemoteGuard.Result
	if type(autoFuseOn) ~= "boolean" or not RemoteGuard.IsInt(sellBelow, 0, Rarity.Count) then
		return RemoteGuard.Fail("Configuração inválida")
	end
	DataService.Set(player, { "Settings", "AutoFuse" }, autoFuseOn)
	DataService.Set(player, { "Settings", "AutoSellBelowTier" }, sellBelow)
	local fused = if autoFuseOn then autoFuse(player) else 0
	return { Ok = true, Fused = fused }
end

--------------------------------------------------------------------------------
-- Equipar
--------------------------------------------------------------------------------

local function handleEquip(player: Player, cell: any, slot: any, key: any): RemoteGuard.Result
	if not isValidCell(player, cell) or not RemoteGuard.IsOneOf(slot, EQUIP_SLOTS) then
		return RemoteGuard.Fail("Hexágono ou slot inválido")
	end
	local data = DataService.Get(player) :: any
	local current = data.Grid[cell]
	if RobotService.IsBroken(player, cell) then
		return RemoteGuard.Fail("Robô quebrado — só volta a funcionar após uma derrota")
	end
	if key ~= "" then
		local item = Items.Parse(key)
		if not item or item.Slot ~= slot then
			return RemoteGuard.Fail("Item não serve neste slot")
		end
		if (not current or current[slot] ~= key) and DataService.AvailableCount(player, key) < 1 then
			return RemoteGuard.Fail("Você não tem cópia livre deste item")
		end
	elseif not current then
		return { Ok = true }
	end
	-- Hexágono vazio ganha um robô novo; robô sem nenhuma peça é removido.
	local loadout = if current then table.clone(current) else emptyLoadout()
	loadout[slot] = key
	DataService.Set(player, { "Grid", cell }, if isEmpty(loadout) then nil else loadout)
	RobotService.RefreshCell(player, cell)
	return { Ok = true }
end

local function handleMoveRobot(player: Player, from: any, to: any): RemoteGuard.Result
	if not isValidCell(player, from) or not isValidCell(player, to) or from == to then
		return RemoteGuard.Fail("Hexágono inválido")
	end
	if not RobotService.MoveRobot(player, from, to) then
		return RemoteGuard.Fail("Não há robô nesse hexágono")
	end
	return { Ok = true }
end

local function handleEquipBest(player: Player): RemoteGuard.Result
	local data = DataService.Get(player)
	if not data then
		return RemoteGuard.Fail("Sem dados")
	end
	-- Estoque total (tudo volta para o "bolso" e é redistribuído).
	-- Robôs quebrados ficam como estão: suas peças não entram na redistribuição.
	local stock: { [string]: number } = table.clone(data.Inventory)
	local keptBroken: { [string]: any } = {}
	for cell, loadout in data.Grid :: any do
		if RobotService.IsBroken(player, cell) then
			keptBroken[cell] = loadout
			for slotName, slotKey in loadout do
				if slotName ~= "Targeting" and slotKey ~= "" and stock[slotKey] then
					stock[slotKey] -= 1
				end
			end
		end
	end

	local function takeBest(slot: string): string
		local bestKey, bestTier = "", 0
		for key, count in stock do
			local item = Items.Parse(key)
			if count > 0 and item and item.Slot == slot and item.Tier > bestTier then
				bestKey, bestTier = key, item.Tier
			end
		end
		if bestKey ~= "" then
			stock[bestKey] -= 1
		end
		return bestKey
	end

	-- 1º avatar (melhor arma), 2º pads de defesa, 3º trabalhadores da fábrica.
	DataService.Set(player, { "AvatarWeapon" }, takeBest("Weapon"))
	AvatarService.Refresh(player)

	-- Robôs: uma arma por hexágono. Corpo a corpo na frente (A, B), rifles atrás (C, D).
	local weapons: { string } = {}
	for key, count in stock do
		local item = Items.Parse(key)
		if item and item.Kind == "Weapon" then
			for _ = 1, count do
				table.insert(weapons, key)
			end
		end
	end
	table.sort(weapons, function(a, b)
		return (Items.Parse(a) :: Items.ParsedItem).Tier > (Items.Parse(b) :: Items.ParsedItem).Tier
	end)
	local cells = Grid.UnlockedCells(InventoryService.Columns(player))
	local front, back = {}, {}
	for _, cell in cells do
		if not keptBroken[cell] then
			table.insert(if Grid.IsFrontRow(cell) then front else back, cell)
		end
	end
	local newGrid: { [string]: any } = table.clone(keptBroken)
	local placed: { string } = {}
	local function place(cell: string, weaponKey: string)
		stock[weaponKey] -= 1
		local old = (data.Grid :: any)[cell]
		local loadout = emptyLoadout()
		loadout.Weapon = weaponKey
		loadout.Targeting = if old then old.Targeting else "Nearest"
		newGrid[cell] = loadout
		table.insert(placed, cell)
	end
	local leftover: { string } = {}
	for _, key in weapons do
		local isRifle = (Items.Parse(key) :: Items.ParsedItem).Type == "Rifle"
		local preferred = if isRifle then back else front
		if #preferred > 0 then
			place(table.remove(preferred, 1) :: string, key)
		else
			table.insert(leftover, key)
		end
	end
	for _, key in leftover do
		local cell = table.remove(front, 1) or table.remove(back, 1)
		if not cell then
			break
		end
		place(cell, key)
	end
	-- Peças: os robôs com armas melhores recebem as peças melhores primeiro.
	for _, cell in placed do
		for _, slot in Items.PartSlots do
			newGrid[cell][slot] = takeBest(slot)
		end
	end
	DataService.Set(player, { "Grid" }, newGrid)
	RobotService.RefreshAll(player)

	for _, lineId in Economy.FactoryLineIds() do
		local unlockedLine = data.Factory.Lines[lineId].Unlocked
		for _, slot in Items.PartSlots do
			DataService.Set(
				player,
				{ "Factory", "Lines", lineId, slot },
				if unlockedLine then takeBest(slot) else ""
			)
		end
	end
	FactoryService.Refresh(player)
	return { Ok = true }
end

local function handleTargeting(player: Player, cell: any, mode: any): RemoteGuard.Result
	local data = DataService.Get(player) :: any
	if
		not isValidCell(player, cell)
		or not data.Grid[cell]
		or not RemoteGuard.IsOneOf(mode, TARGETING_MODES)
	then
		return RemoteGuard.Fail("Configuração inválida")
	end
	DataService.Set(player, { "Grid", cell, "Targeting" }, mode)
	return { Ok = true }
end

--------------------------------------------------------------------------------
-- Upgrades
--------------------------------------------------------------------------------

local function handleBuyUpgrade(player: Player, name: any): RemoteGuard.Result
	if type(name) ~= "string" or not (Economy.Upgrades :: any)[name] then
		return RemoteGuard.Fail("Upgrade inválido")
	end
	local data = DataService.Get(player) :: any
	local level = data.Upgrades[name] or 0
	local cost = Economy.UpgradeCost(name, level)
	if not cost then
		return RemoteGuard.Fail("Nível máximo")
	end
	if not DataService.SpendCash(player, cost) then
		return RemoteGuard.Fail("Dinheiro insuficiente")
	end
	DataService.Set(player, { "Upgrades", name }, level + 1)
	if name == "Grid" then
		RobotService.RefreshAll(player)
	end
	return { Ok = true, Level = level + 1 }
end

function InventoryService.Start()
	RemoteGuard.Handle("Roll", 4, 2, handleRoll)
	RemoteGuard.Handle("Fuse", 10, 5, handleFuse)
	RemoteGuard.Handle("Sell", 10, 5, handleSell)
	RemoteGuard.Handle("Equip", 15, 8, handleEquip)
	RemoteGuard.Handle("MoveRobot", 10, 5, handleMoveRobot)
	RemoteGuard.Handle("EquipBest", 2, 0.5, handleEquipBest)
	RemoteGuard.Handle("SetTargeting", 10, 5, handleTargeting)
	RemoteGuard.Handle("SetAutoSettings", 3, 1, handleAutoSettings)
	RemoteGuard.Handle("BuyUpgrade", 5, 2, handleBuyUpgrade)
end

return InventoryService
