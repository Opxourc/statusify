--!strict

const Types = require("./Types")
const Logger = require("./Logger")
const Watcher = require("./Watcher")
const Threads = require("./Threads")
const Effects = require("./Effects")
const Runtime = require("./Runtime")
const Defaults = require("./Defaults")
const Utilities = require("./Utilities")
const Replication = require("./Replication")

local Api = {
	_CreateWatcher = Watcher.Create,
	_DestroyWatcher = Watcher.Destroy,
	_AddThread = Threads.Add,
	_CancelThread = Threads.Cancel,
	_CreateRuntime = Runtime.Create,
	_DestroyRuntime = Runtime.Destroy,
	_MutateStack = Effects.MutateStack,
	_RunCallback = Effects.RunCallback,
	_AddEffect = Effects.Add,
	_RemoveEffect = Effects.Remove,
	_Replicate = Replication.Replicate,
	_GetActiveEffects = Effects.GetActiveEffects,
	_GetActiveThreads = Threads.GetActiveThreads,
}
Api.__index = Api

--[[
	Constructs a new Statusify object.

	@param MaxEffectsPerHumanoid The maximum number of effects a humanoid can have active. Defaults to 3 if not provided.
	@param ReplicationEvent For replicating messages to the client to visually show effects and states. Replication won't happen if this is nil.

	@return Statusify object.
]]
function Api.new(args: {
	MaxEffectsPerHumanoid: number?,
	ReplicationEvent: RemoteEvent?,
}): Types.Statusify
	local maxEffectsPerHumanoid = args.MaxEffectsPerHumanoid
	local replicationEvent = args.ReplicationEvent

	local self = (
		setmetatable({
			_maxEffectsPerHumanoid = maxEffectsPerHumanoid or Defaults.Constructor.MaxEffectsPerHumanoid,
			_replicationEvent = replicationEvent,
			_watcherConnections = {},
			_registeredEffects = {},
			_activeEffects = {},
			_activeThreads = {},
			_runtimeConnection = nil,
		}, Api) :: any
	) :: Types.Statusify

	self:_CreateRuntime()

	Logger.info("Statusify object created.")
	return self
end

--[[
	Destroys the object, releasing everything it owns.
	@return nil so you can reassign the object to it.
]]
function Api.Destroy(self: Types.Statusify)
	Runtime.Destroy(self)
	for humanoid, effects in self._activeEffects do
		self:_DestroyWatcher(humanoid)
		self:_CancelThread({
			Humanoid = humanoid,
			Action = "all",
		})

		-- Effects.Remove doesn't need to be called since it only contains data that the garbage collector will handle, no threads or connections
		-- Also removal runs replication and callbacks which isn't required when destroying the object
	end

	Logger.info("Statusify object destroyed.")
	return nil
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
	- All callbacks have a EffectContext argument called 'context' when being called. You can use this context to get more information on the active effect at that moment.
	- If you don't use a certain callback, then don't define that callback. it will default to nil and won't run when the lifecycle reaches its point.

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
]]
function Api.Register(
	self: Types.Statusify,
	args: {
		EffectName: string,
		Definition: Types.EffectDefinition,
	}
)
	local effectName = Utilities.normalizeEffectName(args.EffectName)
	local definition = args.Definition

	-- Can't register name if it is already registered
	if self._registeredEffects[effectName] then
		Logger.severe(`Attempted to register ({effectName}) effect status when it's already registered.`)
		return
	end

	local defaults = Defaults.EffectDefinition
	local normalized = table.clone(definition)

	normalized.Duration = normalized.Duration or defaults.Duration
	normalized.Interval = normalized.Interval or defaults.Interval
	normalized.Throttle = normalized.Throttle or defaults.Throttle
	normalized.MaxStacks = normalized.MaxStacks or defaults.MaxStacks
	normalized.StackBehavior = normalized.StackBehavior or defaults.StackBehavior :: Types.StackBehavior

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
		normalized.Replicate = {
			Tick = if replicateNormalized.Tick == nil then replicateDefaults.Tick else replicateNormalized.Tick,
			Apply = if replicateNormalized.Apply == nil then replicateDefaults.Apply else replicateNormalized.Apply,
			Remove = if replicateNormalized.Remove == nil then replicateDefaults.Remove else replicateNormalized.Remove,
			Update = if replicateNormalized.Update == nil then replicateDefaults.Update else replicateNormalized.Update,
		}
	end

	self._registeredEffects[effectName] = normalized
end

--[[
	Unregister an status effect so it can no longer be applied.

	If the effect is still running on a humanoid even after it's unregistration,
	it can still be removed manually by :Remove or automatically through connections within Statusify.

	@param EffectName The effect name to unregister.
	@param Terminate If true, the status effect will be removed for all humanoids without letting them naturally finish up.
]]
function Api.Unregister(
	self: Types.Statusify,
	args: {
		EffectName: string,
		Terminate: boolean,
	}
)
	local effectName = Utilities.normalizeEffectName(args.EffectName)
	local terminate = args.Terminate

	if not self._registeredEffects[effectName] then
		return
	end
	self._registeredEffects[effectName] = nil

	if terminate then
		for humanoid, activeEffects in self._activeEffects do
			if not (activeEffects and activeEffects[effectName]) then
				continue
			end

			self:_RemoveEffect({
				Humanoid = humanoid,
				EffectName = effectName,
				Action = "effect",
			})
			self:_CancelThread({
				Humanoid = humanoid,
				Action = "effect",
				EffectName = effectName,
			})
		end
	end
end

--[[
	Apply an status effect onto a humanoid.

	@param Humanoid The humanoid to take the new status effect.
	@param EffectName The effect status that will be applied. This name should be registered first before being applied.
]]
function Api.Apply(
	self: Types.Statusify,
	args: {
		Humanoid: Humanoid,
		EffectName: string,
	}
)
	local effectName = Utilities.normalizeEffectName(args.EffectName)
	local humanoid = args.Humanoid

	local definition = self._registeredEffects[effectName]
	if not definition then
		Logger.severe(`Attempted to apply ({effectName}) effect status despite not being registered.`)
		return
	end

	local now = workspace:GetServerTimeNow()
	local _, effect = self:_GetActiveEffects({
		EffectName = effectName,
		Humanoid = humanoid,
	})

	if not effect then
		self:_AddEffect({
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
		return
	end

	if now < effect.NextAvailableApplyTime then
		return
	end

	local function operateBehavior(mutateStack: boolean, resetDuration: boolean)
		if mutateStack then
			self:_MutateStack({
				Humanoid = humanoid,
				Effect = effect,
				ApplyValue = 1,
			})
		end

		if resetDuration then
			effect.ExpireTime = now + definition.Duration :: number
		end

		self:_Replicate({
			Message = "update",
			EffectName = effectName,
			Definition = definition,
			Humanoid = humanoid,
		})
		self:_RunCallback({
			Message = "update",
			Effect = effect,
			Humanoid = humanoid,
		})
	end

	if definition.StackBehavior == "ignore" then
	elseif definition.StackBehavior == "stack" then
		operateBehavior(true, false)
	elseif definition.StackBehavior == "refresh" then
		operateBehavior(false, true)
	elseif definition.StackBehavior == "stack_refresh" then
		operateBehavior(true, true)
	else
		Logger.severe(`Unknown stack behavior in definition. Got: ({definition.StackBehavior}).`)
	end

	effect.NextAvailableApplyTime = now + definition.Throttle :: number
end

--[[
	Remove an effect status from a humanoid.

	Action meanings:

	- effect: Remove the specified status.
	- all: Remove every status from the humanoid. An effect name does not need to be provided.
	- decrement: Remove one stack of the effect. If the stack drops to 0, it will be removed automatically.
	
	@param Action Determines how removal should work.
	@param EffectName The effect that will be targeted. This can be optional.
	@param Humanoid The humanoid to check.
]]
function Api.Remove(
	self: Types.Statusify,
	args: {
		Action: "effect" | "all" | "decrement",
		EffectName: string?,
		Humanoid: Humanoid,
	}
)
	local humanoid = args.Humanoid
	local action = args.Action
	local effectName = args.EffectName and Utilities.normalizeEffectName(args.EffectName) or nil

	if (action == "effect" or action == "decrement") and not effectName then
		Logger.severe(`Attempted removal behavior for an effect status when no effect name was specified.`)
		return
	end

	if action == "effect" then
		self:_RemoveEffect({
			Humanoid = humanoid,
			EffectName = effectName,
			Action = "effect",
		})
	elseif action == "all" then
		self:_RemoveEffect({
			Humanoid = humanoid,
			Action = "all",
		})
	elseif action == "decrement" then
		local _, effect = self:_GetActiveEffects({
			Humanoid = humanoid,
			EffectName = effectName,
		})

		if not effect then
			return
		end

		self:_MutateStack({
			ApplyValue = -1,
			Humanoid = humanoid,
			Effect = effect,
		})
	else
		Logger.severe(`Unknown action provided for status effect removal behavior. Got ({action}).`)
	end
end

--[[
	Returns the registered EffectDefinition for the given effect name.

	@param effectName The effect's name that will be checked for registration.
	@return EffectDefinition or nil if not found.
]]
function Api.GetRegistered(self: Types.Statusify, effectName: string): Types.EffectDefinition?
	return self._registeredEffects[Utilities.normalizeEffectName(effectName)]
end

--[[
	Returns the active EffectInstance for a humanoid.

	@param Humanoid The humanoid to check.
	@param EffectName The status effect's name to check under the humanoid.

	@return EffectInstance or nil if not found.
]]
function Api.GetActive(
	self: Types.Statusify,
	args: {
		Humanoid: Humanoid,
		EffectName: string,
	}
): Types.EffectInstance?
	local _, effect = self:_GetActiveEffects({
		EffectName = Utilities.normalizeEffectName(args.EffectName),
		Humanoid = args.Humanoid,
	})

	return effect
end

--[[
	Returns the count of active running status effects for a given humanoid.

	@param humanoid The Humanoid to check.
	@return number that represents the count.
]]
function Api.GetActiveCount(self: Types.Statusify, humanoid: Humanoid): number
	local activeEffects = self:_GetActiveEffects({
		Humanoid = humanoid,
	})

	local count = 0
	if activeEffects then
		for _ in activeEffects do
			count += 1
		end
	end

	return count
end

return table.freeze(Api)
