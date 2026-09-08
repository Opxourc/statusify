local RunService = game:GetService("RunService")

local StatusEffect = {}
StatusEffect.__index = StatusEffect

StatusEffect.CurrentObject = nil
StatusEffect.PresistentEffectAttribute = "PresistentEffect" -- For presistent like client replication of effects (Recommended for .Rate and .Enabled = true)
StatusEffect.BurstEffectAttribute = "BurstEffect" -- For burst like client replication of effects (Recommended for :Emit() and .Enabled = false)
StatusEffect.Debugging = RunService:IsStudio()

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

	self.RegisteredEffects = {} :: { [string]: EffectDefinition } -- These are effects that are considered valid
	self.ActiveEffects = {} :: { [Humanoid]: { [string]: EffectInstance } } -- Effects that are currently running on a humanoid

	-- Connection that runs the lifecycle of currently running effects
	RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()

		for humanoid, activeEffects in self.ActiveEffects do
			for effectName, effect in activeEffects do
				if now >= effect.ExpireTime then
					activeEffects[effectName] = nil

					if effect.Definition.OnRemove then
						effect.Definition.OnRemove(self:_createContext(humanoid, effect))
					end
				elseif effect.Definition.Interval and effect.Definition.Interval > 0 and now >= effect.NextTickTime then
					effect.NextTickTime = now + effect.Definition.Interval

					if effect.Definition.OnTick then
						effect.Definition.OnTick(self:_createContext(humanoid, effect))
					end
				end
			end
		end
	end)

	return self
end

-- The information that effect callbacks need, in order to know what to do.
export type EffectContext = {
	Target: Humanoid,
	Effect: EffectInstance,

	Stacks: number,

	Damage: (self: EffectContext, amount: number) -> (),
	Remove: (self: EffectContext) -> (),
	Refresh: (self: EffectContext) -> (),
	AddStacks: (self: EffectContext, amount: number) -> (),
}

-- The contract for a live effect that is running
export type EffectInstance = {
	Definition: EffectDefinition,
	Name: string,
	Stacks: number,
	StartTime: number,
	ExpireTime: number,
	NextTickTime: number,
}

-- Describes the template for an effect
export type EffectDefinition = {
	Duration: number?, -- How long 'one' stack should last naturally without any interuptions
	Interval: number?, -- How fast ticks should be applied during the duration

	MaxStacks: number?,
	StackBehavior: "refresh" | "stack" | "ignore"?,
	-- refresh - Reset duration
	-- stack - Increase the number of stacks by 1 unless capped
	-- ignore - Do nothing

	-- Functions that step through the effect's lifecycle
	OnApply: ((context: EffectContext) -> ())?, -- The moment an effect goes live
	OnTick: ((context: EffectContext) -> ())?, -- When a interval strikes
	OnRemove: ((context: EffectContext) -> ())?, -- The moment an effect is cleared
}

const EFFECT_DEFINITION_DEFAULTS = {
	Duration = 5,
	Interval = 1,
	MaxStacks = math.huge,
	StackBehavior = "refresh",
}
table.freeze(EFFECT_DEFINITION_DEFAULTS)

--[[
	Outputs a message while in Debugging mode.
]]
local function outputMessage(status: "warn" | "log", message: string)
	if not StatusEffect.Debugging then
		return
	end

	if status == "warn" then
		warn(message)
	elseif status == "log" then
		print(message)
	end
end

--[[
	Checks if a incoming definition is correct.
	If there's any issues, those issues are gracefully handled with default values.
]]
local function validateDefinition(effectName: string, definition: EffectDefinition): EffectDefinition
	local normalizedDefinition = definition
	if type(normalizedDefinition) ~= "table" then
		normalizedDefinition = {} :: EffectDefinition
	end

	local function useDefault(propertyName: string)
		local defaultValue = EFFECT_DEFINITION_DEFAULTS[propertyName]
		normalizedDefinition[propertyName] = defaultValue

		outputMessage(
			"warn",
			`Effect "{effectName}" had an invalid {propertyName}; using the default value ({defaultValue}).`
		)
	end

	if type(normalizedDefinition.Duration) ~= "number" or normalizedDefinition.Duration <= 0 then
		useDefault("Duration")
	elseif
		normalizedDefinition.Duration ~= normalizedDefinition.Duration or normalizedDefinition.Duration == math.huge
	then
		useDefault("Duration")
	end

	if type(normalizedDefinition.Interval) ~= "number" or normalizedDefinition.Interval < 0 then
		useDefault("Interval")
	elseif
		normalizedDefinition.Interval ~= normalizedDefinition.Interval or normalizedDefinition.Interval == math.huge
	then
		useDefault("Interval")
	end

	if type(normalizedDefinition.MaxStacks) ~= "number" or normalizedDefinition.MaxStacks < 1 then
		useDefault("MaxStacks")
	elseif
		normalizedDefinition.MaxStacks ~= math.huge
		and (
			normalizedDefinition.MaxStacks ~= normalizedDefinition.MaxStacks
			or normalizedDefinition.MaxStacks % 1 ~= 0
		)
	then
		useDefault("MaxStacks")
	end

	if
		normalizedDefinition.StackBehavior ~= "refresh"
		and normalizedDefinition.StackBehavior ~= "stack"
		and normalizedDefinition.StackBehavior ~= "ignore"
	then
		useDefault("StackBehavior")
	end

	for _, callbackName in { "OnApply", "OnTick", "OnRemove" } do
		local callback = normalizedDefinition[callbackName]
		if callback ~= nil and type(callback) ~= "function" then
			if StatusEffect.Debugging then
				warn(`Effect "{effectName}" had an invalid {callbackName}; removing it.`)
			end
			normalizedDefinition[callbackName] = nil
		end
	end

	return normalizedDefinition
end

--[[
	Register an effect status to be used for the game.

	Return:
		boolean - The success of the registerion. True if successful, false otherwise.

	Arguements:
		effectName - The name you want to give for this effect and reference to.
		defintiion - The essential data and information to know exactly what this effect should do.
			Please read the EffectDefintiion type to know exactly what this parameter expects!

	NOTE: Properties will be defaulted to a value if they're not defined.
]]
function StatusEffect:RegisterEffect(effectName: string, definition: EffectDefinition): boolean
	if self.RegisteredEffects[effectName] then
		warn(`Attempted to register "{effectName}" when it's already registered.`)
		return false
	end

	definition = validateDefinition(effectName, definition)
	self.RegisteredEffects[effectName] = definition

	return true
end

--[[
	Create the context for an effect.
]]
function StatusEffect:_createContext(humanoid: Humanoid, effect: EffectInstance): EffectContext
	return {
		Target = humanoid,
		Effect = effect,
		Stacks = effect.Stacks,
		Damage = function(_, amount: number)
			humanoid:TakeDamage(amount)
		end,
		Remove = function()
			local activeEffects = self.ActiveEffects[humanoid]
			if activeEffects and activeEffects[effect.Name] == effect then
				activeEffects[effect.Name] = nil
				if effect.Definition.OnRemove then
					effect.Definition.OnRemove(self:_createContext(humanoid, effect))
				end
			end
		end,
		Refresh = function()
			effect.ExpireTime = workspace:GetServerTimeNow() + (effect.Definition.Duration :: number)
		end,
		AddStacks = function(_, amount: number)
			effect.Stacks = math.min(effect.Stacks + amount, effect.Definition.MaxStacks :: number)
		end,
	}
end

--[[
	Apply an effect status onto a humanoid.

	Return:
		boolean - The success of the application. True if successful, false otherwise.

	Arguements:
		humanoid - The humanoid instance to apply the effect onto.
		effectName - The effect that will be applied to the humanoid. 
			This name should be registered first before using this method!
]]
function StatusEffect:ApplyEffect(humanoid: Humanoid, effectName: string): boolean
	local definition = self.RegisteredEffects[effectName]
	if not definition then
		outputMessage("warn", `Attempted to apply unregistered effect "{effectName}" onto ({humanoid:GetFullName()})`)
		return false
	end

	local now = workspace:GetServerTimeNow()
	local activeEffects = self.ActiveEffects[humanoid]
	if not activeEffects then
		activeEffects = {}
		self.ActiveEffects[humanoid] = activeEffects
	end

	local existingEffect = activeEffects[effectName]
	if existingEffect then
		if definition.StackBehavior == "ignore" then
			return true
		end

		if definition.StackBehavior == "stack" and existingEffect.Stacks < (definition.MaxStacks :: number) then
			existingEffect.Stacks += 1
		end

		existingEffect.ExpireTime = now + (definition.Duration :: number)
		return true
	end

	local effect: EffectInstance = {
		Name = effectName,
		Definition = definition,
		StartTime = now,
		Stacks = 1,
		ExpireTime = now + (definition.Duration :: number),
		NextTickTime = now + (definition.Interval :: number),
	}

	activeEffects[effectName] = effect
	if definition.OnApply then
		definition.OnApply(self:_createContext(humanoid, effect))
	end

	return true
end

return table.freeze(StatusEffect)
