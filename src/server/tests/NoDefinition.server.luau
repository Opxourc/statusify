const RemoteEvent = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("StatusEffect")
const Manager = require("../StatusEffect/StatusEffect").New({
	MaxNumberPerHumanoid = 3,
	RemoteEvent = RemoteEvent,
})

-- What if there's no callbacks or explicit definition?
const EffectName = "noDefinition"
Manager:RegisterEffect(EffectName, {})

task.wait(3)
local FirstPlayer = game:GetService("Players"):GetPlayers()[1]
local Humanoid = FirstPlayer.character and FirstPlayer.character:WaitForChild("Humanoid")
Manager:ApplyEffect(Humanoid, EffectName)
