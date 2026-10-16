--// xelhub — Multi-Game Hub
--// TSB: 7 = Auto Fight | 9 = Auto Serious | RightControl = Hide GUI
--// MM2: Silent Aim + Aimbot Murderer + Role ESP + Gun ESP
--// Unsupported games: shows warning + exits silently (no kick)

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local VIM     = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local plr     = Players.LocalPlayer

-- ============================================================
-- GAME DETECTION
-- ============================================================
local TSB_PLACE_ID = 107047579715724
local MM2_PLACE_ID = 142823291

local CURRENT_GAME = "UNSUPPORTED"
if game.PlaceId == TSB_PLACE_ID then
    CURRENT_GAME = "TSB"
elseif game.PlaceId == MM2_PLACE_ID then
    CURRENT_GAME = "MM2"
end

print("[xelhub] Detected: " .. CURRENT_GAME .. " (" .. game.PlaceId .. ")")

if CURRENT_GAME == "UNSUPPORTED" then
    local pg = plr:WaitForChild("PlayerGui")
    local warnGui = Instance.new("ScreenGui")
    warnGui.Name = "xelhub_warn"
    warnGui.ResetOnSpawn = false
    warnGui.Parent = pg

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 380, 0, 140)
    frame.Position = UDim2.new(0.5, -190, 0.5, -70)
    frame.BackgroundColor3 = Color3.fromRGB(24, 22, 20)
    frame.BorderSizePixel = 0
    frame.Parent = warnGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)

    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = Color3.fromRGB(220, 170, 90)
    stroke.Thickness = 1

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.Position = UDim2.new(0, 0, 0, 20)
    title.BackgroundTransparency = 1
    title.Text = "xelhub"
    title.TextColor3 = Color3.fromRGB(235, 228, 215)
    title.Font = Enum.Font.Code
    title.TextSize = 20
    title.Parent = frame

    local msg = Instance.new("TextLabel")
    msg.Size = UDim2.new(1, -20, 0, 60)
    msg.Position = UDim2.new(0, 10, 0, 55)
    msg.BackgroundTransparency = 1
    msg.Text = "Unsupported game.\n\nRequest support: @a7ql in dc"
    msg.TextColor3 = Color3.fromRGB(140, 130, 118)
    msg.Font = Enum.Font.Code
    msg.TextSize = 12
    msg.TextWrapped = true
    msg.Parent = frame

    task.wait(3)
    warnGui:Destroy()
    return
end

-- ============================================================
-- SHARED STATE
-- ============================================================
local CONFIG = { ChaseRange = 100 }

local S = {
    autoFight = false, autoSerious = false,
    espEnabled = false, espNames = true, espHealth = true,
    espOutline = true, espHighlight = false, espNPCs = false,
    espMurderer = true, espSheriff = true, espGun = true,
    espFriend = true, espHero = true,
    silentAim = false, aimbot = false, aimbotMurderer = false,
    aimPart = "Head", aimFOV = 150, aimSmooth = 5,
    target=nil, busy=false, lastDash=0,
    char=nil, hum=nil,
    espObjects = {},
    guiVisible = true,
}

local function bind(char)
    S.char = char; S.hum = char:WaitForChild("Humanoid")
end
if plr.Character then bind(plr.Character) end
plr.CharacterAdded:Connect(bind)

local function hrp() return S.char and S.char:FindFirstChild("HumanoidRootPart") end
local function isMoving() return S.hum and S.hum.MoveDirection.Magnitude > 0.05 end

-- ============================================================
-- INPUT
-- ============================================================
local function clickM1()
    local cam = workspace.CurrentCamera
    local x, y = cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2
    VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
    task.wait(0.01)
    VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
end
local function pressKey(kc, hold)
    hold = hold or 0.05
    VIM:SendKeyEvent(true, kc, false, game); task.wait(hold)
    VIM:SendKeyEvent(false, kc, false, game)
end
local function holdKey(kc, hold)
    VIM:SendKeyEvent(true, kc, false, game); task.wait(hold)
    VIM:SendKeyEvent(false, kc, false, game)
end

-- ============================================================
-- TARGETING
-- ============================================================
local function isValidTarget(model, includeNPCs)
    if not model or model == S.char then return false end
    local h = model:FindFirstChildOfClass("Humanoid")
    local t = model:FindFirstChild("HumanoidRootPart")
    if not h or not t or h.Health <= 0 then return false end
    if not includeNPCs and not Players:GetPlayerFromCharacter(model) then return false end
    return true
end

local function findTarget(includeNPCs)
    local me = hrp(); if not me then return nil end
    local best, bestDist = nil, CONFIG.ChaseRange
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= plr and p.Character and isValidTarget(p.Character, false) then
            local t = p.Character.HumanoidRootPart
            local d = (t.Position - me.Position).Magnitude
            if d < bestDist then best, bestDist = t, d end
        end
    end
    if includeNPCs then
        local function scan(parent)
            for _, obj in ipairs(parent:GetChildren()) do
                if obj:IsA("Model") and isValidTarget(obj, true) and not Players:GetPlayerFromCharacter(obj) then
                    local t = obj.HumanoidRootPart
                    local d = (t.Position - me.Position).Magnitude
                    if d < bestDist then best, bestDist = t, d end
                elseif obj:IsA("Folder") or obj:IsA("Model") then scan(obj) end
            end
        end
        scan(workspace)
    end
    return best
end

-- ============================================================
-- MM2 ROLE DETECTION
-- ============================================================
local function hasTool(character, toolName)
    if not character then return false end
    local inChar = character:FindFirstChild(toolName)
    if inChar then return true end
    local player = Players:GetPlayerFromCharacter(character)
    if player then
        local backpack = player:FindFirstChild("Backpack")
        if backpack and backpack:FindFirstChild(toolName) then return true end
    end
    return false
end

local function getRole(character)
    if hasTool(character, "Knife") then return "Murderer" end
    if hasTool(character, "Gun") then return "Sheriff" end
    return "Innocent"
end

local function isFriend(player)
    if player == plr then return false end
    local ok, result = pcall(function()
        return plr:IsFriendsWith(player.UserId)
    end)
    return ok and result
end

-- ============================================================
-- ESP
-- ============================================================
local function clearESP()
    for _, obj in pairs(S.espObjects) do
        if obj and obj.Parent then obj:Destroy() end
    end
    S.espObjects = {}
end

local ROLE_COLORS = {
    Murderer = Color3.fromRGB(255, 60, 60),
    Sheriff  = Color3.fromRGB(60, 140, 255),
    Innocent = Color3.fromRGB(200, 200, 200),
    Hero     = Color3.fromRGB(255, 220, 80),
    Friend   = Color3.fromRGB(255, 255, 255),
}

local function getESPColor(character)
    local player = Players:GetPlayerFromCharacter(character)
    if player and S.espFriend and isFriend(player) then
        return ROLE_COLORS.Friend, "FRIEND"
    end
    if CURRENT_GAME == "MM2" then
        local role = getRole(character)
        if role == "Murderer" and S.espMurderer then
            return ROLE_COLORS.Murderer, "MURDERER"
        end
        if role == "Sheriff" and S.espSheriff then
            return ROLE_COLORS.Sheriff, "SHERIFF"
        end
        if role == "Innocent" then
            return ROLE_COLORS.Innocent, nil
        end
    end
    return Color3.fromRGB(220, 170, 90), nil
end

local function buildESPFor(character)
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end
    local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
    if not head then return end

    local espColor, tagText = getESPColor(character)

    local bb = Instance.new("BillboardGui")
    bb.Name = "xel_ESP"; bb.Size = UDim2.new(0, 220, 0, 60)
    bb.StudsOffset = Vector3.new(0, 3, 0); bb.AlwaysOnTop = true
    bb.Parent = head
    table.insert(S.espObjects, bb)

    if S.espNames then
        local n = Instance.new("TextLabel")
        n.Size = UDim2.new(1, 0, 0, 20); n.BackgroundTransparency = 1
        n.Text = character.Name .. (tagText and (" ["..tagText.."]") or "")
        n.TextColor3 = espColor
        n.TextStrokeTransparency = 0; n.Font = Enum.Font.GothamBold; n.TextSize = 14
        n.Parent = bb; table.insert(S.espObjects, n)
    end

    if S.espHealth then
        local hum = character:FindFirstChildOfClass("Humanoid")
        if hum then
            local hp = Instance.new("TextLabel")
            hp.Size = UDim2.new(1, 0, 0, 16); hp.Position = UDim2.new(0, 0, 0, 20)
            hp.BackgroundTransparency = 1
            hp.Text = string.format("%d / %d", math.floor(hum.Health), math.floor(hum.MaxHealth))
            hp.TextColor3 = Color3.fromRGB(255, 120, 140); hp.TextStrokeTransparency = 0
            hp.Font = Enum.Font.Gotham; hp.TextSize = 12
            hp.Parent = bb; table.insert(S.espObjects, hp)
        end
    end

    if S.espOutline then
        local hi = Instance.new("Highlight")
        hi.FillColor = espColor; hi.FillTransparency = 0.75
        hi.OutlineColor = espColor; hi.OutlineTransparency = 0
        hi.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hi.Adornee = character; hi.Parent = character
        table.insert(S.espObjects, hi)
    end
end

-- Tight Gun ESP: only shows tools that are NOT in a player's hand/inventory
local function buildGunESP()
    if CURRENT_GAME ~= "MM2" or not S.espGun then return end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Tool") and (obj.Name == "Gun" or obj.Name == "Knife") then
            local ancestorModel = obj:FindFirstAncestorOfClass("Model")
            local isOnPlayer = ancestorModel and Players:GetPlayerFromCharacter(ancestorModel)
            if not isOnPlayer and not obj:FindFirstChild("xel_gunESP") then
                local handle = obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart")
                if handle then
                    local bb = Instance.new("BillboardGui")
                    bb.Name = "xel_gunESP"
                    bb.Size = UDim2.new(0, 100, 0, 20)
                    bb.StudsOffset = Vector3.new(0, 2, 0)
                    bb.AlwaysOnTop = true
                    bb.Parent = handle
                    local lbl = Instance.new("TextLabel")
                    lbl.Size = UDim2.new(1, 0, 1, 0)
                    lbl.BackgroundTransparency = 1
                    lbl.Text = "[GUN]"
                    lbl.TextColor3 = Color3.fromRGB(255, 220, 80)
                    lbl.TextStrokeTransparency = 0
                    lbl.Font = Enum.Font.GothamBold
                    lbl.TextSize = 14
                    lbl.Parent = bb
                    table.insert(S.espObjects, bb)
                end
            end
        end
    end
end

local function refreshESP()
    clearESP()
    if not S.espEnabled then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= plr and p.Character then buildESPFor(p.Character) end
    end
    if CURRENT_GAME == "TSB" and S.espNPCs then
        local function scan(parent)
            for _, obj in ipairs(parent:GetChildren()) do
                if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") and not Players:GetPlayerFromCharacter(obj) then
                    buildESPFor(obj)
                elseif obj:IsA("Folder") or obj:IsA("Model") then scan(obj) end
            end
        end
        scan(workspace)
    end
    if CURRENT_GAME == "MM2" then buildGunESP() end
end

-- ============================================================
-- TSB COMBAT
-- ============================================================
local HUNT = {
    FarDash = 45, MidWalk = 18, StrikeRange = 7,
    DashCooldown = 0.35, DashHold = 0.12,
    M1Delay = 0.105, SkillDelay = 0.14,
    PostCombo = 0.05, StuckTime = 1.2, MissBail = 2,
    LeadFactor = 0.20, SideStepOdds = 0.4, HitRecovery = 0.25,
}

local _stuckDist, _stuckTime = nil, 0
local _lastHealth = nil
local _lastHitTime = 0

task.spawn(function()
    while true do
        if S.hum then
            local hp = S.hum.Health
            if _lastHealth and hp < _lastHealth then _lastHitTime = tick() end
            _lastHealth = hp
        end
        task.wait(0.1)
    end
end)

local function justGotHit() return (tick() - _lastHitTime) < HUNT.HitRecovery end

local function humanoidHealthy()
    if not S.char or not S.char.Parent then return false end
    if not S.hum or not S.hum.Parent then
        local h = S.char:FindFirstChildOfClass("Humanoid")
        if h then S.hum = h end
    end
    return S.hum and S.hum.Health > 0
end

local function autoDash(side)
    local now = tick()
    if now - S.lastDash < HUNT.DashCooldown then return end
    S.lastDash = now
    local dirKey = side and (math.random() < 0.5 and Enum.KeyCode.A or Enum.KeyCode.D) or Enum.KeyCode.W
    holdKey(dirKey, HUNT.DashHold)
    pressKey(Enum.KeyCode.Q)
end

local function predictiveFace(target)
    local me = hrp(); if not me or not target then return end
    local vel = target.AssemblyLinearVelocity or Vector3.new()
    local predicted = target.Position + vel * HUNT.LeadFactor
    local flat = Vector3.new(predicted.X, me.Position.Y, predicted.Z)
    if (flat - me.Position).Magnitude < 0.3 then return end
    me.CFrame = CFrame.new(me.Position, flat)
end

local function approach(target)
    if isMoving() then return end
    local me = hrp(); if not me or not target then return end
    predictiveFace(target)
    local dist = (target.Position - me.Position).Magnitude
    if _stuckDist and math.abs(_stuckDist - dist) < 0.5 then
        if tick() - _stuckTime > HUNT.StuckTime then S.target = nil; _stuckDist = nil; return end
    else
        _stuckDist = dist; _stuckTime = tick()
    end
    if dist <= HUNT.StrikeRange then S.hum:MoveTo(me.Position)
    elseif dist <= HUNT.MidWalk then S.hum:MoveTo(target.Position); if math.random() < 0.15 then autoDash(true) end
    elseif dist <= HUNT.FarDash then autoDash(math.random() < HUNT.SideStepOdds); S.hum:MoveTo(target.Position)
    else S.hum:MoveTo(target.Position) end
end

local function fireCombo()
    if S.busy then return end
    S.busy = true
    task.spawn(function()
        local function getTargetHP()
            if not S.target or not S.target.Parent then return nil end
            local h = S.target.Parent:FindFirstChildOfClass("Humanoid")
            return h and h.Health or nil
        end
        local function shouldBail()
            if not humanoidHealthy() then return true end
            if not S.target or not S.target.Parent then return true end
            return false
        end
        pcall(function()
            local hpStart = getTargetHP()
            local misses = 0
            for i = 1, 3 do
                if shouldBail() then return end
                clickM1(); task.wait(HUNT.M1Delay)
                local hpNow = getTargetHP()
                if hpStart and hpNow and hpNow >= hpStart then
                    misses = misses + 1
                    if misses >= HUNT.MissBail then autoDash(true); return end
                else misses = 0; hpStart = hpNow end
            end
            if shouldBail() then return end
            holdKey(Enum.KeyCode.Space, 0.10); clickM1(); task.wait(HUNT.SkillDelay)
            pressKey(Enum.KeyCode.Four); task.wait(HUNT.SkillDelay)
            autoDash(true); task.wait(HUNT.SkillDelay)
            for i = 1, 3 do if shouldBail() then return end clickM1(); task.wait(HUNT.M1Delay) end
            pressKey(Enum.KeyCode.Two); task.wait(HUNT.SkillDelay)
            pressKey(Enum.KeyCode.Three); task.wait(HUNT.SkillDelay)
            autoDash(false); task.wait(HUNT.SkillDelay)
            for i = 1, 3 do if shouldBail() then return end clickM1(); task.wait(HUNT.M1Delay) end
            pressKey(Enum.KeyCode.One); task.wait(0.10)
        end)
        S.busy = false
    end)
end

if CURRENT_GAME == "TSB" then
    task.spawn(function()
        while true do
            if S.autoFight and humanoidHealthy() then
                if justGotHit() then task.wait(0.05)
                else
                    local me = hrp()
                    if not S.target or not S.target.Parent or not isValidTarget(S.target.Parent, true)
                       or (me and (S.target.Position - me.Position).Magnitude > CONFIG.ChaseRange) then
                        S.target = findTarget(true); _stuckDist = nil
                    end
                    if S.target then
                        approach(S.target)
                        local dist = (S.target.Position - me.Position).Magnitude
                        if dist <= HUNT.StrikeRange + 1 and not isMoving() then
                            fireCombo(); task.wait(HUNT.PostCombo)
                        else task.wait(0.02) end
                    else task.wait(0.08) end
                end
            else task.wait(0.05) end
        end
    end)
    task.spawn(function()
        while true do
            if S.autoSerious and S.hum and S.hum.Health > 0 then pressKey(Enum.KeyCode.G) end
            task.wait(1.0)
        end
    end)
end

-- ============================================================
-- MM2 FEATURES
-- ============================================================
local FOVCircle = nil
if CURRENT_GAME == "MM2" then
    if Drawing and Drawing.new then
        FOVCircle = Drawing.new("Circle")
        FOVCircle.Thickness = 1
        FOVCircle.Color = Color3.fromRGB(220, 170, 90)
        FOVCircle.Filled = false
        FOVCircle.Transparency = 1
        FOVCircle.Radius = S.aimFOV
        FOVCircle.Visible = false
    end

    local function getClosestInFOV(onlyMurderer)
        local closest, closestDist = nil, S.aimFOV
        local mousePos = UIS:GetMouseLocation()
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= plr and p.Character then
                if not (onlyMurderer and getRole(p.Character) ~= "Murderer") then
                    local part = p.Character:FindFirstChild(S.aimPart) or p.Character:FindFirstChild("HumanoidRootPart")
                    local hum = p.Character:FindFirstChildOfClass("Humanoid")
                    if part and hum and hum.Health > 0 then
                        local screenPos, onScreen = workspace.CurrentCamera:WorldToViewportPoint(part.Position)
                        if onScreen then
                            local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                            if dist < closestDist then closest = part; closestDist = dist end
                        end
                    end
                end
            end
        end
        return closest
    end

    pcall(function()
        local mt = getrawmetatable(game)
        local oldIndex = mt.__index
        setreadonly(mt, false)
        mt.__index = newcclosure(function(self, key)
            if (S.silentAim or S.aimbotMurderer) and (key == "Hit" or key == "Target") and self == plr:GetMouse() then
                local target
                if S.aimbotMurderer then target = getClosestInFOV(true) end
                if not target and S.silentAim then target = getClosestInFOV(false) end
                if target then return target end
            end
            return oldIndex(self, key)
        end)
        setreadonly(mt, true)
    end)

    RunService.RenderStepped:Connect(function()
        if FOVCircle then
            FOVCircle.Visible = S.silentAim or S.aimbot or S.aimbotMurderer
            FOVCircle.Radius = S.aimFOV
            FOVCircle.Position = UIS:GetMouseLocation()
        end
        if S.aimbot or S.aimbotMurderer then
            local target
            if S.aimbotMurderer then target = getClosestInFOV(true) end
            if not target and S.aimbot then target = getClosestInFOV(false) end
            if target then
                local cam = workspace.CurrentCamera
                local camPos = cam.CFrame.Position
                cam.CFrame = cam.CFrame:Lerp(CFrame.new(camPos, target.Position), 1 / math.max(S.aimSmooth, 1))
            end
        end
    end)

    task.spawn(function()
        while true do
            if S.espEnabled then refreshESP() end
            task.wait(1.0)
        end
    end)
end

-- ============================================================
-- GUI
-- ============================================================
local pg = plr:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("xelhub")
if old then old:Destroy() end

local screen = Instance.new("ScreenGui")
screen.Name = "xelhub"
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = pg

local BG        = Color3.fromRGB(24, 22, 20)
local BG_TOP    = Color3.fromRGB(20, 18, 16)
local PANEL     = Color3.fromRGB(30, 28, 26)
local CARD      = Color3.fromRGB(36, 33, 30)
local CARD_HOV  = Color3.fromRGB(45, 41, 37)
local TEXT      = Color3.fromRGB(235, 228, 215)
local TEXT_DIM  = Color3.fromRGB(140, 130, 118)
local TEXT_FAINT= Color3.fromRGB(90, 84, 76)
local DIVIDER   = Color3.fromRGB(55, 50, 44)
local ACCENT    = Color3.fromRGB(220, 170, 90)
local ACCENT_DIM= Color3.fromRGB(140, 105, 60)
local OFF_TRK   = Color3.fromRGB(52, 47, 42)
local TAB_ACTIVE= Color3.fromRGB(40, 36, 32)

local FONT_MONO = Enum.Font.Code
local FONT_BODY = Enum.Font.Gotham

local function tween(obj, props, time, style)
    TweenService:Create(obj, TweenInfo.new(time or 0.15, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.new(0, 760, 0, 460)
root.Position = UDim2.new(0.5, -380, 0.5, -230)
root.BackgroundColor3 = BG
root.BorderSizePixel = 0
root.Visible = false
root.Parent = screen
Instance.new("UICorner", root).CornerRadius = UDim.new(0, 4)
local rootStroke = Instance.new("UIStroke", root)
rootStroke.Color = DIVIDER
rootStroke.Thickness = 1

local shadow = Instance.new("ImageLabel")
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.Size = UDim2.new(1, 40, 1, 40)
shadow.Position = UDim2.new(0.5, 0, 0.5, 0)
shadow.BackgroundTransparency = 1
shadow.Image = "rbxassetid://5028857084"
shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
shadow.ImageTransparency = 0.55
shadow.ScaleType = Enum.ScaleType.Slice
shadow.SliceCenter = Rect.new(24, 24, 276, 276)
shadow.ZIndex = 0
shadow.Parent = root

local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, 0, 0, 40)
topBar.BackgroundColor3 = BG_TOP
topBar.BorderSizePixel = 0
topBar.Parent = root
Instance.new("UICorner", topBar).CornerRadius = UDim.new(0, 4)

local leftAccent = Instance.new("Frame")
leftAccent.Size = UDim2.new(0, 3, 0, 18)
leftAccent.Position = UDim2.new(0, 16, 0.5, -9)
leftAccent.BackgroundColor3 = ACCENT
leftAccent.BorderSizePixel = 0
leftAccent.Parent = topBar

local tabNames = {}
if CURRENT_GAME == "TSB" then
    tabNames = {"MAIN", "COMBAT", "PLAYER", "CONFIG", "MORE", "SUPPORT"}
elseif CURRENT_GAME == "MM2" then
    tabNames = {"MAIN", "AIMBOT", "PLAYER", "CONFIG", "MORE", "SUPPORT"}
end

local tabButtons = {}
local tabStartX = 40
local tabWidth = 102
local tabGap = 6

for i, name in ipairs(tabNames) do
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = UDim2.new(0, tabWidth, 0, 28)
    btn.Position = UDim2.new(0, tabStartX + (i-1)*(tabWidth + tabGap), 0, 6)
    btn.BackgroundColor3 = Color3.fromRGB(34, 31, 28)
    btn.TextColor3 = TEXT_DIM
    btn.Font = FONT_MONO
    btn.TextSize = 11
    btn.Text = name
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Parent = topBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 2)
    btn.MouseEnter:Connect(function()
        if _G.xel_TAB ~= name then tween(btn, {BackgroundColor3 = CARD_HOV, TextColor3 = TEXT}, 0.12) end
    end)
    btn.MouseLeave:Connect(function()
        if _G.xel_TAB ~= name then tween(btn, {BackgroundColor3 = Color3.fromRGB(34, 31, 28), TextColor3 = TEXT_DIM}, 0.12) end
    end)
    btn.MouseButton1Click:Connect(function() _G.xel_SWITCH_TAB(name) end)
    tabButtons[name] = btn
end

local ticksFrame = Instance.new("Frame")
ticksFrame.Size = UDim2.new(1, -40, 0, 10)
ticksFrame.Position = UDim2.new(0, 20, 0, 44)
ticksFrame.BackgroundTransparency = 1
ticksFrame.Parent = root
for i = 0, 40 do
    local t = Instance.new("Frame")
    t.Size = UDim2.new(0, 3, 0, 3)
    t.Position = UDim2.new(0, i * 17, 0, 4)
    t.BackgroundColor3 = DIVIDER
    t.BorderSizePixel = 0
    t.Rotation = 45
    t.Parent = ticksFrame
end

local contentArea = Instance.new("Frame")
contentArea.Size = UDim2.new(1, 0, 1, -60)
contentArea.Position = UDim2.new(0, 0, 0, 60)
contentArea.BackgroundTransparency = 1
contentArea.Parent = root

local leftCol = Instance.new("ScrollingFrame")
leftCol.Size = UDim2.new(0.62, -30, 1, -30)
leftCol.Position = UDim2.new(0, 20, 0, 10)
leftCol.BackgroundTransparency = 1
leftCol.BorderSizePixel = 0
leftCol.ScrollBarThickness = 3
leftCol.ScrollBarImageColor3 = ACCENT
leftCol.ScrollBarImageTransparency = 0.4
leftCol.CanvasSize = UDim2.new(0, 0, 0, 0)
leftCol.AutomaticCanvasSize = Enum.AutomaticSize.Y
leftCol.ScrollingDirection = Enum.ScrollingDirection.Y
leftCol.Parent = contentArea

local tabContents = {}
for _, name in ipairs(tabNames) do
    local f = Instance.new("Frame")
    f.Name = name
    f.Size = UDim2.new(1, -8, 0, 0)
    f.BackgroundTransparency = 1
    f.AutomaticSize = Enum.AutomaticSize.Y
    f.Visible = false
    f.Parent = leftCol
    tabContents[name] = f
end

local rightCol = Instance.new("Frame")
rightCol.Size = UDim2.new(0.38, -20, 1, -30)
rightCol.Position = UDim2.new(0.62, 10, 0, 10)
rightCol.BackgroundColor3 = PANEL
rightCol.BorderSizePixel = 0
rightCol.Parent = contentArea
Instance.new("UICorner", rightCol).CornerRadius = UDim.new(0, 3)
local rStroke = Instance.new("UIStroke", rightCol)
rStroke.Color = DIVIDER
rStroke.Thickness = 1

local rHeader = Instance.new("Frame")
rHeader.Size = UDim2.new(1, 0, 0, 32)
rHeader.BackgroundColor3 = Color3.fromRGB(20, 18, 16)
rHeader.BorderSizePixel = 0
rHeader.Parent = rightCol
Instance.new("UICorner", rHeader).CornerRadius = UDim.new(0, 3)

local rHeaderLbl = Instance.new("TextLabel")
rHeaderLbl.Size = UDim2.new(1, -20, 1, 0)
rHeaderLbl.Position = UDim2.new(0, 10, 0, 0)
rHeaderLbl.BackgroundTransparency = 1
rHeaderLbl.Text = "STATUS"
rHeaderLbl.TextColor3 = TEXT
rHeaderLbl.TextXAlignment = Enum.TextXAlignment.Left
rHeaderLbl.Font = FONT_MONO
rHeaderLbl.TextSize = 11
rHeaderLbl.Parent = rHeader

local statusBody = Instance.new("Frame")
statusBody.Size = UDim2.new(1, -20, 1, -50)
statusBody.Position = UDim2.new(0, 10, 0, 40)
statusBody.BackgroundTransparency = 1
statusBody.Parent = rightCol

local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, 0, 0, 100)
statusLbl.Position = UDim2.new(0, 0, 0, 0)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "idle"
statusLbl.TextColor3 = TEXT_DIM
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.TextYAlignment = Enum.TextYAlignment.Top
statusLbl.Font = FONT_MONO
statusLbl.TextSize = 11
statusLbl.TextWrapped = true
statusLbl.Parent = statusBody
_G.xel_STATUS = statusLbl

local actionRow = Instance.new("Frame")
actionRow.Size = UDim2.new(1, -20, 0, 60)
actionRow.Position = UDim2.new(0, 10, 1, -70)
actionRow.BackgroundTransparency = 1
actionRow.Parent = rightCol

local resetBtn = Instance.new("TextButton")
resetBtn.Size = UDim2.new(1, 0, 0, 28)
resetBtn.Position = UDim2.new(0, 0, 0, 0)
resetBtn.BackgroundColor3 = Color3.fromRGB(40, 36, 32)
resetBtn.TextColor3 = TEXT
resetBtn.Font = FONT_MONO
resetBtn.TextSize = 11
resetBtn.Text = "RESET CHARACTER"
resetBtn.BorderSizePixel = 0
resetBtn.AutoButtonColor = false
resetBtn.Parent = actionRow
Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 2)
local rbs = Instance.new("UIStroke", resetBtn)
rbs.Color = DIVIDER; rbs.Thickness = 1
resetBtn.MouseEnter:Connect(function() tween(resetBtn, {BackgroundColor3 = CARD_HOV}, 0.12) end)
resetBtn.MouseLeave:Connect(function() tween(resetBtn, {BackgroundColor3 = Color3.fromRGB(40, 36, 32)}, 0.12) end)
resetBtn.MouseButton1Click:Connect(function() if S.hum then S.hum.Health = 0 end end)

local rejoinBtn = Instance.new("TextButton")
rejoinBtn.Size = UDim2.new(1, 0, 0, 28)
rejoinBtn.Position = UDim2.new(0, 0, 0, 32)
rejoinBtn.BackgroundColor3 = Color3.fromRGB(40, 36, 32)
rejoinBtn.TextColor3 = TEXT
rejoinBtn.Font = FONT_MONO
rejoinBtn.TextSize = 11
rejoinBtn.Text = "REJOIN SERVER"
rejoinBtn.BorderSizePixel = 0
rejoinBtn.AutoButtonColor = false
rejoinBtn.Parent = actionRow
Instance.new("UICorner", rejoinBtn).CornerRadius = UDim.new(0, 2)
local rbs2 = Instance.new("UIStroke", rejoinBtn)
rbs2.Color = DIVIDER; rbs2.Thickness = 1
rejoinBtn.MouseEnter:Connect(function() tween(rejoinBtn, {BackgroundColor3 = CARD_HOV}, 0.12) end)
rejoinBtn.MouseLeave:Connect(function() tween(rejoinBtn, {BackgroundColor3 = Color3.fromRGB(40, 36, 32)}, 0.12) end)
rejoinBtn.MouseButton1Click:Connect(function()
    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, plr)
end)

local function makeHeader(parent, title, subtitle)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 60)
    container.BackgroundTransparency = 1
    container.Parent = parent
    local accent = Instance.new("Frame")
    accent.Size = UDim2.new(0, 3, 0, 32)
    accent.Position = UDim2.new(0, 0, 0, 4)
    accent.BackgroundColor3 = ACCENT
    accent.BorderSizePixel = 0
    accent.Parent = container
    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1, -20, 0, 26)
    t.Position = UDim2.new(0, 12, 0, 4)
    t.BackgroundTransparency = 1
    t.Text = title
    t.TextColor3 = TEXT
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Font = FONT_MONO
    t.TextSize = 22
    t.Parent = container
    local s = Instance.new("TextLabel")
    s.Size = UDim2.new(1, -20, 0, 16)
    s.Position = UDim2.new(0, 12, 0, 32)
    s.BackgroundTransparency = 1
    s.Text = subtitle or ""
    s.TextColor3 = TEXT_DIM
    s.TextXAlignment = Enum.TextXAlignment.Left
    s.Font = FONT_BODY
    s.TextSize = 10
    s.Parent = container
    return container
end

local function makeSection(parent, y, text)
    local s = Instance.new("TextLabel")
    s.Size = UDim2.new(1, 0, 0, 20)
    s.Position = UDim2.new(0, 0, 0, y)
    s.BackgroundTransparency = 1
    s.Text = text
    s.TextColor3 = TEXT_FAINT
    s.TextXAlignment = Enum.TextXAlignment.Left
    s.Font = FONT_MONO
    s.TextSize = 10
    s.Parent = parent
    return s
end

local function makeToggle(parent, y, label, initial, onChanged)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 32)
    row.Position = UDim2.new(0, 0, 0, y)
    row.BackgroundColor3 = CARD
    row.BorderSizePixel = 0
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 2)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -80, 1, 0)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = TEXT
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Font = FONT_BODY
    lbl.TextSize = 11
    lbl.Parent = row
    local state = initial
    local stateLbl = Instance.new("TextLabel")
    stateLbl.Size = UDim2.new(0, 50, 1, 0)
    stateLbl.Position = UDim2.new(1, -60, 0, 0)
    stateLbl.BackgroundTransparency = 1
    stateLbl.Text = state and "ON" or "OFF"
    stateLbl.TextColor3 = state and ACCENT or TEXT_DIM
    stateLbl.TextXAlignment = Enum.TextXAlignment.Right
    stateLbl.Font = FONT_MONO
    stateLbl.TextSize = 11
    stateLbl.Parent = row
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = row
    local function update(v)
        state = v
        stateLbl.Text = v and "ON" or "OFF"
        stateLbl.TextColor3 = v and ACCENT or TEXT_DIM
        onChanged(v)
    end
    btn.MouseButton1Click:Connect(function() state = not state; update(state) end)
    return row
end

local function makeSlider(parent, y, label, minV, maxV, initial, onChanged)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 44)
    row.Position = UDim2.new(0, 0, 0, y)
    row.BackgroundColor3 = CARD
    row.BorderSizePixel = 0
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 2)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -70, 0, 18)
    lbl.Position = UDim2.new(0, 12, 0, 6)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = TEXT
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Font = FONT_BODY
    lbl.TextSize = 11
    lbl.Parent = row
    local valLbl = Instance.new("TextLabel")
    valLbl.Size = UDim2.new(0, 60, 0, 18)
    valLbl.Position = UDim2.new(1, -72, 0, 6)
    valLbl.BackgroundTransparency = 1
    valLbl.Text = string.format("%.2f", initial)
    valLbl.TextColor3 = ACCENT
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.Font = FONT_MONO
    valLbl.TextSize = 11
    valLbl.Parent = row
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -24, 0, 2)
    bar.Position = UDim2.new(0, 12, 0, 32)
    bar.BackgroundColor3 = OFF_TRK
    bar.BorderSizePixel = 0
    bar.Parent = row
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((initial - minV) / (maxV - minV), 0, 1, 0)
    fill.BackgroundColor3 = ACCENT
    fill.BorderSizePixel = 0
    fill.Parent = bar
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 8, 0, 8)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new((initial - minV) / (maxV - minV), 0, 0.5, 0)
    knob.BackgroundColor3 = ACCENT
    knob.BorderSizePixel = 0
    knob.Parent = bar
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
    local dragging = false
    local function updateFromX(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local value = minV + rel * (maxV - minV)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, 0, 0.5, 0)
        valLbl.Text = string.format("%.2f", value)
        onChanged(value)
    end
    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; updateFromX(input.Position.X) end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then updateFromX(input.Position.X) end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
end

-- MAIN
local mainTab = tabContents["MAIN"]
makeHeader(mainTab, "MAIN", "system menu")
local welcomeCard = Instance.new("Frame")
welcomeCard.Size = UDim2.new(1, 0, 0, 120)
welcomeCard.Position = UDim2.new(0, 0, 0, 80)
welcomeCard.BackgroundColor3 = CARD
welcomeCard.BorderSizePixel = 0
welcomeCard.Parent = mainTab
Instance.new("UICorner", welcomeCard).CornerRadius = UDim.new(0, 3)
local welcomeLbl = Instance.new("TextLabel")
welcomeLbl.Size = UDim2.new(1, -24, 0, 30)
welcomeLbl.Position = UDim2.new(0, 12, 0, 16)
welcomeLbl.BackgroundTransparency = 1
welcomeLbl.Text = "Welcome to xelhub"
welcomeLbl.TextColor3 = TEXT
welcomeLbl.TextXAlignment = Enum.TextXAlignment.Left
welcomeLbl.Font = FONT_MONO
welcomeLbl.TextSize = 18
welcomeLbl.Parent = welcomeCard
local subLbl = Instance.new("TextLabel")
subLbl.Size = UDim2.new(1, -24, 0, 20)
subLbl.Position = UDim2.new(0, 12, 0, 50)
subLbl.BackgroundTransparency = 1
subLbl.Text = "signed in as @" .. plr.Name .. " | game: " .. CURRENT_GAME
subLbl.TextColor3 = TEXT_DIM
subLbl.TextXAlignment = Enum.TextXAlignment.Left
subLbl.Font = FONT_BODY
subLbl.TextSize = 11
subLbl.Parent = welcomeCard
local hintLbl = Instance.new("TextLabel")
hintLbl.Size = UDim2.new(1, -24, 0, 40)
hintLbl.Position = UDim2.new(0, 12, 0, 72)
hintLbl.BackgroundTransparency = 1
hintLbl.Text = "right control hides this menu\npress 7 / 9 in TSB for combat toggles"
hintLbl.TextColor3 = TEXT_FAINT
hintLbl.TextXAlignment = Enum.TextXAlignment.Left
hintLbl.TextYAlignment = Enum.TextYAlignment.Top
hintLbl.Font = FONT_MONO
hintLbl.TextSize = 10
hintLbl.Parent = welcomeCard
local gameLbl = Instance.new("TextLabel")
gameLbl.Size = UDim2.new(1, 0, 0, 18)
gameLbl.Position = UDim2.new(0, 0, 1, -22)
gameLbl.BackgroundTransparency = 1
gameLbl.Text = "game: " .. CURRENT_GAME
gameLbl.TextColor3 = TEXT_FAINT
gameLbl.TextXAlignment = Enum.TextXAlignment.Left
gameLbl.Font = FONT_MONO
gameLbl.TextSize = 10
gameLbl.Parent = mainTab

-- COMBAT (TSB)
if CURRENT_GAME == "TSB" then
    local combatTab = tabContents["COMBAT"]
    makeHeader(combatTab, "COMBAT", "attack automation")
    makeSection(combatTab, 80, "MODULES")
    makeToggle(combatTab, 100, "Auto Fight",   S.autoFight,   function(v) S.autoFight = v end)
    makeToggle(combatTab, 136, "Auto Serious", S.autoSerious, function(v) S.autoSerious = v end)
    makeSection(combatTab, 180, "TUNING")
    makeSlider(combatTab, 200, "M1 Delay",     0.05, 0.30, HUNT.M1Delay,      function(v) HUNT.M1Delay = v end)
    makeSlider(combatTab, 248, "Skill Delay",  0.05, 0.40, HUNT.SkillDelay,   function(v) HUNT.SkillDelay = v end)
    makeSlider(combatTab, 296, "Dash Cooldown",0.15, 2.0,  HUNT.DashCooldown, function(v) HUNT.DashCooldown = v end)
    makeSlider(combatTab, 344, "Strike Range", 3,    15,   HUNT.StrikeRange,  function(v) HUNT.StrikeRange = v end)
end

-- AIMBOT (MM2)
if CURRENT_GAME == "MM2" then
    local aimTab = tabContents["AIMBOT"]
    makeHeader(aimTab, "AIMBOT", "silent aim + role detection")
    makeSection(aimTab, 80, "MODULES")
    makeToggle(aimTab, 100, "Silent Aim",           S.silentAim,      function(v) S.silentAim = v end)
    makeToggle(aimTab, 136, "Aimbot",               S.aimbot,         function(v) S.aimbot = v end)
    makeToggle(aimTab, 172, "Aimbot Murderer Only", S.aimbotMurderer, function(v) S.aimbotMurderer = v end)
    makeSection(aimTab, 216, "TUNING")
    makeSlider(aimTab, 236, "FOV Radius", 30, 400, S.aimFOV,     function(v) S.aimFOV = v; if FOVCircle then FOVCircle.Radius = v end end)
    makeSlider(aimTab, 284, "Aim Smooth", 1,  20,  S.aimSmooth,  function(v) S.aimSmooth = v end)
end

-- PLAYER (ESP)
local playerTab = tabContents["PLAYER"]
makeHeader(playerTab, "PLAYER", "visual overlay")
makeSection(playerTab, 80, "ESP MODULES")
makeToggle(playerTab, 100, "ESP Enabled", S.espEnabled, function(v) S.espEnabled = v; refreshESP() end)

if CURRENT_GAME == "MM2" then
    makeToggle(playerTab, 136, "Murderer ESP (red)",    S.espMurderer, function(v) S.espMurderer = v; refreshESP() end)
    makeToggle(playerTab, 172, "Sheriff ESP (blue)",    S.espSheriff,  function(v) S.espSheriff = v; refreshESP() end)
    makeToggle(playerTab, 208, "Gun ESP (yellow)",      S.espGun,      function(v) S.espGun = v; refreshESP() end)
    makeToggle(playerTab, 244, "Friend ESP (white)",    S.espFriend,   function(v) S.espFriend = v; refreshESP() end)
    makeToggle(playerTab, 280, "Show Names",            S.espNames,    function(v) S.espNames = v; refreshESP() end)
    makeToggle(playerTab, 316, "Show Health",           S.espHealth,   function(v) S.espHealth = v; refreshESP() end)
    makeToggle(playerTab, 352, "Show Outline",          S.espOutline,  function(v) S.espOutline = v; refreshESP() end)
else
    makeToggle(playerTab, 136, "Show Names",       S.espNames,     function(v) S.espNames = v; refreshESP() end)
    makeToggle(playerTab, 172, "Show Health",      S.espHealth,    function(v) S.espHealth = v; refreshESP() end)
    makeToggle(playerTab, 208, "Show Outline",     S.espOutline,   function(v) S.espOutline = v; refreshESP() end)
    makeToggle(playerTab, 244, "Include NPCs",     S.espNPCs,      function(v) S.espNPCs = v; refreshESP() end)
end

-- CONFIG
if tabContents["CONFIG"] then
    local configTab = tabContents["CONFIG"]
    makeHeader(configTab, "CONFIG", "advanced tuning")
    if CURRENT_GAME == "TSB" then
        makeSection(configTab, 80, "MOVEMENT")
        makeSlider(configTab, 100, "Lead Factor",    0,   0.5, HUNT.LeadFactor,   function(v) HUNT.LeadFactor = v end)
        makeSlider(configTab, 148, "Side Dash Odds", 0,   1.0, HUNT.SideStepOdds, function(v) HUNT.SideStepOdds = v end)
        makeSlider(configTab, 196, "Stuck Timeout",  0.5, 5.0, HUNT.StuckTime,    function(v) HUNT.StuckTime = v end)
        makeSlider(configTab, 244, "Hit Recovery",   0.05,1.0, HUNT.HitRecovery,  function(v) HUNT.HitRecovery = v end)
    else
        makeSection(configTab, 80, "AIM")
        makeSlider(configTab, 100, "FOV Radius", 30, 400, S.aimFOV,    function(v) S.aimFOV = v; if FOVCircle then FOVCircle.Radius = v end end)
        makeSlider(configTab, 148, "Aim Smooth", 1,  20,  S.aimSmooth, function(v) S.aimSmooth = v end)
    end
end

-- MORE
local moreTab = tabContents["MORE"]
makeHeader(moreTab, "MORE", "server + misc")
makeSection(moreTab, 80, "SERVER")
local rejoinTab = Instance.new("TextButton")
rejoinTab.Size = UDim2.new(1, 0, 0, 32)
rejoinTab.Position = UDim2.new(0, 0, 0, 100)
rejoinTab.BackgroundColor3 = CARD
rejoinTab.TextColor3 = TEXT
rejoinTab.Font = FONT_MONO
rejoinTab.TextSize = 11
rejoinTab.Text = "REJOIN SERVER"
rejoinTab.BorderSizePixel = 0
rejoinTab.AutoButtonColor = false
rejoinTab.Parent = moreTab
Instance.new("UICorner", rejoinTab).CornerRadius = UDim.new(0, 2)
rejoinTab.MouseEnter:Connect(function() tween(rejoinTab, {BackgroundColor3 = CARD_HOV}, 0.12) end)
rejoinTab.MouseLeave:Connect(function() tween(rejoinTab, {BackgroundColor3 = CARD}, 0.12) end)
rejoinTab.MouseButton1Click:Connect(function()
    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, plr)
end)

local resetTab = Instance.new("TextButton")
resetTab.Size = UDim2.new(1, 0, 0, 32)
resetTab.Position = UDim2.new(0, 0, 0, 140)
resetTab.BackgroundColor3 = CARD
resetTab.TextColor3 = TEXT
resetTab.Font = FONT_MONO
resetTab.TextSize = 11
resetTab.Text = "RESET CHARACTER"
resetTab.BorderSizePixel = 0
resetTab.AutoButtonColor = false
resetTab.Parent = moreTab
Instance.new("UICorner", resetTab).CornerRadius = UDim.new(0, 2)
resetTab.MouseEnter:Connect(function() tween(resetTab, {BackgroundColor3 = CARD_HOV}, 0.12) end)
resetTab.MouseLeave:Connect(function() tween(resetTab, {BackgroundColor3 = CARD}, 0.12) end)
resetTab.MouseButton1Click:Connect(function() if S.hum then S.hum.Health = 0 end end)

-- SUPPORT
if tabContents["SUPPORT"] then
    local supportTab = tabContents["SUPPORT"]
    makeHeader(supportTab, "SUPPORT", "help + game requests")
    makeSection(supportTab, 80, "CONTACT")

    local descLbl = Instance.new("TextLabel")
    descLbl.Size = UDim2.new(1, 0, 0, 50)
    descLbl.Position = UDim2.new(0, 0, 0, 100)
    descLbl.BackgroundTransparency = 1
    descLbl.Text = "support or game reco,\nclick button below and paste it\nto add friends box in discord"
    descLbl.TextColor3 = TEXT_DIM
    descLbl.TextXAlignment = Enum.TextXAlignment.Left
    descLbl.TextYAlignment = Enum.TextYAlignment.Top
    descLbl.Font = FONT_BODY
    descLbl.TextSize = 11
    descLbl.Parent = supportTab

    local copyBtn = Instance.new("TextButton")
    copyBtn.Size = UDim2.new(0, 180, 0, 36)
    copyBtn.Position = UDim2.new(0, 0, 0, 168)
    copyBtn.BackgroundColor3 = Color3.fromRGB(88, 101, 242)
    copyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    copyBtn.Font = FONT_MONO
    copyBtn.TextSize = 12
    copyBtn.Text = "COPY USERNAME"
    copyBtn.BorderSizePixel = 0
    copyBtn.AutoButtonColor = false
    copyBtn.Parent = supportTab
    Instance.new("UICorner", copyBtn).CornerRadius = UDim.new(0, 4)

    copyBtn.MouseEnter:Connect(function()
        tween(copyBtn, {BackgroundColor3 = Color3.fromRGB(110, 122, 255)}, 0.12)
    end)
    copyBtn.MouseLeave:Connect(function()
        tween(copyBtn, {BackgroundColor3 = Color3.fromRGB(88, 101, 242)}, 0.12)
    end)

    local copied = false
    copyBtn.MouseButton1Click:Connect(function()
        pcall(function() setclipboard("a7ql") end)
        if not copied then
            copied = true
            local orig = copyBtn.Text
            copyBtn.Text = "COPIED!"
            task.delay(1.5, function()
                copyBtn.Text = orig
                copied = false
            end)
        end
    end)
end

local function switchTab(name)
    _G.xel_TAB = name
    for tname, frame in pairs(tabContents) do
        frame.Visible = (tname == name)
    end
    for tname, btn in pairs(tabButtons) do
        if tname == name then
            tween(btn, {BackgroundColor3 = TAB_ACTIVE, TextColor3 = ACCENT}, 0.12)
        else
            tween(btn, {BackgroundColor3 = Color3.fromRGB(34, 31, 28), TextColor3 = TEXT_DIM}, 0.12)
        end
    end
end
_G.xel_SWITCH_TAB = switchTab
switchTab("MAIN")

-- SPLASH
local splash = Instance.new("Frame")
splash.Size = UDim2.new(0, 320, 0, 180)
splash.Position = UDim2.new(0.5, -160, 0.5, -90)
splash.BackgroundColor3 = BG
splash.BorderSizePixel = 0
splash.Parent = screen
Instance.new("UICorner", splash).CornerRadius = UDim.new(0, 4)
local splashStroke = Instance.new("UIStroke", splash)
splashStroke.Color = ACCENT_DIM
splashStroke.Thickness = 1
local splashTitle = Instance.new("TextLabel")
splashTitle.Size = UDim2.new(1, 0, 0, 50)
splashTitle.Position = UDim2.new(0, 0, 0, 30)
splashTitle.BackgroundTransparency = 1
splashTitle.Text = "xelhub"
splashTitle.TextColor3 = TEXT
splashTitle.Font = FONT_MONO
splashTitle.TextSize = 28
splashTitle.Parent = splash
local splashDiv = Instance.new("Frame")
splashDiv.Size = UDim2.new(0, 80, 0, 1)
splashDiv.Position = UDim2.new(0.5, -40, 0, 84)
splashDiv.BackgroundColor3 = ACCENT
splashDiv.BorderSizePixel = 0
splashDiv.Parent = splash
local splashSub = Instance.new("TextLabel")
splashSub.Size = UDim2.new(1, 0, 0, 16)
splashSub.Position = UDim2.new(0, 0, 0, 94)
splashSub.BackgroundTransparency = 1
splashSub.Text = CURRENT_GAME .. " • SYSTEM MENU"
splashSub.TextColor3 = TEXT_DIM
splashSub.Font = FONT_MONO
splashSub.TextSize = 10
splashSub.Parent = splash
local startBtn = Instance.new("TextButton")
startBtn.Size = UDim2.new(0, 180, 0, 34)
startBtn.Position = UDim2.new(0.5, -90, 0, 126)
startBtn.BackgroundColor3 = ACCENT
startBtn.TextColor3 = Color3.fromRGB(20, 18, 16)
startBtn.Font = FONT_MONO
startBtn.TextSize = 13
startBtn.Text = "START"
startBtn.BorderSizePixel = 0
startBtn.AutoButtonColor = false
startBtn.Parent = splash
Instance.new("UICorner", startBtn).CornerRadius = UDim.new(0, 2)
startBtn.MouseEnter:Connect(function() tween(startBtn, {BackgroundColor3 = Color3.fromRGB(240, 195, 120)}, 0.15) end)
startBtn.MouseLeave:Connect(function() tween(startBtn, {BackgroundColor3 = ACCENT}, 0.15) end)
startBtn.MouseButton1Click:Connect(function()
    tween(splash, {BackgroundTransparency = 1}, 0.25)
    tween(splashStroke, {Transparency = 1}, 0.25)
    tween(splashTitle, {TextTransparency = 1}, 0.25)
    tween(splashSub, {TextTransparency = 1}, 0.25)
    tween(splashDiv, {BackgroundTransparency = 1}, 0.25)
    tween(startBtn, {BackgroundTransparency = 1, TextTransparency = 1}, 0.25)
    task.wait(0.25)
    splash.Visible = false
    root.Visible = true
    root.BackgroundTransparency = 1
    tween(root, {BackgroundTransparency = 0}, 0.3)
end)

-- STATUS
task.spawn(function()
    while true do
        if _G.xel_STATUS then
            local tName = S.target and S.target.Parent and S.target.Parent.Name or "none"
            local statusText = "game > " .. CURRENT_GAME .. "\n\n"
            if CURRENT_GAME == "TSB" then
                statusText = statusText .. string.format(
                    "target > %s\n\nauto fight > %s\nauto serious > %s\nesp > %s\n\nplayers > %d",
                    tName, S.autoFight and "on" or "off", S.autoSerious and "on" or "off",
                    S.espEnabled and "on" or "off", #Players:GetPlayers())
            else
                statusText = statusText .. string.format(
                    "silent aim > %s\nmurderer aimbot > %s\nesp > %s\n\nplayers > %d",
                    S.silentAim and "on" or "off", S.aimbotMurderer and "on" or "off",
                    S.espEnabled and "on" or "off", #Players:GetPlayers())
            end
            _G.xel_STATUS.Text = statusText
        end
        task.wait(0.3)
    end
end)

-- drag
do
    local dragging, dragStart, startPos
    topBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = root.Position
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if CURRENT_GAME == "TSB" then
        if input.KeyCode == Enum.KeyCode.Seven then S.autoFight = not S.autoFight
        elseif input.KeyCode == Enum.KeyCode.Nine then S.autoSerious = not S.autoSerious end
    end
    if input.KeyCode == Enum.KeyCode.RightControl then
        S.guiVisible = not S.guiVisible
        screen.Enabled = S.guiVisible
    end
end)

print("[xelhub] Loaded — " .. CURRENT_GAME)
