--!optimize 2
local Config = {
--BASIC CONFIGURATIONS************************************************************************************************************
	
--ATTRIBUTES: Default simploid object attributes when none are pre-set by you--
	DEFAULT_ATTRIBUTES = {
		Health = 100,
		MaxHealth =	100,
		WalkSpeed = 16,
		JumpHeight = 7.2,
		RootHeight = 3,
	},
	
	
--MODES--
	--How should the module handle simploid deaths : Default = "BreakJoints"
	--This module implements client side ragdolls and breakjoints, so no ragdolls work at the server's expense
	--Default = "BreakJoints"
	DEATH_MODE = "BreakJoints",				
	--[[
	"BreakJoints"	:	Breaks all body joints, causing the character to fall apart
	"Ragdoll"		:	Ragdolls the character (Inefficiently)
	"Destroy"		:	Instantly destroys it on death
	]]
	
	--How simploids will look at waypoints when PathfindTo() or MoveTo() is used 
	--Default = "XZ"
	MOVEMENT_LOOK_MODE = "XZ",
	--[[
	"XZ"			:	Looks only at the X and Z direction values of the waypoints
	"XYZ"			:	Looks at all the direction values of the waypoints
	"NoLook"		:	Does not look at all at the waypoints
	]]
	
	
--DEFAULT RAY PARAMS CONFIGURATION--  (Best to change these in a Simploid using :ReplicateProperty())
	DEFAULT_RAYPARAMS_FILTER_TYPE = Enum.RaycastFilterType.Exclude,
	DEFAULT_RAYPARAMS_IGNORE_WATER = true,
	--Default RayParams FilterDescendantsInstances has the simploid's rig itself inside it by default
	
	
--TECHNICAL CONFIGURATIONS*********************************************************************************************************
--DYNAMICS (Can change all simploid's behavior in runtime when changed in rutime)--
	
	SERVER_PLAYER_TO_SIMPLOID_TWEEN_DISTANCE = 1000,			--Maximum distance where players should be in so that the tween will play in client 
	SERVER_FALLING_WAIT = 3,								--How long to wait to recheck if npc is still falling
	
	BASE_WAYPOINT_SPACING = math.huge,						--Pathfind waypoint spacing
	SIMPLOID_RADIUS_ADDITIVE = 4,							--Adds an extra agent radius for npc pathfinds
	SIMPLOID_HEIGHT_ADDITIVE = 1,							--Adds an extra agent height for npc pathfinds
	SIMPLOID_RAGDOLL_TIME = 10,								--Time to wait for npc character to not be completely destroyed for a ragdoll
	
	RAY_EXIT_DIST = 3,										--How far to check for exits (When npc is stuck)
	
---------------------------------------------------------------------------------------------------------
	
--CONSTANTS (These are cached by user scripts. Cannot and should not be changed in runtime, for better efficiency)--
	
	RAY_DOWN_DIST = 10,										--How far to check for npc grounding (So npc does not look like it's flying). Once this distance gets bypassed by npc, falling begins
	WAYPOINT_Y_OFFSET = 0.5, 								--Adds an offset to the Y value of waypoints (Prechecked by me, don't change if you don't have to)
	--ROOT_TO_SIMPLOID_UPDATE_DIST = 200,					--If simploid is within this distance from the player, it will ground the npc's position
	SIMPLOID_FALL_THROTTLE = 6,								--If simploid goes to falling state, it will wait this long to resend a fall update to server
	
	--Directions for exit raycast
	DIRECTIONS = {
		Vector3.new(1, 0, 0),   -- +X
		Vector3.new(-1, 0, 0),  -- -X
		Vector3.new(0, 0, 1),   -- +Z
		Vector3.new(0, 0, -1),  -- -Z
		Vector3.new(1, 0, 1).Unit,   -- diagonals
		Vector3.new(-1, 0, 1).Unit,
		Vector3.new(1, 0, -1).Unit,
		Vector3.new(-1, 0, -1).Unit,
	},
	
	--List of properties that are the same on server and client, these can be set in the server (with replication) using Simploid:ReplicateProperty()
	REPLICATED_PROPERTIES = {
		RayDownParams = "RaycastParams"
	}
}


return Config
