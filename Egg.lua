--[[
    Eggs Tool - Pro Version (ESP, TP, Auto Farm Priority)
    Hỗ trợ 3 Tab: Trứng trên map, Tất cả trứng (Ưu tiên auto), Cài đặt chung.
]] 

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

--==================================================
-- CẤU HÌNH
--==================================================
local Config = {
    ESPFillTransparency = 0.50,
    ESPOutlineTransparency = 0,
    GlobalESPColor = Color3.fromRGB(170, 85, 255),
    CustomESPColor = Color3.fromRGB(0, 255, 127), 
    MenuWidth = 480,  -- Mở rộng menu ra một chút để đủ chỗ cho 3 Tab
    MenuHeight = 310, 
    AnimationTime = 0.18,
}

local TargetParent = LocalPlayer:WaitForChild("PlayerGui")
local RenderedEggsFolder = Workspace:WaitForChild("RenderedEggs", 10)

--==================================================
-- BIẾN TRẠNG THÁI
--==================================================
local mainESPActive = false
local autoFarmActive = false
local eggData = {}                -- Dữ liệu trứng đang có trên map
local priorityAutoNames = {}      -- Danh sách tên trứng ưu tiên từ tab "Tất Cả Trứng"
local currentSearchQuery = ""
local currentAllEggsQuery = ""
local isMinimized = false

local homeCFrame = nil
local isFalling = false

--==================================================
-- HÀM HỖ TRỢ
--==================================================
local function getCharacter()
    return LocalPlayer.Character
end

local function getRootPart()
    local character = getCharacter()
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function getTargetPosition(target)
    if not target or not target.Parent then return nil end
    if target:IsA("Model") then return target:GetPivot().Position end
    if target:IsA("BasePart") then return target.Position end
    return nil
end

local function tween(object, properties, duration)
    if not object or not object.Parent then return end
    local info = TweenInfo.new(duration or Config.AnimationTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    TweenService:Create(object, info, properties):Play()
end

local function getEggImage(eggName)
    local img = ""
    pcall(function()
        local main = LocalPlayer.PlayerGui:FindFirstChild("Main")
        local eggsHolder = main.Index.Holders.EggsHolder
        img = eggsHolder[eggName].ImageLabel.Image
    end)
    return img ~= "" and img or "rbxassetid://10651105078"
end

local function getEggLuck(egg)
    local luck = "??"
    pcall(function()
        if typeof(egg) == "Instance" then
            if egg:GetAttribute("Luck") then 
                luck = tostring(egg:GetAttribute("Luck"))
            elseif egg:FindFirstChild("Luck") and egg.Luck:IsA("ValueBase") then
                luck = tostring(egg.Luck.Value)
            end
        end
    end)
    return luck
end

-- Lấy danh sách toàn bộ trứng có trong game từ thư mục Index
local function getAllEggNamesInGame()
    local names = {}
    pcall(function()
        local main = LocalPlayer.PlayerGui:FindFirstChild("Main")
        local eggsHolder = main.Index.Holders.EggsHolder
        for _, child in ipairs(eggsHolder:GetChildren()) do
            if not child:IsA("UIComponent") and child.Name ~= "UIGridLayout" and child.Name ~= "UIPadding" then
                table.insert(names, child.Name)
            end
        end
    end)
    return names
end

-- Vòng lặp Noclip để cho rơi tự do xuyên đất
RunService.Stepped:Connect(function()
    if isFalling then
        local char = getCharacter()
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end
    end
end)

--==================================================
-- CORE ESP
--==================================================
local function updateEggESP(egg)
    if not egg or (not egg:IsA("Model") and not egg:IsA("BasePart")) then return end

    if not eggData[egg] then
        eggData[egg] = { Highlight = nil, CustomColor = Config.CustomESPColor, CustomActive = false, CustomAuto = false }
    end

    local data = eggData[egg]
    local shouldShow = data.CustomActive or mainESPActive
    local color = data.CustomActive and data.CustomColor or Config.GlobalESPColor

    if shouldShow then
        if not data.Highlight or not data.Highlight.Parent then
            local highlight = Instance.new("Highlight")
            highlight.Name = "EggESP_Highlight"
            highlight.Adornee = egg
            highlight.FillTransparency = Config.ESPFillTransparency
            highlight.OutlineTransparency = Config.ESPOutlineTransparency
            highlight.Parent = egg
            data.Highlight = highlight
        end
        data.Highlight.FillColor = color
        data.Highlight.OutlineColor = color
        data.Highlight.Enabled = true
    else
        if data.Highlight then data.Highlight.Enabled = false end
    end
end

local function updateAllESP()
    if not RenderedEggsFolder then return end
    for _, egg in ipairs(RenderedEggsFolder:GetChildren()) do updateEggESP(egg) end
end

--==================================================
-- GIAO DIỆN (GUI)
--==================================================
local oldGui = TargetParent:FindFirstChild("EggsESP_Rect")
if oldGui then oldGui:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "EggsESP_Rect"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = TargetParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, Config.MenuWidth, 0, Config.MenuHeight)
MainFrame.Position = UDim2.new(0.5, -Config.MenuWidth / 2, 0.4, -Config.MenuHeight / 2)
MainFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)
Instance.new("UIStroke", MainFrame).Color = Color3.fromRGB(80, 80, 95)

-- TOP BAR
local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 35)
TopBar.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
TopBar.Parent = MainFrame
Instance.new("UICorner", TopBar).CornerRadius = UDim.new(0, 8)

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -50, 1, 0)
TitleLabel.Position = UDim2.new(0, 15, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "Egg Tool - Pro AutoFarm (Update)"
TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleLabel.TextSize = 14
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TopBar

local MinimizeBtn = Instance.new("TextButton")
MinimizeBtn.Size = UDim2.new(0, 25, 0, 25)
MinimizeBtn.Position = UDim2.new(1, -30, 0, 5)
MinimizeBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
MinimizeBtn.Text = "-"
MinimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.Parent = TopBar
Instance.new("UICorner", MinimizeBtn).CornerRadius = UDim.new(0, 6)

-- TABS BAR
local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, 0, 0, 30)
TabBar.Position = UDim2.new(0, 0, 0, 35)
TabBar.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
TabBar.Parent = MainFrame

local TabSpawnedBtn = Instance.new("TextButton")
TabSpawnedBtn.Size = UDim2.new(0.33, 0, 1, 0)
TabSpawnedBtn.BackgroundTransparency = 1
TabSpawnedBtn.Text = "🌍 Trứng Trên Map"
TabSpawnedBtn.TextColor3 = Color3.fromRGB(170, 85, 255)
TabSpawnedBtn.Font = Enum.Font.GothamBold
TabSpawnedBtn.TextSize = 12
TabSpawnedBtn.Parent = TabBar

local TabAllEggsBtn = Instance.new("TextButton")
TabAllEggsBtn.Size = UDim2.new(0.34, 0, 1, 0)
TabAllEggsBtn.Position = UDim2.new(0.33, 0, 0, 0)
TabAllEggsBtn.BackgroundTransparency = 1
TabAllEggsBtn.Text = "📚 Tất Cả Trứng"
TabAllEggsBtn.TextColor3 = Color3.fromRGB(150, 150, 150)
TabAllEggsBtn.Font = Enum.Font.GothamBold
TabAllEggsBtn.TextSize = 12
TabAllEggsBtn.Parent = TabBar

local TabSettingsBtn = Instance.new("TextButton")
TabSettingsBtn.Size = UDim2.new(0.33, 0, 1, 0)
TabSettingsBtn.Position = UDim2.new(0.67, 0, 0, 0)
TabSettingsBtn.BackgroundTransparency = 1
TabSettingsBtn.Text = "⚙️ Cài Đặt Chung"
TabSettingsBtn.TextColor3 = Color3.fromRGB(150, 150, 150)
TabSettingsBtn.Font = Enum.Font.GothamBold
TabSettingsBtn.TextSize = 12
TabSettingsBtn.Parent = TabBar

-- CONTAINERS
local SpawnedContainer = Instance.new("Frame")
SpawnedContainer.Size = UDim2.new(1, 0, 1, -65)
SpawnedContainer.Position = UDim2.new(0, 0, 0, 65)
SpawnedContainer.BackgroundTransparency = 1
SpawnedContainer.Parent = MainFrame

local AllEggsContainer = Instance.new("Frame")
AllEggsContainer.Size = UDim2.new(1, 0, 1, -65)
AllEggsContainer.Position = UDim2.new(0, 0, 0, 65)
AllEggsContainer.BackgroundTransparency = 1
AllEggsContainer.Visible = false
AllEggsContainer.Parent = MainFrame

local SettingsContainer = Instance.new("Frame")
SettingsContainer.Size = UDim2.new(1, 0, 1, -65)
SettingsContainer.Position = UDim2.new(0, 0, 0, 65)
SettingsContainer.BackgroundTransparency = 1
SettingsContainer.Visible = false
SettingsContainer.Parent = MainFrame

-- CHUYỂN TAB LOGIC
local function hideAllContainers()
    SpawnedContainer.Visible = false
    AllEggsContainer.Visible = false
    SettingsContainer.Visible = false
    TabSpawnedBtn.TextColor3 = Color3.fromRGB(150, 150, 150)
    TabAllEggsBtn.TextColor3 = Color3.fromRGB(150, 150, 150)
    TabSettingsBtn.TextColor3 = Color3.fromRGB(150, 150, 150)
end

TabSpawnedBtn.MouseButton1Click:Connect(function()
    hideAllContainers(); SpawnedContainer.Visible = true; TabSpawnedBtn.TextColor3 = Color3.fromRGB(170, 85, 255)
end)

TabAllEggsBtn.MouseButton1Click:Connect(function()
    hideAllContainers(); AllEggsContainer.Visible = true; TabAllEggsBtn.TextColor3 = Color3.fromRGB(170, 85, 255)
end)

TabSettingsBtn.MouseButton1Click:Connect(function()
    hideAllContainers(); SettingsContainer.Visible = true; TabSettingsBtn.TextColor3 = Color3.fromRGB(170, 85, 255)
end)

local function styleSmallBtn(btn, color)
    btn.BackgroundColor3 = color
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    btn.MouseEnter:Connect(function() tween(btn, {BackgroundTransparency = 0.2}, 0.1) end)
    btn.MouseLeave:Connect(function() tween(btn, {BackgroundTransparency = 0}, 0.1) end)
end

-- ================== CÀI ĐẶT TAB ==================
local ToggleGlobalESPBtn = Instance.new("TextButton")
ToggleGlobalESPBtn.Size = UDim2.new(1, -20, 0, 35)
ToggleGlobalESPBtn.Position = UDim2.new(0, 10, 0, 10)
ToggleGlobalESPBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
ToggleGlobalESPBtn.Text = "Bật ESP Toàn Bộ Trứng: OFF"
ToggleGlobalESPBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
ToggleGlobalESPBtn.Font = Enum.Font.GothamBold
ToggleGlobalESPBtn.Parent = SettingsContainer
Instance.new("UICorner", ToggleGlobalESPBtn).CornerRadius = UDim.new(0, 6)

ToggleGlobalESPBtn.MouseButton1Click:Connect(function()
    mainESPActive = not mainESPActive
    ToggleGlobalESPBtn.Text = mainESPActive and "Bật ESP Toàn Bộ Trứng: ON" or "Bật ESP Toàn Bộ Trứng: OFF"
    ToggleGlobalESPBtn.TextColor3 = mainESPActive and Color3.fromRGB(170, 85, 255) or Color3.fromRGB(220, 220, 220)
    updateAllESP()
end)

local SetHomeBtn = Instance.new("TextButton")
SetHomeBtn.Size = UDim2.new(1, -20, 0, 35)
SetHomeBtn.Position = UDim2.new(0, 10, 0, 55)
SetHomeBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
SetHomeBtn.Text = "📍 Đặt Vị Trí Hiện Tại Làm 'Nhà'"
SetHomeBtn.TextColor3 = Color3.fromRGB(255, 200, 50)
SetHomeBtn.Font = Enum.Font.GothamBold
SetHomeBtn.Parent = SettingsContainer
Instance.new("UICorner", SetHomeBtn).CornerRadius = UDim.new(0, 6)

SetHomeBtn.MouseButton1Click:Connect(function()
    local root = getRootPart()
    if root then
        homeCFrame = root.CFrame
        SetHomeBtn.Text = "📍 Đã Lưu Vị Trí Nhà!"
        task.wait(1.5)
        SetHomeBtn.Text = "📍 Đặt Vị Trí Hiện Tại Làm 'Nhà'"
    end
end)

local ToggleAutoFarmBtn = Instance.new("TextButton")
ToggleAutoFarmBtn.Size = UDim2.new(1, -20, 0, 35)
ToggleAutoFarmBtn.Position = UDim2.new(0, 10, 0, 100)
ToggleAutoFarmBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
ToggleAutoFarmBtn.Text = "▶ Bắt Đầu Auto Farm: OFF"
ToggleAutoFarmBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
ToggleAutoFarmBtn.Font = Enum.Font.GothamBold
ToggleAutoFarmBtn.Parent = SettingsContainer
Instance.new("UICorner", ToggleAutoFarmBtn).CornerRadius = UDim.new(0, 6)

ToggleAutoFarmBtn.MouseButton1Click:Connect(function()
    autoFarmActive = not autoFarmActive
    ToggleAutoFarmBtn.Text = autoFarmActive and "▶ Đang Auto Farm: ON" or "▶ Bắt Đầu Auto Farm: OFF"
    ToggleAutoFarmBtn.TextColor3 = autoFarmActive and Color3.fromRGB(0, 255, 127) or Color3.fromRGB(220, 220, 220)
    if autoFarmActive and not homeCFrame then
        local root = getRootPart()
        if root then homeCFrame = root.CFrame end 
    end
end)

-- ================== TRỨNG TRÊN MAP TAB ==================
local SearchBoxSpawned = Instance.new("TextBox")
SearchBoxSpawned.Size = UDim2.new(1, -20, 0, 25)
SearchBoxSpawned.Position = UDim2.new(0, 10, 0, 5)
SearchBoxSpawned.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
SearchBoxSpawned.PlaceholderText = "🔍 Tìm kiếm trứng trên map..."
SearchBoxSpawned.Text = ""
SearchBoxSpawned.TextColor3 = Color3.fromRGB(255, 255, 255)
SearchBoxSpawned.Font = Enum.Font.Gotham
SearchBoxSpawned.TextSize = 12
SearchBoxSpawned.Parent = SpawnedContainer
Instance.new("UICorner", SearchBoxSpawned).CornerRadius = UDim.new(0, 4)

local ScrollListSpawned = Instance.new("ScrollingFrame")
ScrollListSpawned.Size = UDim2.new(1, -20, 1, -40)
ScrollListSpawned.Position = UDim2.new(0, 10, 0, 35)
ScrollListSpawned.BackgroundTransparency = 1
ScrollListSpawned.ScrollBarThickness = 3
ScrollListSpawned.Parent = SpawnedContainer
local UIL1 = Instance.new("UIListLayout", ScrollListSpawned)
UIL1.Padding = UDim.new(0, 5)
UIL1:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    ScrollListSpawned.CanvasSize = UDim2.new(0, 0, 0, UIL1.AbsoluteContentSize.Y)
end)

local function populateSpawnedList()
    for _, child in ipairs(ScrollListSpawned:GetChildren()) do
        if child ~= UIL1 then child:Destroy() end
    end

    if not RenderedEggsFolder then return end

    local query = currentSearchQuery:lower()
    local eggs = {}
    for _, egg in ipairs(RenderedEggsFolder:GetChildren()) do
        if (egg:IsA("Model") or egg:IsA("BasePart")) and (query == "" or string.find(egg.Name:lower(), query, 1, true)) then
            table.insert(eggs, egg)
        end
    end
    table.sort(eggs, function(a, b) return a.Name:lower() < b.Name:lower() end)

    for _, egg in ipairs(eggs) do
        local Item = Instance.new("Frame")
        Item.Size = UDim2.new(1, -5, 0, 45)
        Item.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
        Item.Parent = ScrollListSpawned
        Instance.new("UICorner", Item).CornerRadius = UDim.new(0, 6)

        local EggImg = Instance.new("ImageLabel")
        EggImg.Size = UDim2.new(0, 35, 0, 35)
        EggImg.Position = UDim2.new(0, 5, 0.5, -17.5)
        EggImg.BackgroundTransparency = 1
        EggImg.Image = getEggImage(egg.Name)
        EggImg.Parent = Item

        local nameL = Instance.new("TextLabel")
        nameL.Size = UDim2.new(1, -190, 0, 20)
        nameL.Position = UDim2.new(0, 45, 0, 3)
        nameL.BackgroundTransparency = 1
        nameL.Text = egg.Name
        nameL.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameL.Font = Enum.Font.GothamBold
        nameL.TextSize = 13
        nameL.TextXAlignment = Enum.TextXAlignment.Left
        nameL.Parent = Item

        local luckL = Instance.new("TextLabel")
        luckL.Size = UDim2.new(1, -190, 0, 15)
        luckL.Position = UDim2.new(0, 45, 0, 23)
        luckL.BackgroundTransparency = 1
        luckL.Text = "🍀 May mắn: " .. getEggLuck(egg)
        luckL.TextColor3 = Color3.fromRGB(150, 255, 150)
        luckL.Font = Enum.Font.Gotham
        luckL.TextSize = 11
        luckL.TextXAlignment = Enum.TextXAlignment.Left
        luckL.Parent = Item

        if not eggData[egg] then eggData[egg] = { CustomActive = false, CustomAuto = false } end
        local data = eggData[egg]

        local TPBtn = Instance.new("TextButton")
        TPBtn.Size = UDim2.new(0, 45, 0, 28)
        TPBtn.Position = UDim2.new(1, -95, 0.5, -14)
        TPBtn.Text = "TP"
        TPBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        TPBtn.Font = Enum.Font.GothamBold
        TPBtn.TextSize = 11
        TPBtn.Parent = Item
        styleSmallBtn(TPBtn, Color3.fromRGB(0, 150, 255))
        TPBtn.MouseButton1Click:Connect(function()
            local root = getRootPart()
            local targetPos = getTargetPosition(egg)
            if root and targetPos then root.CFrame = CFrame.new(targetPos + Vector3.new(0, 5, 0)) end
        end)

        local ESPBtn = Instance.new("TextButton")
        ESPBtn.Size = UDim2.new(0, 45, 0, 28)
        ESPBtn.Position = UDim2.new(1, -45, 0.5, -14)
        ESPBtn.Text = data.CustomActive and "ON" or "ESP"
        ESPBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        ESPBtn.Font = Enum.Font.GothamBold
        ESPBtn.TextSize = 11
        ESPBtn.Parent = Item
        styleSmallBtn(ESPBtn, data.CustomActive and Color3.fromRGB(0, 200, 100) or Color3.fromRGB(45, 45, 55))
        ESPBtn.MouseButton1Click:Connect(function()
            data.CustomActive = not data.CustomActive
            ESPBtn.Text = data.CustomActive and "ON" or "ESP"
            ESPBtn.BackgroundColor3 = data.CustomActive and Color3.fromRGB(0, 200, 100) or Color3.fromRGB(45, 45, 55)
            updateEggESP(egg)
        end)
    end
end
SearchBoxSpawned:GetPropertyChangedSignal("Text"):Connect(function()
    currentSearchQuery = SearchBoxSpawned.Text
    populateSpawnedList()
end)

-- ================== TẤT CẢ TRỨNG TAB (ƯU TIÊN) ==================
local SearchBoxAll = Instance.new("TextBox")
SearchBoxAll.Size = UDim2.new(1, -20, 0, 25)
SearchBoxAll.Position = UDim2.new(0, 10, 0, 5)
SearchBoxAll.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
SearchBoxAll.PlaceholderText = "🔍 Tìm kiếm trong toàn bộ trứng..."
SearchBoxAll.Text = ""
SearchBoxAll.TextColor3 = Color3.fromRGB(255, 255, 255)
SearchBoxAll.Font = Enum.Font.Gotham
SearchBoxAll.TextSize = 12
SearchBoxAll.Parent = AllEggsContainer
Instance.new("UICorner", SearchBoxAll).CornerRadius = UDim.new(0, 4)

local ScrollListAll = Instance.new("ScrollingFrame")
ScrollListAll.Size = UDim2.new(1, -20, 1, -40)
ScrollListAll.Position = UDim2.new(0, 10, 0, 35)
ScrollListAll.BackgroundTransparency = 1
ScrollListAll.ScrollBarThickness = 3
ScrollListAll.Parent = AllEggsContainer
local UIL2 = Instance.new("UIListLayout", ScrollListAll)
UIL2.Padding = UDim.new(0, 5)
UIL2:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    ScrollListAll.CanvasSize = UDim2.new(0, 0, 0, UIL2.AbsoluteContentSize.Y)
end)

local function populateAllEggsList()
    for _, child in ipairs(ScrollListAll:GetChildren()) do
        if child ~= UIL2 then child:Destroy() end
    end

    local query = currentAllEggsQuery:lower()
    local masterEggsList = getAllEggNamesInGame()
    table.sort(masterEggsList)

    for _, eggName in ipairs(masterEggsList) do
        if query == "" or string.find(eggName:lower(), query, 1, true) then
            local Item = Instance.new("Frame")
            Item.Size = UDim2.new(1, -5, 0, 45)
            Item.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
            Item.Parent = ScrollListAll
            Instance.new("UICorner", Item).CornerRadius = UDim.new(0, 6)

            local EggImg = Instance.new("ImageLabel")
            EggImg.Size = UDim2.new(0, 35, 0, 35)
            EggImg.Position = UDim2.new(0, 5, 0.5, -17.5)
            EggImg.BackgroundTransparency = 1
            EggImg.Image = getEggImage(eggName)
            EggImg.Parent = Item

            local nameL = Instance.new("TextLabel")
            nameL.Size = UDim2.new(1, -120, 1, 0)
            nameL.Position = UDim2.new(0, 45, 0, 0)
            nameL.BackgroundTransparency = 1
            nameL.Text = eggName
            nameL.TextColor3 = Color3.fromRGB(255, 255, 255)
            nameL.Font = Enum.Font.GothamBold
            nameL.TextSize = 13
            nameL.TextXAlignment = Enum.TextXAlignment.Left
            nameL.Parent = Item

            local isPriority = priorityAutoNames[eggName] or false

            local AutoBtn = Instance.new("TextButton")
            AutoBtn.Size = UDim2.new(0, 90, 0, 28)
            AutoBtn.Position = UDim2.new(1, -100, 0.5, -14)
            AutoBtn.Text = isPriority and "ƯU TIÊN: ON" or "BẬT ƯU TIÊN"
            AutoBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            AutoBtn.Font = Enum.Font.GothamBold
            AutoBtn.TextSize = 11
            AutoBtn.Parent = Item
            styleSmallBtn(AutoBtn, isPriority and Color3.fromRGB(255, 100, 50) or Color3.fromRGB(45, 45, 55))

            AutoBtn.MouseButton1Click:Connect(function()
                isPriority = not isPriority
                priorityAutoNames[eggName] = isPriority and true or nil
                AutoBtn.Text = isPriority and "ƯU TIÊN: ON" or "BẬT ƯU TIÊN"
                AutoBtn.BackgroundColor3 = isPriority and Color3.fromRGB(255, 100, 50) or Color3.fromRGB(45, 45, 55)
            end)
        end
    end
end
SearchBoxAll:GetPropertyChangedSignal("Text"):Connect(function()
    currentAllEggsQuery = SearchBoxAll.Text
    populateAllEggsList()
end)

--==================================================
-- LOGIC AUTO FARM LOOP
--==================================================
task.spawn(function()
    while task.wait(0.2) do
        if autoFarmActive and homeCFrame then
            -- Quét các trứng đang tồn tại trên map xem có quả nào thuộc danh sách ƯU TIÊN không
            local targetEgg = nil
            
            for _, egg in ipairs(RenderedEggsFolder:GetChildren()) do
                if (egg:IsA("Model") or egg:IsA("BasePart")) then
                    -- Nếu trứng có tên nằm trong danh sách priorityAutoNames
                    if priorityAutoNames[egg.Name] then
                        targetEgg = egg
                        break -- Tìm thấy 1 quả ưu tiên là farm ngay
                    end
                end
            end
            
            -- Thực hiện chu trình auto farm
            if targetEgg and targetEgg.Parent then
                local root = getRootPart()
                local targetPos = getTargetPosition(targetEgg)
                
                if root and targetPos then
                    -- 1. Bay tới chỗ trứng
                    root.CFrame = CFrame.new(targetPos + Vector3.new(0, 4, 0))
                    task.wait(0.5) 
                    
                    -- 2. Đè E nút nhặt (Tự động fire ProximityPrompt)
                    local prompt = targetEgg:FindFirstChildWhichIsA("ProximityPrompt", true)
                    if prompt then
                        fireproximityprompt(prompt, 1)
                    end
                    task.wait(0.5) 
                    
                    -- 3. Rơi tự do xuống lòng đất (Noclip bật)
                    isFalling = true
                    root.Velocity = Vector3.new(0, -60, 0) 
                    task.wait(1.5) 
                    isFalling = false
                    
                    -- 4. Dịch chuyển về nhà
                    root.CFrame = homeCFrame
                    task.wait(1) 
                end
            end
        end
    end
end)

--==================================================
-- KÉO THẢ & THU GỌN MENU
--==================================================
local dragging, dragInput, dragStart, startPosition
TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, startPosition = true, input.Position, MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
TopBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
    end
end)

MinimizeBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    TabBar.Visible = not isMinimized
    if isMinimized then
        hideAllContainers()
    else
        if TabSpawnedBtn.TextColor3 == Color3.fromRGB(170, 85, 255) then
            SpawnedContainer.Visible = true
        elseif TabAllEggsBtn.TextColor3 == Color3.fromRGB(170, 85, 255) then
            AllEggsContainer.Visible = true
        else
            SettingsContainer.Visible = true
        end
    end
    tween(MainFrame, {Size = UDim2.new(0, Config.MenuWidth, 0, isMinimized and 35 or Config.MenuHeight)}, 0.2)
    MinimizeBtn.Text = isMinimized and "+" or "-"
end)

-- KHỞI TẠO
if RenderedEggsFolder then
    RenderedEggsFolder.ChildAdded:Connect(function(egg)
        task.wait(0.1)
        if not isMinimized and SpawnedContainer.Visible then populateSpawnedList() end
    end)
    RenderedEggsFolder.ChildRemoved:Connect(function(egg)
        if eggData[egg] then eggData[egg] = nil end
        if not isMinimized and SpawnedContainer.Visible then populateSpawnedList() end
    end)
end
populateSpawnedList()
populateAllEggsList()
