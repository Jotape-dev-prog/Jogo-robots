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
	Click = { Id = "rbxassetid://88442833509532", Volume = 0.35 },
	PvpAlert = { Id = "rbxassetid://123203327964846", Volume = 0.45 }, -- buzina longa: centro abriu
}

-- Sons 3D (tocam no lugar do evento, mais baixos de longe).
local SOUNDS_3D: { [string]: { Id: string, Volume: number } } = {
	Growl = { Id = "rbxassetid://129294628821291", Volume = 0.6 },
	Swing = { Id = "rbxassetid://5789211405", Volume = 0.45 },
	Shot = { Id = "rbxassetid://2436180558", Volume = 0.35 },
	HeavyHit = { Id = "rbxassetid://9125672726", Volume = 0.3 },
}
local MAX_3D_PER_SECOND = 8

local SoundController = {}

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Ui = require(script.Parent.Ui)

local emitter: Part? = nil
local played3d = 0
local windowStart = 0

-- Toca um som 3D numa posição do mundo (com limite por segundo para não virar barulho).
function SoundController.PlayAt(name: string, position: Vector3)
	local def = SOUNDS_3D[name]
	local camera = Workspace.CurrentCamera
	if not def or not camera or (camera.CFrame.Position - position).Magnitude > 90 then
		return
	end
	local now = os.clock()
	if now - windowStart > 1 then
		windowStart, played3d = now, 0
	end
	if played3d >= MAX_3D_PER_SECOND then
		return
	end
	played3d += 1
	local holder = Instance.new("Attachment")
	holder.WorldPosition = position
	holder.Parent = emitter
	local s = Instance.new("Sound")
	s.SoundId = def.Id
	s.Volume = def.Volume
	s.PlaybackSpeed = 0.9 + math.random() * 0.2
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = 90
	s.Parent = holder
	s:Play()
	task.delay(4, function()
		holder:Destroy()
	end)
end

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

	-- Peça âncora (invisível, sem colisão) onde ficam os sons 3D temporários.
	local anchor = Instance.new("Part")
	anchor.Name = "Sound3D"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new()
	anchor.Parent = Workspace
	emitter = anchor

	Ui.ClickHook = function()
		SoundController.Play("Click")
	end

	-- Gemidos 3D: de vez em quando um zumbi da própria base rosna onde ele está.
	task.spawn(function()
		while true do
			task.wait(3 + math.random() * 4)
			local horde = State.Horde
			if horde and horde.State == "Active" and not horde.Paused then
				local myBase: Instance? = nil
				local bases = Workspace:FindFirstChild("Bases")
				for _, base in (if bases then bases:GetChildren() else {}) do
					if base:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId then
						myBase = base
					end
				end
				local zombies = if myBase then myBase:FindFirstChild("Zombies") else nil
				local list = if zombies then zombies:GetChildren() else {}
				if #list > 0 then
					local z = list[math.random(1, #list)]
					if z:IsA("BasePart") then
						SoundController.PlayAt("Growl", z.Position)
					end
				end
			end
		end
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
