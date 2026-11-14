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
local ATTACK_SECONDS = { Cone = 0.45, Circle = 0.6, Line = 1.5 }
local AIM_HOLD = 1.5 -- o robô fica com o rifle no ombro por este tempo depois de cada tiro

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
	Weapon: Motor6D?, -- junta braço → arma
	Rifle: boolean,
	WeaponLength: number, -- da empunhadura até a ponta
	Aim: number, -- 0 = rifle em porte baixo, 1 = no ombro, mirando
	AimUntil: number,
	AimAngle: number, -- quanto o braço sobe para a mira ficar na altura dos olhos
	HandDown: number, -- do ombro até a mão, com o braço solto
	HandForward: number, -- quanto a mão fica à frente do eixo do braço
	BoreUp: number, -- altura do cano acima da mão
	Melee: string, -- "Sword" | "Hammer" | ""
	Guard: number, -- 1 = arma em guarda (parado/andando), 0 = no meio do golpe
}

local AnimationController = {}

local rigs: { [Instance]: Rig } = {}
-- Avatares novos usam AnimationConstraint nas juntas; os antigos, Motor6D. Os dois têm Transform.
type Joint = Motor6D | AnimationConstraint
type AvatarAttack = { Start: number, Pattern: string, Dir: Vector3?, Held: boolean }
local avatarAttacks: { [Model]: AvatarAttack } = {}

local function jointOf(parent: Instance?, name: string): Joint?
	local found = if parent then parent:FindFirstChild(name) else nil
	if found and (found:IsA("Motor6D") or found:IsA("AnimationConstraint")) then
		return (found :: any) :: Joint
	end
	return nil
end

local function smooth(x: number): number
	local c = math.clamp(x, 0, 1)
	return c * c * (3 - 2 * c)
end

local AVATAR_AIM = 1.45 -- braço quase na horizontal: a mira do rifle fica na altura dos olhos

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
	local weaponJoint: Motor6D? = nil
	local rifle, weaponLength = false, 3
	local aimAngle, handDown, handForward, boreUp, melee = 1.38, 2, 0, 0.2, ""
	local weaponModel = model:FindFirstChild("Weapon")
	if weaponModel then
		local joint = root:WaitForChild("Weapon", 3)
		local gripPart = weaponModel:WaitForChild("Grip", 3)
		if joint and joint:IsA("Motor6D") then
			weaponJoint = joint
		end
		if gripPart then
			local weaponType = gripPart:GetAttribute("Type")
			rifle = weaponType == "Rifle"
			melee = if rifle or typeof(weaponType) ~= "string" then "" else weaponType
			local length = gripPart:GetAttribute("Length")
			weaponLength = if typeof(length) == "number" then length else 3
			local bore, sight = gripPart:GetAttribute("BoreUp"), gripPart:GetAttribute("SightUp")
			boreUp = if typeof(bore) == "number" then bore else 0.2
			-- Mira na altura dos olhos: o braço sobe só o bastante para a luneta alinhar com a
			-- cabeça (robôs de ombro alto levantam menos, senão o rifle passa por cima da cabeça).
			local arm, head = joints.ArmR, joints.Head
			if rifle and weaponJoint and arm and head and head.Part1 then
				-- mão em relação ao ombro com o braço solto: handDown para baixo, handForward à frente
				local offset = arm.C1.Position - weaponJoint.C0.Position
				handDown, handForward = math.max(0.5, offset.Y), offset.Z
				local reach = math.sqrt(handDown * handDown + handForward * handForward)
				local eyes = head.C0.Position.Y + head.Part1.Size.Y * 0.5
				local sightUp = if typeof(sight) == "number" then sight else 0.45
				-- altura da mão com o braço em θ: -handDown·cos θ + handForward·sin θ
				local target = math.clamp((eyes - sightUp - arm.C0.Position.Y) / reach, -1, 1)
				aimAngle = math.clamp(math.atan2(handDown, handForward) + math.asin(target), 0.8, 1.6)
			end
		end
	end
	rigs[model] = {
		Weapon = weaponJoint,
		Rifle = rifle,
		WeaponLength = weaponLength,
		Aim = 0,
		AimUntil = 0,
		AimAngle = aimAngle,
		HandDown = handDown,
		HandForward = handForward,
		BoreUp = boreUp,
		Melee = melee,
		Guard = 1,
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

	local armLFrame: CFrame? = nil
	local weapon = rig.Weapon
	if rig.Rifle and not rig.Worker then
		-- Rifle: porte baixo andando/parado; ao atirar sobe para o ombro, o cano fica na horizontal,
		-- a mão esquerda apoia o cano e a cabeça inclina para a mira. Cada tiro dá um coice:
		-- a arma recua, o cano sobe e o braço absorve.
		rig.Aim += ((if now < rig.AimUntil then 1 else 0) - rig.Aim) * math.min(1, dt * 14)
		local aim = rig.Aim
		local since = now - rig.AttackStart
		local kick = if since >= 0 and since < 0.6 then math.exp(-since * 13) else 0
		local carry = 0.4 + armR * 0.25 -- balança um pouco com o passo
		armR = carry + (rig.AimAngle - carry) * aim + kick * 0.12
		local pitch = -0.3 * (1 - aim) + kick * 0.2 -- inclinação do cano em relação ao chão
		if weapon then
			weapon.Transform = CFrame.Angles(pitch - armR, 0, 0) * CFrame.new(0, 0, kick * 0.45)
		end
		armLFrame = CFrame.Angles(0, -0.25 - 0.3 * aim, 0)
			* CFrame.Angles(0.55 + (rig.AimAngle - 0.2 - 0.55) * aim + kick * 0.08, 0, 0)
		head = head:Lerp(CFrame.Angles(0.06 - kick * 0.1, 0, -0.14), aim)
		if rig.Speed <= 0.8 then
			-- Base de tiro: um pé à frente, outro atrás; o coice empurra o corpo um instante
			legL += (0.24 - kick * 0.06) * aim
			legR -= (0.2 + kick * 0.06) * aim
		end
	else
		local duration = ATTACK_SECONDS[rig.AttackPattern] or 0.45
		local t = (now - rig.AttackStart) / duration
		local flick = 0
		local striking = t >= 0 and t < 1 and rig.AttackPattern ~= "Line"
		if striking then
			armR = attackAngle(rig.AttackPattern, t)
			if rig.AttackPattern == "Circle" then
				armL = armR * 0.8 -- martelo: os dois braços
			end
			-- pulso: a arma "chicoteia" para baixo na descida do golpe
			flick = -0.55 * math.clamp((t - 0.3) / 0.25, 0, 1) * (1 - math.clamp((t - 0.6) / 0.4, 0, 1))
		end
		-- Em guarda: espada apontada para cima, martelo meio erguido; baixa durante o golpe
		rig.Guard += ((if striking then 0 else 1) - rig.Guard) * math.min(1, dt * 12)
		local guard = if rig.Melee == "Sword" then 0.6 elseif rig.Melee == "Hammer" then 0.3 else 0
		if weapon then
			weapon.Transform = CFrame.Angles(guard * rig.Guard + flick, 0, 0)
		end
	end

	set(joints, "ArmL", armLFrame or CFrame.Angles(armL, 0, 0))
	set(joints, "ArmR", CFrame.Angles(armR, 0, 0))
	set(joints, "LegL", CFrame.Angles(legL, 0, 0))
	set(joints, "LegR", CFrame.Angles(legR, 0, 0))
	set(joints, "Head", head)
end

-- Golpe de um robô: o FxEvent traz a posição de onde saiu; anima o robô que está ali.
function AnimationController.RobotAttack(origin: Vector3, pattern: string): (Vector3?, number)
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
		if pattern == "Line" then
			best.AimUntil = os.clock() + AIM_HOLD
			-- Boca do cano com o rifle no ombro (de onde saem o clarão e o rastro do tiro)
			local arm = best.Joints.ArmR
			if arm and arm.Part1 then
				-- ponto na altura do cano, acima do ombro; alcance = braço estendido + cano
				local shoulder = (best.Root.CFrame * arm.C0).Position
				local sin, cos = math.sin(best.AimAngle), math.cos(best.AimAngle)
				local rise = best.BoreUp - best.HandDown * cos + best.HandForward * sin
				return shoulder + Vector3.new(0, rise, 0),
					best.HandDown * sin + best.HandForward * cos + best.WeaponLength
			end
		end
	end
	return nil, 0
end

-- Ponto na altura do cano e alcance até a boca do rifle do avatar já em posição de tiro
-- (de onde saem o clarão e o rastro do tiro do jogador).
function AnimationController.AvatarMuzzle(player: Player): (Vector3?, number)
	local character = player.Character
	local torso = if character
		then (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
		else nil
	if not character or not torso or not torso:IsA("BasePart") then
		return nil, 0
	end
	local weaponModel = character:FindFirstChild("AvatarWeapon")
	local gripPart = if weaponModel then weaponModel:FindFirstChild("Grip") else nil
	local length = if gripPart then gripPart:GetAttribute("Length") else nil
	local bore = if gripPart then gripPart:GetAttribute("BoreUp") else nil
	local arm = 1.9 * character:GetScale()
	local shoulder = torso.Position
		+ torso.CFrame.RightVector * (torso.Size.X * 0.5 + 0.3)
		+ Vector3.new(0, torso.Size.Y * 0.25, 0)
	local rise = (if typeof(bore) == "number" then bore else 0.2) - arm * math.cos(AVATAR_AIM)
	return shoulder + Vector3.new(0, rise, 0),
		arm * math.sin(AVATAR_AIM) + (if typeof(length) == "number" then length else 2.4)
end

-- Golpe do avatar de qualquer jogador (o próprio chama na hora; os outros chegam pelo FxEvent).
-- dir: para onde o golpe foi (o rifle aponta para lá).
function AnimationController.AvatarAttack(player: Player, pattern: string, dir: Vector3?)
	local character = player.Character
	if character then
		local previous = avatarAttacks[character]
		avatarAttacks[character] = {
			Start = os.clock(),
			Pattern = pattern,
			Dir = dir,
			-- tiros em sequência: o rifle já está no ombro, não desce e sobe de novo
			Held = previous ~= nil and previous.Pattern == "Line" and pattern == "Line",
		}
	end
end

local function rightShoulder(character: Model): (Joint?, boolean)
	local r15 = jointOf(character:FindFirstChild("RightUpperArm"), "RightShoulder")
	if r15 then
		return r15, false
	end
	local r6 = jointOf(character:FindFirstChild("Torso"), "Right Shoulder")
	if r6 then
		return r6, true
	end
	return nil, false
end

-- Leva uma junta do avatar para uma pose fixa, com peso (0 = animação do Roblox, 1 = pose).
local function pose(character: Model, part: string, name: string, target: CFrame, weight: number)
	local joint = jointOf(character:FindFirstChild(part), name)
	if joint then
		joint.Transform = joint.Transform:Lerp(target, weight)
	end
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

	-- Depois que a animação padrão do Roblox é aplicada, o golpe entra por cima dela: o braço
	-- direito vai para uma pose própria (não depende da animação de parado/andar do avatar).
	RunService.Stepped:Connect(function()
		local now = os.clock()
		for character, attack in avatarAttacks do
			local duration = ATTACK_SECONDS[attack.Pattern] or 0.45
			local t = (now - attack.Start) / duration
			local shoulder, isR6 = rightShoulder(character)
			local weaponModel = character:FindFirstChild("AvatarWeapon")
			local gripPart = if weaponModel then weaponModel:FindFirstChild("Grip") else nil
			local found = if gripPart then gripPart:FindFirstChild("Weapon") else nil
			local weapon: Motor6D? = if found and found:IsA("Motor6D") then found else nil
			if t >= 1 or not shoulder or not character.Parent then
				avatarAttacks[character] = nil
				if weapon then
					weapon.Transform = CFrame.identity
				end
				continue
			end
			local enter = if attack.Held then 1 else smooth(t / 0.1)
			local weight = enter * (1 - smooth((t - 0.88) / 0.12))
			local angle = 0
			if attack.Pattern == "Line" then
				-- Rifle: sobe rápido para o ombro, atira com coice, segura a mira e abaixa.
				local kick = math.exp(-(now - attack.Start) * 12)
				angle = AVATAR_AIM + kick * 0.1
				local hand = if weapon then weapon.Part0 else nil
				if weapon and hand then
					-- o cano fica na horizontal apontando para o alvo, não importa a pose da mão
					local root = character:FindFirstChild("HumanoidRootPart")
					local dir = attack.Dir
					if (not dir or dir.Magnitude < 0.01) and root and root:IsA("BasePart") then
						dir = root.CFrame.LookVector
					end
					local flat = if dir then Vector3.new(dir.X, 0, dir.Z) else Vector3.zAxis
					local target = CFrame.lookAt(Vector3.zero, flat).Rotation
						* CFrame.Angles(kick * 0.22, 0, 0)
					local base = (hand.CFrame * weapon.C0).Rotation
					weapon.Transform = CFrame.identity:Lerp(base:Inverse() * target, weight)
						* CFrame.new(0, 0, kick * 0.35)
				end
				-- mão esquerda apoiando o cano (R15)
				pose(
					character,
					"LeftUpperArm",
					"LeftShoulder",
					CFrame.Angles(0, -0.6, 0) * CFrame.Angles(1.25 + kick * 0.06, 0, 0),
					weight
				)
				pose(character, "LeftLowerArm", "LeftElbow", CFrame.identity, weight)
			else
				angle = attackAngle(attack.Pattern, t)
				if weapon then
					local flick = -0.5
						* math.clamp((t - 0.3) / 0.25, 0, 1)
						* (1 - math.clamp((t - 0.6) / 0.4, 0, 1))
					weapon.Transform = CFrame.Angles(flick, 0, 0)
				end
			end
			if isR6 then
				shoulder.Transform = shoulder.Transform * CFrame.Angles(0, 0, angle * weight)
			else
				shoulder.Transform = shoulder.Transform:Lerp(CFrame.Angles(angle, 0, 0), weight)
				pose(character, "RightLowerArm", "RightElbow", CFrame.identity, weight)
				pose(character, "RightHand", "RightWrist", CFrame.identity, weight)
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
