const TestHelpers = require("./TestHelpers")

local Object = TestHelpers.NewObject(2)
assert(Object)

local Humanoid = TestHelpers.NewHumanoid()
local EffectName = "stacking"

Object:Register({
	EffectName = EffectName,
	Definition = {
		Duration = 30,
		Interval = 1,
		MaxStacks = 2,
		StackBehavior = "stack",
		Throttle = 0,
		Replicate = {
			Apply = false,
			Tick = false,
			Remove = false,
			Update = false,
		},
	},
})

TestHelpers.Assert(Object:GetRegistered(EffectName) ~= nil, "Expected the first effect registration to succeed.")

Object:Register({ EffectName = EffectName, Definition = { Duration = 10 } })
TestHelpers.AssertEqual(
	Object:GetRegistered(EffectName).Duration,
	30,
	"Expected duplicate registration to preserve the original definition."
)

local Definition = Object:GetRegistered(EffectName)
TestHelpers.Assert(Definition ~= nil, "Expected the registered definition to be readable.")
TestHelpers.AssertEqual(Definition.Duration, 30, "Expected the configured duration to be preserved.")
TestHelpers.AssertEqual(Definition.Interval, 1, "Expected the default interval to be applied.")
TestHelpers.AssertEqual(Definition.MaxStacks, 2, "Expected the configured stack limit to be preserved.")

Object:Apply({ Humanoid = Humanoid, EffectName = "missing" })
TestHelpers.Assert(
	Object:GetActive({ Humanoid = Humanoid, EffectName = "missing" }) == nil,
	"Expected unregistered effects to be rejected."
)

Object:Apply({ Humanoid = Humanoid, EffectName = EffectName })
local Active = Object:GetActive({ Humanoid = Humanoid, EffectName = EffectName })
TestHelpers.Assert(Active ~= nil, "Expected an effect to apply.")
TestHelpers.AssertEqual(Active.Stacks, 1, "Expected the first application to create one stack.")

Object:Apply({ Humanoid = Humanoid, EffectName = EffectName })
Active = Object:GetActive({ Humanoid = Humanoid, EffectName = EffectName })
TestHelpers.Assert(Active ~= nil, "Expected a second application to stack.")
TestHelpers.AssertEqual(Active.Stacks, 2, "Expected the second application to reach the stack cap.")

Object:Apply({ Humanoid = Humanoid, EffectName = EffectName })
Active = Object:GetActive({ Humanoid = Humanoid, EffectName = EffectName })
TestHelpers.Assert(Active ~= nil, "Expected effect applications at the cap to remain active.")
TestHelpers.AssertEqual(Active.Stacks, 2, "Expected applications at the stack cap to stay capped.")

Object:Remove({ Humanoid = Humanoid, EffectName = EffectName, Action = "decrement" })
Active = Object:GetActive({ Humanoid = Humanoid, EffectName = EffectName })
TestHelpers.Assert(Active ~= nil, "Expected decrement to leave the effect active while stacks remain.")
TestHelpers.AssertEqual(Active.Stacks, 1, "Expected decrement to remove one stack.")

Object:Remove({ Humanoid = Humanoid, EffectName = EffectName, Action = "decrement" })
TestHelpers.Assert(
	Object:GetActive({ Humanoid = Humanoid, EffectName = EffectName }) == nil,
	"Expected the final decrement to remove the effect."
)

Object:Remove({ Humanoid = Humanoid, Action = "effect" })
Object:Remove({ Humanoid = Humanoid, Action = "all" })

local FirstName = "first"
local SecondName = "second"
local ThirdName = "third"

Object:Register({ EffectName = FirstName, Definition = { Duration = 30 } })
Object:Register({ EffectName = SecondName, Definition = { Duration = 30 } })
Object:Register({ EffectName = ThirdName, Definition = { Duration = 30 } })

TestHelpers.Assert(Object:GetRegistered(FirstName) ~= nil, "Expected the first capacity test effect to register.")
TestHelpers.Assert(Object:GetRegistered(SecondName) ~= nil, "Expected the second capacity test effect to register.")
TestHelpers.Assert(Object:GetRegistered(ThirdName) ~= nil, "Expected the third capacity test effect to register.")

Object:Apply({ Humanoid = Humanoid, EffectName = FirstName })
Object:Apply({ Humanoid = Humanoid, EffectName = SecondName })
Object:Apply({ Humanoid = Humanoid, EffectName = ThirdName })

TestHelpers.AssertEqual(
	Object:GetActiveCount(Humanoid),
	2,
	"Expected the per-humanoid limit to prevent a third active effect."
)

Object:Unregister({ EffectName = FirstName, Terminate = true })
TestHelpers.Assert(
	Object:GetActive({ Humanoid = Humanoid, EffectName = FirstName }) == nil,
	"Expected terminating unregister to remove active effects."
)
TestHelpers.Assert(Object:GetRegistered(FirstName) == nil, "Expected the effect to be unregistered.")

Object:Remove({ Humanoid = Humanoid, Action = "all" })
TestHelpers.AssertEqual(Object:GetActiveCount(Humanoid), 0, "Expected all to clear the remaining active effects.")
