--!strict
-- Mapa em estrela: arena no centro, 5 bases em volta, e de cada base sai um caminho até a arena.
-- Ir para o PvP é opcional: quem quiser segue o caminho (ou usa o atalho "Ir para a arena").
-- Tudo aqui é gerado ao iniciar o servidor (provisório). Se o mapa definitivo tiver
-- Workspace.Paths.PathN, o caminho gerado daquela base é pulado.
--
-- A vegetação decorativa (árvores, arbustos, pedras) que fica em cima das bases, dos caminhos
-- e da arena sai do caminho só durante o jogo: o mapa salvo no Studio não muda.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Pvp = require(ReplicatedStorage.Shared.Config.Pvp)
local BaseService = require(script.Parent.BaseService)

local PATH_WIDTH = 12
local ROAD_TOP = 1.0 -- mesma altura do chão das bases
local POST_SPACING = 16
local VEGETATION = { Arvore = true, Pinheiro = true, Arbusto = true, Pedra = true }

local MapService = {}

local stash: Folder? = nil

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- Guarda (fora do mundo) a vegetação que encosta na caixa.
function MapService.ClearVegetation(cframe: CFrame, size: Vector3)
	if not stash then
		local folder = Instance.new("Folder")
		folder.Name = "ClearedVegetation"
		folder.Parent = ServerStorage
		stash = folder
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local bases = workspace:FindFirstChild("Bases")
	params.FilterDescendantsInstances = if bases then { bases } else {}
	for _, p in workspace:GetPartBoundsInBox(cframe, size, params) do
		local model = p:FindFirstAncestorOfClass("Model")
		local target: Instance = model or p
		if VEGETATION[target.Name] and target.Parent ~= stash then
			target.Parent = stash
		end
	end
end

local function lantern(parent: Instance, at: Vector3, height: number)
	part({
		Name = "LampPost",
		Size = Vector3.new(0.8, height, 0.8),
		CFrame = CFrame.new(at + Vector3.new(0, height / 2, 0)),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(95, 68, 45),
	}, parent)
	local lamp = part({
		Name = "Lamp",
		Size = Vector3.new(1.1, 1.3, 1.1),
		CFrame = CFrame.new(at + Vector3.new(0, height + 0.6, 0)),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 170, 70),
		CanCollide = false,
	}, parent)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 90)
	light.Range = 16
	light.Brightness = 1.2
	light.Parent = lamp
end

-- Placa com texto que aparece de perto.
local function sign(parent: Instance, cframe: CFrame, text: string)
	local board = part({
		Name = "Sign",
		Size = Vector3.new(6, 2.4, 0.4),
		CFrame = cframe,
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(120, 85, 55),
	}, parent)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(300, 120)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.fromRGB(255, 220, 160)
	label.Text = text
	label.Parent = gui
	gui.Parent = board
	part({
		Name = "SignPost",
		Size = Vector3.new(0.6, 4, 0.6),
		CFrame = cframe * CFrame.new(0, -2.6, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(95, 68, 45),
	}, parent)
end

--------------------------------------------------------------------------------
-- Ambientação (props rústicos)
--------------------------------------------------------------------------------

local rng = Random.new(2026) -- fixo: todo servidor monta o mesmo cenário

local function barrel(parent: Instance, at: Vector3)
	part({
		Name = "Barrel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 2.2, 2.2),
		CFrame = CFrame.new(at + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.CorrodedMetal,
		Color = if rng:NextNumber() < 0.5 then Color3.fromRGB(120, 60, 40) else Color3.fromRGB(70, 90, 70),
	}, parent)
end

local function crates(parent: Instance, at: Vector3, yaw: number)
	local base = CFrame.new(at) * CFrame.Angles(0, yaw, 0)
	part({
		Name = "Crate",
		Size = Vector3.new(2.6, 2.6, 2.6),
		CFrame = base * CFrame.new(0, 1.3, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(125, 90, 58),
	}, parent)
	part({
		Name = "Crate",
		Size = Vector3.new(2, 2, 2),
		CFrame = base * CFrame.new(0.3, 3.6, 0.2) * CFrame.Angles(0, math.rad(20), 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(135, 98, 62),
	}, parent)
end

local function scrapPile(parent: Instance, at: Vector3)
	for i = 1, 4 do
		local size = Vector3.new(rng:NextNumber(1, 2.6), rng:NextNumber(0.4, 1.2), rng:NextNumber(1, 2.6))
		part({
			Name = "Scrap",
			Size = size,
			CFrame = CFrame.new(
				at + Vector3.new(rng:NextNumber(-1.5, 1.5), 0.5 + i * 0.35, rng:NextNumber(-1.5, 1.5))
			) * CFrame.Angles(
				rng:NextNumber(-0.5, 0.5),
				rng:NextNumber(0, math.pi),
				rng:NextNumber(-0.5, 0.5)
			),
			Material = if i % 2 == 0 then Enum.Material.CorrodedMetal else Enum.Material.DiamondPlate,
			Color = Color3.fromRGB(100 + i * 10, 80, 65),
			CanCollide = false,
		}, parent)
	end
end

local function grassTuft(parent: Instance, at: Vector3)
	for i = 1, 3 do
		local h = rng:NextNumber(1.2, 2.4)
		part({
			Name = "Grass",
			Size = Vector3.new(0.25, h, 0.6),
			CFrame = CFrame.new(
				at + Vector3.new(rng:NextNumber(-0.6, 0.6), h / 2, rng:NextNumber(-0.6, 0.6))
			) * CFrame.Angles(
				rng:NextNumber(-0.3, 0.3),
				rng:NextNumber(0, math.pi),
				rng:NextNumber(-0.3, 0.3)
			),
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(70 + i * 8, 95 + i * 6, 45),
			CanCollide = false,
			CastShadow = false,
		}, parent)
	end
end

-- Props ao longo das cercas da base (fora do grid e da linha dos zumbis).
local function decorateBase(base: BaseService.Base, container: Instance)
	local model = Instance.new("Model")
	model.Name = `BaseDecor{base.Index}`
	local frame = base.Frame
	for i, z in { 0, 75, 95, 115 } do -- longe do grid (z ≈ 33..57) e do núcleo
		for _, side in { -1, 1 } do
			local at = (frame * CFrame.new(side * 25.5, -0.2, z)).Position -- chão da base (y ≈ 1)
			local pick = (i + (if side > 0 then 1 else 0)) % 3
			if pick == 0 then
				barrel(model, at)
				barrel(model, at + frame.LookVector * 2.6)
			elseif pick == 1 then
				crates(model, at, rng:NextNumber(0, math.pi))
			else
				scrapPile(model, at)
			end
		end
	end
	-- Mato do lado de fora das cercas
	for _ = 1, 16 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local at = (frame * CFrame.new(side * rng:NextNumber(32, 40), -1.2, rng:NextNumber(-15, 125))).Position
		grassTuft(model, at)
	end
	model.Parent = container
end

local function buildPath(base: BaseService.Base, container: Instance)
	local center = Vector3.new(Pvp.Center.X, ROAD_TOP, Pvp.Center.Z)
	local core = Vector3.new(base.Core.X, ROAD_TOP, base.Core.Z)
	local toCenter = (center - core).Unit
	-- Começa logo depois da fábrica (que fica entre o núcleo e o centro: 21..43 studs do núcleo)
	-- e termina na barreira da arena.
	local startPoint = core + toCenter * 46
	local endPoint = center - toCenter * (Pvp.ArenaRadius + 1)
	local length = (endPoint - startPoint).Magnitude
	local mid = (startPoint + endPoint) / 2
	local frame = CFrame.lookAt(mid, endPoint) -- -Z aponta para a arena

	local model = Instance.new("Model")
	model.Name = `Path{base.Index}`

	MapService.ClearVegetation(frame, Vector3.new(PATH_WIDTH + 14, 60, length + 10))

	-- Estrada de terra batida com bordas de pedra
	part({
		Name = "Road",
		Size = Vector3.new(PATH_WIDTH, 0.6, length + 2),
		CFrame = frame * CFrame.new(0, -0.3, 0),
		Material = Enum.Material.Ground,
		Color = Color3.fromRGB(110, 85, 60),
	}, model)
	for _, side in { -1, 1 } do
		part({
			Name = "Curb",
			Size = Vector3.new(1, 0.8, length + 2),
			CFrame = frame * CFrame.new(side * (PATH_WIDTH / 2 + 0.5), -0.2, 0),
			Material = Enum.Material.Cobblestone,
			Color = Color3.fromRGB(95, 88, 80),
		}, model)
	end

	-- Cerca de madeira nas laterais e lanternas alternadas
	local posts = math.floor(length / POST_SPACING)
	for i = 0, posts do
		local z = -length / 2 + i * (length / math.max(1, posts))
		for _, side in { -1, 1 } do
			local x = side * (PATH_WIDTH / 2 + 1.5)
			local at = (frame * CFrame.new(x, 0, z)).Position
			if i % 3 == 0 and side == (if i % 6 == 0 then 1 else -1) then
				lantern(model, at, 7)
			else
				part({
					Name = "FencePost",
					Size = Vector3.new(0.6, 2.6, 0.6),
					CFrame = CFrame.new(at + Vector3.new(0, 1.3, 0)),
					Material = Enum.Material.WoodPlanks,
					Color = Color3.fromRGB(95, 68, 45),
				}, model)
			end
			if i < posts then
				local nextZ = -length / 2 + (i + 1) * (length / math.max(1, posts))
				local rail = frame * CFrame.new(x, 1.9, (z + nextZ) / 2)
				part({
					Name = "Rail",
					Size = Vector3.new(0.3, 0.3, nextZ - z),
					CFrame = rail,
					Material = Enum.Material.WoodPlanks,
					Color = Color3.fromRGB(105, 75, 50),
				}, model)
			end
		end
	end

	-- Placa na saída da base
	-- A frente da placa fica virada para quem sai da base.
	local signAt = startPoint
		+ toCenter * 4
		+ frame.RightVector * (PATH_WIDTH / 2 + 3)
		+ Vector3.new(0, 4.2, 0)
	sign(model, CFrame.lookAt(signAt, signAt - toCenter), "⚔ ARENA PvP\n(opcional)")

	-- Mato e sucata na beira do caminho
	for _ = 1, math.floor(length / 10) do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local z = rng:NextNumber(-length / 2, length / 2)
		local at = (frame * CFrame.new(
			side * rng:NextNumber(PATH_WIDTH / 2 + 3, PATH_WIDTH / 2 + 7),
			-ROAD_TOP,
			z
		)).Position
		if rng:NextNumber() < 0.8 then
			grassTuft(model, at)
		else
			scrapPile(model, at)
		end
	end

	-- Arco de entrada na arena
	local gate = endPoint - toCenter * 3
	local gateFrame = CFrame.lookAt(gate, gate + toCenter)
	for _, side in { -1, 1 } do
		part({
			Name = "GatePillar",
			Size = Vector3.new(2, 14, 2),
			CFrame = gateFrame * CFrame.new(side * (PATH_WIDTH / 2 + 1), 7, 0),
			Material = Enum.Material.CorrodedMetal,
			Color = Color3.fromRGB(100, 75, 55),
		}, model)
	end
	part({
		Name = "GateBeam",
		Size = Vector3.new(PATH_WIDTH + 6, 2, 2),
		CFrame = gateFrame * CFrame.new(0, 15, 0),
		Material = Enum.Material.CorrodedMetal,
		Color = Color3.fromRGB(100, 75, 55),
	}, model)
	part({
		Name = "GateSign",
		Size = Vector3.new(PATH_WIDTH - 2, 1.2, 0.3),
		CFrame = gateFrame * CFrame.new(0, 13.2, 0),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(230, 140, 40),
		CanCollide = false,
	}, model)

	model.Parent = container
end

function MapService.Start()
	local existing = workspace:FindFirstChild("Paths")
	local container: Instance = existing or Instance.new("Folder")
	if not existing then
		container.Name = "Paths"
		container.Parent = workspace
	end
	for _, base in BaseService.All() do
		-- Vegetação em cima do chão da base sai do caminho.
		-- (inclui a fábrica, que fica a 21..43 studs do núcleo em direção ao centro)
		MapService.ClearVegetation(base.Frame * CFrame.new(0, 0, 45), Vector3.new(70, 60, 195))
		if not container:FindFirstChild(`Path{base.Index}`) then
			buildPath(base, container)
			decorateBase(base, container)
		end
	end
end

return MapService
