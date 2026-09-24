--!strict

const inStudio = game:GetService("RunService"):IsStudio()
local Logger = {}

--[[
	Output a "LOG" message for informational context.

	When running outside of Studio, no output will occur.

	@param message The string message that will printed.
]]
function Logger.info(message: string)
	if not inStudio then
		return
	end

	print(`\n[Statusify][INFO]\n{message}`)
end

--[[
	Output a "SEVERE" message that will result in a warning.

	This should be used in cases where the occurence is invalid, bugged, or shouldn't have happened and should be addressed.
	The message will printed regardless if the code environment is running in in Studio or in production.

	@param message The string message that will be traced back and printed.
]]
function Logger.severe(message: string)
	local source, line = debug.info(2, "sl")
	warn(`\n[Statusify][SEVERE]\n\nSOURCE:\n{source}:{line}\n\nTRACEBACK:\n{debug.traceback(message, 2)}`)
end

return table.freeze(Logger)
