local StatusEffect = {}
StatusEffect.__index = StatusEffect
StatusEffect.CurrentObject = nil

-- Creates an object of StatusEffect and returns the object.
-- This should only be ran once and referenced later in 'StatusEffect.CurrentObject'
function StatusEffect.New()
	if StatusEffect.CurrentObject then
		warn(
			"Attempted to create a StatusEffect object when one already exists. Reference 'StatusEffect.CurrentObject' instead to get the object."
		)
		return
	end

	local self = setmetatable({}, StatusEffect)

	self.RegisteredEffects = {} -- These are effects that are considered valid
	self.ConnectedEvents = {}
	self.ActiveHumanoids = {}

	return self
end

export type RegisterEffectArgs = {
	EffectName: string,
	VisualEffect: Instance,
	OnActive: () -> (),
	CanKill: boolean,
}

export type EffectContext = {
	Target: Humanoid,
	--Effect: EffectInstance,

	Stacks: number,

	Damage: (self: EffectContext, amount: number) -> (),
	Remove: (self: EffectContext) -> (),
	Refresh: (self: EffectContext) -> (),
	AddStacks: (self: EffectContext, amount: number) -> (),
}

export type EffectDefinition = {
	Duration: number?,
	Interval: number?,

	MaxStacks: number?,
	StackBehavior: "Refresh" | "Stack" | "Ignore"?,

	-- Functions that step through the effect's lifecycle
	OnApply: (() -> ())?,
	OnTick: (() -> ())?,
	OnRemove: (() -> ())?,
}

--[[
-- Register an effect to be used on a humanoid later.
-- A bool and string is returned for the success of registering and the now valid effect string.

    Arguments through RegisterEffectArgs:
    -- EffectName: The effect that will be used later. This should be unique and cannot be a duplicate of another already existing name.
    -- VisualEffect: The instance that will visualize the effect being active on a humanoid in the Workspace. Should generally be a BasePart, Attachment, or Model.
    -- OnActive: The function that should be ran when the active is activated for a humanoid. NOTE: DO NOT USE A WHILE LOOP INSIDE THIS FUNCTION, THIS FRAMEWORK HANDLES THIS.
    -- CanKill: Specifies whether the effect can damage and eventually even kill the humanoid.
]]
function StatusEffect:RegisterEffect(effectName: string, visualEffect: Instance, onActive: () -> ()): (boolean, string?)
	if self.RegisteredEffects[effectName] then
		warn(`Attempted to register "{effectName} when it's already registered.`)
		return false, nil
	end

	self.RegisteredEffects[effectName] = {
		VisualEffect = visualEffect,
		OnActive = onActive(),
	}
	return true, effectName
end

-- Apply a valid effect onto
function StatusEffect:ApplyEffect(humanoid: Humanoid, effectName: string)
	-- Create a humanoid.Died event in case they die while this effect is active
	local effectInfo = self.RegisteredEffects[effectName]
	if not effectInfo then
		warn(
			`Attempted to apply an status effect onto ({humanoid:GetFullName()}) when the effect wasn't registered yet!`
		)
		return
	end

	-- TODO: Apply effect
end
