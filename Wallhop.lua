-- =========================================================
-- SCRIPT: WALLHOP PRO (Tối ưu độ nhạy + GUI Hiện đại)
-- Đã điều chỉnh: Tối ưu vật lý, chống khựng/kẹt ở góc hẹp, delay 0.1s
-- =========================================================

local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local guiParent = (RunService:IsStudio() and player:WaitForChild("PlayerGui")) or CoreGui

-- 1. TẠO SCREEN GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "WallHopPro_GUI"
screenGui.Parent = guiParent
screenGui.ResetOnSpawn = false

-- 2. TẠO KHUNG CHÍNH (FRAME)
local frame = Instance.new("Frame")
frame.Parent = screenGui
frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
frame.Size = UDim2.new(0, 220, 0, 110)
frame.Position = UDim2.new(0.5, -110, 0.5, -55)
frame.Active = true
frame.Draggable = true
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

-- Tiêu đề
local title = Instance.new("TextLabel")
title.Parent = frame
title.Size = UDim2.new(1, -30, 0, 30)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.Text = "WallHop Pro"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left

-- Nút Đóng (Destroy)
local destroyBtn = Instance.new("TextButton")
destroyBtn.Parent = frame
destroyBtn.Size = UDim2.new(0, 30, 0, 30)
destroyBtn.Position = UDim2.new(1, -30, 0, 0)
destroyBtn.BackgroundTransparency = 1
destroyBtn.Text = "X"
destroyBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
destroyBtn.Font = Enum.Font.GothamBold
destroyBtn.TextSize = 14

-- Trạng thái
local statusLabel = Instance.new("TextLabel")
statusLabel.Parent = frame
statusLabel.Size = UDim2.new(1, 0, 0, 20)
statusLabel.Position = UDim2.new(0, 0, 0, 32)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Trạng thái: TẮT"
statusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 12

-- Nút Bật/Tắt (Toggle)
local toggleBtn = Instance.new("TextButton")
toggleBtn.Parent = frame
toggleBtn.Size = UDim2.new(0.8, 0, 0, 35)
toggleBtn.Position = UDim2.new(0.1, 0, 0, 60)
toggleBtn.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
toggleBtn.Text = "BẬT"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 12
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 6)


-- =========================================================
-- LOGIC WALLHOP 
-- =========================================================
local toggle = false
local InfiniteJumpEnabled = true

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Blacklist

destroyBtn.MouseButton1Click:Connect(function()
    screenGui:Destroy()
end)

toggleBtn.MouseButton1Click:Connect(function()
    toggle = not toggle
    if toggle then
        toggleBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
        toggleBtn.Text = "TẮT"
        statusLabel.Text = "Trạng thái: ĐANG BẬT"
        statusLabel.TextColor3 = Color3.fromRGB(46, 204, 113)
    else
        toggleBtn.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
        toggleBtn.Text = "BẬT"
        statusLabel.Text = "Trạng thái: TẮT"
        statusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
    end
end)

-- Hàm quét tường (Giữ nguyên 8 hướng để bám tường tốt)
local function getWallRaycastResult()
    local character = player.Character
    if not character then return nil end
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return nil end
    
    raycastParams.FilterDescendantsInstances = {character}
    
    local lv = humanoidRootPart.CFrame.LookVector
    local rv = humanoidRootPart.CFrame.RightVector
    
    local directions = {
        lv, -lv, rv, -rv,
        (lv + rv).Unit, (lv - rv).Unit, (-lv + rv).Unit, (-lv - rv).Unit
    }
    
    local detectionDistance = 3
    local closestHit = nil
    local minDistance = detectionDistance + 1
    
    for _, direction in pairs(directions) do
        local ray = Workspace:Raycast(humanoidRootPart.Position, direction * detectionDistance, raycastParams)
        if ray and ray.Instance then
            if ray.Distance < minDistance then
                minDistance = ray.Distance
                closestHit = ray
            end
        end
    end
    return closestHit
end

-- Xử lý Jump
UserInputService.JumpRequest:Connect(function()
    if not toggle or not InfiniteJumpEnabled then return end
    
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    local camera = Workspace.CurrentCamera
    
    if not (humanoid and rootPart and camera) then return end
    
    local wallRayResult = getWallRaycastResult()
    if wallRayResult then
        InfiniteJumpEnabled = false 
        
        local wallNormal = wallRayResult.Normal
        local horizontalWallNormal = Vector3.new(wallNormal.X, 0, wallNormal.Z).Unit
        if horizontalWallNormal.Magnitude < 0.1 then
            horizontalWallNormal = (rootPart.CFrame.LookVector * Vector3.new(1,0,1)).Unit
            if horizontalWallNormal.Magnitude < 0.1 then
                horizontalWallNormal = Vector3.new(0,0,-1)
            end
        end
        local baseDirectionAwayFromWall = horizontalWallNormal
        
        local cameraLook = camera.CFrame.LookVector
        local horizontalCameraLook = Vector3.new(cameraLook.X, 0, cameraLook.Z).Unit
        if horizontalCameraLook.Magnitude < 0.1 then
            horizontalCameraLook = baseDirectionAwayFromWall
        end
        
        local maxInfluenceAngle = math.rad(40)
        local dot = math.clamp(baseDirectionAwayFromWall:Dot(horizontalCameraLook), -1, 1)
        local angleBetween = math.acos(dot)
        local cross = baseDirectionAwayFromWall:Cross(horizontalCameraLook)
        local rotationSign = math.sign(cross.Y)
        if rotationSign == 0 then angleBetween = 0 end
        
        local actualInfluenceAngle = math.min(angleBetween, maxInfluenceAngle)
        local adjustmentRotation = CFrame.Angles(0, actualInfluenceAngle * rotationSign, 0)
        local initialTargetLookDirection = adjustmentRotation * baseDirectionAwayFromWall
        
        rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + initialTargetLookDirection)
        RunService.Heartbeat:Wait()
        
        local didJump = false
        if humanoid and humanoid:GetState() ~= Enum.HumanoidStateType.Dead then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            didJump = true
            
            -- [FIX KẸT GÓC]: Bảo toàn vận tốc hiện tại, ép lực ngang văng ra cực nhỏ (còn 2) thay vì 15.
            local currentVel = rootPart.AssemblyLinearVelocity
            rootPart.AssemblyLinearVelocity = Vector3.new(
                currentVel.X, 
                50, -- Lực nhảy lên (Y axis)
                currentVel.Z
            ) + (initialTargetLookDirection * 2) 
        end
        
        if didJump then
            local directionTowardsWall = -baseDirectionAwayFromWall
            rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + directionTowardsWall)
        end
        
        task.wait(0.1) 
        InfiniteJumpEnabled = true 
    end
end)
