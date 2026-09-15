const SharedTypes = require("@game/ReplicatedStorage/Shared/Statusify/Types")
const Logger = require("./Logger")
const Types = require("./Types")

local Replication = {}

export type ReplicateType = {
	Definition: Types.EffectDefinition,
	Message: SharedTypes.EventMessage,
	Self: Types.StatusEffectInternal,
	Humanoid: Humanoid,
	EffectName: string,
}

function Replication.Replicate(args: ReplicateType)
	local activeEffects = args.Self.ActiveEffects[args.Humanoid]
	if not activeEffects then
		Logger.Output(
			"warn",
			`Attempted to send a replication event for ({args.Humanoid:GetFullName()}) when there's no active effects.`
		)
		return
	end

	local effect = activeEffects[args.EffectName]
	if not effect then
		Logger.Output(
			"warn",
			`Attempted to send a ({effect}) replication event when it's not active under ({args.Humanoid:GetFullName()}).`
		)
		return
	end

	-- Replication is determined by the definition of the effect
	local shouldReplicate = false
	if args.Definition.Replicate then
		if args.Message == "apply" and args.Definition.Replicate.Apply then
			shouldReplicate = true
		elseif args.Message == "tick" and args.Definition.Replicate.Tick then
			shouldReplicate = true
		elseif args.Message == "remove" and args.Definition.Replicate.Remove then
			shouldReplicate = true
		elseif args.Message == "update" and args.Definition.Replicate.Update then
			shouldReplicate = true
		end
	end

	if not shouldReplicate then
		return
	end

	-- Only give enough information to allow the client to build whatever representation they want
	local packet: SharedTypes.Replication = {
		EffectName = args.EffectName,
		Message = args.Message,
		Target = args.Humanoid,
		Stacks = effect.Stacks,
		StartTime = effect.StartTime,
		ExpireTime = effect.ExpireTime,
	}
	args.Self.RemoteEvent:FireAllClients(packet)
	Logger.Output("log", `Sent {args.EffectName} {args.Message} replication event for ({args.Humanoid:GetFullName()}).`)
end

return Replication
