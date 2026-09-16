const RunService = game:GetService("RunService")
const Players = game:GetService("Players")

const Replication = require("./Replication")
const Utilities = require("./Utilities")
const Threads = require("./Threads")
const Logger = require("./Logger")
const Types = require("./Types")

local Connections = {}

function Connections.CreateRuntime(self: Types.StatusEffectInternal): RBXScriptConnection?
	if self.RuntimeConnection ~= nil then
		Logger.Output("warn", "Attempted to create a new runtime connection while one already exists.")
		return nil
	end

	return RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()

		-- Thread the callbacks because we don't know how long a callback can last for
		-- We also don't want it to halt the entire Heartbeat connection if one errors or yields
		for humanoid, activeEffects in self.ActiveEffects do
			for effectName, effect in activeEffects do
				if now >= effect.ExpireTime then
					Utilities.RemoveFromActive({
						Self = self,
						Humanoid = humanoid,
						EffectName = effectName,
					})
				elseif effect.Definition.Interval and effect.Definition.Interval > 0 and now >= effect.NextTickTime then
					effect.NextTickTime = now + effect.Definition.Interval

					-- Run callback for tick
					if effect.Definition.OnTick then
						Threads.AddToActive(
							self,
							humanoid,
							effectName,
							task.spawn(function()
								local ok, err =
									pcall(effect.Definition.OnTick, Utilities.CreateContext(humanoid, effect))
								if not ok then
									Logger.Output("error", `OnTick callback for ({effectName}) errored: ({err}).`)
								end
							end)
						)
					end

					Replication.Replicate({
						Self = self,
						Definition = effect.Definition,
						Message = "tick",
						EffectName = effectName,
						Humanoid = humanoid,
					})
				end
			end
		end
	end)
end

function Connections.CreateWatcher(self: Types.StatusEffectInternal): { [RBXScriptConnection]: true }
	if self.WatcherConnections ~= nil and next(self.WatcherConnections) ~= nil then
		Logger.Output("warn", "Attempted to create new watcher connections when they already exist.")
		return {}
	end

	local connections: { [RBXScriptConnection]: true } = {}
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

		-- If the humanoid dies, remove all effects automatically
		connections[humanoid.Died:Connect(function()
			self:ClearEffect(humanoid, "removeAll")
			Threads.CancelAllFromActive(self, humanoid, "cancelAll")
		end)] =
			true
	end

	local function watchPlayer(player: Player)
		createDiedEvent(player.Character)
		connections[player.CharacterAdded:Connect(createDiedEvent)] = true
	end

	-- Catch any players that are already in the game
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	-- Connection to catch incoming players and outgoing players
	connections[Players.PlayerAdded:Connect(watchPlayer)] = true
	connections[Players.PlayerRemoving:Connect(function(player)
		local humanoid = getHumanoid(player.Character, false)
		if humanoid then
			self:ClearEffect(humanoid, "removeAll")
			Threads.CancelAllFromActive(self, humanoid, "cancelAll")
		end
	end)] =
		true

	return connections
end

return table.freeze(Connections)
