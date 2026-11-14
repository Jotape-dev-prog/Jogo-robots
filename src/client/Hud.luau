--!strict
-- HUD: painel de status (canto superior esquerdo) e barra de menu (embaixo) que abre as janelas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Economy = require(Shared.Config.Economy)
local Items = require(Shared.Config.Items)

local Ui = require(script.Parent.Ui)
local State = require(script.Parent.State)

local T = Ui.Theme

local Hud = {}

local TweenService = game:GetService("TweenService")

local labels: { [string]: TextLabel } = {}
local lastCash: number? = nil
local gainLayer: Frame? = nil -- camada sem layout por cima do painel (para os "+123")
local pendingGain = 0
local gainScheduled = false

-- "+123" subindo do lado do dinheiro (ganhos agrupados a cada 0,4 s).
local function popGain()
	gainScheduled = false
	local amount = pendingGain
	pendingGain = 0
	local layer = gainLayer
	if amount <= 0 or not layer then
		return
	end
	local pop = Ui.Label(layer, `+{Ui.FormatNumber(amount)}`, UDim2.fromOffset(120, 24), {
		Position = UDim2.fromOffset(130, 8),
		TextColor3 = Color3.fromRGB(140, 230, 120),
		Font = T.Font,
		ZIndex = 4,
	})
	TweenService:Create(pop, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(130, -18),
		TextTransparency = 1,
	}):Play()
	task.delay(1, function()
		pop:Destroy()
	end)
end
local invasionBar: Frame? = nil
local pauseButton: TextButton? = nil

local function refresh()
	local data, horde = State.Data, State.Horde
	if data then
		local income = Economy.FactoryIncome(data.Factory.Lines) * (1 + data.Rebirths * 0.5)
		labels.Cash.Text = `💰 <b>{Ui.FormatNumber(data.Cash)}</b>`
		if lastCash and data.Cash > lastCash then
			pendingGain += data.Cash - lastCash
			if not gainScheduled then
				gainScheduled = true
				task.delay(0.4, popGain)
			end
		end
		lastCash = data.Cash
		labels.Factory.Text = `🏭 +{Ui.FormatNumber(income)}/s`
		labels.Weapon.Text = if data.AvatarWeapon ~= ""
			then `⚔ {Items.DisplayName(data.AvatarWeapon)}`
			else "⚔ <font color='#c86450'>Sem arma</font>"
	end
	if horde then
		local boss = if horde.Boss then "  <font color='#ff5050'>💀 BOSS</font>" else ""
		labels.Wave.Text = `🧟 Horda <b>{horde.Wave}</b>{boss}`
		local button = pauseButton
		if button then
			local userPaused = horde.State == "Paused"
			button.Text = if userPaused then "▶ Retomar hordas" else "⏸ Pausar hordas"
			button.BackgroundColor3 = if userPaused then T.Good else T.Bad
		end
		if horde.Paused then
			labels.Status.Text = "⏸ Hordas pausadas (PvP)"
		elseif horde.State == "Paused" then
			labels.Status.Text = "⏸ Hordas pausadas — foco no tycoon"
		elseif horde.State == "Active" then
			labels.Status.Text = `Restantes: {horde.Remaining}`
		elseif horde.State == "Defeated" then
			labels.Status.Text = `<font color='#ff6050'>Base invadida!</font> {horde.Timer}s`
		else
			labels.Status.Text = `Próxima horda em {horde.Timer}s`
		end
		local bar = invasionBar
		if bar then
			for i = 1, horde.MaxInvasions do
				local pip = bar:FindFirstChild(tostring(i)) :: Frame?
				if pip then
					pip.BackgroundColor3 = if i <= horde.Invasions then T.Bad else T.PanelLight
				end
			end
		end
	end
end

function Hud.Build(windows: { [string]: Ui.Window })
	local gui = Ui.Screen()

	-- Painel de status
	local panel = Ui.Frame(gui, UDim2.fromOffset(270, 176), T.Background, 0.2)
	panel.Position = UDim2.fromOffset(12, 12)
	Ui.Corner(panel, 12)
	Ui.Stroke(panel, T.Stroke, 2)
	Ui.Padding(panel, 10)
	Ui.ListLayout(panel, false, 4)
	local layer = Ui.Frame(gui, UDim2.fromOffset(270, 60), T.Background, 1)
	layer.Position = UDim2.fromOffset(12, 12)
	layer.ZIndex = 4
	gainLayer = layer
	labels.Cash = Ui.Label(panel, "💰 0", UDim2.new(1, 0, 0, 30), { Font = T.Font })
	labels.Wave = Ui.Label(panel, "🧟 Horda 1")
	local invRow = Ui.Frame(panel, UDim2.new(1, 0, 0, 18), T.Background, 1)
	Ui.ListLayout(invRow, true, 6)
	Ui.Label(invRow, "Invasões", UDim2.fromOffset(80, 18), { TextColor3 = T.TextDim })
	for i = 1, 3 do
		local pip = Ui.Frame(invRow, UDim2.fromOffset(28, 12), T.PanelLight)
		pip.Name = tostring(i)
		pip.LayoutOrder = i
		Ui.Corner(pip, 4)
	end
	invasionBar = invRow
	labels.Status = Ui.Label(panel, "", UDim2.new(1, 0, 0, 22), { TextColor3 = T.TextDim })
	labels.Factory = Ui.Label(panel, "🏭 +0/s")
	labels.Weapon = Ui.Label(panel, "⚔", UDim2.new(1, 0, 0, 20))

	-- Barra de menu
	local bar = Ui.Frame(gui, UDim2.fromOffset(950, 52), T.Background, 1)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -12)
	local layout = Ui.ListLayout(bar, true, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local entries = {
		{ "Roll", "🎰 Roleta", T.Accent },
		{ "Inventory", "🎒 Inventário", T.Info },
		{ "Factory", "🏭 Fábrica", Color3.fromRGB(150, 110, 60) },
		{ "Upgrades", "⬆ Upgrades", T.Purple },
		{ "Social", "👥 Jogadores", Color3.fromRGB(60, 140, 150) },
	}
	for i, entry in entries do
		local window = windows[entry[1]]
		local b = Ui.Button(bar, entry[2], entry[3], function()
			window.Toggle()
		end, UDim2.fromOffset(125, 48))
		b.LayoutOrder = i
	end
	-- Pausar/retomar as hordas (a fábrica continua rendendo).
	pauseButton = Ui.Button(bar, "⏸ Pausar hordas", T.Bad, function()
		local horde = State.Horde
		State.Call("SetHordePaused", not (horde and horde.State == "Paused"))
	end, UDim2.fromOffset(140, 48));
	(pauseButton :: TextButton).LayoutOrder = #entries + 1

	State.OnChange(refresh)
	refresh()
end

return Hud
