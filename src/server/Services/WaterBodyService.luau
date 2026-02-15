--!strict
--[[
	WaterBodyService - Creates Part-based water bodies with containment walls.
	Depends on: Config, Types, TerrainService (heightAt, carveRegion, fillColumn)
	Does NOT know about: HUD, Swimming, Noise
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

local WaterBodyService = {}

local terrainService: any = nil

local VOXEL = Config.TERRAIN.VOXEL_RESOLUTION
local WALL_THICKNESS = Config.WATER.WALL_THICKNESS_STUDS
local SURFACE_INSET = Config.WATER.SURFACE_INSET_STUDS
local SHORELINE_RING = Config.WATER.SHORELINE_RING_VOXELS

--[[
	Initializes the service with a reference to TerrainService.
	Dependency injection: WaterBodyService only uses heightAt, carveRegion, fillColumn.
]]
function WaterBodyService.init(ts: any)
	terrainService = ts

	local folder = Instance.new("Folder")
	folder.Name = Config.FOLDERS.WATER_BODIES
	folder.Parent = workspace
end

--[[
	Snaps a value down to the nearest voxel grid boundary.
]]
local function snapToGrid(value: number): number
	return math.floor(value / VOXEL) * VOXEL
end

--[[
	Resolves a WaterBodyDef by merging with type defaults.
	Returns all resolved values needed for creation.
]]
local function resolveDefaults(def: Types.WaterBodyDef): {
	centerX: number,
	centerZ: number,
	surfaceY: number,
	width: number,
	length: number,
	depth: number,
	wallMaterial: Enum.Material,
	waterColor: Color3,
	waterTransparency: number,
}
	local defaults = Config.WATER_BODY_DEFAULTS[def.type]

	local centerX = def.centerX
	local centerZ = def.centerZ
	local width = def.width or defaults.width
	local length = def.length or defaults.length
	local depth = def.depth or defaults.depth
	local surfaceY = def.surfaceY or Config.TERRAIN.SEA_LEVEL

	return {
		centerX = centerX,
		centerZ = centerZ,
		surfaceY = surfaceY,
		width = width,
		length = length,
		depth = depth,
		wallMaterial = def.wallMaterial or defaults.wallMaterial,
		waterColor = def.waterColor or defaults.waterColor,
		waterTransparency = def.waterTransparency or defaults.waterTransparency,
	}
end

--[[
	Creates a single Part with common properties.
]]
local function createPart(props: {
	name: string,
	size: Vector3,
	position: Vector3,
	anchored: boolean,
	canCollide: boolean,
	material: Enum.Material?,
	color: Color3?,
	transparency: number?,
	reflectance: number?,
	castShadow: boolean?,
	canTouch: boolean?,
	tag: string?,
	parent: Instance,
})
	local part = Instance.new("Part")
	part.Name = props.name
	part.Shape = Enum.PartType.Block
	part.Size = props.size
	part.Position = props.position
	part.Anchored = props.anchored
	part.CanCollide = props.canCollide
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	if props.material then
		part.Material = props.material
	end
	if props.color then
		part.Color = props.color
	end
	if props.transparency then
		part.Transparency = props.transparency
	end
	if props.reflectance then
		part.Reflectance = props.reflectance
	end
	if props.castShadow ~= nil then
		part.CastShadow = props.castShadow
	end
	if props.canTouch ~= nil then
		part.CanTouch = props.canTouch
	end

	if props.tag then
		CollectionService:AddTag(part, props.tag)
	end

	part.Parent = props.parent
	return part
end

--[[
	Shapes the shoreline terrain around the water body perimeter.
	Sets terrain in a ring outside the walls to be flush with the surface Y.
]]
local function shapeShoreline(
	minX: number, minZ: number,
	maxX: number, maxZ: number,
	surfaceY: number
)
	local ringWidth = SHORELINE_RING * VOXEL
	local shorelineMaterial = Config.WATER.SHORELINE_MATERIAL

	for x = minX - ringWidth, maxX + ringWidth - VOXEL, VOXEL do
		for z = minZ - ringWidth, maxZ + ringWidth - VOXEL, VOXEL do
			local isInside = x >= minX and x < maxX and z >= minZ and z < maxZ
			if not isInside then
				local isInRing = x >= (minX - ringWidth) and x < (maxX + ringWidth)
					and z >= (minZ - ringWidth) and z < (maxZ + ringWidth)
				if isInRing then
					terrainService.fillColumn(x, z, surfaceY, shorelineMaterial)
				end
			end
		end
	end
end

--[[
	Creates a water body from a definition.
	Returns the Model containing all parts.
]]
function WaterBodyService.create(def: Types.WaterBodyDef): Model
	assert(terrainService, "[WaterBodyService] Must call init() before create()")

	local resolved = resolveDefaults(def)

	local halfWidth = resolved.width / 2
	local halfLength = resolved.length / 2

	-- Snap boundaries to voxel grid
	local minX = snapToGrid(resolved.centerX - halfWidth)
	local maxX = snapToGrid(resolved.centerX + halfWidth) + VOXEL
	local minZ = snapToGrid(resolved.centerZ - halfLength)
	local maxZ = snapToGrid(resolved.centerZ + halfLength) + VOXEL

	local surfaceY = resolved.surfaceY
	local floorY = surfaceY - resolved.depth

	local bodyName = string.format(
		"%s_%d_%d",
		string.upper(string.sub(def.type, 1, 1)) .. string.sub(def.type, 2),
		math.round(resolved.centerX),
		math.round(resolved.centerZ)
	)

	local model = Instance.new("Model")
	model.Name = bodyName

	-- Interior dimensions (inside the walls)
	local interiorWidth = maxX - minX
	local interiorLength = maxZ - minZ
	local wallHeight = surfaceY - floorY

	-- 1. Carve interior terrain (clear from below floor up through max height)
	local maxTerrainY = Config.TERRAIN.BASE_Y + Config.TERRAIN.MAX_HEIGHT_STUDS + VOXEL
	terrainService.carveRegion(
		minX, minZ,
		maxX, maxZ,
		floorY - VOXEL,
		maxTerrainY
	)

	-- 2. Shape shoreline terrain flush with wall tops
	shapeShoreline(minX, minZ, maxX, maxZ, surfaceY)

	-- 3. Create floor Part
	createPart({
		name = "Floor",
		size = Vector3.new(interiorWidth + WALL_THICKNESS * 2, WALL_THICKNESS, interiorLength + WALL_THICKNESS * 2),
		position = Vector3.new(
			(minX + maxX) / 2,
			floorY - WALL_THICKNESS / 2,
			(minZ + maxZ) / 2
		),
		anchored = true,
		canCollide = true,
		material = resolved.wallMaterial,
		tag = Config.TAGS.WATER_FLOOR,
		parent = model,
	})

	-- 4. Create wall Parts
	-- North wall (positive Z)
	createPart({
		name = "WallNorth",
		size = Vector3.new(interiorWidth + WALL_THICKNESS * 2, wallHeight, WALL_THICKNESS),
		position = Vector3.new(
			(minX + maxX) / 2,
			floorY + wallHeight / 2,
			maxZ + WALL_THICKNESS / 2
		),
		anchored = true,
		canCollide = true,
		material = resolved.wallMaterial,
		tag = Config.TAGS.WATER_WALL,
		parent = model,
	})

	-- South wall (negative Z)
	createPart({
		name = "WallSouth",
		size = Vector3.new(interiorWidth + WALL_THICKNESS * 2, wallHeight, WALL_THICKNESS),
		position = Vector3.new(
			(minX + maxX) / 2,
			floorY + wallHeight / 2,
			minZ - WALL_THICKNESS / 2
		),
		anchored = true,
		canCollide = true,
		material = resolved.wallMaterial,
		tag = Config.TAGS.WATER_WALL,
		parent = model,
	})

	-- East wall (positive X)
	createPart({
		name = "WallEast",
		size = Vector3.new(WALL_THICKNESS, wallHeight, interiorLength + WALL_THICKNESS * 2),
		position = Vector3.new(
			maxX + WALL_THICKNESS / 2,
			floorY + wallHeight / 2,
			(minZ + maxZ) / 2
		),
		anchored = true,
		canCollide = true,
		material = resolved.wallMaterial,
		tag = Config.TAGS.WATER_WALL,
		parent = model,
	})

	-- West wall (negative X)
	createPart({
		name = "WallWest",
		size = Vector3.new(WALL_THICKNESS, wallHeight, interiorLength + WALL_THICKNESS * 2),
		position = Vector3.new(
			minX - WALL_THICKNESS / 2,
			floorY + wallHeight / 2,
			(minZ + maxZ) / 2
		),
		anchored = true,
		canCollide = true,
		material = resolved.wallMaterial,
		tag = Config.TAGS.WATER_WALL,
		parent = model,
	})

	-- 5. Create water volume Part
	local waterHeight = wallHeight - SURFACE_INSET
	createPart({
		name = "WaterVolume",
		size = Vector3.new(interiorWidth, waterHeight, interiorLength),
		position = Vector3.new(
			(minX + maxX) / 2,
			floorY + waterHeight / 2,
			(minZ + maxZ) / 2
		),
		anchored = true,
		canCollide = false,
		canTouch = true,
		castShadow = false,
		material = Config.WATER.MATERIAL,
		color = resolved.waterColor,
		transparency = resolved.waterTransparency,
		reflectance = Config.WATER.REFLECTANCE,
		tag = Config.TAGS.WATER_VOLUME,
		parent = model,
	})

	-- Parent model to the WaterBodies folder
	local folder = workspace:FindFirstChild(Config.FOLDERS.WATER_BODIES)
	if folder then
		model.Parent = folder
	else
		model.Parent = workspace
	end

	print(string.format(
		"[WaterBodyService] Created %s at (%d, %d) surface=%.1f depth=%.1f",
		bodyName, math.round(resolved.centerX), math.round(resolved.centerZ),
		surfaceY, resolved.depth
	))

	return model
end

--[[
	Creates all water bodies from a definitions array.
]]
function WaterBodyService.createAll(defs: { Types.WaterBodyDef })
	print(string.format("[WaterBodyService] Creating %d water bodies...", #defs))

	for _, def in defs do
		WaterBodyService.create(def)
		task.wait()
	end

	print("[WaterBodyService] All water bodies created.")
end

return WaterBodyService
