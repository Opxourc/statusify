const Logger = require("./Logger")
const Types = require("./Types")

local Replication = {}

function Replication.Replicate(args: {
	Definition: Types.EffectDefinition,
	Message: Types.EventMessage,
	Self: Types.StatusifyInternal,
	Humanoid: Humanoid,
	EffectName: string,
})
	local definition = args.Definition
	local effectName = args.EffectName
	local humanoid = args.Humanoid
	local message = args.Message
	local self = args.Self

	local activeEffects = self.ActiveEffects[humanoid]
	if not activeEffects then
		Logger.Output(
			"warn",
			`Attempted to send a replication event for ({humanoid:GetFullName()}) when there's no active effects.`
		)
		return
	end

	local effect = activeEffects[effectName]
	if not effect then
		Logger.Output(
			"warn",
			`Attempted to send a ({effect}) replication event when it's not active under ({humanoid:GetFullName()}).`
		)
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
	local packet: Types.Replication = {
		EffectName = effectName,
		Message = message,
		Target = humanoid,
		Stacks = effect.Stacks,
		StartTime = effect.StartTime,
		ExpireTime = effect.ExpireTime,
	}
	self.ReplicationEvent:FireAllClients(packet)
	Logger.Output("log", `Sent {effectName} {message} replication event for ({humanoid:GetFullName()}).`)
end

return Replication
