--!strict
-- Arrastar robôs no mundo 3D: pressione sobre um robô (ou o hexágono dele) na sua base,
-- arraste até outro hexágono e solte para mover/trocar. Um clique simples abre a janela do grid.
-- Funciona com mouse e toque.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Grid = require(ReplicatedStorage.Shared.Config.Grid)

local State = require(script.Parent.State)
local Sound = require(script.Parent.SoundController)

local player = Players.LocalPlayer

local GridController = {}

local dragging: { From: string, Input: InputObject, Moved: boolean, StartPos: Vector2 }? = nil
local hoverHighlight: Highlight? = nil
local robotHighlight: Highlight? = nil
local onClickCell: ((string) -> ())? = nil

local function myBase(): Model?
	local bases = Workspace:FindFirstChild("Bases")
	if not bases then
		return nil
	end
	for _, base in bases:GetChildren() do
		if base:GetAttribute("OwnerUserId") == player.UserId then
			return base :: Model
		end
	end
	return nil
end

local function cellFromInstance(instance: Instance?): string?
	local current = instance
	while current and current ~= Workspace do
		local cell = current:GetAttribute("Cell")
		if type(cell) == "string" then
			return cell
		end
		current = current.Parent
	end
	return nil
end

-- Hexágono (ou robô) sob o ponto da tela, na base do jogador. nil se não houver.
function GridController.HitCell(screenPosition: Vector2 | Vector3): string?
	local base = myBase()
	local camera = Workspace.CurrentCamera
	if not base or not camera then
		return nil
	end
	local include = {}
	for _, name in { "Grid", "Robots" } do
		local folder = base:FindFirstChild(name)
		if folder then
			table.insert(include, folder)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	-- ScreenPointToRay: mesmo espaço do InputObject.Position (desconta a barra superior do Roblox).
	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 400, params)
	return if result then cellFromInstance(result.Instance) else nil
end

local function highlight(target: Instance?, existing: Highlight?, color: Color3): Highlight?
	if not target then
		if existing then
			existing:Destroy()
		end
		return nil
	end
	local h = existing or Instance.new("Highlight")
	h.FillColor = color
	h.FillTransparency = 0.5
	h.OutlineColor = color
	h.Adornee = target
	h.Parent = target
	return h
end

local function robotModel(cell: string): Model?
	local base = myBase()
	local folder = base and base:FindFirstChild("Robots")
	if not folder then
		return nil
	end
	for _, m in folder:GetChildren() do
		if m:GetAttribute("Cell") == cell then
			return m :: Model
		end
	end
	return nil
end

local function hexModel(cell: string): Instance?
	local base = myBase()
	local folder = base and base:FindFirstChild("Grid")
	return if folder then folder:FindFirstChild(cell) else nil
end

local function stopDrag()
	dragging = nil
	hoverHighlight = highlight(nil, hoverHighlight, Color3.new())
	robotHighlight = highlight(nil, robotHighlight, Color3.new())
end

local function isUnlocked(cell: string): boolean
	local data = State.Data
	return data ~= nil and Grid.IsUnlocked(cell, Grid.Columns(data.Upgrades.Grid))
end

function GridController.SetOnClickCell(callback: (string) -> ())
	onClickCell = callback
end

function GridController.Start()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or dragging then
			return
		end
		local isPointer = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		if not isPointer then
			return
		end
		local cell = GridController.HitCell(input.Position)
		local data = State.Data
		if not cell or not data then
			return
		end
		dragging = {
			From = cell,
			Input = input,
			Moved = false,
			StartPos = Vector2.new(input.Position.X, input.Position.Y),
		}
		if data.Grid[cell] then
			robotHighlight = highlight(robotModel(cell), robotHighlight, Color3.fromRGB(255, 200, 80))
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		local drag = dragging
		if not drag then
			return
		end
		local isMove = input.UserInputType == Enum.UserInputType.MouseMovement
			or (input.UserInputType == Enum.UserInputType.Touch and input == drag.Input)
		if not isMove then
			return
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if (pos - drag.StartPos).Magnitude > 8 then
			drag.Moved = true
		end
		local data = State.Data
		if not drag.Moved or not data or not data.Grid[drag.From] then
			return
		end
		local hover = GridController.HitCell(input.Position)
		if hover and hover ~= drag.From then
			local ok = isUnlocked(hover)
			hoverHighlight = highlight(
				hexModel(hover),
				hoverHighlight,
				if ok then Color3.fromRGB(90, 220, 120) else Color3.fromRGB(220, 70, 60)
			)
		else
			hoverHighlight = highlight(nil, hoverHighlight, Color3.new())
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		local drag = dragging
		if not drag then
			return
		end
		local isRelease = input.UserInputType == Enum.UserInputType.MouseButton1
			or (input.UserInputType == Enum.UserInputType.Touch and input == drag.Input)
		if not isRelease then
			return
		end
		local from = drag.From
		local moved = drag.Moved
		stopDrag()
		if not moved then
			if onClickCell then
				onClickCell(from)
			end
			return
		end
		local to = GridController.HitCell(input.Position)
		local data = State.Data
		if to and to ~= from and data and data.Grid[from] and isUnlocked(to) then
			local r = State.Call("MoveRobot", from, to)
			if r and r.Ok then
				Sound.Play("Equip")
			end
		end
	end)
end

return GridController
