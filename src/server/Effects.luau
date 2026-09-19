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

function Effects.RunOnUpdate(args: {
	Self: Types.StatusifyInternal,
	Effect: Types.EffectInstance,
	Humanoid: Humanoid,
})
	local self = args.Self
	local effect = args.Effect
	local humanoid = args.Humanoid
	local effectName = effect.Name
	local definition = effect.Definition

	if definition.OnUpdate then
		Threads.AddToActive({
			Self = self,
			Humanoid = humanoid,
			EffectName = effectName,
			Thread = task.spawn(function()
				local ok, err = pcall(definition.OnUpdate, Utilities.CreateContext(humanoid, effect))
				if not ok then
					Logger.Output("error", `OnUpdate callback for ({effectName}) errored: ({err}).`)
				end
			end),
		})
	end
end

function Effects.Add(args: {
	Self: Types.StatusifyInternal,
	Humanoid: Humanoid,
	EffectName: string,
}) end

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
