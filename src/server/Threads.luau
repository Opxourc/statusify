--!strict

const Utilities = require("./Utilities")
const Types = require("./Types")
const Logger = require("./Logger")

local Threads = {}

--[[
	Adds a new thread to be ActiveThreads table for a Statusify object.

	@param Self The object that will be referenced from.
	@param Humanoid The humanoid to check from.
	@param EffectName The effect name is hosting the thread.
	@param Thread The thread that will be stored.
]]
function Threads.Add(args: {
	Self: Types.Statusify,
	Humanoid: Humanoid,
	EffectName: string,
	Thread: thread,
})
	local self = args.Self
	local thread = args.Thread
	local humanoid = args.Humanoid
	local effectName = args.EffectName

	local activeThreads = self._activeThreads[humanoid]
	if not activeThreads then
		activeThreads = {}
		self._activeThreads[humanoid] = activeThreads
	end
	assert(activeThreads ~= nil)

	local threads = activeThreads[effectName]
	if not threads then
		threads = {}
		activeThreads[effectName] = threads
	end
	assert(threads ~= nil)

	threads[thread] = true
	Logger.Info(`Added a thread for ({effectName}) status effect by ({humanoid:GetFullName()}).`)
end

--[[
	Cancels thread(s) so any callbacks for a effect running are cancelled.

	Actions:

	- "all": All running threads under the humanoid will be cancelled.
	- "effect": All running threads under an active effect under a humanoid will be cancelled.

	@param Self The object that will be referenced from.
	@param Action Determines how cancelling will work.
	@param Humanoid The humanoid to cancel from.
	@param EffectName The effect name that hosted the threads.
]]
function Threads.Cancel(args: {
	Self: Types.Statusify,
	Humanoid: Humanoid,
	EffectName: string?,
	Action: "all" | "effect",
})
	local effectName = args.EffectName
	local humanoid = args.Humanoid
	local action = args.Action
	local self = args.Self

	local function cancelThreads(threadTable: { [thread]: boolean? }?)
		if threadTable then
			for thread in threadTable do
				if coroutine.status(thread) ~= "dead" then
					task.cancel(thread)
				end
			end
		end
	end

	if action == "effect" then
		if not effectName then
			Logger.Severe("Attempted to cancel a thread when an effect name wasn't provided.")
			return
		end

		local activeThreads, threads = Utilities.GetActiveThreads({
			Self = self,
			Humanoid = humanoid,
			EffectName = effectName,
			Source = "Threads.Cancel (removing threads under a specific effect)",
		})

		if not activeThreads then
			return
		end

		cancelThreads(threads)
		activeThreads[effectName] = nil
		self._activeThreads[humanoid] = Utilities.NilOnEmpty(activeThreads)

		Logger.Info(`Cancelled a thread under ({effectName}) status effect for ({humanoid:GetFullName()}).`)
	elseif action == "all" then
		local activeThreads = Utilities.GetActiveThreads({
			Self = self,
			Humanoid = humanoid,
			Source = `Threads.Cancel (removing all threads under ({humanoid:GetFullName()}))`,
		})

		if not activeThreads then
			return
		end

		for name, threads in activeThreads do
			cancelThreads(threads)
			activeThreads[name] = nil
		end

		self._activeThreads[humanoid] = nil
		Logger.Info(`Cancelled all threads for ({humanoid:GetFullName()}).`)
	else
		Logger.Info(`Unknown action provided for cancelling threads. Got: ({action}).`)
	end
end

return table.freeze(Threads)
