--!optimize 2
--CLIENT SIMPLOID CLASS HELPER

--Module Dependencies: Change path if wanted
local Config = require(script.Parent.Config)

local AnimationFolder:Folder = Instance.new("Folder")
AnimationFolder.Name = "AnimationFolder"
AnimationFolder.Parent = script.Parent

--********************************************************************************************************
--CLIENT SIMPLOID HELPER METHODS
--********************************************************************************************************
return function(Simploid)
	--Sets Simploid attribute (NOT REPLICATED)
	function Simploid:SetAttribute(attributeName:string, value:any)
		self.Character:SetAttribute(attributeName, value)
	end

	--Gets Simploid attribute
	function Simploid:GetAttribute(attributeName:string) : any
		return self.Character:GetAttribute(attributeName)
	end
	
	--Death method (NOT REPLICATED)
	function Simploid:Death()
		self.Janitor:Cleanup()
		
		if Config.DEATH_MODE == "BreakJoints" then
			for _, descendant in self.Character:GetDescendants() do
				if descendant:IsA("Motor6D") then
					descendant:Destroy()
				end
			end
		elseif Config.DEATH_MODE == "Ragdoll" then
			local ragdoll = self.Character:Clone()
			self.Character:Remove()
			for _, descendant in ragdoll:GetDescendants() do
				if descendant:IsA("Motor6D") then
					local socket = Instance.new("BallSocketConstraint")
					local a1 = Instance.new("Attachment")
					local a2 = Instance.new("Attachment")
					a1.Parent = descendant.Part0
					a2.Parent = descendant.Part1
					socket.Parent = descendant.Parent
					socket.Attachment0 = a1
					socket.Attachment1 = a2
					a1.CFrame = descendant.C0
					a2.CFrame = descendant.C1
					socket.LimitsEnabled = true
					socket.TwistLimitsEnabled = true
					descendant:Destroy()
				elseif descendant:IsA("BasePart") then
					descendant.CanCollide = true
					descendant.Anchored = false
				end
			end
			ragdoll.Parent = workspace
		elseif Config.DEATH_MODE == "Destroy" then
			self:Destroy()
			return
		end

		task.wait(Config.SIMPLOID_RAGDOLL_TIME)
		self:Destroy()
	end

	--Cleanup method
	function Simploid:Destroy()
		self.Animations = nil
		self.Janitor:Destroy()
		self.Janitor = nil
		self = nil
	end
end

