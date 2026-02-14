--!strict
--[[
	Water body definitions registry.
	Add entries here to place water bodies in the world.
	The user walks around, reads coordinates from the HUD (x,z y),
	and provides them here as centerX and centerZ.
	surfaceY is auto-derived from terrain height if omitted.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

local WaterBodies: { Types.WaterBodyDef } = {
	-- Example: a pond near the center of the map
	{ type = "pond", centerX = 200, centerZ = 200 },
}

return WaterBodies
