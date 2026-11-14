--!strict
-- Desenha os efeitos de combate avisados pelo servidor (FxEvent):
--   Espada (Cone): leque de lâminas brilhantes  •  Martelo (Circle): onda de impacto + atordoamento
--   Rifle (Line): rastro do tiro + clarão  •  Acertos: faíscas
-- Efeitos longe da câmera são ignorados, e há um limite por frame para não pesar no celular.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local Sound = require(script.Parent.SoundController)
local AnimationController = require(script.Parent.AnimationController)

local MAX_DISTANCE = 160
local MAX_PER_BATCH = 25
local COLORS = {
	Cone = Color3.fromRGB(255, 230, 150),
	Circle = Color3.fromRGB(255, 170, 60),
	Line = Color3.fromRGB(120, 210, 255),
}

local FxController = {}

local folder: Folder
local sparkPart: Part
local sparkEmitter: ParticleEmitter

local function neon(size: Vector3, cframe: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	if shape then
		p.Shape = shape
	end
	p.CFrame = cframe
	p.Transparency = 0.25
	p.Parent = folder
	return p
end

local function fadeOut(p: BasePart, seconds: number, goal: { [string]: any }?)
	local props: { [string]: any } = goal or {}
	props.Transparency = 1
	local tween =
		TweenService:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tween:Play()
	tween.Completed:Once(function()
		p:Destroy()
	end)
end

local function sparks(position: Vector3, color: Color3, amount: number)
	sparkPart.CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0))
	sparkEmitter.Color = ColorSequence.new(color)
	sparkEmitter:Emit(amount)
end

local function stunMark(position: Vector3, seconds: number)
	local ring = neon(
		Vector3.new(0.2, 3, 3),
		CFrame.new(position + Vector3.new(0, 6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(255, 230, 70),
		Enum.PartType.Cylinder
	)
	ring.Transparency = 0.4
	-- Gira enquanto o zumbi está atordoado.
	TweenService:Create(
		ring,
		TweenInfo.new(seconds, Enum.EasingStyle.Linear),
		{ CFrame = ring.CFrame * CFrame.Angles(math.rad(720), 0, 0) }
	):Play()
	task.delay(math.max(0, seconds - 0.25), function()
		fadeOut(ring, 0.25)
	end)
end

-- Nuvem de poeira/fumaça (partes neon desbotando para cima).
local function puff(position: Vector3, color: Color3, count: number, spread: number, rise: number)
	for _ = 1, count do
		local offset = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * spread
		local size = 0.6 + math.random() * 1.2
		local p =
			neon(Vector3.new(size, size, size), CFrame.new(position + offset), color, Enum.PartType.Ball)
		p.Material = Enum.Material.SmoothPlastic
		p.Transparency = 0.3
		fadeOut(p, 0.6 + math.random() * 0.4, {
			Size = Vector3.new(size, size, size) * 2.2,
			CFrame = CFrame.new(
				position + offset * 1.6 + Vector3.new(0, rise * (0.6 + math.random() * 0.6), 0)
			),
		})
	end
end

local function shake(intensity: number, seconds: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local started = os.clock()
	local connection
	connection = game:GetService("RunService").RenderStepped:Connect(function()
		local t = os.clock() - started
		if t > seconds then
			connection:Disconnect()
			return
		end
		local k = intensity * (1 - t / seconds)
		camera.CFrame = camera.CFrame
			* CFrame.Angles(math.rad((math.random() - 0.5) * k), math.rad((math.random() - 0.5) * k), 0)
	end)
end

-- Explosão de cor (raridade da roleta, rebirth, vitória): anel + faíscas + brilho.
function FxController.Burst(position: Vector3, color: Color3, scale: number?)
	local s = scale or 1
	local ring = neon(
		Vector3.new(0.3, 2, 2),
		CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		Enum.PartType.Cylinder
	)
	fadeOut(ring, 0.6, { Size = Vector3.new(0.3, 18 * s, 18 * s) })
	local ball =
		neon(Vector3.new(2, 2, 2), CFrame.new(position + Vector3.new(0, 2, 0)), color, Enum.PartType.Ball)
	fadeOut(ball, 0.45, { Size = Vector3.new(8, 8, 8) * s })
	sparks(position, color, math.floor(30 * s))
end

-- Explosão de cor em volta do próprio personagem.
function FxController.BurstAtPlayer(color: Color3, scale: number?)
	local character = localPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if root and folder then
		FxController.Burst(root.Position - Vector3.new(0, 2.5, 0), color, scale)
	end
end

local function event(entry: any)
	local position: Vector3 = entry.o
	if entry.t == "k" then
		-- Zumbi derrotado: poeira + gosma verde
		puff(position + Vector3.new(0, 1, 0), Color3.fromRGB(120, 110, 95), 4, 2 * entry.z, 3)
		sparks(position, Color3.fromRGB(120, 230, 90), 10)
	elseif entry.t == "i" then
		-- Núcleo invadido: onda vermelha e tremor para o dono da base
		local ring = neon(
			Vector3.new(0.4, 4, 4),
			CFrame.new(position + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(255, 60, 40),
			Enum.PartType.Cylinder
		)
		fadeOut(ring, 0.7, { Size = Vector3.new(0.4, 40, 40) })
		sparks(position + Vector3.new(0, 4, 0), Color3.fromRGB(255, 90, 40), 25)
		if entry.u == localPlayer.UserId then
			shake(1.6, 0.5)
		end
	elseif entry.t == "b" then
		-- Robô quebrado: estouro de faíscas e fumaça escura
		sparks(position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 160, 60), 25)
		puff(position + Vector3.new(0, 2.5, 0), Color3.fromRGB(50, 48, 45), 6, 3, 6)
	end
end

-- Tiro de rifle: clarão em estrela e luz na boca do cano, projétil riscando até o fim do alcance,
-- rastro que some, fumaça e a cápsula saltando para o lado.
-- `shoulder` + `dir` × `reach` = boca do cano (rifle no ombro, apontado para o alvo).
function FxController.Shot(
	shoulder: Vector3,
	reach: number,
	direction: Vector3,
	range: number,
	color: Color3?
)
	if not folder then
		return
	end
	local flatDir = Vector3.new(direction.X, 0, direction.Z)
	local dir = if flatDir.Magnitude > 0.01 then flatDir.Unit else Vector3.zAxis
	local tint = color or COLORS.Line
	local muzzle = shoulder + dir * reach
	local aim = CFrame.lookAt(muzzle, muzzle + dir)
	local length = math.max(4, range - reach)

	-- Clarão: bola + duas lâminas cruzadas + luz rápida
	local flash = neon(Vector3.new(0.9, 0.9, 0.9), aim, Color3.fromRGB(255, 240, 190), Enum.PartType.Ball)
	fadeOut(flash, 0.09, { Size = Vector3.new(2.2, 2.2, 2.2) })
	for i = 0, 1 do
		local blade = neon(
			Vector3.new(2.6, 0.12, 0.5),
			aim * CFrame.new(0, 0, -0.4) * CFrame.Angles(0, 0, math.rad(45 + i * 90)),
			Color3.fromRGB(255, 220, 140)
		)
		fadeOut(blade, 0.08)
	end
	local cone = neon(Vector3.new(0.5, 0.5, 2.4), aim * CFrame.new(0, 0, -1.4), Color3.fromRGB(255, 230, 160))
	fadeOut(cone, 0.08, { Size = Vector3.new(0.1, 0.1, 3.4) })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 150)
	light.Range = 14
	light.Brightness = 4
	light.Parent = flash

	-- Rastro fino que fica um instante + projétil brilhante que corre até o fim
	local trail = neon(Vector3.new(0.08, 0.08, length), aim * CFrame.new(0, 0, -length / 2), tint)
	trail.Transparency = 0.55
	fadeOut(trail, 0.22)
	local bullet = neon(Vector3.new(0.22, 0.22, 5), aim * CFrame.new(0, 0, -2.5), Color3.new(1, 1, 1))
	bullet.Transparency = 0
	local fly = TweenService:Create(
		bullet,
		TweenInfo.new(math.clamp(length / 380, 0.05, 0.16), Enum.EasingStyle.Linear),
		{ CFrame = aim * CFrame.new(0, 0, -(length - 2.5)) }
	)
	fly:Play()
	fly.Completed:Once(function()
		bullet:Destroy()
	end)

	-- Fumaça na boca do cano: dois fiapos pequenos que sobem
	for _ = 1, 2 do
		local size = 0.25 + math.random() * 0.2
		local wisp = neon(
			Vector3.new(size, size, size),
			CFrame.new(muzzle + dir * 0.3),
			Color3.fromRGB(205, 205, 210),
			Enum.PartType.Ball
		)
		wisp.Material = Enum.Material.SmoothPlastic
		wisp.Transparency = 0.45
		fadeOut(wisp, 0.35 + math.random() * 0.2, {
			Size = Vector3.new(size, size, size) * 2.4,
			CFrame = CFrame.new(
				muzzle + dir * (0.6 + math.random() * 0.5) + Vector3.new(0, 0.5 + math.random() * 0.5, 0)
			),
		})
	end

	-- Cápsula saltando para a direita e caindo
	local shell = neon(
		Vector3.new(0.14, 0.14, 0.4),
		aim * CFrame.new(0.3, 0.1, reach * 0.6),
		Color3.fromRGB(230, 180, 70)
	)
	shell.Material = Enum.Material.Metal
	shell.Transparency = 0
	local side = aim.RightVector * (1.6 + math.random()) + Vector3.new(0, 1.2, 0)
	local up = TweenService:Create(
		shell,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = (shell.CFrame + side) * CFrame.Angles(2, 1, 0) }
	)
	up:Play()
	up.Completed:Once(function()
		local fall =
			TweenService:Create(shell, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = (shell.CFrame + side * 0.5 - Vector3.new(0, 3.4, 0)) * CFrame.Angles(3, 2, 1),
				Transparency = 1,
			})
		fall:Play()
		fall.Completed:Once(function()
			shell:Destroy()
		end)
	end)
end

local function draw(entry: any)
	if entry.t then
		event(entry)
		return
	end
	local origin: Vector3 = entry.o
	local dir: Vector3 = if entry.d.Magnitude > 0.01 then entry.d.Unit else Vector3.zAxis
	local color = COLORS[entry.p] or COLORS.Cone
	local own = entry.u == localPlayer.UserId -- o próprio golpe já foi desenhado na hora pelo CombatController

	-- Animação do golpe: robô que está na origem, ou o avatar de outro jogador.
	-- Para o rifle, a animação devolve o ombro e o alcance do cano (de onde sai o tiro).
	local shoulder: Vector3?, reach = nil, 0
	if entry.u == 0 then
		shoulder, reach = AnimationController.RobotAttack(origin, entry.p)
	elseif not own then
		local attacker = Players:GetPlayerByUserId(entry.u)
		if attacker then
			AnimationController.AvatarAttack(attacker, entry.p, dir)
			shoulder, reach = AnimationController.AvatarMuzzle(attacker)
		end
	end

	if not own then
		-- Som 3D do golpe (robôs e outros jogadores), no lugar de onde ele saiu.
		Sound.PlayAt(
			if entry.p == "Line" then "Shot" elseif entry.p == "Circle" then "HeavyHit" else "Swing",
			origin
		)
		local ground = origin + Vector3.new(0, 0.6, 0)
		local facing = CFrame.lookAt(ground, ground + dir)
		if entry.p == "Circle" then
			local ring = neon(
				Vector3.new(0.3, 2, 2),
				CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90)),
				color,
				Enum.PartType.Cylinder
			)
			fadeOut(ring, 0.3, { Size = Vector3.new(0.3, entry.r * 2, entry.r * 2) })
		elseif entry.p == "Line" then
			FxController.Shot(shoulder or (origin + Vector3.new(0, 2.6, 0)), reach, dir, entry.r, color)
		else
			-- Leque de 5 lâminas cobrindo o ângulo do corte.
			local half = math.rad(entry.a / 2)
			for i = 0, 4 do
				local angle = -half + (2 * half) * (i / 4)
				local blade = neon(
					Vector3.new(0.15, 0.15, entry.r * 0.8),
					facing * CFrame.Angles(0, angle, 0) * CFrame.new(0, 2, -entry.r * 0.45),
					color
				)
				fadeOut(blade, 0.18)
			end
		end
	end

	for _, hit in entry.h do
		sparks(hit, color, 6)
		if entry.s then
			stunMark(hit, entry.s)
		end
	end
end

function FxController.Start()
	folder = Instance.new("Folder")
	folder.Name = "CombatFx"
	folder.Parent = Workspace

	sparkPart = Instance.new("Part")
	sparkPart.Anchored = true
	sparkPart.CanCollide = false
	sparkPart.CanQuery = false
	sparkPart.Transparency = 1
	sparkPart.Size = Vector3.new(0.2, 0.2, 0.2)
	sparkPart.Parent = folder
	sparkEmitter = Instance.new("ParticleEmitter")
	sparkEmitter.Enabled = false
	sparkEmitter.LightEmission = 1
	sparkEmitter.Lifetime = NumberRange.new(0.2, 0.4)
	sparkEmitter.Speed = NumberRange.new(8, 16)
	sparkEmitter.SpreadAngle = Vector2.new(180, 180)
	sparkEmitter.Drag = 4
	sparkEmitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparkEmitter.Parent = sparkPart

	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("FxEvent") :: RemoteEvent
	remote.OnClientEvent:Connect(function(batch: { any })
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		local drawn = 0
		for _, entry in batch do
			if drawn >= MAX_PER_BATCH then
				break
			end
			if
				typeof(entry) == "table"
				and typeof(entry.o) == "Vector3"
				and (entry.o - eye).Magnitude < MAX_DISTANCE
			then
				drawn += 1
				draw(entry)
			end
		end
	end)
end

return FxController
