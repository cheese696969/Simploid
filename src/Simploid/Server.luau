--!optimize 2
--SERVER SIMPLOID CLASS HELPER

--Module Dependencies: Change path if wanted
local simploid = script.Parent
local ReplicatedTween = require(simploid.ReplicatedTween)
local Config = require(simploid.Config)
local Utils = require(simploid.Utils)

--Storage
local REPLICATED_PROPERTIES = Config.REPLICATED_PROPERTIES
local Terrain = workspace.Terrain
local ReplicationRemote:RemoteEvent = simploid:WaitForChild("ReplicationRemote")

--Terain helping variables
local RESOLUTION = 4 					-- voxel resolution (4x4x4 studs)
local HALF = Vector3.new(1, 1, 1) 		--Initial terrain region check size

--********************************************************************************************************
--SERVER SIMPLOID HELPER METHODS
--********************************************************************************************************
return function(Simploid)
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
	
	--Sets Simploid attribute (REPLICATES)
	function Simploid:SetAttribute(attributeName:string, value:any)
		self.Character:SetAttribute(attributeName, value)
	end

	--Gets Simploid attribute
	function Simploid:GetAttribute(attributeName:string) : any
		return self.Character:GetAttribute(attributeName)
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

		-- Special case for RayDownParams
		local sendValue = value
		if propertyName == "RayDownParams" and typeof(value) == "RaycastParams" then
			-- Serialize the RaycastParams before sending to clients
			sendValue = Utils.RayParamsSerialize(value)
		end

		self[propertyName] = value
		ReplicationRemote:FireAllClients(self:GetAttribute("Id"), propertyName, sendValue)
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
		
		local tween = ReplicatedTween:Construct(self.AnchoredRoot, tweenTime, nextPosition, nil, speed)
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

	--Pathfind an Simploid along a path
	function Simploid:PathfindTo(targetPosition:Vector3)
		assert(targetPosition, "No goal Vector3 given!")
		if not self.NormalState or self.Motion ~= "None" then return end
		
		local path : Path | Vector3? = self:_computePath(targetPosition)
		if not path then return end
		
		self.Motion = "Pathfinding"
		
		if typeof(path) == "Instance" and path:IsA("Path") then
			self.MotionTarget = targetPosition
			local waypoints = path:GetWaypoints()
			
			for i, point:PathWaypoint in ipairs(waypoints) do
				if i == 1 then continue end	
				if not self.NormalState then break end

				if point and point.Action == Enum.PathWaypointAction.Jump then
					task.defer(function()
						self:Jump()
					end)
				end
				
				local completed = self:MoveTo(point.Position)

				if not completed then 
					if self.JumpSignal then
						self.JumpSignal:Wait()
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
		
		self.Motion = "None"
		self.MotionTarget = nil
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
		
		-- Set Position if simploid is moving
		self:SetTimedPosition()

		-- Compute jump physics
		local tweenTime = 2 * math.sqrt((2 * jumpHeight) / workspace.Gravity)
		local range = lastSpeed * tweenTime
		local predictedLanding = AnchoredRoot.Position + direction * range
		predictedLanding = Vector3.new(predictedLanding.X, AnchoredRoot.Position.Y, predictedLanding.Z)

		-- Create jump tween
		local tween = ReplicatedTween:Construct(AnchoredRoot, tweenTime, predictedLanding, jumpHeight, lastSpeed)
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
	end
	
	--Method on death
	function Simploid:Death()
		self:SetAttribute("State", "Dead")
		self:_cancelMoveTo()

		self.Janitor:Cleanup()
		
		task.wait(Config.SIMPLOID_RAGDOLL_TIME + 1)
		self:Destroy()
	end

	--Cleanup method
	function Simploid:Destroy()
		self.Janitor:Destroy()
		self.Character:Destroy()
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

	--function Simploid:ShowPoint(point:Vector3, color:Color3) : nil
	--	local part = Instance.new("Part")
	--	part.Shape = Enum.PartType.Ball
	--	part.Material = Enum.Material.Neon
	--	part.Position = point
	--	part.Size = Vector3.new(1,1,1)
	--	part.Color = color or Color3.new(1, 1, 1)
	--	part.Anchored = true
	--	part.CanTouch = false
	--	part.CanCollide = false
	--	part.CanQuery = false

	--	task.defer(function()
	--		task.wait(50)
	--		part:Destroy()
	--	end)
	--	part.Parent = workspace
	--end

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
			character:PivotTo(CFrame.new(nextPosition))
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
			character:PivotTo(CFrame.new(nextPosition))
		end

		if result then return end
		if self:_isInsideTerrain() then return end

		self.NormalState = false
		AnchoredRoot.CanCollide = true
		AnchoredRoot.Anchored = false
		AnchoredRoot:SetNetworkOwner(nil)

		while true do
			task.wait(Config.SERVER_FALLING_WAIT)
			result = self:_castGroundCheck()
			if result then
				character:PivotTo(CFrame.new(result.Position + self.HeightAdditive))
				AnchoredRoot.CanCollide = false
				AnchoredRoot.Anchored = true
				self.NormalState = true
				break
			end
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
		
		warn("SIMPLOID IS STUCK WITHOUT EXIT POINTS! | RECALCULATING PATH...")
		return nil
	end

	--Pathfinds and returns a path to a target position
	function Simploid:_computePath(targetPosition:Vector3) : (Path | Vector3)?
		assert(targetPosition, "No goal Vector3 given!")
		local path = self.Path
		if not path then 
			warn("Path object required! | Create one and set it to the simploid.") 
			return 
		end
			
		local success, _ = pcall(function()
			path:ComputeAsync(self.HumanoidRootPart.Position, targetPosition)
		end)

		if success and path.Status == Enum.PathStatus.Success then
			return path
		else
			return self:_getExitErrorPoint()
		end
	end
end
