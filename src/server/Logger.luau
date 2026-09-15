local Debugging = game:GetService("RunService"):IsStudio()
local Log = {}

function Log.Output(status: "warn" | "log" | "error", message: string)
	if not Debugging then
		return
	end

	if status == "warn" then
		warn(message)
	elseif status == "log" then
		print(message)
	elseif status == "error" then
		error(message)
	end
end

return table.freeze(Log)
