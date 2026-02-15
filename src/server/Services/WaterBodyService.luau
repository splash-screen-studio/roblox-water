--!strict
--[[
	WaterBodyService - Creates Part-based water bodies with containment walls.
	Supports two creation modes:
	  - Cell-based: irregular shapes from DepressionScanner (row-span merged Parts)
	  - Rectangular: manual definitions with width/length
	Depends on: Config, Types, TerrainService (carveRegion, fillColumn)
	Does NOT know about: HUD, Swimming, Noise, DepressionScanner
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
local MAX_TERRAIN_Y = Config.TERRAIN.BASE_Y + Config.TERRAIN.MAX_HEIGHT_STUDS + VOXEL

-- ============================================================
-- Shared utilities
-- ============================================================

function WaterBodyService.init(ts: any)
	terrainService = ts

	local folder = Instance.new("Folder")
	folder.Name = Config.FOLDERS.WATER_BODIES
	folder.Parent = workspace
end

local function snapToGrid(value: number): number
	return math.floor(value / VOXEL) * VOXEL
end

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

	return {
		centerX = def.centerX,
		centerZ = def.centerZ,
		surfaceY = def.surfaceY or Config.TERRAIN.SEA_LEVEL,
		width = def.width or defaults.width,
		length = def.length or defaults.length,
		depth = def.depth or defaults.depth,
		wallMaterial = def.wallMaterial or defaults.wallMaterial,
		waterColor = def.waterColor or defaults.waterColor,
		waterTransparency = def.waterTransparency or defaults.waterTransparency,
	}
end

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

local function makeBodyName(def: Types.WaterBodyDef): string
	return string.format(
		"%s_%d_%d",
		string.upper(string.sub(def.type, 1, 1)) .. string.sub(def.type, 2),
		math.round(def.centerX),
		math.round(def.centerZ)
	)
end

local function parentToFolder(model: Model)
	local folder = workspace:FindFirstChild(Config.FOLDERS.WATER_BODIES)
	model.Parent = folder or workspace
end

-- ============================================================
-- Cell-based creation (irregular shapes from DepressionScanner)
-- ============================================================

--[[
	Builds a set from cell positions for O(1) membership lookup.
	Key format: "x,z"
]]
local function buildCellSet(cells: {{ number }}): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, cell in cells do
		set[string.format("%d,%d", cell[1], cell[2])] = true
	end
	return set
end

local function cellKey(x: number, z: number): string
	return string.format("%d,%d", x, z)
end

--[[
	Groups cells by X coordinate and merges consecutive Z values into spans.
	Returns sorted spans: { { x, zStart, zEnd } }
	zEnd is exclusive (zStart to zEnd covers zEnd-zStart studs).
]]
local function buildRowSpans(cells: {{ number }}): { { number } }
	-- Group cells by X
	local byX: { [number]: { number } } = {}
	for _, cell in cells do
		local x = cell[1]
		if not byX[x] then
			byX[x] = {}
		end
		table.insert(byX[x], cell[2])
	end

	-- For each X row, sort Z values and merge consecutive
	local spans: { { number } } = {}
	for x, zValues in byX do
		table.sort(zValues)

		local spanStart = zValues[1]
		local spanEnd = zValues[1] + VOXEL

		for i = 2, #zValues do
			if zValues[i] == spanEnd then
				-- Consecutive: extend span
				spanEnd = zValues[i] + VOXEL
			else
				-- Gap: emit current span, start new
				table.insert(spans, { x, spanStart, spanEnd })
				spanStart = zValues[i]
				spanEnd = zValues[i] + VOXEL
			end
		end

		table.insert(spans, { x, spanStart, spanEnd })
	end

	return spans
end

type WallEdge = {
	axis: string,
	pos: number,
	start: number,
	finish: number,
}

--[[
	Finds all boundary edges and merges adjacent ones into wall segments.
	A boundary edge exists where a depression cell is adjacent to a non-depression cell.
]]
local function buildWallSegments(cellSet: { [string]: boolean }, cells: {{ number }}): { WallEdge }
	-- Collect raw edges grouped by (axis, position on that axis)
	-- N/S walls run along X axis: key = "z,<zPos>", value = list of X positions
	-- E/W walls run along Z axis: key = "x,<xPos>", value = list of Z positions
	local edgeGroups: { [string]: { number } } = {}

	for _, cell in cells do
		local x, z = cell[1], cell[2]

		-- Check north neighbor (Z+)
		if not cellSet[cellKey(x, z + VOXEL)] then
			local key = string.format("ns,%d", z + VOXEL)
			if not edgeGroups[key] then edgeGroups[key] = {} end
			table.insert(edgeGroups[key], x)
		end

		-- Check south neighbor (Z-)
		if not cellSet[cellKey(x, z - VOXEL)] then
			local key = string.format("ns,%d", z)
			if not edgeGroups[key] then edgeGroups[key] = {} end
			table.insert(edgeGroups[key], x)
		end

		-- Check east neighbor (X+)
		if not cellSet[cellKey(x + VOXEL, z)] then
			local key = string.format("ew,%d", x + VOXEL)
			if not edgeGroups[key] then edgeGroups[key] = {} end
			table.insert(edgeGroups[key], z)
		end

		-- Check west neighbor (X-)
		if not cellSet[cellKey(x - VOXEL, z)] then
			local key = string.format("ew,%d", x)
			if not edgeGroups[key] then edgeGroups[key] = {} end
			table.insert(edgeGroups[key], z)
		end
	end

	-- Merge consecutive values in each group into segments
	local segments: { WallEdge } = {}

	for key, values in edgeGroups do
		table.sort(values)

		local axis = string.sub(key, 1, 2)
		local pos = tonumber(string.sub(key, 4)) :: number

		local spanStart = values[1]
		local spanEnd = values[1] + VOXEL

		for i = 2, #values do
			if values[i] == spanEnd then
				spanEnd = values[i] + VOXEL
			else
				table.insert(segments, {
					axis = axis,
					pos = pos,
					start = spanStart,
					finish = spanEnd,
				})
				spanStart = values[i]
				spanEnd = values[i] + VOXEL
			end
		end

		table.insert(segments, {
			axis = axis,
			pos = pos,
			start = spanStart,
			finish = spanEnd,
		})
	end

	return segments
end

--[[
	Creates a water body from cell footprint data (irregular shape).
]]
local function createFromCells(def: Types.WaterBodyDef): Model
	local resolved = resolveDefaults(def)
	local cells = def.cells :: {{ number }}
	local cellSet = buildCellSet(cells)

	local surfaceY = resolved.surfaceY
	local floorY = surfaceY - resolved.depth
	local wallHeight = surfaceY - floorY
	local waterHeight = wallHeight - SURFACE_INSET

	local model = Instance.new("Model")
	model.Name = makeBodyName(def)

	local spans = buildRowSpans(cells)

	-- 1. Carve terrain for each row-span
	for _, span in spans do
		local x, zStart, zEnd = span[1], span[2], span[3]
		terrainService.carveRegion(
			x, zStart,
			x + VOXEL, zEnd,
			floorY - VOXEL,
			MAX_TERRAIN_Y
		)
	end

	-- 2. Shape shoreline: fill neighbor cells outside the depression to surfaceY
	local shoreSet: { [string]: boolean } = {}
	local shorelineMaterial = Config.WATER.SHORELINE_MATERIAL

	for _, cell in cells do
		local x, z = cell[1], cell[2]
		local neighbors = {
			{ x - VOXEL, z },
			{ x + VOXEL, z },
			{ x, z - VOXEL },
			{ x, z + VOXEL },
		}
		for _, n in neighbors do
			local nKey = cellKey(n[1], n[2])
			if not cellSet[nKey] and not shoreSet[nKey] then
				shoreSet[nKey] = true
				terrainService.fillColumn(n[1], n[2], surfaceY, shorelineMaterial)
			end
		end
	end

	-- 3. Create floor spans
	local floorIndex = 0
	for _, span in spans do
		floorIndex += 1
		local x, zStart, zEnd = span[1], span[2], span[3]
		local spanLen = zEnd - zStart
		createPart({
			name = string.format("Floor_%d", floorIndex),
			size = Vector3.new(VOXEL, WALL_THICKNESS, spanLen),
			position = Vector3.new(
				x + VOXEL / 2,
				floorY - WALL_THICKNESS / 2,
				zStart + spanLen / 2
			),
			anchored = true,
			canCollide = true,
			material = resolved.wallMaterial,
			tag = Config.TAGS.WATER_FLOOR,
			parent = model,
		})
	end

	-- 4. Create water volume spans
	local waterIndex = 0
	for _, span in spans do
		waterIndex += 1
		local x, zStart, zEnd = span[1], span[2], span[3]
		local spanLen = zEnd - zStart
		createPart({
			name = string.format("Water_%d", waterIndex),
			size = Vector3.new(VOXEL, waterHeight, spanLen),
			position = Vector3.new(
				x + VOXEL / 2,
				floorY + waterHeight / 2,
				zStart + spanLen / 2
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
	end

	-- 5. Create wall segments along boundary edges
	local wallSegments = buildWallSegments(cellSet, cells)
	local wallIndex = 0

	for _, seg in wallSegments do
		wallIndex += 1
		local segLen = seg.finish - seg.start

		local size: Vector3
		local position: Vector3

		if seg.axis == "ns" then
			-- North/South wall: runs along X, thin in Z
			size = Vector3.new(segLen, wallHeight, WALL_THICKNESS)
			position = Vector3.new(
				seg.start + segLen / 2,
				floorY + wallHeight / 2,
				seg.pos
			)
		else
			-- East/West wall: runs along Z, thin in X
			size = Vector3.new(WALL_THICKNESS, wallHeight, segLen)
			position = Vector3.new(
				seg.pos,
				floorY + wallHeight / 2,
				seg.start + segLen / 2
			)
		end

		createPart({
			name = string.format("Wall_%d", wallIndex),
			size = size,
			position = position,
			anchored = true,
			canCollide = true,
			material = resolved.wallMaterial,
			tag = Config.TAGS.WATER_WALL,
			parent = model,
		})
	end

	parentToFolder(model)

	print(string.format(
		"[WaterBodyService] Created %s (cells=%d, spans=%d, walls=%d) surface=%.1f depth=%.1f",
		model.Name, #cells, #spans, #wallSegments, surfaceY, resolved.depth
	))

	return model
end

-- ============================================================
-- Rectangular creation (manual definitions without cells)
-- ============================================================

local function createRectangular(def: Types.WaterBodyDef): Model
	local resolved = resolveDefaults(def)

	local halfWidth = resolved.width / 2
	local halfLength = resolved.length / 2

	local minX = snapToGrid(resolved.centerX - halfWidth)
	local maxX = snapToGrid(resolved.centerX + halfWidth) + VOXEL
	local minZ = snapToGrid(resolved.centerZ - halfLength)
	local maxZ = snapToGrid(resolved.centerZ + halfLength) + VOXEL

	local surfaceY = resolved.surfaceY
	local floorY = surfaceY - resolved.depth

	local model = Instance.new("Model")
	model.Name = makeBodyName(def)

	local interiorWidth = maxX - minX
	local interiorLength = maxZ - minZ
	local wallHeight = surfaceY - floorY
	local waterHeight = wallHeight - SURFACE_INSET

	-- 1. Carve interior terrain
	terrainService.carveRegion(minX, minZ, maxX, maxZ, floorY - VOXEL, MAX_TERRAIN_Y)

	-- 2. Shape shoreline
	local ringWidth = SHORELINE_RING * VOXEL
	local shorelineMaterial = Config.WATER.SHORELINE_MATERIAL
	for x = minX - ringWidth, maxX + ringWidth - VOXEL, VOXEL do
		for z = minZ - ringWidth, maxZ + ringWidth - VOXEL, VOXEL do
			local isInside = x >= minX and x < maxX and z >= minZ and z < maxZ
			if not isInside then
				terrainService.fillColumn(x, z, surfaceY, shorelineMaterial)
			end
		end
	end

	-- 3. Floor
	createPart({
		name = "Floor",
		size = Vector3.new(interiorWidth + WALL_THICKNESS * 2, WALL_THICKNESS, interiorLength + WALL_THICKNESS * 2),
		position = Vector3.new((minX + maxX) / 2, floorY - WALL_THICKNESS / 2, (minZ + maxZ) / 2),
		anchored = true,
		canCollide = true,
		material = resolved.wallMaterial,
		tag = Config.TAGS.WATER_FLOOR,
		parent = model,
	})

	-- 4. Walls
	createPart({
		name = "WallNorth",
		size = Vector3.new(interiorWidth + WALL_THICKNESS * 2, wallHeight, WALL_THICKNESS),
		position = Vector3.new((minX + maxX) / 2, floorY + wallHeight / 2, maxZ + WALL_THICKNESS / 2),
		anchored = true, canCollide = true, material = resolved.wallMaterial,
		tag = Config.TAGS.WATER_WALL, parent = model,
	})
	createPart({
		name = "WallSouth",
		size = Vector3.new(interiorWidth + WALL_THICKNESS * 2, wallHeight, WALL_THICKNESS),
		position = Vector3.new((minX + maxX) / 2, floorY + wallHeight / 2, minZ - WALL_THICKNESS / 2),
		anchored = true, canCollide = true, material = resolved.wallMaterial,
		tag = Config.TAGS.WATER_WALL, parent = model,
	})
	createPart({
		name = "WallEast",
		size = Vector3.new(WALL_THICKNESS, wallHeight, interiorLength + WALL_THICKNESS * 2),
		position = Vector3.new(maxX + WALL_THICKNESS / 2, floorY + wallHeight / 2, (minZ + maxZ) / 2),
		anchored = true, canCollide = true, material = resolved.wallMaterial,
		tag = Config.TAGS.WATER_WALL, parent = model,
	})
	createPart({
		name = "WallWest",
		size = Vector3.new(WALL_THICKNESS, wallHeight, interiorLength + WALL_THICKNESS * 2),
		position = Vector3.new(minX - WALL_THICKNESS / 2, floorY + wallHeight / 2, (minZ + maxZ) / 2),
		anchored = true, canCollide = true, material = resolved.wallMaterial,
		tag = Config.TAGS.WATER_WALL, parent = model,
	})

	-- 5. Water volume
	createPart({
		name = "WaterVolume",
		size = Vector3.new(interiorWidth, waterHeight, interiorLength),
		position = Vector3.new((minX + maxX) / 2, floorY + waterHeight / 2, (minZ + maxZ) / 2),
		anchored = true, canCollide = false, canTouch = true, castShadow = false,
		material = Config.WATER.MATERIAL, color = resolved.waterColor,
		transparency = resolved.waterTransparency, reflectance = Config.WATER.REFLECTANCE,
		tag = Config.TAGS.WATER_VOLUME, parent = model,
	})

	parentToFolder(model)

	print(string.format(
		"[WaterBodyService] Created %s (rect %dx%d) surface=%.1f depth=%.1f",
		model.Name, math.round(interiorWidth), math.round(interiorLength),
		surfaceY, resolved.depth
	))

	return model
end

-- ============================================================
-- Public API
-- ============================================================

--[[
	Creates a water body. Routes to cell-based or rectangular creation
	based on whether the definition includes cell footprint data.
]]
function WaterBodyService.create(def: Types.WaterBodyDef): Model
	assert(terrainService, "[WaterBodyService] Must call init() before create()")

	if def.cells then
		return createFromCells(def)
	else
		return createRectangular(def)
	end
end

function WaterBodyService.createAll(defs: { Types.WaterBodyDef })
	print(string.format("[WaterBodyService] Creating %d water bodies...", #defs))

	for _, def in defs do
		WaterBodyService.create(def)
		task.wait()
	end

	print("[WaterBodyService] All water bodies created.")
end

return WaterBodyService
