--!nocheck

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reach = ReplicatedStorage:WaitForChild("Constants"):WaitForChild("Melee"):WaitForChild("Reach")

local CONFIG = {
	DETECTION_DISTANCE = 1000,
	AIM_SPEED = 2.5,
	AIM_ACCURACY = 100,
  
	ACTIVE = true,
  TELEPORT_MODE = false,
	WALL_DETECTION = true,
	EXCLUDE_NPCS = false,
	EXCLUDE_PLAYERS = false,
	EXCLUDE_TEAMMATES = true,
  
	TOGGLE_KEY = Enum.KeyCode.E,
  TELEPORT_TOGGLE_KEY = Enum.KeyCode.Q,
  
	ACTION_NAME = "ToggleAimston",
  
	RETARGET_INTERVAL = 5,
	REACH = 15,
  
	COMBO_THRESHOLD = 3,
	COMBO_REACH = 20,
	COMBO_AIM_SPEED = 5,
	COMBO_ZIGZAG_FREQUENCY = 2,
	COMBO_ZIGZAG_AMPLITUDE = 2,
	COMBO_DISTANCE = 3,
  
	ZIGZAG_FREQUENCY = 7,
	ZIGZAG_AMPLITUDE = 3,
  
	JUMP_COOLDOWN = 0.1,
  
	TARGET_DISTANCE = 4,
  
	MAX_VERTICAL_DISTANCE = 20,
  
	SIDESTEP_COOLDOWN = 0.5,
  
	ESCAPE_COOLDOWN = 2,
  
	CLICK_RANGE = 5,
  
	CPS = 15,
  
	CPS_VARIATION = 5,

	TELEPORT_ACTION_NAME = "ToggleTeleportMode",
	TELEPORT_PATTERN = {
		AWAY_DISTANCE = 50,
		RETURN_DISTANCE = 2,
		COOLDOWN = 0.2
	}
}

local LP = Players.LocalPlayer
local camera = workspace.CurrentCamera
local target, lastJump, lastRetarget, lastMove, lastSidestep, lastEscape, lastTeleport = nil, 0, 0, 0, 0, 0, 0
local hitCount, lastHit, maneuvering, inCombo = 0, 0, false, false
local hitTimes = {}
local originalZigzagFrequency = CONFIG.ZIGZAG_FREQUENCY
local originalZigzagAmplitude = CONFIG.ZIGZAG_AMPLITUDE
local lastClick = 0

local function isVisible(tgt)
	if not LP.Character or not tgt then return false end
	local origin = LP.Character.PrimaryPart.Position
	local dest = tgt.PrimaryPart.Position
	local dir = (dest - origin).Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {LP.Character}
	local result = workspace:Raycast(origin, dir * (dest - origin).Magnitude, params)
	return not result or (result.Instance:IsDescendantOf(tgt) or result.Instance.Transparency ~= 0)
end

local function isSitting(tgt)
	return tgt:FindFirstChildOfClass("Humanoid") and tgt:FindFirstChildOfClass("Humanoid").Sit
end

local function getWalkSpeed(tgt)
	return tgt:FindFirstChildOfClass("Humanoid") and tgt:FindFirstChildOfClass("Humanoid").WalkSpeed or 0
end

local function getTarget()
	local closest, dist = nil, CONFIG.DETECTION_DISTANCE
	for _, model in pairs(workspace:GetDescendants()) do
		if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") and model ~= LP.Character then
			local part = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
			if part then
				local d = (part.Position - LP.Character.PrimaryPart.Position).Magnitude
				local vd = math.abs(part.Position.Y - LP.Character.PrimaryPart.Position.Y)
				if d > dist or vd > CONFIG.MAX_VERTICAL_DISTANCE then
					continue
				end
				local plr = Players:GetPlayerFromCharacter(model)
				if (plr and CONFIG.EXCLUDE_PLAYERS) or (not plr and CONFIG.EXCLUDE_NPCS) or (plr and CONFIG.EXCLUDE_TEAMMATES and plr.Team == LP.Team) then
					continue
				end
				if not CONFIG.WALL_DETECTION or isVisible(model) or d <= 20 then
					closest, dist = model, d
				end
			end
		end
	end
	return closest
end

local function getAimPart(tgt)
	if not tgt or not tgt:FindFirstChild("Humanoid") then return nil end
	local parts = {
		Head = tgt:FindFirstChild("Head"),
		Torso = tgt:FindFirstChild("UpperTorso") or tgt:FindFirstChild("Torso"),
		Legs = tgt:FindFirstChild("LeftLeg") or tgt:FindFirstChild("RightLeg") or tgt:FindFirstChild("LeftFoot") or tgt:FindFirstChild("RightFoot")
	}
	local diff = camera.CFrame.Position.Y - tgt.PrimaryPart.Position.Y
	return diff > 2 and (parts.Head or parts.Torso) or diff < -2 and (parts.Legs or parts.Torso) or (parts.Torso or parts.Head)
end

local function aimlock()
	if CONFIG.ACTIVE and target and target.PrimaryPart then
		local part = getAimPart(target)
		if part then
			local pos = (part.Position or part:GetPivot().Position)
			local inaccuracy = (100 - CONFIG.AIM_ACCURACY) / 100
			local offset = Vector3.new(
				math.random(-10, 10) * inaccuracy / 100,
				math.random(-10, 10) * inaccuracy / 100,
				math.random(-10, 10) * inaccuracy / 100
			)
			local cf = CFrame.new(camera.CFrame.Position, pos + offset)
			camera.CFrame = camera.CFrame:Lerp(cf, CONFIG.AIM_SPEED / 10)
		end
	end
end

local function isFirstPerson()
	return LP.CameraMode == Enum.CameraMode.LockFirstPerson or (LP.Character and LP.Character:FindFirstChild("Head") and (camera.CFrame.Position - LP.Character.Head.Position).Magnitude <= 1)
end

local function resetCombo()
	inCombo = false
	Reach.Value = CONFIG.REACH
	CONFIG.AIM_SPEED = 2.2
	CONFIG.ZIGZAG_FREQUENCY = originalZigzagFrequency
	CONFIG.ZIGZAG_AMPLITUDE = originalZigzagAmplitude
	hitCount = 0
	hitTimes = {}
end

local function checkHit(desc)
	if desc:IsA("BodyForce") or desc:IsA("BodyVelocity") or desc:IsA("BodyThrust") or desc:IsA("ParticleEmitter") or desc:IsA("Sparkles") or desc:IsA("Highlight") then
		local now = workspace.DistributedGameTime
		table.insert(hitTimes, now)
		while #hitTimes > 0 and now - hitTimes[1] > 10 do
			table.remove(hitTimes, 1)
		end
		if #hitTimes >= 3 then
			resetCombo()
			return true
		end
		hitCount = now - lastHit < 0.5 and hitCount + 1 or 1
		lastHit = now
		if hitCount >= CONFIG.COMBO_THRESHOLD then
			inCombo = true
			Reach.Value = CONFIG.COMBO_REACH
			CONFIG.AIM_SPEED = CONFIG.COMBO_AIM_SPEED
			CONFIG.ZIGZAG_FREQUENCY = CONFIG.COMBO_ZIGZAG_FREQUENCY
			CONFIG.ZIGZAG_AMPLITUDE = CONFIG.COMBO_ZIGZAG_AMPLITUDE
			return true
		end
	end
	return false
end

local function detectCombo(char)
	for _, desc in ipairs(char:GetDescendants()) do
		if checkHit(desc) then
			return true
		end
	end
	char.DescendantAdded:Connect(function(desc)
		if checkHit(desc) then
			return true
		end
	end)
	return false
end

local function sidestep(char, dir)
	if workspace.DistributedGameTime - lastSidestep < CONFIG.SIDESTEP_COOLDOWN then return end
	maneuvering = true
	local sideDir = Vector3.new(-dir.Z, 0, dir.X).Unit
	local pos = char.PrimaryPart.Position + sideDir * 5
	char.Humanoid:MoveTo(pos)
	lastSidestep = workspace.DistributedGameTime
	task.wait(0.5)
	maneuvering = false
end

local function escape(char)
	if workspace.DistributedGameTime - lastEscape < CONFIG.ESCAPE_COOLDOWN then return end
	maneuvering = true
	local escapeDir = -char.PrimaryPart.CFrame.LookVector
	local pos = char.PrimaryPart.Position + escapeDir * 15
	char.Humanoid:MoveTo(pos)
	char.Humanoid.Jump = true
	lastEscape = workspace.DistributedGameTime
	task.wait(1)
	maneuvering = false
end

local function click()
	local now = workspace.DistributedGameTime
	local actualCPS = CONFIG.CPS + math.random(-CONFIG.CPS_VARIATION, CONFIG.CPS_VARIATION)
	local clickInterval = 1 / actualCPS
	if now - lastClick >= clickInterval then
		script.Parent.cps.Clicked.Value = not script.Parent.cps.Clicked.Value
		--mouse1click()
		lastClick = now
	end
end

local function teleportAndHit(tgt)
	if not LP.Character or not LP.Character.PrimaryPart or not tgt or not tgt.PrimaryPart then return end
	local now = workspace.DistributedGameTime
	if now - lastTeleport < CONFIG.TELEPORT_PATTERN.COOLDOWN then return end

	-- tp away
	local awayDir = (LP.Character.PrimaryPart.Position - tgt.PrimaryPart.Position).Unit
	local awayPos = tgt.PrimaryPart.Position + awayDir * CONFIG.TELEPORT_PATTERN.AWAY_DISTANCE
	LP.Character:SetPrimaryPartCFrame(CFrame.new(awayPos))
	task.wait(0.1)  -- small delay

	-- tp to target and hit
	local behindDir = tgt.PrimaryPart.CFrame.LookVector
	local behindPos = tgt.PrimaryPart.Position - behindDir * CONFIG.TELEPORT_PATTERN.RETURN_DISTANCE
	LP.Character:SetPrimaryPartCFrame(CFrame.new(behindPos, tgt.PrimaryPart.Position))
	click()

	lastTeleport = now
end

local function moveTowards(tgt, guard)
	if not tgt or not tgt.PrimaryPart or not LP.Character or not LP.Character:FindFirstChild("Humanoid") or not LP.Character.PrimaryPart then return false end
	if CONFIG.TELEPORT_MODE or isSitting(tgt) or getWalkSpeed(tgt) >= 20 then
		teleportAndHit(tgt)
		return true
	end
	local time = workspace.DistributedGameTime
	local start = LP.Character.PrimaryPart.Position
	local finish = tgt.PrimaryPart.Position
	local dir = (finish - start).Unit
	local dist = (finish - start).Magnitude
	local targetDistance = inCombo and CONFIG.COMBO_DISTANCE or CONFIG.TARGET_DISTANCE
	local right = Vector3.new(-dir.Z, 0, dir.X).Unit
	local targetVelocity = tgt.PrimaryPart.Velocity
	local targetSpeed = targetVelocity.Magnitude
	local targetDir = targetVelocity.Unit
	local predictedPosition = finish + targetVelocity
	local dotProduct = dir:Dot(targetDir)
	local angle = math.acos(dotProduct)
	local cutAcross = false
	if angle > math.pi/4 and angle < 3*math.pi/4 and targetSpeed > 5 then
		cutAcross = true
	end
	local desiredPosition
	if cutAcross then
		local timeToIntercept = dist / (LP.Character.Humanoid.WalkSpeed + targetSpeed)
		desiredPosition = predictedPosition - targetDir * (targetDistance + timeToIntercept * targetSpeed)
	else
		local zigzagFrequency = inCombo and CONFIG.COMBO_ZIGZAG_FREQUENCY or CONFIG.ZIGZAG_FREQUENCY
		local zigzagAmplitude = inCombo and CONFIG.COMBO_ZIGZAG_AMPLITUDE or CONFIG.ZIGZAG_AMPLITUDE
		local zigzag = right * math.sin(time * zigzagFrequency) * zigzagAmplitude
		desiredPosition = finish - dir * targetDistance + zigzag
	end
	if dist <= targetDistance then
		desiredPosition = start + (start - finish).Unit * (targetDistance - dist + 0.5)
	end
	LP.Character.Humanoid:MoveTo(desiredPosition)
	if dist <= targetDistance + 1 then
		local speed = 16 * (dist / targetDistance)
		LP.Character.Humanoid.WalkSpeed = math.max(1, math.min(16, speed))
	else
		LP.Character.Humanoid.WalkSpeed = 16
	end
	if math.abs(dist - targetDistance) <= CONFIG.CLICK_RANGE then
		click()
	end
	return true
end

local function toggle(_, state)
	if state == Enum.UserInputState.Begin then
		CONFIG.ACTIVE = not CONFIG.ACTIVE
		target = nil
		if not CONFIG.ACTIVE and LP.Character and LP.Character:FindFirstChild("Humanoid") then
			LP.Character.Humanoid:MoveTo(LP.Character.PrimaryPart.Position)
		end
		print(CONFIG.ACTIVE and "Aimston enabled" or "Aimston disabled")
	end
end

local function toggleTeleportMode(_, state)
	if state == Enum.UserInputState.Begin then
		CONFIG.TELEPORT_MODE = not CONFIG.TELEPORT_MODE
		print(CONFIG.TELEPORT_MODE and "Teleport mode enabled" or "Teleport mode disabled")
	end
end

ContextActionService:BindAction(CONFIG.ACTION_NAME, toggle, true, CONFIG.TOGGLE_KEY, Enum.KeyCode.ButtonR3)
ContextActionService:BindAction(CONFIG.TELEPORT_ACTION_NAME, toggleTeleportMode, true, CONFIG.TELEPORT_TOGGLE_KEY)

if UserInputService.TouchEnabled then
	ContextActionService:BindAction(CONFIG.ACTION_NAME, toggle, true)
	ContextActionService:SetPosition(CONFIG.ACTION_NAME, UDim2.new(1, -280, 0, 10))
	ContextActionService:SetTitle(CONFIG.ACTION_NAME, "Aym")

	ContextActionService:BindAction(CONFIG.TELEPORT_ACTION_NAME, toggleTeleportMode, true)
	ContextActionService:SetPosition(CONFIG.TELEPORT_ACTION_NAME, UDim2.new(1, -280, 0, 70))
	ContextActionService:SetTitle(CONFIG.TELEPORT_ACTION_NAME, "TP")
end

Reach.Value = CONFIG.REACH

RunService.Heartbeat:Connect(function()
	if not CONFIG.ACTIVE or not LP.Character or not LP.Character:FindFirstChild("Humanoid") then return end

	local now = workspace.DistributedGameTime

	if detectCombo(LP.Character) then
		escape(LP.Character)
		return
	end

	if now - lastHit > 2 then
		resetCombo()
	end

	if now - lastRetarget >= CONFIG.RETARGET_INTERVAL or not target or not target:IsA("Model") or not target:FindFirstChildOfClass("Humanoid") or not isVisible(target) then
		target = getTarget()
		lastRetarget = now
		resetCombo()
	end

	if target then
		if CONFIG.TELEPORT_MODE then
			teleportAndHit(target)
		else
			moveTowards(target, false)
		end
	end

	if not maneuvering and now - lastJump > CONFIG.JUMP_COOLDOWN then
		if math.random(1, 5) == 1 then
			LP.Character.Humanoid.Jump = true
			lastJump = now
		end
	end

	if isFirstPerson() then
		coroutine.wrap(aimlock)()
	else
		target = nil
	end
end)
