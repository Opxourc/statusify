--!strict

const Types = require("./Types")
const Logger = require("./Logger")
const Utilities = require("./Utilities")
const Replication = require("./Replication")

local Effects = {}

--[[
	Mutate the stack of an active effect.
	
	If the stack count drops to 0, the status effect will be removed from the humanoid.

	@param Effect The effect instance that will be mutated.
	@param Humanoid The humanoid that has this effect active.
	@param ApplyValue The application value to apply to the stacks, not the final value.
]]
function Effects.MutateStack(
	self: Types.Statusify,
	args: {
		Effect: Types.EffectInstance,
		Humanoid: Humanoid,
		ApplyValue: number,
	}
)
	local effect = args.Effect
	local humanoid = args.Humanoid
	local applyValue = args.ApplyValue

	local previous = effect.Stacks
	effect.Stacks = math.clamp(effect.Stacks + applyValue, 0, effect.Definition.MaxStacks :: number)
	local subsequent = effect.Stacks

	Replication.Replicate({
		Self = self,
		Humanoid = humanoid,
		Message = "update",
		EffectName = effect.Name,
		Definition = effect.Definition,
	})

	if effect.Stacks == 0 then
		self:_RemoveEffect({
			Humanoid = humanoid,
			EffectName = effect.Name,
			Action = "effect",
		})
	end

	Logger.Info(
		`({effect.Name}) status effect for ({humanoid:GetFullName()}) updated. (Stack: {previous} -> {subsequent}).`
	)
end

--[[
	Calls a callback function within an active effect and stores it under the humanoid.

	This callback is ran on a seperate thread so it cannot halt execution if it takes longer to complete. 
	When the callback finishes, the thread will automatically remove itself from the player.

	@param Effect The effect instance that that callbacks will run from
	@param Message The event message that took place and determines what callback to run.
	@param Humanoid The humanoid the effect is running off of.
]]
function Effects.RunCallback(
	self: Types.Statusify,
	args: {
		Effect: Types.EffectInstance,
		Message: Types.EventMessage,
		Humanoid: Humanoid,
	}
)
	local effect = args.Effect
	local message = args.Message
	local humanoid = args.Humanoid
	local definition = effect.Definition

	local function createThread(callback: (context: Types.EffectContext) -> ())
		local thread: thread
		thread = task.spawn(function()
			xpcall(callback, function(err)
				Logger.Severe(`({message}) callback for ({effect.Name}) ran into a problem. (Error: {err}).`)
			end, Utilities.CreateContext(humanoid, effect))

			-- Self clean up when callback has returned
			local activeThreads, threads, existing = Utilities.GetActiveThreads({
				Self = self,
				Humanoid = humanoid,
				EffectName = effect.Name,
				Thread = thread,
			})

			if not (threads and activeThreads) then
				return
			end

			if existing then
				threads[thread] = nil
			end

			activeThreads[effect.Name] = Utilities.NilOnEmpty(threads)
			self._activeThreads[humanoid] = Utilities.NilOnEmpty(activeThreads)
		end)

		return thread
	end

	local thread = nil
	if message == "apply" and definition.OnApply then
		thread = createThread(definition.OnApply)
	elseif message == "tick" and definition.OnTick then
		thread = createThread(definition.OnTick)
	elseif message == "update" and definition.OnUpdate then
		thread = createThread(definition.OnUpdate)
	elseif message == "remove" and definition.OnRemove then
		thread = createThread(definition.OnRemove)
	else
		Logger.Severe(`Either missing callback function or unknown message related to callback. (Got: {message}).`)
		return
	end

	self:_AddThread({
		Humanoid = humanoid,
		EffectName = effect.Name,
		Thread = thread,
	})
end

--[[
    Adds an effect to a humanoid to make it active.
	
	@param Humanoid The humanoid that will targetted with this new effect.
	@param Effect The effect instance that will be added to the humanoid.
]]
function Effects.Add(
	self: Types.Statusify,
	args: {
		Humanoid: Humanoid,
		Effect: Types.EffectInstance,
	}
)
	local humanoid = args.Humanoid
	local effect = args.Effect
	local effectName = effect.Name

	local activeEffects = self._activeEffects[humanoid]
	if not activeEffects then
		activeEffects = {}
		self._activeEffects[humanoid] = activeEffects
		self:_CreateWatcher(humanoid)
	end
	assert(activeEffects)

	if activeEffects[effectName] ~= nil then
		return
	end

	local effectCount = Utilities.GetActiveCount(self, humanoid)
	if effectCount >= self._maxEffectsPerHumanoid then
		return
	end

	activeEffects[effectName] = effect
	self:_RunCallback({
		Message = "apply",
		Humanoid = humanoid,
		Effect = effect,
	})
	Replication.Replicate({
		Self = self,
		Message = "apply",
		Definition = effect.Definition,
		Humanoid = humanoid,
		EffectName = effectName,
	})

	Logger.Info(`Added ({effectName}) status effect for ({humanoid:GetFullName()}).`)
end

--[[
	Removes active effect(s) so they're no longer considered active on a humanoid.

	Threads are not cancelled during the removal process.

	Actions:

	- "all": All active effects under the humanoid will be removed.
	- "effect": The specific active effect will be removed from the humanoid.

	@param Action Determines how removal will work.
	@param Humanoid The humanoid to remove from.
	@param EffectName The effect name that is considered active.
]]
function Effects.Remove(
	self: Types.Statusify,
	args: {
		Humanoid: Humanoid,
		EffectName: string?,
		Action: "all" | "effect",
	}
)
	local humanoid = args.Humanoid
	local effectName = args.EffectName
	local action = args.Action

	local function process(humanoid: Humanoid, effect: Types.EffectInstance?)
		if effect then
			Replication.Replicate({
				Self = self,
				Humanoid = humanoid,
				Message = "remove",
				EffectName = effect.Name,
				Definition = effect.Definition,
			})
			self:_RunCallback({
				Message = "remove",
				Humanoid = humanoid,
				Effect = effect,
			})
		end
	end

	if action == "effect" then
		if not effectName then
			Logger.Severe("Attempted to remove a status effect when an effect name wasn't provided.")
			return
		end

		local activeEffects, effect = Utilities.GetActiveEffects({
			Self = self,
			Humanoid = humanoid,
			EffectName = effectName,
			Source = "Effects.Remove",
		})

		if not activeEffects then
			return
		end

		process(humanoid, effect)
		activeEffects[effectName] = nil
		self._activeEffects[humanoid] = Utilities.NilOnEmpty(activeEffects)

		if not self._activeEffects[humanoid] then
			self:_DestroyWatcher(humanoid)
		end

		Logger.Info(`Removed ({effectName}) status effect from ({humanoid:GetFullName()}).`)
	elseif action == "all" then
		local activeEffects = Utilities.GetActiveEffects({
			Self = self,
			Humanoid = humanoid,
			Source = "Effects.Remove",
		})

		if not activeEffects then
			return
		end

		for name, effect in activeEffects do
			process(humanoid, effect)
			activeEffects[name] = nil
		end

		self._activeEffects[humanoid] = nil
		self:_DestroyWatcher(humanoid)

		Logger.Info(`Removed all status effects for ({humanoid:GetFullName()}).`)
	else
		Logger.Info(`Unknown action provided for removing effects. (Got {action}).`)
	end
end

return table.freeze(Effects)
