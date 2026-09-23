--!strict

if not game:GetService("RunService"):IsStudio() then
	script:Destroy()
end

const remoteEvent = game:GetService("ReplicatedStorage")
	:WaitForChild("Remotes")
	:WaitForChild("Statusify")
	:WaitForChild("DemoReplication")
const sharedNames = require("@game/ReplicatedStorage/Shared/Statusify/Names")
const Statusify = require("./Source/Api")

-- Construct the object
local object = Statusify.new({
	MaxNumberPerHumanoid = 5,
	ReplicationEvent = remoteEvent,
})

-- Register the desired effect and provide a definition
object:Register({
	EffectName = sharedNames.Burn,
	Definition = {
		Duration = 10,
		Interval = 1,
		MaxStacks = 3,
		StackBehavior = "refresh",

		-- Use the context that's given to know more about the effect
		OnApply = function(context)
			context.Target:TakeDamage(5)
		end,

		OnTick = function(context)
			context.Target:TakeDamage(5 * context.Stacks) -- Multiply the damage based on number of stacks
		end,

		-- OnRemove is not needed as we don't wanna do anything when this effect is removed.
		-- OnUpdate is not needed because we don't want to do anything if reapplication happens or stack count changes

		-- Callbacks can be nil but we can optionally continue to replicate or not without needing a callback
		Replicate = {
			Apply = true, -- Callback exists and we still want to replicate to client
			Tick = false, -- Callback exists but we're not replicating to client
			Remove = true, -- Callback doesn't exist but we still wanna replicate to client
			Update = true,
		},
	},
})

task.wait(3)

local firstPlayer = game:GetService("Players"):GetPlayers()[1]
local humanoid = firstPlayer.Character and firstPlayer.Character:WaitForChild("Humanoid")
if humanoid and humanoid:IsA("Humanoid") then
	object:Apply({
		EffectName = sharedNames.Burn,
		Humanoid = humanoid,
	}) -- One stack

	task.wait(5)

	object:Apply({
		Humanoid = humanoid,
		EffectName = sharedNames.Burn,
	}) -- Two stacks

	-- Because Burn is already applied, on the second application, an 'update' replication/callback will be used instead
end
