--!strict
-- Fábrica tycoon: 3 andares × 2 linhas de produção atrás do núcleo da base.
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

local FLOOR_HEIGHT = 12
local DISTANCE_FROM_CORE = 32 -- studs do núcleo em direção ao centro do mapa
local WORKER_SLOTS = { "Head", "Torso", "Arms", "Legs" }

type Built = {
	Model: Model,
	Prompt: ProximityPrompt,
	Stations: { [string]: BasePart },
	Workers: { [string]: Model },
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
		station.Transparency = if line.Unlocked then 0 else 0.75
		station.Color = if line.Unlocked then Color3.fromRGB(60, 120, 70) else Color3.fromRGB(90, 90, 90)

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
			local m = Instance.new("Model")
			m.Name = `Worker_{id}`
			local base = station.CFrame * CFrame.new(0, station.Size.Y / 2, 3)
			local pieces = {
				{ "Legs", Vector3.new(1.8, 1.6, 1), 0.8 },
				{ "Torso", Vector3.new(2, 1.8, 1.2), 2.5 },
				{ "Head", Vector3.new(1.1, 1, 1.1), 3.9 },
			}
			for _, piece in pieces do
				local slot, size, y = piece[1] :: string, piece[2] :: Vector3, piece[3] :: number
				part({
					Name = slot,
					Size = size,
					CFrame = base * CFrame.new(0, y, 0),
					Color = tierColor((line :: any)[slot]),
					Material = Enum.Material.Metal,
					CanCollide = false,
					Transparency = if (line :: any)[slot] == "" then 0.8 else 0,
				}, m)
			end
			part({
				Name = "Arms",
				Size = Vector3.new(3.2, 0.6, 0.6),
				CFrame = base * CFrame.new(0, 2.8, 0),
				Color = tierColor(line.Arms),
				Material = Enum.Material.Metal,
				CanCollide = false,
				Transparency = if line.Arms == "" then 0.8 else 0,
			}, m)
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

local function build(player: Player)
	local base = BaseService.Get(player)
	if not base then
		return
	end
	local origin = base.Frame * CFrame.new(0, 0, -DISTANCE_FROM_CORE)
	local model = Instance.new("Model")
	model.Name = "Factory"

	local width, depth = 34, 22
	local stations: { [string]: BasePart } = {}
	for floor = 1, Economy.Factory.Floors do
		local y = (floor - 1) * FLOOR_HEIGHT
		part({
			Name = `Floor{floor}`,
			Size = Vector3.new(width, 1, depth),
			CFrame = origin * CFrame.new(0, y + 0.5, 0),
			Material = Enum.Material.DiamondPlate,
			Color = Color3.fromRGB(85, 80, 75),
		}, model)
		for line = 1, Economy.Factory.LinesPerFloor do
			local id = `{floor}-{line}`
			local x = if line == 1 then -8 else 8
			stations[id] = part({
				Name = `Line{id}`,
				Size = Vector3.new(6, 1.2, 14),
				CFrame = origin * CFrame.new(x, y + 1.6, 0),
				Material = Enum.Material.Metal,
				Color = Color3.fromRGB(90, 90, 90),
			}, model)
		end
	end
	-- Colunas
	for _, corner in
		{ Vector3.new(-16, 0, -10), Vector3.new(16, 0, -10), Vector3.new(-16, 0, 10), Vector3.new(16, 0, 10) }
	do
		part({
			Name = "Pillar",
			Size = Vector3.new(1.2, FLOOR_HEIGHT * Economy.Factory.Floors, 1.2),
			CFrame = origin
				* CFrame.new(corner + Vector3.new(0, FLOOR_HEIGHT * Economy.Factory.Floors / 2, 0)),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(60, 60, 65),
		}, model)
	end

	-- Painel de compra no térreo, do lado da base
	local kiosk = part({
		Name = "Kiosk",
		Size = Vector3.new(3, 4, 1),
		CFrame = origin * CFrame.new(0, 2, depth / 2 + 3),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 170, 40),
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
	built[player] = { Model = model, Prompt = prompt, Stations = stations, Workers = {} }
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
