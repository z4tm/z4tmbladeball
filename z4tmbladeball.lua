--[[
    Zatm Software - ULTIMATE FIX
    
    TRUE SINGLE CLICK (no double!)
    PER-BALL DECISION LOCK
    STRICT TARGET VALIDATION
    FIXED TTI (horizontal only)
    1v1-SAFE BALL SELECTION
    AUTO ABILITY (emergency save)
]]

-- UI Library
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("BLADE BALL PRO V2", "DarkTheme")

-- Services
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer

-- Settings
local Settings = {
    AutoParry = false,
    Mode = "MACHINE",
    
    Configs = {
        LEGIT = {
            TTIWindow = 0.20,
            MinTTI = 0.05,
            BaseAngle = 0.75,
            BaseCooldown = 0.18,
            HumanDelay = true,
            MissChance = 40,
            PingCompensation = true
        },
        MACHINE = {
            -- TTI BASED
            TTIWindow = 0.18,
            MinTTI = 0.04,
            
            -- ANGLE (strict!)
            BaseAngle = 0.80,           -- Stricter for safety
            CloseRangeAngle = 0.90,     -- Very strict when close
            
            -- COOLDOWN
            BaseCooldown = 0.15,
            PerBallCooldown = 0.40,     -- Decision lock per ball
            
            -- SMART FEATURES
            FakeDetection = true,
            StrictTargeting = true,     -- Only trust attribute at distance
            PingCompensation = true,
            
            -- DISTANCE
            MaxDistance = 50,
            AttributeOnlyDistance = 15,  -- Beyond this, ONLY attribute
            CloseRange = 8               -- Very strict angle here
        }
    },
    
    -- AUTO ABILITY (NEW!)
    AutoAbility = false,
    AbilityKeys = {
        Enum.KeyCode.E,  -- Primary
        Enum.KeyCode.R,  -- Secondary
        Enum.KeyCode.F   -- Tertiary
    },
    EmergencyTTI = 0.12,         -- Activate if ball THIS close
    AbilityCooldown = 4,         -- Min seconds between uses
    PanicMode = true,            -- Use ability even if not targeting (close ball)
    
    -- Movement
    Speed = false,
    SpeedValue = 50,
    Fly = false,
    FlySpeed = 50,
    Noclip = false,
    InfJump = false,
    
    -- Auto
    AutoDash = false,
    AutoSpam = false,
    SpamDistance = 10,
    SpamSpeed = 0.05,
    SpamToggleKey = Enum.KeyCode.X,
    AntiRagdoll = true,
    
    -- ESP
    BallESP = false,
    
    -- Other
    MenuToggleKey = Enum.KeyCode.Delete,
    DebugMode = false
}

local menuVisible = true
local lastParry = 0
local parryAttempts = 0
local successfulParries = 0

-- PER-BALL DECISION LOCK (CRITICAL!)
local ballDecisions = {}

-- AUTO ABILITY STATE
local lastAbilityUse = 0
local abilityUsed = 0

-- PING
local currentPing = 0
task.spawn(function()
    while true do
        task.wait(1)
        pcall(function()
            currentPing = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
        end)
    end
end)

-- VELOCITY TRACKING (fake detection)
local velocityTracking = {}

-- CLEANUP OLD DECISIONS
task.spawn(function()
    while true do
        task.wait(2)
        local now = tick()
        for ballId, decision in pairs(ballDecisions) do
            if now - decision.time > 1 then
                ballDecisions[ballId] = nil
            end
        end
        for ballId, tracker in pairs(velocityTracking) do
            if now - tracker.lastUpdate > 2 then
                velocityTracking[ballId] = nil
            end
        end
    end
end)

-- SMART BALL SELECTION (1v1-safe!)
local function GetBall()
    local balls = Workspace:FindFirstChild("Balls")
    if not balls then return nil end
    
    local myBall = nil
    local highestPriority = -999
    local config = Settings.Configs[Settings.Mode]
    
    for _, ball in pairs(balls:GetChildren()) do
        if not (ball and ball:IsA("Part")) then continue end
        
        local vel = ball.AssemblyLinearVelocity.Magnitude
        if vel < 5 then continue end
        
        -- Priority #1: ATTRIBUTE
        local target = ball:GetAttribute("target")
        if target == LocalPlayer.Name then
            return ball  -- INSTANT return!
        end
        
        -- For non-attributed balls: VERY CAREFUL
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local dist = (ball.Position - char.HumanoidRootPart.Position).Magnitude
            
            -- Only consider if VERY close
            if dist < (config.CloseRange or 8) then
                local priority = vel / dist
                if priority > highestPriority then
                    highestPriority = priority
                    myBall = ball
                end
            end
        end
    end
    
    return myBall
end

-- FAKE DETECTION
local function IsFakeBall(ball)
    local config = Settings.Configs[Settings.Mode]
    if not config.FakeDetection then return false end
    
    local ballId = tostring(ball)
    local currentVel = ball.AssemblyLinearVelocity.Magnitude
    
    if not velocityTracking[ballId] then
        velocityTracking[ballId] = {
            lastVelocity = currentVel,
            lastUpdate = tick()
        }
        return false
    end
    
    local tracker = velocityTracking[ballId]
    local velChange = math.abs(currentVel - tracker.lastVelocity)
    local timeDiff = tick() - tracker.lastUpdate
    
    tracker.lastVelocity = currentVel
    tracker.lastUpdate = tick()
    
    if timeDiff < 0.1 and velChange > 120 then
        if Settings.DebugMode then
            print(string.format("[FAKE?] Δvel: %.0f in %.3fs", velChange, timeDiff))
        end
        return true
    end
    
    return false
end

-- FIXED TTI (HORIZONTAL ONLY!)
local function CalculateTTI(ball)
    local char = LocalPlayer.Character
    if not (char and char:FindFirstChild("HumanoidRootPart")) then return 999 end
    
    local hrp = char.HumanoidRootPart
    local ballPos = ball.Position
    local ballVel = ball.AssemblyLinearVelocity
    
    -- HORIZONTAL DISTANCE (ignore Y!)
    local horizontalDist = Vector3.new(
        ballPos.X - hrp.Position.X,
        0,
        ballPos.Z - hrp.Position.Z
    ).Magnitude
    
    -- HORIZONTAL VELOCITY (ignore Y!)
    local horizontalBallVel = Vector3.new(ballVel.X, 0, ballVel.Z)
    local horizontalPlayerVel = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z)
    
    local relativeVel = horizontalBallVel - horizontalPlayerVel
    local toBall = Vector3.new(ballPos.X - hrp.Position.X, 0, ballPos.Z - hrp.Position.Z).Unit
    local closingSpeed = -relativeVel:Dot(toBall)
    
    if closingSpeed <= 0 then
        closingSpeed = horizontalBallVel.Magnitude
    end
    
    if closingSpeed <= 0 then return 999 end
    
    local tti = horizontalDist / closingSpeed
    
    -- Ping compensation
    local config = Settings.Configs[Settings.Mode]
    if config.PingCompensation then
        tti = tti - currentPing - 0.015
    end
    
    if Settings.DebugMode then
        print(string.format("[TTI] HDist: %.1f | HClose: %.0f | TTI: %.3fs", 
            horizontalDist, closingSpeed, tti))
    end
    
    return math.max(tti, 0)
end

-- STRICT ANGLE CHECK
local function IsComingToMe(ball, distance)
    local char = LocalPlayer.Character
    if not (char and char:FindFirstChild("HumanoidRootPart")) then return false end
    
    local hrp = char.HumanoidRootPart
    local ballVel = ball.AssemblyLinearVelocity
    
    if ballVel.Magnitude < 20 then return false end
    
    local ballToMe = (hrp.Position - ball.Position).Unit
    local velDir = ballVel.Unit
    local dot = velDir:Dot(ballToMe)
    
    local config = Settings.Configs[Settings.Mode]
    local threshold = config.BaseAngle or 0.80
    
    -- STRICTER when close!
    if distance and distance < (config.CloseRange or 8) then
        threshold = config.CloseRangeAngle or 0.90
    end
    
    return dot > threshold
end

-- STRICT TARGET VALIDATION
local function IsTargetingMe(ball)
    if not ball then return false end
    
    local char = LocalPlayer.Character
    if not (char and char:FindFirstChild("HumanoidRootPart")) then return false end
    
    local config = Settings.Configs[Settings.Mode]
    local distance = (ball.Position - char.HumanoidRootPart.Position).Magnitude
    
    -- Method 1: ATTRIBUTE (most reliable)
    local target = ball:GetAttribute("target")
    if target then
        return target == LocalPlayer.Name
    end
    
    -- Method 2: STRICT validation
    if config.StrictTargeting then
        -- Beyond safe distance? NO parry without attribute
        if distance > (config.AttributeOnlyDistance or 15) then
            return false
        end
    end
    
    -- Method 3: Angle (only if close)
    return IsComingToMe(ball, distance)
end

-- AUTO ABILITY (EMERGENCY!)
local function TryAutoAbility(ball, tti)
    if not Settings.AutoAbility then return false end
    
    local now = tick()
    local cooldown = Settings.AbilityCooldown or 4
    
    -- Cooldown check
    if now - lastAbilityUse < cooldown then
        return false
    end
    
    local char = LocalPlayer.Character
    if not (char and char:FindFirstChild("HumanoidRootPart")) then return false end
    
    local distance = (ball.Position - char.HumanoidRootPart.Position).Magnitude
    
    -- Emergency condition
    local isEmergency = false
    
    -- Condition 1: TTI critical
    if tti <= (Settings.EmergencyTTI or 0.12) then
        isEmergency = true
    end
    
    -- Condition 2: Panic mode (very close ball)
    if Settings.PanicMode and distance < 6 then
        isEmergency = true
    end
    
    if not isEmergency then return false end
    
    -- TRY ABILITIES (in order)
    for _, key in ipairs(Settings.AbilityKeys) do
        VirtualInputManager:SendKeyEvent(true, key, false, game)
        task.wait(0.02)
        VirtualInputManager:SendKeyEvent(false, key, false, game)
        task.wait(0.01)
    end
    
    lastAbilityUse = now
    abilityUsed = abilityUsed + 1
    
    if Settings.DebugMode then
        print(string.format("ABILITY! TTI: %.3fs | Dist: %.1f", tti, distance))
    end
    
    return true
end

-- LEGIT helpers
local function GetHumanDelay()
    if Settings.Mode ~= "LEGIT" then return 0 end
    return math.random(100, 250) / 1000
end

local function ShouldMiss()
    if Settings.Mode ~= "LEGIT" then return false end
    return math.random(1, 100) <= Settings.Configs.LEGIT.MissChance
end

-- EXECUTE PARRY (TRUE SINGLE CLICK!)
local function ExecuteParry(ball)
    local ballId = tostring(ball)
    local now = tick()
    local config = Settings.Configs[Settings.Mode]
    
    -- PER-BALL DECISION LOCK (CRITICAL!)
    if ballDecisions[ballId] then
        local decision = ballDecisions[ballId]
        if now - decision.time < (config.PerBallCooldown or 0.40) then
            if Settings.DebugMode then
                print(string.format("[LOCKED] Ball locked for %.2fs", 
                    (config.PerBallCooldown or 0.40) - (now - decision.time)))
            end
            return false
        end
    end
    
    -- Global cooldown
    if now - lastParry < (config.BaseCooldown or 0.15) then
        return false
    end
    
    -- LOCK DECISION FIRST!
    ballDecisions[ballId] = {
        time = now,
        executed = false
    }
    
    -- LEGIT: Miss chance
    if ShouldMiss() then
        parryAttempts = parryAttempts + 1
        lastParry = now
        
        -- TRY AUTO ABILITY (missed parry!)
        local tti = CalculateTTI(ball)
        TryAutoAbility(ball, tti)
        
        return false
    end
    
    -- Human delay
    local delay = GetHumanDelay()
    if delay > 0 then
        task.wait(delay)
    end
    
    lastParry = now
    parryAttempts = parryAttempts + 1
    
    -- ✅ TRUE SINGLE CLICK (NO DOUBLE!)
    mouse1click()
    
    ballDecisions[ballId].executed = true
    successfulParries = successfulParries + 1
    
    if Settings.DebugMode then
        local tti = CalculateTTI(ball)
        local acc = math.floor((successfulParries / parryAttempts) * 100)
        print(string.format("PARRY! TTI: %.3fs | Acc: %d%%", tti, acc))
    end
    
    return true
end

-- MAIN LOOP (RENDERSTEP!)
local parryConnection
local function StartAutoParry()
    if parryConnection then 
        parryConnection:Disconnect()
    end
    
    parryConnection = RunService.RenderStepped:Connect(function()
        if not Settings.AutoParry then return end
        
        local char = LocalPlayer.Character
        if not (char and char:FindFirstChild("HumanoidRootPart")) then return end
        
        -- Get ball (1v1-safe)
        local ball = GetBall()
        if not ball then return end
        
        -- Update velocity tracking
        local ballId = tostring(ball)
        local currentVel = ball.AssemblyLinearVelocity.Magnitude
        if not velocityTracking[ballId] then
            velocityTracking[ballId] = {
                lastVelocity = currentVel,
                lastUpdate = tick()
            }
        end
        
        -- Fake check
        if IsFakeBall(ball) then
            if Settings.DebugMode then
                print("[FAKE] Skipped")
            end
            return
        end
        
        -- STRICT target validation
        if not IsTargetingMe(ball) then return end
        
        -- TTI calculation (fixed!)
        local tti = CalculateTTI(ball)
        
        local config = Settings.Configs[Settings.Mode]
        local window = config.TTIWindow or 0.18
        local minTTI = config.MinTTI or 0.04
        
        -- AUTO ABILITY (if enabled and emergency)
        if Settings.AutoAbility and tti < (Settings.EmergencyTTI or 0.12) then
            TryAutoAbility(ball, tti)
        end
        
        -- Parry window
        if tti >= minTTI and tti <= window then
            local success = ExecuteParry(ball)
            
            -- If parry failed and ball is close, try ability
            if not success and Settings.AutoAbility then
                TryAutoAbility(ball, tti)
            end
        end
    end)
end

-- Speed
local speedConnection
local function ApplySpeed()
    if speedConnection then speedConnection:Disconnect() end
    speedConnection = RunService.Heartbeat:Connect(function()
        if not Settings.Speed then return end
        local char = LocalPlayer.Character
        if not char then return end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid.WalkSpeed = Settings.SpeedValue end
    end)
end

-- Fly
local flyConnection
local flying = false
local function ToggleFly()
    if flyConnection then flyConnection:Disconnect(); flyConnection = nil end
    if not Settings.Fly then flying = false; return end
    flying = true
    local char = LocalPlayer.Character
    if not (char and char:FindFirstChild("HumanoidRootPart")) then return end
    local hrp = char.HumanoidRootPart
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 10000
    bg.Parent = hrp
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Velocity = Vector3.new(0, 0, 0)
    bv.Parent = hrp
    flyConnection = RunService.Heartbeat:Connect(function()
        if not (Settings.Fly and flying) then
            bg:Destroy(); bv:Destroy()
            if flyConnection then flyConnection:Disconnect() end
            return
        end
        local cam = Workspace.CurrentCamera
        bg.CFrame = cam.CFrame
        local velocity = Vector3.new(0, 0, 0)
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then velocity = velocity + (cam.CFrame.LookVector * Settings.FlySpeed) end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then velocity = velocity - (cam.CFrame.LookVector * Settings.FlySpeed) end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then velocity = velocity - (cam.CFrame.RightVector * Settings.FlySpeed) end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then velocity = velocity + (cam.CFrame.RightVector * Settings.FlySpeed) end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then velocity = velocity + Vector3.new(0, Settings.FlySpeed, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then velocity = velocity - Vector3.new(0, Settings.FlySpeed, 0) end
        bv.Velocity = velocity
    end)
end

-- Noclip
local noclipConnection
local function ToggleNoclip()
    if noclipConnection then noclipConnection:Disconnect() end
    if not Settings.Noclip then return end
    noclipConnection = RunService.Stepped:Connect(function()
        if not Settings.Noclip then noclipConnection:Disconnect(); return end
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end)
end

-- Inf Jump
UserInputService.JumpRequest:Connect(function()
    if not Settings.InfJump then return end
    local char = LocalPlayer.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

-- Anti Ragdoll
local antiRagdollConnection
local function ApplyAntiRagdoll()
    if antiRagdollConnection then antiRagdollConnection:Disconnect() end
    antiRagdollConnection = RunService.Heartbeat:Connect(function()
        if not Settings.AntiRagdoll then return end
        local char = LocalPlayer.Character
        if not char then return end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid:GetState() == Enum.HumanoidStateType.Ragdoll then
            humanoid:ChangeState(Enum.HumanoidStateType.Running)
        end
    end)
end

-- Auto Dash
local autoDashConnection
local function ApplyAutoDash()
    if autoDashConnection then autoDashConnection:Disconnect() end
    autoDashConnection = RunService.Heartbeat:Connect(function()
        if not Settings.AutoDash then return end
        local char = LocalPlayer.Character
        if not (char and char:FindFirstChild("HumanoidRootPart")) then return end
        local ball = GetBall()
        if not (ball and IsTargetingMe(ball)) then return end
        local dist = (ball.Position - char.HumanoidRootPart.Position).Magnitude
        if dist <= 12 then
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
            task.wait(2)
        end
    end)
end

-- Auto Spam
local autoSpamConnection
local spamming = false
local function ApplyAutoSpam()
    if autoSpamConnection then autoSpamConnection:Disconnect() end
    autoSpamConnection = RunService.Heartbeat:Connect(function()
        if not Settings.AutoSpam then spamming = false; return end
        local char = LocalPlayer.Character
        if not (char and char:FindFirstChild("HumanoidRootPart")) then spamming = false; return end
        local ball = GetBall()
        if not ball then spamming = false; return end
        local dist = (ball.Position - char.HumanoidRootPart.Position).Magnitude
        if dist <= Settings.SpamDistance then
            spamming = true
            mouse1click()
            task.wait(Settings.SpamSpeed)
        else
            spamming = false
        end
    end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Settings.SpamToggleKey then
        Settings.AutoSpam = not Settings.AutoSpam
        if Settings.AutoSpam then print("SPAM: ON"); ApplyAutoSpam()
        else print("SPAM: OFF"); if autoSpamConnection then autoSpamConnection:Disconnect() end; spamming = false end
    end
end)

-- Ball ESP
local ballESPConnection
local function UpdateBallESP()
    if ballESPConnection then ballESPConnection:Disconnect() end
    ballESPConnection = RunService.RenderStepped:Connect(function()
        if not Settings.BallESP then return end
        local ball = GetBall()
        if not ball then return end
        local esp = ball:FindFirstChild("ESP")
        if not esp then
            esp = Instance.new("BillboardGui")
            esp.Name = "ESP"
            esp.AlwaysOnTop = true
            esp.Size = UDim2.new(0, 100, 0, 50)
            esp.Parent = ball
            local text = Instance.new("TextLabel")
            text.Size = UDim2.new(1, 0, 1, 0)
            text.BackgroundTransparency = 1
            text.TextColor3 = Color3.fromRGB(255, 100, 100)
            text.TextSize = 14
            text.Font = Enum.Font.GothamBold
            text.TextStrokeTransparency = 0
            text.Parent = esp
        end
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local tti = CalculateTTI(ball)
            local isTarget = IsTargetingMe(ball)
            local vel = ball.AssemblyLinearVelocity.Magnitude
            esp.TextLabel.Text = string.format("TTI: %.3fs\n%.0f speed\n%s", tti, vel, isTarget and "YOU" or "Other")
            esp.TextLabel.TextColor3 = isTarget and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(100, 255, 100)
        end
    end)
end

-- GUI
local AutoParryTab = Window:NewTab("Auto Parry")
local ParrySection = AutoParryTab:NewSection("Auto Parry")

-- Make Window toggleable
local guiMain = game:GetService("CoreGui"):FindFirstChild("Zatm Software") or game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("Zatm Software")

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Settings.MenuToggleKey then
        menuVisible = not menuVisible
        if guiMain then
            guiMain.Enabled = menuVisible
        end
    end
end)

ParrySection:NewToggle("Enable Auto Parry", "Toggle", function(state)
    Settings.AutoParry = state
    if state then
        print("═══════════════════════════════════")
        print("Zatm Software - ULTIMATE")
        print("TRUE single click (no double!)")
        print("Per-ball decision lock")
        print("Fixed TTI (horizontal)")
        print("Strict targeting")
        print("1v1-safe selection")
        print("Auto ability emergency")
        print("═══════════════════════════════════")
        StartAutoParry()
    else
        print("OFF")
        if parryConnection then parryConnection:Disconnect() end
    end
end)

ParrySection:NewDropdown("Mode", "Choose", {"LEGIT", "MACHINE"}, function(value)
    Settings.Mode = value
    print("Mode:", value)
end)

ParrySection:NewToggle("Debug", "Logs", function(state)
    Settings.DebugMode = state
end)

ParrySection:NewButton("Reset Stats", "Reset", function()
    parryAttempts = 0
    successfulParries = 0
    abilityUsed = 0
    print("Reset!")
end)

-- AUTO ABILITY SECTION
local AbilitySection = AutoParryTab:NewSection("Auto Ability (Emergency)")

AbilitySection:NewToggle("Enable Auto Ability", "Emergency save", function(state)
    Settings.AutoAbility = state
    if state then
        print("AUTO ABILITY: ON")
        print("• Uses E/R/F when parry missed")
        print("• Emergency TTI: " .. Settings.EmergencyTTI .. "s")
    else
        print("AUTO ABILITY: OFF")
    end
end)

AbilitySection:NewSlider("Emergency TTI", "Activate when <", 30, 5, function(value)
    Settings.EmergencyTTI = value / 100
    print("Emergency TTI: " .. Settings.EmergencyTTI .. "s")
end)

AbilitySection:NewSlider("Ability Cooldown", "Min seconds", 10, 2, function(value)
    Settings.AbilityCooldown = value
    print("Ability CD: " .. value .. "s")
end)

AbilitySection:NewToggle("Panic Mode", "Use even if not targeting", function(state)
    Settings.PanicMode = state
end)

local InfoSection = AutoParryTab:NewSection("V2 Ultimate")
InfoSection:NewLabel("ULTIMATE FIXES:")
InfoSection:NewLabel("TRUE single click")
InfoSection:NewLabel("Per-ball lock (0.40s)")
InfoSection:NewLabel("Horizontal TTI only")
InfoSection:NewLabel("Strict targeting")
InfoSection:NewLabel("1v1-safe ball pick")
InfoSection:NewLabel("Auto ability emergency")
InfoSection:NewLabel("")
InfoSection:NewLabel("AUTO ABILITY:")
InfoSection:NewLabel("• E/R/F when parry missed")
InfoSection:NewLabel("• Emergency when TTI critical")
InfoSection:NewLabel("• Panic mode for close balls")

local MovementTab = Window:NewTab("Movement")
local MovementSection = MovementTab:NewSection("Movement")
MovementSection:NewToggle("Speed", "Enable", function(state) Settings.Speed = state; if state then ApplySpeed() else if speedConnection then speedConnection:Disconnect() end; local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid"); if h then h.WalkSpeed = 16 end end end)
MovementSection:NewSlider("Speed Value", "Speed", 200, 16, function(value) Settings.SpeedValue = value end)
MovementSection:NewToggle("Fly", "WASD", function(state) Settings.Fly = state; ToggleFly() end)
MovementSection:NewSlider("Fly Speed", "Speed", 100, 10, function(value) Settings.FlySpeed = value end)
MovementSection:NewToggle("Noclip", "Enable", function(state) Settings.Noclip = state; ToggleNoclip() end)
MovementSection:NewToggle("Inf Jump", "Enable", function(state) Settings.InfJump = state end)

local AutoTab = Window:NewTab("Auto")
local AutoSection = AutoTab:NewSection("Auto")
AutoSection:NewToggle("Auto Dash", "Enable", function(state) Settings.AutoDash = state; if state then ApplyAutoDash() else if autoDashConnection then autoDashConnection:Disconnect() end end end)
AutoSection:NewToggle("Auto Spam", "X", function(state) Settings.AutoSpam = state; if state then ApplyAutoSpam() else if autoSpamConnection then autoSpamConnection:Disconnect() end; spamming = false end end)
AutoSection:NewSlider("Spam Distance", "Distance", 20, 5, function(value) Settings.SpamDistance = value end)
AutoSection:NewSlider("Spam Speed", "Delay", 10, 1, function(value) Settings.SpamSpeed = value / 100 end)
AutoSection:NewToggle("Anti Ragdoll", "Enable", function(state) Settings.AntiRagdoll = state; if state then ApplyAntiRagdoll() else if antiRagdollConnection then antiRagdollConnection:Disconnect() end end end)

local VisualTab = Window:NewTab("ESP")
local ESPSection = VisualTab:NewSection("ESP")
ESPSection:NewToggle("Ball ESP", "Show", function(state) Settings.BallESP = state; if state then UpdateBallESP() else if ballESPConnection then ballESPConnection:Disconnect() end; local b = GetBall(); if b and b:FindFirstChild("ESP") then b.ESP:Destroy() end end end)

local InfoTab = Window:NewTab("Info")
local InfoSection2 = InfoTab:NewSection("About")
InfoSection2:NewLabel("Creator: z4tm & stellar scripts")
InfoSection2:NewLabel("")
InfoSection2:NewButton("Discord Server", "Click to copy link", function()
    setclipboard("https://discord.gg/ff7p6hGM")
    print("Discord link copied to clipboard!")
    print("https://discord.gg/ff7p6hGM")
end)

-- Status Display
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "StatusDisplay"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = LocalPlayer.PlayerGui

local StatusFrame = Instance.new("Frame")
StatusFrame.Size = UDim2.new(0, 320, 0, 165)
StatusFrame.Position = UDim2.new(1, -340, 0, 20)
StatusFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
StatusFrame.BackgroundTransparency = 0.2
StatusFrame.BorderSizePixel = 0
StatusFrame.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 15)
Corner.Parent = StatusFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -10, 0, 22)
Title.Position = UDim2.new(0, 5, 0, 5)
Title.BackgroundTransparency = 1
Title.Text = "Zatm Software"
Title.TextColor3 = Color3.fromRGB(100, 200, 255)
Title.TextSize = 14
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = StatusFrame

local S1 = Instance.new("TextLabel")
S1.Size = UDim2.new(1, -10, 0, 18)
S1.Position = UDim2.new(0, 5, 0, 28)
S1.BackgroundTransparency = 1
S1.Text = "Parry: OFF"
S1.TextColor3 = Color3.fromRGB(255, 100, 100)
S1.TextSize = 12
S1.Font = Enum.Font.Gotham
S1.TextXAlignment = Enum.TextXAlignment.Left
S1.Parent = StatusFrame

local S2 = Instance.new("TextLabel")
S2.Size = UDim2.new(1, -10, 0, 16)
S2.Position = UDim2.new(0, 5, 0, 48)
S2.BackgroundTransparency = 1
S2.Text = "Target: --"
S2.TextColor3 = Color3.fromRGB(150, 150, 150)
S2.TextSize = 11
S2.Font = Enum.Font.Gotham
S2.TextXAlignment = Enum.TextXAlignment.Left
S2.Parent = StatusFrame

local S3 = Instance.new("TextLabel")
S3.Size = UDim2.new(1, -10, 0, 16)
S3.Position = UDim2.new(0, 5, 0, 66)
S3.BackgroundTransparency = 1
S3.Text = "TTI: --"
S3.TextColor3 = Color3.fromRGB(180, 180, 180)
S3.TextSize = 10
S3.Font = Enum.Font.Gotham
S3.TextXAlignment = Enum.TextXAlignment.Left
S3.Parent = StatusFrame

local S4 = Instance.new("TextLabel")
S4.Size = UDim2.new(1, -10, 0, 16)
S4.Position = UDim2.new(0, 5, 0, 84)
S4.BackgroundTransparency = 1
S4.Text = "Ping: --ms"
S4.TextColor3 = Color3.fromRGB(180, 180, 180)
S4.TextSize = 10
S4.Font = Enum.Font.Gotham
S4.TextXAlignment = Enum.TextXAlignment.Left
S4.Parent = StatusFrame

local S5 = Instance.new("TextLabel")
S5.Size = UDim2.new(1, -10, 0, 16)
S5.Position = UDim2.new(0, 5, 0, 102)
S5.BackgroundTransparency = 1
S5.Text = "Accuracy: --"
S5.TextColor3 = Color3.fromRGB(200, 200, 200)
S5.TextSize = 10
S5.Font = Enum.Font.Gotham
S5.TextXAlignment = Enum.TextXAlignment.Left
S5.Parent = StatusFrame

local S6 = Instance.new("TextLabel")
S6.Size = UDim2.new(1, -10, 0, 16)
S6.Position = UDim2.new(0, 5, 0, 120)
S6.BackgroundTransparency = 1
S6.Text = "Ability: --"
S6.TextColor3 = Color3.fromRGB(255, 200, 100)
S6.TextSize = 10
S6.Font = Enum.Font.Gotham
S6.TextXAlignment = Enum.TextXAlignment.Left
S6.Parent = StatusFrame

local Hint = Instance.new("TextLabel")
Hint.Size = UDim2.new(1, 0, 0, 14)
Hint.Position = UDim2.new(0, 0, 0, 145)
Hint.BackgroundTransparency = 1
Hint.Text = "DELETE = Menu | X = Spam"
Hint.TextColor3 = Color3.fromRGB(100, 100, 100)
Hint.TextSize = 9
Hint.Font = Enum.Font.Gotham
Hint.TextXAlignment = Enum.TextXAlignment.Center
Hint.Parent = StatusFrame

-- Update Display
RunService.RenderStepped:Connect(function()
    if Settings.AutoParry then
        S1.Text = "Parry: ON [" .. Settings.Mode .. "]"
        S1.TextColor3 = Color3.fromRGB(100, 255, 100)
        Title.TextColor3 = Color3.fromRGB(100, 255, 100)
        
        local ball = GetBall()
        if ball then
            local isTarget = IsTargetingMe(ball)
            if isTarget then
                local tti = CalculateTTI(ball)
                local vel = ball.AssemblyLinearVelocity.Magnitude
                
                S2.Text = "Target: YOU"
                S2.TextColor3 = Color3.fromRGB(255, 100, 100)
                
                S3.Text = string.format("TTI: %.3fs | Vel: %.0f", tti, vel)
                S3.TextColor3 = tti <= 0.18 and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(100, 255, 100)
            else
                S2.Text = "Target: Other"
                S2.TextColor3 = Color3.fromRGB(100, 255, 100)
                S3.Text = "TTI: --"
                S3.TextColor3 = Color3.fromRGB(180, 180, 180)
            end
        else
            S2.Text = "Target: --"
            S2.TextColor3 = Color3.fromRGB(150, 150, 150)
            S3.Text = "TTI: --"
            S3.TextColor3 = Color3.fromRGB(180, 180, 180)
        end
        
        S4.Text = string.format("Ping: %.0fms", currentPing * 1000)
        
        if parryAttempts > 0 then
            local acc = math.floor((successfulParries / parryAttempts) * 100)
            S5.Text = string.format("Accuracy: %d%% (%d/%d)", acc, successfulParries, parryAttempts)
        else
            S5.Text = "Accuracy: --"
        end
        
        if Settings.AutoAbility then
            local timeSince = tick() - lastAbilityUse
            local cdRemaining = math.max(0, Settings.AbilityCooldown - timeSince)
            S6.Text = string.format("Ability: %s (%.1fs) [%d used]", 
                cdRemaining > 0 and "CD" or "RDY", 
                cdRemaining, 
                abilityUsed)
            S6.TextColor3 = cdRemaining > 0 and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(100, 255, 100)
        else
            S6.Text = "Ability: OFF"
            S6.TextColor3 = Color3.fromRGB(150, 150, 150)
        end
    else
        S1.Text = "Parry: OFF"
        S1.TextColor3 = Color3.fromRGB(255, 100, 100)
        Title.TextColor3 = Color3.fromRGB(255, 100, 100)
        S2.Text = "Target: --"
        S2.TextColor3 = Color3.fromRGB(150, 150, 150)
        S3.Text = "TTI: --"
        S3.TextColor3 = Color3.fromRGB(180, 180, 180)
        S4.Text = "Ping: --ms"
        S5.Text = "Accuracy: --"
        S6.Text = "Ability: --"
    end
end)

-- Character respawn
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if Settings.AutoParry then StartAutoParry() end
    if Settings.Speed then ApplySpeed() end
    if Settings.Fly then ToggleFly() end
    if Settings.Noclip then ToggleNoclip() end
    if Settings.AutoDash then ApplyAutoDash() end
    if Settings.AutoSpam then ApplyAutoSpam() end
    if Settings.AntiRagdoll then ApplyAntiRagdoll() end
    if Settings.BallESP then UpdateBallESP() end
end)

if Settings.AntiRagdoll then ApplyAntiRagdoll() end

print("═══════════════════════════════════")
print("Zatm Software - ULTIMATE")
print("═══════════════════════════════════")
print("")
print("ULTIMATE FIXES:")
print("TRUE single click (no double!)")
print("Per-ball decision lock (0.40s)")
print("Fixed TTI (horizontal only)")
print("Strict target validation")
print("1v1-safe ball selection")
print("Auto ability emergency system")
print("")
print("AUTO ABILITY:")
print("• Activates when parry missed")
print("• Emergency when TTI < 0.12s")
print("• Uses E/R/F keys")
print("• Panic mode for close balls")
print("• 4s cooldown default")
print("")
print("MODES:")
print("• LEGIT = 60% accuracy")
print("• MACHINE = Intelligent")
print("")
print("Creator: z4tm & stellar scripts")
print("Discord: https://discord.gg/ff7p6hGM")
print("")
print("DELETE = Menu | X = Spam")
print("")
print("═══════════════════════════════════")
