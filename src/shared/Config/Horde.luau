--!strict
-- Composição e escalonamento das hordas.

export type ZombieSpec = {
	Kind: "Normal" | "Fast" | "Tank" | "Boss",
	Hp: number,
	Speed: number,
	Reward: number,
	ContactDps: number,
}

local Horde = {}

Horde.MaxAlivePerBase = 15 -- Wave Spawning Limit
Horde.SpawnInterval = 0.6
Horde.InvasionsToLose = 3
Horde.CheckpointEvery = 10
Horde.IntermissionSeconds = 4
Horde.DefeatAutoResumeSeconds = 15
Horde.ContactRange = 5 -- distância para zumbi causar dano por contato

local function scale(base: number, wave: number, growth: number): number
	return base * growth ^ (wave - 1)
end

-- Primeira horda de cada checkpoint: 1, 11, 21, ...
function Horde.IsCheckpointWave(wave: number): boolean
	return (wave - 1) % Horde.CheckpointEvery == 0
end

function Horde.CheckpointFor(wave: number): number
	return wave - ((wave - 1) % Horde.CheckpointEvery)
end

function Horde.IsBossWave(wave: number): boolean
	return wave % Horde.CheckpointEvery == 0
end

-- Lista dos zumbis da horda, na ordem de spawn.
function Horde.Build(wave: number): { ZombieSpec }
	local list = {}
	local count = 6 + math.floor(wave * 1.5)
	local hp = scale(20, wave, 1.13)
	local reward = math.floor(scale(4, wave, 1.09))
	local speed = math.min(7 + wave * 0.08, 14)

	for i = 1, count do
		local kind: "Normal" | "Fast" | "Tank" = "Normal"
		if wave >= 4 and i % 5 == 0 then
			kind = "Fast"
		elseif wave >= 7 and i % 7 == 0 then
			kind = "Tank"
		end
		if kind == "Fast" then
			table.insert(
				list,
				{ Kind = kind, Hp = hp * 0.6, Speed = speed * 1.6, Reward = reward, ContactDps = hp * 0.15 }
			)
		elseif kind == "Tank" then
			table.insert(
				list,
				{ Kind = kind, Hp = hp * 3, Speed = speed * 0.7, Reward = reward * 2, ContactDps = hp * 0.3 }
			)
		else
			table.insert(
				list,
				{ Kind = kind, Hp = hp, Speed = speed, Reward = reward, ContactDps = hp * 0.2 }
			)
		end
	end

	if Horde.IsBossWave(wave) then
		table.insert(
			list,
			{ Kind = "Boss", Hp = hp * 20, Speed = speed * 0.6, Reward = reward * 25, ContactDps = hp }
		)
	end
	return list
end

return Horde
