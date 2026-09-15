const Types = require("./Types")
const Logger = require("./Logger")

local Threads = {}
const WEAK_METATABLE = { __mode = "k" }

function Threads.AddToActive(self: Types.StatusEffectInternal, humanoid: Humanoid, effectName: string, thread: thread)
	local activeThreads = self.ActiveThreads[humanoid]
	if not activeThreads then
		Logger.Output("warn", `({humanoid:GetFullName()}) doesn't have any active effects that can take threads.`)
		return
	end

	-- Create a new table if one doesn't already exist
	local threads = activeThreads[effectName]
	if not threads then
		threads = setmetatable({}, WEAK_METATABLE) -- When the thread is considered "dead" and no longer referenced, GC should remove it
		activeThreads[effectName] = threads
	end

	threads[thread] = true
	Logger.Output("log", `Added a thread for ({effectName}) by ({humanoid:GetFullName()}).`)
end

function Threads.CancelAllFromActive(
	self: Types.StatusEffectInternal,
	humanoid: Humanoid,
	action: "cancelEffect" | "cancelAll",
	effectName: string?
)
	if action == "cancelEffect" and not effectName then
		Logger.Output(
			"warn",
			`Attempted to cancel threads for a specific effect status on ({humanoid:GetFullName()}) when no effect name was specified.`
		)
		return
	end

	local activeThreads = self.ActiveThreads[humanoid]
	if not activeThreads then
		Logger.Output("warn", `({humanoid:GetFullName()}) doesn't have any active effects that can take threads.`)
		return
	end

	if action == "cancelAll" then
		for effectName, threads in activeThreads do
			for thread in threads do
				if coroutine.status(thread) ~= "dead" then
					task.cancel(thread)
				end
			end
		end

		self.ActiveThreads[humanoid] = nil
		Logger.Output("log", `Cancelled all running threads for ({humanoid:GetFullName()}).`)
	elseif action == "cancelEffect" then
		local threads = activeThreads[effectName]
		if not threads then
			Logger.Output(
				"warn",
				`({humanoid:GetFullName()}) doesn't have an active {effectName} effect to cancel threads from.`
			)
			return
		end

		for thread in threads do
			if coroutine.status(thread) ~= "dead" then
				task.cancel(thread)
			end
		end

		threads = nil
		Logger.Output(
			"log",
			`Cancelled all running threads for the ({effectName}) status effect for ({humanoid:GetFullName()}).`
		)
	else
		Logger.Output("warn", `Unknown action to cancel threads. Got: {action}.`)
	end
end

return table.freeze(Threads)
