--!strict
-- Fábrica tycoon: 3 andares × 2 linhas de produção atrás do núcleo da base.
--   Visual Cyber-Rustic: galpão de tijolo e chapa ondulada, telhado de duas águas, chaminés com
--   fumaça, escada lateral, guarda-corpos, luminárias, esteiras com rolos e máquina por linha.
--   As caixas andando nas esteiras são animadas no cliente (FactoryFx), sem custo de rede.
--   • As linhas são compradas em ordem por um painel (ProximityPrompt) no térreo.
--   • Andares altos multiplicam a renda (1x / 3x / 9x).
--   • Cada linha aceita um robô trabalhador (Cabeça, Torso, Braços, Pernas) que multiplica a renda.
--   • A renda cai no dinheiro a cada segundo (com multiplicador de rebirth).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Economy = require(Shared.Config.Economy)
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)

local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)
local RemoteGuard = require(script.Parent.RemoteGuard)
local Models = require(script.Parent.Parent.Models)

local FLOOR_HEIGHT = 12
local DISTANCE_FROM_CORE = 32 -- studs do núcleo em direção ao centro do mapa
local WORKER_SLOTS = { "Head", "Torso", "Arms", "Legs" }

type Built = {
	Model: Model,
	Prompt: ProximityPrompt,
	Stations: { [string]: BasePart },
	Workers: { [string]: Model },
	Origin: CFrame,
}

local FactoryService = {}

local built: { [Player]: Built } = {}
local carry: { [Player]: number } = {} -- frações de moeda acumuladas

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function nextLockedLine(player: Player): string?
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	for _, id in Economy.FactoryLineIds() do
		if not data.Factory.Lines[id].Unlocked then
			return id
		end
	end
	return nil
end

local MACHINE_SOUND = "rbxassetid://9112839293" -- Pro Sound Effects: refinaria/máquinas em loop

local function tierColor(key: string): Color3
	local item = Items.Parse(key)
	return if item then Rarity.Get(item.Tier).Color else Color3.fromRGB(70, 70, 70)
end

local function refreshVisuals(player: Player)
	local b = built[player]
	local data = DataService.Get(player)
	if not b or not data then
		return
	end
	for id, station in b.Stations do
		local line = data.Factory.Lines[id]
		station.Transparency = if line.Unlocked then 0 else 0.6
		station:SetAttribute("Active", line.Unlocked) -- o cliente anima as caixas na esteira
		local lamp = station:FindFirstChild("StatusLamp") :: BasePart?
		if lamp then
			lamp.Color = if line.Unlocked then Color3.fromRGB(90, 230, 110) else Color3.fromRGB(200, 70, 50)
		end
		local sign = station:FindFirstChild("LineSign") :: BillboardGui?
		if sign then
			local label = sign:FindFirstChildOfClass("TextLabel")
			if label then
				label.Text = if line.Unlocked
					then `Linha {id}  •  +{math.floor(Economy.LineIncome(id, line) + 0.5)}/s`
					else `🔒 Linha {id}  •  {Economy.FactoryLineCost(id)}`
			end
		end

		-- Som mecânico 3D: mais alto e mais acelerado em andares de cima.
		local hum = station:FindFirstChild("MachineHum") :: Sound?
		if line.Unlocked and not hum then
			local floor = tonumber(string.match(id, "^(%d+)")) or 1
			local s = Instance.new("Sound")
			s.Name = "MachineHum"
			s.SoundId = MACHINE_SOUND
			s.Looped = true
			s.Volume = 0.15 + 0.1 * floor
			s.PlaybackSpeed = 0.85 + 0.12 * floor
			s.RollOffMode = Enum.RollOffMode.InverseTapered
			s.RollOffMinDistance = 6
			s.RollOffMaxDistance = 45
			s.Parent = station
			s:Play()
		elseif not line.Unlocked and hum then
			hum:Destroy()
		end

		local old = b.Workers[id]
		if old then
			old:Destroy()
			b.Workers[id] = nil
		end
		if line.Unlocked and (line.Torso ~= "" or line.Head ~= "" or line.Arms ~= "" or line.Legs ~= "") then
			-- Trabalhador: o mesmo modelo de robô da defesa, ao lado da esteira, virado para ela.
			local localX = b.Origin:PointToObjectSpace(station.Position).X
			local groundY = station.Position.Y - station.Size.Y / 2 -- piso do andar
			local stand = (b.Origin * CFrame.new(localX + (if localX > 0 then -4.8 else 4.8), 0, 1)).Position
			local ground = Vector3.new(stand.X, groundY, stand.Z)
			local facing = Vector3.new(station.Position.X, groundY, station.Position.Z)
			local m = Models.Robot({
				Head = line.Head,
				Torso = line.Torso,
				Arms = line.Arms,
				Legs = line.Legs,
				Weapon = "",
				Targeting = "Nearest",
			}, CFrame.lookAt(ground, facing))
			m.Name = `Worker_{id}`
			m.Parent = b.Model
			b.Workers[id] = m
		end
	end

	local nextId = nextLockedLine(player)
	if nextId then
		b.Prompt.Enabled = true
		b.Prompt.ObjectText = `Linha {nextId} (andar {string.sub(nextId, 1, 1)})`
		b.Prompt.ActionText = `Comprar por {Economy.FactoryLineCost(nextId)}`
	else
		b.Prompt.Enabled = false
	end
end

local function buyNextLine(player: Player): RemoteGuard.Result
	local id = nextLockedLine(player)
	if not id then
		return RemoteGuard.Fail("Todas as linhas já foram compradas")
	end
	if not DataService.SpendCash(player, Economy.FactoryLineCost(id)) then
		return RemoteGuard.Fail("Dinheiro insuficiente")
	end
	DataService.Set(player, { "Factory", "Lines", id, "Unlocked" }, true)
	refreshVisuals(player)
	return { Ok = true, Line = id }
end

local BRICK = Color3.fromRGB(140, 78, 58)
local IRON = Color3.fromRGB(70, 68, 66)
local RUSTY = Color3.fromRGB(120, 80, 55)
local WOOD = Color3.fromRGB(110, 78, 52)

local function lineSign(station: BasePart, text: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "LineSign"
	gui.Size = UDim2.fromOffset(150, 26)
	gui.StudsOffset = Vector3.new(0, 5.6, -8.4) -- em cima da máquina
	gui.MaxDistance = 32 -- só de perto (de longe as placas dos andares se sobrepõem)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(25, 22, 20)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.fromRGB(255, 210, 140)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label
	label.Parent = gui
	gui.Parent = station
end

-- Esteira de produção: base com rolos, cinta de borracha e máquina com lâmpada de status.
local function productionLine(parent: Instance, at: CFrame, id: string): BasePart
	local belt = part({
		Name = `Line{id}`,
		Size = Vector3.new(6, 1.2, 14),
		CFrame = at,
		Material = Enum.Material.Metal,
		Color = IRON,
	}, parent)
	part({
		Name = "Belt",
		Size = Vector3.new(4.6, 0.15, 13.6),
		CFrame = at * CFrame.new(0, 0.66, 0),
		Material = Enum.Material.Rubber,
		Color = Color3.fromRGB(30, 30, 32),
	}, parent)
	for z = -6, 6, 3 do
		part({
			Name = "Roller",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(5.2, 0.5, 0.5),
			CFrame = at * CFrame.new(0, 0.35, z),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(150, 150, 155),
		}, parent)
	end
	for _, side in { -1, 1 } do
		part({
			Name = "Rail",
			Size = Vector3.new(0.3, 0.6, 14),
			CFrame = at * CFrame.new(side * 2.6, 0.9, 0),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(200, 160, 40),
		}, parent)
	end
	-- Máquina de montagem no fim da esteira (lado de trás), com lâmpada de status e exaustor
	local machine = part({
		Name = "Machine",
		Size = Vector3.new(6.4, 5, 3.4),
		CFrame = at * CFrame.new(0, 1.9, -8.4),
		Material = Enum.Material.DiamondPlate,
		Color = RUSTY,
	}, parent)
	part({
		Name = "Hatch",
		Size = Vector3.new(4.4, 2.6, 0.2),
		CFrame = machine.CFrame * CFrame.new(0, -0.6, 1.75),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(40, 40, 42),
	}, parent)
	local lamp = part({
		Name = "StatusLamp",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.8, 0.8, 0.8),
		CFrame = machine.CFrame * CFrame.new(2.4, 2.9, 1.2),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(200, 70, 50),
		CanCollide = false,
	}, parent)
	lamp.Parent = belt -- refreshVisuals procura a lâmpada dentro da esteira
	part({
		Name = "Exhaust",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.2, 0.9, 0.9),
		CFrame = machine.CFrame * CFrame.new(-2, 3.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.CorrodedMetal,
		Color = RUSTY,
	}, parent)
	lineSign(belt, `🔒 Linha {id}`)
	return belt
end

local function build(player: Player)
	local base = BaseService.Get(player)
	if not base then
		return
	end
	local origin = base.Frame * CFrame.new(0, 0, -DISTANCE_FROM_CORE)
	local model = Instance.new("Model")
	model.Name = "Factory"

	local width, depth = 34, 22
	local floors = Economy.Factory.Floors
	local totalHeight = FLOOR_HEIGHT * floors
	local stations: { [string]: BasePart } = {}

	-- Fundação de pedra
	part({
		Name = "Foundation",
		Size = Vector3.new(width + 2, 1, depth + 2),
		CFrame = origin * CFrame.new(0, 0.5, 0),
		Material = Enum.Material.Cobblestone,
		Color = Color3.fromRGB(100, 94, 86),
	}, model)

	for floor = 1, floors do
		local y = (floor - 1) * FLOOR_HEIGHT
		if floor > 1 then
			-- Piso de tábuas com viga de aço na borda
			part({
				Name = `Floor{floor}`,
				Size = Vector3.new(width, 0.8, depth),
				CFrame = origin * CFrame.new(0, y + 0.6, 0),
				Material = Enum.Material.WoodPlanks,
				Color = WOOD,
			}, model)
			part({
				Name = "Beam",
				Size = Vector3.new(width + 0.6, 1, 0.8),
				CFrame = origin * CFrame.new(0, y + 0.1, depth / 2),
				Material = Enum.Material.Metal,
				Color = IRON,
			}, model)
			-- Guarda-corpo na frente aberta (com vão no meio para ver as máquinas)
			for _, x in { -12, 12 } do
				part({
					Name = "Railing",
					Size = Vector3.new(9, 0.25, 0.25),
					CFrame = origin * CFrame.new(x, y + 4, depth / 2 - 0.3),
					Material = Enum.Material.Metal,
					Color = Color3.fromRGB(200, 160, 40),
				}, model)
			end
		end
		-- Paredes: tijolo no térreo, chapa ondulada enferrujada em cima. Fundo e laterais fechados.
		local wallMaterial = if floor == 1 then Enum.Material.Brick else Enum.Material.CorrodedMetal
		local wallColor = if floor == 1 then BRICK else RUSTY
		part({
			Name = "BackWall",
			Size = Vector3.new(width, FLOOR_HEIGHT, 1),
			CFrame = origin * CFrame.new(0, y + FLOOR_HEIGHT / 2 + 0.5, -depth / 2 + 0.5),
			Material = wallMaterial,
			Color = wallColor,
		}, model)
		for _, side in { -1, 1 } do
			-- Parede lateral com janela (duas faixas acima e abaixo da janela)
			part({
				Name = "SideWallLow",
				Size = Vector3.new(1, 4, depth),
				CFrame = origin * CFrame.new(side * (width / 2 - 0.5), y + 2.5, 0),
				Material = wallMaterial,
				Color = wallColor,
			}, model)
			part({
				Name = "SideWallHigh",
				Size = Vector3.new(1, 4, depth),
				CFrame = origin * CFrame.new(side * (width / 2 - 0.5), y + FLOOR_HEIGHT - 1.5, 0),
				Material = wallMaterial,
				Color = wallColor,
			}, model)
			part({
				Name = "Window",
				Size = Vector3.new(0.3, 4, depth - 2),
				CFrame = origin * CFrame.new(side * (width / 2 - 0.5), y + 6.5, 0),
				Material = Enum.Material.Glass,
				Color = Color3.fromRGB(255, 190, 120),
				Transparency = 0.45,
			}, model)
		end
		-- Luminária pendurada por andar
		local lamp = part({
			Name = "HangingLamp",
			Size = Vector3.new(1.6, 0.6, 1.6),
			CFrame = origin * CFrame.new(0, y + FLOOR_HEIGHT - 1, 0),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 200, 130),
			CanCollide = false,
		}, model)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 190, 120)
		light.Range = 22
		light.Brightness = 1.3
		light.Shadows = false
		light.Parent = lamp

		for line = 1, Economy.Factory.LinesPerFloor do
			local id = `{floor}-{line}`
			local x = if line == 1 then -8 else 8
			stations[id] = productionLine(model, origin * CFrame.new(x, y + 1.6, 1), id)
		end
	end

	-- Pilares de aço nos cantos da frente
	for _, x in { -width / 2 + 0.6, width / 2 - 0.6 } do
		part({
			Name = "Pillar",
			Size = Vector3.new(1.2, totalHeight, 1.2),
			CFrame = origin * CFrame.new(x, totalHeight / 2 + 0.5, depth / 2 - 0.6),
			Material = Enum.Material.Metal,
			Color = IRON,
		}, model)
	end

	-- Telhado de duas águas (cunhas) com cumeeira
	local roofY = totalHeight + 0.5
	for _, side in { -1, 1 } do
		local roof = part({
			Name = "Roof",
			Size = Vector3.new(depth + 3, 5, width / 2 + 1.5),
			CFrame = origin
				* CFrame.new(side * (width / 4 + 0.4), roofY + 2.5, 0)
				* CFrame.Angles(0, math.rad(side * -90), 0),
			Material = Enum.Material.CorrodedMetal,
			Color = Color3.fromRGB(95, 60, 45),
		}, model)
		roof.Shape = Enum.PartType.Wedge
	end
	-- Chaminés com fumaça
	for i, x in { -9, 6 } do
		local chimney = part({
			Name = "Chimney",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(9, 2.4, 2.4),
			CFrame = origin * CFrame.new(x, roofY + 5, -depth / 4) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Brick,
			Color = BRICK,
		}, model)
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(4.6, 0, 0)
		top.Parent = chimney
		local smoke = Instance.new("ParticleEmitter")
		smoke.Name = "Smoke"
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Color = ColorSequence.new(Color3.fromRGB(90, 85, 80), Color3.fromRGB(160, 150, 140))
		smoke.Size =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 6) })
		smoke.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		smoke.Lifetime = NumberRange.new(3, 5)
		smoke.Speed = NumberRange.new(3, 5)
		smoke.Acceleration = Vector3.new(1.5, 1, 0)
		smoke.Rate = if i == 1 then 4 else 3
		smoke.RotSpeed = NumberRange.new(-20, 20)
		smoke.Parent = top
	end

	-- Escada externa no lado direito (degraus de madeira até o último andar)
	local steps = math.floor(totalHeight / 1.2)
	for i = 0, steps - 1 do
		local floorIndex = math.floor(i * 1.2 / FLOOR_HEIGHT)
		local localStep = i - floorIndex * (FLOOR_HEIGHT / 1.2)
		local dir = if floorIndex % 2 == 0 then 1 else -1
		part({
			Name = "Step",
			Size = Vector3.new(4, 0.4, 1.4),
			CFrame = origin
				* CFrame.new(width / 2 + 2.4, i * 1.2 + 0.8, dir * (-depth / 2 + 1 + localStep * 1.8)),
			Material = Enum.Material.WoodPlanks,
			Color = WOOD,
		}, model)
	end

	-- Placa luminosa da fábrica
	local signBoard = part({
		Name = "FactorySign",
		Size = Vector3.new(14, 2.6, 0.4),
		CFrame = origin * CFrame.new(0, roofY - 1.2, depth / 2 + 0.4),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(40, 36, 32),
	}, model)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.CanvasSize = Vector2.new(560, 104)
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 170, 60)
	label.Text = "⚙ FÁBRICA"
	label.Parent = gui
	gui.Parent = signBoard

	-- Painel de compra no térreo, do lado da base
	local kiosk = part({
		Name = "Kiosk",
		Size = Vector3.new(3, 4, 1),
		CFrame = origin * CFrame.new(0, 2.5, depth / 2 + 3),
		Material = Enum.Material.Metal,
		Color = IRON,
	}, model)
	part({
		Name = "KioskScreen",
		Size = Vector3.new(2.4, 1.6, 0.1),
		CFrame = kiosk.CFrame * CFrame.new(0, 0.8, 0.55),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 170, 40),
		CanCollide = false,
	}, model)
	local prompt = Instance.new("ProximityPrompt")
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = kiosk
	prompt.Triggered:Connect(function(who)
		if who ~= player then
			return -- só o dono compra na própria fábrica
		end
		buyNextLine(player)
	end)

	model.Parent = base.Model
	built[player] = { Model = model, Prompt = prompt, Stations = stations, Workers = {}, Origin = origin }
	refreshVisuals(player)
end

local function destroy(player: Player)
	local b = built[player]
	if b then
		b.Model:Destroy()
	end
	built[player] = nil
	carry[player] = nil
end

local function handleEquipWorker(player: Player, lineId: any, slot: any, key: any): RemoteGuard.Result
	local data = DataService.Get(player)
	if not data or type(lineId) ~= "string" or not data.Factory.Lines[lineId] then
		return RemoteGuard.Fail("Linha inválida")
	end
	if not data.Factory.Lines[lineId].Unlocked then
		return RemoteGuard.Fail("Linha ainda não comprada")
	end
	if not RemoteGuard.IsOneOf(slot, WORKER_SLOTS) then
		return RemoteGuard.Fail("Slot inválido")
	end
	if key ~= "" then
		local item = Items.Parse(key)
		if not item or item.Slot ~= slot then
			return RemoteGuard.Fail("Peça não serve neste slot")
		end
		if
			(data.Factory.Lines[lineId] :: any)[slot] ~= key
			and DataService.AvailableCount(player, key) < 1
		then
			return RemoteGuard.Fail("Você não tem cópia livre desta peça")
		end
	end
	DataService.Set(player, { "Factory", "Lines", lineId, slot }, key)
	refreshVisuals(player)
	return { Ok = true }
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function FactoryService.Refresh(player: Player)
	refreshVisuals(player)
end

function FactoryService.IncomePerSecond(player: Player): number
	local data = DataService.Get(player)
	return if data then Economy.FactoryIncome(data.Factory.Lines) else 0
end

function FactoryService.Start()
	RemoteGuard.Handle("EquipWorker", 15, 8, handleEquipWorker)
	RemoteGuard.Handle("BuyFactoryLine", 3, 1, buyNextLine)
	DataService.OnLoaded(build)
	DataService.OnReleasing(destroy)
	Players.PlayerRemoving:Connect(destroy)

	task.spawn(function()
		while true do
			task.wait(1)
			for player in built do
				local income = FactoryService.IncomePerSecond(player) + (carry[player] or 0)
				local whole = math.floor(income)
				carry[player] = income - whole
				if whole > 0 then
					DataService.AddCash(player, whole, true)
				end
			end
		end
	end)
end

return FactoryService
