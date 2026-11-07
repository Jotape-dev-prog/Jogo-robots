--!strict
-- Resolução de acertos compartilhada por robôs e avatar.
-- Cone (espada), Circle (martelo, com stun) e Line (rifle, com pierce). Tudo no plano XZ.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Config.Items)
local Types = require(script.Parent.Types)

type Zombie = Types.Zombie

local Combat = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Combat.FlatDistance(a: Vector3, b: Vector3): number
	return flat(a - b).Magnitude
end

-- Retorna os zumbis atingidos por um ataque saindo de `origin` na direção `dir`.
-- `primary` (opcional) garante o alvo principal no ataque em linha.
function Combat.Resolve(
	weapon: Items.WeaponStats,
	origin: Vector3,
	dir: Vector3,
	zombies: { Zombie },
	primary: Zombie?
): { Zombie }
	local hits = {}
	local forward = flat(dir)
	forward = if forward.Magnitude > 1e-3 then forward.Unit else Vector3.zAxis

	if weapon.Pattern == "Circle" then
		for _, z in zombies do
			if #hits >= weapon.MaxTargets then
				break
			end
			if not z.Dead and Combat.FlatDistance(origin, z.Position) <= weapon.Range then
				table.insert(hits, z)
			end
		end
	elseif weapon.Pattern == "Cone" then
		local cosHalf = math.cos(math.rad((weapon.Angle or 90) / 2))
		for _, z in zombies do
			if #hits >= weapon.MaxTargets then
				break
			end
			local offset = flat(z.Position - origin)
			local dist = offset.Magnitude
			if not z.Dead and dist <= weapon.Range and (dist < 1 or offset.Unit:Dot(forward) >= cosHalf) then
				table.insert(hits, z)
			end
		end
	else -- Line (pierce): ordena pela distância ao longo do raio
		local candidates = {}
		for _, z in zombies do
			if not z.Dead then
				local offset = flat(z.Position - origin)
				local along = offset:Dot(forward)
				local side = (offset - forward * along).Magnitude
				if along > 0 and along <= weapon.Range and side <= 3 then
					table.insert(candidates, { Zombie = z, Along = along })
				end
			end
		end
		table.sort(candidates, function(a, b)
			return a.Along < b.Along
		end)
		if primary and not primary.Dead then
			table.insert(hits, primary)
		end
		for _, c in candidates do
			if #hits >= weapon.MaxTargets then
				break
			end
			if c.Zombie ~= primary then
				table.insert(hits, c.Zombie)
			end
		end
	end
	return hits
end

return Combat
