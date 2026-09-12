--[[
    This is a demostration LocalScript for the StatusEffect framework.
    Use this as a reference for how a client might use and replicate the visuals from the framework!
]]

-- You can delete this script if this is in production
if not game:GetService("RunService"):IsStudio() then
	script:Destroy()
end

const ReplicatedStorage = game:GetService("ReplicatedStorage")

-- We'll use the Burn effect example
const StatusEffectEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StatusEffect")
const BurnAsset = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Burn")
if not (StatusEffectEvent and StatusEffectEvent:IsA("RemoteEvent") and BurnAsset and BurnAsset:IsA("BasePart")) then
	return
end

-- We'll also use the shared resources that the client and server and see and use
const SharedModules = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StatusEffect")
const SharedNames = require(SharedModules.Names)
const SharedTypes = require(SharedModules.Types)

local CurrentBurnAssets: { [Humanoid]: BasePart } = {}

-- The framework will send valuable information on what effect happen and who it happened on
StatusEffectEvent.OnClientEvent:Connect(function(data: SharedTypes.Replication)
	if data.EffectName == SharedNames.Burn and data.Target then
		if data.Message == "apply" and not CurrentBurnAssets[data.Target] then -- For applying the visual
			local character = data.Target:FindFirstAncestorWhichIsA("Model")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not (character and root and root:IsA("BasePart")) then
				return
			end

			-- The asset is assumed to have been preconfigured
			local asset = BurnAsset:Clone()
			asset.CFrame = character.WorldPivot
			asset.Parent = workspace

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = asset
			weld.Parent = asset
			CurrentBurnAssets[data.Target] = asset
		elseif data.Message == "remove" and CurrentBurnAssets[data.Target] then -- Removing the visual
			CurrentBurnAssets[data.Target]:Destroy()
		elseif data.Message == "tick" then -- We even can add tick based replications if need be
		end
	end
end)
