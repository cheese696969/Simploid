--!optimize 2
local Config = {
--BASIC CONFIGURATIONS*******************************************************************************************************************************
------------------------------------------------------------------------------------------------------------------------
--DEFAULT ATTRIBUTES: Default simploid object attributes when none are pre-set by you-----------------------------------
------------------------------------------------------------------------------------------------------------------------

	DEFAULT_ATTRIBUTES = {
		Health = 100,
		MaxHealth =	100,
		WalkSpeed = 16,
		JumpHeight = 7.2,
		RootHeight = 3,
	},
	
------------------------------------------------------------------------------------------------------------------------
--DEFAULT RAY PARAMS CONFIGURATION--(Best to change these in a Simploid using :ReplicateProperty())---------------------
------------------------------------------------------------------------------------------------------------------------

	DEFAULT_RAYPARAMS_FILTER_TYPE = Enum.RaycastFilterType.Exclude,
	DEFAULT_RAYPARAMS_IGNORE_WATER = true,
	--Default RayParams FilterDescendantsInstances has the simploid's rig itself inside it by default.
	
------------------------------------------------------------------------------------------------------------------------
--START SETTINGS: Defines starting properties and behavior that should not be changed at runtime------------------------
------------------------------------------------------------------------------------------------------------------------

	--Automatically makes animation dependencies for you: like the built in :LoadAnimation(), animation controllers and animator for each Simploid
	SETUP_ANIMATOR = true,

	--If Simploids can use the built in pathfinding method
	CAN_PATHFIND = true,

		--If module should warn you if Simploid is trying to exit a stuck point
		PATHFINDING_STUCK_MESSAGE_ENABLED = true,

	--If Simploids can use the built in jump method
	CAN_JUMP = true,

	--If Simploids can use the built in wander method
	CAN_WANDER = true,

	--Activates per frame checks : Simploids will have an accurate positioning and grounding per frame when idle, adds extra load
	--More performative and efficient performance on false but rigs sometimes might look like they are flying when no object is under them
	CAN_IDLE_RAYCAST_LOOP = true,
	

------------------------------------------------------------------------------------------------------------------------
--MODES: Defines more behaviors-----------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

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
	
--TECHNICAL CONFIGURATIONS***************************************************************************************************************************
------------------------------------------------------------------------------------------------------------------------
--DYNAMICS (Can change all simploid's behavior in runtime when changed in rutime)---------------------------------------
------------------------------------------------------------------------------------------------------------------------

	SERVER_PLAYER_TO_SIMPLOID_TWEEN_DISTANCE = 1000,		--Maximum distance where players should be in so that the tween will play in client 
	SERVER_FALLING_WAIT = 3,								--How long to wait to recheck if npc is still falling

	--PathfindService Config
	BASE_WAYPOINT_SPACING = math.huge,						--Pathfind waypoint spacing
	SIMPLOID_RADIUS_ADDITIVE = 4,							--Adds an extra agent radius for npc pathfinds
	SIMPLOID_HEIGHT_ADDITIVE = 1,							--Adds an extra agent height for npc pathfinds

	SIMPLOID_RAGDOLL_TIME = 10,								--Time to wait for npc character to not be completely destroyed for a ragdoll
	RAY_EXIT_DIST = 3,										--How far to check for exits (When npc is stuck)
	
------------------------------------------------------------------------------------------------------------------------
--CONSTANTS (These are cached by user scripts. Cannot and should not be changed in runtime, for better efficiency)------
------------------------------------------------------------------------------------------------------------------------

	RAY_DOWN_DIST = 20,										--How far to check for npc grounding (So npc does not look like it's flying). Once this distance gets bypassed by npc, falling begins
	PATHFINDING_RAY_CHECK_ITERATIONS = 4,					--The higher the number is, the more accurate the position of weird roblox pathfinding point corrections
	WAYPOINT_Y_OFFSET = 0.5, 								--Adds an offset to the Y value of waypoints (Prechecked by me, don't change if you don't have to)
	--ROOT_TO_SIMPLOID_UPDATE_DIST = 200,					--If simploid is within this distance from the player, it will ground the npc's position
	SIMPLOID_FALL_THROTTLE = 3,								--If simploid goes to falling state, it will wait this long to resend a fall update to server
	
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
	},

	--Debug Configs			
	DEBUG_PATHFINDING_POINTS = false,						--If true, Shows pathfinding waypoints: 
																--[[
																BLUE CIRCLES= waypoints returned by roblox pathfinding, 
																WHITE CIRCLES = created correction waypoint
																]]

	DEBUG_PATHFINDING_RAYS = false,							--If true, Shows pathfinding correction raycasts: 
																--[[
																RED RAY = SIGHT BLOCKED,
																GREEN RAY = SIGHT CLEAR, 
																YELLOW RAY = HIGH BECOMES MIDDLE,
																PINK RAY = LOW BECOMES MIDDLE
																]]
}


return Config
