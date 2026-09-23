const TestHelpers = require("./TestHelpers")

local object = TestHelpers.NewObject(2)
assert(object)

local humanoid = TestHelpers.NewHumanoid()
local effectName = "stacking"

object:Register({
	EffectName = effectName,
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

TestHelpers.Assert(object:GetRegistered(effectName) ~= nil, "Expected the first effect registration to succeed.")

object:Register({ EffectName = effectName, Definition = { Duration = 10 } })
TestHelpers.AssertEqual(
	object:GetRegistered(effectName).Duration,
	30,
	"Expected duplicate registration to preserve the original definition."
)

local Definition = object:GetRegistered(effectName)
TestHelpers.Assert(Definition ~= nil, "Expected the registered definition to be readable.")
TestHelpers.AssertEqual(Definition.Duration, 30, "Expected the configured duration to be preserved.")
TestHelpers.AssertEqual(Definition.Interval, 1, "Expected the default interval to be applied.")
TestHelpers.AssertEqual(Definition.MaxStacks, 2, "Expected the configured stack limit to be preserved.")

object:Apply({ Humanoid = humanoid, EffectName = "missing" })
TestHelpers.Assert(
	object:GetActive({ Humanoid = humanoid, EffectName = "missing" }) == nil,
	"Expected unregistered effects to be rejected."
)

object:Apply({ Humanoid = humanoid, EffectName = effectName })
local Active = object:GetActive({ Humanoid = humanoid, EffectName = effectName })
TestHelpers.Assert(Active ~= nil, "Expected an effect to apply.")
TestHelpers.AssertEqual(Active.Stacks, 1, "Expected the first application to create one stack.")

object:Apply({ Humanoid = humanoid, EffectName = effectName })
Active = object:GetActive({ Humanoid = humanoid, EffectName = effectName })
TestHelpers.Assert(Active ~= nil, "Expected a second application to stack.")
TestHelpers.AssertEqual(Active.Stacks, 2, "Expected the second application to reach the stack cap.")

object:Apply({ Humanoid = humanoid, EffectName = effectName })
Active = object:GetActive({ Humanoid = humanoid, EffectName = effectName })
TestHelpers.Assert(Active ~= nil, "Expected effect applications at the cap to remain active.")
TestHelpers.AssertEqual(Active.Stacks, 2, "Expected applications at the stack cap to stay capped.")

object:Remove({ Humanoid = humanoid, EffectName = effectName, Action = "decrement" })
Active = object:GetActive({ Humanoid = humanoid, EffectName = effectName })
TestHelpers.Assert(Active ~= nil, "Expected decrement to leave the effect active while stacks remain.")
TestHelpers.AssertEqual(Active.Stacks, 1, "Expected decrement to remove one stack.")

object:Remove({ Humanoid = humanoid, EffectName = effectName, Action = "decrement" })
TestHelpers.Assert(
	object:GetActive({ Humanoid = humanoid, EffectName = effectName }) == nil,
	"Expected the final decrement to remove the effect."
)

object:Remove({ Humanoid = humanoid, Action = "effect" })
object:Remove({ Humanoid = humanoid, Action = "all" })

local FirstName = "first"
local SecondName = "second"
local ThirdName = "third"

object:Register({ EffectName = FirstName, Definition = { Duration = 30 } })
object:Register({ EffectName = SecondName, Definition = { Duration = 30 } })
object:Register({ EffectName = ThirdName, Definition = { Duration = 30 } })

TestHelpers.Assert(object:GetRegistered(FirstName) ~= nil, "Expected the first capacity test effect to register.")
TestHelpers.Assert(object:GetRegistered(SecondName) ~= nil, "Expected the second capacity test effect to register.")
TestHelpers.Assert(object:GetRegistered(ThirdName) ~= nil, "Expected the third capacity test effect to register.")

object:Apply({ Humanoid = humanoid, EffectName = FirstName })
object:Apply({ Humanoid = humanoid, EffectName = SecondName })
object:Apply({ Humanoid = humanoid, EffectName = ThirdName })

TestHelpers.AssertEqual(
	object:GetActiveCount(humanoid),
	2,
	"Expected the per-humanoid limit to prevent a third active effect."
)

object:Unregister({ EffectName = FirstName, Terminate = true })
TestHelpers.Assert(
	object:GetActive({ Humanoid = humanoid, EffectName = FirstName }) == nil,
	"Expected terminating unregister to remove active effects."
)
TestHelpers.Assert(object:GetRegistered(FirstName) == nil, "Expected the effect to be unregistered.")

object:Remove({ Humanoid = humanoid, Action = "all" })
TestHelpers.AssertEqual(object:GetActiveCount(humanoid), 0, "Expected all to clear the remaining active effects.")
