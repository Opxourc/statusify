--!strict

const Types = require("./Types")
local Watcher = {}

--[[
	Creates a new watcher connection that observe ".Destroying" events on humanoids to clean them up.

	Only one watcher connection should exist per humanoid.

	@param humanoid The humanoid that will be observed.
	@return RBXScriptConnection or nil if creation failed.
]]
function Watcher.Create(self: Types.Statusify, humanoid: Humanoid)
	self:_DestroyWatcher(humanoid)
	self._watcherConnections[humanoid] = humanoid.Destroying:Connect(function()
		self:_DestroyWatcher(humanoid)
		self:_CancelThread({
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
