--!optimize 2
if not game:GetService("RunService"):IsClient() then return nil end
--CLIENT SIMPLOID CLASS HELPER

--Module Dependencies: Change path if wanted
local Config = require(script.Parent.Config)
local ReplicatedTween = require(script.Parent.ReplicatedTween)

--Storage
local AnimationFolder:Folder = Instance.new("Folder")
AnimationFolder.Name = "AnimationFolder"
AnimationFolder.Parent = script.Parent

local clientActiveSimploids = ReplicatedTween.ClientActiveSimploids

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

	-- Returns the RBXScriptSignal for this specific attribute
	function Simploid:GetAttributeChangedSignal(attributeName: string) : RBXScriptSignal?
		return self.Character:GetAttributeChangedSignal(attributeName)
	end
	
	--Loads an animation
	function Simploid:LoadAnimation(animation:Animation) : AnimationTrack?
		if not self.Animator then 
			error("No Animator created!") 
		end
		return self.Animator:LoadAnimation(animation)
	end

	--Death method (NOT REPLICATED)
	function Simploid:Death()
		self.Janitor:Cleanup()
		
		if Config.DEATH_MODE == "BreakJoints" then
			if Config.SETUP_ANIMATOR and self.Animator then
				self.Animator.Parent:Destroy()
			end
			self.AnchoredRoot:Destroy()
			for _, descendant in self.Character:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = false
					continue
				end
				if descendant:IsA("Motor6D") then
					descendant:Destroy()
				end
			end

			local ragdoll = self.Character:Clone()
			self.Character:Remove()
			ragdoll.Parent = workspace
			task.wait(Config.SIMPLOID_RAGDOLL_TIME)
			ragdoll:Destroy()

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
			task.wait(Config.SIMPLOID_RAGDOLL_TIME)
			ragdoll:Destroy()
		elseif Config.DEATH_MODE == "Destroy" then
			self:Destroy()
			return
		end

		task.wait(Config.SIMPLOID_RAGDOLL_TIME)
		self:Destroy()
	end

	--Cleanup method
	function Simploid:Destroy()
		clientActiveSimploids[self.Character] = nil
		self.Animations = nil
		self.Janitor:Destroy()
		self.Janitor = nil
		self.Character:Destroy()
		self = nil
	end
end

