-- This is a demostration ServerScript for the Statusify framework.
-- Use this as a reference for how the server might use and register effects for the framework!

-- You can delete this script if this is in production
if not game:GetService("RunService"):IsStudio() then
	script:Destroy()
end

const RemoteEvent = game:GetService("ReplicatedStorage")
	:WaitForChild("Remotes")
	:WaitForChild("Statusify")
	:WaitForChild("DemoReplication")
const SharedNames = require("@game/ReplicatedStorage/Shared/Statusify/Names")
const Statusify = require("./Source/Api")
const MaxNumberPerHumanoid = 5 -- Max number of effects per humanoid will be 5

-- Construct the object
local Object = Statusify.New({
	MaxNumberPerHumanoid = MaxNumberPerHumanoid,
	RemoteEvent = RemoteEvent,
})

-- Register the desired effect and provide a definition
const BaseDamage = 5
Object:RegisterEffect(SharedNames.Burn, {
	Duration = 10,
	Interval = 1,
	MaxStacks = 3,
	StackBehavior = "refresh",

	-- Use the context that's given to know more about the effect
	OnApply = function(context)
		context.Target:TakeDamage(BaseDamage)
	end,

	OnTick = function(context)
		context.Target:TakeDamage(BaseDamage * context.Stacks) -- Here we multiply the damage based on number of stacks
	end,

	-- OnRemove is not needed as we don't wanna do anything when this effect is removed.
	-- OnUpdate is not needed because we don't want to do anything if reapplication happens or stack count changes

	-- Even though those callbacks are voided, we can use the Replicate key to determine whether we want to still replicate effects to the client
	Replicate = {
		Apply = true,
		Tick = false,

		-- Even though OnRemove and OnUpdate are nil, we still will replicate to the client for them
		Remove = true,
		Update = true,
	},
})

-- Effect is now registered, let's use it on our character!
task.wait(3) -- Player may or may not be fully loaded in

local FirstPlayer = game:GetService("Players"):GetPlayers()[1]
local Humanoid = FirstPlayer.Character and FirstPlayer.Character:WaitForChild("Humanoid")
if Humanoid and Humanoid:IsA("Humanoid") then
	Object:ApplyEffect(Humanoid, SharedNames.Burn) -- One stack
	task.wait(5)
	Object:ApplyEffect(Humanoid, SharedNames.Burn) -- Two stacks

	-- Because Burn is already applied, on the second application an 'update' replication/callback will be used instead
end

-- That's the end of the server-side demo!
-- You can expand on this drastically to create very complex systems that leverage Statusify!
-- Hope you enjoy :)
