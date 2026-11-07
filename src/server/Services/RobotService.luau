--!strict
-- Robôs nos Pads de Defesa: montagem visual (provisória), HP por raridade, targeting e ataques.
-- HP = soma das peças; se zerar, o robô fica "quebrado" até o início da próxima horda (sem custo).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Items = require(Shared.Config.Items)
local Economy = require(Shared.Config.Economy)

local Types = require(script.Parent.Parent.Types)
local Combat = require(script.Parent.Parent.Combat)
local Models = require(script.Parent.Parent.Models)
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
	local model = Models.Robot(padData, facing)
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
			for _, p in robot.Model:GetDescendants() do
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
			for _, p in robot.Model:GetDescendants() do
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
				local toTarget =
					Vector3.new(target.Position.X - robot.Position.X, 0, target.Position.Z - robot.Position.Z)
				local dir = if toTarget.Magnitude > 0 then toTarget.Unit else Vector3.zAxis
				for _, z in Combat.Resolve(weapon, robot.Position, dir, zombies, target) do
					dealDamage(z, robot.Damage, weapon.Stun)
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
