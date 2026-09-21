--!strict

const Logger = require("./Logger")
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
function Watcher.Create(self: Types.StatusifyInternal, humanoid: Humanoid): RBXScriptConnection?
	if self.WatcherConnections[humanoid] then
		Logger.Output(
			"warn",
			`Attempted to create new watcher connection for ({humanoid:GetFullName()}) when it already exist.`
		)
		return nil
	end

	-- Whenever the humanoid is being destroyed, clean up the humanoid
	return humanoid.Destroying:Connect(function()
		-- Cancel all threads
		Threads.Cancel({
			Self = self,
			Humanoid = humanoid,
			Action = "all",
		})

		-- Destrpy watcher and remove
		Watcher.Destroy(self, humanoid)
		self:Remove({
			Action = "remove_all",
			Humanoid = humanoid,
		})
	end)
end

--[[
	Creates a new watcher connection that observe '.Destroying' events on humanoids to clean them up.

	Only one watcher connection should exist per humanoid.

	@param self The object that will be referenced from.
	@param humanoid The humanoid that will be observed.

	@return RBXScriptConnection or nil if creation failed.
]]
function Watcher.Destroy(self: Types.StatusifyInternal, humanoid: Humanoid)
	local connection = self.WatcherConnections[humanoid]
	if not connection then
		Logger.Output("warn", `There's no watcher connection to disconnect for ({humanoid:GetFullName()}).`)
		return
	end

	connection:Disconnect()
	self.WatcherConnections[humanoid] = nil
end

return table.freeze(Watcher)
