--!strict
--[[
	Water body definitions registry (manual overrides).
	Auto-detection via DepressionScanner handles most water bodies.
	Add entries here only for manual placements (e.g. a pool on a hilltop).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

local WaterBodies: { Types.WaterBodyDef } = {}

return WaterBodies
