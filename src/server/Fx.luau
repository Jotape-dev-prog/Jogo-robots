--!strict
-- Efeitos visuais de combate: o servidor só AVISA o que aconteceu (padrão do golpe, origem,
-- direção, onde acertou); cada cliente desenha. Os avisos de um frame vão juntos num único
-- RemoteEvent para economizar rede.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Items = require(ReplicatedStorage.Shared.Config.Items)

local Fx = {}

local event: RemoteEvent? = nil
local queue: { any } = {}
local MAX_PER_FRAME = 60

-- weapon: padrão do golpe; hits: posições atingidas; source: UserId do avatar (0 = robô)
function Fx.Attack(
	weapon: Items.WeaponStats,
	origin: Vector3,
	dir: Vector3,
	hits: { Vector3 },
	source: number?
)
	if #queue >= MAX_PER_FRAME then
		return
	end
	table.insert(queue, {
		p = weapon.Pattern,
		o = origin,
		d = Vector3.new(dir.X, 0, dir.Z),
		r = weapon.Range,
		a = weapon.Angle or 90,
		h = hits,
		s = weapon.Stun, -- segundos de atordoamento (martelo)
		u = source or 0,
	})
end

function Fx.Start()
	local folder = require(ReplicatedStorage.Shared.Net).Folder()
	local remote = Instance.new("RemoteEvent")
	remote.Name = "FxEvent"
	remote.Parent = folder
	event = remote
	RunService.Heartbeat:Connect(function()
		if #queue == 0 or not event then
			return
		end
		local batch = queue
		queue = {}
		event:FireAllClients(batch)
	end)
end

return Fx
