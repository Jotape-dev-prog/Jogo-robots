--!strict
-- Ciclo de PvP — King of the Hill no centro do mapa (GDD 2.5).
--   • 20 min de hordas → as hordas de todos pausam e o centro abre por 10 min.
--     Com menos de 2 jogadores no servidor o centro não abre e o ciclo recomeça.
--   • Captura: ficar 30 s ininterruptos SOZINHO na zona. Com mais de um jogador na zona
--     (inclusive aliados) a captura fica "Contestada" e o tempo pausa. Se quem estava
--     capturando sai da zona, o tempo zera.
--   • Vitória: +15% dinheiro e sorte por 20 min. A zona zera e pode ser capturada de novo.
--   • Morte na arena durante o PvP: perde 5% do dinheiro atual e renasce na base em 5 s.
--   • Aliados não causam dano entre si. Tudo é decidido no servidor (posição real dos personagens).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local Pvp = require(Shared.Config.Pvp)
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local Replica = require(ServerScriptService.ReplicaServer)

local Combat = require(script.Parent.Parent.Combat)
local Buffs = require(script.Parent.Parent.Buffs)
local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)
local HordeService = require(script.Parent.HordeService)
local SocialService = require(script.Parent.SocialService)
local RemoteGuard = require(script.Parent.RemoteGuard)

type Phase = "Hordes" | "Open"

local PvpToken = Replica.Token("PvpState")
local TICK = 0.2

local PvpService = {}

local phase: Phase = "Hordes"
local phaseEnds = 0
local holder: Player? = nil
local progress = 0
local replica: any = nil
local barrier: { BasePart } = {}
local zonePart: BasePart? = nil

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function ui(field: string, value: any)
	if replica and replica.Data[field] ~= value then
		replica:Set({ field }, value)
	end
end

--------------------------------------------------------------------------------
-- Arena (provisória, se o mapa não tiver Workspace.Arena)
--------------------------------------------------------------------------------

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- Vegetação decorativa dentro da arena sai do caminho durante o jogo (o mapa salvo não muda).
local VEGETATION = { Arvore = true, Pinheiro = true, Arbusto = true, Pedra = true }

local function clearVegetation()
	local stash = Instance.new("Folder")
	stash.Name = "ArenaVegetation"
	stash.Parent = game:GetService("ServerStorage")
	local seen: { [Instance]: boolean } = {}
	for _, p in workspace:GetPartBoundsInRadius(Pvp.Center, Pvp.ArenaRadius + 4) do
		local model = p:FindFirstAncestorOfClass("Model")
		local target: Instance = model or p
		if not seen[target] and VEGETATION[target.Name] then
			seen[target] = true
			target.Parent = stash
		end
	end
end

local function buildArena(): Model
	clearVegetation()
	local existing = workspace:FindFirstChild("Arena")
	if existing and existing:IsA("Model") then
		return existing
	end
	local model = Instance.new("Model")
	model.Name = "Arena"
	local c = Pvp.Center
	part({
		Name = "Platform",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, Pvp.ArenaRadius * 2, Pvp.ArenaRadius * 2),
		CFrame = CFrame.new(c + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(85, 80, 75),
	}, model)
	part({
		Name = "Zone",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, Pvp.ZoneRadius * 2, Pvp.ZoneRadius * 2),
		CFrame = CFrame.new(c + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(230, 140, 40),
		Transparency = 0.35,
		CanCollide = false,
	}, model)
	-- Bandeira no centro da zona
	part({
		Name = "FlagPole",
		Size = Vector3.new(0.6, 16, 0.6),
		CFrame = CFrame.new(c + Vector3.new(0, 9, 0)),
		Material = Enum.Material.CorrodedMetal,
		Color = Color3.fromRGB(90, 85, 80),
	}, model)
	part({
		Name = "Flag",
		Size = Vector3.new(5, 3, 0.2),
		CFrame = CFrame.new(c + Vector3.new(2.8, 15.5, 0)),
		Material = Enum.Material.Fabric,
		Color = Color3.fromRGB(200, 70, 60),
		CanCollide = false,
	}, model)
	-- Barreira: anel de paredes de energia que bloqueia o centro fora do horário do PvP.
	local barrierFolder = Instance.new("Folder")
	barrierFolder.Name = "Barrier"
	barrierFolder.Parent = model
	local segments = 36
	local radius = Pvp.ArenaRadius + 1
	local width = 2 * math.pi * radius / segments + 0.5
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local position = c + Vector3.new(math.cos(angle) * radius, 7.5, math.sin(angle) * radius)
		part({
			Name = "Wall",
			Size = Vector3.new(width, 14, 1),
			CFrame = CFrame.lookAt(position, Vector3.new(c.X, position.Y, c.Z)),
			Material = Enum.Material.ForceField,
			Color = Color3.fromRGB(120, 180, 255),
			Transparency = 0.3,
		}, barrierFolder)
	end
	model.Parent = workspace
	return model
end

local function setBarrier(open: boolean)
	for _, wall in barrier do
		wall.CanCollide = not open
		wall.Transparency = if open then 1 else 0.3
	end
end

--------------------------------------------------------------------------------
-- Jogadores na arena
--------------------------------------------------------------------------------

local function rootOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return root, humanoid
end

local function inRadius(position: Vector3, radius: number): boolean
	return flat(position - Pvp.Center).Magnitude <= radius and position.Y < Pvp.Center.Y + 40
end

function PvpService.IsOpen(): boolean
	return phase == "Open"
end

function PvpService.InArena(player: Player): boolean
	local root = rootOf(player)
	return root ~= nil and inRadius(root.Position, Pvp.ArenaRadius + 2)
end

--------------------------------------------------------------------------------
-- Fases
--------------------------------------------------------------------------------

local function resetCapture()
	holder = nil
	progress = 0
	ui("HolderId", 0)
	ui("HolderName", "")
	ui("Progress", 0)
	ui("Contested", false)
end

local function openArena()
	phase = "Open"
	phaseEnds = os.clock() + Pvp.OpenSeconds
	resetCapture()
	setBarrier(true)
	HordeService.SetPaused(true)
	ui("Phase", "Open")
end

local function closeArena()
	phase = "Hordes"
	phaseEnds = os.clock() + Pvp.HordeSeconds
	resetCapture()
	-- Quem ainda está na arena volta para casa antes de a barreira fechar.
	for _, player in Players:GetPlayers() do
		if PvpService.InArena(player) then
			BaseService.TeleportHome(player)
		end
	end
	setBarrier(false)
	HordeService.SetPaused(false)
	ui("Phase", "Hordes")
end

local function win(player: Player)
	Buffs.Set(player, "Cash", Pvp.WinBonus, Pvp.WinBonusSeconds)
	Buffs.Set(player, "Luck", Pvp.WinBonus, Pvp.WinBonusSeconds)
	ui("LastWinner", player.DisplayName)
	ui("LastWinAt", os.clock())
	for _, other in Players:GetPlayers() do
		SocialService.Notify(
			other,
			if other == player
				then "👑 Você dominou o centro! +15% dinheiro e sorte por 20 min"
				else `👑 {player.DisplayName} dominou o centro!`
		)
	end
	resetCapture()
end

local function stepCapture(dt: number)
	local occupants: { Player } = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and inRadius(root.Position, Pvp.ZoneRadius) then
			table.insert(occupants, player)
		end
	end

	-- Quem estava capturando saiu (ou morreu): zera.
	if holder and not table.find(occupants, holder) then
		resetCapture()
	end

	if #occupants == 0 then
		ui("Contested", false)
		return
	end
	if #occupants > 1 then
		ui("Contested", true) -- tempo pausado até restar um
		return
	end
	local only = occupants[1]
	ui("Contested", false)
	if holder ~= only then
		holder = only
		progress = 0
		ui("HolderId", only.UserId)
		ui("HolderName", only.DisplayName)
	end
	progress += dt
	ui("Progress", math.floor(progress * 10) / 10)
	if progress >= Pvp.CaptureSeconds then
		win(only)
	end
end

local function tick(dt: number)
	local remaining = phaseEnds - os.clock()
	ui("Timer", math.max(0, math.ceil(remaining)))
	ui("Players", #Players:GetPlayers())
	if phase == "Hordes" then
		if remaining <= 0 then
			if #Players:GetPlayers() >= Pvp.MinPlayers then
				openArena()
			else
				phaseEnds = os.clock() + Pvp.HordeSeconds
			end
		end
	else
		stepCapture(dt)
		if remaining <= 0 then
			closeArena()
		end
	end
	if zonePart then
		zonePart.Color = if replica and replica.Data.Contested
			then Color3.fromRGB(220, 60, 50)
			elseif holder then Color3.fromRGB(80, 200, 100)
			else Color3.fromRGB(230, 140, 40)
	end
end

--------------------------------------------------------------------------------
-- Combate entre jogadores
--------------------------------------------------------------------------------

-- Golpe do avatar contra outros jogadores na arena. Retorna quantos acertou.
function PvpService.PlayerAttack(
	attacker: Player,
	weapon: Items.WeaponStats,
	tier: number,
	origin: Vector3,
	dir: Vector3
): number
	if phase ~= "Open" or not inRadius(origin, Pvp.ArenaRadius + 2) then
		return 0
	end
	local targets: { any } = {}
	local byTarget: { [any]: Humanoid } = {}
	for _, other in Players:GetPlayers() do
		if other ~= attacker and not SocialService.IsAllied(attacker, other) then
			local root, humanoid = rootOf(other)
			if root and humanoid and inRadius(root.Position, Pvp.ArenaRadius + 2) then
				local target = { Position = root.Position, Dead = false, StunnedUntil = 0 }
				table.insert(targets, target)
				byTarget[target] = humanoid
			end
		end
	end
	if #targets == 0 then
		return 0
	end
	local damage = weapon.Damage * Rarity.Multiplier(tier) ^ 0.75 * Pvp.DamageFactor
	local hits = Combat.Resolve(weapon, origin, dir, targets :: any, nil)
	for _, target in hits do
		local humanoid = byTarget[target]
		if humanoid then
			humanoid:TakeDamage(damage)
		end
	end
	return #hits
end

--------------------------------------------------------------------------------
-- Viagem base ↔ arena
--------------------------------------------------------------------------------

local function handleTravel(player: Player, toArena: any): RemoteGuard.Result
	if typeof(toArena) ~= "boolean" then
		return RemoteGuard.Fail("Pedido inválido")
	end
	local root = rootOf(player)
	if not root then
		return RemoteGuard.Fail("Sem personagem")
	end
	if not toArena then
		BaseService.TeleportHome(player)
		return { Ok = true }
	end
	if phase ~= "Open" then
		return RemoteGuard.Fail("O centro ainda está fechado")
	end
	-- Chega na borda da arena, do lado da própria base.
	local base = BaseService.Get(player)
	local fromDir = if base then flat(base.Core - Pvp.Center) else Vector3.xAxis
	fromDir = if fromDir.Magnitude > 0.01 then fromDir.Unit else Vector3.xAxis
	local spot = Pvp.Center + fromDir * (Pvp.ArenaRadius - 8) + Vector3.new(0, 4, 0)
	root.CFrame = CFrame.lookAt(spot, Pvp.Center + Vector3.new(0, 4, 0))
	return { Ok = true }
end

--------------------------------------------------------------------------------
-- Início
--------------------------------------------------------------------------------

local function watchDeaths(player: Player)
	local function onCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then
			return
		end
		humanoid.Died:Connect(function()
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if phase == "Open" and root and inRadius(root.Position, Pvp.ArenaRadius + 2) then
				local lost = DataService.LosePercent(player, Pvp.DeathCashLossPercent)
				SocialService.Notify(player, `💀 Você caiu na arena e perdeu {lost} de dinheiro`)
			end
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

function PvpService.Start()
	Players.RespawnTime = Pvp.RespawnSeconds

	local arena = buildArena()
	local barrierFolder = arena:FindFirstChild("Barrier")
	if barrierFolder then
		for _, wall in barrierFolder:GetChildren() do
			if wall:IsA("BasePart") then
				table.insert(barrier, wall)
			end
		end
	end
	zonePart = arena:FindFirstChild("Zone") :: BasePart?
	setBarrier(false) -- começa fechada

	phaseEnds = os.clock() + Pvp.HordeSeconds
	replica = Replica.New({
		Token = PvpToken,
		Data = {
			Phase = "Hordes",
			Timer = Pvp.HordeSeconds,
			Required = Pvp.CaptureSeconds,
			MinPlayers = Pvp.MinPlayers,
			Players = 0,
			HolderId = 0,
			HolderName = "",
			Progress = 0,
			Contested = false,
			LastWinner = "",
			LastWinAt = 0,
		},
	})
	replica:Replicate()

	RemoteGuard.Handle("PvpTravel", 3, 0.5, handleTravel)
	if RunService:IsStudio() then
		RemoteGuard.Handle("DevSkipPvpPhase", 3, 0.5, function()
			if phase == "Hordes" then
				openArena()
			else
				closeArena()
			end
			return { Ok = true }
		end)
	end

	DataService.OnLoaded(watchDeaths)

	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < TICK then
			return
		end
		local step = accumulated
		accumulated = 0
		local ok, err = pcall(tick, step)
		if not ok then
			warn("[PvpService]", err)
		end
	end)
end

return PvpService
