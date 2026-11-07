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
	local m = Instance.new("Model")
	m.Name = "Robot"
	local up = base * CFrame.new(0, 0.2, 0)

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
	if pad.Weapon ~= "" then
		Models.Weapon(m, pad.Weapon, up * CFrame.new(1.95, 2.6, -0.6), 1.1)
	end

	-- Brilho nos tiers futuristas (7+).
	local best = 0
	for _, key in pad do
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
		end
	end

	-- Raiz invisível ancorada; o resto é soldado nela para o robô andar com um único CFrame.
	local root = block(m, "Root", Vector3.new(1, 1, 1), base, Color3.new(), Enum.Material.SmoothPlastic)
	root.Transparency = 1
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") and p ~= root then
			p.Anchored = false
			p.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = p
			weld.Parent = p
		end
	end
	m.PrimaryPart = root
	return m
end

local ZOMBIE_COLORS = {
	Normal = { Skin = Color3.fromRGB(110, 150, 90), Cloth = Color3.fromRGB(70, 60, 55) },
	Fast = { Skin = Color3.fromRGB(150, 170, 80), Cloth = Color3.fromRGB(90, 50, 40) },
	Tank = { Skin = Color3.fromRGB(80, 110, 70), Cloth = Color3.fromRGB(50, 50, 60) },
	Boss = { Skin = Color3.fromRGB(140, 50, 60), Cloth = Color3.fromRGB(30, 20, 25) },
}

-- Zumbi: um corpo ancorado (movido pelo servidor) + partes soldadas que seguem junto.
function Models.Zombie(kind: string, size: Vector3, cframe: CFrame): BasePart
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
