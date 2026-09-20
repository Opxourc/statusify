const Types = require("./Types")
const Logger = require("./Logger")
const Threads = require("./Threads")
const Watcher = require("./Watcher")
const Utilities = require("./Utilities")
const Replication = require("./Replication")

local Effects = {}

--[[
    Mutate the stack of an active effect. 
    If the stack value drops to 0, the effect will be removed from the humanoid.

    ApplyValue should be the value that will be added onto the current value, not the final value.
    (e.g., -1 for subtraction or 1 for addition).
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
	effect.Stacks = math.clamp(effect.Stacks + applyValue, 0, effect.Definition.MaxStacks)
	local subsequent = effect.Stacks

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
    Calls a callback function within an active effect.

    This callback will be ran a seperate thread so it cannot halt execution if it takes time to complete or errors.

    If the thread is successfully created, it will be stored under the humanoid.
]]
function Effects.RunCallback(args: {
	Self: Types.StatusifyInternal,
	Effect: Types.EffectInstance,
	EventMessage: Types.EventMessage,
	Humanoid: Humanoid,
})
	local self = args.Self
	local effect = args.Effect
	local humanoid = args.Humanoid
	local eventMessage = args.EventMessage
	local definition = effect.Definition

	local function createThread(
		callback: (context: Types.EffectContext) -> (),
		callbackName: string,
		context: Types.EffectContext
	)
		-- we'd want this to not yield the main thread if it takes longer to complete
		return task.spawn(function()
			-- This thread will run the wanted callback
			-- Will return when the callback finishes or an error happens
			local thread = task.spawn(function()
				local ok, err = pcall(callback, context)
				if not ok then
					Logger.Output(
						"error",
						`({callback}) callback for ({effect.Name}) errored on ({humanoid:GetFullName()}): ({err}).`
					)
				end
			end)

			-- This will automatically finish this thread if the effect ends or if the callback thread ends
			while coroutine.status(thread) ~= "dead" or effect.Removed do
				break
			end
		end)
	end

	-- Run the callback based on EventMessage
	local thread: thread? = nil
	local context = Utilities.CreateContext(humanoid, effect)

	if eventMessage == "apply" and definition.OnApply then
		thread = createThread(definition.OnApply, "OnApply", context)
	elseif eventMessage == "tick" and definition.OnTick then
		thread = createThread(definition.OnTick, "OnTick", context)
	elseif eventMessage == "update" and definition.OnUpdate then
		thread = createThread(definition.OnUpdate, "OnApply", context)
	elseif eventMessage == "remove" and definition.OnRemove then
		thread = createThread(definition.OnRemove, "OnRemove", context)
	else
		Logger.Output("error", `Unknown message provided for calling status effect callback. Got: ({eventMessage}).`)
		return
	end

	-- Store thread if it was successfully created
	Threads.AddToActive({
		Self = self,
		Humanoid = humanoid,
		EffectName = effect.Name,
		Thread = thread,
	})

	return thread
end

--[[
    Adds an effect to a humanoid to make it active.

    This function does not consider any stacking.
    It only standardizes setting an effect into it's active state.
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

	if activeEffects[effectName] ~= nil then
		Logger.Output("warn", `({effectName}) is already active on ({humanoid:GetFullName()}).`)
		return false
	end

	-- The number of effects the humanoid has cannot exceed the maximum allowed
	local effectCount = Utilities.GetActiveCount(self, humanoid)
	if effectCount >= self.MaxEffectsPerHumanoid then
		Logger.Output(
			"warn",
			`Attempted to add ({effectName}) onto ({humanoid:GetFullName()}) but it already has the maximum number of effects of ({self.MaxEffectsPerHumanoid}).`
		)
		return false
	end

	-- Assign effect, run callback, and replicate for "apply"
	activeEffects[effectName] = effect

	Effects.RunCallback({
		EventMessage = "apply",
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
	return true
end

function Effects.Remove(args: {
	Self: Types.StatusifyInternal,
	Humanoid: Humanoid,
	EffectName: string,
})
	local self = args.Self
	local humanoid = args.Humanoid
	local effectName = args.EffectName

	local activeEffects = self.ActiveEffects[humanoid]
	if not activeEffects then
		Logger.Output("warn", `({humanoid:GetFullName()}) doesn't have any active effects to remove.`)
		return
	end

	local effect = activeEffects[effectName]
	if not effect then
		Logger.Output("warn", `({humanoid:GetFullName()}) doesn't have a ({effectName}) to be removed.`)
		return
	end

	-- Call the replication event first before setting nil
	-- This is because replication is going to check the state of the effect for this humanoid again
	Replication.Replicate({
		Self = self,
		Humanoid = humanoid,
		Message = "remove",
		EffectName = effectName,
		Definition = effect.Definition,
	})

	Effects.RunCallback({
		EventMessage = "remove",
		Self = self,
		Humanoid = humanoid,
		Effect = effect,
	})

	activeEffects[effectName] = nil
	Logger.Output("log", `Removed ({effectName}) from ({humanoid:GetFullName()}).`)

	-- If there's no more effects under this humanoid
	-- Nullify the humanoid key and remove any watcher connections it has
	if next(activeEffects) == nil then
		Watcher.Destroy(self, humanoid)
		self.ActiveEffects[humanoid] = nil
		Logger.Output("log", `No more status effects remain for ({humanoid:GetFullName()}).`)
	end

	-- Threads are not cancelled here because we want them to naturally finish up
	-- They're cancelled explicity and usually alongside this function call for flexability

	return true
end

return table.freeze(Effects)
