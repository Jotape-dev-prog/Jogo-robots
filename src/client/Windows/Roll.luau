--!strict
-- Janela da roleta: chances por tier (já com sorte), giro x1 / máximo, Auto-Fundir, Auto-Vender e resultados.
-- As chances exibidas vêm da mesma fórmula do servidor (Rarity.Odds), exigência para caixas pagas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Economy = require(Shared.Config.Economy)
local Items = require(Shared.Config.Items)

local Ui = require(script.Parent.Parent.Ui)
local State = require(script.Parent.Parent.State)
local Sound = require(script.Parent.Parent.SoundController)

local T = Ui.Theme

local Roll = {}

local resultsArea: ScrollingFrame
local oddsList: Frame
local controls: Frame
local spinning = false
local skipAnimation = false

local function luck(data: any): number
	return 1 + (data.Upgrades.Luck or 0) * Economy.Upgrades.Luck.PerLevel
end

local function maxRolls(data: any): number
	return math.min(1 + (data.Upgrades.Rolls or 0), Economy.MaxSimultaneousRolls)
end

local function showResults(results: { any }, fused: number)
	Ui.Clear(resultsArea)
	table.sort(results, function(a, b)
		return a.Tier > b.Tier
	end)
	for i, r in results do
		local tier = Rarity.Get(r.Tier)
		local tile = Ui.Frame(resultsArea, UDim2.fromOffset(122, 92), T.Panel)
		tile.LayoutOrder = i
		Ui.Corner(tile, 10)
		Ui.Stroke(tile, tier.Color, if r.Tier >= 5 then 4 else 2)
		Ui.Padding(tile, 6)
		Ui.Label(tile, tier.Name, UDim2.new(1, 0, 0, 22), {
			TextColor3 = tier.Color,
			Font = T.Font,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local name = Items.DisplayName(r.Key):gsub(" " .. tier.Name, "")
		Ui.Label(tile, name, UDim2.new(1, 0, 0, 30), {
			Position = UDim2.fromOffset(0, 24),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		if r.Sold then
			Ui.Label(tile, "vendido", UDim2.new(1, 0, 0, 18), {
				Position = UDim2.fromOffset(0, 58),
				TextColor3 = T.TextDim,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
		end
		tile.BackgroundTransparency = 1
		TweenService:Create(tile, TweenInfo.new(0.25), { BackgroundTransparency = 0 }):Play()
	end
	if fused > 0 then
		Ui.Toast(`Auto-Fundir: {fused} fusões`, T.Good)
	end
end

local function doRoll(count: number)
	if spinning then
		return
	end
	spinning = true
	Sound.Play("RollSpin")
	if not skipAnimation then
		-- Suspense curto: pisca cores de tiers aleatórios antes de revelar.
		Ui.Clear(resultsArea)
		local flash = Ui.Label(resultsArea, "Girando...", UDim2.fromOffset(300, 60), {
			Font = T.Font,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		for _ = 1, 6 do
			flash.TextColor3 = Rarity.Get(math.random(1, 6)).Color
			task.wait(0.08)
		end
	end
	local result = State.Call("Roll", count)
	spinning = false
	if result and result.Ok then
		local best = 1
		for _, r in result.Results do
			best = math.max(best, r.Tier)
		end
		Sound.PlayReveal(best)
		showResults(result.Results, result.Fused)
	else
		Ui.Clear(resultsArea)
	end
end

local function refresh()
	local data = State.Data
	if not data then
		return
	end
	Ui.Clear(oddsList)
	local l = luck(data)
	Ui.Label(oddsList, `<b>Chances</b>  (sorte x{string.format("%.1f", l)})`, UDim2.new(1, 0, 0, 24), {
		TextColor3 = T.Accent,
	}).LayoutOrder =
		0
	for i, odd in Rarity.Odds(l) do
		local tier = Rarity.Get(i)
		local text = if odd >= 0.1 then string.format("%.2f%%", odd) else string.format("%.4f%%", odd)
		local row = Ui.Label(oddsList, `<font color="{Ui.Hex(tier.Color)}">{tier.Name}</font>   {text}`)
		row.LayoutOrder = i
	end
	Ui.Label(oddsList, "80% peças • 20% armas", UDim2.new(1, 0, 0, 20), { TextColor3 = T.TextDim }).LayoutOrder =
		20

	Ui.Clear(controls)
	local n = maxRolls(data)
	Ui.Button(controls, `Girar x1\n({Economy.RollCost})`, T.Accent, function()
		task.spawn(doRoll, 1)
	end, UDim2.fromOffset(150, 56), data.Cash >= Economy.RollCost).LayoutOrder =
		1
	if n > 1 then
		Ui.Button(controls, `Girar x{n}\n({Ui.FormatNumber(n * Economy.RollCost)})`, T.Accent, function()
			task.spawn(doRoll, n)
		end, UDim2.fromOffset(150, 56), data.Cash >= n * Economy.RollCost).LayoutOrder =
			2
	end
	local s = data.Settings
	Ui.Button(
		controls,
		if s.AutoFuse then "Auto-Fundir: ON" else "Auto-Fundir: OFF",
		if s.AutoFuse then T.Good else T.PanelLight,
		function()
			State.Call("SetAutoSettings", not s.AutoFuse, s.AutoSellBelowTier)
		end,
		UDim2.fromOffset(150, 40)
	).LayoutOrder =
		3
	local sellText = if s.AutoSellBelowTier == 0
		then "Auto-Vender: OFF"
		else `Vende abaixo de {Rarity.Get(s.AutoSellBelowTier).Name}`
	Ui.Button(controls, sellText, if s.AutoSellBelowTier > 0 then T.Bad else T.PanelLight, function()
		-- 0 (desligado) → 2 (vende Comum) → 3 → 4 → 0
		local nextValue = if s.AutoSellBelowTier >= 4
			then 0
			elseif s.AutoSellBelowTier == 0 then 2
			else s.AutoSellBelowTier + 1
		State.Call("SetAutoSettings", s.AutoFuse, nextValue)
	end, UDim2.fromOffset(150, 40)).LayoutOrder =
		4
	Ui.Button(
		controls,
		if skipAnimation then "Animação: OFF" else "Animação: ON",
		T.PanelLight,
		function()
			skipAnimation = not skipAnimation
			refresh()
		end,
		UDim2.fromOffset(150, 34)
	).LayoutOrder =
		5
end

function Roll.Create(): Ui.Window
	local window = Ui.Window("Roll", "🎰 Roleta", Vector2.new(720, 440))
	local body = window.Body

	oddsList = Ui.Frame(body, UDim2.new(0, 230, 1, 0), T.Panel)
	Ui.Corner(oddsList, 10)
	Ui.Padding(oddsList, 10)
	Ui.ListLayout(oddsList, false, 2)

	controls = Ui.Frame(body, UDim2.new(0, 160, 1, 0), T.Background, 1)
	controls.Position = UDim2.fromOffset(240, 0)
	Ui.ListLayout(controls, false, 8)

	resultsArea = Ui.Grid(body, UDim2.new(1, -420, 1, 0), UDim2.fromOffset(122, 92), 8)
	resultsArea.Position = UDim2.fromOffset(410, 0)

	window.OnOpen(refresh)
	State.OnChange(function()
		if window.IsOpen() then
			refresh()
		end
	end)
	return window
end

return Roll
