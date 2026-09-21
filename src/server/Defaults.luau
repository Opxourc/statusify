local Defaults = {}

Defaults.Constructor = {
	MaxEffectsPerHumanoid = 3,
}

Defaults.EffectDefinition = {
	Duration = 5,
	Interval = 1,
	MaxStacks = math.huge,
	StackBehavior = "stack_refresh",
	Throttle = 0.25,
	Replicate = {
		Apply = true,
		Tick = true,
		Remove = true,
		Update = true,
	},
}

return table.freeze(Defaults)
