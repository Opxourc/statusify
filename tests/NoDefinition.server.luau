const StatusEffect = require("../StatusEffect/StatusEffect")
while StatusEffect.GetExistingObject() do
	task.wait()
end

const RemoteEvent = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("StatusEffect")
const Manager = StatusEffect.New({
	MaxNumberPerHumanoid = 3,
	RemoteEvent = RemoteEvent,
})

-- What if there's no callbacks or explicit definition?
const EffectName = "noDefinition"
Manager:RegisterEffect(EffectName, {})

task.wait(3)
local Humanoid = Instance.new("Humanoid")
assert(Manager:ApplyEffect(Humanoid, EffectName), "Expected an empty effect definition to apply")
assert(Manager:HasEffect(Humanoid, EffectName), "Expected the empty effect definition to become active")
assert(Manager:GetRegisteredEffect(EffectName).Duration == 5, "Expected default duration to be applied")

Manager:Destroy()
Humanoid:Destroy()
