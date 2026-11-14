--!strict
-- Modelos procedurais no estilo Cyber-Rustic (placeholder da arte final).
-- Faixas visuais por tier, como no GDD: sucata (1-3) → industrial (4-6) → futurista (7-9).
-- Cada peça tem nome fixo (Head, Torso, ArmL, ArmR, LegL, LegR, Weapon) para ser trocada
-- por MeshParts quando a modelagem 3D ficar pronta, sem mudar a lógica do jogo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)

local Models = {}

type Style = { Material: Enum.Material, Trim: Enum.Material?, Glow: boolean, Rust: number }

-- Faixa visual de cada tier.
local function styleFor(tier: number): Style
	if tier <= 3 then
		return { Material = Enum.Material.CorrodedMetal, Trim = nil, Glow = false, Rust = 0.45 }
	elseif tier <= 6 then
		return { Material = Enum.Material.DiamondPlate, Trim = Enum.Material.Metal, Glow = false, Rust = 0.15 }
	end
	return { Material = Enum.Material.SmoothPlastic, Trim = Enum.Material.Neon, Glow = true, Rust = 0 }
end

local RUST = Color3.fromRGB(120, 72, 40)

-- Modelos 3D (MeshParts gerados) guardados no place em ServerStorage.Assets.
-- Convenção: frente para -Z, sem rotação, já no tamanho de referência. Se um modelo faltar,
-- o código volta para as formas feitas de blocos (o jogo nunca quebra por falta de asset).
local assetsFolder: Instance? = game:GetService("ServerStorage"):FindFirstChild("Assets")
local BAND_NAMES = { "Scrap", "Industrial", "Future" }

local function asset(name: string): MeshPart?
	local found = if assetsFolder then assetsFolder:FindFirstChild(name) else nil
	if found and found:IsA("MeshPart") then
		return found
	end
	return nil
end

-- Clona um modelo 3D no tamanho e na posição pedidos.
local function meshPart(
	parent: Instance,
	name: string,
	template: MeshPart,
	size: Vector3,
	cframe: CFrame
): MeshPart
	local p = template:Clone()
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cframe
	p.Parent = parent
	return p
end

local function block(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function tierOf(key: string): number?
	local item = Items.Parse(key)
	return if item then item.Tier else nil
end

-- Faixa visual: 1 = sucata (tiers 1-3), 2 = industrial (4-6), 3 = futurista (7-9).
local function bandOf(key: string): number
	local tier = tierOf(key) or 1
	return if tier <= 3 then 1 elseif tier <= 6 then 2 else 3
end

local function paint(key: string): (Color3, Style)
	local tier = tierOf(key) or 1
	local style = styleFor(tier)
	return Rarity.Get(tier).Color:Lerp(RUST, style.Rust), style
end

-- Arma em coordenadas locais (empunhadura na origem, lâmina/cano para -Z).
function Models.Weapon(parent: Instance, key: string, grip: CFrame, scale: number?): Model?
	local item = Items.Parse(key)
	if not item or item.Kind ~= "Weapon" then
		return nil
	end
	local s = scale or 1
	local color, style = paint(key)
	local trimColor = Rarity.Get(item.Tier).Color
	local m = Instance.new("Model")
	m.Name = "Weapon"
	local template = asset(`Weapon_{item.Type}`)
	if template then
		-- Modelo 3D: comprimento ao longo de -Z; a empunhadura fica perto da ponta de trás.
		local size = template.Size * s
		local back = if item.Type == "Rifle" then 0.3 elseif item.Type == "Hammer" then 0.3 else 0.4
		meshPart(m, "Mesh", template, size, grip * CFrame.new(0, 0, -size.Z * back))
		-- Faixa brilhante na cor da raridade (é o que diferencia os tiers à distância).
		if item.Tier >= 4 then
			block(
				m,
				"RarityGlow",
				Vector3.new(0.12, 0.12, size.Z * 0.6),
				grip * CFrame.new(0, size.Y * 0.35, -size.Z * 0.5),
				trimColor,
				Enum.Material.Neon
			)
		end
		m.Parent = parent
		return m
	end
	if item.Type == "Sword" then
		block(m, "Handle", Vector3.new(0.3, 0.3, 1) * s, grip, Color3.fromRGB(60, 45, 35), Enum.Material.Wood)
		block(
			m,
			"Guard",
			Vector3.new(1.2, 0.25, 0.3) * s,
			grip * CFrame.new(0, 0, -0.6 * s),
			color,
			style.Material
		)
		block(
			m,
			"Blade",
			Vector3.new(0.35, 0.12, 3) * s,
			grip * CFrame.new(0, 0, -2.2 * s),
			color,
			style.Trim or style.Material
		)
	elseif item.Type == "Hammer" then
		block(
			m,
			"Handle",
			Vector3.new(0.3, 0.3, 2.2) * s,
			grip * CFrame.new(0, 0, -0.6 * s),
			Color3.fromRGB(60, 45, 35),
			Enum.Material.Wood
		)
		block(m, "Head", Vector3.new(1.4, 1, 1) * s, grip * CFrame.new(0, 0, -1.9 * s), color, style.Material)
		block(
			m,
			"Shield",
			Vector3.new(1.8, 2.2, 0.25) * s,
			grip * CFrame.new(-1.5 * s, 0, 0.2 * s),
			color,
			style.Material
		)
		if style.Trim then
			block(
				m,
				"ShieldTrim",
				Vector3.new(0.9, 1.2, 0.05) * s,
				grip * CFrame.new(-1.5 * s, 0, 0.05 * s),
				trimColor,
				style.Trim
			)
		end
	else -- Rifle
		block(
			m,
			"Stock",
			Vector3.new(0.35, 0.6, 1) * s,
			grip * CFrame.new(0, -0.1 * s, 0.4 * s),
			Color3.fromRGB(60, 45, 35),
			Enum.Material.Wood
		)
		block(
			m,
			"Body",
			Vector3.new(0.4, 0.5, 1.6) * s,
			grip * CFrame.new(0, 0, -0.8 * s),
			color,
			style.Material
		)
		block(
			m,
			"Barrel",
			Vector3.new(0.18, 0.18, 1.8) * s,
			grip * CFrame.new(0, 0.1 * s, -2.4 * s),
			Color3.fromRGB(50, 50, 55),
			Enum.Material.Metal
		)
		if style.Trim then
			block(
				m,
				"Scope",
				Vector3.new(0.2, 0.2, 0.7) * s,
				grip * CFrame.new(0, 0.4 * s, -0.9 * s),
				trimColor,
				style.Trim
			)
		end
	end
	m.Parent = parent
	return m
end

-- Robô completo a partir das peças equipadas. `base` = chão sob o robô, olhando para os zumbis.
-- A peça "Root" (invisível, ancorada) é o PrimaryPart: mover ela move o robô inteiro.
function Models.Robot(pad: { [string]: string }, base: CFrame): Model
	local originalPad = pad
	local m = Instance.new("Model")
	m.Name = "Robot"
	local up = base * CFrame.new(0, 0.2, 0)

	-- Modelos 3D por faixa (sucata / industrial / futurista). Cada peça foi gerada como parte de um
	-- robô inteiro e guarda a posição que tinha no corpo (atributo Offset, com os pés na origem),
	-- então qualquer combinação de faixas encaixa: cabeça futurista + pernas de sucata etc.
	local SLOT_PARTS = {
		Head = { "Head" },
		Torso = { "Torso" },
		Arms = { "ArmL", "ArmR" },
		Legs = { "LegL", "LegR" },
	}
	local function templatesFor(slot: string, key: string): { MeshPart }?
		if key == "" then
			return nil
		end
		local list = {}
		for _, partName in SLOT_PARTS[slot] do
			local t = asset(`Robot_{BAND_NAMES[bandOf(key)]}_{partName}`)
			if not t then
				return nil
			end
			table.insert(list, t)
		end
		return list
	end
	local hand = Vector3.new(1.95, 2.6, -0.6) -- onde a arma fica (mão direita)
	local usable = true
	local chosen: { [string]: { MeshPart } } = {}
	for slot in SLOT_PARTS do
		local key = (pad :: any)[slot]
		if key ~= "" then
			local list = templatesFor(slot, key)
			if list then
				chosen[slot] = list
			else
				usable = false
			end
		end
	end
	if usable and next(chosen) then
		for slot, list in chosen do
			for _, template in list do
				local offset = template:GetAttribute("Offset")
				local at = if typeof(offset) == "Vector3" then offset else Vector3.zero
				meshPart(
					m,
					string.match(template.Name, "_(%w+)$") or slot,
					template,
					template.Size,
					up * CFrame.new(at)
				)
			end
			if slot == "Arms" then
				local right = list[2]
				local o = right:GetAttribute("Offset")
				if typeof(o) == "Vector3" then
					hand = Vector3.new(o.X + 0.15, o.Y - right.Size.Y * 0.38, -0.6)
				end
			end
			-- Luz na cor da raridade de cada peça (diferencia tiers dentro da mesma faixa).
			local first = list[1]
			local offset = first:GetAttribute("Offset")
			local at = if typeof(offset) == "Vector3" then offset else Vector3.zero
			local color = Rarity.Get(tierOf((pad :: any)[slot]) or 1).Color
			if slot == "Torso" then
				block(
					m,
					"Core",
					Vector3.new(0.55, 0.55, 0.1),
					up * CFrame.new(at + Vector3.new(0, 0.15, -first.Size.Z / 2 - 0.02)),
					color,
					Enum.Material.Neon
				)
			elseif slot == "Head" then
				block(
					m,
					"Eye",
					Vector3.new(0.8, 0.16, 0.08),
					up * CFrame.new(at + Vector3.new(0, 0, -first.Size.Z / 2 - 0.02)),
					color,
					Enum.Material.Neon
				)
			end
		end
		pad = table.clone(pad)
		pad.Legs, pad.Torso, pad.Arms, pad.Head = "", "", "", "" -- não monta as formas de bloco
		m:SetAttribute("UsesMeshes", true)
	end

	if pad.Legs ~= "" then
		local c, st = paint(pad.Legs)
		block(m, "LegL", Vector3.new(0.9, 2.6, 1), up * CFrame.new(-0.7, 1.3, 0), c, st.Material)
		block(m, "LegR", Vector3.new(0.9, 2.6, 1), up * CFrame.new(0.7, 1.3, 0), c, st.Material)
		block(
			m,
			"Feet",
			Vector3.new(2.4, 0.4, 1.6),
			up * CFrame.new(0, 0.2, -0.2),
			c:Lerp(Color3.new(0, 0, 0), 0.3),
			Enum.Material.Metal
		)
	end
	if pad.Torso ~= "" then
		local c, st = paint(pad.Torso)
		block(m, "Torso", Vector3.new(3, 2.6, 1.8), up * CFrame.new(0, 3.9, 0), c, st.Material)
		block(
			m,
			"Core",
			Vector3.new(0.8, 0.8, 0.1),
			up * CFrame.new(0, 4, -0.92),
			Rarity.Get(tierOf(pad.Torso) or 1).Color,
			if st.Glow then Enum.Material.Neon else Enum.Material.Metal
		)
	end
	if pad.Arms ~= "" then
		local c, st = paint(pad.Arms)
		block(m, "ArmL", Vector3.new(0.8, 2.4, 0.8), up * CFrame.new(-1.95, 3.7, 0), c, st.Material)
		block(m, "ArmR", Vector3.new(0.8, 2.4, 0.8), up * CFrame.new(1.95, 3.7, 0), c, st.Material)
	end
	if pad.Head ~= "" then
		local c, st = paint(pad.Head)
		block(m, "Head", Vector3.new(1.6, 1.3, 1.5), up * CFrame.new(0, 5.9, 0), c, st.Material)
		block(
			m,
			"Eye",
			Vector3.new(1.1, 0.25, 0.1),
			up * CFrame.new(0, 6, -0.78),
			if st.Glow then Rarity.Get(tierOf(pad.Head) or 1).Color else Color3.fromRGB(255, 120, 40),
			Enum.Material.Neon
		)
		block(
			m,
			"Antenna",
			Vector3.new(0.12, 0.8, 0.12),
			up * CFrame.new(0.5, 6.9, 0),
			c,
			Enum.Material.Metal
		)
	end
	-- Detalhes de forma por faixa (além do material): cada peça muda de silhueta ao subir de faixa.
	local DARK = Color3.fromRGB(45, 42, 40)
	if pad.Torso ~= "" then
		local c, _ = paint(pad.Torso)
		local band = bandOf(pad.Torso)
		local glow = Rarity.Get(tierOf(pad.Torso) or 1).Color
		if band == 1 then
			-- Sucata: placa remendada torta e parafusos
			block(
				m,
				"Patch",
				Vector3.new(1, 0.8, 0.1),
				up * CFrame.new(-0.8, 3.4, -0.93) * CFrame.Angles(0, 0, math.rad(12)),
				RUST,
				Enum.Material.CorrodedMetal
			)
			for _, x in { -1.2, 1.2 } do
				block(
					m,
					"Bolt",
					Vector3.new(0.25, 0.25, 0.25),
					up * CFrame.new(x, 4.9, -0.92),
					DARK,
					Enum.Material.Metal,
					Enum.PartType.Ball
				)
			end
		elseif band == 2 then
			-- Industrial: grade de ventilação e tanque nas costas
			for i = 0, 2 do
				block(
					m,
					"Vent",
					Vector3.new(1.6, 0.12, 0.1),
					up * CFrame.new(0, 3.2 + i * 0.25, -0.93),
					DARK,
					Enum.Material.Metal
				)
			end
			block(
				m,
				"Tank",
				Vector3.new(1.8, 1, 1),
				up * CFrame.new(0, 4, 1.3) * CFrame.Angles(0, 0, math.rad(90)),
				c:Lerp(DARK, 0.3),
				Enum.Material.Metal,
				Enum.PartType.Cylinder
			)
		else
			-- Futurista: peito afinado (cunhas) e linhas de energia
			for _, side in { -1, 1 } do
				block(
					m,
					"ChestFin",
					Vector3.new(0.4, 2.2, 1.6),
					up * CFrame.new(side * 1.6, 4, 0) * CFrame.Angles(0, 0, math.rad(side * -12)),
					c,
					Enum.Material.SmoothPlastic
				)
				block(
					m,
					"EnergyLine",
					Vector3.new(0.12, 2, 0.1),
					up * CFrame.new(side * 0.8, 3.9, -0.93),
					glow,
					Enum.Material.Neon
				)
			end
		end
	end
	if pad.Arms ~= "" then
		local c, _ = paint(pad.Arms)
		local band = bandOf(pad.Arms)
		local glow = Rarity.Get(tierOf(pad.Arms) or 1).Color
		for _, side in { -1, 1 } do
			if band == 1 then
				-- Sucata: braço com mola/fio exposto
				block(
					m,
					"Wire",
					Vector3.new(0.15, 1.6, 0.15),
					up * CFrame.new(side * 2.4, 3.6, 0.3),
					Color3.fromRGB(160, 90, 40),
					Enum.Material.Metal
				)
			elseif band == 2 then
				-- Industrial: ombreiras grossas
				block(
					m,
					"Shoulder",
					Vector3.new(1.4, 0.7, 1.3),
					up * CFrame.new(side * 2, 5.1, 0),
					c:Lerp(DARK, 0.2),
					Enum.Material.DiamondPlate
				)
			else
				-- Futurista: ombreira em barbatana com ponta brilhante
				block(
					m,
					"ShoulderFin",
					Vector3.new(0.3, 1.4, 1.2),
					up * CFrame.new(side * 2.2, 5.4, 0.1) * CFrame.Angles(0, 0, math.rad(side * -25)),
					c,
					Enum.Material.SmoothPlastic
				)
				block(
					m,
					"FinTip",
					Vector3.new(0.32, 0.3, 1.22),
					up * CFrame.new(side * 2.5, 6.05, 0.1) * CFrame.Angles(0, 0, math.rad(side * -25)),
					glow,
					Enum.Material.Neon
				)
			end
		end
	end
	if pad.Head ~= "" then
		local c, _ = paint(pad.Head)
		local band = bandOf(pad.Head)
		local glow = Rarity.Get(tierOf(pad.Head) or 1).Color
		if band == 1 then
			-- Sucata: antena torta extra e olho de lâmpada
			block(
				m,
				"BentAntenna",
				Vector3.new(0.12, 0.9, 0.12),
				up * CFrame.new(-0.5, 6.9, 0) * CFrame.Angles(0, 0, math.rad(30)),
				c,
				Enum.Material.Metal
			)
			block(
				m,
				"Bulb",
				Vector3.new(0.35, 0.35, 0.35),
				up * CFrame.new(-0.75, 7.35, 0),
				Color3.fromRGB(255, 200, 80),
				Enum.Material.Neon,
				Enum.PartType.Ball
			)
		elseif band == 2 then
			-- Industrial: capacete com viseira
			block(
				m,
				"Helmet",
				Vector3.new(1.8, 0.5, 1.7),
				up * CFrame.new(0, 6.7, 0),
				c:Lerp(DARK, 0.25),
				Enum.Material.DiamondPlate
			)
			block(
				m,
				"Visor",
				Vector3.new(1.5, 0.15, 0.4),
				up * CFrame.new(0, 6.42, -0.95),
				DARK,
				Enum.Material.Metal
			)
		else
			-- Futurista: cúpula arredondada e auréola de energia
			block(
				m,
				"Dome",
				Vector3.new(1.7, 1.2, 1.6),
				up * CFrame.new(0, 6.5, 0),
				c,
				Enum.Material.SmoothPlastic,
				Enum.PartType.Ball
			)
			block(
				m,
				"Halo",
				Vector3.new(0.12, 2, 2),
				up * CFrame.new(0, 7.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
				glow,
				Enum.Material.Neon,
				Enum.PartType.Cylinder
			).Transparency =
				0.3
		end
	end
	if pad.Legs ~= "" then
		local c, _ = paint(pad.Legs)
		local band = bandOf(pad.Legs)
		local glow = Rarity.Get(tierOf(pad.Legs) or 1).Color
		for _, side in { -1, 1 } do
			if band == 2 then
				-- Industrial: joelheiras
				block(
					m,
					"KneePad",
					Vector3.new(1, 0.6, 0.4),
					up * CFrame.new(side * 0.7, 1.5, -0.6),
					c:Lerp(DARK, 0.2),
					Enum.Material.DiamondPlate
				)
			elseif band == 3 then
				-- Futurista: propulsores nos pés
				block(
					m,
					"Thruster",
					Vector3.new(0.3, 0.7, 0.7),
					up * CFrame.new(side * 0.7, 0.4, 0.7) * CFrame.Angles(0, 0, math.rad(90)),
					glow,
					Enum.Material.Neon,
					Enum.PartType.Cylinder
				)
			end
		end
	end

	if pad.Weapon ~= "" then
		Models.Weapon(m, pad.Weapon, up * CFrame.new(hand), 1.1)
	end

	-- Brilho nos tiers futuristas (7+).
	local best = 0
	for _, key in originalPad do
		best = math.max(best, tierOf(key) or 0)
	end
	if best >= 7 then
		local core = m:FindFirstChild("Torso") or m:FindFirstChildWhichIsA("BasePart")
		if core then
			local light = Instance.new("PointLight")
			light.Color = Rarity.Get(best).Color
			light.Range = 10
			light.Brightness = 1.5
			light.Parent = core
			-- Primordial e Galáctico (8+): faíscas da cor da raridade.
			if best >= 8 then
				local sparkle = Instance.new("ParticleEmitter")
				sparkle.Color = ColorSequence.new(Rarity.Get(best).Color)
				sparkle.LightEmission = 1
				sparkle.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.25),
					NumberSequenceKeypoint.new(1, 0),
				})
				sparkle.Transparency = NumberSequence.new(0.2)
				sparkle.Lifetime = NumberRange.new(0.6, 1.1)
				sparkle.Rate = if best >= 9 then 14 else 8
				sparkle.Speed = NumberRange.new(1, 2.5)
				sparkle.SpreadAngle = Vector2.new(180, 180)
				sparkle.Parent = core
			end
		end
	end

	-- Raiz invisível ancorada; o resto é soldado nela para o robô andar com um único CFrame.
	local root = block(m, "Root", Vector3.new(1, 1, 1), base, Color3.new(), Enum.Material.SmoothPlastic)
	root.Transparency = 1
	-- Membros e cabeça ficam em juntas (Motor6D) com o pivô no ombro/quadril/pescoço: o cliente
	-- anima essas juntas (andar, atacar, respirar) sem custo de rede — ver AnimationController.
	local limbs: { [string]: BasePart } = {}
	for _, name in { "ArmL", "ArmR", "LegL", "LegR", "Head" } do
		local limb = m:FindFirstChild(name)
		if limb and limb:IsA("BasePart") then
			limbs[name] = limb
		end
	end
	local weaponModel = m:FindFirstChild("Weapon")
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") and p ~= root then
			p.Anchored = false
			p.Massless = true
			local limbName = if p.Parent == m then p.Name else ""
			if limbs[limbName] == p then
				-- pivô: topo da peça (ombro/quadril) ou base (pescoço), com a orientação do robô
				local up = if limbName == "Head" then -p.Size.Y / 2 else p.Size.Y / 2 - 0.25
				local pivot = CFrame.new((p.CFrame * CFrame.new(0, up, 0)).Position) * base.Rotation
				local joint = Instance.new("Motor6D")
				joint.Name = limbName
				joint.Part0 = root
				joint.Part1 = p
				joint.C0 = root.CFrame:ToObjectSpace(pivot)
				joint.C1 = p.CFrame:ToObjectSpace(pivot)
				joint.Parent = root
			else
				-- A arma acompanha o braço direito; o olho acompanha a cabeça; o resto fica no corpo.
				local anchor: BasePart = root
				if weaponModel and p:IsDescendantOf(weaponModel) and limbs.ArmR then
					anchor = limbs.ArmR
				elseif (p.Name == "Eye" or p.Name == "Bulb" or p.Name == "Halo") and limbs.Head then
					anchor = limbs.Head
				end
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = anchor
				weld.Part1 = p
				weld.Parent = p
			end
		end
	end
	m.PrimaryPart = root
	m:AddTag("RobotRig")
	return m
end

local ZOMBIE_COLORS = {
	Normal = { Skin = Color3.fromRGB(110, 150, 90), Cloth = Color3.fromRGB(70, 60, 55) },
	Fast = { Skin = Color3.fromRGB(150, 170, 80), Cloth = Color3.fromRGB(90, 50, 40) },
	Tank = { Skin = Color3.fromRGB(80, 110, 70), Cloth = Color3.fromRGB(50, 50, 60) },
	Boss = { Skin = Color3.fromRGB(140, 50, 60), Cloth = Color3.fromRGB(30, 20, 25) },
}

-- Zumbi: um corpo ancorado (movido pelo servidor) + partes soldadas que seguem junto.
-- Zumbi articulado: 6 peças 3D (Zombie_<Tipo>_Head/Torso/ArmL/ArmR/LegL/LegR) presas por juntas a
-- uma raiz invisível do tamanho do zumbi. O servidor só move a raiz; o cliente anima as juntas.
local ZOMBIE_PARTS = { "Head", "Torso", "ArmL", "ArmR", "LegL", "LegR" }

local function riggedZombie(kind: string, size: Vector3, cframe: CFrame): BasePart?
	local templates: { [string]: MeshPart } = {}
	for _, name in ZOMBIE_PARTS do
		local t = asset(`Zombie_{kind}_{name}`)
		if not t then
			return nil
		end
		templates[name] = t
	end
	local height = templates.Torso:GetAttribute("Height")
	local scale = size.Y / (if typeof(height) == "number" and height > 0 then height else size.Y)

	local root = Instance.new("Part")
	root.Name = kind
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Transparency = 1
	root.Size = size
	root.CFrame = cframe

	for name, template in templates do
		local offsetValue = template:GetAttribute("Offset")
		local offset = (if typeof(offsetValue) == "Vector3" then offsetValue else Vector3.zero) * scale
		local p = template:Clone()
		p.Name = name
		p.Anchored = false
		p.Massless = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = template.Size * scale
		p.CFrame = cframe * CFrame.new(offset - Vector3.new(0, size.Y / 2, 0))
		p.Parent = root
		if name == "Torso" then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = p
			weld.Parent = p
		else
			-- Pivô: pescoço (base da cabeça), quadril (topo da perna) ou ombro. Braço gerado em
			-- "T" (deitado) tem o ombro na ponta de dentro; braço caído tem o ombro no topo.
			local pivotLocal: Vector3
			local side = if offset.X >= 0 then 1 else -1
			local tPose = false
			if name == "Head" then
				pivotLocal = Vector3.new(0, -p.Size.Y / 2, 0)
			elseif (name == "ArmL" or name == "ArmR") and p.Size.X > p.Size.Y * 1.1 then
				tPose = true
				pivotLocal = Vector3.new(-side * (p.Size.X / 2 - 0.1 * p.Size.X), 0, 0)
			else
				pivotLocal = Vector3.new(0, p.Size.Y / 2 - 0.1 * p.Size.Y, 0)
			end
			local pivot = CFrame.new((p.CFrame * CFrame.new(pivotLocal)).Position) * cframe.Rotation
			local joint = Instance.new("Motor6D")
			joint.Name = name
			joint.Part0 = root
			joint.Part1 = p
			joint.C0 = cframe:ToObjectSpace(pivot)
			joint.C1 = p.CFrame:ToObjectSpace(pivot)
			joint:SetAttribute("TPose", tPose)
			joint:SetAttribute("Side", side)
			joint.Parent = root
		end
	end
	root:AddTag("ZombieRig")
	return root
end

function Models.Zombie(kind: string, size: Vector3, cframe: CFrame): BasePart
	local rigged = riggedZombie(kind, size, cframe)
	if rigged then
		return rigged
	end
	local template = asset(`Zombie_{kind}`)
	if template then
		local root = template:Clone()
		root.Name = kind
		root.Anchored = true
		root.CanCollide = false
		root.CanQuery = false
		root.CanTouch = false
		-- Escala uniforme pela altura (não deforma o modelo); a base continua no chão.
		local s = size.Y / template.Size.Y
		root.Size = template.Size * s
		root.CFrame = cframe
		return root
	end
	local colors = ZOMBIE_COLORS[kind] or ZOMBIE_COLORS.Normal
	local root = block(
		workspace,
		kind,
		Vector3.new(size.X, size.Y * 0.45, size.Z),
		cframe,
		colors.Cloth,
		Enum.Material.Fabric
	)
	root.Parent = nil
	local h = size.Y
	local function attach(
		name: string,
		partSize: Vector3,
		offset: CFrame,
		color: Color3,
		material: Enum.Material
	)
		local p = block(root, name, partSize, cframe * offset, color, material)
		p.Anchored = false
		p.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
	end
	attach(
		"Head",
		Vector3.new(size.X * 0.6, h * 0.22, size.Z * 0.75),
		CFrame.new(0, h * 0.34, -0.1),
		colors.Skin,
		Enum.Material.SmoothPlastic
	)
	attach(
		"ArmL",
		Vector3.new(size.X * 0.22, size.X * 0.22, h * 0.32),
		CFrame.new(-size.X * 0.35, h * 0.12, -h * 0.16),
		colors.Skin,
		Enum.Material.SmoothPlastic
	)
	attach(
		"ArmR",
		Vector3.new(size.X * 0.22, size.X * 0.22, h * 0.32),
		CFrame.new(size.X * 0.35, h * 0.12, -h * 0.16),
		colors.Skin,
		Enum.Material.SmoothPlastic
	)
	attach(
		"Legs",
		Vector3.new(size.X * 0.8, h * 0.3, size.Z * 0.8),
		CFrame.new(0, -h * 0.35, 0),
		colors.Cloth:Lerp(Color3.new(0, 0, 0), 0.3),
		Enum.Material.Fabric
	)
	attach(
		"Eyes",
		Vector3.new(size.X * 0.4, h * 0.03, 0.05),
		CFrame.new(0, h * 0.36, -size.Z * 0.38 - 0.1),
		Color3.fromRGB(255, 60, 40),
		Enum.Material.Neon
	)
	return root
end

return Models
