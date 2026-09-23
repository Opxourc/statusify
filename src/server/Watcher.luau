--!strict

const Types = require("./Types")
const Threads = require("./Threads")

local Watcher = {}

--[[
	Creates a new watcher connection that observe '.Destroying' events on humanoids to clean them up.

	Only one watcher connection should exist per humanoid.

	@param self The object that will be referenced from.
	@param humanoid The humanoid that will be observed.

	@return RBXScriptConnection or nil if creation failed.
]]
function Watcher.Create(self: Types.Statusify, humanoid: Humanoid): RBXScriptConnection
	Watcher.Destroy(self, humanoid)

	return humanoid.Destroying:Connect(function()
		Watcher.Destroy(self, humanoid)
		Threads.Cancel({
			Self = self,
			Humanoid = humanoid,
			Action = "all",
		})
		self:Remove({
			Action = "all",
			Humanoid = humanoid,
		})
	end)
end

--[[
	Destroy and disconnect a watcher connection for a humanoid.

	@param self The object that will be referenced from.
	@param humanoid The humanoid that will have it's connection removed.
]]
function Watcher.Destroy(self: Types.Statusify, humanoid: Humanoid)
	local connection = self._watcherConnections[humanoid]
	if connection then
		connection:Disconnect()
		self._watcherConnections[humanoid] = nil
	end
end

return table.freeze(Watcher)
