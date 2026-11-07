--!strict
-- HUD PROVISÓRIO para testar o core loop. Será substituído pelas telas desenhadas (Figma).
-- Mostra dinheiro, horda, invasões e tem botões de roleta / equipar / auto-fundir / checkpoint.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local Economy = require(Shared.Config.Economy)

local player = Players.LocalPlayer

local Hud = {}

local playerData: any = nil
local hordeState: any = nil

local labels: { [string]: TextLabel } = {}
local buttons: { [string]: TextButton } = {}
local toastLabel: TextLabel? = nil
local toastToken = 0

local function formatNumber(n: number): string
	local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi" }
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

local function toast(text: string, color: Color3?)
	local label = toastLabel
	if not label then
		return
	end
	toastToken += 1
	local token = toastToken
	label.Text = text
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.Visible = true
	task.delay(3, function()
		if token == toastToken then
			label.Visible = false
		end
	end)
end

local function call(name: string, ...: any): any
	local ok, result = pcall(Net.Function(name).InvokeServer, Net.Function(name), ...)
	if not ok then
		toast("Falha de conexão", Color3.fromRGB(255, 90, 90))
		return nil
	end
	if not result.Ok then
		toast(result.Error or "Erro", Color3.fromRGB(255, 120, 90))
	end
	return result
end

--------------------------------------------------------------------------------
-- Atualização
--------------------------------------------------------------------------------

local function maxRolls(): number
	if not playerData then
		return 1
	end
	return math.min(1 + (playerData.Data.Upgrades.Rolls or 0), Economy.MaxSimultaneousRolls)
end

local function refresh()
	if playerData then
		local data = playerData.Data
		labels.Cash.Text = `💰 {formatNumber(data.Cash)}`
		labels.Checkpoint.Text = `Maior checkpoint: {data.Horde.HighestCheckpoint}`
		local n = maxRolls()
		buttons.Roll.Text = `Girar x{n} ({formatNumber(n * Economy.RollCost)})`
		buttons.AutoFuse.Text = if data.Settings.AutoFuse then "Auto-Fundir: ON" else "Auto-Fundir: OFF"
	end
	if hordeState then
		local s = hordeState.Data
		local boss = if s.Boss then " 💀 BOSS" else ""
		labels.Wave.Text = `Horda {s.Wave}{boss}`
		labels.Invasions.Text = `Invasões: {s.Invasions}/{s.MaxInvasions}`
		if s.Paused then
			labels.Status.Text = "⏸ Hordas pausadas (PvP)"
		elseif s.State == "Active" then
			labels.Status.Text = `Zumbis restantes: {s.Remaining}`
		elseif s.State == "Defeated" then
			labels.Status.Text = `Derrota! -{formatNumber(s.LastLoss)} • recomeça em {s.Timer}s`
		else
			labels.Status.Text = `Próxima horda em {s.Timer}s`
		end
		buttons.Checkpoint.Visible = s.State ~= "Active"
	end
end

function Hud.BindPlayerData(replica: any)
	playerData = replica
	replica:OnChange(refresh)
	refresh()
end

function Hud.BindHordeState(replica: any)
	hordeState = replica
	replica:OnChange(function(action, path, value)
		if path[1] == "State" and value == "Defeated" then
			toast("A base foi invadida 3 vezes!", Color3.fromRGB(255, 80, 80))
		end
		refresh()
	end)
	refresh()
end

--------------------------------------------------------------------------------
-- Construção
--------------------------------------------------------------------------------

local function makeLabel(name: string, parent: Instance, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(1, 0, 0, 26)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.LayoutOrder = order
	label.Text = ""
	label.Parent = parent
	labels[name] = label
	return label
end

local function makeButton(
	name: string,
	text: string,
	color: Color3,
	parent: Instance,
	onClick: () -> ()
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(0, 170, 0, 46)
	button.BackgroundColor3 = color
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = text
	button.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = button
	button.Parent = parent
	button.Activated:Connect(onClick)
	buttons[name] = button
	return button
end

function Hud.Build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DebugHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false

	-- Painel de status (canto superior esquerdo)
	local panel = Instance.new("Frame")
	panel.Position = UDim2.new(0, 12, 0, 12)
	panel.Size = UDim2.new(0, 300, 0, 150)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	panel.BackgroundTransparency = 0.35
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = panel
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 2)
	list.Parent = panel

	makeLabel("Cash", panel, 1)
	makeLabel("Wave", panel, 2)
	makeLabel("Invasions", panel, 3)
	makeLabel("Status", panel, 4)
	makeLabel("Checkpoint", panel, 5).TextColor3 = Color3.fromRGB(190, 190, 190)

	-- Barra de botões (parte de baixo)
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -16)
	bar.Size = UDim2.new(0, 720, 0, 46)
	bar.BackgroundTransparency = 1
	bar.Parent = gui
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.Padding = UDim.new(0, 10)
	row.Parent = bar

	makeButton("Roll", "Girar", Color3.fromRGB(200, 120, 20), bar, function()
		local result = call("Roll", maxRolls())
		if result and result.Ok then
			local best = result.Results[1]
			for _, r in result.Results do
				if r.Tier > best.Tier then
					best = r
				end
			end
			local extra = if result.Fused > 0 then ` • {result.Fused} fusões` else ""
			toast(`Melhor: {Items.DisplayName(best.Key)}{extra}`, Rarity.Get(best.Tier).Color)
		end
	end)
	makeButton("EquipBest", "Equipar melhores", Color3.fromRGB(40, 140, 80), bar, function()
		local result = call("EquipBest")
		if result and result.Ok then
			toast("Robôs atualizados")
		end
	end)
	makeButton("AutoFuse", "Auto-Fundir", Color3.fromRGB(90, 70, 160), bar, function()
		if not playerData then
			return
		end
		local settings = playerData.Data.Settings
		local result = call("SetAutoSettings", not settings.AutoFuse, settings.AutoSellBelowTier)
		if result and result.Ok and result.Fused > 0 then
			toast(`{result.Fused} fusões feitas`)
		end
	end)
	makeButton("Checkpoint", "Recomeçar checkpoint", Color3.fromRGB(150, 50, 50), bar, function()
		if playerData then
			call("StartFromCheckpoint", playerData.Data.Horde.HighestCheckpoint)
		end
	end)

	-- Aviso temporário
	local t = Instance.new("TextLabel")
	t.AnchorPoint = Vector2.new(0.5, 1)
	t.Position = UDim2.new(0.5, 0, 1, -76)
	t.Size = UDim2.new(0, 520, 0, 34)
	t.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	t.BackgroundTransparency = 0.3
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.Visible = false
	t.Parent = gui
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0, 8)
	tc.Parent = t
	toastLabel = t

	gui.Parent = player:WaitForChild("PlayerGui")
	refresh()
end

return Hud
