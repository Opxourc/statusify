const RunService = game:GetService("RunService")

const Connections = require("./Connections")
const Replication = require("./Replication")
const Utilities = require("./Utilities")
const Threads = require("./Threads")
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
				if now >= effect.ExpireTime then
					-- Remove from active and clean up the destroyer
					Utilities.RemoveFromActive({
						Self = self,
						Humanoid = humanoid,
						EffectName = effectName,
					})
					Connections.DestroyWatcher(self, humanoid)
				elseif effect.Definition.Interval and effect.Definition.Interval > 0 and now >= effect.NextTickTime then
					effect.NextTickTime = now + effect.Definition.Interval

					-- Run callback for tick
					if effect.Definition.OnTick then
						Threads.AddToActive({
							Self = self,
							Humanoid = humanoid,
							EffectName = effectName,
							Thread = task.spawn(function()
								local ok, err =
									pcall(effect.Definition.OnTick, Utilities.CreateContext(humanoid, effect))
								if not ok then
									Logger.Output("error", `OnTick callback for ({effectName}) errored: ({err}).`)
								end
							end),
						})
					end

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
