--!strict
--[[
	HudController - Displays player coordinates in the top-right corner.
	Format: "x,z y" (just numbers, comma between x and z, space before y)
	Depends on: Config
	Does NOT know about: Terrain, Water, Swimming
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local HudController = {}

local player = Players.LocalPlayer
local positionLabel: TextLabel? = nil
local elapsed = 0

function HudController.init()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CoordinateHud"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 10
	screenGui.Parent = player.PlayerGui

	local label = Instance.new("TextLabel")
	label.Name = "PositionLabel"
	label.AnchorPoint = Vector2.new(1, 0)
	label.Position = UDim2.new(1, -Config.HUD.PADDING_PX, 0, Config.HUD.PADDING_PX)
	label.Size = UDim2.new(0, Config.HUD.LABEL_WIDTH_PX, 0, Config.HUD.LABEL_HEIGHT_PX)
	label.BackgroundColor3 = Config.HUD.BACKGROUND_COLOR
	label.BackgroundTransparency = Config.HUD.BACKGROUND_TRANSPARENCY
	label.TextColor3 = Config.HUD.TEXT_COLOR
	label.TextSize = Config.HUD.TEXT_SIZE
	label.Font = Config.HUD.FONT
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = "0,0 0"
	label.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Config.HUD.CORNER_RADIUS_PX)
	corner.Parent = label

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Config.HUD.INNER_PADDING_PX)
	padding.PaddingRight = UDim.new(0, Config.HUD.INNER_PADDING_PX)
	padding.PaddingBottom = UDim.new(0, Config.HUD.INNER_PADDING_PX)
	padding.PaddingLeft = UDim.new(0, Config.HUD.INNER_PADDING_PX)
	padding.Parent = label

	positionLabel = label

	RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		if elapsed < Config.HUD.UPDATE_INTERVAL then
			return
		end
		elapsed = 0
		HudController._update()
	end)

	print("[HudController] Initialized.")
end

function HudController._update()
	if not positionLabel then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	local pos = rootPart.Position
	positionLabel.Text = string.format("%d,%d %d", math.round(pos.X), math.round(pos.Z), math.round(pos.Y))
end

return HudController
