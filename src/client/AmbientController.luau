--!strict
-- Vida no cenário (só no cliente, sem custo de rede):
--   • caixas andando nas esteiras das fábricas com linha ativa;
--   • vaga-lumes em volta do jogador à noite e poeira dourada de dia.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local AmbientController = {}

local CRATE_INTERVAL = 1.6
local MAX_DISTANCE = 140

local folder: Folder

local function crate(belt: BasePart)
	local size = 1 + math.random() * 0.4
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = Vector3.new(size, size, size)
	p.Material = Enum.Material.WoodPlanks
	p.Color = Color3.fromRGB(150 + math.random(0, 30), 105, 65)
	-- da frente da esteira até a máquina (fundo, -Z local)
	local start = belt.CFrame * CFrame.new(0, belt.Size.Y / 2 + 0.2 + size / 2, belt.Size.Z / 2 - 1)
	local finish = belt.CFrame * CFrame.new(0, belt.Size.Y / 2 + 0.2 + size / 2, -belt.Size.Z / 2 + 0.6)
	p.CFrame = start
	p.Parent = folder
	local tween = TweenService:Create(p, TweenInfo.new(4, Enum.EasingStyle.Linear), { CFrame = finish })
	tween:Play()
	tween.Completed:Once(function()
		p:Destroy()
	end)
end

local function activeBelts(): { BasePart }
	local list = {}
	local bases = Workspace:FindFirstChild("Bases")
	if not bases then
		return list
	end
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	for _, base in bases:GetChildren() do
		local factory = base:FindFirstChild("Factory")
		if factory then
			for _, child in factory:GetChildren() do
				if
					child:IsA("BasePart")
					and child:GetAttribute("Active") == true
					and (child.Position - eye).Magnitude < MAX_DISTANCE
				then
					table.insert(list, child)
				end
			end
		end
	end
	return list
end

local function makeAmbientEmitter(): ParticleEmitter
	local anchor = Instance.new("Part")
	anchor.Name = "AmbientParticles"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(60, 8, 60)
	anchor.Parent = folder
	local emitter = Instance.new("ParticleEmitter")
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.18),
		NumberSequenceKeypoint.new(0.8, 0.18),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(4, 7)
	emitter.Speed = NumberRange.new(0.3, 1)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 0.2, 0)
	emitter.Rate = 10
	emitter.Parent = anchor
	return emitter
end

function AmbientController.Start()
	folder = Instance.new("Folder")
	folder.Name = "AmbientFx"
	folder.Parent = Workspace
	local emitter = makeAmbientEmitter()
	local anchor = emitter.Parent :: BasePart

	-- Caixas nas esteiras
	task.spawn(function()
		while true do
			task.wait(CRATE_INTERVAL)
			for _, belt in activeBelts() do
				crate(belt)
			end
		end
	end)

	-- Partículas ambiente seguem o jogador; cor e quantidade mudam com a hora do dia
	task.spawn(function()
		while true do
			task.wait(0.5)
			local character = player.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
			if root then
				anchor.CFrame = CFrame.new(root.Position + Vector3.new(0, 1, 0))
			end
			local clock = Lighting.ClockTime
			local night = clock < 5.5 or clock > 19
			emitter.Color = ColorSequence.new(
				if night then Color3.fromRGB(190, 255, 120) else Color3.fromRGB(255, 220, 150)
			)
			emitter.Rate = if night then 14 else 5
			emitter.Transparency = NumberSequence.new(if night then 0 else 0.4)
		end
	end)
end

return AmbientController
