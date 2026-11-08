--!strict
-- Combate do avatar: arma roletada equipada, HP máximo escalado pelo tier da arma e ataque contra a horda.
-- O servidor decide tudo: origem do golpe = posição real do personagem; o cliente só sugere a direção.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)

local DataService = require(script.Parent.DataService)
local Models = require(script.Parent.Parent.Models)
local RemoteGuard = require(script.Parent.RemoteGuard)
local HordeService = require(script.Parent.HordeService)
local PvpService = require(script.Parent.PvpService)

-- Avatar bate um pouco mais fraco que o robô, mas pode se mover.
local AVATAR_DAMAGE_FACTOR = 0.8

local AvatarService = {}

local nextAttack: { [Player]: number } = {}

local function equippedWeapon(player: Player): (Items.WeaponStats?, number)
	local data = DataService.Get(player)
	local item = if data then Items.Parse(data.AvatarWeapon) else nil
	if not item then
		return nil, 1
	end
	return Items.Weapons[item.Type], item.Tier
end

local function findHand(character: Model): BasePart?
	return (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart?
end

-- Aplica HP máximo e o modelo provisório da arma na mão.
function AvatarService.Refresh(player: Player)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not character or not humanoid then
		return
	end
	local data = DataService.Get(player)
	local weapon, tier = equippedWeapon(player)

	local maxHp = Items.AvatarMaxHp(if weapon then tier else 1)
	local ratio = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1
	humanoid.MaxHealth = maxHp
	humanoid.Health = math.max(1, maxHp * ratio)

	local old = character:FindFirstChild("AvatarWeapon")
	if old then
		old:Destroy()
	end
	local hand = findHand(character)
	if not weapon or not hand or not data then
		return
	end
	local grip = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, 0)
	local visual = Models.Weapon(character, data.AvatarWeapon, grip, 0.8)
	if not visual then
		return
	end
	visual.Name = "AvatarWeapon"
	for _, p in visual:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hand
			weld.Part1 = p
			weld.Parent = p
		end
	end
end

local function handleAttack(player: Player, aim: any): RemoteGuard.Result
	local weapon, tier = equippedWeapon(player)
	if not weapon then
		return RemoteGuard.Fail("Equipe uma arma no avatar")
	end
	local now = os.clock()
	if now < (nextAttack[player] or 0) then
		return { Ok = false, Error = "Recarregando", Silent = true }
	end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not root or not humanoid or humanoid.Health <= 0 then
		return RemoteGuard.Fail("Sem personagem")
	end
	nextAttack[player] = now + weapon.Cooldown

	-- Direção sugerida pelo cliente (mira); se inválida, usa para onde o personagem olha.
	local dir = root.CFrame.LookVector
	if typeof(aim) == "Vector3" and aim.Magnitude > 0.01 and aim.Magnitude < 1e4 then
		dir = aim
	end
	local damage = weapon.Damage * Rarity.Multiplier(tier) * AVATAR_DAMAGE_FACTOR
	local hits, kills = HordeService.PlayerAttack(player, weapon, root.Position, dir, damage)
	local playerHits = PvpService.PlayerAttack(player, weapon, tier, root.Position, dir)
	return {
		Ok = true,
		Hits = hits + playerHits,
		Kills = kills,
		Pattern = weapon.Pattern,
		Range = weapon.Range,
		Angle = weapon.Angle or 0,
		Cooldown = weapon.Cooldown,
	}
end

local function handleEquipAvatarWeapon(player: Player, key: any): RemoteGuard.Result
	local data = DataService.Get(player)
	if not data then
		return RemoteGuard.Fail("Sem dados")
	end
	if key ~= "" then
		local item = Items.Parse(key)
		if not item or item.Kind ~= "Weapon" then
			return RemoteGuard.Fail("Item não é uma arma")
		end
		if data.AvatarWeapon ~= key and DataService.AvailableCount(player, key) < 1 then
			return RemoteGuard.Fail("Você não tem cópia livre desta arma")
		end
	end
	DataService.Set(player, { "AvatarWeapon" }, key)
	AvatarService.Refresh(player)
	return { Ok = true }
end

function AvatarService.Start()
	RemoteGuard.Handle("Attack", 4, 4, handleAttack)
	RemoteGuard.Handle("EquipAvatarWeapon", 6, 3, handleEquipAvatarWeapon)

	DataService.OnLoaded(function(player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 5)
			character:WaitForChild("HumanoidRootPart", 5)
			task.wait() -- deixa o Roblox terminar de montar o personagem
			AvatarService.Refresh(player)
		end)
		if player.Character then
			AvatarService.Refresh(player)
		end
	end)
	DataService.OnReleasing(function(player)
		nextAttack[player] = nil
	end)
end

return AvatarService
