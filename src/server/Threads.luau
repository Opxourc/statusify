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
	Self: Types.StatusifyInternal,
	Humanoid: Humanoid,
	EffectName: string,
	Thread: thread,
})
	local self = args.Self
	local thread = args.Thread
	local humanoid = args.Humanoid
	local effectName = args.EffectName

	-- If the humanoid doesn't have a table, create one
	local activeThreads = self.ActiveThreads[humanoid]
	if not activeThreads then
		activeThreads = {}
		self.ActiveThreads[humanoid] = activeThreads
	end

	-- If the effect name doesn't have a table, create one
	local threads = activeThreads[effectName]
	if not threads then
		threads = {}
		activeThreads[effectName] = threads
	end

	threads[thread] = true
	Logger.Output("log", `Added a thread for ({effectName}) by ({humanoid:GetFullName()}).`)
end

--[[
	Cancels thread(s) so any callbacks for a effect running are cancelled.

	@param Self The object that will be referenced from.
	@param Humanoid The humanoid to cancel from.
	@param EffectName The effect name that hosted the threads.
]]
function Threads.Cancel(args: {
	Self: Types.StatusifyInternal,
	Humanoid: Humanoid,
	EffectName: string,
})
	local effectName = args.EffectName
	local humanoid = args.Humanoid
	local self = args.Self

	-- Humanoid should have a table
	local activeThreads = self.ActiveThreads[humanoid]
	if not activeThreads then
		Logger.Output("warn", `({humanoid:GetFullName()}) doesn't have any active threads to cancel.`)
		return
	end

	-- The effect name should have a table
	local threads = activeThreads[effectName]
	if not threads then
		Logger.Output(
			"warn",
			`({humanoid:GetFullName()}) doesn't have an active ({effectName}) effect to cancel threads from.`
		)
		return
	end

	-- Cancel all running threads if they aren't already dead
	for thread in threads do
		if coroutine.status(thread) ~= "dead" then
			task.cancel(thread)
		end
	end

	activeThreads[effectName] = nil
	Logger.Output(
		"log",
		`Cancelled all running threads for the ({effectName}) status effect for ({humanoid:GetFullName()}).`
	)

	-- If the number of effects under the humanoid is 0, nullify the humanoid entry
	self.ActiveThreads[humanoid] = Utilities.NilOnEmpty(activeThreads)
end

return table.freeze(Threads)
