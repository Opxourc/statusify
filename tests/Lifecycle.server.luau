const TestHelpers = require("./TestHelpers")

local tickCount = 0
local applyStacks = 0
local removeStacks = 0

local object = TestHelpers.NewObject(2)
local humanoid = TestHelpers.NewHumanoid()
local effectName = "lifecycle"

TestHelpers.Assert(object ~= nil, "Expected the lifecycle manager to be created.")

object:Register({
	EffectName = effectName,
	Definition = {
		Duration = 2,
		Interval = 0.5,
		Replicate = {
			Apply = true,
			Tick = true,
			Remove = true,
		},
		OnApply = function(context)
			applyStacks = context.Stacks
		end,
		OnTick = function(context)
			tickCount += context.Stacks
		end,
		OnRemove = function(context)
			removeStacks = context.Stacks
		end,
	},
})

TestHelpers.Assert(object:GetRegistered(effectName) ~= nil, "Expected lifecycle effect registration to succeed.")
object:Apply({ Humanoid = humanoid, EffectName = effectName })

local active = object:GetActive({ Humanoid = humanoid, EffectName = effectName })
TestHelpers.Assert(active ~= nil, "Expected lifecycle effect to apply.")
TestHelpers.AssertEqual(applyStacks, 1, "Expected OnApply to receive the initial stack count.")

task.wait(2)
TestHelpers.Assert(tickCount > 0, "Expected the runtime to invoke OnTick.")

task.wait(3)
TestHelpers.Assert(
	object:GetActive({ Humanoid = humanoid, EffectName = effectName }) == nil,
	"Expected the effect to expire."
)
TestHelpers.AssertEqual(removeStacks, 1, "Expected OnRemove to receive the final stack count.")

object:Unregister({ EffectName = effectName, Terminate = false })
TestHelpers.Assert(object:GetRegistered(effectName) == nil, "Expected lifecycle effect unregister to succeed.")

object:Apply({ Humanoid = humanoid, EffectName = effectName })
TestHelpers.Assert(
	object:GetActive({ Humanoid = humanoid, EffectName = effectName }) == nil,
	"Expected an unregistered effect to stay unavailable."
)

print(`Total numbers: Tick count: {tickCount}, Apply Stacks: {applyStacks}, Remove Stacks {removeStacks}.`)
