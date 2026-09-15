-- This is a demostration LocalScript for the Statusify framework.
-- Use this as a reference for how a client might use and replicate the visuals from the framework!

-- You can delete this script if this is in production
if not game:GetService("RunService"):IsStudio() then
	script:Destroy()
end

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RemoteEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Statusify"):WaitForChild("DemoReplication")
const SharedNames = require("@game/ReplicatedStorage/Shared/Statusify/Names")
const SharedTypes = require("@game/ReplicatedStorage/Shared/Statusify/Types") -- We want the structure of how incoming data will look like
const BurnPart = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Statusify"):WaitForChild("BurnPart")

local CurrentVisuals: { [Humanoid]: BasePart } = {} -- We should keep a note on what visuals are currently running

RemoteEvent.OnClientEvent:Connect(function(data: SharedTypes.Replication)
	-- Incoming data will provide context on what effect sent the message
	-- And Information on itself
	if data.EffectName == SharedNames.Burn then -- Check if the effect name is 'Burn'
		if data.Message == "apply" and not CurrentVisuals[data.Target] then -- Check the message sent and if a visual is already provided to this humanoid
			local character = data.Target:FindFirstAncestorWhichIsA("Model")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not (character and root and root:IsA("BasePart")) then
				return
			end

			local asset = BurnPart:Clone()
			asset.CFrame = character.WorldPivot
			asset.Parent = workspace

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = asset
			weld.Parent = asset
			CurrentVisuals[data.Target] = asset
		elseif data.Message == "remove" and CurrentVisuals[data.Target] then -- Removing the visual from the humanoid
			CurrentVisuals[data.Target]:Destroy() -- Destroy() returns nil, we're done here
		elseif data.Message == "update" then
			-- Even though the server doesn't have any callbacks for 'update' on this event
			-- If Replicate was set to true for Update we can still do stuff here on the client
			print("Here's the Update replication!")
		end
	end
end)

-- That's the end of the client-side demo!
-- This demo only showed 3D visual replication but you can also do UI replication as well!
-- Hope you enjoy :)
