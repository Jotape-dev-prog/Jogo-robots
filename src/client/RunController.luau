--!strict
-- Correr: só enquanto o Shift esquerdo estiver pressionado. Soltou, volta a andar.
-- A animação de corrida é a padrão do Roblox (ela troca sozinha pela velocidade).
-- A câmera abre um pouco (FOV) para dar sensação de velocidade.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local WALK_SPEED = 16
local RUN_SPEED = 26
local WALK_FOV = 70
local RUN_FOV = 78

local player = Players.LocalPlayer

local RunController = {}

local function apply(running: boolean)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		humanoid.WalkSpeed = if running then RUN_SPEED else WALK_SPEED
	end
	local camera = Workspace.CurrentCamera
	if camera then
		TweenService:Create(camera, TweenInfo.new(0.25), {
			FieldOfView = if running then RUN_FOV else WALK_FOV,
		}):Play()
	end
end

function RunController.Start()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.KeyCode == Enum.KeyCode.LeftShift and not gameProcessed then
			apply(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift then
			apply(false)
		end
	end)
	-- Perdeu o foco da janela com o Shift apertado: para de correr.
	UserInputService.WindowFocusReleased:Connect(function()
		apply(false)
	end)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid", 5)
		apply(UserInputService:IsKeyDown(Enum.KeyCode.LeftShift))
	end)
end

return RunController
