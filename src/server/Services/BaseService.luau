--!strict
-- 5 bases ao redor do centro. Cada jogador recebe uma base livre.
-- Se o mapa não tiver Workspace.Bases.BaseN, gera uma base provisória (placeholder) com:
--   Spawn (de onde os zumbis saem), Core (o que eles invadem) e Pads 1..6.
-- Quando o mapa definitivo for modelado, basta manter esses nomes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local DataService = require(script.Parent.DataService)

local BASE_COUNT = 5
local BASE_RADIUS = 380 -- distância do centro do mapa
local GROUND_Y = 0

export type Base = {
	Index: number,
	Frame: CFrame, -- origem no núcleo, LookVector apontando para o centro do mapa
	Model: Model,
	Spawn: Vector3,
	Core: Vector3,
	Pads: { [string]: BasePart },
	Zombies: Folder,
	Robots: Folder,
}

local BaseService = {}

local bases: { Base } = {}
local owners: { [number]: Player } = {}
local playerBase: { [Player]: Base } = {}

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

-- Gera a geometria provisória de uma base, virada para o centro do mapa.
local function buildPlaceholder(index: number, parent: Instance): Model
	local angle = math.rad((index - 1) * (360 / BASE_COUNT))
	local position = Vector3.new(math.cos(angle) * BASE_RADIUS, GROUND_Y, math.sin(angle) * BASE_RADIUS)
	local frame = CFrame.lookAt(position, Vector3.new(0, GROUND_Y, 0)) -- LookVector aponta para o centro

	local model = Instance.new("Model")
	model.Name = `Base{index}`

	part({
		Name = "Floor",
		Size = Vector3.new(60, 1, 150),
		CFrame = frame * CFrame.new(0, 0.5, -5),
		Material = Enum.Material.Concrete,
		Color = Color3.fromRGB(110, 105, 95),
	}, model)
	part({
		Name = "Path",
		Size = Vector3.new(8, 0.2, 120),
		CFrame = frame * CFrame.new(0, 1.1, -5),
		Material = Enum.Material.Ground,
		Color = Color3.fromRGB(95, 70, 50),
	}, model)
	part({
		Name = "Spawn",
		Size = Vector3.new(10, 0.4, 10),
		CFrame = frame * CFrame.new(0, 1.2, 65), -- lado de fora
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(120, 40, 40),
		CanCollide = false,
	}, model)
	part({
		Name = "Core",
		Size = Vector3.new(12, 8, 6),
		CFrame = frame * CFrame.new(0, 5, -60), -- lado do centro
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(70, 140, 220),
	}, model)
	-- Detalhes do núcleo (gerador): anel brilhante e chaminés
	part({
		Name = "CoreRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 9, 9),
		CFrame = frame * CFrame.new(0, 9.5, -60) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(90, 200, 255),
		CanCollide = false,
	}, model)
	for _, x in { -4, 4 } do
		part({
			Name = "Chimney",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(6, 1.4, 1.4),
			CFrame = frame * CFrame.new(x, 12, -61.5) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.CorrodedMetal,
			Color = Color3.fromRGB(110, 75, 50),
		}, model)
	end

	-- Cercas de madeira e metal nas laterais (Cyber-Rustic)
	for _, x in { -29.5, 29.5 } do
		for z = -75, 65, 14 do
			part({
				Name = "Fence",
				Size = Vector3.new(0.6, 3, 12),
				CFrame = frame * CFrame.new(x, 2.5, z),
				Material = Enum.Material.WoodPlanks,
				Color = Color3.fromRGB(105, 75, 50),
			}, model)
			part({
				Name = "FencePost",
				Size = Vector3.new(1, 4, 1),
				CFrame = frame * CFrame.new(x, 3, z + 6.5),
				Material = Enum.Material.CorrodedMetal,
				Color = Color3.fromRGB(90, 85, 80),
			}, model)
		end
	end

	-- Máquina da roleta e bancada da forja: o painel abre a tela correspondente no cliente.
	local function station(name: string, offset: Vector3, color: Color3, label: string, window: string)
		local body = part({
			Name = name,
			Size = Vector3.new(5, 6, 3),
			CFrame = frame * CFrame.new(offset + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, math.rad(180), 0),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(70, 65, 60),
		}, model)
		part({
			Name = name .. "Screen",
			Size = Vector3.new(3.6, 2.4, 0.2),
			CFrame = body.CFrame * CFrame.new(0, 1.2, -1.55),
			Material = Enum.Material.Neon,
			Color = color,
			CanCollide = false,
		}, model)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ObjectText = label
		prompt.ActionText = "Abrir"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("OpensWindow", window)
		prompt.Parent = body
	end
	station("RollMachine", Vector3.new(-18, 1, -45), Color3.fromRGB(255, 170, 40), "Roleta", "Roll")
	station(
		"ForgeBench",
		Vector3.new(18, 1, -45),
		Color3.fromRGB(170, 90, 255),
		"Forja e Inventário",
		"Inventory"
	)

	local pads = Instance.new("Folder")
	pads.Name = "Pads"
	pads.Parent = model
	local padOffsets = {
		Vector3.new(-12, 0, 30),
		Vector3.new(12, 0, 30),
		Vector3.new(-12, 0, 5),
		Vector3.new(12, 0, 5),
		Vector3.new(-12, 0, -20),
		Vector3.new(12, 0, -20),
	}
	for i, offset in padOffsets do
		part({
			Name = tostring(i),
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 9, 9),
			CFrame = frame * CFrame.new(offset + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.DiamondPlate,
			Color = Color3.fromRGB(80, 80, 85),
		}, pads)
	end

	model.Parent = parent
	return model
end

local function loadBase(index: number, container: Instance): Base
	local model = container:FindFirstChild(`Base{index}`) :: Model?
	if not model then
		model = buildPlaceholder(index, container)
	end
	assert(model, "base")

	local padsFolder = model:FindFirstChild("Pads") :: Folder
	local pads: { [string]: BasePart } = {}
	for i = 1, Economy.MaxPads do
		pads[tostring(i)] = padsFolder:FindFirstChild(tostring(i)) :: BasePart
	end

	local zombies = Instance.new("Folder")
	zombies.Name = "Zombies"
	zombies.Parent = model
	local robots = Instance.new("Folder")
	robots.Name = "Robots"
	robots.Parent = model

	local spawnPart = model:FindFirstChild("Spawn") :: BasePart
	local corePart = model:FindFirstChild("Core") :: BasePart
	local core = Vector3.new(corePart.Position.X, spawnPart.Position.Y, corePart.Position.Z)
	local towardCenter = (core - spawnPart.Position).Unit
	return {
		Index = index,
		Frame = CFrame.lookAt(core, core + towardCenter),
		Model = model,
		Spawn = spawnPart.Position,
		Core = Vector3.new(corePart.Position.X, spawnPart.Position.Y, corePart.Position.Z),
		Pads = pads,
		Zombies = zombies,
		Robots = robots,
	}
end

local function teleportToBase(player: Player, character: Model)
	local base = playerBase[player]
	if not base then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if root then
		local toSpawn = (base.Spawn - base.Core).Unit
		root.CFrame = CFrame.lookAt(base.Core + toSpawn * 12 + Vector3.new(0, 4, 0), base.Spawn)
	end
end

local function assign(player: Player)
	for i, base in bases do
		if owners[i] == nil then
			owners[i] = player
			playerBase[player] = base
			base.Model:SetAttribute("OwnerUserId", player.UserId)
			if player.Character then
				task.spawn(teleportToBase, player, player.Character)
			end
			return
		end
	end
	player:Kick("Servidor cheio (máximo de 5 bases).")
end

local function release(player: Player)
	local base = playerBase[player]
	if base then
		owners[base.Index] = nil
		base.Model:SetAttribute("OwnerUserId", nil)
		playerBase[player] = nil
	end
end

function BaseService.Start()
	local container = workspace:FindFirstChild("Bases")
	if not container then
		container = Instance.new("Folder")
		container.Name = "Bases"
		container.Parent = workspace
	end
	for i = 1, BASE_COUNT do
		bases[i] = loadBase(i, container :: Instance)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			teleportToBase(player, character)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character)
			teleportToBase(player, character)
		end)
	end

	DataService.OnLoaded(assign)
	Players.PlayerRemoving:Connect(release)
end

function BaseService.Get(player: Player): Base?
	return playerBase[player]
end

return BaseService
