--!strict

local Utilities = require("./Utilities")
const Logger = require("./Logger")
const Types = require("./Types")

local Replication = {}

--[[
	Sends a replication event to the client with a message and packet of information so the client can do any form of replication.

	If there's no ReplicationEvent, no replication event will be sent.
	
	@param Definition The definition or template of an status effect.
	@param Message The event string that the client will see to know what part of the lifecycle the event is at.
	@param Humanoid The humanoid that this effect is targetted towards.
	@param EffectName The name of the effect.
]]
function Replication.Replicate(
	self: Types.Statusify,
	args: {
		Definition: Types.EffectDefinition,
		Message: Types.EventMessage,
		Humanoid: Humanoid,
		EffectName: string,
	}
)
	if not self._replicationEvent then
		return
	end

	local definition = args.Definition
	local effectName = args.EffectName
	local humanoid = args.Humanoid
	local message = args.Message

	local _, effect = Utilities.GetActiveEffects({
		Humanoid = humanoid,
		EffectName = effectName,
		Self = self,
		Source = "Replication.Replicate",
	})

	if not effect then
		return
	end

	local shouldReplicate = false
	if definition.Replicate then
		if message == "apply" and definition.Replicate.Apply then
			shouldReplicate = true
		elseif message == "tick" and definition.Replicate.Tick then
			shouldReplicate = true
		elseif message == "remove" and definition.Replicate.Remove then
			shouldReplicate = true
		elseif message == "update" and definition.Replicate.Update then
			shouldReplicate = true
		end
	end

	if not shouldReplicate then
		return
	end

	self._replicationEvent:FireAllClients({
		EffectName = effectName,
		Message = message,
		Target = humanoid,
		Stacks = effect.Stacks,
		StartTime = effect.StartTime,
		ExpireTime = effect.ExpireTime,
	})
	Logger.Info(`Sent ({effectName}) ({message}) replication event.`)
end

return Replication
