-- ==========================================
-- BUILD A BOAT - PIXEL VIDEO PLAYER (BẢN ỔN ĐỊNH)
-- Diff-paint + phát liên tục không khựng + bỏ frame theo đồng hồ thật
-- ==========================================

local RunService = game:GetService("RunService")
local players = game:GetService("Players")
local workspace = game:GetService("Workspace")

local player = players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local playerGui = player:WaitForChild("PlayerGui")
local blockData = player:WaitForChild("Data")
local blocksFolder = workspace:WaitForChild("Blocks")

player.CharacterAdded:Connect(function(char)
	character = char
end)

-- ==========================================
-- CẤU HÌNH
-- ==========================================
local PRECISION = 10000
local ROW_STRIDE = 4096     -- khoá pixel = y * 4096 + x (số nguyên, không tạo string mỗi frame)
local FRAME_TIMEOUT = 2     -- thời gian chờ tối đa trước khi nhả nhịp phát liên tục (giây)

local selectedMaterial = "NeonBlock"
local gridWidth, gridHeight = 128, 58
local pixelScale = 1
local heightOffset = 15
local loopVideo = true
local targetFPS = 10
local lockTargetFPS = true  -- true: dùng FPS cố định, false: dùng time trong file
local localInstant = true   -- lật màu cục bộ ngay lập tức (màn hình bạn nhìn đổi cùng lúc, hết rít)
local paintWorkers = 4      -- số gói gửi song song lên server
local chunkSize = 240       -- số ô mỗi gói
local colorTol = 5          -- bỏ qua thay đổi màu nhỏ <= N/255
local buildMaxWorkers = 32  -- luồng dựng/xóa lưới tối đa (tăng tốc dựng ngay lập tức)
local forceRescale = false  -- true: luôn căn lại kích thước mọi ô (chậm hơn)

local isPlaying = false
local playToken = 0
local screenReady = false

local videoData = { width = 128, height = 58, frames = {} }
local pixelSourceInput = ""
local scannedPixeFiles = {}

-- Trạng thái màn hình: mảng phẳng, chỉ số = y * screenW + x + 1
local screenW, screenH, cellCount = 0, 0, 0
local cellBlock, cellPart, cellSent, cellKey = {}, {}, {}, {}

-- Hàng đợi gửi màu nền để luồng phát khung hình luôn chạy liên tục, không bị khựng
local pendingChunkQueue = {}
local activeSendWorkers = 0
local maxQueuedChunks = 16

-- ==========================================
-- HÀM HỖ TRỢ
-- ==========================================
local function snapVector3(vec)
	return Vector3.new(
		math.round(vec.X * PRECISION) / PRECISION,
		math.round(vec.Y * PRECISION) / PRECISION,
		math.round(vec.Z * PRECISION) / PRECISION
	)
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
	for _, v in pairs(workspace:GetChildren()) do
		if v:FindFirstChild("TeamColor") and v.TeamColor.Value == teamColor then
			return v
		end
	end
	return nil
end

-- Ẩn / xóa UI chọn màu của PaintingTool nhưng giữ nguyên RemoteFunction (RF) để tô màu
local function hidePaintingToolUI(tool)
	pcall(function()
		if tool then
			for _, obj in ipairs(tool:GetDescendants()) do
				if obj:IsA("ScreenGui") or obj:IsA("BillboardGui") or obj:IsA("SurfaceGui") then
					obj.Enabled = false
					pcall(function() obj:Destroy() end)
				elseif obj:IsA("GuiObject") then
					local n = obj.Name:lower()
					if n:find("paint") or n:find("color") or n:find("palette") or n:find("picker") or n:find("hsv") or n:find("rgb") then
						obj.Visible = false
						pcall(function() obj:Destroy() end)
					end
				end
			end
		end

		for _, gui in ipairs(playerGui:GetChildren()) do
			if gui:IsA("ScreenGui") then
				local gn = gui.Name:lower()
				if gn:find("paint") or (gn:find("color") and not gn:find("rayfield")) or gn:find("palette") or gn:find("picker") then
					gui.Enabled = false
					pcall(function() gui:Destroy() end)
				else
					for _, desc in ipairs(gui:GetDescendants()) do
						if desc:IsA("GuiObject") then
							local dn = desc.Name:lower()
							if dn:find("paint") or dn:find("palette") or dn:find("colorpicker") or dn:find("color_picker") then
								desc.Visible = false
								pcall(function() desc:Destroy() end)
							end
						end
					end
				end
			end
		end
	end)
end

playerGui.ChildAdded:Connect(function(child)
	if child:IsA("ScreenGui") then
		local cn = child.Name:lower()
		if cn:find("paint") or (cn:find("color") and not cn:find("rayfield")) or cn:find("palette") or cn:find("picker") then
			child.Enabled = false
			pcall(function() child:Destroy() end)
		end
	end
end)

local function getTool(toolName)
	if not character then return nil end
	local tool = character:FindFirstChild(toolName) or player.Backpack:FindFirstChild(toolName)
	if tool and tool.Parent == player.Backpack then
		tool.Parent = character
	end
	local found = character:FindFirstChild(toolName)
	if toolName == "PaintingTool" and found then
		hidePaintingToolUI(found)
	end
	return found
end

-- Màu lưu dạng số nguyên: r * 65536 + g * 256 + b (nhẹ RAM, so sánh nhanh)
local function hexToPacked(hex)
	local n = #hex
	if n == 3 then
		local r = tonumber(hex:sub(1, 1), 16) * 17
		local g = tonumber(hex:sub(2, 2), 16) * 17
		local b = tonumber(hex:sub(3, 3), 16) * 17
		return r * 65536 + g * 256 + b
	end
	if n < 6 then return 0 end
	return tonumber(hex:sub(1, 6), 16) or 0
end

local function packedToColor3(c)
	return Color3.fromRGB(c // 65536, (c // 256) % 256, c % 256)
end

local function isClose(a, b, tol)
	if a == b then return true end
	if tol <= 0 then return false end
	local dr = a // 65536 - b // 65536
	local dg = (a // 256) % 256 - (b // 256) % 256
	local db = a % 256 - b % 256
	return dr <= tol and dr >= -tol and dg <= tol and dg >= -tol and db <= tol and db >= -tol
end

-- Chạy fn(i) cho i = 1..n song song. Bắt đầu với luồng cao hơn để dựng màn hình tức thì
-- và tự mở rộng tối đa maxWorkers khi thông lượng tăng.
local function parallelFor(n, startWorkers, fn, maxWorkers)
	if n <= 0 then return end
	maxWorkers = math.max(startWorkers, maxWorkers or startWorkers)
	local cursor, active, done = 0, 0, 0

	local function worker()
		while true do
			cursor += 1
			local i = cursor
			if i > n then break end
			pcall(fn, i)
			done += 1
		end
		active -= 1
	end

	local function addWorkers(k)
		for _ = 1, k do
			active += 1
			task.spawn(worker)
		end
	end

	local target = math.max(1, math.min(startWorkers, n))
	addWorkers(target)

	local lastTime, lastDone, lastRate = os.clock(), 0, 0
	while active > 0 do
		task.wait(0.05)
		local now = os.clock()
		if now - lastTime >= 0.5 then
			local rate = (done - lastDone) / (now - lastTime)
			if cursor < n and target < maxWorkers and rate >= lastRate * 0.95 then
				local add = math.min(8, maxWorkers - target)
				target += add
				addWorkers(add)
			end
			lastTime, lastDone, lastRate = now, done, rate
		end
	end
end

local function placeBlock(rf, name, id, pos, zone)
	local snappedOffset = snapCFrame(zone.CFrame:ToObjectSpace(pos))
	rf:InvokeServer(name, id, zone, snappedOffset, true, snapCFrame(pos), false)
end

-- ==========================================
-- SO KHỚP BLOCK BẰNG BĂM KHÔNG GIAN (thay vòng lặp O(N^2) gây đơ)
-- ==========================================
local function bucketKey(kx, ky, kz)
	return ((kx + 50000) * 100001 + (ky + 50000)) * 100001 + (kz + 50000)
end

local function indexFolder(folder, bs)
	local buckets = {}
	for _, b in ipairs(folder:GetChildren()) do
		local pp = b:FindFirstChild("PPart")
		if pp then
			local p = pp.Position
			local k = bucketKey(math.floor(p.X / bs), math.floor(p.Y / bs), math.floor(p.Z / bs))
			local list = buckets[k]
			if not list then
				list = {}
				buckets[k] = list
			end
			list[#list + 1] = b
		end
	end
	return buckets
end

local function findBlock(buckets, pos, name, taken, maxDist, bs)
	local kx, ky, kz = math.floor(pos.X / bs), math.floor(pos.Y / bs), math.floor(pos.Z / bs)
	local best, bestDist = nil, maxDist
	for dx = -1, 1 do
		for dy = -1, 1 do
			for dz = -1, 1 do
				local list = buckets[bucketKey(kx + dx, ky + dy, kz + dz)]
				if list then
					for _, b in ipairs(list) do
						if not taken[b] and b.Name == name then
							local pp = b:FindFirstChild("PPart")
							if pp then
								local d = (pp.Position - pos).Magnitude
								if d < bestDist then
									best, bestDist = b, d
								end
							end
						end
					end
				end
			end
		end
	end
	return best
end

local function matchCells(pending, buckets, template, material, taken, radius, bs)
	local missing = {}
	for n, i in ipairs(pending) do
		local b = findBlock(buckets, template[i].Position, material, taken, radius, bs)
		if b then
			taken[b] = true
			cellBlock[i] = b
			cellPart[i] = b:FindFirstChild("PPart")
		else
			missing[#missing + 1] = i
		end
		if n % 500 == 0 then RunService.Heartbeat:Wait() end
	end
	return missing
end

-- ==========================================
-- DỰNG LƯỚI MÀN HÌNH (TỐC ĐỘ CAO)
-- 1) Nhận lại block đã có sẵn đúng chỗ  2) Chỉ đặt ô còn thiếu
-- 3) Chỉ căn kích thước ô chưa đúng cỡ  4) Khởi động nhiều luồng ngay lập tức
-- ==========================================
local function waitForReplication(getFolder, expected, maxWait)
	local waited, lastCount, stable = 0, -1, 0
	while waited < maxWait do
		local folder = getFolder()
		local c = folder and #folder:GetChildren() or 0
		if c >= expected then return end
		if c == lastCount then
			stable += 0.15
		else
			stable = 0
			lastCount = c
		end
		if stable >= 0.6 then return end
		task.wait(0.15)
		waited += 0.15
	end
end

local function buildScreenGrid(w, h, material, scale, yOffset, setStatus)
	local zone = getPlayerZone(player)
	if not zone then return false end

	local buildTool = getTool("BuildingTool")
	local scaleTool = getTool("ScalingTool")
	getTool("PaintingTool")
	local buildRF = buildTool and buildTool:FindFirstChild("RF")
	local scaleRF = scaleTool and scaleTool:FindFirstChild("RF")
	if not buildRF then return false end

	local startClock = os.clock()
	screenReady = false
	screenW, screenH, cellCount = w, h, w * h
	cellBlock, cellPart, cellSent, cellKey = {}, {}, {}, {}

	-- Vị trí từng ô (căn giữa ngang, y = 0 ở trên cùng)
	local template = table.create(cellCount)
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local xPos = (x - (w / 2) + 0.5) * scale
			local yPos = ((h - 1 - y) * scale) + yOffset
			template[y * w + x + 1] = snapCFrame(zone.CFrame * CFrame.new(xPos, yPos, 0))
		end
	end

	local blockId = getBlockID(material)
	local bs = math.max(scale, 1)
	local strictR = math.min(0.3, scale * 0.4)
	local looseR = bs * 1.7
	local startWorkers = math.min(16, buildMaxWorkers)
	local taken = {}
	local pending = table.create(cellCount)
	for i = 1, cellCount do pending[i] = i end

	local function getFolder()
		return blocksFolder:FindFirstChild(player.Name)
	end

	-- attempt 0: chỉ nhận lại block có sẵn. attempt 1-3: đặt ô thiếu rồi so khớp lại
	for attempt = 0, 3 do
		if attempt == 0 then
			setStatus("Kiểm tra block có sẵn...")
		else
			local folder = getFolder()
			local expected = (folder and #folder:GetChildren() or 0) + #pending
			local list = pending
			local placed = 0
			parallelFor(#list, startWorkers, function(n)
				placeBlock(buildRF, material, blockId, template[list[n]], zone)
				placed += 1
				if placed % 500 == 0 then
					setStatus(string.format("Đang đặt block %d/%d...", placed, #list))
				end
			end, buildMaxWorkers)
			if not getFolder() then blocksFolder:WaitForChild(player.Name, 3) end
			waitForReplication(getFolder, expected, 5)
		end

		local folder = getFolder()
		if folder then
			pending = matchCells(pending, indexFolder(folder, bs), template, material, taken, strictR, bs)
		end
		if #pending == 0 then break end
	end

	-- Ô còn sót: nới lỏng bán kính tìm block
	if #pending > 0 then
		local folder = getFolder()
		if folder then
			pending = matchCells(pending, indexFolder(folder, bs), template, material, taken, looseR, bs)
		end
	end

	-- Chỉ căn lại những ô chưa đúng kích thước / vị trí
	local size = snapVector3(Vector3.new(scale, scale, scale))
	local assigned, needScale = 0, {}
	for i = 1, cellCount do
		local part = cellPart[i]
		if part then
			assigned += 1
			if forceRescale
				or (part.Size - size).Magnitude > 0.02
				or (part.Position - template[i].Position).Magnitude > 0.05 then
				needScale[#needScale + 1] = i
			end
		end
		if i % 800 == 0 then RunService.Heartbeat:Wait() end
	end

	if scaleRF and #needScale > 0 then
		local done = 0
		parallelFor(#needScale, startWorkers, function(n)
			local i = needScale[n]
			scaleRF:InvokeServer(cellBlock[i], size, template[i])
			done += 1
			if done % 500 == 0 then
				setStatus(string.format("Đang căn kích thước %d/%d...", done, #needScale))
			end
		end, buildMaxWorkers)
	end

	screenReady = assigned > 0
	return screenReady, #pending, assigned, os.clock() - startClock, #needScale
end

local function deleteBlocks(list)
	local tool = getTool("DeleteTool")
	local rf = tool and tool:FindFirstChild("RF")
	if not rf then return false end
	parallelFor(#list, math.min(16, buildMaxWorkers), function(i)
		local b = list[i]
		if b and b.Parent then
			rf:InvokeServer(b)
		end
	end, buildMaxWorkers)
	return true
end

-- ==========================================
-- QUÉT WORKSPACE FILE .PIXE
-- ==========================================
local function scanWorkspacePixeFiles(rootDir)
	local results = {}
	if type(listfiles) ~= "function" then
		return results
	end

	local function walk(dir)
		local ok, entries = pcall(function()
			return listfiles(dir)
		end)
		if not ok or type(entries) ~= "table" then return end

		for _, entry in ipairs(entries) do
			local normalized = tostring(entry):gsub("\\", "/")
			if normalized:match("%.pixe$") then
				table.insert(results, entry)
			else
				local isFileOk, isFileVal = pcall(function()
					return isfile and isfile(entry)
				end)
				if not (isFileOk and isFileVal) then
					walk(entry)
				end
			end
		end
	end

	walk(rootDir or "")
	return results
end

-- ==========================================
-- ĐỌC FILE PIXEL VIDEO (grid / frame / x,y,#hex)
-- ==========================================
local function parsePixelVideoText(rawText)
	if not rawText or rawText == "" then return nil end

	local parsed = { width = gridWidth, height = gridHeight, frames = {} }
	local cur = nil
	local n = 0

	for line in rawText:gmatch("[^\r\n]+") do
		n += 1
		if n % 4000 == 0 then RunService.Heartbeat:Wait() end -- không đơ máy khi file lớn

		-- Dòng pixel là phổ biến nhất nên thử trước
		local x, y, hex = line:match("^%s*(%d+)%s*[,:%s]%s*(%d+)%s*[,:%s]%s*#?(%x+)%s*$")
		if x then
			if cur then
				cur.pix[tonumber(y) * ROW_STRIDE + tonumber(x)] = hexToPacked(hex)
			end
		else
			local gw, gh = line:match("^%s*grid%s+(%d+)%s+(%d+)")
			if gw then
				parsed.width, parsed.height = tonumber(gw), tonumber(gh)
			else
				local fIdx, fTime = line:match("^%s*frame%s+(%d+)%s+([%d%.]+)")
				if fIdx then
					cur = { index = tonumber(fIdx), time = tonumber(fTime) or 0, pix = {} }
					table.insert(parsed.frames, cur)
				end
			end
		end
	end

	table.sort(parsed.frames, function(a, b)
		if a.time == b.time then return a.index < b.index end
		return a.time < b.time
	end)

	return (#parsed.frames > 0) and parsed or nil
end

local function loadVideoFromInput(inputStr)
	if not inputStr or inputStr == "" then return nil end

	if inputStr:match("^https?://") then
		local ok, body = pcall(function() return game:HttpGet(inputStr) end)
		if not ok or not body or body == "" then return nil end
		return parsePixelVideoText(body)
	end

	local okFile, exists = pcall(function()
		return isfile and readfile and isfile(inputStr)
	end)
	if okFile and exists then
		local ok, body = pcall(function() return readfile(inputStr) end)
		if ok and body and body ~= "" then
			return parsePixelVideoText(body)
		end
	end

	return parsePixelVideoText(inputStr)
end

-- ==========================================
-- PHÁT VIDEO: DIFF -> GỬI NỀN LIÊN TỤC -> KHÔNG KHỰNG
-- ==========================================
local function buildCellKeys(srcW, srcH)
	cellKey = table.create(cellCount)
	for y = 0, screenH - 1 do
		local sy = math.min(srcH - 1, math.floor((y + 0.5) * srcH / screenH))
		for x = 0, screenW - 1 do
			local sx = math.min(srcW - 1, math.floor((x + 0.5) * srcW / screenW))
			cellKey[y * screenW + x + 1] = sy * ROW_STRIDE + sx
		end
	end
end

local function pumpSendQueue(rf, token)
	local desired = math.max(1, math.min(paintWorkers, 6))
	while activeSendWorkers < desired and #pendingChunkQueue > 0 and isPlaying and playToken == token do
		activeSendWorkers += 1
		task.spawn(function()
			while isPlaying and playToken == token and #pendingChunkQueue > 0 do
				local chunk = table.remove(pendingChunkQueue, 1)
				if not chunk then break end
				pcall(function()
					rf:InvokeServer(chunk)
				end)
				if #pendingChunkQueue > maxQueuedChunks then
					task.wait(0.004)
				end
			end
			activeSendWorkers -= 1
		end)
	end
end

-- Đẩy các chunk của frame vào hàng đợi nền và trả nhịp ngay lập tức để phát liên tục
local function sendFrame(rf, list, token)
	local total = #list
	if total == 0 then return true end

	-- Nếu hàng đợi bị dồn quá mức do server chậm, giữ phần đuôi mới nhất để tránh trễ nhịp
	if #pendingChunkQueue > maxQueuedChunks then
		local trimTo = math.max(4, maxQueuedChunks // 2)
		while #pendingChunkQueue > trimTo do
			table.remove(pendingChunkQueue, 1)
		end
	end

	local numChunks = math.max(1, math.ceil(total / chunkSize))
	local chunks = table.create(numChunks)
	for j = 1, numChunks do chunks[j] = {} end
	for n = 1, total do
		local c = chunks[(n - 1) % numChunks + 1]
		c[#c + 1] = list[n]
	end

	for j = 1, numChunks do
		if not isPlaying or playToken ~= token then break end
		pendingChunkQueue[#pendingChunkQueue + 1] = chunks[j]
	end

	pumpSendQueue(rf, token)
	return true
end

local function renderFrame(frame, token)
	if not isPlaying or playToken ~= token then return 0 end
	local tool = getTool("PaintingTool")
	local rf = tool and tool:FindFirstChild("RF")
	if not rf then return 0 end

	local pix = frame.pix
	local list, count = {}, 0
	local tol = colorTol
	for i = 1, cellCount do
		local part = cellPart[i]
		if part and part.Parent then
			local c = pix[cellKey[i]] or 0
			local sent = cellSent[i]
			if sent == nil or not isClose(sent, c, tol) then
				cellSent[i] = c
				count += 1
				local col = packedToColor3(c)
				list[count] = { cellBlock[i], col }
				if localInstant then
					part.Color = col
				end
			end
		end
	end
	if count == 0 then return 0 end

	sendFrame(rf, list, token)
	return count
end

local function playPixelVideo(data, statusCallback)
	local frames = data.frames
	local n = #frames
	if n == 0 then return end
	if not screenReady then
		if statusCallback then statusCallback("Chưa dựng màn hình lưới!") end
		return
	end

	playToken += 1
	local token = playToken
	isPlaying = true
	pendingChunkQueue = {}
	buildCellKeys(data.width, data.height)

	local fps = math.max(0.1, targetFPS)
	local interval = 1 / fps
	local t0 = frames[1].time
	local lastT = frames[n].time - t0
	local duration = lockTargetFPS and (n * interval) or (lastT + (n > 1 and lastT / (n - 1) or interval))

	local function frameIndexAt(elapsed)
		if lockTargetFPS then
			local idx = math.floor(elapsed * fps) + 1
			if idx > n then return nil end
			return idx
		end
		if elapsed >= duration then return nil end
		local lo, hi = 1, n
		while lo < hi do
			local mid = (lo + hi + 1) // 2
			if frames[mid].time - t0 <= elapsed then lo = mid else hi = mid - 1 end
		end
		return lo
	end

	local dropped, lastReport = 0, 0
	while isPlaying and playToken == token do
		local startClock = os.clock()
		local lastIdx = 0

		while isPlaying and playToken == token do
			local idx = frameIndexAt(os.clock() - startClock)
			if not idx then break end

			if idx == lastIdx then
				RunService.Heartbeat:Wait()
			else
				-- Tô chậm hơn nhịp thì bỏ qua frame cũ, nhảy thẳng tới frame đúng giờ để phát liên tục
				if lastIdx > 0 and idx > lastIdx + 1 then
					dropped += idx - lastIdx - 1
				end
				lastIdx = idx

				local t = os.clock()
				local sent = renderFrame(frames[idx], token)
				local ms = (os.clock() - t) * 1000

				-- Cập nhật UI tối đa 2 lần/giây (UI Rayfield cập nhật liên tục sẽ gây khựng)
				if statusCallback and (t - lastReport) >= 0.5 and isPlaying and playToken == token then
					lastReport = t
					statusCallback(string.format("Frame %d/%d | gửi %d ô | %.0f ms | bỏ %d frame", idx, n, sent, ms, dropped))
				end
			end
		end

		if not loopVideo then break end
		RunService.Heartbeat:Wait()
	end

	if playToken == token then
		isPlaying = false
		pendingChunkQueue = {}
	end
	if statusCallback then
		statusCallback("Đã dừng")
	end
end

local function stopPlayback()
	isPlaying = false
	playToken += 1
	pendingChunkQueue = {}
end

-- ==========================================
-- DANH SÁCH VẬT LIỆU (lấy theo block bạn thật sự có, tránh dropdown 250 mục gây lag UI)
-- ==========================================
local function collectMaterials()
	local seen, others = { NeonBlock = true }, {}
	for _, v in ipairs(blockData:GetChildren()) do
		if v.Name:match("Block$") and not seen[v.Name] then
			seen[v.Name] = true
			table.insert(others, v.Name)
		end
	end
	if #others < 4 then
		for _, name in ipairs({
			"PlasticBlock", "SmoothBlock", "WoodBlock", "StoneBlock", "BrickBlock", "SandBlock",
			"IceBlock", "GlassBlock", "MetalBlock", "TitaniumBlock", "GoldBlock", "ObsidianBlock",
			"MarbleBlock", "FabricBlock", "CoalBlock", "GrassBlock", "DirtBlock", "SnowBlock",
			"ConcreteBlock", "DiamondBlock", "CandyBlock", "BouncyBlock", "RustedBlock",
		}) do
			if not seen[name] then
				seen[name] = true
				table.insert(others, name)
			end
		end
	end
	table.sort(others)
	table.insert(others, 1, "NeonBlock")
	return others
end

-- ==========================================
-- RAYFIELD UI
-- ==========================================
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Window = Rayfield:CreateWindow({
	Name = "BABFT - Pixel Video Player",
	Icon = 0,
	LoadingTitle = "Pixel Video System",
	LoadingSubtitle = "Grid Screen & Frame Playback",
	Theme = "Default",
	ConfigurationSaving = { Enabled = false }
})

local videoTab = Window:CreateTab("Video Pixel", "video")
local statusParagraph = videoTab:CreateParagraph({ Title = "Trạng thái phát", Content = "Chưa tải video" })
local pixeFilesParagraph = videoTab:CreateParagraph({
	Title = "Danh sách file .pixe (Workspace)",
	Content = "Định dạng hỗ trợ: *.pixe | Chưa quét"
})

local function setStatus(text)
	statusParagraph:Set({ Title = "Trạng thái phát", Content = text })
end

local function refreshPixeFilesUI()
	scannedPixeFiles = scanWorkspacePixeFiles("")
	if type(listfiles) ~= "function" then
		pixeFilesParagraph:Set({
			Title = "Danh sách file .pixe (Workspace)",
			Content = "Định dạng hỗ trợ: *.pixe | Executor không hỗ trợ listfiles()"
		})
		return
	end

	if #scannedPixeFiles == 0 then
		pixeFilesParagraph:Set({
			Title = "Danh sách file .pixe (Workspace)",
			Content = "Định dạng hỗ trợ: *.pixe | Không tìm thấy file *.pixe nào"
		})
	else
		local lines = { "Định dạng hỗ trợ: *.pixe" }
		for i, filePath in ipairs(scannedPixeFiles) do
			table.insert(lines, i .. ". " .. tostring(filePath))
		end
		pixeFilesParagraph:Set({
			Title = "Danh sách file .pixe (Workspace)",
			Content = table.concat(lines, "\n")
		})
	end
end

videoTab:CreateButton({
	Name = "🔍 Quét Workspace (*.pixe)",
	Callback = function()
		refreshPixeFilesUI()
		Rayfield:Notify({
			Title = "Quét Workspace (.pixe)",
			Content = "Tìm thấy " .. #scannedPixeFiles .. " file đuôi .pixe",
			Duration = 3
		})
	end,
})

videoTab:CreateInput({
	Name = "Nguồn Pixel (Link Raw / File *.pixe / Nội dung)",
	PlaceholderText = "Dán link raw, tên file *.pixe hoặc nội dung pixel...",
	RemoveTextOnFocus = false,
	Callback = function(Text)
		pixelSourceInput = Text
	end,
})

videoTab:CreateDropdown({
	Name = "Vật Liệu Màn Hình",
	Options = collectMaterials(),
	CurrentOption = { "NeonBlock" },
	MultipleOptions = false,
	Callback = function(Options)
		selectedMaterial = Options[1]
	end,
})

local widthSlider = videoTab:CreateSlider({
	Name = "Chiều Rộng Lưới (Width) - nhỏ hơn = mượt hơn",
	Range = { 8, 128 },
	Increment = 2,
	Suffix = "px",
	CurrentValue = 128,
	Callback = function(Value)
		gridWidth = Value
	end,
})

local heightSlider = videoTab:CreateSlider({
	Name = "Chiều Cao Lưới (Height)",
	Range = { 8, 64 },
	Increment = 2,
	Suffix = "px",
	CurrentValue = 58,
	Callback = function(Value)
		gridHeight = Value
	end,
})

videoTab:CreateSlider({
	Name = "Tốc Độ Khung Hình (FPS)",
	Range = { 0.1, 20 },
	Increment = 0.1,
	Suffix = "FPS",
	CurrentValue = 10,
	Callback = function(Value)
		targetFPS = Value
	end,
})

videoTab:CreateSlider({
	Name = "Luồng Gửi Song Song (tăng nếu server theo kịp)",
	Range = { 1, 8 },
	Increment = 1,
	Suffix = "luồng",
	CurrentValue = 4,
	Callback = function(Value)
		paintWorkers = Value
	end,
})

videoTab:CreateSlider({
	Name = "Luồng Dựng Lưới Tối Đa (tự tăng dần)",
	Range = { 4, 32 },
	Increment = 1,
	Suffix = "luồng",
	CurrentValue = 32,
	Callback = function(Value)
		buildMaxWorkers = Value
	end,
})

videoTab:CreateSlider({
	Name = "Số Ô Mỗi Gói",
	Range = { 50, 400 },
	Increment = 10,
	Suffix = "ô",
	CurrentValue = 240,
	Callback = function(Value)
		chunkSize = Value
	end,
})

videoTab:CreateSlider({
	Name = "Độ Nhạy Màu (bỏ qua đổi nhỏ, cao = ít ô phải tô)",
	Range = { 0, 24 },
	Increment = 1,
	Suffix = "/255",
	CurrentValue = 5,
	Callback = function(Value)
		colorTol = Value
	end,
})

videoTab:CreateToggle({
	Name = "FPS cố định (bỏ qua time trong file)",
	CurrentValue = true,
	Callback = function(Value)
		lockTargetFPS = Value
	end,
})

videoTab:CreateToggle({
	Name = "Lật màu tức thì trên máy bạn (chống rít)",
	CurrentValue = true,
	Callback = function(Value)
		localInstant = Value
	end,
})

videoTab:CreateToggle({
	Name = "Luôn căn lại kích thước ô khi dựng (chậm hơn)",
	CurrentValue = false,
	Callback = function(Value)
		forceRescale = Value
	end,
})

videoTab:CreateToggle({
	Name = "Lặp lại video (Loop)",
	CurrentValue = true,
	Callback = function(Value)
		loopVideo = Value
	end,
})

videoTab:CreateButton({
	Name = "📥 1. Tải & Đọc File Pixel",
	Callback = function()
		task.spawn(function()
			setStatus("Đang phân tích dữ liệu pixel...")
			local targetInput = pixelSourceInput
			if (not targetInput or targetInput == "") and #scannedPixeFiles > 0 then
				targetInput = scannedPixeFiles[1]
				pixelSourceInput = targetInput
			end
			local loaded = loadVideoFromInput(targetInput)
			if loaded then
				videoData = loaded
				gridWidth, gridHeight = loaded.width, loaded.height
				pcall(function() widthSlider:Set(math.clamp(loaded.width, 8, 128)) end)
				pcall(function() heightSlider:Set(math.clamp(loaded.height, 8, 64)) end)
				setStatus(string.format("Đã tải %d khung hình (%dx%d)", #videoData.frames, videoData.width, videoData.height))
				Rayfield:Notify({
					Title = "Thành công ✅",
					Content = "Đã đọc " .. #videoData.frames .. " frame!",
					Duration = 3
				})
			else
				setStatus("Lỗi đọc dữ liệu pixel")
				Rayfield:Notify({
					Title = "Lỗi",
					Content = "Không đọc được dữ liệu pixel hợp lệ!",
					Duration = 3
				})
			end
		end)
	end,
})

videoTab:CreateButton({
	Name = "🧱 2. Dựng Lưới Màn Hình (1 Lần)",
	Callback = function()
		task.spawn(function()
			stopPlayback()
			setStatus("Đang dựng lưới " .. gridWidth .. "x" .. gridHeight .. "...")
			local ok, missing, assigned, secs, scaled = buildScreenGrid(gridWidth, gridHeight, selectedMaterial, pixelScale, heightOffset, setStatus)
			if ok then
				local note = (missing and missing > 0) and (" | thiếu " .. missing .. " ô") or ""
				setStatus(string.format("Màn hình sẵn sàng (%d ô) trong %.0fs | căn lại %d ô%s", assigned, secs, scaled, note))
				Rayfield:Notify({
					Title = "Hoàn tất ✅",
					Content = "Đã dựng lưới màn hình ở giữa sân!",
					Duration = 3
				})
			else
				setStatus("Lỗi dựng màn hình (kiểm tra Zone/Tool)")
				Rayfield:Notify({
					Title = "Lỗi",
					Content = "Không tìm thấy sân hoặc thiếu BuildingTool!",
					Duration = 3
				})
			end
		end)
	end,
})

videoTab:CreateButton({
	Name = "▶️ 3. Phát Video Pixel",
	Callback = function()
		if isPlaying then return end
		if #videoData.frames == 0 then
			Rayfield:Notify({ Title = "Lỗi", Content = "Chưa tải dữ liệu frame nào!", Duration = 3 })
			return
		end
		if not screenReady then
			Rayfield:Notify({ Title = "Lỗi", Content = "Hãy dựng lưới màn hình trước!", Duration = 3 })
			return
		end
		task.spawn(function()
			playPixelVideo(videoData, setStatus)
		end)
	end,
})

videoTab:CreateButton({
	Name = "⏸️ Dừng Phát",
	Callback = function()
		stopPlayback()
		setStatus("Đã tạm dừng")
	end,
})

videoTab:CreateButton({
	Name = "🧹 Xóa Riêng Màn Hình (giữ lại tàu)",
	Callback = function()
		stopPlayback()
		screenReady = false
		local list = {}
		for i = 1, cellCount do
			if cellBlock[i] then list[#list + 1] = cellBlock[i] end
		end
		cellBlock, cellPart, cellSent, cellKey = {}, {}, {}, {}
		task.spawn(function()
			if #list == 0 then return end
			if deleteBlocks(list) then
				setStatus("Đã xóa màn hình")
				Rayfield:Notify({ Title = "Hoàn tất ✅", Content = "Đã xóa các ô màn hình!", Duration = 3 })
			else
				Rayfield:Notify({ Title = "Lỗi", Content = "Không tìm thấy DeleteTool!", Duration = 3 })
			end
		end)
	end,
})

videoTab:CreateButton({
	Name = "🗑️ Xóa Tất Cả Blocks (cả tàu)",
	Callback = function()
		stopPlayback()
		screenReady = false
		cellBlock, cellPart, cellSent, cellKey = {}, {}, {}, {}
		task.spawn(function()
			local myFolder = blocksFolder:FindFirstChild(player.Name)
			if not myFolder then return end
			local blocks = myFolder:GetChildren()
			if #blocks == 0 then return end
			if deleteBlocks(blocks) then
				setStatus("Đã xóa sạch block")
				Rayfield:Notify({ Title = "Hoàn tất ✅", Content = "Đã xóa sạch các khối trên sân!", Duration = 3 })
			else
				Rayfield:Notify({ Title = "Lỗi", Content = "Không tìm thấy DeleteTool!", Duration = 3 })
			end
		end)
	end,
})

task.defer(refreshPixeFilesUI)
