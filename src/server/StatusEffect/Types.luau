-- Messages that the client should recognize for effect statuses
-- These are used to show the proper visual feedback on such effect
export type EventMessages = {
	Apply: string,
	Tick: string,
	Remove: string,
}

-- Dependencies that the constructor needs to have injected before it can work
export type ConstructorDependencies = {
	RemoteEvent: RemoteEvent,
	EventMessages: EventMessages,
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

-- The information that effect callbacks need, in order to know what to do.
export type EffectContext = {
	Target: Humanoid,
	Effect: EffectInstance,
	Stacks: number,

	Damage: (self: EffectContext, amount: number) -> (),
	Remove: (self: EffectContext) -> (),
	Refresh: (self: EffectContext) -> (),
	AddStacks: (self: EffectContext, amount: number) -> (),
}

local Types = {}
Types.CD_DefaultMaxPerHumanoid = 3
Types.ED_StackBehaviors = table.freeze({
	Refresh = "refresh",
	Ignore = "ignore",
	Stack = "stack",
})
Types.ED_Defaults = table.freeze({
	Duration = 5,
	Interval = 1,
	MaxStacks = math.huge,
	StackBehavior = Types.ED_StackBehaviors.Refresh,
})

return table.freeze(Types)
