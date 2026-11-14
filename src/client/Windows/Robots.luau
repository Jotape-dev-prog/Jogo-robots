--!strict
-- Tela do Estande de Montagem (abre no estande da base): escolher o hexágono, encaixar as peças
-- do inventário em cada encaixe do robô e posicionar. Colmeia 4 fileiras × até 7 colunas (A = frente, voltada para os zumbis).
-- Clique num robô para ver/editar; depois clique noutro hexágono para mover ou trocar de lugar.
-- (Também dá para arrastar os robôs direto no mundo 3D — ver GridController.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Grid = require(Shared.Config.Grid)
local Items = require(Shared.Config.Items)

local Ui = require(script.Parent.Parent.Ui)
local State = require(script.Parent.Parent.State)
local Sound = require(script.Parent.Parent.SoundController)
local Common = require(script.Parent.Common)

local T = Ui.Theme

local Robots = {}

local HEX_W, HEX_H = 70, 58
local selected: string? = nil
local pickSlot = "Weapon" -- encaixe cujas peças estão sendo mostradas
local board: Frame
local details: Frame
local window: Ui.Window

local function weaponIcon(key: string): string
	local item = Items.Parse(key)
	if not item then
		return ""
	end
	return if item.Type == "Sword" then "🗡" elseif item.Type == "Hammer" then "🔨" else "🔫"
end

local refresh: () -> ()

function refresh()
	local data, horde = State.Data, State.Horde
	if not data then
		return
	end
	local columns = Grid.Columns(data.Upgrades.Grid)
	local hpByCell = if horde and horde.Robots then horde.Robots else {}

	Ui.Clear(board)
	Ui.Label(board, "▲ zumbis vêm por aqui (fileira A)", UDim2.new(1, 0, 0, 18), {
		TextColor3 = T.Bad,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	for rowIndex, row in Grid.Rows do
		for column = 1, Grid.MaxColumns do
			local cell = `{row}{column}`
			local unlocked = column <= columns
			local robot = data.Grid[cell]
			local offsetX = (column - 1) * (HEX_W + 6) + (if rowIndex % 2 == 0 then (HEX_W + 6) / 2 else 0)
			local offsetY = 24 + (rowIndex - 1) * (HEX_H + 4)
			local text: string
			local color: Color3
			if not unlocked then
				text = `🔒\n<font size="11">{cell}</font>`
				color = T.Background
			elseif robot then
				local hp = hpByCell[cell]
				local hpText = if hp
						and hp.MaxHp > 0
						and hp.Hp <= 0
					then "💥"
					elseif hp and hp.MaxHp > 0 then `{math.floor(hp.Hp / hp.MaxHp * 100)}%`
					else ""
				text =
					`{weaponIcon(robot.Weapon)} <font size="11">{cell}</font>\n<font size="12">{hpText}</font>`
				color = Common.TierColor(robot.Weapon ~= "" and robot.Weapon or robot.Torso)
			else
				text = `<font size="12">{cell}</font>`
				color = T.PanelLight
			end
			local button = Ui.Button(board, text, color, function()
				if not unlocked then
					Ui.Toast("Libere mais colunas em Upgrades", T.TextDim)
					return
				end
				if selected and selected ~= cell and data.Grid[selected] then
					-- Segundo clique: mover / trocar
					local from = selected
					selected = cell
					local r = State.Call("MoveRobot", from, cell)
					if r and r.Ok then
						Sound.Play("Equip")
					end
				else
					selected = if selected == cell then nil else cell
					refresh()
				end
			end, UDim2.fromOffset(HEX_W, HEX_H))
			button.Position = UDim2.fromOffset(offsetX, offsetY)
			if not unlocked then
				button.TextColor3 = T.TextDim
			end
			if cell == selected then
				Ui.Stroke(button, Color3.new(1, 1, 1), 3)
			end
		end
	end
	Ui.Label(board, "▼ núcleo (fileira D)", UDim2.new(1, 0, 0, 18), {
		Position = UDim2.fromOffset(0, 24 + 4 * (HEX_H + 4)),
		TextColor3 = T.Info,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	-- Painel de detalhes do hexágono selecionado
	Ui.Clear(details)
	local top = Ui.Frame(details, UDim2.new(1, 0, 0, 36), T.Background, 1)
	top.LayoutOrder = 0
	Ui.ListLayout(top, true, 8)
	Ui.Button(top, "Equipar melhores", T.Good, function()
		State.Call("EquipBest")
		Sound.Play("Equip")
	end, UDim2.fromOffset(160, 34))
	Ui.Label(top, `Robôs: {Common.RobotCount(data)}/{columns * #Grid.Rows}`, UDim2.fromOffset(150, 24))

	local cell = selected
	if not cell then
		Ui.Label(
			details,
			"Clique num hexágono para montar ou editar o robô dele. Com um robô selecionado, clique em outro hexágono para mover.",
			UDim2.new(1, 0, 0, 40),
			{
				TextColor3 = T.TextDim,
				TextWrapped = true,
			}
		).LayoutOrder =
			1
		return
	end
	if not Grid.IsUnlocked(cell, columns) then
		return
	end
	-- Hexágono vazio também pode ser montado: escolher a primeira peça cria o robô.
	local robot = data.Grid[cell]
		or { Head = "", Torso = "", Arms = "", Legs = "", Weapon = "", Targeting = "Nearest" }
	local exists = data.Grid[cell] ~= nil
	local hp = hpByCell[cell]
	local hpText = if hp and exists then `HP {Ui.FormatNumber(hp.Hp)}/{Ui.FormatNumber(hp.MaxHp)}` else ""
	local broken = exists and hp and hp.Hp <= 0
	local header = Ui.Frame(details, UDim2.new(1, 0, 0, 28), T.Background, 1)
	header.LayoutOrder = 1
	Ui.Label(
		header,
		`<b>{if exists then "Robô" else "Novo robô em"} {cell}</b>  {hpText}{if broken
			then "  <font color='#ff6050'>💥 quebrado — volta só após uma derrota</font>"
			else ""}`,
		UDim2.new(1, -170, 1, 0)
	)
	if exists then
		local targetButton = Ui.Button(
			header,
			`🎯 {Common.TargetingNames[robot.Targeting]}`,
			T.Info,
			function()
				State.Call("SetTargeting", cell, Common.TargetingCycle[robot.Targeting])
			end,
			UDim2.fromOffset(165, 28)
		)
		targetButton.Position = UDim2.new(1, -165, 0, 0)
	end

	-- Encaixes do robô: clique num encaixe para escolher a peça dele.
	local chips = Ui.Frame(details, UDim2.new(1, 0, 0, 48), T.Background, 1)
	chips.LayoutOrder = 2
	Ui.ListLayout(chips, true, 6)
	for order, slot in Common.SlotOrder do
		local chip = Common.SlotChip(chips, slot, robot[slot], function()
			pickSlot = slot
			refresh()
		end)
		chip.LayoutOrder = order
		if slot == pickSlot then
			Ui.Stroke(chip, Color3.new(1, 1, 1), 3)
		end
	end

	-- Peças livres do inventário que servem no encaixe escolhido (melhores primeiro).
	local current = robot[pickSlot]
	Ui.Label(
		details,
		`Peças para <b>{Common.SlotNames[pickSlot]}</b> — clique para encaixar:`,
		UDim2.new(1, 0, 0, 20),
		{ TextColor3 = T.Accent }
	).LayoutOrder =
		3
	local picker = Ui.Scroll(details, UDim2.new(1, 0, 0, 66), 6, true)
	picker.LayoutOrder = 4
	local order = 0
	if current ~= "" then
		Ui.Button(picker, "✖ Tirar", T.Bad, function()
			State.Call("Equip", cell, pickSlot, "")
		end, UDim2.fromOffset(84, 56), not broken).LayoutOrder =
			0
	end
	local options = {}
	for key, count in data.Inventory do
		local item = Items.Parse(key)
		if item and item.Slot == pickSlot and key ~= current then
			local free = count - Common.EquippedCount(data, key)
			if free > 0 then
				table.insert(options, { Key = key, Tier = item.Tier, Free = free })
			end
		end
	end
	table.sort(options, function(a, b)
		if a.Tier ~= b.Tier then
			return a.Tier > b.Tier
		end
		return a.Key < b.Key
	end)
	for _, option in options do
		order += 1
		local detail = if pickSlot == "Weapon" then Common.Short(option.Key) else Common.TierName(option.Key)
		local button = Ui.Button(
			picker,
			`{detail}\n<font size="12">x{option.Free}</font>`,
			Common.TierColor(option.Key),
			function()
				local r = State.Call("Equip", cell, pickSlot, option.Key)
				if r and r.Ok then
					Sound.Play("Equip")
				end
			end,
			UDim2.fromOffset(104, 56),
			not broken
		)
		button.LayoutOrder = order
	end
	if #options == 0 and current == "" then
		Ui.Label(
			picker,
			"Nenhuma peça livre para este encaixe — gire a roleta.",
			UDim2.fromOffset(420, 40),
			{
				TextColor3 = T.TextDim,
			}
		)
	end
end

function Robots.Select(cell: string?)
	selected = cell
	if window and window.IsOpen() then
		refresh()
	end
end

function Robots.Create(): Ui.Window
	window = Ui.Window("Robots", "🔧 Estande de Montagem", Vector2.new(640, 640))
	board = Ui.Frame(window.Body, UDim2.new(1, 0, 0, 300), T.Background, 1)
	details = Ui.Frame(window.Body, UDim2.new(1, 0, 1, -306), T.Panel)
	details.Position = UDim2.fromOffset(0, 306)
	Ui.Corner(details, 10)
	Ui.Padding(details, 8)
	Ui.ListLayout(details, false, 6)
	window.OnOpen(refresh)
	State.OnChange(function()
		if window.IsOpen() then
			refresh()
		end
	end)
	return window
end

return Robots
