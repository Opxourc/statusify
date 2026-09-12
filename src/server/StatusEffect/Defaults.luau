local Defaults = {}

Defaults.CD_DefaultMaxPerHumanoid = 3
Defaults.ED_Defaults = table.freeze({
	Duration = 5,
	Interval = 1,
	MaxStacks = math.huge,
	StackBehavior = "refresh",
	Replicate = {
		Apply = true,
		Tick = true,
		Remove = true,
	},
})

return table.freeze(Defaults)
