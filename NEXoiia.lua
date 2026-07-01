--[[ .____ ________ ___. _____ __ | | __ _______ \_____ \\_ |___/ ____\_ __ ______ ____ _____ _/ |_ ___________ | | | | \__ \ / | \| __ \ __\ | \/ ___// ___\\__ \\ __\/ _ \_ __ \ | |___| | // __ \_/ | \ \_\ \ | | | /\___ \\ \___ / __ \| | ( <_> ) | \/ |_______ \____/(____ /\_______ /___ /__| |____//____ >\___ >____ /__| \____/|__| \/ \/ ​​\/ ​​\/ ​​\/ ​​\/ ​​\/ Chào mừng đến với LuaObfuscator.com (Phiên bản Alpha 0.10.9) ~ Trân trọng, Ferib ]]-- 
local v0 = game:GetService("Players")
local v1 = game:GetService("RunService")
local v2 = v0.LocalPlayer

local v3 = Instance.new("ScreenGui", game.CoreGui)
v3.Name = "Follow_GUI_Hybrid"

local v5 = Instance.new("Frame", v3)
v5.Size = UDim2.new(0, 220, 0, 190)
v5.Position = UDim2.new(0.8, 0, 0.4, 0)
v5.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
v5.Active = true
v5.Draggable = true
Instance.new("UICorner", v5).CornerRadius = UDim.new(0, 8)

local v12 = Instance.new("TextButton", v5)
v12.Size = UDim2.new(0, 30, 0, 30)
v12.Position = UDim2.new(1, -35, 0, 5)
v12.Text = "-"
v12.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
v12.TextColor3 = Color3.new(1, 1, 1)
v12.Font = Enum.Font.GothamBold
v12.TextSize = 18
Instance.new("UICorner", v12).CornerRadius = UDim.new(0, 5)

local v22 = Instance.new("TextLabel", v5)
v22.Size = UDim2.new(0.8, 0, 0, 30)
v22.Position = UDim2.new(0.05, 0, 0.05, 0)
v22.Text = "Mục tiêu: Chưa có"
v22.TextColor3 = Color3.new(1, 1, 1)
v22.BackgroundTransparency = 1
v22.Font = Enum.Font.GothamBold
v22.TextSize = 13
v22.TextXAlignment = Enum.TextXAlignment.Left

local v32 = Instance.new("TextBox", v5)
v32.Size = UDim2.new(0.9, 0, 0, 35)
v32.Position = UDim2.new(0.05, 0, 0.25, 0)
v32.PlaceholderText = "Nhập tên người chơi..."
v32.Text = ""
v32.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
v32.TextColor3 = Color3.new(1, 1, 1)
v32.Font = Enum.Font.Gotham
v32.TextSize = 12
Instance.new("UICorner", v32).CornerRadius = UDim.new(0, 5)

local v43 = Instance.new("TextBox", v5)
v43.Size = UDim2.new(0.9, 0, 0, 35)
v43.Position = UDim2.new(0.05, 0, 0.5, 0)
v43.PlaceholderText = "Tốc độ bay (Mặc định: 60)"
v43.Text = ""
v43.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
v43.TextColor3 = Color3.new(1, 1, 1)
v43.Font = Enum.Font.Gotham
v43.TextSize = 12
Instance.new("UICorner", v43).CornerRadius = UDim.new(0, 5)

local v53 = Instance.new("TextButton", v5)
v53.Size = UDim2.new(0.9, 0, 0, 35)
v53.Position = UDim2.new(0.05, 0, 0.75, 0)
v53.Text = "BÁM LƯNG: [ TẮT ]"
v53.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
v53.TextColor3 = Color3.new(1, 1, 1)
v53.Font = Enum.Font.GothamBold
v53.TextSize = 13
Instance.new("UICorner", v53).CornerRadius = UDim.new(0, 5)

local v62 = false
local v63 = nil
local v64 = false
local v65 = {}
local v66 = false

v12.MouseButton1Click:Connect(function()
    v64 = not v64
    if v64 then
        v5.Size = UDim2.new(0, 220, 0, 40)
        v32.Visible = false
        v43.Visible = false
        v53.Visible = false
        v12.Text = "+"
        v12.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
    else
        v5.Size = UDim2.new(0, 220, 0, 190)
        v32.Visible = true
        v43.Visible = true
        v53.Visible = true
        v12.Text = "-"
        v12.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    end
end)

v32.FocusLost:Connect(function()
    local v71 = string.lower(v32.Text)
    local v72 = false
    if v71 ~= "" then
        for v115, v116 in pairs(v0:GetPlayers()) do
            if (v116 ~= v2) and (string.lower(v116.Name):match("^" .. v71) or string.lower(v116.DisplayName):match("^" .. v71)) then
                v63 = v116
                v22.Text = "Mục tiêu: " .. v116.DisplayName
                v72 = true
                break
            end
        end
    end
    if not v72 then
        v63 = nil
        v22.Text = "Mục tiêu: Không tìm thấy"
    end
end)

local function v67()
    for v92, v93 in pairs(v65) do
        if v93 and v93.Parent then
            v93:Destroy()
        end
    end
    table.clear(v65)
    local v73 = v2.Character
    if v73 and v73:FindFirstChild("Humanoid") then
        v73.Humanoid.PlatformStand = false
    end
    v66 = false
end

local function v68(v74)
    v67()
    local v75 = Instance.new("Attachment", v74)
    local v76 = Instance.new("LinearVelocity", v74)
    v76.Attachment0 = v75
    v76.MaxForce = math.huge
    v76.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    v76.RelativeTo = Enum.ActuatorRelativeTo.World
    local v84 = Instance.new("AlignOrientation", v74)
    v84.Attachment0 = v75
    v84.Mode = Enum.OrientationAlignmentMode.OneAttachment
    v84.MaxTorque = math.huge
    v84.MaxAngularVelocity = math.huge
    table.insert(v65, v75)
    table.insert(v65, v76)
    table.insert(v65, v84)
    local v90 = v74.Parent:FindFirstChild("Humanoid")
    if v90 then
        v90.PlatformStand = true
    end
    return v76, v84
end

v53.MouseButton1Click:Connect(function()
    if not v63 then return end
    v62 = not v62
    
    if v62 then
        v53.Text = "BÁM LƯNG: [ BẬT ]"
        v53.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
        local v114 = v2.Character
        if v114 and v114:FindFirstChild("HumanoidRootPart") then
            v68(v114.HumanoidRootPart)
        end
    else
        v53.Text = "BÁM LƯNG: [ TẮT ]"
        v53.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
        v67()
    end
end)

v1.Heartbeat:Connect(function()
    if v62 and v63 then
        local v96, v97 = v2.Character, v63.Character
        if v96 and v97 and v96:FindFirstChild("HumanoidRootPart") and v97:FindFirstChild("HumanoidRootPart") then
            local v103, v104 = v96.HumanoidRootPart, v97.HumanoidRootPart
            local v105 = (v104.Position - v103.Position).Magnitude
            local v106 = v103:FindFirstChildOfClass("LinearVelocity")
            local v107 = v103:FindFirstChildOfClass("AlignOrientation")
            
            if not v106 or not v107 then
                v106, v107 = v68(v103)
            end
            
            if v105 > 15 then
                v66 = false
                local v142 = tonumber(v43.Text) or 60
                local v143 = (v104.Position - v103.Position).Unit
                local v144 = v143
                local v145 = RaycastParams.new()
                v145.FilterDescendantsInstances = {v96, v97}
                v145.FilterType = Enum.RaycastFilterType.Exclude
                
                local v149 = workspace:Raycast(v103.Position, v143 * math.clamp(v142 * 0.3, 5, 15), v145)
                if v149 then
                    local v154 = workspace:Raycast(v103.Position, Vector3.new(0, 15, 0), v145)
                    if not v154 then
                        v144 = (Vector3.new(0, 1, 0) + (v143 * 0.3)).Unit
                    else
                        v144 = (v103.CFrame.RightVector + (v143 * 0.3)).Unit
                    end
                end
                
                v106.VectorVelocity = v144 * v142
                local v151 = Vector3.new(v143.X, 0, v143.Z)
                if v151.Magnitude > 0.001 then
                    v107.CFrame = CFrame.lookAt(v103.Position, v103.Position + v151)
                end
            else
                v66 = true
                v106.VectorVelocity = Vector3.zero
            end
        elseif not v96 or not v96:FindFirstChild("HumanoidRootPart") then
            v62 = false
            v53.Text = "BÁM LƯNG: [ TẮT ]"
            v53.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
            v67()
        end
    end
end)

v1.RenderStepped:Connect(function()
    if v62 and v66 and v63 then
        local v98, v99 = v2.Character, v63.Character
        if v98 and v99 and v98:FindFirstChild("HumanoidRootPart") and v99:FindFirstChild("HumanoidRootPart") then
            local v109 = v98.HumanoidRootPart
            local v110 = v99.HumanoidRootPart
            v109.CFrame = v110.CFrame * CFrame.new(0, 0, 5)
            v109.Velocity = Vector3.zero
            v109.RotVelocity = Vector3.zero
        end
    end
end)
