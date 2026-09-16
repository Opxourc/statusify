const Types = require("./Types")
const Logger = require("./Logger")

local Threads = {}
const WEAK_METATABLE = { __mode = "k" }

function Threads.AddToActive(args: {
	Self: Types.StatusEffectInternal,
	Humanoid: Humanoid,
	EffectName: string,
	Thread: thread,
})
	local self = args.Self
	local thread = args.Thread
	local humanoid = args.Humanoid
	local effectName = args.EffectName

	local activeThreads = self.ActiveThreads[humanoid]
	if not activeThreads then
		activeThreads = {}
		self.ActiveThreads[humanoid] = activeThreads
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

function Threads.CancelAllFromActive(args: {
	Action: "cancelEffect" | "cancelAll",
	Self: Types.StatusEffectInternal,
	Humanoid: Humanoid,
	EffectName: string?,
})
	local effectName = args.EffectName
	local humanoid = args.Humanoid
	local action = args.Action
	local self = args.Self

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
