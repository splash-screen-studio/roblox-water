--!strict
--[[
	SwimController - Handles swimming in Part-based water volumes.
	Detects water zones via CollectionService tags on water volume Parts.
	Depends on: Config
	Does NOT know about: Terrain generation, Water body creation, Noise, HUD
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local SwimController = {}

local player = Players.LocalPlayer
local isInWater = false
local currentWaterPart: BasePart? = nil
local bodyVelocity: BodyVelocity? = nil

--[[
	Checks if a point is inside a Part's axis-aligned bounding box.
]]
local function isPointInsidePart(point: Vector3, part: BasePart): boolean
	local halfSize = part.Size / 2
	local partPos = part.Position
	return math.abs(point.X - partPos.X) < halfSize.X
		and math.abs(point.Y - partPos.Y) < halfSize.Y
		and math.abs(point.Z - partPos.Z) < halfSize.Z
end

--[[
	Finds which water volume Part (if any) contains the given point.
]]
local function findContainingWater(point: Vector3): BasePart?
	local waterParts = CollectionService:GetTagged(Config.TAGS.WATER_VOLUME)
	for _, part in waterParts do
		if part:IsA("BasePart") and isPointInsidePart(point, part :: BasePart) then
			return part :: BasePart
		end
	end
	return nil
end

--[[
	Called when the player enters a water volume.
]]
local function enterWater(character: Model, humanoid: Humanoid, rootPart: BasePart)
	if isInWater then
		return
	end
	isInWater = true

	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)

	if not bodyVelocity then
		local bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		bv.Velocity = Vector3.zero
		bv.P = 1250
		bv.Parent = rootPart
		bodyVelocity = bv
	end
end

--[[
	Called when the player exits a water volume.
]]
local function exitWater(humanoid: Humanoid)
	if not isInWater then
		return
	end
	isInWater = false
	currentWaterPart = nil

	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)

	if bodyVelocity then
		bodyVelocity:Destroy()
		bodyVelocity = nil
	end
end

--[[
	Per-frame update: checks water zone and applies swimming physics.
]]
local function onHeartbeat(_dt: number)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	local waterPart = findContainingWater(rootPart.Position)

	if waterPart and not isInWater then
		currentWaterPart = waterPart
		enterWater(character, humanoid, rootPart)
	elseif not waterPart and isInWater then
		exitWater(humanoid)
	end

	if isInWater and bodyVelocity and humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
		local moveDir = humanoid.MoveDirection
		local swimVelocity = moveDir * Config.WATER.SWIM_SPEED

		-- Buoyancy: push upward when below the water surface
		local buoyancy = Vector3.new(0, Config.WATER.BUOYANCY_FORCE, 0)

		-- If player is near the surface of the water, reduce buoyancy
		if currentWaterPart then
			local waterTop = currentWaterPart.Position.Y + currentWaterPart.Size.Y / 2
			local playerY = rootPart.Position.Y
			local depthBelowSurface = waterTop - playerY
			if depthBelowSurface < 0 then
				buoyancy = Vector3.zero
			end
		end

		bodyVelocity.Velocity = swimVelocity + buoyancy
	end
end

--[[
	Cleans up swimming state when the character respawns.
]]
local function onCharacterAdded(_character: Model)
	isInWater = false
	currentWaterPart = nil
	bodyVelocity = nil
end

function SwimController.init()
	RunService.Heartbeat:Connect(onHeartbeat)

	player.CharacterAdded:Connect(onCharacterAdded)

	print("[SwimController] Initialized.")
end

return SwimController
