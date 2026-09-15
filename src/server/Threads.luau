const Types = require("./Types")
const Logger = require("./Logger")

local Threads = {}

export type FunctionArgs = {
	Self: Types.StatusEffectInternal,
	Humanoid: Humanoid,
	EffectName: string,
}

export type AddToActiveArgs = FunctionArgs & {
	Thread: thread,
}

local function getActiveThreads(args: FunctionArgs): { thread }?
	local activeThreads = args.Self.ActiveThreads[args.Humanoid]
	if not activeThreads then
		Logger.Output("warn", `({args.Humanoid}) doesn't have any active effects that can take threads.`)
		return nil
	end

	local effect = activeThreads[args.EffectName]
	if not effect then
		Logger.Output("warn", `({args.Humanoid}) doesn't have an active ({args.EffectName}) effect.`)
		return nil
	end

	return effect
end

function Threads.AddToActive(args: AddToActiveArgs)
	local threads = getActiveThreads(args)
	if not threads then
		return
	end

	table.insert(threads, args.Thread)
	Logger.Output("log", `Added a thread for ({args.EffectName}) by ({args.Humanoid}).`)
end

function Threads.CancelAll(args: FunctionArgs)
	local threads = getActiveThreads(args)
	if not threads then
		return
	end

	for i, thread in threads do
		if coroutine.status(thread) ~= "dead" then
			task.cancel(thread)
		end
		threads[i] = nil
	end

	threads = nil
	Logger.Output("log", `Cancelled all threads for ({args.EffectName}) by ({args.Humanoid}).`)
end
