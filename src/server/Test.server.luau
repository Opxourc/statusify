--[[
    This is a demostration ServerScript for the StatusEffect framework.
	Use this as a reference for how the server might use and register effects for the framework!
]]

-- You can delete this script if this is in production
if not game:GetService("RunService"):IsStudio() then
	script:Destroy()
end

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

-- We'll use the Burn effect example
const StatusEffectEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StatusEffect")
const SharedNames = require(ReplicatedStorage.Shared.StatusEffect.Names)
const StatusEffect = require(script.Parent.StatusEffect.StatusEffect)
const MaxNumberPerHumanoid = 5

-- Construct the object
local Manager = StatusEffect.New({
	MaxNumberPerHumanoid = MaxNumberPerHumanoid,
	RemoteEvent = StatusEffectEvent :: RemoteEvent,
})

-- Register the effect
Manager:RegisterEffect(SharedNames.Burn, {
	Duration = 10,
	Interval = 1,
	MaxStacks = 3,
	StackBehavior = "refresh",

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
task.wait(3) -- Player may or may not be fully loaded in
local FirstPlayer = Players:GetPlayers()[1]
local Humanoid = FirstPlayer.Character and FirstPlayer.Character:WaitForChild("Humanoid")
if Humanoid and Humanoid:IsA("Humanoid") then
	Manager:ApplyEffect(Humanoid, SharedNames.Burn)
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
