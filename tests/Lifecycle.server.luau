const TestHelpers = require("./TestHelpers")

local TickCount = 0
local ApplyStacks = 0
local RemoveStacks = 0

local Object = TestHelpers.NewObject(2)
local Humanoid = TestHelpers.NewHumanoid()
local EffectName = "lifecycle"

TestHelpers.Assert(Object ~= nil, "Expected the lifecycle manager to be created.")

Object:Register({
	EffectName = EffectName,
	Definition = {
		Duration = 2,
		Interval = 0.5,
		Replicate = {
			Apply = true,
			Tick = true,
			Remove = true,
		},
		OnApply = function(context)
			ApplyStacks = context.Stacks
		end,
		OnTick = function(context)
			TickCount += context.Stacks
		end,
		OnRemove = function(context)
			RemoveStacks = context.Stacks
		end,
	},
})

TestHelpers.Assert(Object:GetRegistered(EffectName) ~= nil, "Expected lifecycle effect registration to succeed.")

Object:Apply({ Humanoid = Humanoid, EffectName = EffectName })
local active = Object:GetActive({ Humanoid = Humanoid, EffectName = EffectName })
TestHelpers.Assert(active ~= nil, "Expected lifecycle effect to apply.")
TestHelpers.AssertEqual(ApplyStacks, 1, "Expected OnApply to receive the initial stack count.")

task.wait(2)
TestHelpers.Assert(TickCount > 0, "Expected the runtime to invoke OnTick.")

task.wait(3)
TestHelpers.Assert(
	Object:GetActive({ Humanoid = Humanoid, EffectName = EffectName }) == nil,
	"Expected the effect to expire."
)
TestHelpers.AssertEqual(RemoveStacks, 1, "Expected OnRemove to receive the final stack count.")

Object:Unregister({ EffectName = EffectName, Terminate = false })
TestHelpers.Assert(Object:GetRegistered(EffectName) == nil, "Expected lifecycle effect unregister to succeed.")

Object:Apply({ Humanoid = Humanoid, EffectName = EffectName })
TestHelpers.Assert(
	Object:GetActive({ Humanoid = Humanoid, EffectName = EffectName }) == nil,
	"Expected an unregistered effect to stay unavailable."
)

print(`Total numbers: Tick count: {TickCount}, Apply Stacks: {ApplyStacks}, Remove Stacks {RemoveStacks}.`)
