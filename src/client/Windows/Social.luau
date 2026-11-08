--!strict
-- Janela "Jogadores": convites recebidos (aliança e troca), lista de jogadores do servidor
-- com os botões Aliar / Desfazer aliança / Trocar. Avisos do servidor viram toasts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Pvp = require(ReplicatedStorage.Shared.Config.Pvp)

local Ui = require(script.Parent.Parent.Ui)
local State = require(script.Parent.Parent.State)
local Sound = require(script.Parent.Parent.SoundController)

local T = Ui.Theme
local localPlayer = Players.LocalPlayer

local Social = {}
Social.OpenTrade = nil :: (() -> ())?

local list: ScrollingFrame
local window: Ui.Window
local lastNotice: any = nil
local lastInviteCount = 0

local function row(order: number, height: number?): Frame
	local r = Ui.Frame(list, UDim2.new(1, -10, 0, height or 52), T.Panel)
	r.LayoutOrder = order
	Ui.Corner(r, 8)
	Ui.Padding(r, 8)
	return r
end

local function sectionTitle(order: number, text: string)
	local l = Ui.Label(list, text, UDim2.new(1, -10, 0, 26), { Font = T.Font, TextColor3 = T.Accent })
	l.LayoutOrder = order
end

local function inviteRow(order: number, name: string, kind: string, userId: number)
	local r = row(order)
	Ui.Label(
		r,
		`{if kind == "Ally" then "🤝" else "🔄"} <b>{name}</b> {if kind == "Ally"
			then "quer ser seu aliado"
			else "quer trocar itens"}`,
		UDim2.new(1, -230, 1, 0)
	)
	local accept = Ui.Button(r, "Aceitar", T.Good, function()
		State.Call(if kind == "Ally" then "AllyRespond" else "TradeRespond", userId, true)
	end, UDim2.fromOffset(105, 36))
	accept.AnchorPoint = Vector2.new(1, 0.5)
	accept.Position = UDim2.new(1, -112, 0.5, 0)
	local decline = Ui.Button(r, "Recusar", T.Bad, function()
		State.Call(if kind == "Ally" then "AllyRespond" else "TradeRespond", userId, false)
	end, UDim2.fromOffset(105, 36))
	decline.AnchorPoint = Vector2.new(1, 0.5)
	decline.Position = UDim2.new(1, 0, 0.5, 0)
end

local function refresh()
	local social, data = State.Social, State.Data
	if not social or not data then
		return
	end
	Ui.Clear(list)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	if social.Trade then
		local r = row(nextOrder(), 48)
		Ui.Button(r, `🔄 Troca em andamento com {social.Trade.PartnerName} — abrir`, T.Info, function()
			if Social.OpenTrade then
				Social.OpenTrade()
			end
		end, UDim2.fromScale(1, 1))
	end

	local hasInvites = next(social.AllyInvites) ~= nil or next(social.TradeInvites) ~= nil
	if hasInvites then
		sectionTitle(nextOrder(), "📨 Convites")
		for id, name in social.AllyInvites do
			inviteRow(nextOrder(), name, "Ally", tonumber(id) :: number)
		end
		for id, name in social.TradeInvites do
			inviteRow(nextOrder(), name, "Trade", tonumber(id) :: number)
		end
	end

	local canTrade = data.Horde.Highest >= Pvp.TradeMinWave
	sectionTitle(nextOrder(), "👥 Jogadores no servidor")
	local tradeHint = Ui.Label(
		list,
		if canTrade
			then "Trocas: só itens livres (não equipados). Os dois marcam Pronto e confirmam."
			else `🔒 Trocas liberam quando você chegar à horda {Pvp.TradeMinWave}.`,
		UDim2.new(1, -10, 0, 20),
		{ TextColor3 = T.TextDim }
	)
	tradeHint.LayoutOrder = nextOrder()

	local others = 0
	for _, other in Players:GetPlayers() do
		if other ~= localPlayer then
			others += 1
			local allied = social.Allies[tostring(other.UserId)] ~= nil
			local r = row(nextOrder())
			Ui.Label(
				r,
				`<b>{other.DisplayName}</b>{if allied
					then "  <font color='#7fd08f'>🤝 aliado</font>"
					else ""}`,
				UDim2.new(1, -250, 1, 0)
			)
			local allyButton = Ui.Button(
				r,
				if allied then "Desfazer" else "🤝 Aliar",
				if allied then T.PanelLight else T.Good,
				function()
					local r2 = State.Call(if allied then "AllyLeave" else "AllyRequest", other.UserId)
					if r2 and r2.Ok and not allied then
						Ui.Toast(`Convite de aliança enviado para {other.DisplayName}`, T.Good)
					end
				end,
				UDim2.fromOffset(115, 36)
			)
			allyButton.AnchorPoint = Vector2.new(1, 0.5)
			allyButton.Position = UDim2.new(1, -122, 0.5, 0)
			local tradeButton = Ui.Button(r, "🔄 Trocar", T.Info, function()
				local r2 = State.Call("TradeRequest", other.UserId)
				if r2 and r2.Ok then
					Ui.Toast(`Pedido de troca enviado para {other.DisplayName}`, T.Info)
				end
			end, UDim2.fromOffset(115, 36), canTrade)
			tradeButton.AnchorPoint = Vector2.new(1, 0.5)
			tradeButton.Position = UDim2.new(1, 0, 0.5, 0)
		end
	end
	if others == 0 then
		local empty = Ui.Label(list, "Ninguém mais no servidor por enquanto.", UDim2.new(1, -10, 0, 30), {
			TextColor3 = T.TextDim,
		})
		empty.LayoutOrder = nextOrder()
	end
end

-- Avisos e convites novos aparecem mesmo com a janela fechada.
local function watch()
	local social = State.Social
	if not social then
		return
	end
	local notice = social.Notice
	if notice and notice ~= lastNotice and (not lastNotice or notice.At ~= lastNotice.At) then
		lastNotice = notice
		Ui.Toast(notice.Text, T.Accent)
	end
	local count = 0
	for _ in social.AllyInvites do
		count += 1
	end
	for _ in social.TradeInvites do
		count += 1
	end
	if count > lastInviteCount then
		Ui.Toast("📨 Novo convite — abra 👥 Jogadores", T.Info)
		Sound.Play("Equip")
	end
	lastInviteCount = count
end

function Social.Create(): Ui.Window
	window = Ui.Window("Social", "👥 Jogadores, alianças e trocas", Vector2.new(640, 460))
	list = Ui.Scroll(window.Body, UDim2.fromScale(1, 1), 6)
	window.OnOpen(refresh)
	State.OnChange(function()
		watch()
		if window.IsOpen() then
			refresh()
		end
	end)
	Players.PlayerAdded:Connect(function()
		if window.IsOpen() then
			refresh()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if window.IsOpen() then
				refresh()
			end
		end)
	end)
	return window
end

return Social
