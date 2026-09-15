const Types = require("./Types")
const Logger = require("./Logger")
const Defaults = require("./Defaults")
const Utilities = require("./Utilities")
const Connections = require("./Connections")
const Replication = require("./Replication")

-- Convenience exporting so you don't have to import 'Types.luau' constantly
export type ConstructorDependencies = Types.ConstructorDependencies
export type EffectDefinition = Types.EffectDefinition
export type EffectInstance = Types.EffectInstance
export type EffectContext = Types.EffectContext
export type StatusEffectExternal = Types.StatusEffectExternal
export type StatusEffectInternal = Types.StatusEffectInternal

local CurrentObject: StatusEffectExternal? = nil -- Represents the single object the StatusEffect

local StatusEffect = {}
StatusEffect.__index = StatusEffect

--[[
	Returns the currently existing object.
]]
function StatusEffect.GetExistingObject()
	return CurrentObject
end

--[[
	Constructs a new StatusEffect object.
	Only one object can exist at a time and should be referenced by .GetExistingObject() instead.
]]
function StatusEffect.New(dependencies: ConstructorDependencies): StatusEffectExternal?
	if CurrentObject then
		Logger.Output(
			"warn",
			"Attempted to create object when one already exists. Use .GetExistingObject() to get this object instead!"
		)
		return nil
	end

	local self = setmetatable({}, StatusEffect)

	-- Connections to handle the active states of effects when a humanoid dies or if a player leaves and joins
	self.WatcherConnections = Connections.CreaterWatcher(self)
	if #self.JanitorConnections == 0 then
		Logger.Output("warn", "Unable to create object due to janitor creation failure.")
		return nil
	end

	-- Connection that runs the lifecycle of currently running effects
	self.RuntimeConnection = Connections.CreateRuntime(self)
	if self.RuntimeConnection == nil then
		Logger.Output("warn", "Unable to create StatusEffect object due to runtime creation failure.")
		return nil
	end

	self.MaxNumberPerHumanoid = dependencies.MaxNumberPerHumanoid or Defaults.CD_DefaultMaxPerHumanoid -- The max number of effects a humanoid can take at a moment
	self.RemoteEvent = dependencies.RemoteEvent -- This will be used to send replication events to clients
	self.RegisteredEffects = {} :: { [string]: EffectDefinition } -- These are effects that are considered valid
	self.ActiveEffects = {} :: { [Humanoid]: { [string]: EffectInstance } } -- Effects that are currently running on a humanoid

	Logger.Output("log", "StatusEffect object created.")
	CurrentObject = self

	return self
end

--[[
	Destroys the object, releasing everything it owns.
]]
function StatusEffect:Destroy()
	local self = Utilities.AnnotateSelf(self)
	CurrentObject = nil

	for _, connection in self.JanitorConnections do
		connection:Disconnect()
	end

	if self.RuntimeConnection then
		self.RuntimeConnection:Disconnect()
	end

	for humanoid, effects in self.ActiveEffects do
		for effectName in effects do
			Utilities.RemoveFromActive(self, humanoid, effectName)
		end
	end

	Logger.Output("log", "StatusEffect object destroyed.")
end

--[[
	Register an effect status to be available for use.
	Properties will be defaulted to a value if they're nil.
	
	Use a number <= 0 for Interval to disable ticking (no logic and replication for ticks)
	Use math.huge for Duration for a permanent duration (effect is either removed when humanoid dies or manual removal)

	Note: Very small positive intervals (e.g. 0.1) are supported, but aren't recommended for effects that may be active in large numbers.
	Lower intervals cause 'OnTick' to execute more frequently and can increase CPU usage. Consider using 0.5 or 1 second(s) for effects that only need periodic updates.

	Effect names are case insensitive, "MYEFFECT" and "myEffect" are considered the same.
]]
function StatusEffect:RegisterEffect(effectName: string, definition: EffectDefinition): boolean
	local self = Utilities.AnnotateSelf(self)
	effectName = string.lower(effectName)

	if self.RegisteredEffects[effectName] then
		Logger.Output("warn", `Attempted to register ({effectName}) when it's already registered.`)
		return false
	end

	definition.Duration = definition.Duration or Defaults.ED_Defaults.Duration
	definition.Interval = definition.Interval or Defaults.ED_Defaults.Interval
	definition.MaxStacks = definition.MaxStacks or Defaults.ED_Defaults.MaxStacks
	definition.StackBehavior = definition.StackBehavior or Defaults.ED_Defaults.StackBehavior

	if not definition.Replicate then
		definition.Replicate = {
			Apply = Defaults.ED_Defaults.Replicate.Apply,
			Tick = Defaults.ED_Defaults.Replicate.Tick,
			Remove = Defaults.ED_Defaults.Replicate.Remove,
		}
	else
		definition.Replicate = {
			Apply = if definition.Replicate.Apply == nil
				then Defaults.ED_Defaults.Replicate.Apply
				else definition.Replicate.Apply,

			Tick = if definition.Replicate.Tick == nil
				then Defaults.ED_Defaults.Replicate.Tick
				else definition.Replicate.Tick,

			Remove = if definition.Replicate.Remove == nil
				then Defaults.ED_Defaults.Replicate.Remove
				else definition.Replicate.Remove,

			Update = if definition.Replicate.Update == nil
				then Defaults.ED_Defaults.Replicate.Update
				else definition.Replicate.Update,
		}
	end

	self.RegisteredEffects[effectName] = definition
	return true
end

--[[
	Unregister an effect status that will no longer be used.
	Use 'terminate' to destroy all active instances of the effect instantly.
]]
function StatusEffect:UnregisterEffect(effectName: string, terminate: boolean): boolean
	local self = Utilities.AnnotateSelf(self)
	effectName = string.lower(effectName)

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
			Utilities.RemoveFromActive(self, humanoid, effectName)
		end
	end

	return true
end

--[[
	Apply an effect status onto a humanoid.
	This effect status should be registered first before any application of it can be used!
]]
function StatusEffect:ApplyEffect(humanoid: Humanoid, effectName: string): boolean
	local self = Utilities.AnnotateSelf(self)
	effectName = string.lower(effectName)

	local definition = self.RegisteredEffects[effectName]
	if not definition then
		Logger.Output("warn", `Attempted to apply unregistered effect ({effectName}) onto ({humanoid:GetFullName()})`)
		return false
	end

	local now = workspace:GetServerTimeNow()
	local activeEffects = self.ActiveEffects[humanoid]
	if not activeEffects then
		activeEffects = {}
		self.ActiveEffects[humanoid] = activeEffects
	end

	-- If the effect already exists, check the StackBehavior to decide what to do
	local existing = activeEffects[effectName]
	if existing then
		if definition.StackBehavior == "ignore" then
		elseif definition.StackBehavior == "stack" then
			Utilities.MutateStack(self, humanoid, existing, 1)
		elseif definition.StackBehavior == "refresh" then
			existing.ExpireTime = now + definition.Duration
			Replication.Replicate({
				Self = self,
				Message = "update",
				EffectName = effectName,
				Definition = definition,
				Humanoid = humanoid,
			})
		end

		return true
	end

	local currentCount = 0
	for _ in activeEffects do
		currentCount += 1
	end

	-- The number of stacks cannot go higher than the max allowment
	if currentCount >= self.MaxNumberPerHumanoid then
		Logger.Output(
			"warn",
			`Attempted to apply ({effectName}) onto ({humanoid:GetFullName()}) but it already has the maximum number of effects of ({self.MaxNumberPerHumanoid}).`
		)
		return true
	end

	local effect: EffectInstance = {
		Name = effectName,
		Definition = definition,
		StartTime = now,
		Stacks = 1,
		ExpireTime = now + (definition.Duration :: number),
		NextTickTime = now + (definition.Interval :: number),
	}

	activeEffects[effectName] = effect

	-- Run callback for application
	if definition.OnApply then
		task.spawn(function()
			local ok, err = pcall(definition.OnApply, Utilities.CreateContext(humanoid, effect))
			if not ok then
				Logger.Output("warn", `OnApply callback for ({effectName}) errored: {err}`)
			end
		end)
	end

	Replication.Replicate({
		Self = self,
		Message = "apply",
		Definition = definition,
		Humanoid = humanoid,
		EffectName = effectName,
	})
	return true
end

--[[
	Remove an effect status from a humanoid.
	Use 'action' to determine how effect(s) should be removed.
	
	Actions:
		remove - Remove one single effect, ignoring all stacks on it.
		removeAll - Remove every effect from the humanoid.
		decrement - Remove one stack of the effect. If the stack drops to 0, it will be removed automatically.
	If the action is either "remove" or "decrement" you must specify the effectName.
]]
function StatusEffect:ClearEffect(
	humanoid: Humanoid,
	action: "remove" | "removeAll" | "decrement",
	effectName: string?
): boolean
	local self = Utilities.AnnotateSelf(self)

	-- effectName is not guaranteed to exist
	if effectName then
		effectName = string.lower(effectName)
	end

	if (action == "remove" or action == "decrement") and not effectName then
		Logger.Output("warn", `Attempted to clear a effect when no effect name was specified.`)
		return false
	end

	if action == "remove" then
		Utilities.RemoveFromActive(self, humanoid, effectName :: string)
		Logger.Output("log", `Removed ({effectName}) status effect from ({humanoid:GetFullName()}).`)
	elseif action == "removeAll" then
		local activeEffects = self.ActiveEffects[humanoid]
		if not activeEffects then
			Logger.Output("warn", `({humanoid:GetFullName()}) doesn't have any active effects to remove.`)
			return false
		end

		for name in activeEffects do
			Utilities.RemoveFromActive(self, humanoid, name)
		end
		Logger.Output("log", `Removed all status effects from ({humanoid:GetFullName()}).`)
	elseif action == "decrement" then
		local activeEffects = self.ActiveEffects[humanoid]
		if not activeEffects then
			Logger.Output("warn", `({humanoid:GetFullName()}) doesn't have any active effects to decrement.`)
			return false
		end

		local effect = activeEffects[effectName]
		if not effect then
			Logger.Output(
				"warn",
				`({humanoid:GetFullName()}) doesn't have a active ({effectName}) effect to decrement.`
			)
			return false
		end

		Utilities.MutateStack(self, humanoid, effect, -1)
		if effect.Stacks == 0 then
			Utilities.RemoveFromActive(self, humanoid, effectName :: string)
		end
		Logger.Output("log", `Decremented ({effectName}) status effect from ({humanoid:GetFullName()}).`)
	else
		Logger.Output("warn", `Unknown action provided. Got: ({action})`)
		return false
	end

	return true
end

--[[
	Returns the registered EffectDefinition for the given effect name, or nil if unregistered.
]]
function StatusEffect:GetRegisteredEffect(effectName: string): EffectDefinition?
	return Utilities.AnnotateSelf(self).RegisteredEffects[string.lower(effectName)]
end

--[[
	Returns the active EffectInstance for a humanoid, or nil if it isn't active.
]]
function StatusEffect:GetActiveEffect(humanoid: Humanoid, effectName: string): EffectInstance?
	local activeEffects = Utilities.AnnotateSelf(self).ActiveEffects[humanoid]
	if not activeEffects then
		return nil
	end

	return activeEffects[string.lower(effectName)]
end

--[[
	Returns whether a humanoid currently has the given effect active.
]]
function StatusEffect:HasEffect(humanoid: Humanoid, effectName: string): boolean
	local effects = Utilities.AnnotateSelf(self).ActiveEffects[humanoid]
	if not effects then
		return false
	end

	return effects[string.lower(effectName)] ~= nil
end

return table.freeze(StatusEffect)
