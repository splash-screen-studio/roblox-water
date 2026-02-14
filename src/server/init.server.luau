--!strict
print("roblox-water init.server 0.1.0")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local TerrainService = require(script.Services.TerrainService)
local WaterBodyService = require(script.Services.WaterBodyService)
local WaterBodies = require(script.Data.WaterBodies)

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

-- 3. Initialize water body system and create all defined water bodies
WaterBodyService.init(TerrainService)
WaterBodyService.createAll(WaterBodies)

print("roblox-water server ready.")
