local Helpers = require(script.Parent.TestHelpers)

local TickCount = 0
local ApplyStacks = 0
local RemoveStacks = 0
local ReplicationMessages = {}
local RemoteEvent = {
	FireAllClients = function(_, packet)
		table.insert(ReplicationMessages, packet)
	end,
}

local StatusEffect = require(script.Parent.Parent.StatusEffect.StatusEffect)
while StatusEffect.GetExistingObject() do
	task.wait()
end
local Manager = StatusEffect.New({
	MaxNumberPerHumanoid = 3,
	RemoteEvent = RemoteEvent :: RemoteEvent,
})
Helpers.Assert(Manager ~= nil, "Expected the lifecycle manager to be created")

local Humanoid = Helpers.NewHumanoid()
Helpers.Assert(
	Manager:RegisterEffect("lifecycle", {
		Duration = 0.15,
		Interval = 0.05,
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
	}),
	"Expected lifecycle effect registration to succeed"
)

Helpers.Assert(Manager:ApplyEffect(Humanoid, "lifecycle"), "Expected lifecycle effect to apply")
Helpers.AssertEqual(ApplyStacks, 1, "Expected OnApply to receive the initial stack count")
Helpers.AssertEqual(#ReplicationMessages, 1, "Expected apply to replicate once")
Helpers.AssertEqual(ReplicationMessages[1].Message, "apply", "Expected the first replication message to be apply")

task.wait(0.08)
Helpers.Assert(TickCount > 0, "Expected the runtime to invoke OnTick")
Helpers.AssertEqual(ReplicationMessages[2].Message, "tick", "Expected a tick replication message")

task.wait(0.15)
Helpers.Assert(not Manager:HasEffect(Humanoid, "lifecycle"), "Expected the effect to expire")
Helpers.AssertEqual(RemoveStacks, 1, "Expected OnRemove to receive the final stack count")
Helpers.AssertEqual(
	ReplicationMessages[#ReplicationMessages].Message,
	"remove",
	"Expected expiration to replicate removal"
)

Helpers.AssertEqual(
	Manager:UnregisterEffect("lifecycle", false),
	true,
	"Expected lifecycle effect unregister to succeed"
)
Helpers.AssertEqual(
	Manager:ApplyEffect(Humanoid, "lifecycle"),
	false,
	"Expected an unregistered effect to stay unavailable"
)
Helpers.WaitForCleanup(Manager, Humanoid)
