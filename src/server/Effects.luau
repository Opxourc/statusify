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
		return task.spawn(function()
			local ok, err = pcall(callback, context)
			if not ok then
				Logger.Output(
					"error",
					`({callback}) callback for ({effect.Name}) errored on ({humanoid:GetFullName()}): ({err}).`
				)
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
	activeEffects[effectName] = nil

	local effectCounts = self.ActiveEffectCounts[humanoid]
	if effectCounts then
		effectCounts = math.max(0, effectCounts - 1)

		if effectCounts == 0 then
			effectCounts = nil
		end

		self.ActiveEffectCounts[humanoid] = effectCounts
	end

	Logger.Output("log", `Removed ({effectName}) from ({humanoid:GetFullName()}).`)

	-- If there's no more effects under this humanoid
	-- Nullify the humanoid key and remove any watcher connections it has
	if next(activeEffects) == nil then
		Watcher.Destroy(self, humanoid)
		self.ActiveEffects[humanoid] = nil
		Logger.Output("log", `No more status effects remain for ({humanoid:GetFullName()}).`)
	end

	-- Run callback for the removal
	if effect.Definition.OnRemove then
		Threads.AddToActive({
			Self = self,
			Humanoid = humanoid,
			EffectName = effectName,
			Thread = task.spawn(function()
				local ok, err = pcall(effect.Definition.OnRemove, Utilities.CreateContext(humanoid, effect))
				if not ok then
					Logger.Output("error", `OnRemove callback for ({effectName}) errored: ({err}).`)
				end
			end),
		})
	end

	-- Threads are not cancelled here because we want them to naturally finish up
	-- They're cancelled explicity and usually alongside this function call for flexability

	return true
end

return table.freeze(Effects)
