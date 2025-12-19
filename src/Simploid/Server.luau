--!optimize 2
--SERVER SIMPLOID CLASS HELPER
if not game:GetService("RunService"):IsServer() then return nil end

--Module Dependencies: Change path if wanted
local simploid = script.Parent
local ReplicatedTween = require(simploid.ReplicatedTween)
local Config = require(simploid.Config)
local Utils = require(simploid.Utils)

--Storage
local REPLICATED_PROPERTIES = Config.REPLICATED_PROPERTIES
local serverPropertyCache = ReplicatedTween.ServerPropertyCache
local serverActiveSimploids = ReplicatedTween.ServerActiveSimploids
local Terrain = workspace.Terrain
local ReplicationRemote:RemoteEvent = simploid:WaitForChild("ReplicationRemote")

--Terain helping variables
local RESOLUTION = 4 					-- voxel resolution (4x4x4 studs)
local HALF = Vector3.new(1, 1, 1) 		--Initial terrain region check size
local DEBUG_PATHFINDING_RAYS = Config.DEBUG_PATHFINDING_RAYS
local DEBUG_PATHFINDING_POINTS = Config.DEBUG_PATHFINDING_POINTS
local ITERATIONS = Config.PATHFINDING_RAY_CHECK_ITERATIONS

--Debug Functions
local function showPoint(position:Vector3, color:Color3?)
	if not DEBUG_PATHFINDING_POINTS then return end
	local part = Instance.new("Part")
	part.Color = color or Color3.new(0.07451, 0.109804, 0.8)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Position = position
	part.Size = Vector3.new(1,1,1)
	part.Shape = Enum.PartType.Ball
	part.Parent = workspace
	task.defer(function()
		task.wait(10)
		part:Destroy()
	end)
end
	
local function drawRay(origin: Vector3, direction: Vector3, color: Color3)
	if not DEBUG_PATHFINDING_RAYS then return end

	local length = direction.Magnitude
	if length <= 0 then return end

	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = Vector3.new(0.1, 0.1, length)
	part.CFrame = CFrame.lookAt(
		origin + direction * 0.5,
		origin + direction
	)
	part.Parent = workspace

	-- Auto cleanup
	game:GetService("Debris"):AddItem(part, 10)
end


--********************************************************************************************************
--SERVER SIMPLOID HELPER METHODS
--********************************************************************************************************
return function(Simploid)
	--Sets Simploid attribute (REPLICATES)
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
	
	--Changes a property on both the server and client (Property must be one that is listed in Config.REPLICATED_PROPERTIES)
	function Simploid:ReplicateProperty(propertyName: string, value: any)
		assert(propertyName, "The property's name to be replicated is needed!")
		local expectedType = REPLICATED_PROPERTIES[propertyName]

		if not expectedType then
			warn("The property ".. propertyName .." does not exist or is not replicated! || ReplicateProperty cancelled.")
			return
		end

		local actualType = typeof(value)
		if actualType ~= expectedType then
			error(string.format(
				"ReplicateProperty failed: Expected '%s' but got '%s' for property '%s'",
				tostring(expectedType), tostring(actualType), propertyName
				))
			return
		end
		
		self[propertyName] = value

		-- Special case for RayDownParams
		if propertyName == "RayDownParams" and typeof(value) == "RaycastParams" then
			-- Serialize the RaycastParams before sending to clients
			value = Utils.RayParamsSerialize(value)
		end

		serverPropertyCache[self.Character] = serverPropertyCache[self.Character] or {}
		serverPropertyCache[self.Character][propertyName] = value

		ReplicationRemote:FireAllClients(self:GetAttribute("Id"), propertyName, value)
	end

	--Move an Simploid to a point
	function Simploid:MoveTo(targetPosition:Vector3?) : boolean
		assert(targetPosition, "No goal Vector3 given!")
		if self.CurrentTween and not self.CurrentTween.IsJump then 
			self.CurrentTween:Cancel() 
		end
		
		self:SetAttribute("State", "Running")

		local character = self.Character
		local speed = self:GetAttribute("WalkSpeed")

		local nextPosition =  targetPosition + Vector3.new(0, self.WaypointHeight, 0)
		local pastPosition = self.AnchoredRoot.Position
		local pastTime = time()
		local tweenTime = self:_calculateTime(speed, pastPosition, nextPosition)
		
		if Config.MOVEMENT_LOOK_MODE == "XZ" then
			character:PivotTo(CFrame.lookAt(pastPosition, Vector3.new(nextPosition.X, pastPosition.Y, nextPosition.Z)))
		elseif Config.MOVEMENT_LOOK_MODE == "XYZ" then
			character:PivotTo(CFrame.lookAt(pastPosition, nextPosition))
		end
		
		local tween = ReplicatedTween.Construct(self.AnchoredRoot, tweenTime, nextPosition, nil, speed)
		tween:Play(Config.SERVER_PLAYER_TO_SIMPLOID_TWEEN_DISTANCE)

		self.CurrentTween = tween
		self.CurrentTweenTime = tweenTime
		self.CurrentPastTime = pastTime
		self.CurrentPastPosition = pastPosition
		self.CurrentNextPosition = nextPosition

		local completed = false
		tween.Completed:Once(function(isCompleted)
			if isCompleted then
				completed = true
				self.CurrentTween = nil
				self:_updatePosition(nextPosition)
			else	
				self:_updatePosition(self:_getTimedPosition())
				self.CurrentTween = nil
			end
		end)
		tween.Completed:Wait()
		task.wait()
		return completed
	end

	if Config.CAN_PATHFIND then
		--Pathfind an Simploid along a path
		function Simploid:PathfindTo(targetPosition:Vector3)
			assert(targetPosition, "No goal Vector3 given!")
			if not self.NormalState or self.Motion ~= "None" then return end
			
			local path : {PathWaypoint} | Vector3? = self:_computePath(targetPosition)
			if not path then return end
			
			self.Motion = "Pathfinding"
			
			if typeof(path) == "table" then
				self.MotionTarget = targetPosition
				
				if DEBUG_PATHFINDING_POINTS then
					for _, point in path do
						showPoint(point.Position)
					end
				end

				for i, point in path do
					if i == 1 then continue end	
					if not self.NormalState then break end

					if point and point.Action == Enum.PathWaypointAction.Jump then
						task.defer(function()
							self:Jump()
						end)
					end
					
					local completed = self:MoveTo(point.Position)

					if not completed then 
						if self.Signal then
							self.Signal:Wait()
							continue
						end
						break
					end
				end
			elseif typeof(path) == "Vector3" then
				if self.NormalState then
					self:MoveTo(path)
					task.wait()
				end
			end
			
			self:SetAttribute("State", "Idle")
			self.Motion = "None"
			self.MotionTarget = nil
		end
	end
	
	--Updates the position of the Simploid based on the time of movement
	function Simploid:SetTimedPosition()
		if not self.CurrentTween then return end
		if self.CurrentTween.IsJump then
			self:_updatePosition(self:_getJumpPosition())
		else
			self:_updatePosition(self:_getTimedPosition())
		end
	end

	if Config.CAN_JUMP then
		--Makes the simploid character jump
		function Simploid:Jump()
			if self:GetAttribute("State") == "Jumping" then return end
			local current = self.CurrentTween
			if current and current.IsJump then return end
			
			self:SetAttribute("State", "Jumping")

			-- Base motion setup
			local AnchoredRoot = self.AnchoredRoot
			local jumpHeight = self:GetAttribute("JumpHeight")
			local lastSpeed = current and current.Speed or 0
			local goal = current and current.Goal or nil
			local direction = current and (goal - AnchoredRoot.Position).Unit or AnchoredRoot.CFrame.LookVector
			current:Cancel(true)
			
			-- Set Position if simploid is moving
			self:SetTimedPosition()
			self.Signal = self.JumpSignal

			-- Compute jump physics
			local tweenTime = 2 * math.sqrt((2 * jumpHeight) / workspace.Gravity)
			local range = lastSpeed * tweenTime
			local predictedLanding = AnchoredRoot.Position + direction * range
			predictedLanding = Vector3.new(predictedLanding.X, AnchoredRoot.Position.Y, predictedLanding.Z)

			-- Create jump tween
			local tween = ReplicatedTween.Construct(AnchoredRoot, tweenTime, predictedLanding, jumpHeight, lastSpeed)
			tween.IsJump = true

			-- Store state
			self.CurrentTween = tween
			self.CurrentTweenTime = tweenTime
			self.CurrentPastPosition = AnchoredRoot.Position
			self.CurrentNextPosition = predictedLanding
			
			tween:Play(Config.SERVER_PLAYER_TO_SIMPLOID_TWEEN_DISTANCE)
			
			tween.Completed:Wait()
			self.CurrentTween = nil
			self:_updatePosition(predictedLanding)
			self:SetAttribute("State", "Running")
			self.JumpSignal:Fire()
			self.Signal = nil
		end
	end
	
	if Config.CAN_WANDER then
		--Wander Method for testing
		function Simploid:Wander(range: number)
			range = range or 50
			task.defer(function()
				while true do
					if self:GetAttribute("State") ~= "Running" then 
						task.wait(1) 
						continue 
					end

					-- get Simploid's current position
					local origin = self.HumanoidRootPart.Position
					-- pick a random point within the given range
					local randomX = origin.X + (math.random() - 0.5) * 2 * range
					local randomZ = origin.Z + (math.random() - 0.5) * 2 * range
					local point = Vector3.new(randomX, origin.Y, randomZ)

					-- pathfind to that point
					self:PathfindTo(point)

					task.wait(1)
				end
			end)
		end
	end

	--Method on death
	function Simploid:Death()
		self:_cancelMoveTo()
		self:SetAttribute("State", "Dead")

		self.Janitor:Cleanup()
		
		task.wait(Config.SIMPLOID_RAGDOLL_TIME + 1)
		self:Destroy()
	end

	--Cleanup method
	function Simploid:Destroy()
		local character = self.Character
		self:_cancelMoveTo()
		
		serverActiveSimploids[character] = nil
		serverPropertyCache[character] = nil

		self.Janitor:Destroy()
		character:Destroy()
		self = nil
	end
	
	
	
	






	
--****************************************************************************************************************************	
--PROTECTED METHODS : RECOMMENDED TO NOT MESS WITH THESE METHODS UNLESS YOU KNOW WHAT YOU'RE DOING--
--****************************************************************************************************************************
	
	--Gets position at current tween time
	function Simploid:_getTimedPosition() : Vector3
		local direction = (self.CurrentNextPosition - self.CurrentPastPosition).Unit
		local distance = self.CurrentTween.Speed * (time() - self.CurrentPastTime)
		return self.CurrentPastPosition + direction * distance
	end
	
	function Simploid:_getJumpPosition() : Vector3
		local g = workspace.Gravity
		local v0 = math.sqrt(2 * g * self:GetAttribute("JumpHeight"))
	
		-- Clamp to duration
		self.CurrentPastTime = self.CurrentPastTime or 0
		local t = math.clamp(time() - self.CurrentPastTime , 0, self.CurrentTweenTime)

		-- Normalized horizontal alpha
		local alpha = t / self.CurrentTweenTime
		local horizontal = self.CurrentPastPosition:Lerp(self.CurrentNextPosition, alpha)

		-- Compute vertical offset under gravity
		local yOffset = v0 * t - 0.5 * g * t * t

		return Vector3.new(horizontal.X, self.CurrentPastPosition.Y + yOffset, horizontal.Z)
	end
	
	--Calculates tween time based on given speed
	function Simploid:_calculateTime(speed:number, pastPos:Vector3, nextPos:Vector3) : number
		local distance = (pastPos - nextPos).Magnitude
		return distance / speed
	end

	--Cast ray to check the ground
	function Simploid:_castGroundCheck() : RaycastResult?
		return workspace:Raycast(
			self.AnchoredRoot.Position + self.HeightAdditive,					--ORIGIN
			self.RayDirection,													--DIRECTION
			self.RayDownParams)													--RAY PARAMS
	end

	--Checks if the Simploid is inside terrain
	function Simploid:_isInsideTerrain() : boolean
		local pos = self.AnchoredRoot.Position
		local material = Terrain:ReadVoxels(Region3.new(pos - HALF, pos + HALF):ExpandToGrid(RESOLUTION), RESOLUTION)[1][1][1]
		-- If material isn’t Air, it's inside terrain
		return material ~= Enum.Material.Air
	end

	--Forces the Simploid to calculate where it is and position it in that current moment of time
	function Simploid:_cancelMoveTo()
		if self.CurrentTween then
			self.CurrentTween:Cancel()
		end
	end
	
	--Forces the Simploid to calculate where it is and position it in that current moment of time, with a fall timer constraint
	function Simploid:_cancelMoveTo_FallConstrained()
		if not self.CanFallUpdate then return end
		self.CanFallUpdate = false
		self:_cancelMoveTo()
		task.wait(Config.SIMPLOID_FALL_THROTTLE)
		self.CanFallUpdate = true
	end

	--Updates the position of the Simploid
	function Simploid:_updatePosition(nextPosition:Vector3)
		local AnchoredRoot:BasePart = self.AnchoredRoot
		local character:Model = self.Character
		
		if self.CurrentTween and self.CurrentTween.IsJump then
			character:PivotTo(CFrame.new(nextPosition) * AnchoredRoot.CFrame.Rotation)
			return
		end
		
		local result = workspace:Raycast(
			nextPosition + self.HeightAdditive,	
			self.RayDirection,			
			self.RayDownParams)

		if result then
			local p = result.Position + self.HeightAdditive
			self.CurrentPastPosition = p
			self.CurrentPastTime = time()
			character:PivotTo(CFrame.new(p) * AnchoredRoot.CFrame.Rotation)
		else
			character:PivotTo(CFrame.new(nextPosition + self.HeightAdditive + self.RayDirection) * AnchoredRoot.CFrame.Rotation)
		end

		if result then return end
		if self:_isInsideTerrain() then return end

		self:SetAttribute("State", "Falling")
		self.NormalState = false
		AnchoredRoot.CanCollide = true
		AnchoredRoot.Anchored = false
		AnchoredRoot:SetNetworkOwner(nil)

		while true do
			result = self:_castGroundCheck()
			if result then
				character:PivotTo(CFrame.new(result.Position + self.HeightAdditive))
				AnchoredRoot.CanCollide = false
				AnchoredRoot.Anchored = true
				self.NormalState = true
				self:SetAttribute("State", "Idle")
				break
			elseif not character.Parent then
				break
			end
			task.wait(Config.SERVER_FALLING_WAIT)
		end
	end

	--Runs a check to find an exit from a pathfind error spot
	function Simploid:_getExitErrorPoint() : Vector3?
		local origin = self.AnchoredRoot.Position
		local dir = Config.DIRECTIONS[math.random(1, 8)]
		local rayDirection = dir * Config.RAY_EXIT_DIST
		local result = workspace:Raycast(origin, rayDirection, self.RayDownParams)

		if not result then
			return (origin + rayDirection) - Vector3.new(0, self.WaypointHeight, 0)
		end
		
		if not Config.PATHFINDING_STUCK_MESSAGE_ENABLED then return end 
		warn("SIMPLOID IS STUCK WITHOUT EXIT POINTS! | RECALCULATING PATH...")
		return nil
	end

	--Pathfinds and returns a path to a target position
	function Simploid:_computePath(targetPosition:Vector3) : ({PathWaypoint} | Vector3)?
		assert(targetPosition, "No goal Vector3 given!")
		local path:Path = self.Path
		if not path then
			warn("Path object required! | Create one and set it to the simploid.") 
			return 
		end
			
		local success, _ = pcall(function()
			path:ComputeAsync(self.HumanoidRootPart.Position, targetPosition)
		end)

		if success and path.Status == Enum.PathStatus.Success then
			local waypoints = path:GetWaypoints()
			local processedPoints = {}

			-- Always keep the first waypoint
			table.insert(processedPoints, waypoints[1])

			for i = 1, #waypoints - 1 do
				local currentPos = waypoints[i].Position
				local nextPoint = waypoints[i+1]
				local nextPos = nextPoint.Position

				-- Flat direction (XZ only)
				local direction = nextPos - currentPos
				local dist = direction.Magnitude
				if dist == 0 then
					table.insert(processedPoints, nextPoint)
					continue
				end

				-- Check if path is blocked
				local blocked = workspace:Raycast(
					currentPos,
					direction,
					self.RaycastDownParams
				)

				if not blocked then
					-- Path clear: keep original next waypoint
					table.insert(processedPoints, nextPoint)
					continue
				end

				drawRay(
					currentPos,
					direction,
					blocked and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(0, 255, 0)
				)

				-- Blocked: move NEXT backward toward POINT
				-- XZ-only direction
				local isAbove = nextPos.Y >= currentPos.Y
				local flatDir = Vector3.new(
						nextPos.X - currentPos.X,
						0,
						nextPos.Z - currentPos.Z
					)

				local unitDir = flatDir.Unit
				local low = 0
				local high = dist

				for _i = 1, ITERATIONS do
					task.wait(0.5)
					local mid = (low + high) * 0.5

					local testPos

					if isAbove then
						testPos = Vector3.new(
							nextPos.X - unitDir.X * mid,
							nextPos.Y, -- Y LOCKED
							nextPos.Z - unitDir.Z * mid
						)
					else
						testPos = Vector3.new(
							nextPos.X - unitDir.X * mid,
							currentPos.Y, -- Y LOCKED
							nextPos.Z - unitDir.Z * mid
						)
					end

					local testDir
					local hit

					if isAbove then 
						testDir = testPos - currentPos
						hit = workspace:Raycast(
							currentPos,
							testDir,
							self.RaycastDownParams
						)
					else
						testDir = nextPos - testPos
						hit = workspace:Raycast(
							testPos,
							testDir,
							self.RaycastDownParams
						)
					end
					if hit then
						if isAbove then 
							low = mid
								
							drawRay(
								currentPos,
								testDir,
								Color3.fromRGB(255, 0, 251)
							)
						else
							if _i == 1 then
								low = mid
							else
								high = mid	
							end
							
								
							drawRay(
								testPos,
								testDir,
								Color3.fromRGB(221, 255, 1)
							)
						end
					else
						if isAbove then
							high = mid
					
							drawRay(
								currentPos,
								testDir,
								Color3.fromRGB(221, 255, 1)
							)

						else
							low = mid
								
							drawRay(
								testPos,
								testDir,
								Color3.fromRGB(255, 0, 251)
							)
						end
					end
				end

				local newPoint = {
					Position = Vector3.new(
					nextPos.X - unitDir.X * high,
					isAbove and nextPos.Y or currentPos.Y,
					nextPos.Z - unitDir.Z * high
					),
					Action = Enum.PathWaypointAction.Walk,
				}

				showPoint(newPoint.Position, Color3.fromRGB(255, 255, 255))
				table.insert(processedPoints, newPoint)
				table.insert(processedPoints, nextPoint)
			end
			
			return processedPoints
		else
			return self:_getExitErrorPoint()
		end
	end
end
