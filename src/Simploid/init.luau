--!optimize 2
--[[SIMPLOID CLASS=================================================================================================================
	By @cheesyhuman2 : https://github.com/cheese696969/Simploid
	10/26/2025
	
	Simploids aim to create a much more lightweight and more performant alternative to Humanoids when you need NPCs.
	Your npc rigs must have a HumanoidRootPart as its PrimaryPart.		
	
	Features:
	-No need for a humanoid
	-Almost does not rely on physics 						(Only uses physics when falling is detected)
	-No smooth movement on server, only on client 			(Helps heavily in network efficiency)
	-Uses raycasting to simulate collisions
	-Built in pathfinding system with pathfinding service
	-Update server movement position whenever you want
	
	Drawbacks:
	-Only the most basic methods of humanoids are reproduced
	-NPC characters may go through walls
	-Does not implement any of the humanoid events
	-Does not implement most of the humanoid properties
	-Does not implement most of the humanoid functions
	-Does not implement any of the humanoid's other features
	
	If you do want to implement specific humanoid features, you can easily do so by forking this module, and other
	modules which are childrens of this module.
	
	To start using Simploids, simply require this module in the SERVER AND CLIENT (Using a script and a local script)
	and use the .new() constructor ON THE SERVER to create a Simploid.
	
	EXAMPLE USAGE:
	In local script:
		require(game.ReplicatedStorage.Simploid)
		
	In server script:
		local Simploid = require(game.ReplicatedStorage.Simploid)
		local character = workspace.Dummy 							--Have your own dummy rig character to use.
		
		local new_simploid = Simploid.new(character)
		new_simploid:PathfindTo(Vector3.new(10,0,10))				--Moves npc dummy to the given position
	
	For more information on Simploid's properties, attributes, and methods, go to:
	<Simploid's Usable Attributes and Methods in the github API reference documentation>		
	https://github.com/cheese696969/Simploid/blob/main/API_REFERENCE.md
]]

--Services
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

--[[
Module Dependencies: Change path if wanted
Make sure you have the module dependencies installed/created as an instance as a child of this module.
To get the latest version of these module dependencies, go to:
https://github.com/cheese696969/Simploid under \DevPackages
]]
local Janitor = require(script.Packages.Janitor)
local ReplicatedTween = require(script.ReplicatedTween)
local Goodsignal = require(script.Packages.Goodsignal)
local Config = require(script.Config)
local Utils = require(script.Utils)

--Table to be returned
local Simploid = {}

--IF MODULE IS REQUIRED IN SERVER==================================================================================================
if RunService:IsServer() then
	--MODULE TABLE (For Server)----------------------------------------------------------------------
	Simploid.Server = {}
	Simploid.Server.__index = Simploid.Server
	local ServerSimploid = Simploid.Server
	
	--Put ActiveSimploids (Server Initialized) in the module-----------------------------------------
	local serverActiveSimploids = ReplicatedTween.ServerActiveSimploids

	local serverPropertyCache = ReplicatedTween.ServerPropertyCache

	--Remote Events and Functions--------------------------------------------------------------------
	local FallRemote:RemoteEvent = script:WaitForChild("FallRemote")
	
	local ReplicationRemote:RemoteEvent = Instance.new("RemoteEvent")
	ReplicationRemote.Name = "ReplicationRemote"
	ReplicationRemote.Parent = script

	local RequestPropertiesRemote:RemoteFunction = Instance.new("RemoteFunction")
	RequestPropertiesRemote.Name = "RequestPropertiesRemote"
	RequestPropertiesRemote.Parent = script
	
	--Default Simploid Storage-----------------------------------------------------------------------
	local SimploidStorage:Folder = Instance.new("Folder")
	SimploidStorage.Name = "__SimploidStorage"
	SimploidStorage.AncestryChanged:Connect(function()
		if SimploidStorage.Parent ~= workspace then
			warn("Storage can only be under workspace!")
			SimploidStorage.Parent = workspace
		end
	end)
	SimploidStorage.Parent = workspace
	
	--Remote Connections-----------------------------------------------------------------------------
	FallRemote.OnServerEvent:Connect(function(_, character)
		local self = serverActiveSimploids[character]
		if self then
			self:_cancelMoveTo_FallConstrained()
		end
	end)

	RequestPropertiesRemote.OnServerInvoke = function(_, character:Model?)
		return serverPropertyCache[character]
	end
	
	--Server Type Definitions------------------------------------------------------------------------
	type Simploid = {
		--Attributes
		RayDownParams: RaycastParams,
		Path: Path,
		--Methods
		SetAttribute: (self:Simploid, attributeName:string, attributeValue:any) -> nil,
		GetAttribute: (self:Simploid, attributeName:string) -> any,
		GetAttributeChangedSignal: (self:Simploid, attributeName:string) -> RBXScriptSignal?,
		ReplicateProperty: (self:Simploid, propertyName:string, value:any) -> nil,
		MoveTo: (self:Simploid, position:Vector3) -> nil,
		CancelMoveTo: (self:Simploid) -> nil,
		PathfindTo: (self: Simploid, position:Vector3) -> nil,
		SetTimedPosition: (self:Simploid) -> nil,
		Jump: (self:Simploid) -> nil,
		Wander: (self:Simploid) -> nil,
		Death: (self:Simploid) -> nil,
		Destroy: (self:Simploid) -> nil
	}

	--Server Getters---------------------------------------------------------------------------------

	--Gets an active simploid (Server).
	function ServerSimploid.GetSimploidFromCharacter(character:Model) : Simploid
		return serverActiveSimploids[character]
	end
	--Gets all active simploids (Server).
	function ServerSimploid.GetAllSimploids() : { [Model] : Simploid? }
		return table.clone(serverActiveSimploids)
	end

	require(script.Server)(ServerSimploid)
--*************************************************************************************************************
--Simploid Server constructor
--*************************************************************************************************************
	function ServerSimploid.new(character:Model?) : Simploid
		assert(character, "A character model is required!")
		if not character:IsA("Model") then 
			error("The character "..character.Name.." is not a model!") 
		end
		
		local self = setmetatable({}, ServerSimploid)
		self.Janitor = Janitor.new()

		--CHARACTER SETUP-------------------------------------------------------------------------
		self.Character = character
		self.HumanoidRootPart = character:WaitForChild("HumanoidRootPart", 60)
		assert(self.HumanoidRootPart, "No HumanoidRootPart Found")
		
		--PARTS SETUP-----------------------------------------------------------------------------
		--Anchored Root
		local AnchoredRoot:BasePart = self.HumanoidRootPart:Clone()
		AnchoredRoot.CanCollide = false
		AnchoredRoot.CanTouch = false
		AnchoredRoot.CanQuery = false
		AnchoredRoot.Transparency = 1
		AnchoredRoot.Anchored = true
		AnchoredRoot.Name = "__AnchoredRoot"
		AnchoredRoot:ClearAllChildren()
				
		--ATTRIBUTES:(Like a normal humanoid's properties ... Only some are implemented)----------
		--[[
		Setup Attributes 
		-> The character holds attributes for the simploid attributes, event connection, and replication
		-> These act like instance properties 
		-> These are replicated from server to client
		-> Some are imitated from roblox humanoids, others are custom added (For updates)
		-> To trigger events on client
		-> Attributes are public and can be accessed outside of this class using simploidObject:GetAttribute()
		]]
		
		--Humanoid imitated attributes
		character:SetAttribute("MaxHealth", Config.DEFAULT_ATTRIBUTES.MaxHealth)
		character:SetAttribute("Health", Config.DEFAULT_ATTRIBUTES.Health)
		character:SetAttribute("WalkSpeed", Config.DEFAULT_ATTRIBUTES.WalkSpeed)
		character:SetAttribute("JumpHeight", Config.DEFAULT_ATTRIBUTES.JumpHeight)
		character:SetAttribute("RootHeight", Config.DEFAULT_ATTRIBUTES.RootHeight)
		
		--State Attributes
		character:SetAttribute("State", "Idle")

		--Anchored Root Weld
		local AnchoredRootWeld:Weld = Instance.new("Weld")
		AnchoredRootWeld.Name = "AnchoredRootWeld"
		AnchoredRootWeld.Part0 = AnchoredRoot
		AnchoredRootWeld.Part1 = self.HumanoidRootPart
		AnchoredRootWeld.C0 = CFrame.identity
		AnchoredRootWeld.Enabled = true
		
		self.AnchoredRoot = AnchoredRoot
		
		--STATES----------------------------------------------------------------------------------
		--DO NOT CHANGE THESE: changeable through code only
		self.NormalState = true 						
		self.Motion = "None" 						--Used so that pathfinding calls do not clash
		self.MotionTarget = nil
		self.CanFallUpdate = true
		self.JumpSignal = Goodsignal.new()
		
		--HELPING ATTRIBUTES----------------------------------------------------------------------
		self.HeightAdditive = Vector3.new(0, (character:GetAttribute("RootHeight") :: number?), 0)
		self.RayDirection = Vector3.new(0, -Config.RAY_DOWN_DIST, 0) - (self.HeightAdditive * 2)
		self.WaypointHeight = character:GetAttribute("RootHeight") - Config.WAYPOINT_Y_OFFSET

		--EVENTS CONNECTION-----------------------------------------------------------------------
		self.Janitor:Add(character:GetAttributeChangedSignal("RootHeight"):Connect(function()
			local raw = character:GetAttribute("RootHeight")
			local rootHeight = (typeof(raw) == "number" and raw or 0) :: number

			self.HeightAdditive = Vector3.new(0, rootHeight, 0)
			self.RayDirection = Vector3.new(0, -Config.RAY_DOWN_DIST, 0) - (self.HeightAdditive * 2)
			self.WaypointHeight = rootHeight - Config.WAYPOINT_Y_OFFSET
		end), "Disconnect")
		
		self.Janitor:Add(character:GetAttributeChangedSignal("Health"):Connect(function()
			local raw = character:GetAttribute("Health")
			local health = (typeof(raw) == "number" and raw or 0) :: number

			if health <= 0 then
				self:Death()
			end
		end), "Disconnect")
		
		self.Janitor:Add(AnchoredRoot.Destroying:Once(function()
			self:Death()
		end), "Disconnect")
			
		--RAY DOWN PARAMS-------------------------------------------------------------------------
		self.RayDownParams = RaycastParams.new()
		self.RayDownParams.FilterType = Config.DEFAULT_RAYPARAMS_FILTER_TYPE
		self.RayDownParams.FilterDescendantsInstances = {character}
		self.RayDownParams.IgnoreWater = Config.DEFAULT_RAYPARAMS_IGNORE_WATER
		
		--MOVEMENT TWEEN SETUP--------------------------------------------------------------------
		self.CurrentTween = nil
		self.CurrentNextPosition = nil
		self.CurrentPastPosition = nil
		self.CurrentPastTime = nil
		self.CurrentTweenTime = nil
		
		--PATH SETUP------------------------------------------------------------------------------
		--Default path object
		--A created path object cannot be modified, if you want different path parameters, you need to create one yourself.
		if Config.CAN_PATHFIND then
			self.Path = PathfindingService:CreatePath({
				AgentRadius = (self.HumanoidRootPart.Size.Z/2) + Config.SIMPLOID_RADIUS_ADDITIVE,
				AgentHeight = (self.HumanoidRootPart.Size.Y/2) + Config.SIMPLOID_HEIGHT_ADDITIVE,
				AgentCanJump = Config.CAN_JUMP,
				WaypointSpacing = Config.BASE_WAYPOINT_SPACING
			})
		end
		
		AnchoredRoot.Parent = character
		AnchoredRootWeld.Parent = AnchoredRoot
		character.Parent = SimploidStorage
		
		serverActiveSimploids[character] = self
		return self
	end
	
	
	
	
	
--IF MODULE IS REQUIRED IN CLIENT==================================================================================================
else
	--MODULE TABLE (For Client)-----------------------------------------------------------------------
	Simploid.Client = {}
	local ClientSimploid = {}
	ClientSimploid.__index = ClientSimploid

	--Put ActiveSimploids (Server Initialized) in the module------------------------------------------
	local clientActiveSimploids = ReplicatedTween.ClientActiveSimploids

	--Remote Events, Functions, and storage-----------------------------------------------------------
	local ReplicationRemote:RemoteEvent	= script:WaitForChild("ReplicationRemote")
	local RequestPropertiesRemote:RemoteFunction = script:WaitForChild("RequestPropertiesRemote")

	--Client Type Definitions-------------------------------------------------------------------------
	type Simploid = {
		--Attributes
		RayDownParams:RaycastParams,
		--Methods
		SetAttribute: (self:Simploid, attributeName:string, attributeValue:any) -> nil,
		GetAttribute: (self:Simploid, attributeName:string) -> any,
		GetAttributeChangedSignal: (self:Simploid, attributeName:string) -> RBXScriptSignal?,
		LoadAnimation: (self:Simploid, animation:Animation) -> AnimationTrack?
	}

	--Client Getters----------------------------------------------------------------------------------

	--Gets an active simploid (Client).
	function Simploid.Client.GetSimploidFromCharacter(character:Model) : Simploid
		return clientActiveSimploids[character]
	end
	--Gets all active simploids (Client).
	function Simploid.Client.GetAllSimploids() : { [Model] : Simploid? }
		return table.clone(clientActiveSimploids)
	end

	require(script:WaitForChild("Client"))(ClientSimploid)
--*************************************************************************************************************
--Simploid Client Constructor
--*************************************************************************************************************
	function ClientSimploid.new(character:Model?) : Simploid?
		assert(character, "No Character Found")
		
		local self = setmetatable({}, ClientSimploid)
		self.Janitor = Janitor.new()
		
		--CHARACTER SETUP-------------------------------------------------------------------------
		self.Character = character	
		
		--Helping Properties
		self.HeightAdditive = Vector3.new(0, (character:GetAttribute("RootHeight") :: number?), 0)
		self.RayDirection = Vector3.new(0, -Config.RAY_DOWN_DIST, 0) - (self.HeightAdditive * 2)
		
		--EVENTS CONNECTION-----------------------------------------------------------------------
		self.Janitor:Add(character:GetAttributeChangedSignal("RootHeight"):Connect(function()
			local rawHeight = character:GetAttribute("RootHeight")
			local rootHeight = (typeof(rawHeight) == "number" and rawHeight or 0) :: number
			
			self.HeightAdditive = Vector3.new(0, rootHeight, 0)
			self.RayDirection = Vector3.new(0, -Config.RAY_DOWN_DIST, 0) - (self.HeightAdditive * 2)
		end), "Disconnect")
		
		self.Janitor:Add(character:GetAttributeChangedSignal("State"):Connect(function()
			if character:GetAttribute("State") == "Dead" then
				self:Death()
			end
		end), "Disconnect")
		
		--SIMPLOID UPDATE DEPENDENCIES-----------------------------------------------------------
		self.CanFallUpdate = true
		
		--RAY DOWN PARAMS-------------------------------------------------------------------------
		self.RayDownParams = RaycastParams.new()
		self.RayDownParams.FilterType = Config.DEFAULT_RAYPARAMS_FILTER_TYPE
		self.RayDownParams.FilterDescendantsInstances = {character}
		self.RayDownParams.IgnoreWater = Config.DEFAULT_RAYPARAMS_IGNORE_WATER

		--ANIMATION DEPENDECIES-------------------------------------------------------------------
		if Config.SETUP_ANIMATOR then
			local AnimationController = Instance.new("AnimationController")
			self.Animator = Instance.new("Animator")
			self.Animator.Parent = AnimationController
			AnimationController.Parent = character
		end
		
		--STREAM IN WAITS AND CLEANUP-------------------------------------------------------------
		local rootWait
		local rootWaitDone = false

		if character:FindFirstChild("__AnchoredRoot") then
			self.AnchoredRoot = character:FindFirstChild("__AnchoredRoot")
			rootWaitDone = true
		else
			rootWait = character.ChildAdded:Connect(function(child)
				if child.Name == "__AnchoredRoot" then
					self.AnchoredRoot = child
					rootWaitDone = true
					rootWait:Disconnect() 
				end
			end)
		end

		self.Janitor:Add(character.AncestryChanged:Connect(function()
			if character.Parent then return end
			if rootWait then
				rootWaitDone = true
				rootWait:Disconnect() 
			end
			self:Destroy()
		end), "Disconnect")

		repeat task.wait()
		until rootWaitDone
		
		if not self.AnchoredRoot then return end
		self.AnchoredRootWeld = self.AnchoredRoot:WaitForChild("AnchoredRootWeld")
		
		return self
	end
	

	


--|| Non-Class Client Setup ||*********************************************************************************
	--Default Simploid Storage-----------------------------------------------------------------------
	local SimploidStorage = workspace:WaitForChild("__SimploidStorage")

	--Property setter for a Simploid object
	local function setSimploidProperty(simploid:Simploid?, propertyName:string, propertyValue:any)
		if not simploid then return end
		if propertyName == "RayDownParams" and typeof(propertyValue) == "table" then
			propertyValue = Utils.RayParamsDeserialize(propertyValue)
		end

		simploid[propertyName] = propertyValue
	end

	--Activate simploid client side logic
	local function clientSimploidInit(character)
		if not clientActiveSimploids[character] then
			local newSimploid:Simploid? = ClientSimploid.new(character)
			if not newSimploid then return end
			clientActiveSimploids[character] = newSimploid

			task.defer(function()
				local propertyTable = RequestPropertiesRemote:InvokeServer(character)
				if not propertyTable then return end
				for propertyName, propertyValue in propertyTable do
					setSimploidProperty(newSimploid, propertyName, propertyValue)
				end
			end)
		end
	end
	
	SimploidStorage.ChildAdded:Connect(clientSimploidInit)
	for _, character in SimploidStorage:GetChildren() do
		clientSimploidInit(character)
	end
	
	--Replication Remotes Handling--------------------------------------------------------------------
	ReplicationRemote.OnClientEvent:Connect(function(character:Model?, propertyName: string, propertyValue: any)
		local simploid = clientActiveSimploids[character]
		if not simploid then return end
		setSimploidProperty(simploid ,propertyName, propertyValue)
	end)
end

return Simploid

