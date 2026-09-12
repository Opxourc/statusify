--[[
    This is a demostration LocalScript for the StatusEffect framework.
    Use this as a reference for how a client might use and replicate the visuals from the framework!
]]

-- You can delete this script if this is in production
if not game:GetService("RunService"):IsStudio() then
	script:Destroy()
end

-- We'll use the Burn effect like what the server created
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const StatusEffectEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StatusEffect") :: RemoteEvent
const BurnAsset = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Burn") :: BasePart
if not (StatusEffectEvent and BurnAsset) then
	return
end

local CurrentBurnAsset: BasePart? = nil

if StatusEffectEvent then
	-- The framework will send valuable information on what effect happen and who it happened on
	StatusEffectEvent.OnClientEvent:Connect(function(data)
		if data.EffectName == "Burn" and data.Target then
			if data.Message == "apply" and not CurrentBurnAsset then -- For applying the visual
				local character = data.Target.Character :: Model?
				local root = character and character:WaitForChild("HumanoidRootPart") :: BasePart?
				if not (character and root) then
					return
				end

				-- The asset is assumed to have been preconfigured
				local asset = BurnAsset:Clone() :: BasePart
				asset.CFrame = character.WorldPivot
				asset.Parent = workspace

				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = asset
				weld.Parent = asset
				CurrentBurnAsset = asset
			elseif data.Message == "remove" and CurrentBurnAsset then -- Removing the visual
				CurrentBurnAsset:Destroy()
			elseif data.Message == "tick" then -- We even can add tick based replications
				-- other code stuff here or whatever lol
			end
		end
	end)
end
