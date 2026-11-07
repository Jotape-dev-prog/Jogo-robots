--!strict
-- Horda instanciada por jogador.
--   • Wave Spawning Limit: no máximo 15 zumbis vivos por base; o resto espera na fila.
--   • 3 invasões = derrota: -10% do dinheiro, horda pausa, volta a um checkpoint desbloqueado.
--   • Checkpoint a cada 10 hordas (1, 11, 21...). Boss na última horda de cada bloco.
--   • Robôs restauram 100% de HP no início de cada horda.
-- Um único Heartbeat move todos os zumbis de todas as bases (BulkMoveTo) — barato para 5 × 15.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local HordeConfig = require(Shared.Config.Horde)
local Economy = require(Shared.Config.Economy)
local Replica = require(ServerScriptService.ReplicaServer)

local Types = require(script.Parent.Parent.Types)
local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)
local RobotService = require(script.Parent.RobotService)
local RemoteGuard = require(script.Parent.RemoteGuard)

type Zombie = Types.Zombie
type State = "Intermission" | "Active" | "Defeated"

type Run = {
	Player: Player,
	Base: BaseService.Base,
	Replica: any,
	State: State,
	Wave: number,
	Queue: { HordeConfig.ZombieSpec },
	Zombies: { Zombie },
	Invasions: number,
	SpawnTimer: number,
	Timer: number, -- intermissão / retomada após derrota
	LastUiTimer: number,
}

local HordeStateToken = Replica.Token("HordeState")

local ZOMBIE_LOOK = {
	Normal = { Size = Vector3.new(2, 5, 1.6), Color = Color3.fromRGB(85, 130, 70) },
	Fast = { Size = Vector3.new(1.6, 4.4, 1.4), Color = Color3.fromRGB(150, 160, 60) },
	Tank = { Size = Vector3.new(3.4, 6.4, 2.6), Color = Color3.fromRGB(70, 90, 60) },
	Boss = { Size = Vector3.new(6, 10, 4.5), Color = Color3.fromRGB(120, 30, 40) },
}
local ROBOT_AGGRO_RANGE = 14 -- zumbis desviam para atacar robôs próximos
local ROBOT_ATTACK_RANGE = 4

local HordeService = {}

local runs: { [Player]: Run } = {}
local paused = false
local nextZombieId = 0

--------------------------------------------------------------------------------
-- UI (replica de estado da horda — só o dono recebe)
--------------------------------------------------------------------------------

local function ui(run: Run, key: string, value: any)
	if run.Replica:IsActive() and run.Replica.Data[key] ~= value then
		run.Replica:Set({ key }, value)
	end
end

local function aliveCount(run: Run): number
	return #run.Zombies
end

local function syncCounts(run: Run)
	ui(run, "Alive", aliveCount(run))
	ui(run, "Remaining", #run.Queue + aliveCount(run))
end

--------------------------------------------------------------------------------
-- Zumbis
--------------------------------------------------------------------------------

local function removeZombie(run: Run, index: number)
	local z = run.Zombies[index]
	z.Dead = true
	z.Part:Destroy()
	-- remoção O(1): troca com o último
	run.Zombies[index] = run.Zombies[#run.Zombies]
	run.Zombies[#run.Zombies] = nil
end

local function clearZombies(run: Run)
	for _, z in run.Zombies do
		z.Dead = true
		z.Part:Destroy()
	end
	table.clear(run.Zombies)
	table.clear(run.Queue)
end

local function spawnZombie(run: Run, spec: HordeConfig.ZombieSpec)
	local look = ZOMBIE_LOOK[spec.Kind]
	nextZombieId += 1
	local p = Instance.new("Part")
	p.Name = spec.Kind
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.Size = look.Size
	p.Color = look.Color
	p.Material = Enum.Material.SmoothPlastic
	local jitter = Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
	local position = run.Base.Spawn + jitter
	p.CFrame = CFrame.lookAt(
		position + Vector3.new(0, look.Size.Y / 2, 0),
		run.Base.Core + Vector3.new(0, look.Size.Y / 2, 0)
	)
	p.Parent = run.Base.Zombies

	table.insert(run.Zombies, {
		Id = nextZombieId,
		Kind = spec.Kind,
		Hp = spec.Hp,
		MaxHp = spec.Hp,
		Speed = spec.Speed,
		Reward = spec.Reward,
		ContactDps = spec.ContactDps,
		Position = position,
		StunnedUntil = 0,
		Part = p,
		Dead = false,
	})
end

local function killReward(player: Player, zombie: Zombie)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local bonus = 1 + (data.Upgrades.KillValue or 0) * Economy.Upgrades.KillValue.PerLevel
	DataService.AddCash(player, zombie.Reward * bonus, true)
	DataService.Increment(player, { "Stats", "Kills" }, 1)
end

--------------------------------------------------------------------------------
-- Fluxo da horda
--------------------------------------------------------------------------------

local function startWave(run: Run, wave: number)
	clearZombies(run)
	run.Wave = wave
	run.Queue = HordeConfig.Build(wave)
	run.Invasions = 0
	run.SpawnTimer = 0
	run.State = "Active"
	DataService.Set(run.Player, { "Horde", "Current" }, wave)
	RobotService.RestoreAll(run.Player)

	ui(run, "Wave", wave)
	ui(run, "State", "Active")
	ui(run, "Invasions", 0)
	ui(run, "Boss", HordeConfig.IsBossWave(wave))
	syncCounts(run)
end

local function enterIntermission(run: Run, nextWave: number, seconds: number)
	run.State = "Intermission"
	run.Timer = seconds
	run.Wave = nextWave
	ui(run, "State", "Intermission")
	ui(run, "Wave", nextWave)
	ui(run, "Timer", math.ceil(seconds))
end

local function completeWave(run: Run)
	local player = run.Player
	local data = DataService.Get(player)
	if not data then
		return
	end
	local nextWave = run.Wave + 1
	if nextWave > data.Horde.Highest then
		DataService.Set(player, { "Horde", "Highest" }, nextWave)
	end
	if HordeConfig.IsCheckpointWave(nextWave) and nextWave > data.Horde.HighestCheckpoint then
		DataService.Set(player, { "Horde", "HighestCheckpoint" }, nextWave)
	end
	DataService.Set(player, { "Horde", "Current" }, nextWave)
	enterIntermission(run, nextWave, HordeConfig.IntermissionSeconds)
end

local function defeat(run: Run)
	local player = run.Player
	clearZombies(run)
	local lost = DataService.LosePercent(player, Economy.DefeatCashLossPercent)
	DataService.Increment(player, { "Stats", "Defeats" }, 1)
	local data = DataService.Get(player)
	local checkpoint = if data then data.Horde.HighestCheckpoint else 1

	run.State = "Defeated"
	run.Timer = HordeConfig.DefeatAutoResumeSeconds
	run.Wave = checkpoint
	DataService.Set(player, { "Horde", "Current" }, checkpoint)
	ui(run, "State", "Defeated")
	ui(run, "LastLoss", lost)
	ui(run, "Wave", checkpoint)
	ui(run, "Timer", math.ceil(run.Timer))
	syncCounts(run)
end

local function stepRun(run: Run, dt: number, now: number)
	if run.State ~= "Active" then
		run.Timer -= dt
		local shown = math.max(0, math.ceil(run.Timer))
		if shown ~= run.LastUiTimer then
			run.LastUiTimer = shown
			ui(run, "Timer", shown)
		end
		if run.Timer <= 0 then
			startWave(run, run.Wave)
		end
		return
	end

	-- Spawn com limite simultâneo
	run.SpawnTimer -= dt
	if run.SpawnTimer <= 0 and #run.Queue > 0 and aliveCount(run) < HordeConfig.MaxAlivePerBase then
		spawnZombie(run, table.remove(run.Queue, 1) :: HordeConfig.ZombieSpec)
		run.SpawnTimer = HordeConfig.SpawnInterval
		syncCounts(run)
	end

	-- Robôs atacam
	local killedAny = false
	RobotService.Step(run.Player, run.Zombies, now, function(z: Zombie, amount: number, stun: number?)
		if z.Dead then
			return
		end
		z.Hp -= amount
		if stun then
			z.StunnedUntil = math.max(z.StunnedUntil, now + stun)
		end
		if z.Hp <= 0 then
			z.Dead = true
			killedAny = true
			killReward(run.Player, z)
		end
	end)
	if killedAny then
		for i = #run.Zombies, 1, -1 do
			if run.Zombies[i].Dead then
				removeZombie(run, i)
			end
		end
		syncCounts(run)
	end

	-- Movimento, ataque a robôs, dano por contato no avatar e invasões
	local robots = RobotService.GetRobots(run.Player)
	local character = run.Player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil

	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	local i = 1
	while i <= #run.Zombies do
		local z = run.Zombies[i]
		local invaded = false
		if now >= z.StunnedUntil then
			-- alvo: robô vivo próximo, senão o núcleo
			local goal = run.Base.Core
			local attacking: RobotService.Robot? = nil
			for _, robot in robots do
				if not robot.Broken then
					local d = (Vector3.new(robot.Position.X, z.Position.Y, robot.Position.Z) - z.Position).Magnitude
					if d <= ROBOT_AGGRO_RANGE then
						goal = Vector3.new(robot.Position.X, z.Position.Y, robot.Position.Z)
						if d <= ROBOT_ATTACK_RANGE then
							attacking = robot
						end
						break
					end
				end
			end

			if attacking then
				RobotService.Damage(run.Player, attacking, z.ContactDps * dt)
			else
				local offset = goal - z.Position
				local distance = offset.Magnitude
				local stepLen = z.Speed * dt
				if distance <= stepLen then
					z.Position = goal
					if goal == run.Base.Core then
						invaded = true
					end
				else
					z.Position += offset.Unit * stepLen
				end
				local half = z.Part.Size.Y / 2
				table.insert(parts, z.Part)
				table.insert(
					frames,
					CFrame.lookAt(z.Position + Vector3.new(0, half, 0), goal + Vector3.new(0, half, 0))
				)
			end
		end

		if root and humanoid and humanoid.Health > 0 then
			if (root.Position - z.Position).Magnitude <= HordeConfig.ContactRange + z.Part.Size.X / 2 then
				humanoid:TakeDamage(z.ContactDps * dt)
			end
		end

		if invaded then
			removeZombie(run, i)
			run.Invasions += 1
			ui(run, "Invasions", run.Invasions)
			syncCounts(run)
			if run.Invasions >= HordeConfig.InvasionsToLose then
				defeat(run)
				return
			end
		else
			i += 1
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end

	if #run.Queue == 0 and #run.Zombies == 0 then
		completeWave(run)
	end
end

--------------------------------------------------------------------------------
-- Jogadores
--------------------------------------------------------------------------------

local function begin(player: Player)
	local base = BaseService.Get(player)
	local data = DataService.Get(player)
	if not base or not data then
		return
	end

	local replica = Replica.New({
		Token = HordeStateToken,
		Tags = { UserId = player.UserId },
		Data = {
			Wave = data.Horde.Current,
			State = "Intermission",
			Invasions = 0,
			MaxInvasions = HordeConfig.InvasionsToLose,
			Alive = 0,
			Remaining = 0,
			Timer = 0,
			Boss = false,
			LastLoss = 0,
			Paused = paused,
			Pads = {},
		},
	})
	if Replica.ReadyPlayers[player] then
		replica:Subscribe(player)
	else
		local connection
		connection = Replica.NewReadyPlayer:Connect(function(ready)
			if ready == player then
				connection:Disconnect()
				if replica:IsActive() then
					replica:Subscribe(player)
				end
			end
		end)
	end

	local run: Run = {
		Player = player,
		Base = base,
		Replica = replica,
		State = "Intermission",
		Wave = data.Horde.Current,
		Queue = {},
		Zombies = {},
		Invasions = 0,
		SpawnTimer = 0,
		Timer = 0,
		LastUiTimer = -1,
	}
	runs[player] = run
	RobotService.RefreshAll(player)
	enterIntermission(run, data.Horde.Current, HordeConfig.IntermissionSeconds + 2)
end

local function finish(player: Player)
	local run = runs[player]
	if run then
		clearZombies(run)
		run.Replica:Destroy()
		runs[player] = nil
	end
	RobotService.Clear(player)
end

local function handleStartFromCheckpoint(player: Player, wave: any): RemoteGuard.Result
	local run = runs[player]
	local data = DataService.Get(player)
	if not run or not data then
		return RemoteGuard.Fail("Sem horda")
	end
	if run.State == "Active" then
		return RemoteGuard.Fail("Só é possível trocar de checkpoint fora de uma horda")
	end
	if
		not RemoteGuard.IsInt(wave, 1, data.Horde.HighestCheckpoint) or not HordeConfig.IsCheckpointWave(wave)
	then
		return RemoteGuard.Fail("Checkpoint não desbloqueado")
	end
	startWave(run, wave)
	return { Ok = true }
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

-- Pausa/retoma todas as hordas (usado pelo ciclo de PvP).
function HordeService.SetPaused(value: boolean)
	paused = value
	for _, run in runs do
		ui(run, "Paused", value)
	end
end

function HordeService.IsPaused(): boolean
	return paused
end

function HordeService.Start()
	RobotService.SetHpListener(function(player, pad, hp, maxHp)
		local run = runs[player]
		if not run or not run.Replica:IsActive() then
			return
		end
		-- Só replica quando o valor inteiro muda (evita enviar a cada frame).
		local shownHp, shownMax = math.ceil(hp), math.ceil(maxHp)
		local current = run.Replica.Data.Pads[pad]
		if current and current.Hp == shownHp and current.MaxHp == shownMax then
			return
		end
		run.Replica:Set({ "Pads", pad }, { Hp = shownHp, MaxHp = shownMax })
	end)
	RemoteGuard.Handle("StartFromCheckpoint", 3, 0.5, handleStartFromCheckpoint)

	DataService.OnLoaded(begin)
	DataService.OnReleasing(finish)

	RunService.Heartbeat:Connect(function(dt)
		if paused then
			return
		end
		local now = os.clock()
		for _, run in runs do
			local ok, err = pcall(stepRun, run, dt, now)
			if not ok then
				warn("[HordeService] erro na horda de", run.Player.UserId, err)
			end
		end
	end)
end

return HordeService
