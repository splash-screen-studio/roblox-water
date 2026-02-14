--!strict
local Types = {}

export type WaterBodyType = "puddle" | "pool" | "pond" | "lake" | "sea" | "ocean"

export type WaterBodyDef = {
	type: WaterBodyType,
	centerX: number,
	centerZ: number,
	surfaceY: number?,
	width: number?,
	length: number?,
	depth: number?,
	wallMaterial: Enum.Material?,
	waterColor: Color3?,
	waterTransparency: number?,
}

export type NoiseConfig = {
	seed: number,
	octaves: number,
	lacunarity: number,
	persistence: number,
	scale: number,
}

return Types
