const RunService = game:GetService("RunService")

const Replication = require("./Replication")
const Watcher = require("./Watcher")
const Effects = require("./Effects")
const Logger = require("./Logger")
const Types = require("./Types")

local Runtime = {}

function Runtime.Create(self: Types.StatusifyInternal): RBXScriptConnection?
	if self.RuntimeConnection ~= nil then
		Logger.Output("warn", "Attempted to create a new runtime connection while one already exists.")
		return nil
	end

	return RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()

		-- Thread the callbacks because we don't know how long a callback can last for
		-- We also don't want it to halt the entire Heartbeat connection if one errors or yields
		for humanoid, activeEffects in self.ActiveEffects do
			for effectName, effect in activeEffects do
				-- If the time expires, clean up the effect under the humanoid
				-- Otherwise run a tick as long as tick is higher than 0
				if now >= effect.ExpireTime then
					Effects.Remove({
						Self = self,
						Humanoid = humanoid,
						EffectName = effectName,
					})
					Watcher.Destroy(self, humanoid)
				elseif effect.Definition.Interval and effect.Definition.Interval > 0 and now >= effect.NextTickTime then
					effect.NextTickTime = now + effect.Definition.Interval

					Effects.RunCallback({
						EventMessage = "tick",
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

return table.freeze(Runtime)
