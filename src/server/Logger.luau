--!strict

const inStudio = game:GetService("RunService"):IsStudio()
local Logger = {}

--[[
	Output a "LOG" message for informational context.

	This function will check the code environment.
	If the environment is at studio time, then no output will occur.

	@param message The string message that will outputted.
]]
function Logger.info(message: string)
	if not inStudio then
		return
	end

	print(`\n[Statusify][INFO]\n{message}`)
end

--[[
	Output a "SERVERE" message that will result in a warning.

	This should be used in cases where the occurence is invalid, bugged, or shouldn't have happened and should be addressed.
	The message will outputted regardless if the code environment is in studio or live.

	@param message The string message that will be traced back and outputted.
]]
function Logger.severe(message: string)
	local source, line = debug.info(2, "sl")
	warn(`\n[Statusify][SEVERE]\n\nSOURCE:\n{source}:{line}\n\nTRACEBACK:\n{debug.traceback(message, 2)}`)
end

return table.freeze(Logger)
