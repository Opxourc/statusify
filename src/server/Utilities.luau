--!strict

const Logger = require("./Logger")
const Types = require("./Types")

local Utilities = {}

--[[
	Returns an asserted table as Types.StatusifyInternal.

	@param a A table that will be asserted. This should be 'self' or a Statusify object that's missing proper type checking.
	@return Asserted Types.StatusifyInternal.
]]
function Utilities.AnnotateSelf(a: any)
	return a :: Types.StatusifyInternal
end

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
function Utilities.GetActiveCount(self: Types.StatusifyInternal, humanoid: Humanoid): number
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
	Self: Types.StatusifyInternal,
	Humanoid: Humanoid,
	EffectName: string?,
	Source: string,
}): ({ [string]: Types.EffectInstance? }?, Types.EffectInstance?)
	local self = args.Self
	local source = args.Source
	local humanoid = args.Humanoid
	local effectName = args.EffectName

	local activeEffects = self.ActiveEffects[humanoid]
	if not activeEffects then
		Logger.Output("warn", `({humanoid:GetFullName()}) doesn't have any active effects. (For: {source}).`)
		return nil, nil
	end

	-- If any EffectName was provided, also search for that
	local effect = nil
	if effectName then
		effect = activeEffects[effectName]
		if not effect then
			Logger.Output(
				"warn",
				`({humanoid:GetFullName()}) doesn't have a active ({effectName}) effect. (For: {source}).`
			)
		end
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
	Self: Types.StatusifyInternal,
	Humanoid: Humanoid,
	EffectName: string?,
	Thread: thread?,
	Source: string,
}): ({ [string]: { [thread]: true? }? }?, { [thread]: true? }?, boolean?)
	local self = args.Self
	local source = args.Source
	local thread = args.Thread
	local humanoid = args.Humanoid
	local effectName = args.EffectName

	local activeThreads = self.ActiveThreads[humanoid]
	if not activeThreads then
		Logger.Output("warn", `({humanoid:GetFullName()}) doesn't have any active threads. (For: {source}).`)
		return nil, nil, nil
	end

	local threads = nil
	local found = nil

	-- If effect name was provided, search for that
	if effectName then
		threads = activeThreads[effectName]
		if not threads then
			Logger.Output(
				"warn",
				`({humanoid:GetFullName()}) doesn't have a active ({effectName}) effect. (For: {source}).`
			)
		end

		-- If a specific thread was provided, also search for that
		if thread and threads then
			found = threads[thread]
			if not found then
				Logger.Output(
					"warn",
					`({humanoid:GetFullName()}) doesn't have a specified thread under ({effectName}). (For: {source}).`
				)
			end
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
