--!strict

const Replication = require("./Replication")
const Effects = require("./Effects")
const Types = require("./Types")

local Runtime = {}

--[[
	Creates a runtime connection that will run the lifecycle of all active effects.

	@param self The object that will be referenced from.
	@return RBXScriptConnection or nil if creation failed.
]]
function Runtime.Create(self: Types.Statusify): RBXScriptConnection
	Runtime.Destroy(self)

	return game:GetService("RunService").Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		for humanoid, activeEffects in self._activeEffects do
			if not activeEffects then
				continue
			end

			for effectName, effect in activeEffects do
				if not effect then
					continue
				end

				if now >= effect.ExpireTime then
					Effects.Remove({
						Self = self,
						Humanoid = humanoid,
						EffectName = effectName,
						Action = "effect",
					})
				elseif effect.Definition.Interval and effect.Definition.Interval > 0 and now >= effect.NextTickTime then
					effect.NextTickTime = now + effect.Definition.Interval
					Effects.RunCallback({
						Message = "tick",
						Self = self,
						Humanoid = humanoid,
						Effect = effect,
					})
					Replication.Replicate({
						Self = self,
						Definition = effect.Definition,
						Message = "tick",
						EffectName = effectName,
						Humanoid = humanoid,
					})
				end
			end
		end
	end)
end

--[[
	Destroys and disconnects the current runtime connection.
	@param self The object that will be referenced from.
]]
function Runtime.Destroy(self: Types.Statusify)
	if self._runtimeConnection then
		self._runtimeConnection:Disconnect()
		self._runtimeConnection = nil
	end
end

return table.freeze(Runtime)
