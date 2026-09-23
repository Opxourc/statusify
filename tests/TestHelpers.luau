--!strict

const Statusify = require("../Source/Api")
local TestHelpers = {}

function TestHelpers.Assert(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

function TestHelpers.AssertEqual<T, E>(actual: T, expected: E, message: string)
	TestHelpers.Assert(actual == expected, `{message} (expected {expected}, got {actual}).`)
end

function TestHelpers.NewObject(maxEffectsPerHumanoid: number?)
	local manager = Statusify.new({
		MaxEffectsPerHumanoid = maxEffectsPerHumanoid,
		ReplicationEvent = Instance.new("RemoteEvent"), -- No need to parent, we don't need to see any replication
	})

	TestHelpers.Assert(manager ~= nil, "Expected the object to be created.")
	return manager
end

function TestHelpers.NewHumanoid()
	return Instance.new("Humanoid")
end

return table.freeze(TestHelpers)
