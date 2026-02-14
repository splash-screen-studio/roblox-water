--!strict
--[[
	TerrainService - Generates undulating terrain and provides height queries.
	Depends on: Config, Noise
	Does NOT know about: Water, HUD, Swimming
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Noise = require(ReplicatedStorage.Shared.Noise)
local Types = require(ReplicatedStorage.Shared.Types)

local TerrainService = {}

local terrain = workspace.Terrain

local VOXEL = Config.TERRAIN.VOXEL_RESOLUTION
local MAX_HEIGHT = Config.TERRAIN.MAX_HEIGHT_STUDS
local MAP_SIZE = Config.TERRAIN.MAP_SIZE_STUDS
local CHUNK_STUDS = Config.TERRAIN.CHUNK_SIZE_VOXELS * VOXEL
local BASE_Y = Config.TERRAIN.BASE_Y

local heightNoiseConfig: Types.NoiseConfig = {
	seed = Config.NOISE.SEED,
	octaves = Config.NOISE.OCTAVES,
	lacunarity = Config.NOISE.LACUNARITY,
	persistence = Config.NOISE.PERSISTENCE,
	scale = Config.NOISE.SCALE,
}

--[[
	Returns the deterministic terrain height at world coordinates (x, z).
	This recomputes from noise so no storage is needed.
]]
function TerrainService.heightAt(x: number, z: number): number
	local noiseVal = Noise.fractal(x, z, heightNoiseConfig)
	local normalized = math.clamp(noiseVal + 0.5, 0, 1)
	return BASE_Y + normalized * MAX_HEIGHT
end

--[[
	Returns the terrain material for a given world height, with noise-based
	perturbation for natural material band variation.
]]
local function getMaterialAt(worldX: number, worldZ: number, worldY: number): Enum.Material
	local normalizedHeight = (worldY - BASE_Y) / MAX_HEIGHT
	local materialNoise = math.noise(
		worldX * Config.MATERIAL_NOISE.FREQUENCY,
		worldZ * Config.MATERIAL_NOISE.FREQUENCY,
		Config.MATERIAL_NOISE.SEED
	)
	local adjustedHeight = normalizedHeight + materialNoise * Config.MATERIAL_NOISE.STRENGTH

	for _, band in Config.MATERIAL_BANDS do
		if adjustedHeight > band.threshold then
			return band.material
		end
	end

	return Config.MATERIAL_BANDS[#Config.MATERIAL_BANDS].material
end

--[[
	Creates a 3D array filled with a default value.
	Indexed as [x][y][z].
]]
local function make3D<T>(sizeX: number, sizeY: number, sizeZ: number, default: T): {{{T}}}
	local arr = table.create(sizeX)
	for x = 1, sizeX do
		local yArr = table.create(sizeY)
		for y = 1, sizeY do
			yArr[y] = table.create(sizeZ, default)
		end
		arr[x] = yArr
	end
	return arr
end

--[[
	Generates a single chunk of terrain at chunk coordinates (cx, cz).
	Chunk coordinates are in chunk units (not studs or voxels).
]]
local function generateChunk(cx: number, cz: number)
	local chunkVoxels = Config.TERRAIN.CHUNK_SIZE_VOXELS
	local maxYVoxels = math.ceil(MAX_HEIGHT / VOXEL) + 1

	local materials = make3D(chunkVoxels, maxYVoxels, chunkVoxels, Enum.Material.Air)
	local occupancies = make3D(chunkVoxels, maxYVoxels, chunkVoxels, 0)

	for lx = 1, chunkVoxels do
		for lz = 1, chunkVoxels do
			local worldX = cx * CHUNK_STUDS + (lx - 1) * VOXEL
			local worldZ = cz * CHUNK_STUDS + (lz - 1) * VOXEL

			local surfaceHeight = TerrainService.heightAt(worldX, worldZ)

			for ly = 1, maxYVoxels do
				local voxelBottom = BASE_Y + (ly - 1) * VOXEL
				local voxelTop = voxelBottom + VOXEL

				if surfaceHeight >= voxelTop then
					materials[lx][ly][lz] = getMaterialAt(worldX, worldZ, voxelBottom)
					occupancies[lx][ly][lz] = 1.0
				elseif surfaceHeight > voxelBottom then
					materials[lx][ly][lz] = getMaterialAt(worldX, worldZ, voxelBottom)
					occupancies[lx][ly][lz] = (surfaceHeight - voxelBottom) / VOXEL
				end
			end
		end
	end

	local originX = cx * CHUNK_STUDS
	local originZ = cz * CHUNK_STUDS
	local region = Region3.new(
		Vector3.new(originX, BASE_Y, originZ),
		Vector3.new(originX + CHUNK_STUDS, BASE_Y + maxYVoxels * VOXEL, originZ + CHUNK_STUDS)
	):ExpandToGrid(VOXEL)

	terrain:WriteVoxels(region, VOXEL, materials, occupancies)
end

--[[
	Generates the full terrain map in chunks with yielding.
]]
function TerrainService.generate()
	terrain:Clear()

	local numChunks = math.ceil(MAP_SIZE / CHUNK_STUDS)
	local totalChunks = numChunks * numChunks
	local completed = 0

	print(string.format("[TerrainService] Generating %d chunks...", totalChunks))

	for cx = 0, numChunks - 1 do
		for cz = 0, numChunks - 1 do
			generateChunk(cx, cz)
			completed += 1
			if completed % 4 == 0 then
				task.wait()
			end
		end
	end

	print("[TerrainService] Terrain generation complete.")
end

--[[
	Carves a rectangular region of terrain to Air.
	All voxels within the specified world-coordinate bounds are cleared.
]]
function TerrainService.carveRegion(
	minX: number, minZ: number,
	maxX: number, maxZ: number,
	fromY: number, toY: number
)
	local region = Region3.new(
		Vector3.new(minX, fromY, minZ),
		Vector3.new(maxX, toY, maxZ)
	):ExpandToGrid(VOXEL)

	local size = region.Size / VOXEL
	local sizeX = math.round(size.X)
	local sizeY = math.round(size.Y)
	local sizeZ = math.round(size.Z)

	if sizeX <= 0 or sizeY <= 0 or sizeZ <= 0 then
		return
	end

	local materials = make3D(sizeX, sizeY, sizeZ, Enum.Material.Air)
	local occupancies = make3D(sizeX, sizeY, sizeZ, 0)

	terrain:WriteVoxels(region, VOXEL, materials, occupancies)
end

--[[
	Fills a single voxel column at world (x, z) to the target height with
	the specified material. Clears everything above targetHeight to Air.
	Coordinates are snapped to the voxel grid.
]]
function TerrainService.fillColumn(
	x: number, z: number,
	targetHeight: number, material: Enum.Material
)
	local snappedX = math.floor(x / VOXEL) * VOXEL
	local snappedZ = math.floor(z / VOXEL) * VOXEL
	local maxYVoxels = math.ceil((MAX_HEIGHT + VOXEL) / VOXEL)

	local region = Region3.new(
		Vector3.new(snappedX, BASE_Y, snappedZ),
		Vector3.new(snappedX + VOXEL, BASE_Y + maxYVoxels * VOXEL, snappedZ + VOXEL)
	):ExpandToGrid(VOXEL)

	local materials = make3D(1, maxYVoxels, 1, Enum.Material.Air)
	local occupancies = make3D(1, maxYVoxels, 1, 0)

	for ly = 1, maxYVoxels do
		local voxelBottom = BASE_Y + (ly - 1) * VOXEL
		local voxelTop = voxelBottom + VOXEL

		if targetHeight >= voxelTop then
			materials[1][ly][1] = material
			occupancies[1][ly][1] = 1.0
		elseif targetHeight > voxelBottom then
			materials[1][ly][1] = material
			occupancies[1][ly][1] = (targetHeight - voxelBottom) / VOXEL
		end
	end

	terrain:WriteVoxels(region, VOXEL, materials, occupancies)
end

return TerrainService
