-- ==========================================
-- BUILD A BOAT - API IMAGE BUILDER (CENTERED & ELEVATED)
-- ==========================================

local HttpService = game:GetService("HttpService")
local players = game:GetService("Players")
local workspace = game:GetService("Workspace")
local coreGui = (gethui and gethui()) or game:GetService("CoreGui") or players.LocalPlayer:WaitForChild("PlayerGui")

local player = players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local blockData = player:WaitForChild("Data")
local blocksFolder = workspace:WaitForChild("Blocks")

-- Variables
local pastePercent = 0
local ignoreAnchored = true
local PRECISION = 10000 
local trackedAssignedBlocks = {}

-- Variables cho Build Ảnh API
local imageUrlInput = ""
local selectedMaterial = "WoodBlock"
local imageWidth = 32
local imageHeight = 32
local loadedImageBuildData = nil

local VERCEL_API_URL = "https://api-aeoo.vercel.app/api/get-pixels"

-- ==========================================
-- HÀM HỖ TRỢ & CÔNG CỤ XÂY DỰNG
-- ==========================================
local function snapVector3(vec)
    return Vector3.new(math.round(vec.X * PRECISION) / PRECISION, math.round(vec.Y * PRECISION) / PRECISION, math.round(vec.Z * PRECISION) / PRECISION)
end

local function snapCFrame(cf)
    local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
    return CFrame.new(
        math.round(x * PRECISION) / PRECISION, math.round(y * PRECISION) / PRECISION, math.round(z * PRECISION) / PRECISION,
        math.round(r00 * PRECISION) / PRECISION, math.round(r01 * PRECISION) / PRECISION, math.round(r02 * PRECISION) / PRECISION,
        math.round(r10 * PRECISION) / PRECISION, math.round(r11 * PRECISION) / PRECISION, math.round(r12 * PRECISION) / PRECISION,
        math.round(r20 * PRECISION) / PRECISION, math.round(r21 * PRECISION) / PRECISION, math.round(r22 * PRECISION) / PRECISION
    )
end

local function getBlockID(name)
    local stat = blockData:FindFirstChild(name)
    return stat and stat.Value or 0
end

local function getPlayerZone(playerInstance)
    if not playerInstance then return nil end
    local teamColor = playerInstance.TeamColor
    for _,v in pairs(workspace:GetChildren()) do
        if v:FindFirstChild("TeamColor") and v.TeamColor.Value == teamColor then return v end
    end
    return nil
end

local function colorMatch(c1, c2) return math.abs(c1.R - c2.R) < 0.01 and math.abs(c1.G - c2.G) < 0.01 and math.abs(c1.B - c2.B) < 0.01 end

local function getTool(toolName)
    local tool = character:FindFirstChild(toolName) or player.Backpack:FindFirstChild(toolName)
    if tool and tool.Parent == player.Backpack then tool.Parent = character end
    return character:FindFirstChild(toolName)
end

local function placeBlock(name, pos, relativeTo, Anchored)
    local tool = getTool("BuildingTool")
    if not tool or not tool:FindFirstChild("RF") then return end
    if not relativeTo then relativeTo = getPlayerZone(player) end
    local rawOffset = relativeTo and relativeTo.CFrame:ToObjectSpace(pos) or CFrame.new()
    local snappedOffset = snapCFrame(rawOffset)
    local args = { name, getBlockID(name), relativeTo, snappedOffset, ignoreAnchored and true or Anchored, snapCFrame(pos), false }
    task.spawn(function() pcall(function() tool.RF:InvokeServer(unpack(args)) end) end)
end

local function getBlockForAssigning(expected, createdList)
    local best, bestDist, bestIdx = nil, math.huge, nil
    for idx, b in ipairs(createdList) do
        if not trackedAssignedBlocks[idx] and b and b:FindFirstChild("PPart") and b.Name == expected.Name then
            local dist = (b.PPart.Position - expected.Pos.Position).Magnitude
            if dist < 0.3 then trackedAssignedBlocks[idx] = true; return b end
            if dist < bestDist then bestDist = dist; best = b; bestIdx = idx end
        end
    end
    if best and bestIdx then trackedAssignedBlocks[bestIdx] = true; return best end
    return nil
end

local function rescaleBlocksFast(blocksData)
    local tool = getTool("ScalingTool")
    if not tool or not tool:FindFirstChild("RF") then return end
    for i, data in ipairs(blocksData) do
        local block, pos, size = data[1], data[2], data[3]
        if block then
            task.spawn(function() pcall(function() tool.RF:InvokeServer(block, snapVector3(size), snapCFrame(pos)) end) end)
            if i % 20 == 0 then task.wait(0.02) end
        end
    end
end

local function paintBlocksBatch(blocksAndColors)
    local tool = getTool("PaintingTool")
    if not tool or not tool:FindFirstChild("RF") then return end
    local chunk = {}
    for i, data in ipairs(blocksAndColors) do
        local block, color = data[1], data[2]
        if block and block:FindFirstChild("PPart") and not colorMatch(block.PPart.Color, color) then table.insert(chunk, {block, color}) end
        if #chunk >= 60 then pcall(function() tool.RF:InvokeServer(chunk) end); chunk = {}; task.wait(0.03) end
    end
    if #chunk > 0 then pcall(function() tool.RF:InvokeServer(chunk) end) end
end

local function setTransparencyBatch(blocksAndTrans)
    local tool = getTool("PropertiesTool")
    if not tool or not tool:FindFirstChild("SetPropertieRF") then return end
    local clickGroups = {}
    for _, data in ipairs(blocksAndTrans) do
        local block, targetTrans = data[1], data[2]
        if block and block:FindFirstChild("PPart") then
            local currentTrans = block.PPart.Transparency
            if currentTrans ~= targetTrans then
                local calls = math.ceil(targetTrans / 0.25)
                if calls > 0 then
                    if not clickGroups[calls] then clickGroups[calls] = {} end
                    table.insert(clickGroups[calls], block)
                end
            end
        end
    end
    for calls, blocks in pairs(clickGroups) do
        local chunk = {}
        for i, b in ipairs(blocks) do
            table.insert(chunk, b)
            if #chunk >= 60 then
                for c = 1, calls do pcall(function() tool.SetPropertieRF:InvokeServer("Transparency", chunk) end) end
                chunk = {}; task.wait(0.03)
            end
        end
        if #chunk > 0 then
            for c = 1, calls do pcall(function() tool.SetPropertieRF:InvokeServer("Transparency", chunk) end) end
        end
    end
end

local function pasteBuild(t)
    if not t or #t == 0 then return end
    local myBase = getPlayerZone(player)
    if not myBase then return end
    pastePercent = 0
    local tCount = #t
    local adjustedBuild = {}
    for _, v in ipairs(t) do
        table.insert(adjustedBuild, {Name = v.Name, Pos = snapCFrame(myBase.CFrame * v.Pos), Transparency = v.Transparency, Anchored = v.Anchored, Size = v.Size, Color = v.Color})
    end

    local requiredTools = {"BuildingTool", "ScalingTool", "PaintingTool", "PropertiesTool"}
    for _, tName in ipairs(requiredTools) do getTool(tName) end
    task.wait(0.3) 

    local lastPlaced = tick()
    local c = blocksFolder.DescendantAdded:Connect(function(desc) if desc:IsA("Model") or desc:IsA("BasePart") then lastPlaced = tick() end end) 
    
    for i,v in ipairs(adjustedBuild) do
        placeBlock(v.Name, v.Pos, myBase, v.Anchored)
        pastePercent = (i / tCount) * 40
        if i % 40 == 0 then task.wait() end
    end
    
    repeat task.wait(0.05) until tick() - lastPlaced > 0.8
    if c then c:Disconnect() end
    
    local myFolder = blocksFolder:FindFirstChild(player.Name)
    local playerBaseList = myFolder and myFolder:GetChildren() or {}
    trackedAssignedBlocks = {}
    local scaleData, paintData, transData = {}, {}, {}
    
    for i,v in ipairs(adjustedBuild) do
        local b = getBlockForAssigning(v, playerBaseList)
        if b then
            table.insert(scaleData, {b, v.Pos, v.Size})
            table.insert(paintData, {b, v.Color})
            table.insert(transData, {b, v.Transparency})
        end
        pastePercent = 40 + ((i / tCount) * 20)
        if i % 60 == 0 then task.wait() end
    end
    
    pastePercent = 70; rescaleBlocksFast(scaleData)
    pastePercent = 85; paintBlocksBatch(paintData)
    pastePercent = 95; setTransparencyBatch(transData)
    pastePercent = 100; task.wait(0.5); pastePercent = 0
end

-- ==========================================
-- XỬ LÝ ẢNH THÔNG QUA API VERCEL (CĂN GIỮA & NÂNG CAO)
-- ==========================================
local function fetchAndParseImagePixels(url, targetW, targetH, material)
    if url == "" then return nil end

    local apiUrl = VERCEL_API_URL .. "?url=" .. url .. "&w=" .. targetW .. "&h=" .. targetH
    local success, res = pcall(function() return game:HttpGet(apiUrl) end)
    if not success or res == "" then return nil end

    local successJson, decoded = pcall(function() return HttpService:JSONDecode(res) end)
    if not successJson or not decoded or decoded.error then return nil end

    local buildData = {}
    local scale = 1 -- Chuẩn kích thước 1x1x1 stud
    local heightOffset = 15 -- Độ cao so với mặt đất sân nhà (15 studs)

    for _, p in ipairs(decoded) do
        -- Căn giữa chiều rộng: (p.x - 1 - targetW / 2)
        local xPos = (p.x - 1 - (targetW / 2)) * scale
        local yPos = (targetH - p.y) * scale + heightOffset

        table.insert(buildData, {
            Name = material,
            Pos = CFrame.new(xPos, yPos, 0),
            Transparency = 0,
            Anchored = true,
            Size = Vector3.new(scale, scale, scale),
            Color = Color3.fromRGB(p.r, p.g, p.b)
        })
    end

    return (#buildData > 0) and buildData or nil
end

-- ==========================================
-- RAYFIELD UI - TAB BUILD ẢNH API
-- ==========================================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
   Name = "BABFT - API Image Builder",
   Icon = 0, LoadingTitle = "API Image System", LoadingSubtitle = "Centered & Fast Build",
   Theme = "Default", ConfigurationSaving = { Enabled = false }
})

local imageTab = Window:CreateTab("Build Ảnh API", "image")

imageTab:CreateInput({
    Name = "URL Ảnh (http/https)", PlaceholderText = "Dán link ảnh vào đây...", RemoveTextOnFocus = false,
    Callback = function(Text) imageUrlInput = Text end,
})

local ExpandedMaterials = {
    "WoodBlock", "PlasticBlock", "ConcreteBlock", "MarbleBlock", "NeonBlock", 
    "GoldBlock", "ObsidianBlock", "SmoothBlock", "GlassBlock", "TitaniumBlock", 
    "MetalBlock", "RustedBlock", "FabricBlock", "IceBlock", "SnowBlock", 
    "SandBlock", "DirtBlock", "GrassBlock", "StoneBlock", "BrickBlock", 
    "CoalBlock", "BouncyBlock", "FoilBlock", "GlueBlock", "CakeBlock"
}

imageTab:CreateDropdown({
    Name = "Chọn Vật Liệu Xây Ảnh",
    Options = ExpandedMaterials,
    CurrentOption = {"PlasticBlock"},
    MultipleOptions = false,
    Callback = function(Options) selectedMaterial = Options[1] end,
})

imageTab:CreateSlider({
    Name = "Chiều Rộng Ảnh (Width - Pixel)", Range = {10, 100}, Increment = 2, Suffix = "px", CurrentValue = 32,
    Callback = function(Value) imageWidth = Value end,
})

imageTab:CreateSlider({
    Name = "Chiều Cao Ảnh (Height - Pixel)", Range = {10, 100}, Increment = 2, Suffix = "px", CurrentValue = 32,
    Callback = function(Value) imageHeight = Value end,
})

imageTab:CreateButton({
    Name = "📥 Tải Mảng Màu Từ API",
    Callback = function()
        if imageUrlInput ~= "" then
            Rayfield:Notify({Title = "Đang xử lý...", Content = "Đang gửi yêu cầu tới API Server...", Duration = 3})
            task.spawn(function()
                loadedImageBuildData = fetchAndParseImagePixels(imageUrlInput, imageWidth, imageHeight, selectedMaterial)
                if loadedImageBuildData then Rayfield:Notify({Title = "Thành công ✅", Content = "Đã nhận " .. #loadedImageBuildData .. " pixel màu chuẩn!", Duration = 3})
                else Rayfield:Notify({Title = "Lỗi", Content = "Không thể kết nối API hoặc đọc ảnh!", Duration = 3}) end
            end)
        else Rayfield:Notify({Title = "Lỗi", Content = "Vui lòng dán link ảnh trước!", Duration = 3}) end
    end,
})

imageTab:CreateButton({
    Name = "🔨 XÂY ẢNH (CĂN GIỮA + NÂNG CAO)",
    Callback = function()
        if loadedImageBuildData then
            task.spawn(function() pasteBuild(loadedImageBuildData) end)
            Rayfield:Notify({Title = "Bắt đầu xây", Content = "Đang tiến hành xây bức ảnh ở giữa sân!", Duration = 3})
        else Rayfield:Notify({Title = "Lỗi", Content = "Chưa tải dữ liệu ảnh từ API!", Duration = 3}) end
    end,
})

imageTab:CreateButton({
    Name = "🗑️ XÓA TẤT CẢ BLOCKS",
    Callback = function()
        task.spawn(function()
            local myFolder = blocksFolder:FindFirstChild(player.Name)
            if myFolder then
                local blocks = myFolder:GetChildren()
                if #blocks > 0 then
                    local deleteTool = getTool("DeleteTool") 
                    if deleteTool and deleteTool:FindFirstChild("RF") then
                        for i, block in ipairs(blocks) do
                            task.spawn(function() pcall(function() deleteTool.RF:InvokeServer(block) end) end)
                            if i % 40 == 0 then task.wait() end
                        end
                        Rayfield:Notify({Title = "Hoàn tất ✅", Content = "Đã xóa sạch các khối trên sân!", Duration = 3})
                    else
                        Rayfield:Notify({Title = "Lỗi", Content = "Không tìm thấy DeleteTool trong túi đồ!", Duration = 3})
                    end
                else
                    Rayfield:Notify({Title = "Thông báo", Content = "Không có khối nào trên sân để xóa!", Duration = 3})
                end
            end
        end)
    end,
})

local pasteStatus = imageTab:CreateParagraph({Title = "Tiến độ xây dựng", Content = "0%"})
task.spawn(function() while task.wait(0.2) do pasteStatus:Set({Title = "Tiến độ", Content = tostring(math.floor(pastePercent)) .. "%"}) end end)
