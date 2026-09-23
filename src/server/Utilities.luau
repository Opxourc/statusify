--!strict

const Types = require("./Types")
local Utilities = {}

--[[
	Creates a context that callbacks can use.

	@param humanoid The humanoid who will be the target of this context.
	@param effect The effect instance that the context information will grab from.

	@return Types.EffectContext of created context.
]]
function Utilities.CreateContext(humanoid: Humanoid, effect: Types.EffectInstance): Types.EffectContext
	return {
		Target = humanoid,
		Stacks = effect.Stacks,
		EffectName = effect.Name,
		StartTime = effect.StartTime,
		ExpireTime = effect.ExpireTime,
	}
end

--[[
	Normalizes the effect names to lowercase so they're case-insensitive.

	@param effectName The effect name string to normalize.
	@return string of the normalized name.
]]
function Utilities.NormalizeEffectName(effectName: string): string
	return string.lower(effectName)
end

--[[
	Returns the count of active effects for a given humanoid.

	@param self The object that will be referenced from.
	@param humanoid The humanoid to check the count of.

	@return number that represents the count.
]]
function Utilities.GetActiveCount(self: Types.Statusify, humanoid: Humanoid): number
	local activeEffects = Utilities.GetActiveEffects({
		Self = self,
		Humanoid = humanoid,
		Source = "Getting active effects count",
	})

	local count = 0
	if activeEffects then
		for _ in activeEffects do
			count += 1
		end
	end

	return count
end

--[[
	Returns active effect(s) depending on provided arguements.

	@param Self The object that will be referenced from.
	@param Humanoid The humanoid to get effects from.
	@param EffectName The effect to grab effects from. This is optional.
	@param Source What script/function within the framework is calling. This is only for informational purposes.

	@return Tuple of ActiveEffects (for all under humanoid) and Effects (for effect name)).
]]
function Utilities.GetActiveEffects(args: {
	Self: Types.Statusify,
	Humanoid: Humanoid,
	EffectName: string?,
}): ({ [string]: Types.EffectInstance? }?, Types.EffectInstance?)
	local self = args.Self
	local humanoid = args.Humanoid
	local effectName = args.EffectName

	local activeEffects = self._activeEffects[humanoid]
	if not activeEffects then
		return nil, nil
	end

	local effect = nil
	if effectName then
		effect = activeEffects[effectName]
	end

	return activeEffects, effect
end

--[[
	Returns active thread(s) depending on provided arguements.

	@param Self The object that will be referenced from.
	@param Humanoid The humanoid to get threads from.
	@param EffectName The effect to grab threads from. This is optional.
	@param Thread The specific thread to look for that's under a effect. This is optional.
	@param Source What script/function within the framework is calling. This is only for informational purposes.

	@return Tuple of ActiveThreads (for all under humanoid), Threads (for effect name), and boolean (for if the specific thread exists).
]]
function Utilities.GetActiveThreads(args: {
	Self: Types.Statusify,
	Humanoid: Humanoid,
	EffectName: string?,
	Thread: thread?,
}): ({ [string]: { [thread]: boolean? }? }?, { [thread]: boolean? }?, boolean?)
	local self = args.Self
	local thread = args.Thread
	local humanoid = args.Humanoid
	local effectName = args.EffectName

	local activeThreads = self._activeThreads[humanoid]
	if not activeThreads then
		return nil, nil, nil
	end

	local threads = nil
	local found = nil

	if effectName then
		threads = activeThreads[effectName]

		if thread and threads then
			found = threads[thread]
		end
	end

	return activeThreads, threads, found
end

--[[
	Returns a nil value for if the provided table has no entries.

	@param checkTab The table that will be checked.
	@return table or nil depending on the conditions result.
]]
function Utilities.NilOnEmpty<T, E>(tab: { [T]: E }): { [T]: E }?
	if next(tab) == nil then
		return nil
	end

	return tab
end

return table.freeze(Utilities)
