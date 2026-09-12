-- Dependencies that the constructor needs to have injected before it can work
export type ConstructorDependencies = {
	RemoteEvent: RemoteEvent,
	MaxNumberPerHumanoid: number?,
}

-- Describes the template for an effect
export type EffectDefinition = {
	Duration: number?, -- How long 'one' stack should last naturally without any interuptions
	Interval: number?, -- How fast ticks should be applied during the duration

	MaxStacks: number?,
	StackBehavior: "refresh" | "stack" | "ignore"?,
	-- refresh - Reset duration
	-- stack - Increase the number of stacks by 1 unless capped
	-- ignore - Do nothing

	-- Functions that step through the effect's lifecycle
	OnApply: ((context: EffectContext) -> ())?, -- The moment an effect goes live
	OnTick: ((context: EffectContext) -> ())?, -- When a interval strikes
	OnRemove: ((context: EffectContext) -> ())?, -- The moment an effect is cleared
}

-- The contract for a live effect that is running
export type EffectInstance = {
	Definition: EffectDefinition,
	Name: string,
	Stacks: number,
	StartTime: number,
	ExpireTime: number,
	NextTickTime: number,
}

-- The context of the running effect at a given state.
export type EffectContext = {
	Effect: EffectInstance,
	Target: Humanoid,
	Stacks: number,
}

-- The actual object type for a StatusEffectObject
export type StatusEffectObject = {
	-- Properties
	MaxNumberPerHumanoid: number,
	RemoteEvent: RemoteEvent,
	RegisteredEffects: { [string]: EffectDefinition },
	ActiveEffects: { [Humanoid]: { [string]: EffectInstance } },
	JanitorConnections: { RBXScriptConnection },
	RuntimeConnections: RBXScriptConnection,

	-- Private methods
	_removeFromActive: (self: StatusEffectObject, humanoid: Humanoid, effectName: string) -> (),
	_createContext: (self: StatusEffectObject, humanoid: Humanoid, effect: EffectInstance) -> EffectContext,
	_createRuntime: (self: StatusEffectObject) -> RBXScriptConnection?,
	_createJanitor: (self: StatusEffectObject) -> boolean,

	-- Public methods
	Destroy: (self: StatusEffectObject) -> (),
	RegisterEffect: (self: StatusEffectObject, effectName: string, definition: EffectDefinition) -> boolean,
	UnregisterEffect: (self: StatusEffectObject, effectName: string, terminate: boolean) -> boolean,
	ClearEffect: (self: StatusEffectObject, Humanoid: Humanoid, action: "one" | "all") -> boolean,
	ApplyEffect: (self: StatusEffectObject, humanoid: Humanoid, effectName: string) -> boolean,
}

return table.freeze({})
