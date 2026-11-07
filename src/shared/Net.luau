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
	"Equip", -- (pad: string, slot: string, key: string | "")
	"EquipBest", -- () preenche os pads com as melhores peças
	"SetTargeting", -- (pad: string, mode: string)
	"SetAutoSettings", -- (autoFuse: boolean, autoSellBelowTier: number)
	"BuyUpgrade", -- (name: string)
	"StartFromCheckpoint", -- (wave: number)
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
