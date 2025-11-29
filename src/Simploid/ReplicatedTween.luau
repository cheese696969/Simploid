--!optimize 2

--[[
[FORKED] TweenService+ V1.1
@rek_kie on 8/9/20

For the original TweenService+, Please read the devforum post here!
https://devforum.roblox.com/t/tweenservice-plus/716025


Forked by @cheesyhuman2
This is a heavily forked version of the original TweenService+ by @rek_kie, and is now specially used for simploid handling, 
do not use for scripts outside the simploid module.
]]
--

--Services
local Players = game.Players
local Stats = game.Stats
local RunService = game:GetService("RunService")

--Module Dependencies
local Goodsignal = require(script.Parent.Packages.Goodsignal)
local clock = require(script.Parent.SyncedTime)
local Config = require(script.Parent.Config)

--Module Table
local tweenService = {}

--Config
local THRESHOLD = 0
local DEFAULT_RANGE = Config.SERVER_PLAYER_TO_SIMPLOID_TWEEN_DISTANCE
local SIMPLOID_FALL_THROTTLE = Config.SIMPLOID_FALL_THROTTLE

--Lerped tween type definition
type LerpedTween = {
	NormalType: boolean,
	Object: BasePart,
	Start: Vector3,
	Goal: Vector3,
	PastTime: number,
	Duration: number,

	JumpHeight: number?,
	Gravity: number?,
	HalfDuration: number,

	Cancel: (self: Tween) -> nil,
}

type ServerLerpedTween = {
	IsCancelled: boolean,
	Completed: any,
	IsJump: boolean,
	Goal: Vector3,
	Speed: number,
}

if RunService:IsServer() then
	local FallRemote = Instance.new("RemoteEvent")
	FallRemote.Name = "FallRemote"
	FallRemote.Parent = script.Parent

	--Server to Client Tween RemoteEvent
	local TweenRemote = Instance.new("RemoteEvent")
	TweenRemote.Name = "TweenRemote"
	TweenRemote.Parent = script

	if not clock:IsSynced() then -- make sure our clock is synced
		repeat
			clock:Sync()
			task.wait(0.5)
		until clock:IsSynced()
	end
end

local TweenRemote = script:WaitForChild("TweenRemote")

function tweenService:Construct(object: BasePart?, tweenTime: number?, position: Vector3?, jumpHeight: number?, speed: number?) : ServerLerpedTween
	if not object then
		error("Object doesn't exist.")
	end

	self = {
		["IsCancelled"] = false,
		["Completed"] = Goodsignal.new(),

		["IsJump"] = (jumpHeight or 0) > 0,
		["Goal"] = position,
		["Speed"] = speed,
	}

	local function tweenWait(n)
		n = n or 1 / 30
		local now = tick()
		repeat
			RunService.Heartbeat:Wait()
			if self.IsCancelled == true then
				return true
			end
		until tick() - now >= n
		return
	end

	local function completionWait(t)
		task.defer(function()
			local cancelled = tweenWait(t)

			if not cancelled then
				self.Completed:Fire(true)
			end

			table.clear(self)
		end)
	end
	
	function self:Play(range)
		if not object or not object:IsA("BasePart") or not object:IsDescendantOf(workspace) then
			warn("The tween object must be a BasePart in the workspace.")
			return
		end
		range = range or DEFAULT_RANGE

		for _, player in Players:GetPlayers() do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")

			if root then
				if (object.Position - root.Position).Magnitude <= range then
					task.defer(function()
						TweenRemote:FireClient(player, object, tweenTime, position, jumpHeight, clock:GetTime())
					end)
				end
			end
		end

		completionWait(tweenTime)
	end

	function self:Cancel(clients)
		if clients then
			clients = (type(clients) == "table") and clients or { clients }

			for _, client in clients do
				TweenRemote:FireClient(client, self.Object)
			end
		else
			TweenRemote:FireAllClients(self.Object)
		end

		self.Completed:Fire(false)
		self.IsCancelled = true
	end

	return self
end

if RunService:IsClient() then
	--Calculates tween time based on given speed
	local function _calculateTime(speed: number, pastPos: Vector3, nextPos: Vector3): number
		local distance = (pastPos - nextPos).Magnitude
		return distance / speed
	end

	local tweens = {}
	local nextFrameUpdate = {}

	local tweenKeys = {} -- array of active tweens
	local tweenIndex = {} -- tween → index
	local rrCursor = 1 -- round-robin cursor

	local FallRemote = script.Parent:WaitForChild("FallRemote")

	-- O(1) add
	local function addTween(tween)
		table.insert(tweenKeys, tween)
		tweenIndex[tween] = #tweenKeys
	end

	-- O(1) remove
	local function removeTween(tween)
		local idx = tweenIndex[tween]
		if not idx then
			return
		end

		local last = tweenKeys[#tweenKeys]

		tweenKeys[idx] = last
		tweenIndex[last] = idx

		tweenKeys[#tweenKeys] = nil
		tweenIndex[tween] = nil
		nextFrameUpdate[tween] = nil

		if rrCursor > #tweenKeys then
			rrCursor = 1
		end
	end

	local function tweenPosition(object: BasePart, goal: Vector3, tweenTime: number, jumpHeight: number): LerpedTween?
		local parent = object.Parent
		if not parent then
			return
		end

		local tween: LerpedTween = {
			Object = object,
			Goal = goal,
			Duration = tweenTime,
			Start = object.Position,
			PastTime = time(),
			NormalType = jumpHeight == 0,
			Cancel = nil, -- required placeholder
			JumpHeight = jumpHeight or 0,
			HalfDuration = nil,
		}

		if jumpHeight > 0 then
			tween.HalfDuration = tweenTime / 2
			tween.Gravity = 2 * jumpHeight / (tween.HalfDuration ^ 2)
		end

		function tween:Cancel()
			removeTween(tween)
			tweens[object] = nil
		end

		tweens[object] = tween
		addTween(tween)
		return tween
	end

	TweenRemote.OnClientEvent:Connect(
		function(object: BasePart, tweenTime: number, position: Vector3, jumpHeight: number, timestamp: number)
			if not tweenTime then
				local tweenToEdit = tweens[object]

				if not tweenToEdit then -- if the tween doesn't exist, just return and give a warning
					--warn("The tween you tried to modify does not exist.")
					return
				end

				tweenToEdit:Cancel()
				return
			end

			local latency = clock:GetTime() - timestamp

			local newTweenTime = tweenTime - latency 
			--[[If enabled, this syncs the tween up based on latency.
			Ex. If the server told a client to do a 10 second tween and it
			took .7 seconds to get to the client, then the time for the
			client's tween would be 10 - .7 = 9.3 seconds.
			I'm using Quenty's module to get a global timestamp, so
			that server and client time are synced. This results in a
			perfect sync between client and server tween completion.
			To better see this for yourself, turn on debug mode and
			look at the output to see how the server prints exactly
			when the client tween ends. (If you are in Studio, Make sure you
			stay watching only on the client though, because switching to
			the server  view pauses the client's game session on Play Solo)

			threshold = threshold or 0 -- Defaults to 0. When you set this, this basically means the amount of time
			the new tween time (after calculating latency) needs to be greater than
			for the tween to play. If the new tween time after calculating latency is less than
			or equal to than the threshold, the tween will not play.]]

			if newTweenTime > THRESHOLD and object and position then -- some checks
				local tween = tweens[object]
				if tween then
					tween:Cancel()
				end
				tweens[object] = tweenPosition(object, position, newTweenTime, jumpHeight)
			end
		end
	)

	local fps = 1 / Stats.FrameTime
	local currentFrame = 0
	local count = #tweenKeys
	local now = time()
	local skipFactor = 1
	local toProcess = 0

	local ActiveSimploids = {}
	tweenService.ActiveSimploids = ActiveSimploids

	RunService.RenderStepped:Connect(function()
		currentFrame += 1
		fps = 1 / Stats.FrameTime
		count = #tweenKeys
		if count == 0 then
			return
		end

		-- Dynamic skip factor
		if fps >= 57 then
			skipFactor = 1
		elseif fps >= 50 then
			skipFactor = 3
		elseif fps >= 40 then
			skipFactor = 6
		elseif fps >= 30 then
			skipFactor = 12
		elseif fps >= 20 then
			skipFactor = 24
		else
			skipFactor = 48
		end

		-- update a fraction each frame (perfect distribution)
		toProcess = math.max(1, math.floor(count / skipFactor))
		now = time()

		for _ = 1, toProcess do
			local tween = tweenKeys[rrCursor]
			rrCursor += 1
			if rrCursor > count then
				rrCursor = 1
			end
			if not tween then
				continue
			end

			-- schedule initialization
			if not nextFrameUpdate[tween] then
				nextFrameUpdate[tween] = currentFrame
			end

			if currentFrame >= nextFrameUpdate[tween] then
				nextFrameUpdate[tween] = currentFrame + skipFactor

				local character: Model? = tween.Object.Parent
				if not character then
					tween:Cancel()
					continue
				end
				local self = ActiveSimploids[character]
				if not self then
					tween:Cancel()
					continue
				end
				local AnchoredRoot: BasePart = self.AnchoredRoot

				-- Compute alpha and position
				local alpha = math.clamp((now - tween.PastTime) / tween.Duration, 0, 1)
				local pos = tween.Start:Lerp(tween.Goal, alpha)

				-- Jump arc
				if not tween.NormalType then
					local t = alpha * tween.Duration
					local timeFromPeak = math.abs(t - tween.HalfDuration)
					local yOffset = tween.JumpHeight - 0.5 * tween.Gravity * (timeFromPeak ^ 2)
					pos = Vector3.new(pos.X, pos.Y + yOffset, pos.Z)
				else
					local result = workspace:Raycast(pos + self.HeightAdditive, self.RayDirection, self.RayDownParams)

					if result then
						pos = result.Position + self.HeightAdditive
					else
						self.AnchoredRootWeld.C0 = CFrame.identity
						if not self.CanFallUpdate then
							return
						end

						self.CanFallUpdate = false
						FallRemote:FireServer(self.Character)
						task.wait(SIMPLOID_FALL_THROTTLE)
						self.CanFallUpdate = true
					end
				end

				character:PivotTo(CFrame.new(pos) * AnchoredRoot.CFrame.Rotation)

				-- end tween
				if alpha >= 1 then
					tween:Cancel()
					count = #tweenKeys
				end
			end
		end
	end)
end

return tweenService
