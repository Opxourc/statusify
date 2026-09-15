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
		Update: boolean?,
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
	--[[
		Returns whether a humanoid currently has the given effect active.
	]]
	HasEffect: (self: StatusEffectInternal, humanoid: Humanoid, effectName: string) -> boolean,

	--[[
		Returns the active EffectInstance for a humanoid, or nil if it isn't active.
	]]
	GetActiveEffect: (self: StatusEffectInternal, humanoid: Humanoid, effectName: string) -> EffectInstance?,

	--[[
		Returns the registered EffectDefinition for the given effect name, or nil if unregistered.
	]]
	GetRegisteredEffect: (self: StatusEffectInternal, effectName: string) -> EffectDefinition?,

	--[[
		Remove an effect status from a humanoid.
		Use 'action' to determine how effect(s) should be removed.
		
		Actions:
			remove - Remove one single effect, ignoring all stacks on it.
			removeAll - Remove every effect from the humanoid.
			decrement - Remove one stack of the effect. If the stack drops to 0, it will be removed automatically.
		If the action is either "remove" or "decrement" you must specify the effectName.
	]]
	ClearEffect: (
		self: StatusEffectInternal,
		humanoid: Humanoid,
		action: "remove" | "removeAll" | "decrement",
		effectName: string?
	) -> boolean,

	--[[
		Apply an effect status onto a humanoid.
		This effect status should be registered first before any application of it can be used!
	]]
	ApplyEffect: (self: StatusEffectInternal, humanoid: Humanoid, effectName: string) -> boolean,

	--[[
		Unregister an effect status that will no longer be used.
		Use 'terminate' to destroy all active instances of the effect instantly.
	]]
	UnregisterEffect: (self: StatusEffectInternal, effectName: string, terminate: boolean) -> boolean,

	--[[
		Register an effect status to be available for use.
		Properties will be defaulted to a value if they're nil.
		
		Use a number <= 0 for Interval to disable ticking (no logic and replication for ticks)
		Use math.huge for Duration for a permanent duration (effect is either removed when humanoid dies or manual removal)

		Note: Very small positive intervals (e.g. 0.1) are supported, but aren't recommended for effects that may be active in large numbers.
		Lower intervals cause 'OnTick' to execute more frequently and can increase CPU usage. Consider using 0.5 or 1 second(s) for effects that only need periodic updates.

		Effect names are case insensitive, "MYEFFECT" and "myEffect" are considered the same.
	]]
	RegisterEffect: (self: StatusEffectInternal, effectName: string, definition: EffectDefinition) -> boolean,

	--[[
		Destroys the object, releasing everything it owns.
	]]
	Destroy: (self: StatusEffectInternal) -> (),
}

-- Private interface for the framework to work with
export type StatusEffectInternal = StatusEffectExternal & {
	WatcherConnections: { RBXScriptConnection },
	RuntimeConnection: RBXScriptConnection,
	MaxNumberPerHumanoid: number,
	RemoteEvent: RemoteEvent,
	RegisteredEffects: { [string]: EffectDefinition },
	ActiveEffects: { [Humanoid]: { [string]: EffectInstance } },
	ActiveThreads: { [Humanoid]: { [string]: { thread } } },
}

return table.freeze({})
