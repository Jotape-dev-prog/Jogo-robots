--!strict
-- Nomes dos remotes. O servidor cria; o cliente espera.
-- Todas as ações do cliente são RemoteFunctions (pedido → resposta {Ok, Error?, ...}).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Functions = {
	"Roll", -- (count: number) -> resultados da roleta
	"Fuse", -- (key: string) -> forja 3 → 1
	"Sell", -- (key: string, amount: number)
	"Equip", -- (cell: string, slot: string, key: string | "") hexágono "A1".."D7"
	"MoveRobot", -- (from: string, to: string) move ou troca robôs de hexágono
	"EquipBest", -- () preenche os pads com as melhores peças
	"SetTargeting", -- (cell: string, mode: string)
	"SetAutoSettings", -- (autoFuse: boolean, autoSellBelowTier: number)
	"BuyUpgrade", -- (name: string)
	"StartFromCheckpoint", -- (wave: number)
	"SetHordePaused", -- (paused: boolean) pausa/retoma as hordas do jogador (foco no tycoon)
	"Attack", -- (aim: Vector3?) golpe do avatar
	"EquipAvatarWeapon", -- (key: string | "")
	"EquipWorker", -- (lineId: string, slot: string, key: string | "")
	"BuyFactoryLine", -- () compra a próxima linha (mesmo efeito do painel)
	"DevGiveCash", -- (amount) SÓ NO STUDIO: dinheiro para testes
}

local FOLDER_NAME = "Remotes"

function Net.Folder(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder :: Folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function Net.Function(name: string): RemoteFunction
	return Net.Folder():WaitForChild(name) :: RemoteFunction
end

return Net
