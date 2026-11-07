--!strict
-- Efeitos sonoros (somente no cliente). IDs da Creator Store, preferindo bibliotecas licenciadas
-- (Pro Sound Effects / APM) e uploads genéricos. Para trocar um som, mude só a tabela abaixo.
-- Se um som não carregar (áudio privado/moderado), o jogo segue normalmente sem ele.

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local State = require(script.Parent.State)

local SOUNDS: { [string]: { Id: string, Volume: number } } = {
	RollSpin = { Id = "rbxassetid://91159774426415", Volume = 0.5 },
	RevealCommon = { Id = "rbxassetid://1293433423", Volume = 0.5 },
	RevealRare = { Id = "rbxassetid://6079105785", Volume = 0.6 },
	RevealLegendary = { Id = "rbxassetid://1839881844", Volume = 0.7 }, -- APM "Spinning Around (b)"
	Swing = { Id = "rbxassetid://5789211405", Volume = 0.5 },
	HeavyHit = { Id = "rbxassetid://9125672726", Volume = 0.35 }, -- Pro Sound Effects
	Shot = { Id = "rbxassetid://2436180558", Volume = 0.4 },
	ZombieKill = { Id = "rbxassetid://123559569929123", Volume = 0.3 },
	ZombieGroan = { Id = "rbxassetid://106129958887908", Volume = 0.4 },
	Cash = { Id = "rbxassetid://1319346243", Volume = 0.5 },
	Fuse = { Id = "rbxassetid://9116673944", Volume = 0.5 }, -- Pro Sound Effects
	Equip = { Id = "rbxassetid://123559569929123", Volume = 0.4 },
	Build = { Id = "rbxassetid://6079105785", Volume = 0.5 },
	Defeat = { Id = "rbxassetid://104473748336275", Volume = 0.5 },
}

local SoundController = {}

local instances: { [string]: Sound } = {}
local lastKillSound = 0
local lastAlive = 0

function SoundController.Play(name: string)
	local sound = instances[name]
	if sound and sound.IsLoaded then
		SoundService:PlayLocalSound(sound)
	end
end

-- Som da revelação conforme o melhor tier sorteado.
function SoundController.PlayReveal(bestTier: number)
	if bestTier >= 6 then
		SoundController.Play("RevealLegendary")
	elseif bestTier >= 3 then
		SoundController.Play("RevealRare")
	else
		SoundController.Play("RevealCommon")
	end
end

function SoundController.PlayAttack(pattern: string, hits: number)
	if pattern == "Line" then
		SoundController.Play("Shot")
	else
		SoundController.Play("Swing")
	end
	if hits > 0 and pattern == "Circle" then
		SoundController.Play("HeavyHit")
	end
end

function SoundController.Start()
	local folder = Instance.new("Folder")
	folder.Name = "GameSounds"
	folder.Parent = SoundService
	local list = {}
	for name, def in SOUNDS do
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = def.Id
		s.Volume = def.Volume
		s.Parent = folder
		instances[name] = s
		table.insert(list, s)
	end
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, list)
	end)

	-- Eventos da horda: início (gemido), abates (estalo, limitado) e derrota (alarme).
	State.OnHordeEvent(function(path, value)
		local key = path[1]
		if key == "State" and value == "Active" then
			SoundController.Play("ZombieGroan")
		elseif key == "State" and value == "Defeated" then
			SoundController.Play("Defeat")
		elseif key == "Alive" then
			local decreased = type(value) == "number" and value < lastAlive
			lastAlive = if type(value) == "number" then value else lastAlive
			local now = os.clock()
			if decreased and State.Horde and State.Horde.State == "Active" and now - lastKillSound > 0.15 then
				lastKillSound = now
				SoundController.Play("ZombieKill")
			end
		end
	end)
end

return SoundController
