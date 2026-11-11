--!strict
-- Ciclo dia/noite com iluminação dinâmica (GDD 2.7).
-- Um dia completo dura DAY_SECONDS. A noite não fica escura demais: a luz ambiente sobe
-- um pouco para que zumbis e robôs continuem visíveis.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local DAY_SECONDS = 24 * 60 -- 1 minuto real = 1 hora do jogo
local NIGHT_AMBIENT = Color3.fromRGB(105, 110, 145) -- noite azulada, mas legível
local NIGHT_BRIGHTNESS = 1.8

local WorldService = {}

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- 0 = dia pleno, 1 = noite plena (com transições no nascer e no pôr do sol)
local function nightAmount(clock: number): number
	if clock >= 7 and clock <= 17.5 then
		return 0
	elseif clock > 17.5 and clock < 20 then
		return smooth((clock - 17.5) / 2.5)
	elseif clock >= 5 and clock < 7 then
		return 1 - smooth((clock - 5) / 2)
	end
	return 1
end

function WorldService.Start()
	-- Guarda a iluminação de dia que o mapa já tem (o pôr do sol da ambientação).
	local dayAmbient = Lighting.OutdoorAmbient
	local dayBrightness = Lighting.Brightness
	local clock = Lighting.ClockTime

	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < 0.5 then -- atualizar a cada 0,5 s basta e economiza rede
			return
		end
		clock = (clock + accumulated * 24 / DAY_SECONDS) % 24
		accumulated = 0
		local night = nightAmount(clock)
		Lighting.ClockTime = clock
		Lighting.OutdoorAmbient = dayAmbient:Lerp(NIGHT_AMBIENT, night)
		Lighting.Brightness = dayBrightness + (NIGHT_BRIGHTNESS - dayBrightness) * night
	end)
end

return WorldService
