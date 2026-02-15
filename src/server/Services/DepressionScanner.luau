--!strict
--[[
	DepressionScanner - Scans terrain for depressions below sea level.
	Produces WaterBodyDef arrays for WaterBodyService to consume.
	Depends on: Config, Types, TerrainService (heightAt only)
	Does NOT know about: WaterBodyService, HUD, Swimming
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

local DepressionScanner = {}

local VOXEL = Config.TERRAIN.VOXEL_RESOLUTION
local MAP_SIZE = Config.TERRAIN.MAP_SIZE_STUDS
local SEA_LEVEL = Config.TERRAIN.SEA_LEVEL
local GRID_SIZE = MAP_SIZE / VOXEL

--[[
	Classifies a depression by its area (in studs²) into a water body type.
]]
local function classifyByArea(areaStuds2: number): Types.WaterBodyType
	for _, entry in Config.DEPRESSION.CLASSIFICATION do
		if areaStuds2 < entry.maxArea then
			return entry.type :: Types.WaterBodyType
		end
	end
	return "ocean"
end

--[[
	Flood-fills from a starting grid cell to find all connected cells below sea level.
	Uses 4-directional adjacency. Marks visited cells in the visited grid.
	Returns a DepressionInfo describing the connected region.
]]
local function floodFill(
	startGx: number, startGz: number,
	heightGrid: {{ number }},
	visited: {{ boolean }}
): Types.DepressionInfo
	local stack = { { startGx, startGz } }
	local cellCount = 0
	local minX = startGx
	local maxX = startGx
	local minZ = startGz
	local maxZ = startGz
	local minHeight = heightGrid[startGx][startGz]

	while #stack > 0 do
		local cell = table.remove(stack) :: { number }
		local gx, gz = cell[1], cell[2]

		if gx < 1 or gx > GRID_SIZE or gz < 1 or gz > GRID_SIZE then
			continue
		end
		if visited[gx][gz] then
			continue
		end
		if heightGrid[gx][gz] >= SEA_LEVEL then
			continue
		end

		visited[gx][gz] = true
		cellCount += 1

		if gx < minX then minX = gx end
		if gx > maxX then maxX = gx end
		if gz < minZ then minZ = gz end
		if gz > maxZ then maxZ = gz end
		if heightGrid[gx][gz] < minHeight then
			minHeight = heightGrid[gx][gz]
		end

		table.insert(stack, { gx - 1, gz })
		table.insert(stack, { gx + 1, gz })
		table.insert(stack, { gx, gz - 1 })
		table.insert(stack, { gx, gz + 1 })
	end

	return {
		minX = (minX - 1) * VOXEL,
		maxX = maxX * VOXEL,
		minZ = (minZ - 1) * VOXEL,
		maxZ = maxZ * VOXEL,
		minHeight = minHeight,
		cellCount = cellCount,
	}
end

--[[
	Scans the full terrain for depressions below sea level.
	Returns a list of WaterBodyDef entries ready for WaterBodyService.
]]
function DepressionScanner.scan(terrainService: any): { Types.WaterBodyDef }
	print("[DepressionScanner] Scanning terrain for depressions below sea level...")

	-- Build 2D height grid
	local heightGrid: {{ number }} = table.create(GRID_SIZE)
	for gx = 1, GRID_SIZE do
		local row = table.create(GRID_SIZE)
		for gz = 1, GRID_SIZE do
			local worldX = (gx - 1) * VOXEL
			local worldZ = (gz - 1) * VOXEL
			row[gz] = terrainService.heightAt(worldX, worldZ)
		end
		heightGrid[gx] = row
	end

	-- Build visited grid
	local visited: {{ boolean }} = table.create(GRID_SIZE)
	for gx = 1, GRID_SIZE do
		visited[gx] = table.create(GRID_SIZE, false)
	end

	-- Find all depressions via flood-fill
	local depressions: { Types.DepressionInfo } = {}
	for gx = 1, GRID_SIZE do
		for gz = 1, GRID_SIZE do
			if not visited[gx][gz] and heightGrid[gx][gz] < SEA_LEVEL then
				local info = floodFill(gx, gz, heightGrid, visited)
				table.insert(depressions, info)
			end
		end
	end

	-- Filter and classify into WaterBodyDefs
	local results: { Types.WaterBodyDef } = {}
	local cellArea = VOXEL * VOXEL

	for _, dep in depressions do
		local depth = SEA_LEVEL - dep.minHeight
		local area = dep.cellCount * cellArea

		if depth < Config.DEPRESSION.MIN_DEPTH_STUDS then
			continue
		end
		if area < Config.DEPRESSION.MIN_AREA_STUDS2 then
			continue
		end

		local bodyType = classifyByArea(area)
		local width = dep.maxX - dep.minX
		local length = dep.maxZ - dep.minZ

		table.insert(results, {
			type = bodyType,
			centerX = dep.minX + width / 2,
			centerZ = dep.minZ + length / 2,
			surfaceY = SEA_LEVEL,
			width = width,
			length = length,
			depth = depth,
		})
	end

	print(string.format(
		"[DepressionScanner] Found %d depressions, %d qualify as water bodies.",
		#depressions, #results
	))

	return results
end

return DepressionScanner
