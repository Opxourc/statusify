const TestHelpers = require("./TestHelpers")

local Object = TestHelpers.NewObject(2)
local Humanoid = TestHelpers.NewHumanoid()
local EffectName = "stacking"
local Registered = Object:RegisterEffect({
	EffectName = EffectName,
	Definition = {
		Duration = 30,
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

TestHelpers.Assert(Registered, "Expected the first effect registration to succeed.")
TestHelpers.AssertEqual(
	Object:RegisterEffect({ EffectName = EffectName, Definition = {} }),
	false,
	"Expected duplicate registration to fail."
)

local Definition = Object:GetRegisteredEffect(EffectName)
TestHelpers.Assert(Definition ~= nil, "Expected the registered definition to be readable.")
TestHelpers.AssertEqual(Definition.Duration, 30, "Expected the configured duration to be preserved.")
TestHelpers.AssertEqual(Definition.Interval, 1, "Expected the default interval to be applied.")
TestHelpers.AssertEqual(Definition.MaxStacks, 2, "Expected the configured stack limit to be preserved.")

TestHelpers.AssertEqual(
	Object:ApplyEffect({ Humanoid = Humanoid, EffectName = "missing" }),
	false,
	"Expected unregistered effects to be rejected."
)
TestHelpers.AssertEqual(
	Object:ApplyEffect({ Humanoid = Humanoid, EffectName = EffectName }),
	true,
	"Expected an effect to apply."
) -- Stack -> 1
TestHelpers.AssertEqual(
	Object:ApplyEffect({ Humanoid = Humanoid, EffectName = EffectName }),
	true,
	"Expected a second application to stack."
) -- Stack -> 2 (max)
TestHelpers.AssertEqual(
	Object:ApplyEffect({ Humanoid = Humanoid, EffectName = EffectName }), -- Stack x-> 3
	true,
	"Expected applications at the stack cap to succeed."
)

local Active = Object:GetActiveEffect({ Humanoid = Humanoid, EffectName = EffectName })
TestHelpers.Assert(Active ~= nil, "Expected the effect to be active.")
TestHelpers.AssertEqual(Active.Stacks, 2, "Expected stacks to stop at MaxStacks.")
TestHelpers.Assert(
	Object:HasEffect({ Humanoid = Humanoid, EffectName = EffectName }),
	"Expected HasEffect to report the active effect."
)

TestHelpers.AssertEqual(
	Object:ClearEffect({ Humanoid = Humanoid, EffectName = EffectName, Action = "decrement" }),
	true,
	"Expected decrement to succeed."
) -- Stack -> 1
TestHelpers.AssertEqual(
	Object:GetActiveEffect({ Humanoid = Humanoid, EffectName = EffectName }).Stacks,
	1,
	"Expected decrement to remove one stack."
)
TestHelpers.AssertEqual(
	Object:ClearEffect({ Humanoid = Humanoid, EffectName = EffectName, Action = "decrement" }), -- stack -> 0 (remove)
	true,
	"Expected the final decrement to succeed."
)
TestHelpers.Assert(
	not Object:HasEffect({ Humanoid = Humanoid, EffectName = EffectName }),
	"Expected zero stacks to remove the effect."
)

TestHelpers.AssertEqual(
	Object:ClearEffect({ Humanoid = Humanoid, Action = "remove" }),
	false,
	"Expected remove without a name to fail."
)
TestHelpers.AssertEqual(
	Object:ClearEffect({ Humanoid = Humanoid, Action = "removeAll" }),
	false,
	"Expected removeAll on an empty humanoid to fail."
)

local FirstName = "first"
local SecondName = "second"
local ThirdName = "third"

local First = Object:RegisterEffect({ EffectName = FirstName, Definition = { Duration = 30 } })
local Second = Object:RegisterEffect({ EffectName = SecondName, Definition = { Duration = 30 } })
local Third = Object:RegisterEffect({ EffectName = ThirdName, Definition = { Duration = 30 } })

TestHelpers.Assert(First and Second and Third, "Expected capacity test effects to register.")
TestHelpers.Assert(
	Object:ApplyEffect({ Humanoid = Humanoid, EffectName = FirstName }),
	"Expected the first effect to apply."
) -- active -> 1
TestHelpers.Assert(
	Object:ApplyEffect({ Humanoid = Humanoid, EffectName = SecondName }),
	"Expected the second effect to apply."
) -- active -> 2 (max)
TestHelpers.AssertEqual(
	Object:ApplyEffect({ Humanoid = Humanoid, EffectName = ThirdName }),
	false,
	"Expected the per-humanoid limit to reject a third effect."
)

TestHelpers.AssertEqual(
	Object:UnregisterEffect({ EffectName = FirstName, Terminate = true }),
	true,
	"Expected unregister to succeed."
)
TestHelpers.Assert(
	not Object:HasEffect({ Humanoid = Humanoid, EffectName = FirstName }),
	"Expected terminating unregister to remove active effects"
)
TestHelpers.AssertEqual(
	Object:UnregisterEffect({ EffectName = FirstName, Terminate = false }),
	false,
	"Expected repeated unregister to fail."
)

TestHelpers.AssertEqual(
	Object:ClearEffect({ Humanoid = Humanoid, Action = "removeAll" }),
	true,
	"Expected removeAll to clear remaining effects."
)
TestHelpers.WaitForCleanup(Object, Humanoid)
