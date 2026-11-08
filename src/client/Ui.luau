--!strict
-- Kit de interface: tema Cyber-Rustic, escala automática (PC/celular), janelas, botões, listas e avisos.
-- Todas as telas são montadas com estas funções para manter o visual consistente.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Ui = {}

Ui.Theme = {
	Background = Color3.fromRGB(24, 22, 20),
	Panel = Color3.fromRGB(38, 34, 30),
	PanelLight = Color3.fromRGB(54, 48, 42),
	Stroke = Color3.fromRGB(120, 90, 50),
	Text = Color3.fromRGB(240, 232, 220),
	TextDim = Color3.fromRGB(170, 160, 145),
	Accent = Color3.fromRGB(230, 140, 40), -- laranja ferrugem
	Good = Color3.fromRGB(70, 170, 90),
	Bad = Color3.fromRGB(200, 70, 60),
	Info = Color3.fromRGB(70, 130, 200),
	Purple = Color3.fromRGB(120, 80, 190),
	Font = Enum.Font.GothamBold,
	FontBody = Enum.Font.GothamMedium,
}

local T = Ui.Theme

export type Window = {
	Name: string,
	Frame: Frame,
	Body: Frame,
	Open: () -> (),
	Close: () -> (),
	Toggle: () -> (),
	IsOpen: () -> boolean,
	OnOpen: (() -> ()) -> (),
}

local screen: ScreenGui? = nil
local windows: { Window } = {}
local toastLabel: TextLabel? = nil
local toastToken = 0

--------------------------------------------------------------------------------
-- Básicos
--------------------------------------------------------------------------------

function Ui.Corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
end

function Ui.Stroke(parent: Instance, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or T.Stroke
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

function Ui.Padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
end

function Ui.ListLayout(parent: Instance, horizontal: boolean?, gap: number?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, gap or 6)
	if horizontal then
		l.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	l.Parent = parent
	return l
end

function Ui.Frame(parent: Instance, size: UDim2, color: Color3?, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.BackgroundColor3 = color or T.Panel
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

function Ui.Label(parent: Instance, text: string, size: UDim2?, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size or UDim2.new(1, 0, 0, 24)
	l.BackgroundTransparency = 1
	l.Font = T.FontBody
	l.TextColor3 = T.Text
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.RichText = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 22
	limit.Parent = l
	if props then
		for k, v in props do
			(l :: any)[k] = v
		end
	end
	l.Parent = parent
	return l
end

-- Chamado em todo clique de botão (o SoundController liga o som de clique aqui).
Ui.ClickHook = nil :: (() -> ())?

function Ui.Button(
	parent: Instance,
	text: string,
	color: Color3?,
	onClick: () -> (),
	size: UDim2?,
	enabled: boolean?
): TextButton
	local b = Instance.new("TextButton")
	b.Size = size or UDim2.new(0, 150, 0, 40)
	b.BackgroundColor3 = color or T.Accent
	b.Font = T.Font
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextScaled = true
	b.Text = text
	b.AutoButtonColor = true
	b.RichText = true
	Ui.Corner(b, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = b
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 20
	limit.Parent = b
	if enabled == false then
		b.BackgroundColor3 = T.PanelLight
		b.TextColor3 = T.TextDim
		b.AutoButtonColor = false
	else
		b.Activated:Connect(function()
			local hook = Ui.ClickHook
			if hook then
				hook()
			end
			onClick()
		end)
	end
	b.Parent = parent
	return b
end

-- Lista com rolagem que cresce conforme o conteúdo.
function Ui.Scroll(parent: Instance, size: UDim2, gap: number?, horizontal: boolean?): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.Size = size
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 6
	s.ScrollBarImageColor3 = T.Stroke
	s.CanvasSize = UDim2.new()
	s.AutomaticCanvasSize = if horizontal then Enum.AutomaticSize.X else Enum.AutomaticSize.Y
	s.ScrollingDirection = if horizontal then Enum.ScrollingDirection.X else Enum.ScrollingDirection.Y
	Ui.ListLayout(s, horizontal, gap)
	s.Parent = parent
	return s
end

function Ui.Grid(parent: Instance, size: UDim2, cell: UDim2, gap: number?): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.Size = size
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 6
	s.ScrollBarImageColor3 = T.Stroke
	s.CanvasSize = UDim2.new()
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	local g = Instance.new("UIGridLayout")
	g.CellSize = cell
	g.CellPadding = UDim2.new(0, gap or 6, 0, gap or 6)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = s
	s.Parent = parent
	return s
end

-- Remove o conteúdo de um container, mantendo layouts, paddings e restrições.
function Ui.Clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

--------------------------------------------------------------------------------
-- Tela, janelas e avisos
--------------------------------------------------------------------------------

function Ui.Screen(): ScreenGui
	if screen then
		return screen
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "GameUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = false

	-- Escala: telas pequenas (celular) diminuem a UI, telas grandes aumentam um pouco.
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function updateScale()
		local camera = Workspace.CurrentCamera
		if camera then
			local v = camera.ViewportSize
			scale.Scale = math.clamp(math.min(v.X / 1280, v.Y / 720), 0.55, 1.25)
		end
	end
	updateScale()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	screen = gui
	return gui
end

function Ui.CloseAll(except: Window?)
	for _, w in windows do
		if w ~= except and w.IsOpen() then
			w.Close()
		end
	end
end

function Ui.Window(name: string, title: string, size: Vector2): Window
	local gui = Ui.Screen()
	local frame = Ui.Frame(gui, UDim2.fromOffset(size.X, size.Y), T.Background, 0.05)
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Visible = false
	frame.ZIndex = 5
	Ui.Corner(frame, 14)
	Ui.Stroke(frame, T.Stroke, 3)

	local header = Ui.Frame(frame, UDim2.new(1, 0, 0, 48), T.Panel)
	Ui.Corner(header, 14)
	Ui.Label(header, title, UDim2.new(1, -70, 1, -10), {
		Position = UDim2.fromOffset(16, 5),
		Font = T.Font,
		TextColor3 = T.Accent,
	})

	local body = Ui.Frame(frame, UDim2.new(1, -24, 1, -64), T.Background, 1)
	body.Position = UDim2.fromOffset(12, 56)

	local openCallbacks: { () -> () } = {}
	local window: Window
	window = {
		Name = name,
		Frame = frame,
		Body = body,
		Open = function()
			Ui.CloseAll(window)
			frame.Visible = true
			for _, cb in openCallbacks do
				task.spawn(cb)
			end
		end,
		Close = function()
			frame.Visible = false
		end,
		Toggle = function()
			if frame.Visible then
				window.Close()
			else
				window.Open()
			end
		end,
		IsOpen = function()
			return frame.Visible
		end,
		OnOpen = function(cb)
			table.insert(openCallbacks, cb)
		end,
	}

	local close = Ui.Button(header, "X", T.Bad, function()
		window.Close()
	end, UDim2.fromOffset(38, 38))
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -6, 0.5, 0)

	table.insert(windows, window)
	return window
end

function Ui.Toast(text: string, color: Color3?)
	local gui = Ui.Screen()
	local label = toastLabel
	if not label then
		local l = Ui.Label(gui, "", UDim2.fromOffset(560, 40), {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 70),
			BackgroundColor3 = T.Background,
			BackgroundTransparency = 0.15,
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = T.Font,
			ZIndex = 20,
		})
		Ui.Corner(l, 10)
		Ui.Stroke(l, T.Stroke, 2)
		toastLabel = l
		label = l
	end
	assert(label)
	toastToken += 1
	local token = toastToken
	label.Text = text
	label.TextColor3 = color or T.Text
	label.Visible = true
	label.TextTransparency = 0
	task.delay(2.6, function()
		if token == toastToken and label then
			TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			task.wait(0.3)
			if token == toastToken then
				label.Visible = false
			end
		end
	end)
end

function Ui.FormatNumber(n: number): string
	local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx" }
	local i = 1
	while math.abs(n) >= 1000 and i < #suffixes do
		n /= 1000
		i += 1
	end
	if i == 1 then
		return tostring(math.floor(n))
	end
	return string.format("%.1f%s", n, suffixes[i])
end

function Ui.Hex(color: Color3): string
	return string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
end

return Ui
