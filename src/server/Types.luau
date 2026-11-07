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
	Part: BasePart,
	Dead: boolean,
}

return {}
