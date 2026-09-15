const TestHelpers = require("./TestHelpers")

local Object = TestHelpers.NewObject(2)
local Humanoid = TestHelpers.NewHumanoid()
local EffectName = "stacking"
local Registered = Object:RegisterEffect(EffectName, {
	Duration = 30,
	MaxStacks = 2,
	StackBehavior = "stack",
	Replicate = {
		Apply = false,
		Tick = false,
		Remove = false,
		Update = false,
	},
})

TestHelpers.Assert(Registered, "Expected the first effect registration to succeed.")
TestHelpers.AssertEqual(Object:RegisterEffect(EffectName, {}), false, "Expected duplicate registration to fail.")

local Definition = Object:GetRegisteredEffect(EffectName)
TestHelpers.Assert(Definition ~= nil, "Expected the registered definition to be readable.")
TestHelpers.AssertEqual(Definition.Duration, 30, "Expected the configured duration to be preserved.")
TestHelpers.AssertEqual(Definition.Interval, 1, "Expected the default interval to be applied.")
TestHelpers.AssertEqual(Definition.MaxStacks, 2, "Expected the configured stack limit to be preserved.")

TestHelpers.AssertEqual(Object:ApplyEffect(Humanoid, "missing"), false, "Expected unregistered effects to be rejected.")
TestHelpers.AssertEqual(Object:ApplyEffect(Humanoid, EffectName), true, "Expected an effect to apply.") -- Stack -> 1
TestHelpers.AssertEqual(Object:ApplyEffect(Humanoid, EffectName), true, "Expected a second application to stack.") -- Stack -> 2 (max)
TestHelpers.AssertEqual(
	Object:ApplyEffect(Humanoid, EffectName), -- Stack x-> 3
	true,
	"Expected applications at the stack cap to succeed."
)

local Active = Object:GetActiveEffect(Humanoid, EffectName)
TestHelpers.Assert(Active ~= nil, "Expected the effect to be active.")
TestHelpers.AssertEqual(Active.Stacks, 2, "Expected stacks to stop at MaxStacks.")
TestHelpers.Assert(Object:HasEffect(Humanoid, "stacking"), "Expected HasEffect to report the active effect.")

TestHelpers.AssertEqual(Object:ClearEffect(Humanoid, "decrement", EffectName), true, "Expected decrement to succeed.") -- Stack -> 1
TestHelpers.AssertEqual(
	Object:GetActiveEffect(Humanoid, EffectName).Stacks,
	1,
	"Expected decrement to remove one stack."
)
TestHelpers.AssertEqual(
	Object:ClearEffect(Humanoid, "decrement", EffectName), -- stack -> 0 (remove)
	true,
	"Expected the final decrement to succeed."
)
TestHelpers.Assert(not Object:HasEffect(Humanoid, EffectName), "Expected zero stacks to remove the effect.")

TestHelpers.AssertEqual(Object:ClearEffect(Humanoid, "remove"), false, "Expected remove without a name to fail.")
TestHelpers.AssertEqual(
	Object:ClearEffect(Humanoid, "removeAll"),
	false,
	"Expected removeAll on an empty humanoid to fail."
)

local FirstName = "first"
local SecondName = "second"
local ThirdName = "third"

local First = Object:RegisterEffect(FirstName, { Duration = 30 })
local Second = Object:RegisterEffect(SecondName, { Duration = 30 })
local Third = Object:RegisterEffect(ThirdName, { Duration = 30 })

TestHelpers.Assert(First and Second and Third, "Expected capacity test effects to register.")
TestHelpers.Assert(Object:ApplyEffect(Humanoid, FirstName), "Expected the first effect to apply.") -- active -> 1
TestHelpers.Assert(Object:ApplyEffect(Humanoid, SecondName), "Expected the second effect to apply.") -- active -> 2 (max)
TestHelpers.AssertEqual(
	Object:ApplyEffect(Humanoid, "third"),
	false,
	"Expected the per-humanoid limit to reject a third effect."
)

TestHelpers.AssertEqual(Object:UnregisterEffect(FirstName, true), true, "Expected unregister to succeed.")
TestHelpers.Assert(
	not Object:HasEffect(Humanoid, FirstName),
	"Expected terminating unregister to remove active effects"
)
TestHelpers.AssertEqual(Object:UnregisterEffect(FirstName, false), false, "Expected repeated unregister to fail.")

TestHelpers.AssertEqual(
	Object:ClearEffect(Humanoid, "removeAll"),
	true,
	"Expected removeAll to clear remaining effects."
)
TestHelpers.WaitForCleanup(Object, Humanoid)
