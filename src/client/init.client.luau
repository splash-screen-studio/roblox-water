--!strict
print("roblox-water init.client 0.1.0")

game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, false)

local HudController = require(script.Controllers.HudController)
local SwimController = require(script.Controllers.SwimController)

HudController.init()
SwimController.init()

print("roblox-water client ready.")
