const RunService = game:GetService("RunService")
const Players = game:GetService("Players")

const CurrentDirectory = script.Parent
const Types = require(CurrentDirectory.Types)

-- Convenience exporting so you don't have to import 'Types.luau' constantly
export type ConstructorDependencies = Types.ConstructorDependencies
export type StatusEffectObject = Types.StatusEffectObject
export type EffectDefinition = Types.EffectDefinition
export type EventMessages = Types.EventMessages
export type EffectInstance = Types.EffectInstance
export type EffectContext = Types.EffectContext

local CurrentObject: StatusEffectObject? = nil -- Represents the single object the StatusEffect
const Debugging = RunService:IsStudio()

--[[
	Output a message to the console about an event.
	Messages are only printed at studio time and won't be printed during production.
]]
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
	If the constructor was not used or the :Destroy method was used while one existed, the returned object will be nil.
]]
function StatusEffect.GetExistingObject()
	return CurrentObject
end

--[[
	Create an object of StatusEffect type to start managing the lifecycle of status effects.
	The reference of the object can be later referenced in StatusEffect.CurrentObject.

	Return:
		object - The newly created object that represents the StatusEffect.

	Arguements:
		remoteEvent - The RemoteEvent instance that will be used to send replication requests to the client. 
			Be sure to have a handler on the client to catch these events!
		eventNames - The names/messages that will be used for the RemoveEvent to send for precise replication.
		maxNumberPerHumanoid - The max number of events statuses a humanoid to have.
			By default, this value is capped at 3.
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
	if self.JanitorConnections == nil or #self.JanitorConnections == 0 then
		outputMessage("warn", "Unable to create StatusEffect object due to janitor creation failure.")
		return nil
	end

	-- Connection that runs the lifecycle of currently running effects
	self.RuntimeConnection = self:_createRuntime()
	if self.RuntimeConnection == nil or #self.RuntimeConnection == 0 then
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
	Shut down and destruct the entire StatusEffect object, releasing everything it owns.
	You'll have to create a new StatusEffect object if you want to use the StatusEffect.CurrentObject reference again.
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

const EFFECT_DEFINITION_DEFAULTS = {
	Duration = 5,
	Interval = 1,
	MaxStacks = math.huge,
	StackBehavior = "refresh",
}
table.freeze(EFFECT_DEFINITION_DEFAULTS)

function StatusEffect:_createRuntime(): RBXScriptConnection?
	if self.RuntimeConnection then
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
				end
			end
		end
	end)
end

--[[
	Create a janitor which will handle the creation and clean up of players who are joining, leaving the game, and already in the game.
	This will prevent any memory leaks that might come from active effects.

	This should only be ran once to initialize the janitor of the object.

	Return:
		{RBXScriptConnection} - An array of connections related to the janitor. Empty if failed to create any such connections.
]]
function StatusEffect:_createJanitor(): { RBXScriptConnection }
	if #self.JanitorConnections ~= 0 or self.JanitorConnections ~= nil then
		outputMessage("warn", "Attempted to create new janitor connections when they already exist.")
		return {}
	end

	local function getHumanoid(player: Player): Humanoid?
		local character = player.Character
		local humanoid = character and character:WaitForChild("Humanoid", 3)
		return humanoid:IsA("Humanoid") and humanoid
	end

	local function createDiedEvent(humanoid: Humanoid?)
		if not humanoid then
			return
		end

		humanoid.Died:Connect(function()
			self:ClearEffect(humanoid, "all")
		end)
	end

	-- Catch any players that are already in the game
	for _, player in Players:GetPlayers() do
		createDiedEvent(getHumanoid(player))
	end

	return {
		-- Connection to catch incoming players
		Players.PlayerAdded:Connect(function(player)
			createDiedEvent(getHumanoid(player))
			player.CharacterAdded:Connect(function()
				createDiedEvent(getHumanoid(player))
			end)
		end),

		-- Connection to catch outgoing players
		Players.PlayerRemoving:Connect(function(player)
			local humanoid = getHumanoid(player)
			if humanoid then
				self:ClearEffect(humanoid, "all")
			end
		end),
	}
end

function StatusEffect:_removeFromActive(humanoid: Humanoid, effectName: string)
	local effects = self.ActiveEffects[humanoid]
	if not effects then
		return
	end

	if effects[effectName] then
		effects[effectName] = nil

		local players = Players:GetPlayerFromCharacter(humanoid.Parent)
		self.RemoteEvent:FireAllClients(players, self.EventMessages.Remove, effectName)
	end
end

--[[
	Register an effect status to be avaliable for use.

	Return:
		boolean - The success of the registerion. True if successful, false otherwise.

	Arguements:
		effectName - The name you want to give for this effect and reference to.
		defintiion - The essential data and information to know exactly what this effect should do when it's actively running.

	NOTE: Properties will be defaulted to a value if they're not defined.
]]
function StatusEffect:RegisterEffect(effectName: string, definition: EffectDefinition): boolean
	if self.RegisteredEffects[effectName] then
		warn(`Attempted to register "{effectName}" when it's already registered.`)
		return false
	end

	definition.Duration = definition.Duration or Types.ED_Defaults.Duration
	definition.Interval = definition.Interval or Types.ED_Defaults.Interval
	definition.MaxStacks = definition.MaxStacks or Types.ED_Defaults.MaxStacks
	definition.StackBehavior = definition.StackBehavior or Types.ED_Defaults.StackBehavior

	self.RegisteredEffects[effectName] = definition
	return true
end

--[[
	Unregister an effect status type that will no longer be used.

	Return:
		boolean - The success of the unregisteration. True if successful, false otherwise.

	Arguements:
		effectName - The name of the effect that will be unregistered.
		terminate - Whether all running instances of this effect should also, to, be removed from humanoids.
			If terminate is false, existing instances will naturally disappear through their lifecycles.
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
	Create the context for an effect.
]]
function StatusEffect:_createContext(humanoid: Humanoid, effect: EffectInstance): EffectContext
	return {
		Target = humanoid,
		Effect = effect,
		Stacks = effect.Stacks,
		Damage = function(_, amount: number)
			humanoid:TakeDamage(amount)
		end,
		Remove = function()
			local activeEffects = self.ActiveEffects[humanoid]
			if activeEffects and activeEffects[effect.Name] == effect then
				activeEffects[effect.Name] = nil
				if effect.Definition.OnRemove then
					effect.Definition.OnRemove(self:_createContext(humanoid, effect))
				end
			end
		end,
		Refresh = function()
			effect.ExpireTime = workspace:GetServerTimeNow() + (effect.Definition.Duration :: number)
		end,
		AddStacks = function(_, amount: number)
			effect.Stacks = math.min(effect.Stacks + amount, effect.Definition.MaxStacks :: number)
		end,
	}
end

--[[
	Apply an effect status onto a humanoid.

	Return:
		boolean - The success of the application. True if successful, false otherwise.

	Arguements:
		humanoid - The humanoid instance to apply the effect onto.
		effectName - The effect that will be applied to the humanoid. 
			This name should be registered first before using this method!
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

	local player = Players:GetPlayerFromCharacter(humanoid.Parent)
	self.RemoteEvent:FireAllClients(player, self.EventMessages.Presist, effectName)

	return true
end

--[[
	Remove an effect manually from a humanoid.
	You can remove either one or all effects from the humanoid.

	Return:
		boolean - The success of the removal. True if successful, false otherwise.

	Arguements:
		humanoid - The humanoid instance to apply the effect onto.
		action - Either 'one' (to target one effect) or 'all' (to target all effects)
		effectName - The name of the effect to target for removal.
			You do not need to set this parameter if the action is 'all'.
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
