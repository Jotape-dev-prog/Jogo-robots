--!strict
-- Faixa do PvP no topo da tela:
--   • fora do PvP: contagem até o centro abrir;
--   • com o centro aberto: tempo restante, botão para ir/voltar da arena e a barra de captura
--     (quem está capturando, progresso de 30 s e o estado "CONTESTADO").
-- Também mostra o bônus de quem venceu (+15% dinheiro e sorte) enquanto ele durar.

local Players = game:GetService("Players")

local Ui = require(script.Parent.Ui)
local State = require(script.Parent.State)
local Sound = require(script.Parent.SoundController)

local T = Ui.Theme
local player = Players.LocalPlayer

local PvpHud = {}

local banner: Frame
local title: TextLabel
local travel: TextButton
local captureBack: Frame
local captureFill: Frame
local captureText: TextLabel
local buffLabel: TextLabel
local lastPhase = ""

local function clock(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function refresh()
	local pvp = State.Pvp
	if not pvp then
		banner.Visible = false
		return
	end
	banner.Visible = true
	local open = pvp.Phase == "Open"
	if pvp.Phase ~= lastPhase then
		if lastPhase ~= "" and open then
			Ui.Toast("⚔ O centro abriu! Hordas pausadas — domine a zona por 30 s", T.Accent)
			Sound.Play("PvpAlert")
		end
		lastPhase = pvp.Phase
	end

	if open then
		title.Text = `<b>⚔ PvP ABERTO</b>  {clock(pvp.Timer)}`
		travel.Visible = true
		captureBack.Visible = true
		local ratio = math.clamp(pvp.Progress / pvp.Required, 0, 1)
		captureFill.Size = UDim2.fromScale(ratio, 1)
		if pvp.Contested then
			captureFill.BackgroundColor3 = T.Bad
			captureText.Text = "⚠ CONTESTADO — tempo pausado"
		elseif pvp.HolderId ~= 0 then
			local me = pvp.HolderId == player.UserId
			captureFill.BackgroundColor3 = if me then T.Good else T.Accent
			captureText.Text =
				`{if me then "Você" else pvp.HolderName} capturando: {math.floor(pvp.Progress)}/{pvp.Required}s`
		else
			captureFill.BackgroundColor3 = T.Accent
			captureText.Text = "Zona livre — fique sozinho nela por 30 s"
		end
	else
		local waiting = if pvp.Players < pvp.MinPlayers
			then `  <font color="#aaa08f">(precisa de {pvp.MinPlayers} jogadores)</font>`
			else ""
		title.Text = `⚔ PvP em <b>{clock(pvp.Timer)}</b>{waiting}`
		travel.Visible = false
		captureBack.Visible = false
	end

	local untilTime = player:GetAttribute("CashBuffUntil")
	local remaining = if typeof(untilTime) == "number" then untilTime - os.time() else 0
	local buffed = remaining > 0
	buffLabel.Visible = buffed
	if buffed then
		buffLabel.Text = `👑 +15% dinheiro e sorte  {clock(remaining)}`
	end
	buffLabel.Position = UDim2.fromOffset(0, if open then 58 else 30)
	banner.Size = UDim2.fromOffset(420, 36 + (if open then 26 else 0) + (if buffed then 24 else 0))
end

function PvpHud.Build()
	local gui = Ui.Screen()
	banner = Ui.Frame(gui, UDim2.fromOffset(420, 36), T.Background, 0.2)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 8)
	Ui.Corner(banner, 10)
	Ui.Stroke(banner, T.Stroke, 2)
	Ui.Padding(banner, 6)

	title = Ui.Label(banner, "", UDim2.new(1, -150, 0, 24), { TextXAlignment = Enum.TextXAlignment.Left })
	travel = Ui.Button(banner, "Ir para a arena", T.Accent, function()
		local pvp = State.Pvp
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		-- Se já está perto do centro, o botão leva de volta para a base.
		local inArena = root ~= nil and Vector3.new(root.Position.X, 0, root.Position.Z).Magnitude < 80
		if pvp and pvp.Phase == "Open" then
			State.Call("PvpTravel", not inArena)
		end
	end, UDim2.fromOffset(140, 26))
	travel.Position = UDim2.new(1, -140, 0, 0)

	captureBack = Ui.Frame(banner, UDim2.new(1, 0, 0, 22), T.PanelLight)
	captureBack.Position = UDim2.fromOffset(0, 32)
	Ui.Corner(captureBack, 6)
	captureFill = Ui.Frame(captureBack, UDim2.fromScale(0, 1), T.Accent)
	Ui.Corner(captureFill, 6)
	captureText = Ui.Label(captureBack, "", UDim2.fromScale(1, 1), {
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = T.Font,
		ZIndex = 3,
	})

	buffLabel = Ui.Label(banner, "", UDim2.new(1, 0, 0, 20), {
		Position = UDim2.fromOffset(0, 58),
		TextColor3 = Color3.fromRGB(255, 210, 90),
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	State.OnChange(refresh)
	-- O texto do botão alterna conforme a distância do centro; atualiza a cada segundo.
	task.spawn(function()
		while true do
			task.wait(1)
			local character = player.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
			if root and travel.Visible then
				local inArena = Vector3.new(root.Position.X, 0, root.Position.Z).Magnitude < 80
				travel.Text = if inArena then "Voltar para a base" else "Ir para a arena"
			end
			refresh()
		end
	end)
	refresh()
end

return PvpHud
