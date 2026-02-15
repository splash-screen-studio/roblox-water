--!strict
print("roblox-water init.server 0.2.0")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local TerrainService = require(script.Services.TerrainService)
local DepressionScanner = require(script.Services.DepressionScanner)
local WaterBodyService = require(script.Services.WaterBodyService)
local ManualWaterBodies = require(script.Data.WaterBodies)

-- 1. Generate undulating terrain
TerrainService.generate()

-- 2. Set up spawn location on terrain surface
local spawnHeight = TerrainService.heightAt(Config.SPAWN.X, Config.SPAWN.Z)
local spawnLocation = Instance.new("SpawnLocation")
spawnLocation.Name = "Spawn"
spawnLocation.Anchored = true
spawnLocation.CanCollide = true
spawnLocation.Size = Vector3.new(6, 1, 6)
spawnLocation.Position = Vector3.new(
	Config.SPAWN.X,
	spawnHeight + Config.SPAWN.HEIGHT_OFFSET,
	Config.SPAWN.Z
)
spawnLocation.Transparency = 1
spawnLocation.Parent = workspace

-- 3. Auto-detect terrain depressions below sea level
local autoWaterBodies = DepressionScanner.scan(TerrainService)

-- 4. Merge auto-detected with manual definitions
local allWaterBodies = {}
for _, def in autoWaterBodies do
	table.insert(allWaterBodies, def)
end
for _, def in ManualWaterBodies do
	table.insert(allWaterBodies, def)
end

-- 5. Create all water bodies
WaterBodyService.init(TerrainService)
WaterBodyService.createAll(allWaterBodies)

print("roblox-water server ready.")
