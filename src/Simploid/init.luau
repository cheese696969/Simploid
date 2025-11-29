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
	-Does not implement any of the humanoid functions
	-Does not implement any of the humanoid's other features
	
	If you do want to implement specific humanoid features, you can easily do so by forking this module, the ServerHelper
	and ClientHelper modules which are childrens of this module.
	
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
		
	Simploid's Usable Attributes and Methods in the github API reference documentation:		
	https://github.com/cheese696969/Simploid/blob/main/API_REFERENCE.md
	
]]

--Services
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local HttpService = game:GetService("HttpService")

--[[
Module Dependencies: Change path if wanted
Make sure you have the module dependencies installed/created as an instance as a child of this module.
To get the latest version of these module dependencies, go to:
https://github.com/cheese696969/Simploid
]]
local Janitor = require(script.Packages.Janitor)
local ReplicatedTween = require(script.ReplicatedTween)
local Goodsignal = require(script.Packages.Goodsignal)
local Config = require(script.Config)
local Utils = require(script.Utils)


--GENERAL SETUP====================================================================================================================
--MODULE TABLE (For Client and Server)-----------------------------------------------------------
local Simploid = {}
Simploid.__index = Simploid

--Put ActiveSimploids in the module--------------------------------------------------------------
--This is a table of all initialized simploids that are still not cleaned by :Destroy()
local ActiveSimploids = {}
Simploid.ActiveSimploids = ActiveSimploids

--GETTERS----------------------------------------------------------------------------------------
--[[
These are for manipulation of simploids on client or server if you need it for 
other scripts other than the script that constructed the simploid

Note In Local Scripts and client usage:
A character's simploid or basically the whole rig may not be streamed in the client yet.
Therefore, the ActiveSimploids Table (when used in client) only contains streamed in rigs.
]]

--Gets an active simploid.
function Simploid.GetSimploidFromCharacter(character:Model) : Model?
	return ActiveSimploids[character]
end
--Gets all active simploids.
function Simploid.GetAllSimploids() : { [Model] : any }
	return table.clone(ActiveSimploids)
end
--------------------------------------------------------------------------------------------------

--IF MODULE IS REQUIRED ON SERVER==================================================================================================
if RunService:IsServer() then
	--Remote Events----------------------------------------------------------------------------------
	local FallRemote:RemoteEvent = script:WaitForChild("FallRemote")
	
	local ReplicationRemote:RemoteEvent = Instance.new("RemoteEvent")
	ReplicationRemote.Name = "ReplicationRemote"
	ReplicationRemote.Parent = script
	
	--Default Simploid Storage-----------------------------------------------------------------------
	local SimploidStorage:Folder = Instance.new("Folder")
	SimploidStorage.Name = "__SimploidStorage"
	SimploidStorage.Parent = workspace
	
	--To Update NPCs when it is falling--------------------------------------------------------------
	FallRemote.OnServerEvent:Connect(function(_, character)
		local self = ActiveSimploids[character]
		if self then
			self:_cancelMoveTo_FallConstrained()
		end
	end)
	
	--Server Type Definitions-----------------------------------------------------------------------------
	type Simploid = {
		--Attributes
		RayDownParams: RaycastParams,
		Path: Path,
		--Methods
		SetAttribute: (self:Simploid, attributeName:string, attributeValue:any) -> nil,
		GetAttribute: (self:Simploid, attributeName:string) -> any,
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
	require(script.Server)(Simploid)
--*************************************************************************************************************
--Simploid Server constructor
--*************************************************************************************************************
	function Simploid.new(character:Model?, storage:any) : Simploid?
		assert(character, "A character model is required!")
		if not character:IsA("Model") then 
			error("The character "..character.Name.." is not a model!") 
			return 
		end
		
		if storage then		
			--Check if storage is a descendant of a basepart
			local ancestor:BasePart? = storage:FindFirstAncestorWhichIsA("BasePart")
			if ancestor then
				error("Storage cannot have a basepart ancestor! | Ancestor Part: "..ancestor.Name)
			end
		else
			storage = SimploidStorage
		end
		
		local self = setmetatable({}, Simploid)
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
		AnchoredRoot.Name = "AnchoredRoot"
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
		character:SetAttribute("MaxHealth", 	Config.DEFAULT_ATTRIBUTES.MaxHealth)
		character:SetAttribute("Health", 	Config.DEFAULT_ATTRIBUTES.Health)
		character:SetAttribute("WalkSpeed", 	Config.DEFAULT_ATTRIBUTES.WalkSpeed)
		character:SetAttribute("JumpHeight", Config.DEFAULT_ATTRIBUTES.JumpHeight)
		character:SetAttribute("RootHeight", Config.DEFAULT_ATTRIBUTES.RootHeight)
		
		--State Attributes
		character:SetAttribute("State", "Running")
		
		--Simploid ID
		character:SetAttribute("Id", HttpService:GenerateGUID(false))

		--Anchored Root Weld
		local AnchoredRootWeld:Weld = Instance.new("Weld")
		AnchoredRootWeld.Name = "AnchoredRootWeld"
		AnchoredRootWeld.Part0 = AnchoredRoot
		AnchoredRootWeld.Part1 = self.HumanoidRootPart
		AnchoredRootWeld.C0 = CFrame.identity
		AnchoredRootWeld.Enabled = true
		
		self.AnchoredRoot = AnchoredRoot
		self.AnchoredRootWeld = AnchoredRootWeld
		
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
		self.Path = PathfindingService:CreatePath({
			AgentRadius = (self.HumanoidRootPart.Size.Z/2) + Config.SIMPLOID_RADIUS_ADDITIVE,
			AgentHeight = (self.HumanoidRootPart.Size.Y/2) + Config.SIMPLOID_HEIGHT_ADDITIVE,
			AgentCanJump = false,
			WaypointSpacing = Config.BASE_WAYPOINT_SPACING
		})
		
		AnchoredRoot.Parent = character
		AnchoredRootWeld.Parent = AnchoredRoot
		character.Parent = storage
		return self
	end
	
	
	
	
	
	
--IF MODULE IS REQUIRED ON CLIENT==================================================================================================
else
	--Remote Events and storage-----------------------------------------------------------------------
	local ReplicationRemote:RemoteEvent		= script:WaitForChild("ReplicationRemote")
	
	--Client Type Definitions-----------------------------------------------------------------------------
	type Simploid = {
		--Attributes
		RayDownParams:RaycastParams,
		--Methods
		SetAttribute: (self:Simploid, attributeName:string, attributeValue:any) -> nil,
		GetAttribute: (self:Simploid, attributeName:string) -> any,
		Death: (self:Simploid) -> nil,
		Destroy: (self:Simploid) -> nil,
		
	}
	require(script:WaitForChild("Client"))(Simploid)
--*************************************************************************************************************
--Simploid Client Constructor
--*************************************************************************************************************
	function Simploid.new(character:Model?)
		assert(character, "No Character Found")
		
		local self = setmetatable({}, Simploid)
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
		
		--SIMPLOID UPDATE DEPENCDENCIES-----------------------------------------------------------
		self.CanFallUpdate = true
		
		--RAY DOWN PARAMS-------------------------------------------------------------------------
		self.RayDownParams = RaycastParams.new()
		self.RayDownParams.FilterType = Config.DEFAULT_RAYPARAMS_FILTER_TYPE
		self.RayDownParams.FilterDescendantsInstances = {character}
		self.RayDownParams.IgnoreWater = Config.DEFAULT_RAYPARAMS_IGNORE_WATER

		--ANIMATION DEPENDECIES-------------------------------------------------------------------
		self.AnimationTracks = {}
		local AnimationController = Instance.new("AnimationController")
		self.Animator = Instance.new("Animator")
		self.Animator.Parent = AnimationController
		AnimationController.Parent = character
		
		local AnchoredRoot = character:WaitForChild("AnchoredRoot")
		self.AnchoredRoot = AnchoredRoot
		self.AnchoredRootWeld = AnchoredRoot:WaitForChild("AnchoredRootWeld")
		return self
	end
	
--|| Non-Class Client Setup ||*********************************************************************************
	--Default Simploid Storage-----------------------------------------------------------------------
	local SimploidStorage = workspace:WaitForChild("__SimploidStorage")
	local streamedSimploids = {}
	local valueCache = {}
	
	task.defer(function()
		while task.wait(1)  do
			print(valueCache, Utils.ctr)
			
		end
	end)
	
	ActiveSimploids = ReplicatedTween.ActiveSimploids
	Simploid.ActiveSimploids = ActiveSimploids
	local ActiveIdSimploids = {}
	
	--Activate simploid client side logic
	local function clientSimploidInit(character)
		if not ActiveSimploids[character] then
			local newSimploid:Simploid = Simploid.new(character)
			ActiveSimploids[character] = newSimploid
			ActiveIdSimploids[newSimploid:GetAttribute("Id")] = newSimploid
			
			task.defer(function()
				task.wait(1)
				local simploidCache = valueCache[newSimploid:GetAttribute("Id")]
				if simploidCache then
					for propertyName, propertyValue in simploidCache do
						newSimploid[propertyName] = propertyValue
					end
					valueCache[newSimploid:GetAttribute("Id")] = nil
				end
			end)
			
			streamedSimploids[character] = newSimploid
		else
			streamedSimploids[character] = ActiveSimploids[character]
		end
	end
	
	SimploidStorage.ChildAdded:Connect(clientSimploidInit)
	SimploidStorage.ChildRemoved:Connect(function(character)
		streamedSimploids[character] = nil
	end)
	for _, character in SimploidStorage:GetChildren() do
		clientSimploidInit(character)
	end
	
	--Replication Remotes Handling--------------------------------------------------------------------
	ReplicationRemote.OnClientEvent:Connect(function(Id:string, propertyName: string, value: any)
		if propertyName == "RayDownParams" and typeof(value) == "table" then
			value = Utils.RayParamsDeserialize(value)
		end

		local self = ActiveIdSimploids[Id]
		if self then
			warn("Property changed")
			self[propertyName] = value
		else
			--warn("ReplicateProperty failed: Simploid not found for character || Replication data cached.")
			
			valueCache[Id] = valueCache[Id] or {}
			valueCache[Id][propertyName] = value
		end
	end)
end

return Simploid 