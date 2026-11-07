--!strict
-- Tipos de runtime compartilhados entre serviços do servidor.

export type Zombie = {
	Id: number,
	Kind: string,
	Hp: number,
	MaxHp: number,
	Speed: number,
	Reward: number,
	ContactDps: number,
	Position: Vector3,
	StunnedUntil: number,
	Seed: number, -- fase do zigue-zague (cada zumbi anda diferente)
	Facing: Vector3,
	Part: BasePart,
	Dead: boolean,
}

return {}
