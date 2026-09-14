local StatusEffect = require(script.Parent.Parent.StatusEffect.StatusEffect)
local Helpers = {}

function Helpers.Assert(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

function Helpers.AssertEqual(actual: any, expected: any, message: string)
	Helpers.Assert(actual == expected, `{message} (expected {expected}, got {actual})`)
end

function Helpers.NewManager(maxNumberPerHumanoid: number?)
	while StatusEffect.GetExistingObject() do
		task.wait()
	end

	local remoteEvent = {
		FireAllClients = function() end,
	}

	local manager = StatusEffect.New({
		MaxNumberPerHumanoid = maxNumberPerHumanoid,
		RemoteEvent = remoteEvent :: RemoteEvent,
	})
	Helpers.Assert(manager ~= nil, "Expected the StatusEffect manager to be created")
	return manager, remoteEvent
end

function Helpers.NewHumanoid()
	return Instance.new("Humanoid")
end

function Helpers.WaitForCleanup(manager: any, humanoid: Humanoid)
	manager:Destroy()
	Helpers.AssertEqual(StatusEffect.GetExistingObject(), nil, "Expected manager cleanup to release the singleton")
	humanoid:Destroy()
end

return table.freeze(Helpers)
