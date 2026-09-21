--!strict

const Types = require("./Types")
const Logger = require("./Logger")
const Threads = require("./Threads")
const Watcher = require("./Watcher")
const Utilities = require("./Utilities")
const Replication = require("./Replication")

local Effects = {}

--[[
	Mutate the stack of an active effect.
	
	If the stack count drops to 0, the status effect will be removed from the humanoid.

	@param Self The object that will be referenced from.
	@param Effect The effect instance that will be mutated.
	@param Humanoid The humanoid that has this effect active.
	@param ApplyValue The application value to apply to the stacks, not the final value.
]]
function Effects.MutateStack(args: {
	Self: Types.StatusifyInternal,
	Effect: Types.EffectInstance,
	Humanoid: Humanoid,
	ApplyValue: number,
})
	local self = args.Self
	local effect = args.Effect
	local humanoid = args.Humanoid
	local applyValue = args.ApplyValue

	local previous = effect.Stacks
	effect.Stacks = math.clamp(effect.Stacks + applyValue, 0, effect.Definition.MaxStacks :: number)
	local subsequent = effect.Stacks

	-- Stack value changed so call "update" replication
	Replication.Replicate({
		Self = self,
		Humanoid = humanoid,
		Message = "update",
		EffectName = effect.Name,
		Definition = effect.Definition,
	})

	-- If the stack count drops to 0
	-- Remove the effect from the humanoid
	if effect.Stacks == 0 then
		Effects.Remove({
			Self = self,
			Humanoid = humanoid,
			EffectName = effect.Name,
			Action = "effect",
		})
		Logger.Output(
			"log",
			`({effect.Name}) status effect stack value for ({humanoid:GetFullName()}) dropped 0. Effect was removed.`
		)
	end

	Logger.Output(
		"log",
		`Mutated ({effect.Name}) status effect stack for ({humanoid:GetFullName()}) to ({previous} -> {subsequent}).`
	)
end

--[[
	Calls a callback function within an active effect and stores it under the humanoid.

	This callback is ran on a seperate thread so it cannot halt execution if it takes longer to complete. 
	When the callback finishes, the thread will automatically remove itself from the player.

	@param Self The object that will be referenced from.
	@param Effect The effect instance that that callbacks will run from
	@param Message The event message that took place and determines what callback to run.
	@param Humanoid The humanoid the effect is running off of.
]]
function Effects.RunCallback(args: {
	Self: Types.StatusifyInternal,
	Effect: Types.EffectInstance,
	Message: Types.EventMessage,
	Humanoid: Humanoid,
})
	local self = args.Self
	local effect = args.Effect
	local message = args.Message
	local humanoid = args.Humanoid
	local definition = effect.Definition

	local function removeThread(thread: thread)
		local activeThreads, threads, existing = Utilities.GetActiveThreads({
			Self = self,
			Humanoid = humanoid,
			EffectName = effect.Name,
			Thread = thread,
			Source = "Effects.RunCallback",
		})

		if not (threads and activeThreads) then
			return
		end

		if existing then
			threads[thread] = nil
		end

		-- Check if the number of threads for the humanoid as dropped to 0
		activeThreads[effect.Name] = Utilities.NilOnEmpty(threads)
		self.ActiveThreads[humanoid] = Utilities.NilOnEmpty(activeThreads)
	end

	local function createThread(callback: (context: Types.EffectContext) -> (), callbackName: string)
		-- We'd want this to not yield the main thread if it takes longer to complete
		-- All callbacks should get a context, providing information on the active effect
		local context = Utilities.CreateContext(humanoid, effect)

		local thread: thread
		thread = task.spawn(function()
			-- If the callback hits a problem, log it so and trace it so you know where to look
			xpcall(callback, function(err)
				Logger.Output("warn", `({message}) callback for ({effect.Name}) ran into a problem.`)
				Logger.Output("warn", `Traceback: ({debug.traceback(tostring(err))})`)
			end, context)

			-- Once the callback has completed
			-- Remove this thread from the table as it will finish up
			removeThread(thread)
		end)

		return thread
	end

	-- Run the callback based on EventMessage
	local thread = nil
	if message == "apply" and definition.OnApply then
		thread = createThread(definition.OnApply, "OnApply")
	elseif message == "tick" and definition.OnTick then
		thread = createThread(definition.OnTick, "OnTick")
	elseif message == "update" and definition.OnUpdate then
		thread = createThread(definition.OnUpdate, "OnApply")
	elseif message == "remove" and definition.OnRemove then
		thread = createThread(definition.OnRemove, "OnRemove")
	else
		Logger.Output("error", `Unknown message provided for calling status effect callback. Got: ({message}).`)
		return
	end

	-- Store thread if it was successfully created
	Threads.Add({
		Self = self,
		Humanoid = humanoid,
		EffectName = effect.Name,
		Thread = thread,
	})
end

--[[
    Adds an effect to a humanoid to make it active.
	
	@param Self The object that will be referenced from.
	@param Humanoid The humanoid that will targetted with this new effect.
	@param Effect The effect instance that will be added to the humanoid.
]]
function Effects.Add(args: {
	Self: Types.StatusifyInternal,
	Humanoid: Humanoid,
	Effect: Types.EffectInstance,
})
	local self = args.Self
	local humanoid = args.Humanoid
	local effect = args.Effect
	local effectName = effect.Name

	-- If the humanoid doesn't have a table, make a new one
	-- Also create a watcher connection since this in a new table
	-- Another Watcher connection won't be created for this humanoid as long as this table exists
	local activeEffects = self.ActiveEffects[humanoid]
	if not activeEffects then
		activeEffects = {}
		self.ActiveEffects[humanoid] = activeEffects
		Watcher.Create(self, humanoid)
	end

	assert(activeEffects)

	if activeEffects[effectName] ~= nil then
		Logger.Output("warn", `({effectName}) is already active on ({humanoid:GetFullName()}).`)
		return
	end

	-- The number of effects the humanoid has cannot exceed the maximum allowed
	local effectCount = Utilities.GetActiveCount(self, humanoid)
	if effectCount >= self.MaxEffectsPerHumanoid then
		Logger.Output(
			"warn",
			`Attempted to add ({effectName}) onto ({humanoid:GetFullName()}) but it already has the maximum number of effects of ({self.MaxEffectsPerHumanoid}).`
		)
		return
	end

	-- Assign effect, run callback, and replicate for "apply"
	activeEffects[effectName] = effect

	Effects.RunCallback({
		Message = "apply",
		Self = self,
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

	Logger.Output("log", `Added ({effectName}) to ({humanoid:GetFullName()}).`)
end

--[[
	Removes active effect(s) so they're no considered active on a humanoid.

	Threads are not cancelled during the removal process.

	Actions:

	- "all": All active effects under the humanoid will be removed.
	- "effect": The specific active effect will be removed from the humanoid.

	@param Self The object that will be referenced from.
	@param Action Determines how removal will work.
	@param Humanoid The humanoid to remove from.
	@param EffectName The effect name that is considered active.
]]
function Effects.Remove(args: {
	Self: Types.StatusifyInternal,
	Humanoid: Humanoid,
	EffectName: string?,
	Action: "all" | "effect",
})
	local self = args.Self
	local humanoid = args.Humanoid
	local effectName = args.EffectName
	local action = args.Action

	local function removeEffect(humanoid: Humanoid, effect: Types.EffectInstance?)
		if not effect then
			return
		end

		-- Call the replication event first before setting nil
		-- This is because replication is going to check the state of the effect for this humanoid again
		Replication.Replicate({
			Self = self,
			Humanoid = humanoid,
			Message = "remove",
			EffectName = effect.Name,
			Definition = effect.Definition,
		})

		Effects.RunCallback({
			Message = "remove",
			Self = self,
			Humanoid = humanoid,
			Effect = effect,
		})
	end

	-- Remove a specific active effect
	if action == "effect" then
		-- There shoul dn effect name provided if the action is "effect"
		if not effectName then
			Logger.Output("warn", "Attempted to remove active effect when an effect name wasn't provided.")
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

		removeEffect(humanoid, effect)

		activeEffects[effectName] = nil
		Logger.Output("log", `Removed ({effectName}) from ({humanoid:GetFullName()}).`)

		-- We don't know if that effect was the last to be removed for this humanoid
		-- Check if there's any more effects and if there isn't set nil to the humanoid table
		self.ActiveEffects[humanoid] = Utilities.NilOnEmpty(activeEffects)

	-- Remove all active effects under a humanoid
	elseif action == "all" then
		local activeEffects = Utilities.GetActiveEffects({
			Self = self,
			Humanoid = humanoid,
			Source = "Effects.Remove",
		})

		if not activeEffects then
			return
		end

		-- Remove all active effects
		-- Uses 'name' to avoi shadow
		for name, effect in activeEffects do
			removeEffect(humanoid, effect)
			activeEffects[name] = nil
		end

		self.ActiveEffects[humanoid] = nil
		Logger.Output("log", `Removed all active effects for ({humanoid:GetFullName()}).`)
	else
		Logger.Output("warn", `Unknown action provided for removing effects. Got ({action})`)
	end
end

return table.freeze(Effects)
