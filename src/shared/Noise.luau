--!strict
--[[
	Pure fractal noise module.
	No game service dependencies - only math.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

local Noise = {}

--[[
	Multi-octave fractal Brownian motion noise.
	Returns a value roughly in the range -0.5 to 0.5.
	Inputs x,z are world coordinates.
]]
function Noise.fractal(x: number, z: number, config: Types.NoiseConfig): number
	local value = 0
	local amplitude = 1
	local frequency = 1
	local maxAmplitude = 0

	for _ = 1, config.octaves do
		value += math.noise(
			x * frequency / config.scale,
			z * frequency / config.scale,
			config.seed
		) * amplitude

		maxAmplitude += amplitude
		frequency *= config.lacunarity
		amplitude *= config.persistence
	end

	return value / maxAmplitude
end

return Noise
