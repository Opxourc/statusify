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
	Throttle: number?, -- The minimal time between applications
	MaxStacks: number?,
	StackBehavior: "refresh" | "stack" | "ignore" | "stack_refresh"?,
	-- stack_refresh - Increase number of stacks by 1 and refresh duration
	-- refresh - Reset duration
	-- stack - Increase the number of stacks by 1 unless capped
	-- ignore - Do nothing

	-- Functions that step through the effect's lifecycle
	OnApply: ((context: EffectContext) -> ())?, -- The moment an effect goes live
	OnTick: ((context: EffectContext) -> ())?, -- When a interval strikes
	OnRemove: ((context: EffectContext) -> ())?, -- The moment an effect is cleared
	OnUpdate: ((context: EffectContext) -> ())?, -- When refreshes or stack values change
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
	GetActive: (self: StatusifyInternal, args: { Humanoid: Humanoid, EffectName: string }) -> EffectInstance?,
	GetRegistered: (self: StatusifyInternal, effectName: string) -> EffectDefinition?,
	GetActiveCount: (self: StatusifyInternal, humanoid: Humanoid) -> number,
	Apply: (self: StatusifyInternal, args: { Humanoid: Humanoid, EffectName: string }) -> boolean,
	Unregister: (self: StatusifyInternal, args: { EffectName: string, Terminate: boolean }) -> boolean,
	Register: (self: StatusifyInternal, args: { EffectName: string, Definition: EffectDefinition }) -> boolean,
	Destroy: (self: StatusifyInternal) -> (),
	Remove: (
		self: StatusifyInternal,
		args: { Action: "remove" | "removeAll" | "decrement", EffectName: string?, Humanoid: Humanoid }
	) -> boolean,
}

-- Private interface for the framework to work with
export type StatusifyInternal = Statusify & {
	WatcherConnections: { [Humanoid]: RBXScriptConnection },
	RuntimeConnection: RBXScriptConnection,
	MaxEffectsPerHumanoid: number,
	ReplicationEvent: RemoteEvent,
	RegisteredEffects: { [string]: EffectDefinition },
	ActiveEffects: { [Humanoid]: { [string]: EffectInstance } },
	ActiveThreads: { [Humanoid]: { [string]: { [thread]: true } } },
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
