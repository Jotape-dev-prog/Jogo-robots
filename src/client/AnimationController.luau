--!strict
-- Animações procedurais (só no cliente, sem custo de rede):
--   • Robôs (tag "RobotRig"): o servidor monta braços, pernas e cabeça em juntas Motor6D e só move
--     a raiz. Aqui cada cliente balança as juntas: andar (pela velocidade da raiz), respirar parado,
--     golpe da arma (avisado pelo FxEvent) e "trabalhar" para os robôs da fábrica.
--   • Zumbis (tag "ZombieRig"): mesmas juntas; andam arrastando as pernas com os braços esticados
--     para a frente e dão patadas quando o servidor marca o atributo "Atk".
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
	Zombie: boolean,
	AttackStart: number,
	AttackPattern: string,
}

local AnimationController = {}

local rigs: { [Instance]: Rig } = {}
local avatarAttacks: { [Model]: { Start: number, Pattern: string } } = {}

local function track(model: Instance)
	-- Robô: Model com a raiz "Root". Zumbi: a própria peça marcada é a raiz.
	local root: Instance? = model
	if model:IsA("Model") then
		root = model.PrimaryPart or model:WaitForChild("Root", 5)
	end
	if not root or not root:IsA("BasePart") then
		return
	end
	local joints: { [string]: Motor6D } = {}
	for _, name in { "ArmL", "ArmR", "LegL", "LegR", "Head" } do
		-- as juntas chegam um instante depois da raiz pela rede
		local joint = root:FindFirstChild(name) or root:WaitForChild(name, 2)
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
		Zombie = model:HasTag("ZombieRig"),
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

-- Braço de zumbi: `lift` levanta/abaixa (positivo = para cima), `spread` abre para o lado.
-- O braço pode ter sido gerado em "T" (deitado) ou caído; nos dois casos ele fica para a frente.
local function zombieArm(joint: Motor6D?, lift: number, spread: number)
	if not joint then
		return
	end
	local side = joint:GetAttribute("Side")
	local s = if side == -1 then -1 else 1
	if joint:GetAttribute("TPose") == true then
		joint.Transform = CFrame.Angles(lift, 0, 0) * CFrame.Angles(0, s * (math.pi / 2 - spread), 0)
	else
		joint.Transform = CFrame.Angles(math.pi / 2 + lift, 0, 0) * CFrame.Angles(0, 0, s * spread)
	end
end

local function stepZombie(rig: Rig, now: number, dt: number)
	local position = rig.Root.Position
	local delta = position - rig.Last
	rig.Last = position
	local speed = Vector3.new(delta.X, 0, delta.Z).Magnitude / math.max(dt, 1 / 240)
	rig.Speed += (math.min(speed, 30) - rig.Speed) * math.min(1, dt * 6)
	local joints = rig.Joints
	local seed = rig.Seed
	if rig.Root:GetAttribute("Atk") == true then
		-- Patadas alternadas no robô
		local a = math.sin(now * 9 + seed)
		zombieArm(joints.ArmL, 0.1 + math.max(0, a) * 0.7 - math.max(0, -a) * 0.5, 0.05)
		zombieArm(joints.ArmR, 0.1 + math.max(0, -a) * 0.7 - math.max(0, a) * 0.5, 0.05)
		set(joints, "LegL", CFrame.Angles(0.15, 0, 0))
		set(joints, "LegR", CFrame.Angles(-0.25, 0, 0))
		set(joints, "Head", CFrame.Angles(-0.2 + a * 0.15, 0, 0))
	else
		-- Arrastando os pés, braços esticados balançando, cabeça caída para o lado
		rig.Phase += dt * (2.5 + rig.Speed * 0.9)
		local moving = math.clamp(rig.Speed / 4, 0, 1)
		local swing = math.sin(rig.Phase) * 0.55 * moving
		set(joints, "LegL", CFrame.Angles(swing, 0, 0))
		set(joints, "LegR", CFrame.Angles(-swing, 0, 0))
		zombieArm(
			joints.ArmL,
			-0.05 + math.sin(rig.Phase + seed) * 0.12,
			0.1 + math.sin(now * 1.3 + seed) * 0.06
		)
		zombieArm(
			joints.ArmR,
			-0.05 + math.sin(rig.Phase + seed + 2) * 0.12,
			0.1 + math.cos(now * 1.1 + seed) * 0.06
		)
		set(joints, "Head", CFrame.Angles(0.1, 0, 0.18 * math.sin(now * 1.7 + seed)))
	end
end

local function stepRig(rig: Rig, now: number, dt: number)
	if rig.Zombie then
		stepZombie(rig, now, dt)
		return
	end
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
		if not rig.Zombie and d < bestDistance then
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
	for _, zombie in CollectionService:GetTagged("ZombieRig") do
		task.spawn(track, zombie)
	end
	CollectionService:GetInstanceAddedSignal("ZombieRig"):Connect(function(zombie)
		task.spawn(track, zombie)
	end)
	CollectionService:GetInstanceRemovedSignal("ZombieRig"):Connect(function(zombie)
		rigs[zombie] = nil
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
