const Replication = require("./Replication")
const Threads = require("./Threads")
const Logger = require("./Logger")
const Types = require("./Types")

local Utilities = {}

function Utilities.AnnotateSelf(a: any)
	return a :: Types.StatusEffectInternal
end

function Utilities.CreateContext(humanoid: Humanoid, effect: Types.EffectInstance): Types.EffectContext
	return {
		Target = humanoid,
		Effect = effect,
		Stacks = effect.Stacks,
	}
end

function Utilities.MutateStack(
	self: Types.StatusEffectInternal,
	humanoid: Humanoid,
	effect: Types.EffectInstance,
	applyValue: number
)
	effect.Stacks = math.clamp(effect.Stacks + applyValue, 0, effect.Definition.MaxStacks :: number)
	Replication.Replicate({
		Self = self,
		Humanoid = humanoid,
		Message = "update",
		EffectName = effect.Name,
		Definition = effect.Definition,
	})
end

function Utilities.RemoveFromActive(self: Types.StatusEffectInternal, humanoid: Humanoid, effectName: string)
	local activeEffects = self.ActiveEffects[humanoid]
	if not activeEffects then
		Logger.Output("warn", `({humanoid:GetFullName()}) doesn't have any active effects to remove.`)
		return
	end

	local effect = activeEffects[effectName]
	if not effect then
		Logger.Output("warn", `({humanoid:GetFullName()}) doesn't have a {effectName} to be removed.`)
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
	Logger.Output("log", `Removed {effectName} from ({humanoid:GetFullName()}).`)

	-- If there's no more effects under this humanoid, assign nil to it's key
	if next(activeEffects) == nil then
		self.ActiveEffects[humanoid] = nil
	end

	-- Run callback for the removal
	if effect.Definition.OnRemove then
		Threads.AddToActive(
			self,
			humanoid,
			effectName,
			task.spawn(function()
				local ok, err = pcall(effect.Definition.OnRemove, Utilities.CreateContext(humanoid, effect))
				if not ok then
					Logger.Output("error", `OnRemove callback for "{effectName}" errored: ({err}).`)
				end
			end)
		)
	end

	-- Threads are not cancelled here because we want them to naturally finish up
	-- They're only cancelled if they're forced to cancel like 'terminate' through Unregister

	return true
end

function Utilities.RunOnUpdate(
	self: Types.StatusEffectInternal,
	humanoid: Humanoid,
	effectName: string,
	effect: Types.EffectInstance,
	definition: Types.EffectDefinition
)
	if definition.OnUpdate then
		Threads.AddToActive(
			self,
			humanoid,
			effectName,
			task.spawn(function()
				local ok, err = pcall(definition.OnUpdate, Utilities.CreateContext(humanoid, effect))
				if not ok then
					Logger.Output("error", `OnUpdate callback for "{effectName}" errored: ({err}).`)
				end
			end)
		)
	end
end

return table.freeze(Utilities)
