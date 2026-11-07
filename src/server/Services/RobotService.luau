--!strict
-- Robôs nos Pads de Defesa: montagem visual (provisória), HP por raridade, targeting e ataques.
-- HP = soma das peças; se zerar, o robô fica "quebrado" até o início da próxima horda (sem custo).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Items = require(Shared.Config.Items)
local Economy = require(Shared.Config.Economy)

local Types = require(script.Parent.Parent.Types)
local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)

type Zombie = Types.Zombie

export type Robot = {
	Pad: string,
	Position: Vector3,
	Model: Model?,
	Hp: number,
	MaxHp: number,
	Weapon: Items.WeaponStats?,
	Damage: number,
	NextAttack: number,
	Broken: boolean,
}

-- Callback para avisar mudanças de HP (HordeService repassa para a UI).
type HpListener = (player: Player, pad: string, hp: number, maxHp: number) -> ()

local RobotService = {}

local robots: { [Player]: { [string]: Robot } } = {}
local hpListener: HpListener? = nil

local function tierColor(key: string): Color3
	local item = Items.Parse(key)
	return if item then Rarity.Get(item.Tier).Color else Color3.fromRGB(60, 60, 60)
end

local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.Metal
	p.Parent = parent
	return p
end

-- Modelo provisório: blocos coloridos pela raridade de cada peça. Trocar pelos modelos 3D depois.
local function buildModel(pad: { [string]: string }, base: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Robot"
	local up = base * CFrame.new(0, 0.3, 0)
	if pad.Legs ~= "" then
		block("Legs", Vector3.new(2.6, 2.4, 1.4), up * CFrame.new(0, 1.2, 0), tierColor(pad.Legs), model)
	end
	if pad.Torso ~= "" then
		block("Torso", Vector3.new(3, 2.6, 1.8), up * CFrame.new(0, 3.7, 0), tierColor(pad.Torso), model)
	end
	if pad.Arms ~= "" then
		block("ArmL", Vector3.new(0.9, 2.4, 0.9), up * CFrame.new(-2, 3.6, 0), tierColor(pad.Arms), model)
		block("ArmR", Vector3.new(0.9, 2.4, 0.9), up * CFrame.new(2, 3.6, 0), tierColor(pad.Arms), model)
	end
	if pad.Head ~= "" then
		block("Head", Vector3.new(1.6, 1.4, 1.6), up * CFrame.new(0, 5.8, 0), tierColor(pad.Head), model)
	end
	if pad.Weapon ~= "" then
		block("Weapon", Vector3.new(0.4, 0.4, 3.2), up * CFrame.new(2, 3, -1.6), tierColor(pad.Weapon), model)
	end
	local primary = model:FindFirstChildWhichIsA("BasePart")
	if primary then
		model.PrimaryPart = primary
	end
	return model
end

local function computeStats(pad: { [string]: string }): (number, Items.WeaponStats?, number)
	local hp = 0
	for _, slot in Items.PartSlots do
		local item = Items.Parse(pad[slot])
		if item then
			hp += (Items.PartBaseHp :: any)[slot] * Rarity.Multiplier(item.Tier)
		end
	end
	local weaponItem = Items.Parse(pad.Weapon)
	if not weaponItem then
		return hp, nil, 0
	end
	local weapon = Items.Weapons[weaponItem.Type]
	return math.max(hp, 10), weapon, weapon.Damage * Rarity.Multiplier(weaponItem.Tier)
end

function RobotService.SetHpListener(listener: HpListener)
	hpListener = listener
end

-- Recria o robô de um pad a partir dos dados salvos.
function RobotService.RefreshPad(player: Player, padId: string)
	local data = DataService.Get(player)
	local base = BaseService.Get(player)
	if not data or not base then
		return
	end
	local perPlayer = robots[player]
	if not perPlayer then
		perPlayer = {}
		robots[player] = perPlayer
	end
	local old = perPlayer[padId]
	if old and old.Model then
		old.Model:Destroy()
	end
	perPlayer[padId] = nil

	local unlocked = math.min(Economy.StartPads + (data.Upgrades.Pads or 0), Economy.MaxPads)
	local padPart = base.Pads[padId]
	local padIndex = tonumber(padId) or math.huge
	if padIndex > unlocked or not padPart then
		if padPart then
			padPart.Transparency = 0.7
		end
		return
	end
	padPart.Transparency = 0

	local padData = (data.Pads :: any)[padId]
	local maxHp, weapon, damage = computeStats(padData)
	if maxHp <= 0 and not weapon then
		return
	end

	local top = padPart.Position + Vector3.new(0, padPart.Size.X / 2, 0)
	local facing = CFrame.lookAt(top, Vector3.new(base.Spawn.X, top.Y, base.Spawn.Z))
	local model = buildModel(padData, facing)
	model.Parent = base.Robots

	perPlayer[padId] = {
		Pad = padId,
		Position = top,
		Model = model,
		Hp = maxHp,
		MaxHp = maxHp,
		Weapon = weapon,
		Damage = damage,
		NextAttack = 0,
		Broken = false,
	}
	if hpListener then
		hpListener(player, padId, maxHp, maxHp)
	end
end

function RobotService.RefreshAll(player: Player)
	for i = 1, Economy.MaxPads do
		RobotService.RefreshPad(player, tostring(i))
	end
end

-- Início de horda: todos os robôs voltam com 100% de HP, sem custo.
function RobotService.RestoreAll(player: Player)
	local perPlayer = robots[player]
	if not perPlayer then
		return
	end
	for padId, robot in perPlayer do
		robot.Hp = robot.MaxHp
		robot.Broken = false
		if robot.Model then
			for _, p in robot.Model:GetChildren() do
				if p:IsA("BasePart") then
					p.Transparency = 0
				end
			end
		end
		if hpListener then
			hpListener(player, padId, robot.Hp, robot.MaxHp)
		end
	end
end

function RobotService.GetRobots(player: Player): { [string]: Robot }
	return robots[player] or {}
end

function RobotService.Damage(player: Player, robot: Robot, amount: number)
	if robot.Broken then
		return
	end
	robot.Hp = math.max(0, robot.Hp - amount)
	if robot.Hp <= 0 then
		robot.Broken = true
		if robot.Model then
			for _, p in robot.Model:GetChildren() do
				if p:IsA("BasePart") then
					p.Transparency = 0.75
				end
			end
		end
	end
	if hpListener then
		hpListener(player, robot.Pad, robot.Hp, robot.MaxHp)
	end
end

--------------------------------------------------------------------------------
-- Combate
--------------------------------------------------------------------------------

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function pickTarget(robot: Robot, mode: string, zombies: { Zombie }, range: number): Zombie?
	local best: Zombie? = nil
	local bestScore = -math.huge
	for _, z in zombies do
		if not z.Dead then
			local dist = flatDistance(robot.Position, z.Position)
			if dist <= range then
				local score
				if mode == "Boss" then
					score = (if z.Kind == "Boss" then 1e9 elseif z.Kind == "Tank" then 1e6 else 0) + z.Hp
				elseif mode == "Ranged" then
					score = dist -- mais distante dentro do alcance
				else
					score = -dist -- mais próximo
				end
				if score > bestScore then
					best, bestScore = z, score
				end
			end
		end
	end
	return best
end

type DealDamage = (zombie: Zombie, amount: number, stun: number?) -> ()

-- Executa os ataques dos robôs prontos. Chamado pelo loop da horda.
function RobotService.Step(player: Player, zombies: { Zombie }, now: number, dealDamage: DealDamage)
	local perPlayer = robots[player]
	local data = DataService.Get(player)
	if not perPlayer or not data then
		return
	end
	for padId, robot in perPlayer do
		local weapon = robot.Weapon
		if weapon and not robot.Broken and now >= robot.NextAttack then
			local mode = (data.Pads :: any)[padId].Targeting
			local target = pickTarget(robot, mode, zombies, weapon.Range)
			if target then
				robot.NextAttack = now + weapon.Cooldown
				local hits = 0
				local toTarget =
					Vector3.new(target.Position.X - robot.Position.X, 0, target.Position.Z - robot.Position.Z)
				local dir = if toTarget.Magnitude > 0 then toTarget.Unit else Vector3.zAxis

				if weapon.Pattern == "Circle" then
					for _, z in zombies do
						if hits >= weapon.MaxTargets then
							break
						end
						if not z.Dead and flatDistance(robot.Position, z.Position) <= weapon.Range then
							dealDamage(z, robot.Damage, weapon.Stun)
							hits += 1
						end
					end
				elseif weapon.Pattern == "Cone" then
					local cosHalf = math.cos(math.rad((weapon.Angle or 90) / 2))
					for _, z in zombies do
						if hits >= weapon.MaxTargets then
							break
						end
						local offset =
							Vector3.new(z.Position.X - robot.Position.X, 0, z.Position.Z - robot.Position.Z)
						local dist = offset.Magnitude
						if
							not z.Dead
							and dist <= weapon.Range
							and (dist < 1 or offset.Unit:Dot(dir) >= cosHalf)
						then
							dealDamage(z, robot.Damage)
							hits += 1
						end
					end
				else -- Line (pierce)
					dealDamage(target, robot.Damage)
					hits = 1
					for _, z in zombies do
						if hits >= weapon.MaxTargets then
							break
						end
						if z ~= target and not z.Dead then
							local offset = Vector3.new(
								z.Position.X - robot.Position.X,
								0,
								z.Position.Z - robot.Position.Z
							)
							local along = offset:Dot(dir)
							local side = (offset - dir * along).Magnitude
							if along > 0 and along <= weapon.Range and side <= 3 then
								dealDamage(z, robot.Damage)
								hits += 1
							end
						end
					end
				end

				if robot.Model and robot.Model.PrimaryPart then
					local pivot = robot.Model:GetPivot()
					robot.Model:PivotTo(CFrame.lookAt(pivot.Position, pivot.Position + dir))
				end
			end
		end
	end
end

function RobotService.Clear(player: Player)
	local perPlayer = robots[player]
	if perPlayer then
		for _, robot in perPlayer do
			if robot.Model then
				robot.Model:Destroy()
			end
		end
	end
	robots[player] = nil
end

return RobotService
