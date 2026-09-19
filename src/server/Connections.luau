const RunService = game:GetService("RunService")

const Replication = require("./Replication")
const Utilities = require("./Utilities")
const Threads = require("./Threads")
const Logger = require("./Logger")
const Types = require("./Types")

local Connections = {}

function Connections.CreateRuntime(self: Types.StatusifyInternal): RBXScriptConnection?
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

function Connections.CreateWatcher(self: Types.StatusifyInternal, humanoid: Humanoid): RBXScriptConnection?
	if self.WatcherConnections[humanoid] ~= nil then
		Logger.Output(
			"warn",
			`Attempted to create new watcher connection for ({humanoid:GetFullName()}) when it already exist.`
		)
		return nil
	end

	-- Whenever the humanoid is being destroyed, disconnect the watcher and clean up all effects on the humanoid
	return humanoid.Destroying:Connect(function()
		Connections.DestroyWatcher(self, humanoid)
		self:ClearEffect({
			Action = "removeAll",
			Humanoid = humanoid,
		})
	end)
end

function Connections.DestroyWatcher(self: Types.StatusifyInternal, humanoid: Humanoid)
	local connection = self.WatcherConnections[humanoid]
	if not connection then
		Logger.Output("warn", `There's no watcher connection to disconnect for ({humanoid:GetFullName()}).`)
		return
	end

	connection:Disconnect()
	self.WatcherConnections[humanoid] = nil
end

return table.freeze(Connections)
