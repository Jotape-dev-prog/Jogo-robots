--!strict
-- Roleta gacha, forja (3 → 1), venda, equipar pads, Auto-Fundir/Auto-Vender e upgrades.
-- Tudo é decidido no servidor; o cliente só pede.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Items = require(Shared.Config.Items)
local Economy = require(Shared.Config.Economy)

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

function InventoryService.UnlockedPads(player: Player): number
	local data = DataService.Get(player)
	if not data then
		return 0
	end
	return math.min(Economy.StartPads + (data.Upgrades.Pads or 0), Economy.MaxPads)
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

local function isValidPad(player: Player, pad: any): boolean
	if type(pad) ~= "string" then
		return false
	end
	local index = tonumber(pad)
	return index ~= nil and RemoteGuard.IsInt(index, 1, InventoryService.UnlockedPads(player))
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

local function handleEquip(player: Player, pad: any, slot: any, key: any): RemoteGuard.Result
	if not isValidPad(player, pad) or not RemoteGuard.IsOneOf(slot, EQUIP_SLOTS) then
		return RemoteGuard.Fail("Pad ou slot inválido")
	end
	local data = DataService.Get(player) :: any
	if key ~= "" then
		local item = Items.Parse(key)
		if not item or item.Slot ~= slot then
			return RemoteGuard.Fail("Item não serve neste slot")
		end
		if data.Pads[pad][slot] ~= key and DataService.AvailableCount(player, key) < 1 then
			return RemoteGuard.Fail("Você não tem cópia livre deste item")
		end
	end
	DataService.Set(player, { "Pads", pad, slot }, key)
	RobotService.RefreshPad(player, pad)
	return { Ok = true }
end

local function handleEquipBest(player: Player): RemoteGuard.Result
	local data = DataService.Get(player)
	if not data then
		return RemoteGuard.Fail("Sem dados")
	end
	-- Estoque total (tudo volta para o "bolso" e é redistribuído).
	local stock: { [string]: number } = table.clone(data.Inventory)

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

	local unlocked = InventoryService.UnlockedPads(player)
	for i = 1, Economy.MaxPads do
		local pad = tostring(i)
		for _, slot in EQUIP_SLOTS do
			local key = if i <= unlocked then takeBest(slot) else ""
			DataService.Set(player, { "Pads", pad, slot }, key)
		end
		RobotService.RefreshPad(player, pad)
	end

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

local function handleTargeting(player: Player, pad: any, mode: any): RemoteGuard.Result
	if not isValidPad(player, pad) or not RemoteGuard.IsOneOf(mode, TARGETING_MODES) then
		return RemoteGuard.Fail("Configuração inválida")
	end
	DataService.Set(player, { "Pads", pad, "Targeting" }, mode)
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
	if name == "Pads" then
		RobotService.RefreshAll(player)
	end
	return { Ok = true, Level = level + 1 }
end

function InventoryService.Start()
	RemoteGuard.Handle("Roll", 4, 2, handleRoll)
	RemoteGuard.Handle("Fuse", 10, 5, handleFuse)
	RemoteGuard.Handle("Sell", 10, 5, handleSell)
	RemoteGuard.Handle("Equip", 15, 8, handleEquip)
	RemoteGuard.Handle("EquipBest", 2, 0.5, handleEquipBest)
	RemoteGuard.Handle("SetTargeting", 10, 5, handleTargeting)
	RemoteGuard.Handle("SetAutoSettings", 3, 1, handleAutoSettings)
	RemoteGuard.Handle("BuyUpgrade", 5, 2, handleBuyUpgrade)
end

return InventoryService
