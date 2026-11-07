--!strict
-- Grid hexagonal de posicionamento dos robôs (estilo auto-battler).
-- 4 fileiras (A = frente, voltada para os zumbis; D = fundo, perto do núcleo) × até 7 colunas.
-- Começa com 2 colunas (A1–D2, 8 hexágonos) e cada upgrade libera mais uma coluna.
-- Um robô por hexágono: o número de hexágonos liberados é o limite de robôs.

local Grid = {}

Grid.Rows = { "A", "B", "C", "D" }
Grid.StartColumns = 2
Grid.MaxColumns = 7
Grid.HexSpacing = 7.2 -- distância entre centros na mesma fileira (studs)
Grid.RowSpacing = 6.4 -- distância entre fileiras
Grid.HexRadius = 3.4

function Grid.Columns(upgradeLevel: number?): number
	return math.clamp(Grid.StartColumns + (upgradeLevel or 0), Grid.StartColumns, Grid.MaxColumns)
end

-- Todos os hexágonos (liberados ou não), na ordem A1, B1, C1, D1, A2, ...
function Grid.AllCells(): { string }
	local cells = {}
	for column = 1, Grid.MaxColumns do
		for _, row in Grid.Rows do
			table.insert(cells, `{row}{column}`)
		end
	end
	return cells
end

-- Hexágonos liberados para um número de colunas.
function Grid.UnlockedCells(columns: number): { string }
	local cells = {}
	for column = 1, columns do
		for _, row in Grid.Rows do
			table.insert(cells, `{row}{column}`)
		end
	end
	return cells
end

function Grid.Parse(cell: any): (string?, number?)
	if type(cell) ~= "string" or #cell > 3 then
		return nil, nil
	end
	local row, column = string.match(cell, "^([A-D])(%d)$")
	local n = tonumber(column)
	if not row or not n or n < 1 or n > Grid.MaxColumns then
		return nil, nil
	end
	return row, n
end

function Grid.IsUnlocked(cell: any, columns: number): boolean
	local row, column = Grid.Parse(cell)
	return row ~= nil and column ~= nil and column <= columns
end

-- Posição do centro do hexágono no espaço local do grid:
-- X = largura (colunas), Z = profundidade (fileira A é a mais à frente, Z maior).
-- Fileiras B e D são deslocadas meia casa, como numa colmeia.
function Grid.LocalOffset(cell: string): Vector3
	local row, column = Grid.Parse(cell)
	assert(row and column, `Hexágono inválido: {cell}`)
	local rowIndex = table.find(Grid.Rows, row) :: number
	local shift = if rowIndex % 2 == 0 then Grid.HexSpacing / 2 else 0
	-- Sinal negativo: olhando do núcleo para os zumbis, a coluna 1 fica à esquerda (como no tabuleiro).
	local x = -((column - (Grid.MaxColumns + 1) / 2) * Grid.HexSpacing + shift - Grid.HexSpacing / 4)
	local z = ((#Grid.Rows + 1) / 2 - rowIndex) * Grid.RowSpacing
	return Vector3.new(x, 0, z)
end

-- Fileiras da frente preferem armas corpo a corpo; as de trás, rifles.
function Grid.IsFrontRow(cell: string): boolean
	local row = Grid.Parse(cell)
	return row == "A" or row == "B"
end

return Grid
