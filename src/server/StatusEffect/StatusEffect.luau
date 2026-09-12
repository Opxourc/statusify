const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")
const Players = game:GetService("Players")

const CurrentDirectory = script.Parent
const Types = require(CurrentDirectory.Types)
const Defaults = require(CurrentDirectory.Defaults)
const SharedTypes = require(ReplicatedStorage.Shared.StatusEffect.Types)

-- Convenience exporting so you don't have to import 'Types.luau' constantly
export type ConstructorDependencies = Types.ConstructorDependencies
export type StatusEffectObject = Types.StatusEffectObject
export type EffectDefinition = Types.EffectDefinition
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

	for humanoid, effects in self.ActiveEffects do
		for effectName in effects do
			self:_removeFromActive(humanoid, effectName)
		end
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

		for humanoid, effects in self.ActiveEffects do
			for effectName, effect in effects do
				if now >= effect.ExpireTime then
					self:_removeFromActive(humanoid, effectName)
					if effect.Definition.OnRemove then
						local ok, err = pcall(effect.Definition.OnRemove, self:_createContext(humanoid, effect))
						if not ok then
							outputMessage("warn", `OnRemove callback for "{effectName}" errored: {err}`)
						end
					end
				elseif effect.Definition.Interval and effect.Definition.Interval > 0 and now >= effect.NextTickTime then
					effect.NextTickTime = now + effect.Definition.Interval
					if effect.Definition.OnTick then
						local ok, err = pcall(effect.Definition.OnTick, self:_createContext(humanoid, effect))
						if not ok then
							outputMessage("warn", `OnTick callback for "{effectName}" errored: {err}`)
						end
					end
					self:_sendReplication(humanoid, "tick", effectName, effect.Definition)
				end
			end
		end
	end)
end

--[[
	Mutate the stack count of a effect to go up or down.
]]
function StatusEffect:_mutateStack(humanoid: Humanoid, effect: EffectInstance, applyValue: number)
	effect.Stacks = math.clamp(effect.Stacks + applyValue, 0, effect.Definition.MaxStacks :: number)
	self:_sendReplication(humanoid, "update", effect.Name, effect.Definition)
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
				self:ClearEffect(humanoid, "removeAll")
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
				self:ClearEffect(humanoid, "removeAll")
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
		self:_sendReplication(humanoid, "remove", effectName, effects[effectName].Definition)
		effects[effectName] = nil
		outputMessage("log", `Removed {effectName} from ({humanoid:GetFullName()}).`)

		if next(effects) == nil then
			self.ActiveEffects[humanoid] = nil
		end
	end
end

--[[
	Sends a replication event to the client with information about the current state of an effect.
]]
function StatusEffect:_sendReplication(
	humanoid: Humanoid,
	message: SharedTypes.EventMessage,
	effectName: string,
	definition: EffectDefinition
): boolean
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

	local shouldReplicate = false
	if definition.Replicate then
		if message == "apply" and definition.Replicate.Apply then
			shouldReplicate = true
		elseif message == "tick" and definition.Replicate.Tick then
			shouldReplicate = true
		elseif message == "remove" and definition.Replicate.Remove then
			shouldReplicate = true
		end
	end

	if not shouldReplicate then
		return true
	end

	-- Only give enough information to allow the client to build whatever representation they want
	local packet: SharedTypes.Replication = {
		EffectName = effectName,
		Message = message,
		Target = humanoid,
		Stacks = effect.Stacks,
		StartTime = effect.StartTime,
		ExpireTime = effect.ExpireTime,
	}
	self.RemoteEvent:FireAllClients(packet)

	outputMessage("log", `Sent {message} replication event for {effectName} for humanoid: ({humanoid:GetFullName()})`)
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

	if not definition.Replicate then
		definition.Replicate = {
			Apply = Defaults.ED_Defaults.Replicate.Apply,
			Tick = Defaults.ED_Defaults.Replicate.Tick,
			Remove = Defaults.ED_Defaults.Replicate.Remove,
		}
	else
		definition.Replicate = {
			Apply = if definition.Replicate.Apply == nil
				then Defaults.ED_Defaults.Replicate.Apply
				else definition.Replicate.Apply,

			Tick = if definition.Replicate.Tick == nil
				then Defaults.ED_Defaults.Replicate.Tick
				else definition.Replicate.Tick,

			Remove = if definition.Replicate.Remove == nil
				then Defaults.ED_Defaults.Replicate.Remove
				else definition.Replicate.Remove,
		}
	end

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
	local effects = self.ActiveEffects[humanoid]
	if not effects then
		effects = {}
		self.ActiveEffects[humanoid] = effects
	end

	local existing = effects[effectName]
	if existing then
		if definition.StackBehavior == "ignore" then
			return true
		end

		if definition.StackBehavior == "stack" then
			self:_mutateStack(humanoid, existing, 1)
		end

		existing.ExpireTime = now + (definition.Duration :: number)
		return true
	end

	local currentCount = 0
	for _ in effects do
		currentCount += 1
	end

	if currentCount >= self.MaxNumberPerHumanoid then
		outputMessage(
			"warn",
			`Attempted to apply "{effectName}" onto ({humanoid:GetFullName()}) but it already has the maximum number of effects ({self.MaxNumberPerHumanoid}).`
		)
		return false
	end

	local effect: EffectInstance = {
		Name = effectName,
		Definition = definition,
		StartTime = now,
		Stacks = 1,
		ExpireTime = now + (definition.Duration :: number),
		NextTickTime = now + (definition.Interval :: number),
	}

	effects[effectName] = effect
	if definition.OnApply then
		local ok, err = pcall(definition.OnApply, self:_createContext(humanoid, effect))
		if not ok then
			outputMessage("warn", `OnApply callback for "{effectName}" errored: {err}`)
		end
	end

	self:_sendReplication(humanoid, "apply", effectName, definition)
	return true
end

--[[
	Remove an effect status from a humanoid.
	Use 'action' to determine how effect(s) should be removed.
	
	Actions:
		remove - Remove one single effect, ignoring all stacks on it.
		removeAll - Remove every effect from the humanoid.
		decrement - Remove one stack of the effect. If the stack drops to 0, it will be removed automatically.
	If the action is either "remove" or "decrement" you must specify the effectName.
]]
function StatusEffect:ClearEffect(
	humanoid: Humanoid,
	action: "remove" | "removeAll" | "decrement",
	effectName: string?
): boolean
	if (action == "remove" or action == "decrement") and not effectName then
		outputMessage("warn", `Attempted to clear a effect when no effect name was specified.`)
		return false
	end

	if action == "remove" then
		self:_removeFromActive(humanoid, effectName)
		return true
	elseif action == "removeAll" then
		local effects = self.ActiveEffects[humanoid]
		if not effects then
			return false
		end

		for name in effects do
			self:_removeFromActive(humanoid, name)
		end
	elseif action == "decrement" then
		local effects = self.ActiveEffects[humanoid]
		if not effects then
			return false
		end

		local effect = effects[effectName]
		if not effect then
			outputMessage(
				"warn",
				`Attempted to decrement "{effectName}" when it wasn't active on ({humanoid:GetFullName()})`
			)
			return false
		end

		self:_mutateStack(humanoid, effect, -1)
		if effect.Stacks == 0 then
			self:_removeFromActive(humanoid, effectName)
		end
	end

	return true
end

-- Read Only Methods

--[[
	Returns the registered EffectDefinition for the given effect name, or nil if unregistered.
]]
function StatusEffect:GetRegisteredEffect(effectName: string): EffectDefinition?
	return self.RegisteredEffects[effectName]
end

--[[
	Returns the active EffectInstance for a humanoid, or nil if it isn't active.
]]
function StatusEffect:GetActiveEffect(humanoid: Humanoid, effectName: string): EffectInstance?
	local effects = self.ActiveEffects[humanoid]
	if not effects then
		return nil
	end

	return effects[effectName]
end

--[[
	Returns whether a humanoid currently has the given effect active.
]]
function StatusEffect:HasEffect(humanoid: Humanoid, effectName: string): boolean
	local effects = self.ActiveEffects[humanoid]
	if not effects then
		return false
	end

	return effects[effectName] ~= nil
end

return table.freeze(StatusEffect)
