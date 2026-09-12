export type Replication = {
	Message: EventMessage,
	EffectName: string,
	ExpireTime: number,
	StartTime: number,
	Target: Humanoid,
	Stacks: number,
}

export type EventMessage = "apply" | "tick" | "remove" | "update"

return table.freeze({})
