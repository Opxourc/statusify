const Statusify = require("../Source/Api")
const Types = require("../Source/Types")

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
	while Statusify.GetExistingObject() do
		task.wait() -- Keep waiting until GetExistingObject returns 'nil'
	end

	local manager = Statusify.New({
		MaxEffectsPerHumanoid = maxEffectsPerHumanoid,
		ReplicationEvent = Instance.new("RemoteEvent"), -- No need to parent, we don't need to see any replication
	})

	TestHelpers.Assert(manager ~= nil, "Expected the object to be created.")
	return manager
end

function TestHelpers.NewHumanoid()
	return Instance.new("Humanoid")
end

function TestHelpers.WaitForCleanup(object: Types.StatusEffectExternal, humanoid: Humanoid)
	(object :: any):Destroy()
	TestHelpers.AssertEqual(Statusify.GetExistingObject(), nil, "Expected object cleanup to release the singleton")
	humanoid:Destroy()
end

return table.freeze(TestHelpers)
