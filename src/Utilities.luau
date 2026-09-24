--!strict

const Types = require("./Types")
local Utilities = {}

--[[
	Creates a context that callbacks can use.

	@param humanoid The humanoid who will be the target of this context.
	@param effect The effect instance that the context information will grab from.

	@return Types.EffectContext of created context.
]]
function Utilities.createContext(humanoid: Humanoid, effect: Types.EffectInstance): Types.EffectContext
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
function Utilities.normalizeEffectName(effectName: string): string
	return string.lower(effectName)
end

--[[
	Returns a nil value for if the provided table has no entries.

	@param t The table that will be checked.
	@return table or nil depending on the conditions result.
]]
function Utilities.nilOnEmpty<T, E>(t: { [T]: E }): { [T]: E }?
	if next(t) == nil then
		return nil
	end

	return t
end

return table.freeze(Utilities)
