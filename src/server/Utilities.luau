const Logger = require("./Logger")
const Types = require("./Types")

local Utilities = {}

function Utilities.AnnotateSelf(a: any)
	return a :: Types.StatusifyInternal
end

function Utilities.CreateContext(humanoid: Humanoid, effect: Types.EffectInstance): Types.EffectContext
	return {
		Target = humanoid,
		Stacks = effect.Stacks,
		EffectName = effect.Name,
		StartTime = effect.StartTime,
		ExpireTime = effect.ExpireTime,
	}
end

function Utilities.NormalizeEffectName(effectName: string): string
	return string.lower(effectName)
end

function Utilities.GetActiveCount(self: Types.StatusifyInternal, humanoid: Humanoid)
	local activeEffects = Utilities.GetActiveEffects({
		Self = self,
		Humanoid = humanoid,
		Source = "Getting active effects count",
	})

	local count = 0
	for _ in activeEffects do
		count += 1
	end

	return count
end

function Utilities.GetActiveEffects(args: {
	Self: Types.StatusifyInternal,
	Humanoid: Humanoid,
	EffectName: string?,
	Source: string,
}): ({ [string]: Types.EffectInstance }?, Types.EffectInstance?)
	local self = args.Self
	local source = args.Source
	local humanoid = args.Humanoid
	local effectName = args.EffectName

	local activeEffects = self.ActiveEffects[humanoid]
	if not activeEffects then
		Logger.Output("warn", `({humanoid:GetFullName()}) doesn't have any active effects. (For: {source}).`)
		return nil
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
			return activeEffects
		end
	end

	return activeEffects, effect
end

return table.freeze(Utilities)
