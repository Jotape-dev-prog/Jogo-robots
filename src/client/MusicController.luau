--!strict
-- Música por situação, com troca suave (crossfade):
--   Base (calma) → fora das hordas ou com as hordas pausadas
--   Horde (tensa) → horda em andamento
--   Boss (pesada) → horda de boss
--   Pvp (intensa) → centro aberto
-- Para trocar uma faixa, mude só a tabela TRACKS. Faixa sem ID ou que não carrega é ignorada.

local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local State = require(script.Parent.State)

local TRACKS: { [string]: { Id: string, Volume: number } } = {
	Base = { Id = "", Volume = 0.25 },
	Horde = { Id = "", Volume = 0.3 },
	Boss = { Id = "", Volume = 0.35 },
	Pvp = { Id = "", Volume = 0.35 },
}
local FADE = 1.5

local MusicController = {}

local sounds: { [string]: Sound } = {}
local playing: string? = nil

local function desired(): string
	local pvp, horde = State.Pvp, State.Horde
	if pvp and pvp.Phase == "Open" then
		return "Pvp"
	end
	if horde and horde.State == "Active" and not horde.Paused then
		return if horde.Boss then "Boss" else "Horde"
	end
	return "Base"
end

local function switch(name: string)
	if playing == name then
		return
	end
	local old = if playing then sounds[playing] else nil
	if old then
		local fade = TweenService:Create(old, TweenInfo.new(FADE), { Volume = 0 })
		fade:Play()
		fade.Completed:Once(function()
			if playing ~= old.Name then
				old:Pause()
			end
		end)
	end
	playing = name
	local new = sounds[name]
	if new then
		new.Volume = 0
		if not new.IsPlaying then
			new:Resume()
			if not new.IsPlaying then
				new:Play()
			end
		end
		TweenService:Create(new, TweenInfo.new(FADE), { Volume = TRACKS[name].Volume }):Play()
	end
end

function MusicController.Start()
	local folder = Instance.new("SoundGroup")
	folder.Name = "Music"
	folder.Parent = SoundService
	for name, track in TRACKS do
		if track.Id ~= "" then
			local s = Instance.new("Sound")
			s.Name = name
			s.SoundId = track.Id
			s.Looped = true
			s.Volume = 0
			s.SoundGroup = folder
			s.Parent = folder
			sounds[name] = s
		end
	end
	State.OnChange(function()
		switch(desired())
	end)
end

return MusicController
