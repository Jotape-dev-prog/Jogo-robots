--!strict
-- Funções de apoio compartilhadas pelas janelas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local Economy = require(Shared.Config.Economy)
local Grid = require(Shared.Config.Grid)

local Ui = require(script.Parent.Parent.Ui)

local Common = {}

Common.SlotNames = {
	Head = "Cabeça",
	Torso = "Torso",
	Arms = "Braços",
	Legs = "Pernas",
	Weapon = "Arma",
}
Common.SlotOrder = { "Head", "Torso", "Arms", "Legs", "Weapon" }
Common.TargetingNames = { Nearest = "Mais próximo", Boss = "Boss primeiro", Ranged = "Mais distante" }
Common.TargetingCycle = { Nearest = "Boss", Boss = "Ranged", Ranged = "Nearest" }

function Common.TierColor(key: string): Color3
	local item = Items.Parse(key)
	return if item then Rarity.Get(item.Tier).Color else Ui.Theme.PanelLight
end

function Common.TierName(key: string): string
	local item = Items.Parse(key)
	return if item then Rarity.Get(item.Tier).Name else ""
end

-- Texto curto para um slot: "Torso Raro" ou "—".
function Common.Short(key: string): string
	if key == "" then
		return "—"
	end
	return Items.DisplayName(key)
end

function Common.StatsText(key: string): string
	local item = Items.Parse(key)
	if not item then
		return ""
	end
	local mult = Rarity.Multiplier(item.Tier)
	if item.Kind == "Weapon" then
		local w = Items.Weapons[item.Type]
		local pattern = if w.Pattern == "Cone"
			then "corte em cone"
			elseif w.Pattern == "Circle" then `área + atordoa {w.Stun}s`
			else `tiro que atravessa {w.MaxTargets}`
		return string.format(
			"Dano %s • Alcance %d • %.1fs • %s\nHP do avatar: %s",
			Ui.FormatNumber(w.Damage * mult),
			w.Range,
			w.Cooldown,
			pattern,
			Ui.FormatNumber(Items.AvatarMaxHp(item.Tier))
		)
	end
	local hp = (Items.PartBaseHp :: any)[item.Slot] * mult
	local weight = (Economy.Factory.WorkerWeights :: any)[item.Slot]
	return string.format(
		"HP no robô: %s\nNa fábrica: renda x%.2f",
		Ui.FormatNumber(hp),
		Rarity.Multiplier(item.Tier) ^ weight
	)
end

function Common.Columns(data: any): number
	return Grid.Columns(data.Upgrades.Grid)
end

function Common.RobotCount(data: any): number
	local n = 0
	for _ in data.Grid do
		n += 1
	end
	return n
end

-- Quantas cópias estão em uso (robôs do grid, avatar, fábrica). Espelha DataService.EquippedCount.
function Common.EquippedCount(data: any, key: string): number
	local count = if data.AvatarWeapon == key then 1 else 0
	for _, robot in data.Grid do
		for _, v in robot do
			if v == key then
				count += 1
			end
		end
	end
	for _, worker in data.Factory.Lines do
		for _, v in worker do
			if v == key then
				count += 1
			end
		end
	end
	return count
end

-- "Chip" de um slot: mostra a peça colorida pela raridade; clicar executa onClick.
function Common.SlotChip(parent: Instance, slot: string, key: string, onClick: () -> ()): TextButton
	-- Segunda linha: raridade (peças) ou "Rifle Raro" (armas, pois o tipo importa).
	local detail = if key == ""
		then "—"
		elseif slot == "Weapon" then Common.Short(key)
		else Common.TierName(key)
	local label = `<font size="12">{Common.SlotNames[slot]}</font>\n{detail}`
	local chip = Ui.Button(parent, label, Common.TierColor(key), onClick, UDim2.fromOffset(104, 46))
	if key == "" then
		chip.BackgroundColor3 = Ui.Theme.PanelLight
		chip.TextColor3 = Ui.Theme.TextDim
	end
	return chip
end

return Common
