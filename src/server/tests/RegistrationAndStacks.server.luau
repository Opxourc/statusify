local Helpers = require(script.Parent.TestHelpers)

local Manager = Helpers.NewManager(2)
local Humanoid = Helpers.NewHumanoid()

local Registered = Manager:RegisterEffect("stacking", {
	Duration = 30,
	MaxStacks = 2,
	StackBehavior = "stack",
	Replicate = {
		Apply = false,
		Tick = false,
		Remove = false,
	},
})
Helpers.Assert(Registered, "Expected the first effect registration to succeed")
Helpers.AssertEqual(Manager:RegisterEffect("stacking", {}), false, "Expected duplicate registration to fail")

local Definition = Manager:GetRegisteredEffect("stacking")
Helpers.Assert(Definition ~= nil, "Expected the registered definition to be readable")
Helpers.AssertEqual(Definition.Duration, 30, "Expected the configured duration to be preserved")
Helpers.AssertEqual(Definition.Interval, 1, "Expected the default interval to be applied")
Helpers.AssertEqual(Definition.MaxStacks, 2, "Expected the configured stack limit to be preserved")

Helpers.AssertEqual(Manager:ApplyEffect(Humanoid, "missing"), false, "Expected unregistered effects to be rejected")
Helpers.AssertEqual(Manager:ApplyEffect(Humanoid, "stacking"), true, "Expected an effect to apply")
Helpers.AssertEqual(Manager:ApplyEffect(Humanoid, "stacking"), true, "Expected a second application to stack")
Helpers.AssertEqual(
	Manager:ApplyEffect(Humanoid, "stacking"),
	true,
	"Expected applications at the stack cap to succeed"
)

local Active = Manager:GetActiveEffect(Humanoid, "stacking")
Helpers.Assert(Active ~= nil, "Expected the effect to be active")
Helpers.AssertEqual(Active.Stacks, 2, "Expected stacks to stop at MaxStacks")
Helpers.Assert(Manager:HasEffect(Humanoid, "stacking"), "Expected HasEffect to report the active effect")

Helpers.AssertEqual(Manager:ClearEffect(Humanoid, "decrement", "stacking"), true, "Expected decrement to succeed")
Helpers.AssertEqual(Manager:GetActiveEffect(Humanoid, "stacking").Stacks, 1, "Expected decrement to remove one stack")
Helpers.AssertEqual(
	Manager:ClearEffect(Humanoid, "decrement", "stacking"),
	true,
	"Expected the final decrement to succeed"
)
Helpers.Assert(not Manager:HasEffect(Humanoid, "stacking"), "Expected zero stacks to remove the effect")

Helpers.AssertEqual(Manager:ClearEffect(Humanoid, "remove"), false, "Expected remove without a name to fail")
Helpers.AssertEqual(
	Manager:ClearEffect(Humanoid, "removeAll"),
	false,
	"Expected removeAll on an empty humanoid to fail"
)

local First = Manager:RegisterEffect("first", { Duration = 30 })
local Second = Manager:RegisterEffect("second", { Duration = 30 })
local Third = Manager:RegisterEffect("third", { Duration = 30 })
Helpers.Assert(First and Second and Third, "Expected capacity test effects to register")
Helpers.Assert(Manager:ApplyEffect(Humanoid, "first"), "Expected the first effect to apply")
Helpers.Assert(Manager:ApplyEffect(Humanoid, "second"), "Expected the second effect to apply")
Helpers.AssertEqual(
	Manager:ApplyEffect(Humanoid, "third"),
	false,
	"Expected the per-humanoid limit to reject a third effect"
)

Helpers.AssertEqual(Manager:UnregisterEffect("first", true), true, "Expected unregister to succeed")
task.wait()
Helpers.Assert(not Manager:HasEffect(Humanoid, "first"), "Expected terminating unregister to remove active effects")
Helpers.AssertEqual(Manager:UnregisterEffect("first", false), false, "Expected repeated unregister to fail")

Helpers.AssertEqual(Manager:ClearEffect(Humanoid, "removeAll"), true, "Expected removeAll to clear remaining effects")
Helpers.WaitForCleanup(Manager, Humanoid)
