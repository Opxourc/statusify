const ReplicatedStorage = game:GetService("ReplicatedStorage")
const SharedTypes = require(ReplicatedStorage.Shared.StatusEffect.Types)

-- Dependencies that the constructor needs to have injected before it can work
export type ConstructorDependencies = {
	RemoteEvent: RemoteEvent,
	MaxNumberPerHumanoid: number?,
}

-- Describes the template for an effect
export type EffectDefinition = {
	Duration: number?, -- How long 'one' stack should last naturally without any interuptions
	Interval: number?, -- How fast ticks should be applied during the duration
	Replicate: { -- Determines what points of the lifecycle should be replicated
		Apply: boolean?,
		Tick: boolean?,
		Remove: boolean?,
	}?,
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

-- Public interface for scripts trying to use the framework
export type StatusEffectExternal = {
	HasEffect: (self: StatusEffectInternal, humanoid: Humanoid, effectName: string) -> boolean,
	GetActiveEffect: (self: StatusEffectInternal, humanoid: Humanoid, effectName: string) -> EffectInstance?,
	GetRegisteredEffect: (self: StatusEffectInternal, effectName: string) -> EffectDefinition?,
	ClearEffect: (
		self: StatusEffectInternal,
		humanoid: Humanoid,
		action: "remove" | "removeAll" | "decrement",
		effectName: string?
	) -> boolean,
	ApplyEffect: (self: StatusEffectInternal, humanoid: Humanoid, effectName: string) -> boolean,
	UnregisterEffect: (self: StatusEffectInternal, effectName: string, terminate: boolean) -> boolean,
	RegisterEffect: (self: StatusEffectInternal, effectName: string, definition: EffectDefinition) -> boolean,
	Destroy: () -> (),
}

-- Private interface for the framework to work with
export type StatusEffectInternal = StatusEffectExternal & {
	JanitorConnections: { RBXScriptConnection },
	RuntimeConnections: RBXScriptConnection,
	MaxNumberPerHumanoid: number,
	RemoteEvent: RemoteEvent,
	RegisteredEffects: { [string]: EffectDefinition },
	ActiveEffects: { [Humanoid]: { [string]: EffectInstance } },

	_getSelf: (self: StatusEffectInternal) -> StatusEffectInternal,
	_createRuntime: (self: StatusEffectInternal) -> RBXScriptConnection?,
	_createContext: (self: StatusEffectInternal, humanoid: Humanoid, effect: EffectInstance) -> EffectContext,
	_mutateStack: (self: StatusEffectInternal, humanoid: Humanoid, effect: EffectInstance, applyValue: number) -> (),
	_createJanitor: (self: StatusEffectInternal) -> { RBXScriptConnection },
	_removeFromActive: (self: StatusEffectInternal, humanoid: Humanoid, effectName: string) -> boolean,
	_sendReplication: (
		self: StatusEffectInternal,
		humanoid: Humanoid,
		message: SharedTypes.EventMessage,
		effectName: string,
		definition: EffectDefinition
	) -> boolean,
}

return table.freeze({})
