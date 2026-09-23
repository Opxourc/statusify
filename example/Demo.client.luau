--!strict

if not game:GetService("RunService"):IsStudio() then
	script:Destroy()
end

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const SharedNames = require(ReplicatedStorage.Shared.Statusify.Names)

const removeEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Statusify"):WaitForChild("DemoReplication")
const burnPart = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Statusify"):WaitForChild("BurnPart")

-- We should keep a reference on what visuals are currently running
-- Statusify doesn't enforce how the client should handle replication so we gotta make it ourselves
local CurrentVisuals: { [Humanoid]: BasePart } = {}

removeEvent.OnClientEvent:Connect(function(data)
	local effectName = data.EffectName
	local message = data.Message
	local target = data.Target

	--[[
		All keys from data:
		
		data.Message: "apply" | "tick" | "remove" | "update"
		data.EffectName: string
		data.ExpireTime: number
		data.StartTime: number
		data.Target: Humanoid
		data.Stacks: number
	]]

	if effectName == SharedNames.Burn then
		if message == "apply" and not CurrentVisuals[target] then
			local character = target:FindFirstAncestorWhichIsA("Model")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not (character and root and root:IsA("BasePart")) then
				return
			end

			local asset = burnPart:Clone()
			asset.CFrame = character.WorldPivot
			asset.Parent = workspace

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = asset
			weld.Parent = asset
			CurrentVisuals[target] = asset
		elseif message == "remove" and CurrentVisuals[target] then -- Removing the visual from the humanoid
			CurrentVisuals[data.Target]:Destroy() -- Destroy() returns nil, we're done here
		elseif message == "update" then
			print("Here's the Update replication!")
		end
	end
end)
