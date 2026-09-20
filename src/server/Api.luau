--!strict
local HeatmapQueryService = game:GetService("HeatmapQueryService")

const Types = require("./Types")
const Logger = require("./Logger")
const Threads = require("./Threads")
const Effects = require("./Effects")
const Defaults = require("./Defaults")
const Utilities = require("./Utilities")
const Replication = require("./Replication")
const Runtime = require("./Runtime")

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

	local self = setmetatable({}, Api)

	-- Connection that runs the lifecycle of currently running effects
	self.RuntimeConnection = Runtime.Create(self)
	if self.RuntimeConnection == nil then
		Logger.Output("warn", "Unable to create object due to runtime creation failure.")
		return nil
	end

	self.MaxEffectsPerHumanoid = maxEffectsPerHumanoid or Defaults.CD_DefaultMaxEffectsPerHumanoid -- The max number of effects a humanoid can take at a moment
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

	for connection in self.WatcherConnections do
		connection:Disconnect()
	end

	if self.RuntimeConnection then
		self.RuntimeConnection:Disconnect()
	end

	for humanoid, effects in self.ActiveEffects do
		for effectName in effects do
			Effects.Remove({
				Self = self,
				Humanoid = humanoid,
				EffectName = effectName,
			})
		end
	end

	Logger.Output("log", "Object destroyed.")
end

--[[
	Register an effect status to be available for use.

	Definition:

	- Definition properties will be defaulted to a value if they're nil.
	- Use a number <= 0 for Interval to disable ticking (no logic and replication for ticks)
	- Use math.huge for Duration for a permanent duration (effect is either removed when humanoid dies or manual removal)
	- Very small positive intervals (e.g. 0.1) are supported, but aren't recommended for effects that may be active in large numbers.
	- Effect names are case insensitive, "MYEFFECT" and "myEffect" are considered the same.

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
	local normalized = table.clone(definition)
	normalized.Duration = normalized.Duration or Defaults.ED_Defaults.Duration
	normalized.Interval = normalized.Interval or Defaults.ED_Defaults.Interval
	normalized.Throttle = normalized.Throttle or Defaults.ED_Defaults.Throttle
	normalized.MaxStacks = normalized.MaxStacks or Defaults.ED_Defaults.MaxStacks
	normalized.StackBehavior = normalized.StackBehavior or Defaults.ED_Defaults.StackBehavior

	if not normalized.Replicate then
		normalized.Replicate = {
			Apply = Defaults.ED_Defaults.Replicate.Apply,
			Tick = Defaults.ED_Defaults.Replicate.Tick,
			Remove = Defaults.ED_Defaults.Replicate.Remove,
		}
	else
		-- These values can actually be false
		-- Use a nil check instead of the 'or' inline
		normalized.Replicate = {
			Apply = if normalized.Replicate.Apply == nil
				then Defaults.ED_Defaults.Replicate.Apply
				else normalized.Replicate.Apply,

			Tick = if normalized.Replicate.Tick == nil
				then Defaults.ED_Defaults.Replicate.Tick
				else normalized.Replicate.Tick,

			Remove = if normalized.Replicate.Remove == nil
				then Defaults.ED_Defaults.Replicate.Remove
				else normalized.Replicate.Remove,

			Update = if normalized.Replicate.Update == nil
				then Defaults.ED_Defaults.Replicate.Update
				else normalized.Replicate.Update,
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

	-- Clean up this effect if terminate is true
	if terminate then
		for humanoid, activeEffects in self.ActiveEffects do
			if not activeEffects[effectName] then
				continue
			end

			-- We want to cancel all threads first before removing
			-- This is because we don't want to have OnRemove be involved with the cancellation
			Threads.Cancel({
				Self = self,
				Humanoid = humanoid,
				EffectName = effectName,
			})

			Effects.Remove({
				Self = self,
				Humanoid = humanoid,
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
		return Effects.Add({
			Self = self,
			Humanoid = humanoid,
			Effect = {
				Name = effectName,
				Definition = definition,
				StartTime = now,
				Stacks = 1,
				NextAvailableApplyTime = now + definition.Throttle,
				ExpireTime = now + (definition.Duration :: number),
				NextTickTime = now + (definition.Interval :: number),
			},
		})
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
			EventMessage = "update",
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
			effect.ExpireTime = now + definition.Duration
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

	effect.NextAvailableApplyTime = now + definition.Throttle -- Mutate after stack behavior is verified
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
	Action: "remove" | "removeAll" | "decrement",
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
		Effects.Remove({
			Self = self,
			Humanoid = humanoid,
			EffectName = effectName :: string,
		})

	-- Remove all active effects from the humanoid
	elseif action == "removeAll" then
		local activeEffects = Utilities.GetActiveEffects({
			Self = self,
			Humanoid = humanoid,
			EffectName = effectName,
			Source = "Removing all active effects",
		})

		if activeEffects then
			for name in activeEffects do
				Effects.Remove({
					Self = self,
					Humanoid = humanoid,
					EffectName = name,
				})
			end
		end

	-- Decrement the stack value of the specific effect by 1
	elseif action == "decrement" then
		local _, effect = Utilities.GetActiveEffects({
			Self = self,
			Humanoid = humanoid,
			EffectName = effectName,
			Source = "Decrementing stack count",
		})

		if effect then
			Effects.MutateStack({
				Self = self,
				ApplyValue = -1,
				Humanoid = humanoid,
				Effect = effect,
			})
		end
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
