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

local function draw(entry: any)
	local origin: Vector3 = entry.o
	local dir: Vector3 = if entry.d.Magnitude > 0.01 then entry.d.Unit else Vector3.zAxis
	local color = COLORS[entry.p] or COLORS.Cone
	local own = entry.u == localPlayer.UserId -- o próprio golpe já foi desenhado na hora pelo CombatController

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
			local length = entry.r
			local beam =
				neon(Vector3.new(0.25, 0.25, length), facing * CFrame.new(0, 2.2, -length / 2), color)
			fadeOut(beam, 0.15)
			local flash = neon(
				Vector3.new(1, 1, 1),
				facing * CFrame.new(0, 2.2, -1.2),
				Color3.new(1, 1, 0.8),
				Enum.PartType.Ball
			)
			fadeOut(flash, 0.1, { Size = Vector3.new(2, 2, 2) })
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
