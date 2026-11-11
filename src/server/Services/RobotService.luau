--!strict
-- Robôs do grid hexagonal (estilo auto-battler):
--   • Cada hexágono liberado comporta 1 robô (dados em PlayerData.Grid).
--   • Durante a horda os robôs saem do hexágono e perseguem os zumbis conforme o modo de mira;
--     armas corpo a corpo chegam perto, o rifle mantém distância.
--   • No início de cada horda voltam ao seu hexágono MANTENDO a vida com que terminaram a anterior.
--     Robô quebrado NÃO volta: fica fora (apagado no hexágono) até a derrota, quando todos são consertados.
--     Isso é a dificuldade do jogo. A vida fica salva no perfil (PlayerData.RobotHp), então sair e
--     voltar não conserta nada.
--   • Robô quebrado não pode ter peças trocadas (evita "consertar" reequipando).
--   • PvP: quando o dono entra na arena, os robôs vivos vão junto (escolta), seguem o dono e lutam
--     contra jogadores e robôs inimigos. Ao sair da arena ou quando o centro fecha, voltam para casa
--     com a vida que tinham antes do PvP (o PvP não gasta a vida da defesa).
--   • HP = soma das peças × multiplicador do tier. Pernas aumentam a velocidade.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Items = require(Shared.Config.Items)
local Grid = require(Shared.Config.Grid)
local Pvp = require(Shared.Config.Pvp)

local Types = require(script.Parent.Parent.Types)
local Combat = require(script.Parent.Parent.Combat)
local Fx = require(script.Parent.Parent.Fx)
local Models = require(script.Parent.Parent.Models)
local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)

type Zombie = Types.Zombie

export type Robot = {
	Cell: string,
	Home: Vector3,
	Position: Vector3,
	Facing: Vector3,
	Model: Model?,
	Root: BasePart?,
	HpBar: Frame?,
	Hp: number,
	MaxHp: number,
	Weapon: Items.WeaponStats?,
	WeaponTier: number,
	Damage: number,
	Speed: number,
	NextAttack: number,
	Broken: boolean,
}

-- Callback para avisar mudanças de HP (HordeService repassa para a UI).
type HpListener = (player: Player, cell: string, hp: number, maxHp: number) -> ()

local BASE_SPEED = 8
local SEPARATION = 3.2 -- distância mínima entre robôs
local ROBOT_HEIGHT_OFFSET = 0.2

local RobotService = {}

local robots: { [Player]: { [string]: Robot } } = {}
-- Escolta do PvP: vida de cada robô antes de ir para a arena (restaurada na volta).
type Snapshot = { Ratio: number, Broken: boolean }
local escorts: { [Player]: { [string]: Snapshot } } = {}
local hpListener: HpListener? = nil

local function computeStats(loadout: { [string]: string }): (number, Items.WeaponStats?, number, number)
	local hp = 0
	for _, slot in Items.PartSlots do
		local item = Items.Parse(loadout[slot])
		if item then
			hp += (Items.PartBaseHp :: any)[slot] * Rarity.Multiplier(item.Tier)
		end
	end
	local legs = Items.Parse(loadout.Legs)
	local speed = BASE_SPEED * (if legs then 1 + 0.12 * (legs.Tier - 1) else 0.75)
	local weaponItem = Items.Parse(loadout.Weapon)
	if not weaponItem then
		return hp, nil, 0, speed
	end
	local weapon = Items.Weapons[weaponItem.Type]
	return math.max(hp, 10), weapon, weapon.Damage * Rarity.Multiplier(weaponItem.Tier), speed
end

local function columnsOf(player: Player): number
	local data = DataService.Get(player)
	return Grid.Columns(if data then data.Upgrades.Grid else 0)
end

local function cellPosition(player: Player, cell: string): Vector3?
	local base = BaseService.Get(player)
	if not base then
		return nil
	end
	return (base.GridOrigin * CFrame.new(Grid.LocalOffset(cell))).Position
end

-- Cor dos hexágonos: liberado (aço), bloqueado (quase invisível).
local function paintCells(player: Player)
	local base = BaseService.Get(player)
	if not base then
		return
	end
	local columns = columnsOf(player)
	for cell, hex in base.Cells do
		local unlocked = Grid.IsUnlocked(cell, columns)
		for _, p in hex:GetDescendants() do
			if p:IsA("BasePart") then
				p.Transparency = if unlocked then 0 else 0.8
				p.Color = if unlocked then Color3.fromRGB(80, 88, 100) else Color3.fromRGB(40, 40, 45)
			end
		end
	end
end

local function makeHpBar(root: BasePart): Frame
	local gui = Instance.new("BillboardGui")
	gui.Name = "HpBar"
	gui.Size = UDim2.fromOffset(60, 8)
	gui.StudsOffset = Vector3.new(0, 7.8, 0)
	gui.MaxDistance = 90
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(30, 25, 22)
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(80, 200, 100)
	fill.BorderSizePixel = 0
	fill.Parent = back
	gui.Parent = root
	return fill
end

local function updateVisualHp(robot: Robot)
	local bar = robot.HpBar
	if bar then
		local ratio = if robot.MaxHp > 0 then robot.Hp / robot.MaxHp else 0
		bar.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
		bar.BackgroundColor3 = if ratio > 0.5
			then Color3.fromRGB(80, 200, 100)
			elseif ratio > 0.25 then Color3.fromRGB(230, 180, 50)
			else Color3.fromRGB(220, 70, 60)
	end
	if robot.Model then
		for _, p in robot.Model:GetDescendants() do
			if p:IsA("BasePart") and p.Name ~= "Root" then
				p.Transparency = if robot.Broken then 0.75 else 0
			end
		end
	end
end

local function notify(player: Player, robot: Robot)
	updateVisualHp(robot)
	if hpListener then
		hpListener(player, robot.Cell, robot.Hp, robot.MaxHp)
	end
end

function RobotService.SetHpListener(listener: HpListener)
	hpListener = listener
end

--------------------------------------------------------------------------------
-- Montagem
--------------------------------------------------------------------------------

-- Recria o robô de um hexágono a partir dos dados salvos.
-- Se já existia, preserva a proporção de vida (trocar peça no meio da horda não cura).
function RobotService.RefreshCell(player: Player, cell: string)
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
	local old = perPlayer[cell]
	if old and old.Model then
		old.Model:Destroy()
	end
	perPlayer[cell] = nil

	local loadout = (data.Grid :: any)[cell]
	if not loadout or not Grid.IsUnlocked(cell, columnsOf(player)) then
		if not loadout and (data.RobotHp :: any)[cell] ~= nil then
			DataService.Set(player, { "RobotHp", cell }, nil) -- hexágono vazio: nada a lembrar
		end
		if hpListener then
			hpListener(player, cell, 0, 0)
		end
		return
	end
	local maxHp, weapon, damage, speed = computeStats(loadout)
	if maxHp <= 0 and not weapon then
		return
	end

	local home = cellPosition(player, cell) :: Vector3
	local position = if old then old.Position else home
	-- Vida: do robô que já existia ou, ao entrar no jogo, a salva no perfil.
	local ratio = 1
	local broken = false
	if old then
		ratio = if old.MaxHp > 0 then old.Hp / old.MaxHp else 1
		broken = old.Broken
	else
		local saved = (data.RobotHp :: any)[cell]
		if typeof(saved) == "number" then
			ratio = math.clamp(saved, 0, 1)
			broken = ratio <= 0
		end
	end
	local hp = if broken then 0 else maxHp * ratio
	if broken then
		position = home
	end
	local facing = -base.GridOrigin.LookVector -- de frente para o ponto A
	local model = Models.Robot(loadout, CFrame.lookAt(position, position + facing))
	model:SetAttribute("Cell", cell)
	model:SetAttribute("OwnerUserId", player.UserId)
	model.Parent = base.Robots
	local root = model.PrimaryPart

	local robot: Robot = {
		Cell = cell,
		Home = home,
		Position = position,
		Facing = facing,
		Model = model,
		Root = root,
		HpBar = if root then makeHpBar(root) else nil,
		Hp = hp,
		MaxHp = maxHp,
		Weapon = weapon,
		WeaponTier = (Items.Parse(loadout.Weapon) or { Tier = 1 } :: any).Tier,
		Damage = damage,
		Speed = speed,
		NextAttack = 0,
		Broken = broken,
	}
	perPlayer[cell] = robot
	notify(player, robot)
end

function RobotService.RefreshAll(player: Player)
	paintCells(player)
	for _, cell in Grid.AllCells() do
		RobotService.RefreshCell(player, cell)
	end
end

local function placeAt(robot: Robot, position: Vector3)
	robot.Position = position
	local root = robot.Root
	if root then
		local ground = Vector3.new(position.X, robot.Home.Y + ROBOT_HEIGHT_OFFSET, position.Z)
		root.CFrame = CFrame.lookAt(ground, ground + robot.Facing)
	end
end

-- Grava a vida de cada robô no perfil (só os que não estão com vida cheia).
function RobotService.SaveHp(player: Player)
	local data = DataService.Get(player)
	local perPlayer = robots[player]
	if not data or not perPlayer then
		return
	end
	local saved: { [string]: number } = {}
	local snapshot = escorts[player]
	for cell, robot in perPlayer do
		local ratio = if robot.Broken or robot.MaxHp <= 0 then 0 else robot.Hp / robot.MaxHp
		local before = if snapshot then snapshot[cell] else nil
		if before then
			-- Na arena: o que vale para a defesa é a vida de antes do PvP.
			ratio = if before.Broken then 0 else before.Ratio
		end
		if ratio < 0.999 then
			saved[cell] = math.floor(ratio * 1000) / 1000
		end
	end
	DataService.Set(player, { "RobotHp" }, saved)
end

-- Início de horda: todos voltam ao hexágono mantendo a vida. Quebrados continuam fora.
function RobotService.ResetForWave(player: Player)
	for _, robot in robots[player] or {} do
		placeAt(robot, robot.Home)
		notify(player, robot)
	end
	RobotService.SaveHp(player)
end

-- Conserto total (usado na derrota, quando o jogo recomeça do checkpoint).
function RobotService.HealAll(player: Player)
	for _, robot in robots[player] or {} do
		robot.Broken = false
		robot.Hp = robot.MaxHp
		placeAt(robot, robot.Home)
		notify(player, robot)
	end
	RobotService.SaveHp(player)
end

function RobotService.IsBroken(player: Player, cell: string): boolean
	local robot = (robots[player] or {})[cell]
	return robot ~= nil and robot.Broken
end

function RobotService.AliveCount(player: Player): number
	local count = 0
	for _, robot in robots[player] or {} do
		if not robot.Broken then
			count += 1
		end
	end
	return count
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
		Fx.Event("b", robot.Position, 1, player.UserId)
		RobotService.SaveHp(player) -- grava na hora: sair do jogo não conserta
	end
	notify(player, robot)
end

--------------------------------------------------------------------------------
-- Movimento e combate
--------------------------------------------------------------------------------

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function pickTarget(robot: Robot, mode: string, zombies: { Zombie }): Zombie?
	local best: Zombie? = nil
	local bestScore = -math.huge
	for _, z in zombies do
		if not z.Dead then
			local dist = flat(z.Position - robot.Position).Magnitude
			local score
			if mode == "Boss" then
				score = (if z.Kind == "Boss" then 1e9 elseif z.Kind == "Tank" then 1e6 else 0) - dist
			elseif mode == "Ranged" then
				score = dist -- mais distante (persegue quem está mais longe / perto do ponto A)
			else
				score = -dist -- mais próximo
			end
			if score > bestScore then
				best, bestScore = z, score
			end
		end
	end
	return best
end

-- Distância que cada arma tenta manter do alvo.
local function engageDistance(weapon: Items.WeaponStats): number
	if weapon.Pattern == "Line" then
		return weapon.Range * 0.75
	elseif weapon.Pattern == "Circle" then
		return weapon.Range * 0.45
	end
	return weapon.Range * 0.55
end

-- Mantém dentro do chão da base (espaço local do núcleo).
local function clampToBase(base: BaseService.Base, position: Vector3): Vector3
	local localPos = base.Frame:PointToObjectSpace(position)
	local b = base.Bounds
	local clamped = Vector3.new(
		math.clamp(localPos.X, b.MinX, b.MaxX),
		localPos.Y,
		math.clamp(localPos.Z, b.MinZ, b.MaxZ)
	)
	return base.Frame:PointToWorldSpace(clamped)
end

type DealDamage = (zombie: Zombie, amount: number, stun: number?) -> ()

-- Um passo da simulação: move cada robô e executa os ataques prontos.
function RobotService.Step(
	player: Player,
	zombies: { Zombie },
	now: number,
	dt: number,
	dealDamage: DealDamage
)
	local perPlayer = robots[player]
	local data = DataService.Get(player)
	local base = BaseService.Get(player)
	if not perPlayer or not data or not base then
		return
	end

	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	for cell, robot in perPlayer do
		local weapon = robot.Weapon
		if robot.Broken then
			continue
		end
		local destination = robot.Home
		local target: Zombie? = nil
		if weapon then
			local loadout = (data.Grid :: any)[cell]
			target = pickTarget(robot, if loadout then loadout.Targeting else "Nearest", zombies)
		end

		local move = Vector3.zero
		if target and weapon then
			local toTarget = flat(target.Position - robot.Position)
			local dist = toTarget.Magnitude
			robot.Facing = if dist > 0.01 then toTarget.Unit else robot.Facing
			local want = engageDistance(weapon)
			if dist > want then
				move = toTarget.Unit * math.min(robot.Speed * dt, dist - want)
			end
			if dist <= weapon.Range and now >= robot.NextAttack then
				robot.NextAttack = now + weapon.Cooldown
				local hitPositions: { Vector3 } = {}
				for _, z in Combat.Resolve(weapon, robot.Position, robot.Facing, zombies, target) do
					table.insert(hitPositions, z.Position)
					dealDamage(z, robot.Damage, weapon.Stun)
				end
				Fx.Attack(weapon, robot.Position, robot.Facing, hitPositions)
			end
		else
			-- Sem alvo: volta caminhando para o hexágono.
			local toHome = flat(destination - robot.Position)
			if toHome.Magnitude > 0.5 then
				move = toHome.Unit * math.min(robot.Speed * dt, toHome.Magnitude)
				robot.Facing = toHome.Unit
			end
		end

		-- Separação: não empilhar robôs no mesmo ponto.
		for otherCell, other in perPlayer do
			if otherCell ~= cell and not other.Broken then
				local away = flat(robot.Position - other.Position)
				local d = away.Magnitude
				if d > 0.01 and d < SEPARATION then
					move += away.Unit * (SEPARATION - d) * 0.5
				end
			end
		end

		if move.Magnitude > 0 or robot.Root then
			robot.Position = clampToBase(base, robot.Position + move)
			local root = robot.Root
			if root then
				local ground =
					Vector3.new(robot.Position.X, robot.Home.Y + ROBOT_HEIGHT_OFFSET, robot.Position.Z)
				table.insert(parts, root)
				table.insert(frames, CFrame.lookAt(ground, ground + robot.Facing))
			end
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Move robôs mesmo fora da horda (voltar para casa nos intervalos).
function RobotService.Idle(player: Player, now: number, dt: number)
	RobotService.Step(player, {}, now, dt, function() end)
end

--------------------------------------------------------------------------------
-- Grid: mover / trocar robôs de hexágono
--------------------------------------------------------------------------------

-- Troca o conteúdo de dois hexágonos (mover para vazio ou trocar de lugar).
function RobotService.MoveRobot(player: Player, from: string, to: string): boolean
	local data = DataService.Get(player)
	if not data then
		return false
	end
	local grid = data.Grid :: any
	local a, b = grid[from], grid[to]
	if not a then
		return false
	end
	DataService.Set(player, { "Grid", to }, a)
	DataService.Set(player, { "Grid", from }, b)

	-- Mantém o robô vivo (posição e vida) ao trocar a casa dele.
	local perPlayer = robots[player] or {}
	local ra, rb = perPlayer[from], perPlayer[to]
	perPlayer[to], perPlayer[from] = ra, rb
	local snapshot = escorts[player]
	if snapshot then
		snapshot[to], snapshot[from] = snapshot[from], snapshot[to]
	end
	for cell, robot in { [to] = ra, [from] = rb } :: { [string]: Robot? } do
		if robot then
			robot.Cell = cell
			robot.Home = cellPosition(player, cell) :: Vector3
			if robot.Model then
				robot.Model:SetAttribute("Cell", cell)
			end
			notify(player, robot)
		end
	end
	if not rb and hpListener then
		hpListener(player, from, 0, 0)
	end
	RobotService.SaveHp(player) -- a vida acompanha o robô
	return true
end

--------------------------------------------------------------------------------
-- Escolta no PvP
--------------------------------------------------------------------------------

local FOLLOW_RADIUS = 6 -- distância dos robôs em volta do dono
local ENGAGE_RANGE = 40 -- até onde um robô sai do lado do dono para atacar
local LEASH = 70 -- longe demais do dono: teleporta para perto dele

function RobotService.IsEscorting(player: Player): boolean
	return escorts[player] ~= nil
end

-- Robôs vivos vão para perto do dono (que acabou de entrar na arena).
function RobotService.BeginEscort(player: Player, ownerPosition: Vector3)
	local perPlayer = robots[player]
	if not perPlayer or escorts[player] then
		return
	end
	local snapshot: { [string]: Snapshot } = {}
	local alive: { Robot } = {}
	for cell, robot in perPlayer do
		snapshot[cell] = {
			Ratio = if robot.MaxHp > 0 then robot.Hp / robot.MaxHp else 1,
			Broken = robot.Broken,
		}
		if not robot.Broken then
			table.insert(alive, robot)
		end
	end
	escorts[player] = snapshot
	for i, robot in alive do
		local angle = (i / math.max(1, #alive)) * math.pi * 2
		placeAt(robot, ownerPosition + Vector3.new(math.cos(angle), 0, math.sin(angle)) * FOLLOW_RADIUS)
	end
end

-- Volta para casa com a vida de antes do PvP.
function RobotService.EndEscort(player: Player)
	local snapshot = escorts[player]
	if not snapshot then
		return
	end
	escorts[player] = nil
	for cell, robot in robots[player] or {} do
		local before = snapshot[cell]
		if before then
			robot.Broken = before.Broken
			robot.Hp = if before.Broken then 0 else robot.MaxHp * before.Ratio
		end
		placeAt(robot, robot.Home)
		notify(player, robot)
	end
end

-- Alvos que os inimigos podem atacar: robôs vivos da escolta deste jogador.
function RobotService.EscortTargets(player: Player): { any }
	local list = {}
	if not escorts[player] then
		return list
	end
	for _, robot in robots[player] or {} do
		if not robot.Broken then
			table.insert(
				list,
				{ Position = robot.Position, Dead = false, StunnedUntil = 0, Robot = robot, Owner = player }
			)
		end
	end
	return list
end

type PvpHit = (target: any, robot: Robot) -> ()

local function clampToArena(position: Vector3): Vector3
	local offset = Vector3.new(position.X - Pvp.Center.X, 0, position.Z - Pvp.Center.Z)
	local limit = Pvp.ArenaRadius - 2
	if offset.Magnitude > limit then
		offset = offset.Unit * limit
	end
	return Vector3.new(Pvp.Center.X + offset.X, position.Y, Pvp.Center.Z + offset.Z)
end

-- Um passo da escolta: cada robô ataca o inimigo mais próximo ou acompanha o dono.
function RobotService.StepPvp(
	player: Player,
	owner: Vector3,
	enemies: { any },
	now: number,
	dt: number,
	hit: PvpHit
)
	local perPlayer = robots[player]
	if not perPlayer or not escorts[player] then
		return
	end
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	local alive: { Robot } = {}
	for _, robot in perPlayer do
		if not robot.Broken then
			table.insert(alive, robot)
		end
	end
	table.sort(alive, function(a, b)
		return a.Cell < b.Cell
	end)
	for i, robot in alive do
		if flat(robot.Position - owner).Magnitude > LEASH then
			local angle = (i / #alive) * math.pi * 2
			robot.Position = owner + Vector3.new(math.cos(angle), 0, math.sin(angle)) * FOLLOW_RADIUS
		end
		local weapon = robot.Weapon
		local target: any = nil
		if weapon then
			local best = ENGAGE_RANGE
			for _, enemy in enemies do
				local d = flat(enemy.Position - robot.Position).Magnitude
				if
					not enemy.Dead
					and d < best
					and flat(enemy.Position - owner).Magnitude < ENGAGE_RANGE + 10
				then
					best, target = d, enemy
				end
			end
		end

		local move = Vector3.zero
		if target and weapon then
			local toTarget = flat(target.Position - robot.Position)
			local dist = toTarget.Magnitude
			robot.Facing = if dist > 0.01 then toTarget.Unit else robot.Facing
			local want = engageDistance(weapon)
			if dist > want then
				move = toTarget.Unit * math.min(robot.Speed * 1.2 * dt, dist - want)
			end
			if dist <= weapon.Range and now >= robot.NextAttack then
				robot.NextAttack = now + weapon.Cooldown
				local hitPositions: { Vector3 } = {}
				for _, enemy in Combat.Resolve(weapon, robot.Position, robot.Facing, enemies :: any, target) do
					table.insert(hitPositions, enemy.Position)
					hit(enemy, robot)
				end
				Fx.Attack(weapon, robot.Position, robot.Facing, hitPositions)
			end
		else
			-- Acompanha o dono, cada robô no seu lugar em volta dele.
			local angle = (i / #alive) * math.pi * 2
			local slot = owner + Vector3.new(math.cos(angle), 0, math.sin(angle)) * FOLLOW_RADIUS
			local toSlot = flat(slot - robot.Position)
			if toSlot.Magnitude > 1 then
				move = toSlot.Unit * math.min(robot.Speed * 1.6 * dt, toSlot.Magnitude)
				robot.Facing = toSlot.Unit
			end
		end
		for _, other in alive do
			if other ~= robot then
				local away = flat(robot.Position - other.Position)
				local d = away.Magnitude
				if d > 0.01 and d < SEPARATION then
					move += away.Unit * (SEPARATION - d) * 0.5
				end
			end
		end
		robot.Position = clampToArena(robot.Position + move)
		local root = robot.Root
		if root then
			local ground = Vector3.new(robot.Position.X, robot.Home.Y + ROBOT_HEIGHT_OFFSET, robot.Position.Z)
			table.insert(parts, root)
			table.insert(frames, CFrame.lookAt(ground, ground + robot.Facing))
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function RobotService.Clear(player: Player)
	for _, robot in robots[player] or {} do
		if robot.Model then
			robot.Model:Destroy()
		end
	end
	robots[player] = nil
	escorts[player] = nil
end

RobotService.PaintCells = paintCells

return RobotService
