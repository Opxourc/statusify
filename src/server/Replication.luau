--!strict

local Utilities = require("./Utilities")
const Logger = require("./Logger")
const Types = require("./Types")

local Replication = {}

--[[
	Sends a replication event to the client with a message and packet of information so the client can do any form of replication.
	
	@param Definition The definition or template of an status effect.
	@param Message The event string that the client will see to know what part of the lifecycle the event is at.
	@param Self The object that will be referenced from.
	@param Humanoid The humanoid that this effect is targetted towards.
	@param EffectName The name of the effect.
]]
function Replication.Replicate(args: {
	Definition: Types.EffectDefinition,
	Message: Types.EventMessage,
	Self: Types.StatusifyInternal,
	Humanoid: Humanoid,
	EffectName: string,
})
	-- If there's no ReplicationEvent, then replication is not gonna be used
	local self = args.Self
	if not self.ReplicationEvent then
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

	-- Replication is determined by the definition of the effect
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

	-- Only give enough information to allow the client to build whatever representation they want
	self.ReplicationEvent:FireAllClients({
		EffectName = effectName,
		Message = message,
		Target = humanoid,
		Stacks = effect.Stacks,
		StartTime = effect.StartTime,
		ExpireTime = effect.ExpireTime,
	})
	Logger.Output("log", `Sent ({effectName}) ({message}) replication event for ({humanoid:GetFullName()}).`)
end

return Replication
