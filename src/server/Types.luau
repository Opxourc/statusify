-- Describes the template for an effect
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
	StackBehavior: "refresh" | "stack" | "ignore" | "stack_refresh"?,
	OnTick: ((context: EffectContext) -> ())?,
	OnApply: ((context: EffectContext) -> ())?,
	OnRemove: ((context: EffectContext) -> ())?,
	OnUpdate: ((context: EffectContext) -> ())?,
}

-- The contract for a live effect that is running
export type EffectInstance = {
	Definition: EffectDefinition,
	Name: string,
	Stacks: number,
	StartTime: number,
	ExpireTime: number,
	NextTickTime: number,
	NextAvailableApplyTime: number,
}

-- The context of the running effect at a given state.
export type EffectContext = {
	Target: Humanoid,
	Stacks: number,
	EffectName: string,
	StartTime: number,
	ExpireTime: number,
}

-- Public interface for scripts trying to use the framework
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
}

-- Private interface for the framework to work with
export type StatusifyInternal = Statusify & {
	WatcherConnections: { [Humanoid]: RBXScriptConnection? },
	RuntimeConnection: RBXScriptConnection?,
	MaxEffectsPerHumanoid: number,
	ReplicationEvent: RemoteEvent?,
	RegisteredEffects: { [string]: EffectDefinition? },
	ActiveEffects: { [Humanoid]: { [string]: EffectInstance? }? },
	ActiveThreads: { [Humanoid]: { [string]: { [thread]: boolean? }? }? },
}

-- Package structure to be sent over to clients
export type Replication = {
	Message: EventMessage,
	EffectName: string,
	ExpireTime: number,
	StartTime: number,
	Target: Humanoid,
	Stacks: number,
}

-- Messages that are sent for a package
export type EventMessage = "apply" | "tick" | "remove" | "update"

return table.freeze({})
