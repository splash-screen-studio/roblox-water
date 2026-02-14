--!strict
local Config = {}

Config.VERSION = "0.1.0"

-- Terrain generation
Config.TERRAIN = {
	MAP_SIZE_STUDS = 512,
	MAX_HEIGHT_STUDS = 64,
	VOXEL_RESOLUTION = 4,
	CHUNK_SIZE_VOXELS = 32,
	BASE_Y = 0,
}

-- Fractal noise for heightmap
Config.NOISE = {
	SEED = 42,
	OCTAVES = 5,
	LACUNARITY = 2.0,
	PERSISTENCE = 0.4,
	SCALE = 80,
}

-- Material noise (shifts altitude band boundaries for natural variation)
Config.MATERIAL_NOISE = {
	SEED = 137,
	FREQUENCY = 0.05,
	STRENGTH = 0.12,
}

-- Altitude bands for terrain materials (normalized 0..1 thresholds)
Config.MATERIAL_BANDS = {
	{ threshold = 0.85, material = Enum.Material.Snow },
	{ threshold = 0.65, material = Enum.Material.Rock },
	{ threshold = 0.40, material = Enum.Material.Grass },
	{ threshold = 0.20, material = Enum.Material.Sand },
	{ threshold = 0.00, material = Enum.Material.Mud },
}

-- Water body system
Config.WATER = {
	WALL_THICKNESS_STUDS = 2,
	SURFACE_INSET_STUDS = 0.1,
	REFLECTANCE = 0.15,
	MATERIAL = Enum.Material.SmoothPlastic,
	SHORELINE_MATERIAL = Enum.Material.Sand,
	SHORELINE_RING_VOXELS = 1,
	BUOYANCY_FORCE = 50,
	SWIM_SPEED = 16,
}

-- Per-type defaults for water bodies
Config.WATER_BODY_DEFAULTS = {
	puddle = {
		width = 8,
		length = 8,
		depth = 2,
		wallMaterial = Enum.Material.Mud,
		waterColor = Color3.fromRGB(90, 70, 50),
		waterTransparency = 0.4,
	},
	pool = {
		width = 20,
		length = 20,
		depth = 8,
		wallMaterial = Enum.Material.Concrete,
		waterColor = Color3.fromRGB(100, 180, 220),
		waterTransparency = 0.3,
	},
	pond = {
		width = 32,
		length = 40,
		depth = 6,
		wallMaterial = Enum.Material.Rock,
		waterColor = Color3.fromRGB(60, 120, 80),
		waterTransparency = 0.5,
	},
	lake = {
		width = 80,
		length = 100,
		depth = 20,
		wallMaterial = Enum.Material.Rock,
		waterColor = Color3.fromRGB(33, 84, 185),
		waterTransparency = 0.5,
	},
	sea = {
		width = 200,
		length = 300,
		depth = 40,
		wallMaterial = Enum.Material.Sand,
		waterColor = Color3.fromRGB(20, 100, 160),
		waterTransparency = 0.55,
	},
	ocean = {
		width = 500,
		length = 500,
		depth = 60,
		wallMaterial = Enum.Material.Sand,
		waterColor = Color3.fromRGB(10, 60, 120),
		waterTransparency = 0.6,
	},
}

-- HUD settings
Config.HUD = {
	PADDING_PX = 10,
	FONT = Enum.Font.RobotoMono,
	TEXT_SIZE = 18,
	TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	BACKGROUND_COLOR = Color3.fromRGB(0, 0, 0),
	BACKGROUND_TRANSPARENCY = 0.5,
	CORNER_RADIUS_PX = 4,
	INNER_PADDING_PX = 6,
	UPDATE_INTERVAL = 0.1,
	LABEL_WIDTH_PX = 160,
	LABEL_HEIGHT_PX = 30,
}

-- CollectionService tag names
Config.TAGS = {
	WATER_VOLUME = "WaterVolume",
	WATER_WALL = "WaterWall",
	WATER_FLOOR = "WaterFloor",
}

-- Workspace folder names
Config.FOLDERS = {
	WATER_BODIES = "WaterBodies",
}

-- Spawn
Config.SPAWN = {
	X = 64,
	Z = 64,
	HEIGHT_OFFSET = 5,
}

-- Deep freeze all tables
local function deepFreeze(t: { [any]: any })
	table.freeze(t)
	for _, v in t do
		if type(v) == "table" then
			deepFreeze(v)
		end
	end
end

deepFreeze(Config)

return Config
