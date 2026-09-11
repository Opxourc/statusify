--[[
    This is a test server script for the StatusEffect framework.
    This is only for demostration purposes only but is good to read through to know how to work it!
]]

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const Players = game:GetService("Players")
const StatusEffectEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StatusEffect")

-- Create dependencies and create object
const Framework = script.Parent.StatusEffect
const StatusEffect = require(Framework.StatusEffect)
const Types = require(Framework.Types)

const EventMessages: StatusEffect.EventMessages = {
	Apply = "apply",
	Tick = "tick",
	Remove = "remove",
}
const MaxNumberPerHumanoid = 5
local Manager = StatusEffect.New({
	MaxNumberPerHumanoid = MaxNumberPerHumanoid,
	RemoteEvent = StatusEffectEvent :: RemoteEvent,
	EventMessages = EventMessages,
})

-- Add a burn effect
const EffectName = "Burn"
Manager:RegisterEffect(EffectName, {
	Duration = 10,
	Interval = 1,
	MaxStacks = 3,
	StackBehavior = Types.ED_StackBehaviors.Stack,

	-- Use the context that's given to know more about the effect
	OnApply = function(context)
		context.Target:TakeDamage(5)
	end,

	OnTick = function(context)
		context.Target:TakeDamage(5)
	end,

	-- OnRemove is not needed as we don't wanna do anything when this effect is removed.
	-- It will be set to nil instead
})

-- Effect is now registered, let's use it on our character!
task.wait(3) -- Player may or maynot be fully loaded in
local FirstPlayer = Players:GetPlayers()[1]
local Humanoid = FirstPlayer.Character and FirstPlayer.Character:WaitForChild("Humanoid")
if Humanoid and Humanoid:IsA("Humanoid") then
	Manager:ApplyEffect(Humanoid, EffectName)
end

-- By here, the humanoid will have the burn effect and start taking damage over time
-- The client will also get events so it can start replicating the effects

-- Let's stop the effect manually after a few seconds
--task.wait(3)
--Manager:ClearEffect(Humanoid, "one", EffectName)
--task.wait(5)

-- If we ever need to get the reference of the current object, we can do that as long as it was constructed and wasn't destroyed
-- Let's get a new reference but also destroy the object completely
--local NewManager = StatusEffect.GetExistingObject()
--NewManager:Destroy()
