--!strict
-- Animações procedurais (só no cliente, sem custo de rede):
--   • Robôs (tag "RobotRig"): o servidor monta braços, pernas e cabeça em juntas Motor6D e só move
--     a raiz. Aqui cada cliente balança as juntas: andar (pela velocidade da raiz), respirar parado,
--     golpe da arma (avisado pelo FxEvent) e "trabalhar" para os robôs da fábrica.
--   • Avatares: golpe do braço direito por cima da animação padrão (Motor6D.Transform no Stepped).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MAX_DISTANCE = 170
local ATTACK_SECONDS = { Cone = 0.45, Circle = 0.6, Line = 0.3 }

type Rig = {
	Root: BasePart,
	Joints: { [string]: Motor6D },
	Last: Vector3,
	Speed: number,
	Phase: number,
	Seed: number,
	Worker: boolean,
	AttackStart: number,
	AttackPattern: string,
}

local AnimationController = {}

local rigs: { [Instance]: Rig } = {}
local avatarAttacks: { [Model]: { Start: number, Pattern: string } } = {}

local function track(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local root = model.PrimaryPart or model:WaitForChild("Root", 5)
	if not root or not root:IsA("BasePart") then
		return
	end
	local joints: { [string]: Motor6D } = {}
	for _, name in { "ArmL", "ArmR", "LegL", "LegR", "Head" } do
		local joint = root:FindFirstChild(name)
		if joint and joint:IsA("Motor6D") then
			joints[name] = joint
		end
	end
	rigs[model] = {
		Root = root,
		Joints = joints,
		Last = root.Position,
		Speed = 0,
		Phase = 0,
		Seed = math.random() * 10,
		Worker = model:GetAttribute("Worker") == true,
		AttackStart = -10,
		AttackPattern = "Cone",
	}
end

-- Ângulo do braço da arma ao longo do golpe (t de 0 a 1). Positivo = braço para a frente/cima.
local function attackAngle(pattern: string, t: number): number
	if pattern == "Line" then
		return -0.3 * (1 - t) -- coice do rifle
	end
	local top = if pattern == "Circle" then 2.1 else 1.6
	local low = if pattern == "Circle" then -0.2 else -0.5
	if t < 0.3 then
		return top * (t / 0.3) -- levanta
	elseif t < 0.6 then
		return top + (low - top) * ((t - 0.3) / 0.3) -- desce com força
	end
	return low * (1 - (t - 0.6) / 0.4) -- volta
end

local function set(joints: { [string]: Motor6D }, name: string, transform: CFrame)
	local joint = joints[name]
	if joint then
		joint.Transform = transform
	end
end

local function stepRig(rig: Rig, now: number, dt: number)
	local position = rig.Root.Position
	local delta = position - rig.Last
	rig.Last = position
	local speed = Vector3.new(delta.X, 0, delta.Z).Magnitude / math.max(dt, 1 / 240)
	if speed > 60 then
		speed = 0 -- teleporte (voltar ao hexágono, ir para a arena)
	end
	rig.Speed += (speed - rig.Speed) * math.min(1, dt * 8)

	local joints = rig.Joints
	local armL, armR, legL, legR, head = 0, 0, 0, 0, CFrame.identity
	if rig.Worker then
		-- Fábrica: os dois braços martelando na esteira
		armL = 0.9 + math.sin(now * 6 + rig.Seed) * 0.45
		armR = 0.9 + math.sin(now * 6 + rig.Seed + math.pi) * 0.45
		head = CFrame.Angles(0.15, math.sin(now * 1.5 + rig.Seed) * 0.2, 0)
	elseif rig.Speed > 0.8 then
		-- Andando: pernas e braços alternados; passo mais rápido quanto mais rápido anda
		rig.Phase += dt * (3 + rig.Speed * 0.75)
		local amount = math.clamp(rig.Speed / 7, 0.35, 1)
		local swing = math.sin(rig.Phase) * 0.75 * amount
		legL, legR = swing, -swing
		armL, armR = -swing * 0.8, swing * 0.8
		head = CFrame.Angles(math.sin(rig.Phase * 2) * 0.04, 0, 0)
	else
		-- Parado: respiração e cabeça olhando em volta
		local breathe = math.sin(now * 2 + rig.Seed) * 0.06
		armL, armR = breathe, -breathe
		head = CFrame.Angles(0, math.sin(now * 0.8 + rig.Seed) * 0.25, 0)
	end

	local duration = ATTACK_SECONDS[rig.AttackPattern] or 0.45
	local t = (now - rig.AttackStart) / duration
	if t >= 0 and t < 1 then
		armR = attackAngle(rig.AttackPattern, t)
		if rig.AttackPattern == "Circle" then
			armL = armR * 0.8 -- martelo: os dois braços
		end
	end

	set(joints, "ArmL", CFrame.Angles(armL, 0, 0))
	set(joints, "ArmR", CFrame.Angles(armR, 0, 0))
	set(joints, "LegL", CFrame.Angles(legL, 0, 0))
	set(joints, "LegR", CFrame.Angles(legR, 0, 0))
	set(joints, "Head", head)
end

-- Golpe de um robô: o FxEvent traz a posição de onde saiu; anima o robô que está ali.
function AnimationController.RobotAttack(origin: Vector3, pattern: string)
	local best: Rig? = nil
	local bestDistance = 3
	for _, rig in rigs do
		local d = (rig.Root.Position - origin).Magnitude
		if d < bestDistance then
			best, bestDistance = rig, d
		end
	end
	if best then
		best.AttackStart = os.clock()
		best.AttackPattern = pattern
	end
end

-- Golpe do avatar de qualquer jogador (o próprio chama na hora; os outros chegam pelo FxEvent).
function AnimationController.AvatarAttack(player: Player, pattern: string)
	local character = player.Character
	if character then
		avatarAttacks[character] = { Start = os.clock(), Pattern = pattern }
	end
end

local function rightShoulder(character: Model): (Motor6D?, boolean)
	local upper = character:FindFirstChild("RightUpperArm")
	local r15 = if upper then upper:FindFirstChild("RightShoulder") else nil
	if r15 and r15:IsA("Motor6D") then
		return r15, false
	end
	local torso = character:FindFirstChild("Torso")
	local r6 = if torso then torso:FindFirstChild("Right Shoulder") else nil
	if r6 and r6:IsA("Motor6D") then
		return r6, true
	end
	return nil, false
end

function AnimationController.Start()
	for _, model in CollectionService:GetTagged("RobotRig") do
		task.spawn(track, model)
	end
	CollectionService:GetInstanceAddedSignal("RobotRig"):Connect(function(model)
		task.spawn(track, model)
	end)
	CollectionService:GetInstanceRemovedSignal("RobotRig"):Connect(function(model)
		rigs[model] = nil
	end)

	RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		local now = os.clock()
		for model, rig in rigs do
			if not rig.Root.Parent then
				rigs[model] = nil
			elseif (rig.Root.Position - eye).Magnitude < MAX_DISTANCE then
				stepRig(rig, now, dt)
			end
		end
	end)

	-- Depois que a animação padrão do Roblox é aplicada, soma o golpe no ombro direito.
	RunService.Stepped:Connect(function()
		local now = os.clock()
		for character, attack in avatarAttacks do
			local duration = ATTACK_SECONDS[attack.Pattern] or 0.45
			local t = (now - attack.Start) / duration
			local shoulder, isR6 = rightShoulder(character)
			if t >= 1 or not shoulder or not character.Parent then
				avatarAttacks[character] = nil
			else
				local angle = attackAngle(attack.Pattern, t)
				shoulder.Transform = shoulder.Transform
					* (if isR6 then CFrame.Angles(0, 0, angle) else CFrame.Angles(angle, 0, 0))
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		if player.Character then
			avatarAttacks[player.Character] = nil
		end
	end)
end

return AnimationController
