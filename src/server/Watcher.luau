const Logger = require("./Logger")
const Types = require("./Types")

local Watcher = {}

function Watcher.Create(self: Types.StatusifyInternal, humanoid: Humanoid): RBXScriptConnection?
	if self.WatcherConnections[humanoid] ~= nil then
		Logger.Output(
			"warn",
			`Attempted to create new watcher connection for ({humanoid:GetFullName()}) when it already exist.`
		)
		return nil
	end

	-- Whenever the humanoid is being destroyed, disconnect the watcher and clean up all effects on the humanoid
	return humanoid.Destroying:Connect(function()
		Watcher.Destroy(self, humanoid)
		self:ClearEffect({
			Action = "removeAll",
			Humanoid = humanoid,
		})
	end)
end

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
