--!strict
-- Bônus temporários por jogador (ex.: vitória no King of the Hill: +15% dinheiro e sorte).
-- Ficam só na memória do servidor: valem até expirar ou até o jogador sair.

local Buffs = {}

type Buff = { Multiplier: number, Expires: number }

local buffs: { [Player]: { [string]: Buff } } = {}

-- Multiplicador ativo (1 se não houver).
function Buffs.Get(player: Player, name: string): number
	local perPlayer = buffs[player]
	local buff = if perPlayer then perPlayer[name] else nil
	if not buff or os.time() >= buff.Expires then
		return 1
	end
	return buff.Multiplier
end

-- Define (sem acumular) um bônus por `seconds` segundos.
function Buffs.Set(player: Player, name: string, multiplier: number, seconds: number)
	local perPlayer = buffs[player]
	if not perPlayer then
		perPlayer = {}
		buffs[player] = perPlayer
	end
	perPlayer[name] = { Multiplier = multiplier, Expires = os.time() + seconds }
	player:SetAttribute(name .. "BuffUntil", os.time() + seconds) -- o HUD mostra o bônus
end

function Buffs.Clear(player: Player)
	buffs[player] = nil
end

game:GetService("Players").PlayerRemoving:Connect(Buffs.Clear)

return Buffs
