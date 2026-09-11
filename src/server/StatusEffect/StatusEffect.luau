const RunService = game:GetService("RunService")
const Players = game:GetService("Players")

const CurrentDirectory = script.Parent
const Types = require(CurrentDirectory.Types)
const Defaults = require(CurrentDirectory.Defaults)

-- Convenience exporting so you don't have to import 'Types.luau' constantly
export type ConstructorDependencies = Types.ConstructorDependencies
export type StatusEffectObject = Types.StatusEffectObject
export type EffectDefinition = Types.EffectDefinition
export type EventMessages = Types.EventMessages
export type EffectInstance = Types.EffectInstance
export type EffectContext = Types.EffectContext

local CurrentObject: StatusEffectObject? = nil -- Represents the single object the StatusEffect
const Debugging = RunService:IsStudio()

local function outputMessage(status: "warn" | "log", message: string)
	if not Debugging then
		return
	end

	if status == "warn" then
		warn(message)
	elseif status == "log" then
		print(message)
	end
end

local StatusEffect = {}
StatusEffect.__index = StatusEffect

--[[
	Returns the currently existing StatusEffect object.
]]
function StatusEffect.GetExistingObject()
	return CurrentObject
end

--[[
	Constructs a new StatusEffect object.
	Only one object can exist at a time and should be referenced by .GetExistingObject() instead.
]]
function StatusEffect.New(dependencies: ConstructorDependencies): StatusEffectObject?
	if CurrentObject then
		outputMessage(
			"warn",
			"Attempted to create a StatusEffect object when one already exists. Use .GetExistingObject() to get this object instead!"
		)
		return nil
	end

	local self = setmetatable({}, StatusEffect)

	-- Connections to handle the active states of effects when a player joins/dies/leaves
	self.JanitorConnections = self:_createJanitor()
	if #self.JanitorConnections == 0 then
		outputMessage("warn", "Unable to create StatusEffect object due to janitor creation failure.")
		return nil
	end

	-- Connection that runs the lifecycle of currently running effects
	self.RuntimeConnection = self:_createRuntime()
	if self.RuntimeConnection == nil then
		outputMessage("warn", "Unable to create StatusEffect object due to runtime creation failure.")
		return nil
	end

	self.EventMessages = dependencies.EventMessages
	self.MaxNumberPerHumanoid = dependencies.MaxNumberPerHumanoid or 3
	self.RemoteEvent = dependencies.RemoteEvent -- This will be used to send replication events to the client
	self.RegisteredEffects = {} :: { [string]: EffectDefinition } -- These are effects that are considered valid
	self.ActiveEffects = {} :: { [Humanoid]: { [string]: EffectInstance } } -- Effects that are currently running on a humanoid

	outputMessage("log", "StatusEffect object created.")
	CurrentObject = self
	return self
end

--[[
	Destructs the object, releasing everything it owns.
]]
function StatusEffect:Destroy()
	CurrentObject = nil

	for _, connection in self.JanitorConnections do
		connection:Disconnect()
	end

	if self.RuntimeConnection then
		self.RuntimeConnection:Disconnect()
	end

	for humanoid, effectName in self.ActiveEffects do
		self:_removeFromActive(humanoid, effectName)
	end

	outputMessage("log", "StatusEffect object destroyed.")
end

--[[
	Initializes the Runtime for status effects, running their lifecycle automatically.
	Must only be called once.
]]
function StatusEffect:_createRuntime(): RBXScriptConnection?
	if self.RuntimeConnection ~= nil then
		outputMessage("warn", "Attempted to create a new runtime connection while one already exists.")
		return nil
	end

	return RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()

		for humanoid, activeEffects in self.ActiveEffects do
			for effectName, effect in activeEffects do
				if now >= effect.ExpireTime then
					self:_removeFromActive(humanoid, effectName)
					if effect.Definition.OnRemove then
						effect.Definition.OnRemove(self:_createContext(humanoid, effect))
					end
				elseif effect.Definition.Interval and effect.Definition.Interval > 0 and now >= effect.NextTickTime then
					effect.NextTickTime = now + effect.Definition.Interval
					if effect.Definition.OnTick then
						effect.Definition.OnTick(self:_createContext(humanoid, effect))
					end
					self:_sendReplication(humanoid, self.EventMessages.Tick, effectName)
				end
			end
		end
	end)
end

--[[
	Creates the context used to get the effect's current state.
]]
function StatusEffect:_createContext(humanoid: Humanoid, effect: EffectInstance): EffectContext
	return {
		Target = humanoid,
		Effect = effect,
		Stacks = effect.Stacks,
	}
end

--[[
	Initializes the Janitor and registers cleanup for existing, future, and existing players. 
	Must only be called once.
]]
function StatusEffect:_createJanitor(): { RBXScriptConnection }
	if self.JanitorConnections ~= nil and #self.JanitorConnections ~= 0 then
		outputMessage("warn", "Attempted to create new janitor connections when they already exist.")
		return {}
	end

	local connections: { RBXScriptConnection } = {}

	local function getHumanoid(character: Model?, waitForHumanoid: boolean): Humanoid?
		if not character then
			return nil
		end

		if waitForHumanoid then
			return character:WaitForChild("Humanoid", 5) :: Humanoid?
		end

		return character:FindFirstChildOfClass("Humanoid")
	end

	local function createDiedEvent(character: Model?)
		local humanoid = getHumanoid(character, true)
		if not humanoid then
			return
		end

		table.insert(
			connections,
			humanoid.Died:Connect(function()
				self:ClearEffect(humanoid, "all")
			end)
		)
	end

	local function watchPlayer(player: Player)
		createDiedEvent(player.Character)
		table.insert(connections, player.CharacterAdded:Connect(createDiedEvent))
	end

	-- Catch any players that are already in the game
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	-- Connection to catch incoming players and outgoing players
	table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			local humanoid = getHumanoid(player.Character, false)
			if humanoid then
				self:ClearEffect(humanoid, "all")
			end
		end)
	)

	return connections
end

--[[
	Remove an active effect from a humanoid.
]]
function StatusEffect:_removeFromActive(humanoid: Humanoid, effectName: string)
	local effects = self.ActiveEffects[humanoid]
	if not effects then
		return
	end

	if effects[effectName] then
		-- Call the replication event first before setting nil
		-- This is because replication is goning to check the state of the effect for this humanoid again
		self:_sendReplication(humanoid, self.EventMessages.Remove, effectName)
		effects[effectName] = nil
		outputMessage("log", `Removed {effectName} from ({humanoid:GetFullName()}).`)
	end
end

--[[
	Sends a replication event to the client with information about the current state of an effect.
]]
function StatusEffect:_sendReplication(humanoid: Humanoid, message: EventMessages, effectName: string): boolean
	local player = Players:GetPlayerFromCharacter(humanoid.Parent)
	if not player then
		outputMessage(
			"warn",
			`Attempted to send a replication event when Player instance was found via humanoid: ({humanoid:GetFullName()})`
		)
		return false
	end

	local effects = self.ActiveEffects[humanoid]
	if not effects then
		outputMessage(
			"warn",
			`Attempted to send a replication event when no events exist under the provided humanoid: ({humanoid:GetFullName()})`
		)
		return false
	end

	local effect = effects[effectName]
	if not effect then
		outputMessage(
			"warn",
			`Attempted to send a replication event for "{effectName}" effect when it doesn't exist under the provided humanoid: ({humanoid:GetFullName()})`
		)
		return false
	end

	-- Only give enough information to allow the client to build whatever representation they want
	self.RemoteEvent:FireAllClients({
		EffectName = effectName,
		Message = message,
		Target = player,
		Stacks = effect.Stacks,
		StartTime = effect.StartTime,
		ExpireTime = effect.ExpireTime,
	})

	outputMessage("log", `Sent replication event for {effectName} for humanoid: ({humanoid:GetFullName()})`)
	return true
end

--[[
	Register an effect status to be avaliable for use.
	Properties will be defaulted to a value if they're nil.
]]
function StatusEffect:RegisterEffect(effectName: string, definition: EffectDefinition): boolean
	if self.RegisteredEffects[effectName] then
		outputMessage("warn", `Attempted to register "{effectName}" when it's already registered.`)
		return false
	end

	definition.Duration = definition.Duration or Defaults.ED_Defaults.Duration
	definition.Interval = definition.Interval or Defaults.ED_Defaults.Interval
	definition.MaxStacks = definition.MaxStacks or Defaults.ED_Defaults.MaxStacks
	definition.StackBehavior = definition.StackBehavior or Defaults.ED_Defaults.StackBehavior

	self.RegisteredEffects[effectName] = definition
	return true
end

--[[
	Unregister an effect status that will no longer be used.
	Use 'terminate' to destroy all active instances of the effect instantly.
]]
function StatusEffect:UnregisterEffect(effectName: string, terminate: boolean): boolean
	if not self.RegisteredEffects[effectName] then
		outputMessage("warn", `Attempted to unregister "{effectName}" when it wasn't registered.`)
		return false
	end

	self.RegisteredEffects[effectName] = nil

	if terminate then
		for humanoid, effects in self.ActiveEffects do
			if not effects[effectName] then
				continue
			end

			task.spawn(function()
				self:_removeFromActive(humanoid, effectName)
			end)
		end
	end

	return true
end

--[[
	Apply and effect status onto a humanoid.
	This effect status should be registered first before any application of it can be used!
]]
function StatusEffect:ApplyEffect(humanoid: Humanoid, effectName: string): boolean
	local definition = self.RegisteredEffects[effectName]
	if not definition then
		outputMessage("warn", `Attempted to apply unregistered effect "{effectName}" onto ({humanoid:GetFullName()})`)
		return false
	end

	local now = workspace:GetServerTimeNow()
	local activeEffects = self.ActiveEffects[humanoid]
	if not activeEffects then
		activeEffects = {}
		self.ActiveEffects[humanoid] = activeEffects
	end

	local existingEffect = activeEffects[effectName]
	if existingEffect then
		if definition.StackBehavior == "ignore" then
			return true
		end

		if definition.StackBehavior == "stack" and existingEffect.Stacks < (definition.MaxStacks :: number) then
			existingEffect.Stacks += 1
		end

		existingEffect.ExpireTime = now + (definition.Duration :: number)
		return true
	end

	local effect: EffectInstance = {
		Name = effectName,
		Definition = definition,
		StartTime = now,
		Stacks = 1,
		ExpireTime = now + (definition.Duration :: number),
		NextTickTime = now + (definition.Interval :: number),
	}

	activeEffects[effectName] = effect
	if definition.OnApply then
		definition.OnApply(self:_createContext(humanoid, effect))
	end

	self:_sendReplication(humanoid, self.EventMessages.Apply, effectName)
	return true
end

--[[
	Remove an effect status from a humanoid.
	Use 'action' to determine whether all or one effect should be removed.
	If 'action' is set to "all", you don't have to provide the 'effectName' arguement.
]]
function StatusEffect:ClearEffect(humanoid: Humanoid, action: "one" | "all", effectName: string?): boolean
	if action == "one" then
		if not effectName then
			outputMessage(
				"warn",
				`Attempted to clear an effect from ({humanoid:GetFullName()}) despite no effectName being given.`
			)
			return false
		end

		self:_removeFromActive(humanoid, effectName)
		return true
	elseif action == "all" then
		local effects = self.ActiveEffects[humanoid]
		if not effects then
			return false
		end

		for name in effects do
			self:_removeFromActive(humanoid, name)
		end
	end

	return true
end

return table.freeze(StatusEffect)
