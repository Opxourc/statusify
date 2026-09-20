const Types = require("./Types")
const Logger = require("./Logger")
const Threads = require("./Threads")
const Effects = require("./Effects")
const Defaults = require("./Defaults")
const Utilities = require("./Utilities")
const Replication = require("./Replication")
const Runtime = require("./Runtime")
const Watcher = require("./Watcher")

local Api = {}
Api.__index = Api

--[[
	Constructs a new Statusify object.

	@param MaxEffectsPerHumanoid - The maximum number of effects a humanoid can have active. Defaults to 3 if not provided.
	@param ReplicatedEvent - For replicating messages to the client to visually show effects and states. Replication won't happen if this is nil.
	@return Constructed Statusify object.
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
	return self :: Types.StatusifyInternal
end

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

function Api:RegisterEffect(args: {
	EffectName: string,
	Definition: Types.EffectDefinition,
}): boolean
	local self = Utilities.AnnotateSelf(self)
	local effectName = Utilities.NormalizeEffectName(args.EffectName)
	local definition = args.Definition

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

function Api:UnregisterEffect(args: {
	EffectName: string,
	Terminate: boolean,
}): boolean
	local self = Utilities.AnnotateSelf(self)
	local effectName = Utilities.NormalizeEffectName(args.EffectName)
	local terminate = args.Terminate

	if not self.RegisteredEffects[effectName] then
		Logger.Output("warn", `Attempted to unregister ({effectName}) when it wasn't registered.`)
		return false
	end

	self.RegisteredEffects[effectName] = nil

	if terminate then
		for humanoid, activeEffects in self.ActiveEffects do
			if not activeEffects[effectName] then
				continue
			end

			Effects.Remove({
				Self = self,
				Humanoid = humanoid,
				EffectName = effectName,
			})
			Threads.CancelAllFromActive({
				Self = self,
				Humanoid = humanoid,
				Action = "cancelEffect",
				EffectName = effectName,
			})
		end
	end

	return true
end

function Api:ApplyEffect(args: {
	Humanoid: Humanoid,
	EffectName: string,
}): boolean
	local self = Utilities.AnnotateSelf(self)
	local effectName = Utilities.NormalizeEffectName(args.EffectName)
	local humanoid = args.Humanoid

	local definition = self.RegisteredEffects[effectName]
	if not definition then
		Logger.Output("warn", `Attempted to apply unregistered effect ({effectName}) onto ({humanoid:GetFullName()}).`)
		return false
	end

	local now = workspace:GetServerTimeNow()
	local activeEffects = self.ActiveEffects[humanoid]
	if not activeEffects then
		activeEffects = {}
		self.ActiveEffects[humanoid] = activeEffects
		Watcher.Create(self, humanoid)
	end

	-- If the effect already exists, check the StackBehavior to decide what to do
	local existing = activeEffects[effectName]
	if existing then
		if now < existing.NextAvailableApplyTime then
			Logger.Output(
				"warn",
				`({effectName}) for ({humanoid:GetFullName()}) was throttled. No reapplication was ran.`
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
				Effect = existing,
				Humanoid = humanoid,
			})

			if mutateStack then
				Effects.MutateStack({
					Self = self,
					Humanoid = humanoid,
					Effect = existing,
					ApplyValue = 1,
				})
			end

			if resetDuration then
				existing.ExpireTime = now + definition.Duration
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

		existing.NextAvailableApplyTime = now + definition.Throttle -- Mutate after stack behavior is verified
		return true
	end

	-- Create the effect and add it to the humanoid
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

function Api:ClearEffect(args: {
	Action: "remove" | "removeAll" | "decrement",
	EffectName: string?,
	Humanoid: Humanoid,
}): boolean
	local self = Utilities.AnnotateSelf(self)
	local humanoid = args.Humanoid
	local action = args.Action
	local effectName = args.EffectName and Utilities.NormalizeEffectName(args.EffectName) or nil

	if (action == "remove" or action == "decrement") and not effectName then
		Logger.Output("warn", `Attempted to clear a effect when no effect name was specified.`)
		return false
	end

	-- Use Action to determine what case to run
	if action == "remove" then
		Effects.Remove({
			Self = self,
			Humanoid = humanoid,
			EffectName = effectName,
		})
	elseif action == "removeAll" then
		local activeEffects = Utilities.GetActiveEffects({
			Self = self,
			Humanoid = humanoid,
			EffectName = effectName,
			Source = "Removing all active effects",
		})

		for effectName in activeEffects do
			Effects.Remove({
				Self = self,
				Humanoid = humanoid,
				EffectName = effectName,
			})
		end
	elseif action == "decrement" then
		local _, effect = Utilities.GetActiveEffects({
			Self = self,
			Humanoid = humanoid,
			EffectName = effectName,
			Source = "Decrementing stack count",
		})

		Effects.MutateStack({
			Self = self,
			Humanoid = humanoid,
			Effect = effect,
			ApplyValue = -1,
		})
	else
		Logger.Output("warn", `Unknown action provided. Got: ({action}).`)
		return false
	end

	return true
end

function Api:GetRegisteredEffect(effectName: string): Types.EffectDefinition?
	local self = Utilities.AnnotateSelf(self)
	effectName = Utilities.NormalizeEffectName(effectName)
	return self.RegisteredEffects[effectName]
end

function Api:GetActiveEffect(args: {
	Humanoid: Humanoid,
	EffectName: string,
}): Types.EffectInstance?
	local self = Utilities.AnnotateSelf(self)
	local humanoid = args.Humanoid
	local effectName = Utilities.NormalizeEffectName(args.EffectName)

	local activeEffects = self.ActiveEffects[humanoid]
	if not activeEffects then
		return nil
	end

	return activeEffects[effectName]
end

function Api:HasEffect(args: {
	Humanoid: Humanoid,
	EffectName: string,
}): boolean
	local self = Utilities.AnnotateSelf(self)
	local humanoid = args.Humanoid
	local effectName = Utilities.NormalizeEffectName(args.EffectName)

	local effects = self.ActiveEffects[humanoid]
	if not effects then
		return false
	end

	return effects[effectName] ~= nil
end

function Api:GetNumberOfActiveEffects(humanoid: Humanoid): number
	local self = Utilities.AnnotateSelf(self)
	return Utilities.GetActiveCount(self, humanoid)
end

return table.freeze(Api)
