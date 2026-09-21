--!strict
--[[
	Note:
		'self' is intended to be shadowed in these methods so 'self' can get proper type checking.
		If the type checker complains about this shadowing, you can ignore it.
		This won't hurt the execution of code.
]]

const Types = require("./Types")
const Logger = require("./Logger")
const Watcher = require("./Watcher")
const Threads = require("./Threads")
const Effects = require("./Effects")
const Runtime = require("./Runtime")
const Defaults = require("./Defaults")
const Utilities = require("./Utilities")
const Replication = require("./Replication")

local Api = {}
Api.__index = Api

--[[
	Constructs a new Statusify object.

	@param MaxEffectsPerHumanoid - The maximum number of effects a humanoid can have active. Defaults to 3 if not provided.
	@param ReplicatedEvent - For replicating messages to the client to visually show effects and states. Replication won't happen if this is nil.
	@return Statusify object.
]]
function Api.New(args: {
	MaxEffectsPerHumanoid: number?,
	ReplicationEvent: RemoteEvent?,
}): Types.Statusify?
	local maxEffectsPerHumanoid = args.MaxEffectsPerHumanoid
	local replicationEvent = args.ReplicationEvent

	local self = setmetatable({}, Api) :: Types.StatusifyInternal -- Type checker limitation

	-- Connection that runs the lifecycle of currently running effects
	self.RuntimeConnection = Runtime.Create(self)
	if self.RuntimeConnection == nil then
		Logger.Output("warn", "Unable to create object due to runtime creation failure.")
		return nil
	end

	self.MaxEffectsPerHumanoid = maxEffectsPerHumanoid or Defaults.Constructor.MaxEffectsPerHumanoid -- The max number of effects a humanoid can take at a moment
	self.WatcherConnections = {} -- Connections that are dynamically created and destroyed to clean up humanoids
	self.ReplicationEvent = replicationEvent -- This will be used to send replication events to clients
	self.RegisteredEffects = {} -- These are effects that are considered valid
	self.ActiveEffects = {} -- Effects that are currently running from an effect on a humanoid
	self.ActiveThreads = {} -- Threads that are currently running from an effect on a humanoid

	Logger.Output("log", "Object created.")
	return self
end

--[[
	Destroys the object, releasing everything it owns.
]]
function Api:Destroy()
	local self = Utilities.AnnotateSelf(self)

	if self.RuntimeConnection then
		self.RuntimeConnection:Disconnect()
	end

	for humanoid, effects in self.ActiveEffects do
		Watcher.Destroy(self, humanoid)
		Threads.Cancel({
			Humanoid = humanoid,
			Self = self,
			Action = "all",
		})

		Effects.Remove({
			Self = self,
			Humanoid = humanoid,
			Action = "all",
		})
	end

	Logger.Output("log", "Object destroyed.")
end

--[[
	Register an effect status to be available for use.

	Definition Properties:

	- Duration: How long 'one' stack should last naturally.
	- Interval: How fast ticks should be applied during the duration.
	- Throttle: The minimal time between applications.
	- MaxStacks: The maximum allowed stacks this effect can have.
	- StackBehavior: How stacking logic should work if reapplication happens.
	- Replicate: Which points of the lifecycle should replicate to the client.

	Replicate will contain:

	- Update
	- Tick
	- Remove
	- Apply

	These keys are valued as bools and if true, will allow replication to happen when their point in the lifetime is reached.
	- Example:
	OnApply called -> if Apply in Replicate is true, 'apply' event will be fired to clients.
	
	Definition Callbacks:
	
	- OnUpdate: Ran when either the stack count changes or reapplication happens.
	- OnApply: Ran when the effect is applied for the first time.
	- OnRemove: Ran when the effect is removed or cleared.
	- OnTick: Ran off of the interval in ticks.

	Stack Behavior:
	
	- "stack_refresh": Stack count is increased by one if not at max and duration is reest.
	- "stack": stack count is increased by one.
	- "refresh": Duration is reset.
	- "ignore": Do nothing.
	
	Tips for creating a definition:

	- Definition properties will be defaulted to a value if they're nil.
	- Use a number <= 0 for Interval to disable ticking.
	- Use math.huge for Duration for a permanent duration.
	- Very small positive intervals (e.g. 0.1) are supported, but aren't recommended for effects that may be active in large numbers.
	- Effect names are case-insensitive, "MYEFFECT" and "myEffect" are considered the same.
	- If ReplicationEvent was not provided during the construction of this object, then Replicate won't do anything even if all keys under it are 'true'.
	- All callbacks have a EffectContext arguement called 'context' when being called. You can use this context to get more information on the active effect at that moment.
	- If you plan to not use a callback, then don't define that specific callback. it will default to nil and won't run when the lifecycle reaches its point.

	Defaults:

	- Duration: 5
	- Interval: 1
	- Thottle: 0.25
	- MaxStacks: math.huge
	- StackBehavior: "stack_refresh"
	- Replicate: true for all
	- Callbacks: nil for all
	
	@param EffectName The effect name to register.
	@param Definition The contract that contains all the callbacks and information about a status effect.

	@return boolean whether successful.
]]
function Api:Register(args: {
	EffectName: string,
	Definition: Types.EffectDefinition,
}): boolean
	local self = Utilities.AnnotateSelf(self)
	local effectName = Utilities.NormalizeEffectName(args.EffectName)
	local definition = args.Definition

	-- Can't register name if it is already registered
	if self.RegisteredEffects[effectName] then
		Logger.Output("warn", `Attempted to register ({effectName}) when it's already registered.`)
		return false
	end

	-- Don't mutate the provided table definition directly
	-- That behavior is not intended for this function method
	local defaults = Defaults.EffectDefinition
	local normalized = table.clone(definition)

	normalized.Duration = normalized.Duration or defaults.Duration
	normalized.Interval = normalized.Interval or defaults.Interval
	normalized.Throttle = normalized.Throttle or defaults.Throttle
	normalized.MaxStacks = normalized.MaxStacks or defaults.MaxStacks
	normalized.StackBehavior = normalized.StackBehavior or defaults.StackBehavior

	local replicateDefaults = defaults.Replicate
	local replicateNormalized = normalized.Replicate

	if not replicateNormalized then
		normalized.Replicate = {
			Tick = replicateDefaults.Tick,
			Apply = replicateDefaults.Apply,
			Remove = replicateDefaults.Remove,
			Update = replicateDefaults.Update,
		}
	else
		-- These values can actually be false
		-- Use a nil check instead of the 'or' inline
		normalized.Replicate = {
			Tick = if replicateNormalized.Tick == nil then replicateDefaults.Tick else replicateNormalized.Tick,
			Apply = if replicateNormalized.Apply == nil then replicateDefaults.Apply else replicateNormalized.Apply,
			Remove = if replicateNormalized.Remove == nil then replicateDefaults.Remove else replicateNormalized.Remove,
			Update = if replicateNormalized.Update == nil then replicateDefaults.Update else replicateNormalized.Update,
		}
	end

	self.RegisteredEffects[effectName] = normalized
	return true
end

--[[
	Unregister an status effect so it can no longer be applied.

	If the effect is still running on a humanoid even after it's unregistration,
	it can still be removed manually by :Remove or automatically through connections within Statusify.

	@param EffectName The effect name to unregister.
	@param Terminate If true, the status effect will be removed for all humanoids without letting them naturally finish up.

	@return boolean whether successful.
]]
function Api:Unregister(args: {
	EffectName: string,
	Terminate: boolean,
}): boolean
	local self = Utilities.AnnotateSelf(self)
	local effectName = Utilities.NormalizeEffectName(args.EffectName)
	local terminate = args.Terminate

	-- The effect has to be registered
	if not self.RegisteredEffects[effectName] then
		Logger.Output("warn", `Attempted to unregister ({effectName}) when it wasn't registered.`)
		return false
	end

	self.RegisteredEffects[effectName] = nil

	if terminate then
		for humanoid, activeEffects in self.ActiveEffects do
			if not activeEffects then
				continue
			end

			if not activeEffects[effectName] then
				continue
			end

			Effects.Remove({
				Self = self,
				Humanoid = humanoid,
				EffectName = effectName,
				Action = "effect",
			})

			Threads.Cancel({
				Self = self,
				Humanoid = humanoid,
				Action = "effect",
				EffectName = effectName,
			})
		end
	end

	return true
end

--[[
	Apply an status effect onto a humanoid.

	@param Humanoid The humanoid to take the new status effect.
	@param EffectName The effect status that will be applied. This name should be registered first before being applied.

	@return boolean whether successful.
]]
function Api:Apply(args: {
	Humanoid: Humanoid,
	EffectName: string,
}): boolean
	local self = Utilities.AnnotateSelf(self)
	local effectName = Utilities.NormalizeEffectName(args.EffectName)
	local humanoid = args.Humanoid

	-- There should be a definition for this effect name
	local definition = self.RegisteredEffects[effectName]
	if not definition then
		Logger.Output("warn", `Attempted to apply unregistered effect ({effectName}) onto ({humanoid:GetFullName()}).`)
		return false
	end

	local now = workspace:GetServerTimeNow()

	-- If the effect already exists, use StackBehavior to determine how stacking will work
	-- If effect doesn't exist, then create a new instance of it for the humanoid
	local _, effect = Utilities.GetActiveEffects({
		EffectName = effectName,
		Self = self,
		Source = ":Apply",
		Humanoid = humanoid,
	})

	if not effect then
		Effects.Add({
			Self = self,
			Humanoid = humanoid,
			Effect = {
				Name = effectName,
				Definition = definition,
				StartTime = now,
				Stacks = 1,
				NextAvailableApplyTime = now + definition.Throttle :: number,
				ExpireTime = now + definition.Duration :: number,
				NextTickTime = now + definition.Interval :: number,
			},
		})

		return true
	end

	-- When throttling, the application timing cannot be too fast
	if now < effect.NextAvailableApplyTime then
		Logger.Output(
			"warn",
			`({effectName}) for ({humanoid:GetFullName()}) was throttled. No stacking behavior was ran.`
		)
		return false
	end

	local function operateBehavior(mutateStack: boolean, resetDuration: boolean)
		Replication.Replicate({
			Self = self,
			Message = "update",
			EffectName = effectName,
			Definition = definition,
			Humanoid = humanoid,
		})

		Effects.RunCallback({
			Message = "update",
			Self = self,
			Effect = effect,
			Humanoid = humanoid,
		})

		if mutateStack then
			Effects.MutateStack({
				Self = self,
				Humanoid = humanoid,
				Effect = effect,
				ApplyValue = 1,
			})
		end

		if resetDuration then
			effect.ExpireTime = now + definition.Duration :: number
		end
	end

	if definition.StackBehavior == "ignore" then
		-- Case ignore is here despite being empty so it doesn't fall into the 'else' statement
	elseif definition.StackBehavior == "stack" then
		operateBehavior(true, false)
	elseif definition.StackBehavior == "refresh" then
		operateBehavior(false, true)
	elseif definition.StackBehavior == "stack_refresh" then
		operateBehavior(true, true)
	else
		Logger.Output("warn", `Unknown stack behavior provided. Got: ({definition.StackBehavior}).`)
		return false
	end

	effect.NextAvailableApplyTime = now + definition.Throttle :: number -- Mutate after stack behavior is verified
	return true
end

--[[
	Remove an effect status from a humanoid.

	Action meanings:

	- remove: Remove the specified status.
	- removeAll: Remove every status from the humanoid. An effect name does not need to be provided.
	- decrement: Remove one stack of the effect. If the stack drops to 0, it will be removed automatically.
	
	@param Action Determines how removal should work.
	@param EffectName The effect that will be targeted. This can be optional.
	@param Humanoid The humanoid to check.

	@return boolean whether successful.
]]
function Api:Remove(args: {
	Action: "remove" | "remove_all" | "decrement",
	EffectName: string?,
	Humanoid: Humanoid,
}): boolean
	local self = Utilities.AnnotateSelf(self)
	local humanoid = args.Humanoid
	local action = args.Action
	local effectName = args.EffectName and Utilities.NormalizeEffectName(args.EffectName) or nil

	-- A effect name should have been provided if the actions were "remove" or "decrement"
	if (action == "remove" or action == "decrement") and not effectName then
		Logger.Output("warn", `Attempted to clear a effect when no effect name was specified.`)
		return false
	end

	-- Remove the specific active effect from the humanoid
	if action == "remove" then
		if not effectName then
			Logger.Output("warn", "")
			return false
		end

		Effects.Remove({
			Self = self,
			Humanoid = humanoid,
			EffectName = effectName,
			Action = "effect",
		})

	-- Remove all active effects from the humanoid
	elseif action == "remove_all" then
		local activeEffects = Utilities.GetActiveEffects({
			Self = self,
			Humanoid = humanoid,
			EffectName = effectName,
			Source = "Removing all active effects",
		})

		if not activeEffects then
			return false
		end

		Effects.Remove({
			Self = self,
			Humanoid = humanoid,
			Action = "all",
		})

	-- Decrement the stack value of the specific effect by 1
	elseif action == "decrement" then
		local _, effect = Utilities.GetActiveEffects({
			Self = self,
			Humanoid = humanoid,
			EffectName = effectName,
			Source = "Decrementing stack count",
		})

		if not effect then
			return false
		end

		Effects.MutateStack({
			Self = self,
			ApplyValue = -1,
			Humanoid = humanoid,
			Effect = effect,
		})
	else
		Logger.Output("warn", `Unknown action provided. Got: ({action}).`)
		return false
	end

	return true
end

--[[
	Returns the registered EffectDefinition for the given effect name.

	@param effectName The effect's name that will be checked for registeration.
	@return EffectDefinition or nil if not found.
]]
function Api:GetRegistered(effectName: string): Types.EffectDefinition?
	return Utilities.AnnotateSelf(self).RegisteredEffects[Utilities.NormalizeEffectName(effectName)]
end

--[[
	Returns the active EffectInstance for a humanoid.

	@param Humanoid The humanoid to check.
	@param EffectName The status effect's name to check under the humanoid.

	@return EffectInstance or nil if not found.
]]
function Api:GetActive(args: {
	Humanoid: Humanoid,
	EffectName: string,
}): Types.EffectInstance?
	local _, effect = Utilities.GetActiveEffects({
		EffectName = Utilities.NormalizeEffectName(args.EffectName),
		Humanoid = args.Humanoid,
		Self = Utilities.AnnotateSelf(self),
		Source = ":GetActive",
	})

	return effect
end

--[[
	Returns the count of active running effects for a given humanoid.

	@param humanoid The Humanoid to check.
	@return Number for the count.
]]
function Api:GetActiveCount(humanoid: Humanoid): number
	return Utilities.GetActiveCount(Utilities.AnnotateSelf(self), humanoid)
end

return table.freeze(Api)
