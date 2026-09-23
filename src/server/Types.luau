export type EffectDefinition = {
	Duration: number?,
	Interval: number?,
	Replicate: {
		Apply: boolean?,
		Tick: boolean?,
		Remove: boolean?,
		Update: boolean?,
	}?,
	Throttle: number?,
	MaxStacks: number?,
	StackBehavior: StackBehavior?,

	OnTick: ((context: EffectContext) -> ())?,
	OnApply: ((context: EffectContext) -> ())?,
	OnRemove: ((context: EffectContext) -> ())?,
	OnUpdate: ((context: EffectContext) -> ())?,
}

export type EffectInstance = {
	Definition: EffectDefinition,
	Name: string,
	Stacks: number,
	StartTime: number,
	ExpireTime: number,
	NextTickTime: number,
	NextAvailableApplyTime: number,
}

export type EffectContext = {
	Target: Humanoid,
	Stacks: number,
	EffectName: string,
	StartTime: number,
	ExpireTime: number,
}

export type Statusify = {
	GetActive: (self: Statusify, args: { Humanoid: Humanoid, EffectName: string }) -> EffectInstance?,
	GetRegistered: (self: Statusify, effectName: string) -> EffectDefinition?,
	GetActiveCount: (self: Statusify, humanoid: Humanoid) -> number,
	Apply: (self: Statusify, args: { Humanoid: Humanoid, EffectName: string }) -> (),
	Unregister: (self: Statusify, args: { EffectName: string, Terminate: boolean }) -> (),
	Register: (self: Statusify, args: { EffectName: string, Definition: EffectDefinition }) -> (),
	Destroy: (self: Statusify) -> nil,
	Remove: (
		self: Statusify,
		args: { Action: "effect" | "all" | "decrement", EffectName: string?, Humanoid: Humanoid }
	) -> (),

	_watcherConnections: { [Humanoid]: RBXScriptConnection? },
	_runtimeConnection: RBXScriptConnection?,
	_maxEffectsPerHumanoid: number,
	_replicationEvent: RemoteEvent?,
	_registeredEffects: { [string]: EffectDefinition? },
	_activeEffects: { [Humanoid]: { [string]: EffectInstance? }? },
	_activeThreads: { [Humanoid]: { [string]: { [thread]: boolean? }? }? },
}

export type EventMessage = "apply" | "tick" | "remove" | "update"
export type StackBehavior = "refresh" | "stack" | "ignore" | "stack_refresh"

return table.freeze({})
