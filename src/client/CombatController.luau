--!strict
-- Ataque do avatar: clique esquerdo / tecla F / botão na tela (celular) / R2 (controle).
-- O cliente só manda a direção da mira; dano e acertos são calculados no servidor.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local CombatController = {}

local busy = false
local localCooldownUntil = 0

local function rootPart(): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function aimDirection(root: BasePart): Vector3
	if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
		local target = mouse.Hit.Position
		local flat = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
		if flat.Magnitude > 0.5 then
			return flat.Unit
		end
	end
	return root.CFrame.LookVector
end

-- Efeito visual local e rápido do golpe.
local function playEffect(root: BasePart, dir: Vector3, result: any)
	local fx = Instance.new("Part")
	fx.Anchored = true
	fx.CanCollide = false
	fx.CanQuery = false
	fx.CanTouch = false
	fx.Material = Enum.Material.Neon
	fx.Color = if result.Hits > 0 then Color3.fromRGB(255, 220, 120) else Color3.fromRGB(200, 200, 220)
	fx.Transparency = 0.35
	local ground = root.Position - Vector3.new(0, 2.5, 0)
	local facing = CFrame.lookAt(ground, ground + dir)

	if result.Pattern == "Circle" then
		fx.Shape = Enum.PartType.Cylinder
		fx.Size = Vector3.new(0.3, result.Range * 2, result.Range * 2)
		fx.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90))
	elseif result.Pattern == "Line" then
		fx.Size = Vector3.new(0.4, 0.4, result.Range)
		fx.CFrame = facing * CFrame.new(0, 2, -result.Range / 2)
	else
		local width = 2 * result.Range * math.sin(math.rad((result.Angle or 90) / 2))
		fx.Size = Vector3.new(width, 0.3, result.Range)
		fx.CFrame = facing * CFrame.new(0, 0.5, -result.Range / 2)
	end
	fx.Parent = workspace
	local tween = TweenService:Create(fx, TweenInfo.new(0.25), { Transparency = 1 })
	tween:Play()
	tween.Completed:Once(function()
		fx:Destroy()
	end)
end

local function attack()
	if busy or os.clock() < localCooldownUntil then
		return
	end
	local root = rootPart()
	if not root then
		return
	end
	busy = true
	local dir = aimDirection(root)
	local ok, result = pcall(function()
		return Net.Function("Attack"):InvokeServer(dir)
	end)
	busy = false
	if ok and result and result.Ok then
		localCooldownUntil = os.clock() + (result.Cooldown or 0.5) * 0.9
		playEffect(root, dir, result)
	end
end

function CombatController.Start()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.F then
			task.spawn(attack)
		end
	end)
	-- Botão na tela para celular e gatilho do controle.
	ContextActionService:BindAction("Atacar", function(_, state)
		if state == Enum.UserInputState.Begin then
			task.spawn(attack)
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.ButtonR2)
	ContextActionService:SetTitle("Atacar", "Atacar")
	ContextActionService:SetPosition("Atacar", UDim2.new(1, -110, 1, -170))
end

return CombatController
