-- =========================================================
-- 🔱 ARES MUSIC HUB v5.0 - ULTRA PREMIUM EDITION 🔱
-- =========================================================
-- ✅ All original features FULLY PRESERVED
-- 🆕 v5.0: Ultra Premium GUI Redesign
-- 🆕 Smart Stop: Hover/Skate → DeleteNoMotorVehicle | FE → feSound:Stop
-- 🆕 Mini STOP button on EVERY tab
-- 🆕 Playlist: Enhanced larger song rows with more visual info
-- 🆕 RGB added to Skateboard
-- 🆕 Auto-play Next | Shuffle | Repeat Mode
-- 🆕 Animated Toggle Button | Glassmorphism UI | Tab Indicators
-- 🔧 FIXED: GUI blank issue (UIScale executor rendering fix)
-- 📛 NEW: Auto RP Name Autofill with Smooth RGB Loop
-- 🔒 SECURE: Playlist IDs never exposed, no autofill, no clipboard copy
-- 💾 FIXED: Favorites now persist across re-executes
-- ⭐ NEW: Star save button on every playlist song
-- 🎵 NEW: FE Music option in vehicle selector
-- 🔍 NEW: Search auto-play + auto-copy + auto-fill (no tab switch)
-- 🌐 NEW: Playlist fetched from GitHub (no hardcoded songs)
-- 🎨 v5.1: Next-Gen GUI — compact, sleek, professional redesign
-- =========================================================

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local remote = RS:WaitForChild("RE"):WaitForChild("1NoMoto1rVehicle1s")
local colorRemote = RS:WaitForChild("RE"):WaitForChild("1Player1sCa1r")

-- =========================================================
-- 🎛️ STATE VARIABLES
-- =========================================================
local rgbEnabled = false
local playbackSpeed = 1.0
local shuffleMode = false
local repeatMode = false
local currentSongName = "None"
local currentSongId = ""
local favoritesList = {}
local historyList = {}
local isPlaying = false
local currentPlaylist = {}
local currentIndex = 1
local autoPlayNext = false
local eqEnabled = false
local currentTabIndex = 1
local playlistScrollPos = Vector2.new(0, 0)
local currentLoadedCategory = nil
local currentPlayMode = "Hoverboard"

-- =========================================================
-- 💾 FAVORITES PERSISTENCE
-- =========================================================
local FAVS_FILE = "ares_music_favs.json"

local function saveFavorites()
    pcall(function()
        writefile(FAVS_FILE, HttpService:JSONEncode(favoritesList))
    end)
end

local function loadFavorites()
    pcall(function()
        if isfile and isfile(FAVS_FILE) then
            local raw = readfile(FAVS_FILE)
            if raw and raw ~= "" then
                local decoded = HttpService:JSONDecode(raw)
                if type(decoded) == "table" then
                    favoritesList = decoded
                end
            end
        end
    end)
end

loadFavorites()

-- =========================================================
-- 📐 SCREEN SIZE DETECTION
-- =========================================================
local camera = workspace.CurrentCamera
local screenSize = camera.ViewportSize
local isMobile = screenSize.X < 600 or screenSize.Y < 600

-- =========================================================
-- 🎨 DESIGN CONSTANTS — Next-Gen Theme
-- =========================================================
local C_BG       = Color3.fromRGB(7,   9,  18)   -- deep dark panel
local C_CARD     = Color3.fromRGB(11,  14,  26)   -- card surface
local C_CARD2    = Color3.fromRGB(16,  20,  36)   -- slightly lighter card
local C_BORDER   = Color3.fromRGB(0,  185, 255)   -- cyan accent / border
local C_ACCENT   = Color3.fromRGB(0,  200, 255)   -- primary neon cyan
local C_PURPLE   = Color3.fromRGB(130,  40, 230)  -- purple accent
local C_PINK     = Color3.fromRGB(255,  45, 130)  -- hot pink
local C_GREEN    = Color3.fromRGB(0,   210, 120)  -- success green
local C_RED      = Color3.fromRGB(225,  38,  38)  -- error red
local C_ORANGE   = Color3.fromRGB(255, 130,  20)  -- orange
local C_GOLD     = Color3.fromRGB(255, 200,   0)  -- gold
local C_TEXT     = Color3.fromRGB(220, 228, 255)  -- primary text
local C_MUTED    = Color3.fromRGB(90,  105, 150)  -- muted text
local C_SUBTEXT  = Color3.fromRGB(60,   72, 108)  -- very muted

-- Compact dimensions
local PANEL_W   = isMobile and math.min(screenSize.X - 8, 340) or 455
local PANEL_H   = isMobile and math.min(screenSize.Y - 8, 560) or 575
local HEADER_H  = isMobile and 50 or 56
local NOWPLAY_H = isMobile and 36 or 42
local TABBAR_H  = isMobile and 34 or 38
local BTN_H     = isMobile and 36 or 40
local INPUT_H   = isMobile and 36 or 40
local LABEL_SZ  = isMobile and 10 or 11
local TITLE_SZ  = isMobile and 14 or 18
local MINI_SZ   = isMobile and 24 or 26
local TOGGLE_W  = isMobile and 120 or 138
local TOGGLE_H  = isMobile and 38 or 42

-- =========================================================
-- 🌐 GITHUB PLAYLIST FETCH
-- =========================================================
local PLAYLIST_URL = "https://raw.githubusercontent.com/Goku55050/Aresai/refs/heads/main/ares_playlist.json"

local HindiSongs = {}
local BhojpuriSongs = {}
local PopularSongs = {}

local function fetchPlaylist()
    local ok, result = pcall(function()
        return game:HttpGet(PLAYLIST_URL)
    end)
    if ok and result and result ~= "" then
        local decodeOk, data = pcall(function()
            return HttpService:JSONDecode(result)
        end)
        if decodeOk and type(data) == "table" then
            if type(data.HindiSongs) == "table" then
                for _, entry in ipairs(data.HindiSongs) do
                    if type(entry) == "table" and entry[1] and entry[2] then
                        table.insert(HindiSongs, {tostring(entry[1]), tostring(entry[2])})
                    end
                end
            end
            if type(data.BhojpuriSongs) == "table" then
                for _, entry in ipairs(data.BhojpuriSongs) do
                    if type(entry) == "table" and entry[1] and entry[2] then
                        table.insert(BhojpuriSongs, {tostring(entry[1]), tostring(entry[2])})
                    end
                end
            end
            if type(data.PopularSongs) == "table" then
                for _, entry in ipairs(data.PopularSongs) do
                    if type(entry) == "table" and entry[1] and entry[2] then
                        table.insert(PopularSongs, {tostring(entry[1]), tostring(entry[2])})
                    end
                end
            end
            return true
        end
    end
    return false
end

local fetchSuccess = fetchPlaylist()

local AllSongs = {}
for _, s in pairs(HindiSongs)    do table.insert(AllSongs, s) end
for _, s in pairs(BhojpuriSongs) do table.insert(AllSongs, s) end
for _, s in pairs(PopularSongs)  do table.insert(AllSongs, s) end

-- =========================================================
-- 🖥️ ROOT GUI
-- =========================================================
local gui = Instance.new("ScreenGui")
gui.Name = "ARES_MUSIC_HUB_V5"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = game.CoreGui

-- =========================================================
-- 🔧 UTILITY FUNCTIONS
-- =========================================================
local function makeTween(obj, props, t, style, dir)
    local info = TweenInfo.new(t or 0.22, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
    return TweenService:Create(obj, info, props)
end

local function corner(obj, r)
    Instance.new("UICorner", obj).CornerRadius = UDim.new(0, r or 10)
end

local function stroke(obj, color, thick)
    local s = Instance.new("UIStroke", obj)
    s.Thickness = thick or 1.5
    s.Color = color or C_BORDER
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    return s
end

local function gradient(obj, c0, c1, rot)
    local g = Instance.new("UIGradient", obj)
    g.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, c0), ColorSequenceKeypoint.new(1, c1)})
    g.Rotation = rot or 90
    return g
end

local function applyGlow(obj, color)
    return stroke(obj, color or C_BORDER, 1.5)
end

-- =========================================================
-- 🔔 NOTIFICATION SYSTEM — Compact + Stylish
-- =========================================================
local function notify(msg, color)
    local nW = isMobile and math.min(screenSize.X - 20, 280) or 310
    local notif = Instance.new("Frame", gui)
    notif.Size = UDim2.new(0, nW, 0, 42)
    notif.Position = UDim2.new(0.5, -nW/2, 0, -60)
    notif.BackgroundColor3 = C_CARD2
    notif.ZIndex = 100
    corner(notif, 12)

    -- Left color stripe
    local stripe = Instance.new("Frame", notif)
    stripe.Size = UDim2.new(0, 4, 1, 0)
    stripe.BackgroundColor3 = color or C_GREEN
    stripe.ZIndex = 101
    corner(stripe, 4)

    local icon = Instance.new("TextLabel", notif)
    icon.Size = UDim2.new(0, 32, 1, 0)
    icon.Position = UDim2.new(0, 10, 0, 0)
    icon.Text = "♪"
    icon.Font = Enum.Font.GothamBold
    icon.TextSize = 16
    icon.TextColor3 = color or C_GREEN
    icon.BackgroundTransparency = 1
    icon.ZIndex = 101

    local lbl = Instance.new("TextLabel", notif)
    lbl.Size = UDim2.new(1, -46, 1, 0)
    lbl.Position = UDim2.new(0, 44, 0, 0)
    lbl.Text = msg
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = isMobile and 12 or 13
    lbl.TextColor3 = C_TEXT
    lbl.BackgroundTransparency = 1
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextWrapped = true
    lbl.ZIndex = 101

    stroke(notif, (color or C_GREEN):Lerp(Color3.new(0,0,0), 0.4), 1)

    makeTween(notif, {Position = UDim2.new(0.5, -nW/2, 0, 14)}, 0.4, Enum.EasingStyle.Back):Play()
    task.delay(2.6, function()
        makeTween(notif, {Position = UDim2.new(0.5, -nW/2, 0, -60), BackgroundTransparency = 1}, 0.35):Play()
        task.delay(0.38, function() notif:Destroy() end)
    end)
end

-- =========================================================
-- 🔊 CORE MUSIC FUNCTIONS (unchanged logic)
-- =========================================================
local feSound = Instance.new("Sound", SoundService)
feSound.Looped = true

local function playOnHoverboard(id, name)
    if not id or id == "" then return end
    rgbEnabled = true
    currentSongId = tostring(id)
    currentSongName = name or id
    isPlaying = true
    currentPlayMode = "Hoverboard"
    remote:FireServer("SegwaySmall")
    task.wait(0.3)
    remote:FireServer("PickingScooterMusicText", tostring(id), true)
    table.insert(historyList, 1, {tostring(id), currentSongName})
    if #historyList > 20 then table.remove(historyList) end
    notify("🛵 Playing: " .. currentSongName, C_ACCENT)
end

local function stopMusic()
    rgbEnabled = false
    isPlaying = false
    if currentPlayMode == "FEMusic" then
        feSound:Stop()
        notify("⏹ FE Local Stopped", C_RED)
    else
        local args = {"Delete NoMotorVehicle"}
        remote:FireServer(unpack(args))
        pcall(function() feSound:Stop() end)
        notify("⏹ Music Stopped", C_RED)
    end
end

local function playOnSkateboard(id, name)
    if not id or id == "" then return end
    rgbEnabled = true
    currentSongId = tostring(id)
    currentSongName = name or id
    isPlaying = true
    currentPlayMode = "Skateboard"
    remote:FireServer("SkateBoard")
    task.wait(0.3)
    remote:FireServer("PickingScooterMusicText", id, true)
    table.insert(historyList, 1, {tostring(id), currentSongName})
    if #historyList > 20 then table.remove(historyList) end
    notify("🛹 Skateboard: " .. currentSongName, C_PURPLE)
end

local function playFEMusic(id, name)
    if not id or id == "" then return end
    currentSongId = tostring(id)
    currentSongName = name or id
    isPlaying = true
    currentPlayMode = "FEMusic"
    feSound.SoundId = "rbxassetid://" .. tostring(id)
    feSound.Looped = true
    feSound:Play()
    table.insert(historyList, 1, {tostring(id), currentSongName})
    if #historyList > 20 then table.remove(historyList) end
    notify("🎵 FE Music: " .. currentSongName, C_GREEN)
end

-- =========================================================
-- ✨ TOGGLE BUTTON — Sleek Horizontal Pill (Draggable)
-- =========================================================
local toggleFrame = Instance.new("Frame", gui)
toggleFrame.Size = UDim2.new(0, TOGGLE_W, 0, TOGGLE_H)
toggleFrame.Position = UDim2.new(1, -(TOGGLE_W + 12), 1, -(TOGGLE_H + 70))
toggleFrame.BackgroundTransparency = 1
toggleFrame.Active = true

local toggle = Instance.new("TextButton", toggleFrame)
toggle.Size = UDim2.new(1, 0, 1, 0)
toggle.Text = ""
toggle.BackgroundColor3 = C_BG
toggle.Active = true
toggle.Draggable = false
corner(toggle, TOGGLE_H // 2)

gradient(toggle, Color3.fromRGB(12, 8, 30), Color3.fromRGB(4, 18, 40), 135)

local toggleStroke = stroke(toggle, C_ACCENT, 2)

-- Toggle content
local toggleIconLbl = Instance.new("TextLabel", toggle)
toggleIconLbl.Size = UDim2.new(0, TOGGLE_H, 1, 0)
toggleIconLbl.Text = "🎧"
toggleIconLbl.TextScaled = true
toggleIconLbl.BackgroundTransparency = 1
toggleIconLbl.Font = Enum.Font.GothamBold
toggleIconLbl.ZIndex = 2

local toggleDivider = Instance.new("Frame", toggle)
toggleDivider.Size = UDim2.new(0, 1, 0.55, 0)
toggleDivider.Position = UDim2.new(0, TOGGLE_H, 0.225, 0)
toggleDivider.BackgroundColor3 = C_BORDER
toggleDivider.BackgroundTransparency = 0.6
toggleDivider.ZIndex = 2

local toggleLabel = Instance.new("TextLabel", toggle)
toggleLabel.Size = UDim2.new(1, -(TOGGLE_H + 4), 1, 0)
toggleLabel.Position = UDim2.new(0, TOGGLE_H + 6, 0, 0)
toggleLabel.Text = "ARES HUB"
toggleLabel.Font = Enum.Font.GothamBlack
toggleLabel.TextSize = isMobile and 11 or 12
toggleLabel.TextColor3 = C_ACCENT
toggleLabel.BackgroundTransparency = 1
toggleLabel.TextXAlignment = Enum.TextXAlignment.Left
toggleLabel.ZIndex = 2

-- Pulse glow animation
task.spawn(function()
    while true do
        makeTween(toggleStroke, {Thickness = 2.5, Color = C_ACCENT}, 0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut):Play()
        task.wait(0.9)
        makeTween(toggleStroke, {Thickness = 1.5, Color = Color3.fromRGB(0, 140, 200)}, 0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut):Play()
        task.wait(0.9)
    end
end)

-- Draggable toggle
local dragging, dragStart, startPos
local function onDragBegan(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = toggleFrame.Position
    end
end
local function onDragEnded(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end
toggle.InputBegan:Connect(onDragBegan)
toggle.InputEnded:Connect(onDragEnded)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        if math.abs(delta.X) > 4 or math.abs(delta.Y) > 4 then
            toggleFrame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end
end)

-- =========================================================
-- 🪟 MAIN PANEL — Next-Gen Compact Design
-- =========================================================
-- Shadow layer
local panelShadow = Instance.new("Frame", gui)
panelShadow.Size = UDim2.new(0, PANEL_W + 28, 0, PANEL_H + 28)
panelShadow.Position = UDim2.new(0.5, -(PANEL_W + 28)/2, 0.5, -(PANEL_H + 28)/2 + 6)
panelShadow.BackgroundColor3 = Color3.fromRGB(0, 60, 140)
panelShadow.BackgroundTransparency = 0.84
panelShadow.ZIndex = 9
corner(panelShadow, 22)

local panel = Instance.new("Frame", gui)
panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
panel.Position = UDim2.new(0.5, -PANEL_W/2, 0.5, -PANEL_H/2)
panel.BackgroundColor3 = C_BG
panel.Visible = false
panel.Active = true
panel.Draggable = true
panel.ZIndex = 10
corner(panel, 16)

local panelStroke = stroke(panel, C_BORDER, 1.5)

-- Panel inner gradient
local panelGrad = Instance.new("UIGradient", panel)
panelGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,    Color3.fromRGB(9, 12, 26)),
    ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(7,  9, 20)),
    ColorSequenceKeypoint.new(1,    Color3.fromRGB(10, 8, 22)),
})
panelGrad.Rotation = 145

local panelScale = Instance.new("UIScale", panel)
panelScale.Scale = 0

-- =========================================================
-- 🎨 HEADER — Compact Professional Bar
-- =========================================================
local header = Instance.new("Frame", panel)
header.Size = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = C_CARD
header.BorderSizePixel = 0
header.ZIndex = 12
corner(header, 16)

gradient(header,
    Color3.fromRGB(0, 70, 160),
    Color3.fromRGB(18, 4, 50),
    90)

-- Bottom border line on header
local headerAccentLine = Instance.new("Frame", header)
headerAccentLine.Size = UDim2.new(1, -24, 0, 1)
headerAccentLine.Position = UDim2.new(0, 12, 1, -1)
headerAccentLine.BackgroundTransparency = 0
headerAccentLine.ZIndex = 13
gradient(headerAccentLine, C_PURPLE, C_ACCENT, 0)

-- Logo dot
local logoDot = Instance.new("Frame", header)
logoDot.Size = UDim2.new(0, 8, 0, 8)
logoDot.Position = UDim2.new(0, 14, 0.5, -4)
logoDot.BackgroundColor3 = C_ACCENT
logoDot.ZIndex = 13
corner(logoDot, 4)

-- Title
local title = Instance.new("TextLabel", header)
title.Size = UDim2.new(0.55, 0, 0.55, 0)
title.Position = UDim2.new(0, 28, 0.06, 0)
title.Text = "ARES MUSIC HUB"
title.Font = Enum.Font.GothamBlack
title.TextSize = TITLE_SZ
title.TextColor3 = C_TEXT
title.TextXAlignment = Enum.TextXAlignment.Left
title.BackgroundTransparency = 1
title.TextTruncate = Enum.TextTruncate.AtEnd
title.ZIndex = 13

-- Version badge
local verBadge = Instance.new("TextLabel", header)
verBadge.Size = UDim2.new(0, isMobile and 56 or 64, 0, 14)
verBadge.Position = UDim2.new(0, 28, 0.62, 0)
verBadge.Text = "v5.0 PREMIUM"
verBadge.Font = Enum.Font.GothamBold
verBadge.TextSize = 7
verBadge.TextColor3 = C_GOLD
verBadge.BackgroundColor3 = Color3.fromRGB(40, 30, 5)
verBadge.ZIndex = 13
corner(verBadge, 4)
Instance.new("UIPadding", verBadge).PaddingLeft = UDim.new(0, 4)

-- Header control buttons
local function makeHeaderBtn(icon, xOffset, bgColor)
    local btn = Instance.new("TextButton", header)
    btn.Size = UDim2.new(0, isMobile and 26 or 28, 0, isMobile and 26 or 28)
    btn.Position = UDim2.new(1, xOffset, 0.5, isMobile and -13 or -14)
    btn.Text = icon
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = isMobile and 11 or 12
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.BackgroundColor3 = bgColor
    btn.ZIndex = 13
    corner(btn, 8)
    btn.MouseEnter:Connect(function()
        makeTween(btn, {BackgroundTransparency = 0.2}, 0.15):Play()
    end)
    btn.MouseLeave:Connect(function()
        makeTween(btn, {BackgroundTransparency = 0}, 0.15):Play()
    end)
    return btn
end

local closeBtn = makeHeaderBtn("✕", isMobile and -8 or -10, C_RED)
local minBtn   = makeHeaderBtn("—", isMobile and -38 or -42, Color3.fromRGB(35, 55, 15))

-- =========================================================
-- 🎵 NOW PLAYING BAR — Compact Equalizer Style
-- =========================================================
local NP_TOP = HEADER_H + 4

local nowPlayingBar = Instance.new("Frame", panel)
nowPlayingBar.Size = UDim2.new(1, -14, 0, NOWPLAY_H)
nowPlayingBar.Position = UDim2.new(0, 7, 0, NP_TOP)
nowPlayingBar.BackgroundColor3 = C_CARD
nowPlayingBar.ZIndex = 12
corner(nowPlayingBar, 10)
stroke(nowPlayingBar, Color3.fromRGB(0, 80, 140), 1)

gradient(nowPlayingBar,
    Color3.fromRGB(0, 45, 110),
    Color3.fromRGB(10, 10, 26),
    90)

-- Animated equalizer bars
local eqFrame = Instance.new("Frame", nowPlayingBar)
eqFrame.Size = UDim2.new(0, isMobile and 20 or 22, 1, -10)
eqFrame.Position = UDim2.new(0, 8, 0.5, isMobile and -10 or -11)
eqFrame.BackgroundTransparency = 1
eqFrame.ZIndex = 13

local eqBars = {}
for b = 1, 3 do
    local bar = Instance.new("Frame", eqFrame)
    bar.Width = UDim.new(0, 3)
    bar.BackgroundColor3 = C_ACCENT
    bar.ZIndex = 14
    corner(bar, 2)
    local list = Instance.new("UIListLayout", eqFrame)
    list.FillDirection = Enum.FillDirection.Horizontal
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 2)
    bar.LayoutOrder = b
    table.insert(eqBars, bar)
end
-- Fix: manually position bars since UIListLayout is reused
eqFrame:ClearAllChildren()
for b = 1, 3 do
    local bar = Instance.new("Frame", eqFrame)
    bar.Size = UDim2.new(0, 3, 0.4, 0)
    bar.Position = UDim2.new(0, (b-1)*5, 0.5, 0)
    bar.BackgroundColor3 = C_ACCENT
    bar.ZIndex = 14
    corner(bar, 1)
    eqBars[b] = bar
end

-- Animate EQ bars
task.spawn(function()
    local heights = {0.35, 0.65, 0.45}
    local dirs = {1, -1, 1}
    while true do
        for b = 1, 3 do
            if isPlaying then
                heights[b] = heights[b] + dirs[b] * (0.05 + math.random() * 0.08)
                if heights[b] > 0.9 then dirs[b] = -1 end
                if heights[b] < 0.15 then dirs[b] = 1 end
                eqBars[b].Size = UDim2.new(0, 3, heights[b], 0)
                eqBars[b].Position = UDim2.new(0, (b-1)*5, (1 - heights[b]) / 2, 0)
                eqBars[b].BackgroundColor3 = C_ACCENT
            else
                eqBars[b].Size = UDim2.new(0, 3, 0.25, 0)
                eqBars[b].Position = UDim2.new(0, (b-1)*5, 0.375, 0)
                eqBars[b].BackgroundColor3 = C_MUTED
            end
        end
        task.wait(0.08)
    end
end)

-- Now playing text
local npLabel = Instance.new("TextLabel", nowPlayingBar)
npLabel.Size = UDim2.new(1, isMobile and -100 or -110, 1, 0)
npLabel.Position = UDim2.new(0, isMobile and 36 or 38, 0, 0)
npLabel.Text = "Now Playing: None"
npLabel.Font = Enum.Font.GothamBold
npLabel.TextSize = isMobile and 10 or 12
npLabel.TextColor3 = C_MUTED
npLabel.TextXAlignment = Enum.TextXAlignment.Left
npLabel.TextTruncate = Enum.TextTruncate.AtEnd
npLabel.BackgroundTransparency = 1
npLabel.ZIndex = 13

-- Live dot
local liveIndicator = Instance.new("Frame", nowPlayingBar)
liveIndicator.Size = UDim2.new(0, 6, 0, 6)
liveIndicator.Position = UDim2.new(1, isMobile and -54 or -58, 0.5, -3)
liveIndicator.BackgroundColor3 = C_MUTED
liveIndicator.ZIndex = 13
corner(liveIndicator, 3)

task.spawn(function()
    while true do
        if isPlaying then
            makeTween(liveIndicator, {BackgroundColor3 = C_GREEN}, 0.45):Play()
            task.wait(0.45)
            makeTween(liveIndicator, {BackgroundColor3 = Color3.fromRGB(0, 80, 40)}, 0.45):Play()
            task.wait(0.45)
        else
            liveIndicator.BackgroundColor3 = C_MUTED
            task.wait(0.5)
        end
    end
end)

-- Mini stop in NP bar
local npStopBtn = Instance.new("TextButton", nowPlayingBar)
npStopBtn.Size = UDim2.new(0, isMobile and 40 or 46, 0, isMobile and 20 or 24)
npStopBtn.Position = UDim2.new(1, isMobile and -44 or -50, 0.5, isMobile and -10 or -12)
npStopBtn.Text = "⏹ STOP"
npStopBtn.Font = Enum.Font.GothamBold
npStopBtn.TextSize = isMobile and 8 or 9
npStopBtn.BackgroundColor3 = C_RED
npStopBtn.TextColor3 = Color3.new(1,1,1)
npStopBtn.ZIndex = 14
corner(npStopBtn, 6)

local function updateNowPlaying()
    local modeIcon = ""
    if currentPlayMode == "Hoverboard" then modeIcon = " 🛵"
    elseif currentPlayMode == "Skateboard" then modeIcon = " 🛹"
    elseif currentPlayMode == "FEMusic" then modeIcon = " 🎵"
    end
    npLabel.Text = (isPlaying and "▶  " or "■  ") .. currentSongName .. (isPlaying and modeIcon or "")
    npLabel.TextColor3 = isPlaying and C_ACCENT or C_MUTED
end

-- =========================================================
-- 🗂️ TAB BAR — Icon + Text Compact Pill Tabs
-- =========================================================
local NP_BOTTOM = NP_TOP + NOWPLAY_H + 4

local tabBarFrame = Instance.new("Frame", panel)
tabBarFrame.Size = UDim2.new(1, -14, 0, TABBAR_H)
tabBarFrame.Position = UDim2.new(0, 7, 0, NP_BOTTOM)
tabBarFrame.BackgroundColor3 = C_CARD
tabBarFrame.ZIndex = 12
corner(tabBarFrame, 10)

local tabScroll = Instance.new("ScrollingFrame", tabBarFrame)
tabScroll.Size = UDim2.new(1, 0, 1, 0)
tabScroll.BackgroundTransparency = 1
tabScroll.ScrollBarThickness = 0
tabScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
tabScroll.CanvasSize = UDim2.new(0,0,0,0)
tabScroll.ScrollingDirection = Enum.ScrollingDirection.X
tabScroll.ZIndex = 13

local tabLayout = Instance.new("UIListLayout", tabScroll)
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Padding = UDim.new(0, 2)
Instance.new("UIPadding", tabScroll).PaddingLeft = UDim.new(0, 3)

local tabDefs = {
    {icon = "🎛", label = "PLAYER"},
    {icon = "📋", label = "LIST"},
    {icon = "🔍", label = "SEARCH"},
    {icon = "📻", label = "FE"},
    {icon = "⭐", label = "FAVS"},
    {icon = "🕐", label = "LOG"},
}

local tabButtons = {}
local tabBtnW = isMobile and 64 or 72

for i, def in ipairs(tabDefs) do
    local btn = Instance.new("TextButton", tabScroll)
    btn.Size = UDim2.new(0, tabBtnW, 1, -5)
    btn.LayoutOrder = i
    btn.Text = def.icon .. " " .. def.label
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = isMobile and 8 or 9
    btn.TextColor3 = C_MUTED
    btn.BackgroundColor3 = Color3.fromRGB(14, 17, 32)
    btn.ZIndex = 14
    corner(btn, 8)
    tabButtons[i] = btn
end

-- =========================================================
-- 🖼️ TAB CONTENT AREA
-- =========================================================
local TAB_TOP = NP_BOTTOM + TABBAR_H + 5
local TAB_H = PANEL_H - TAB_TOP - 5

local tabArea = Instance.new("Frame", panel)
tabArea.Size = UDim2.new(1, -14, 0, TAB_H)
tabArea.Position = UDim2.new(0, 7, 0, TAB_TOP)
tabArea.BackgroundTransparency = 1
tabArea.ClipsDescendants = true
tabArea.ZIndex = 12

local function newTabFrame()
    local f = Instance.new("Frame", tabArea)
    f.Size = UDim2.new(1, 0, 1, 0)
    f.BackgroundTransparency = 1
    f.Visible = false
    f.ZIndex = 13
    return f
end

local MusicTab    = newTabFrame()
local PlaylistTab = newTabFrame()
local SearchTab   = newTabFrame()
local FETab       = newTabFrame()
local FavTab      = newTabFrame()
local HistTab     = newTabFrame()

local allTabs = {MusicTab, PlaylistTab, SearchTab, FETab, FavTab, HistTab}

local function setTab(idx)
    currentTabIndex = idx
    for i, f in ipairs(allTabs) do
        f.Visible = (i == idx)
    end
    for i, btn in ipairs(tabButtons) do
        if i == idx then
            btn.BackgroundColor3 = Color3.fromRGB(0, 80, 175)
            btn.TextColor3 = C_ACCENT
        else
            btn.BackgroundColor3 = Color3.fromRGB(14, 17, 32)
            btn.TextColor3 = C_MUTED
        end
    end
end

for i, btn in ipairs(tabButtons) do
    btn.MouseButton1Click:Connect(function() setTab(i) end)
end

-- =========================================================
-- 🔧 WIDGET BUILDERS
-- =========================================================
local function mkLabel(parent, text, y, sz, color)
    local l = Instance.new("TextLabel", parent)
    l.Size = UDim2.new(1, 0, 0, 16)
    l.Position = UDim2.new(0, 0, 0, y)
    l.Text = text
    l.Font = Enum.Font.GothamBold
    l.TextSize = sz or LABEL_SZ
    l.TextColor3 = color or C_MUTED
    l.BackgroundTransparency = 1
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.ZIndex = parent.ZIndex + 1
    return l
end

local function mkTextBox(parent, placeholder, y, h)
    local box = Instance.new("TextBox", parent)
    box.Size = UDim2.new(1, 0, 0, h or INPUT_H)
    box.Position = UDim2.new(0, 0, 0, y)
    box.PlaceholderText = placeholder
    box.Font = Enum.Font.Gotham
    box.TextSize = isMobile and 12 or 13
    box.BackgroundColor3 = C_CARD2
    box.TextColor3 = C_TEXT
    box.PlaceholderColor3 = C_SUBTEXT
    box.ClearTextOnFocus = false
    box.ZIndex = parent.ZIndex + 1
    corner(box, 9)
    stroke(box, Color3.fromRGB(0, 80, 160), 1)
    local pad = Instance.new("UIPadding", box)
    pad.PaddingLeft = UDim.new(0, 10)
    return box
end

local function mkBtn(parent, text, y, h, bgColor, txtColor)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(1, 0, 0, h or BTN_H)
    btn.Position = UDim2.new(0, 0, 0, y)
    btn.Text = text
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = isMobile and 12 or 13
    btn.BackgroundColor3 = bgColor or Color3.fromRGB(0, 100, 200)
    btn.TextColor3 = txtColor or Color3.new(1,1,1)
    btn.ZIndex = parent.ZIndex + 1
    corner(btn, 9)
    local orig = bgColor or Color3.fromRGB(0, 100, 200)
    btn.MouseEnter:Connect(function()
        makeTween(btn, {BackgroundColor3 = orig:Lerp(Color3.new(1,1,1), 0.14)}, 0.16):Play()
    end)
    btn.MouseLeave:Connect(function()
        makeTween(btn, {BackgroundColor3 = orig}, 0.16):Play()
    end)
    return btn
end

-- 🆕 MINI STOP BAR — compact version
local function addMiniStopBar(tabFrame, zOffset)
    local bar = Instance.new("Frame", tabFrame)
    bar.Size = UDim2.new(1, 0, 0, MINI_SZ)
    bar.Position = UDim2.new(0, 0, 0, zOffset or 0)
    bar.BackgroundColor3 = Color3.fromRGB(22, 10, 10)
    bar.ZIndex = tabFrame.ZIndex + 1
    corner(bar, 8)
    gradient(bar, Color3.fromRGB(36, 8, 8), Color3.fromRGB(14, 6, 6), 90)

    local stopLbl = Instance.new("TextLabel", bar)
    stopLbl.Size = UDim2.new(0.5, 0, 1, 0)
    stopLbl.Position = UDim2.new(0, 8, 0, 0)
    stopLbl.Text = "⏹ Quick Stop"
    stopLbl.Font = Enum.Font.GothamBold
    stopLbl.TextSize = isMobile and 8 or 9
    stopLbl.TextColor3 = Color3.fromRGB(255, 110, 110)
    stopLbl.BackgroundTransparency = 1
    stopLbl.TextXAlignment = Enum.TextXAlignment.Left
    stopLbl.ZIndex = bar.ZIndex + 1

    local sBtn = Instance.new("TextButton", bar)
    sBtn.Size = UDim2.new(0, isMobile and 58 or 66, 0, isMobile and 16 or 18)
    sBtn.Position = UDim2.new(1, isMobile and -62 or -70, 0.5, isMobile and -8 or -9)
    sBtn.Text = "STOP NOW"
    sBtn.Font = Enum.Font.GothamBold
    sBtn.TextSize = isMobile and 8 or 9
    sBtn.BackgroundColor3 = C_RED
    sBtn.TextColor3 = Color3.new(1,1,1)
    sBtn.ZIndex = bar.ZIndex + 2
    corner(sBtn, 5)

    sBtn.MouseButton1Click:Connect(function()
        stopMusic()
        feSound:Stop()
        isPlaying = false
        updateNowPlaying()
    end)

    return bar, MINI_SZ + 4
end

-- =========================================================
-- 🎛️ TAB 1 — PLAYER TAB
-- =========================================================
local playerScroll = Instance.new("ScrollingFrame", MusicTab)
playerScroll.Size = UDim2.new(1, 0, 1, 0)
playerScroll.BackgroundTransparency = 1
playerScroll.ScrollBarThickness = isMobile and 2 or 3
playerScroll.ScrollBarImageColor3 = C_BORDER
playerScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
playerScroll.CanvasSize = UDim2.new(0,0,0,0)
playerScroll.ZIndex = 14

local playerPad = Instance.new("Frame", playerScroll)
playerPad.Size = UDim2.new(1, 0, 0, 340)
playerPad.BackgroundTransparency = 1
playerPad.ZIndex = 14

local Y = 0

mkLabel(playerPad, "  Music ID", Y, LABEL_SZ, C_MUTED)
Y = Y + 15
local idBox = mkTextBox(playerPad, "Enter Music ID here...", Y, INPUT_H)
Y = Y + INPUT_H + 6

-- Two-button row: Skate | Hover
local halfW = (PANEL_W - 28) / 2 - 3

local skateBtn = Instance.new("TextButton", playerPad)
skateBtn.Size = UDim2.new(0.48, 0, 0, BTN_H)
skateBtn.Position = UDim2.new(0, 0, 0, Y)
skateBtn.Text = "🛹 Skateboard"
skateBtn.Font = Enum.Font.GothamBold
skateBtn.TextSize = isMobile and 11 or 12
skateBtn.BackgroundColor3 = Color3.fromRGB(28, 90, 210)
skateBtn.TextColor3 = Color3.new(1,1,1)
skateBtn.ZIndex = 15
corner(skateBtn, 9)
skateBtn.MouseEnter:Connect(function() makeTween(skateBtn, {BackgroundColor3 = Color3.fromRGB(48, 110, 230)}, 0.15):Play() end)
skateBtn.MouseLeave:Connect(function() makeTween(skateBtn, {BackgroundColor3 = Color3.fromRGB(28, 90, 210)}, 0.15):Play() end)

local hoverBtn = Instance.new("TextButton", playerPad)
hoverBtn.Size = UDim2.new(0.49, 0, 0, BTN_H)
hoverBtn.Position = UDim2.new(0.51, 0, 0, Y)
hoverBtn.Text = "🛵 Hoverboard"
hoverBtn.Font = Enum.Font.GothamBold
hoverBtn.TextSize = isMobile and 11 or 12
hoverBtn.BackgroundColor3 = Color3.fromRGB(200, 85, 0)
hoverBtn.TextColor3 = Color3.new(1,1,1)
hoverBtn.ZIndex = 15
corner(hoverBtn, 9)
hoverBtn.MouseEnter:Connect(function() makeTween(hoverBtn, {BackgroundColor3 = Color3.fromRGB(220, 105, 20)}, 0.15):Play() end)
hoverBtn.MouseLeave:Connect(function() makeTween(hoverBtn, {BackgroundColor3 = Color3.fromRGB(200, 85, 0)}, 0.15):Play() end)
Y = Y + BTN_H + 4

local stopBtn = mkBtn(playerPad, "⏹  STOP MUSIC", Y, BTN_H, C_RED)
Y = Y + BTN_H + 8

-- Divider
local div1 = Instance.new("Frame", playerPad)
div1.Size = UDim2.new(1, 0, 0, 1)
div1.Position = UDim2.new(0, 0, 0, Y)
div1.BackgroundColor3 = C_CARD2
div1.ZIndex = 14
gradient(div1, Color3.fromRGB(20,25,50), C_CARD2, 0)
Y = Y + 8

-- RGB toggle row
local rgbRow = Instance.new("Frame", playerPad)
rgbRow.Size = UDim2.new(1, 0, 0, 30)
rgbRow.Position = UDim2.new(0, 0, 0, Y)
rgbRow.BackgroundColor3 = C_CARD2
rgbRow.ZIndex = 15
corner(rgbRow, 8)
Y = Y + 36

local rgbLbl = Instance.new("TextLabel", rgbRow)
rgbLbl.Size = UDim2.new(0.6, 0, 1, 0)
rgbLbl.Position = UDim2.new(0, 10, 0, 0)
rgbLbl.Text = "🌈  RGB Global Color"
rgbLbl.Font = Enum.Font.GothamBold
rgbLbl.TextSize = isMobile and 10 or 11
rgbLbl.TextColor3 = C_TEXT
rgbLbl.BackgroundTransparency = 1
rgbLbl.TextXAlignment = Enum.TextXAlignment.Left
rgbLbl.ZIndex = 16

local rgbToggleOuter = Instance.new("Frame", rgbRow)
rgbToggleOuter.Size = UDim2.new(0, 44, 0, 22)
rgbToggleOuter.Position = UDim2.new(1, -50, 0.5, -11)
rgbToggleOuter.BackgroundColor3 = Color3.fromRGB(35, 38, 58)
rgbToggleOuter.ZIndex = 16
corner(rgbToggleOuter, 11)

local rgbKnob = Instance.new("Frame", rgbToggleOuter)
rgbKnob.Size = UDim2.new(0, 18, 0, 18)
rgbKnob.Position = UDim2.new(0, 2, 0.5, -9)
rgbKnob.BackgroundColor3 = Color3.fromRGB(150, 150, 170)
rgbKnob.ZIndex = 17
corner(rgbKnob, 9)

local function setRGB(on)
    rgbEnabled = on
    if on then
        makeTween(rgbToggleOuter, {BackgroundColor3 = C_GREEN}, 0.2):Play()
        makeTween(rgbKnob, {Position = UDim2.new(0, 24, 0.5, -9), BackgroundColor3 = Color3.new(1,1,1)}, 0.2):Play()
    else
        makeTween(rgbToggleOuter, {BackgroundColor3 = Color3.fromRGB(35,38,58)}, 0.2):Play()
        makeTween(rgbKnob, {Position = UDim2.new(0, 2, 0.5, -9), BackgroundColor3 = Color3.fromRGB(150,150,170)}, 0.2):Play()
    end
end
rgbToggleOuter.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1
    or inp.UserInputType == Enum.UserInputType.Touch then
        setRGB(not rgbEnabled)
    end
end)

-- Shuffle / Repeat row
local srRow = Instance.new("Frame", playerPad)
srRow.Size = UDim2.new(1, 0, 0, BTN_H - 6)
srRow.Position = UDim2.new(0, 0, 0, Y)
srRow.BackgroundTransparency = 1
srRow.ZIndex = 15
Y = Y + BTN_H + 2

local shuffleBtn = Instance.new("TextButton", srRow)
shuffleBtn.Size = UDim2.new(0.485, 0, 1, 0)
shuffleBtn.Text = "🔀  Shuffle: OFF"
shuffleBtn.Font = Enum.Font.GothamBold
shuffleBtn.TextSize = isMobile and 10 or 11
shuffleBtn.BackgroundColor3 = C_CARD2
shuffleBtn.TextColor3 = C_MUTED
shuffleBtn.ZIndex = 16
corner(shuffleBtn, 9)

local repeatBtn = Instance.new("TextButton", srRow)
repeatBtn.Size = UDim2.new(0.485, 0, 1, 0)
repeatBtn.Position = UDim2.new(0.515, 0, 0, 0)
repeatBtn.Text = "🔁  Repeat: OFF"
repeatBtn.Font = Enum.Font.GothamBold
repeatBtn.TextSize = isMobile and 10 or 11
repeatBtn.BackgroundColor3 = C_CARD2
repeatBtn.TextColor3 = C_MUTED
repeatBtn.ZIndex = 16
corner(repeatBtn, 9)

shuffleBtn.MouseButton1Click:Connect(function()
    shuffleMode = not shuffleMode
    shuffleBtn.Text = "🔀  Shuffle: " .. (shuffleMode and "ON" or "OFF")
    shuffleBtn.BackgroundColor3 = shuffleMode and Color3.fromRGB(0, 120, 55) or C_CARD2
    shuffleBtn.TextColor3 = shuffleMode and Color3.new(1,1,1) or C_MUTED
    notify("Shuffle " .. (shuffleMode and "ON" or "OFF"), C_GREEN)
end)
repeatBtn.MouseButton1Click:Connect(function()
    repeatMode = not repeatMode
    repeatBtn.Text = "🔁  Repeat: " .. (repeatMode and "ON" or "OFF")
    repeatBtn.BackgroundColor3 = repeatMode and C_PURPLE or C_CARD2
    repeatBtn.TextColor3 = repeatMode and Color3.new(1,1,1) or C_MUTED
    notify("Repeat " .. (repeatMode and "ON" or "OFF"), C_PURPLE)
end)

local favBtn = mkBtn(playerPad, "⭐  Add to Favorites", Y, BTN_H - 4, Color3.fromRGB(160, 115, 0))
Y = Y + BTN_H + 4

playerPad.Size = UDim2.new(1, 0, 0, Y + 10)

skateBtn.MouseButton1Click:Connect(function()
    if idBox.Text ~= "" then
        playOnSkateboard(idBox.Text, currentSongName)
        updateNowPlaying()
    else
        notify("Enter a Music ID first!", C_RED)
    end
end)
hoverBtn.MouseButton1Click:Connect(function()
    if idBox.Text ~= "" then
        playOnHoverboard(idBox.Text, currentSongName)
        updateNowPlaying()
    else
        notify("Enter a Music ID first!", C_RED)
    end
end)
stopBtn.MouseButton1Click:Connect(function()
    stopMusic()
    feSound:Stop()
    isPlaying = false
    updateNowPlaying()
end)
favBtn.MouseButton1Click:Connect(function()
    local id = idBox.Text
    if id ~= "" then
        for _, fav in pairs(favoritesList) do
            if fav[1] == id then
                notify("Already in Favorites!", C_ORANGE)
                return
            end
        end
        table.insert(favoritesList, {id, currentSongName ~= "None" and currentSongName or id})
        saveFavorites()
        notify("⭐ Added to Favorites!", C_GOLD)
    end
end)

-- =========================================================
-- 📋 TAB 2 — PLAYLIST TAB
-- =========================================================
local _, plStopBarH = addMiniStopBar(PlaylistTab, 0)

-- Vehicle selector row
local targetRow = Instance.new("Frame", PlaylistTab)
targetRow.Size = UDim2.new(1, 0, 0, 32)
targetRow.Position = UDim2.new(0, 0, 0, plStopBarH)
targetRow.BackgroundColor3 = C_CARD2
targetRow.ZIndex = 14
corner(targetRow, 8)

local vLbl = Instance.new("TextLabel", targetRow)
vLbl.Size = UDim2.new(0, isMobile and 48 or 54, 1, 0)
vLbl.Position = UDim2.new(0, 6, 0, 0)
vLbl.Text = "Vehicle:"
vLbl.Font = Enum.Font.GothamBold
vLbl.TextSize = isMobile and 8 or 9
vLbl.TextColor3 = C_MUTED
vLbl.BackgroundTransparency = 1
vLbl.TextXAlignment = Enum.TextXAlignment.Left
vLbl.ZIndex = 15

local playlistTarget = "Hoverboard"
local vBtnW = isMobile and 76 or 90
local vBtnX = isMobile and 52 or 58

local function makeVehicleBtn(text, x)
    local b = Instance.new("TextButton", targetRow)
    b.Size = UDim2.new(0, vBtnW, 0, 22)
    b.Position = UDim2.new(0, x, 0.5, -11)
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = isMobile and 8 or 9
    b.BackgroundColor3 = C_CARD
    b.TextColor3 = C_MUTED
    b.ZIndex = 15
    corner(b, 6)
    return b
end

local targetHoverBtn = makeVehicleBtn("🛵 Hover",    vBtnX)
local targetSkateBtn = makeVehicleBtn("🛹 Skate",    vBtnX + vBtnW + 3)
local targetFEBtn    = makeVehicleBtn("🎵 FE Music", vBtnX + (vBtnW + 3) * 2)

local function setVehicleTarget(v)
    playlistTarget = v
    targetHoverBtn.BackgroundColor3 = C_CARD; targetHoverBtn.TextColor3 = C_MUTED
    targetSkateBtn.BackgroundColor3 = C_CARD; targetSkateBtn.TextColor3 = C_MUTED
    targetFEBtn.BackgroundColor3 = C_CARD;    targetFEBtn.TextColor3 = C_MUTED
    if v == "Hoverboard" then
        targetHoverBtn.BackgroundColor3 = Color3.fromRGB(200, 85, 0)
        targetHoverBtn.TextColor3 = Color3.new(1,1,1)
        notify("Vehicle: 🛵 Hoverboard", C_ORANGE)
    elseif v == "Skateboard" then
        targetSkateBtn.BackgroundColor3 = Color3.fromRGB(28, 90, 210)
        targetSkateBtn.TextColor3 = Color3.new(1,1,1)
        notify("Vehicle: 🛹 Skateboard", C_ACCENT)
    elseif v == "FEMusic" then
        targetFEBtn.BackgroundColor3 = C_GREEN
        targetFEBtn.TextColor3 = Color3.new(1,1,1)
        notify("Vehicle: 🎵 FE Music (local)", C_GREEN)
    end
end
targetHoverBtn.BackgroundColor3 = Color3.fromRGB(200, 85, 0)
targetHoverBtn.TextColor3 = Color3.new(1,1,1)

targetHoverBtn.MouseButton1Click:Connect(function() setVehicleTarget("Hoverboard") end)
targetSkateBtn.MouseButton1Click:Connect(function() setVehicleTarget("Skateboard") end)
targetFEBtn.MouseButton1Click:Connect(function() setVehicleTarget("FEMusic") end)

-- Category pill row
local catRowY = plStopBarH + 36
local catRow = Instance.new("Frame", PlaylistTab)
catRow.Size = UDim2.new(1, 0, 0, 28)
catRow.Position = UDim2.new(0, 0, 0, catRowY)
catRow.BackgroundTransparency = 1
catRow.ZIndex = 14

local catScroll = Instance.new("ScrollingFrame", catRow)
catScroll.Size = UDim2.new(1, 0, 1, 0)
catScroll.BackgroundTransparency = 1
catScroll.ScrollBarThickness = 0
catScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
catScroll.CanvasSize = UDim2.new(0,0,0,0)
catScroll.ScrollingDirection = Enum.ScrollingDirection.X
catScroll.ZIndex = 15

local catLL = Instance.new("UIListLayout", catScroll)
catLL.FillDirection = Enum.FillDirection.Horizontal
catLL.SortOrder = Enum.SortOrder.LayoutOrder
catLL.Padding = UDim.new(0, 4)
Instance.new("UIPadding", catScroll).PaddingLeft = UDim.new(0, 2)

local categories = {
    {name = "Hindi",    songs = HindiSongs,    color = Color3.fromRGB(220, 70, 70)},
    {name = "Bhojpuri", songs = BhojpuriSongs, color = Color3.fromRGB(200, 135, 15)},
    {name = "POPULAR",  songs = PopularSongs,  color = Color3.fromRGB(35, 120, 215)},
    {name = "All",      songs = AllSongs,      color = Color3.fromRGB(55, 55, 90)},
}

local plScrollTop = catRowY + 32
local playlistScroll = Instance.new("ScrollingFrame", PlaylistTab)
playlistScroll.Size = UDim2.new(1, 0, 1, -plScrollTop)
playlistScroll.Position = UDim2.new(0, 0, 0, plScrollTop)
playlistScroll.BackgroundTransparency = 1
playlistScroll.ScrollBarThickness = isMobile and 2 or 3
playlistScroll.ScrollBarImageColor3 = C_BORDER
playlistScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
playlistScroll.CanvasSize = UDim2.new(0,0,0,0)
playlistScroll.ZIndex = 14

local plLayout = Instance.new("UIListLayout", playlistScroll)
plLayout.SortOrder = Enum.SortOrder.LayoutOrder
plLayout.Padding = UDim.new(0, 4)
Instance.new("UIPadding", playlistScroll).PaddingTop = UDim.new(0, 2)

local function clearPlaylist()
    for _, c in pairs(playlistScroll:GetChildren()) do
        if c:IsA("UIListLayout") or c:IsA("UIPadding") then continue end
        c:Destroy()
    end
end

local function addCategoryLabel(name, color)
    local lbl = Instance.new("TextLabel", playlistScroll)
    lbl.Size = UDim2.new(1, -4, 0, 24)
    lbl.Text = "  ♪  " .. name .. " Songs"
    lbl.Font = Enum.Font.GothamBlack
    lbl.TextColor3 = color
    lbl.BackgroundColor3 = C_CARD2
    lbl.TextSize = isMobile and 10 or 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.ZIndex = 15
    corner(lbl, 7)
    local sb = Instance.new("Frame", lbl)
    sb.Size = UDim2.new(0, 3, 0.6, 0)
    sb.Position = UDim2.new(0, 2, 0.2, 0)
    sb.BackgroundColor3 = color
    sb.ZIndex = 16
    corner(sb, 2)
end

local function isInFavorites(id)
    for _, fav in pairs(favoritesList) do
        if fav[1] == id then return true end
    end
    return false
end

local currentlyPlayingRow = nil
local function addSongButton(id, name, color)
    local ROW_H = isMobile and 44 or 50

    local row = Instance.new("Frame", playlistScroll)
    row.Size = UDim2.new(1, -4, 0, ROW_H)
    row.BackgroundColor3 = C_CARD
    row.ZIndex = 15
    corner(row, 9)

    gradient(row, Color3.fromRGB(14, 18, 34), C_CARD, 90)

    -- Left accent bar
    local accent = Instance.new("Frame", row)
    accent.Size = UDim2.new(0, 3, 0.6, 0)
    accent.Position = UDim2.new(0, 3, 0.2, 0)
    accent.BackgroundColor3 = color or C_ACCENT
    accent.ZIndex = 16
    corner(accent, 2)

    -- Note icon
    local noteIcon = Instance.new("TextLabel", row)
    noteIcon.Size = UDim2.new(0, isMobile and 26 or 30, 1, 0)
    noteIcon.Position = UDim2.new(0, 10, 0, 0)
    noteIcon.Text = "♫"
    noteIcon.Font = Enum.Font.GothamBold
    noteIcon.TextSize = isMobile and 14 or 16
    noteIcon.TextColor3 = (color or C_ACCENT):Lerp(Color3.new(1,1,1), 0.25)
    noteIcon.BackgroundTransparency = 1
    noteIcon.ZIndex = 16

    -- Song name
    local nameLabel = Instance.new("TextLabel", row)
    nameLabel.Size = UDim2.new(1, isMobile and -80 or -90, 0, isMobile and 20 or 24)
    nameLabel.Position = UDim2.new(0, isMobile and 40 or 44, 0, isMobile and 5 or 7)
    nameLabel.Text = name
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = isMobile and 11 or 12
    nameLabel.TextColor3 = C_TEXT
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.ZIndex = 16

    -- Sub tag
    local catName = color == Color3.fromRGB(220,70,70) and "Hindi" or color == Color3.fromRGB(200,135,15) and "Bhojpuri" or "Popular"
    local subLabel = Instance.new("TextLabel", row)
    subLabel.Size = UDim2.new(1, isMobile and -80 or -90, 0, isMobile and 14 or 16)
    subLabel.Position = UDim2.new(0, isMobile and 40 or 44, 0, isMobile and 26 or 31)
    subLabel.Text = catName .. "  ·  tap to play"
    subLabel.Font = Enum.Font.Gotham
    subLabel.TextSize = isMobile and 8 or 9
    subLabel.TextColor3 = C_SUBTEXT
    subLabel.BackgroundTransparency = 1
    subLabel.TextXAlignment = Enum.TextXAlignment.Left
    subLabel.ZIndex = 16

    -- Star button
    local starBtn = Instance.new("TextButton", row)
    starBtn.Size = UDim2.new(0, isMobile and 24 or 28, 0, isMobile and 24 or 28)
    starBtn.Position = UDim2.new(1, isMobile and -26 or -30, 0.5, isMobile and -12 or -14)
    starBtn.Text = isInFavorites(id) and "★" or "☆"
    starBtn.Font = Enum.Font.GothamBold
    starBtn.TextSize = isMobile and 15 or 17
    starBtn.BackgroundTransparency = 1
    starBtn.TextColor3 = isInFavorites(id) and C_GOLD or C_SUBTEXT
    starBtn.ZIndex = 18
    starBtn.ClipsDescendants = false

    starBtn.MouseButton1Click:Connect(function()
        if isInFavorites(id) then
            for i, fav in ipairs(favoritesList) do
                if fav[1] == id then table.remove(favoritesList, i); break end
            end
            saveFavorites()
            starBtn.Text = "☆"; starBtn.TextColor3 = C_SUBTEXT
            notify("Removed: " .. name, Color3.fromRGB(180, 70, 70))
        else
            table.insert(favoritesList, {id, name})
            saveFavorites()
            starBtn.Text = "★"; starBtn.TextColor3 = C_GOLD
            notify("★ Saved: " .. name, C_GOLD)
        end
    end)

    local playRowBtn = Instance.new("TextButton", row)
    playRowBtn.Size = UDim2.new(1, isMobile and -30 or -34, 1, 0)
    playRowBtn.BackgroundTransparency = 1
    playRowBtn.Text = ""
    playRowBtn.ZIndex = 17

    playRowBtn.MouseButton1Click:Connect(function()
        currentSongName = name
        if playlistTarget == "Hoverboard" then
            playOnHoverboard(id, name)
        elseif playlistTarget == "Skateboard" then
            playOnSkateboard(id, name)
        elseif playlistTarget == "FEMusic" then
            playFEMusic(id, name)
        end
        updateNowPlaying()
        if currentlyPlayingRow then
            pcall(function() makeTween(currentlyPlayingRow, {BackgroundColor3 = C_CARD}, 0.18):Play() end)
        end
        currentlyPlayingRow = row
        makeTween(row, {BackgroundColor3 = Color3.fromRGB(0, 28, 55)}, 0.18):Play()
    end)
    playRowBtn.MouseEnter:Connect(function()
        if row ~= currentlyPlayingRow then
            makeTween(row, {BackgroundColor3 = Color3.fromRGB(16, 24, 46)}, 0.14):Play()
        end
    end)
    playRowBtn.MouseLeave:Connect(function()
        if row ~= currentlyPlayingRow then
            makeTween(row, {BackgroundColor3 = C_CARD}, 0.14):Play()
        end
    end)
end

local function loadCategory(cat)
    currentLoadedCategory = cat
    currentlyPlayingRow = nil
    clearPlaylist()
    if cat.name == "All" then
        for _, c in ipairs(categories) do
            if c.name ~= "All" then
                addCategoryLabel(c.name, c.color)
                local saved, unsaved = {}, {}
                for _, s in pairs(c.songs) do
                    if isInFavorites(s[1]) then table.insert(saved, s)
                    else table.insert(unsaved, s) end
                end
                for _, s in ipairs(saved) do addSongButton(s[1], s[2], c.color) end
                for _, s in ipairs(unsaved) do addSongButton(s[1], s[2], c.color) end
            end
        end
    else
        addCategoryLabel(cat.name, cat.color)
        local saved, unsaved = {}, {}
        for _, s in pairs(cat.songs) do
            if isInFavorites(s[1]) then table.insert(saved, s)
            else table.insert(unsaved, s) end
        end
        for _, s in ipairs(saved) do addSongButton(s[1], s[2], cat.color) end
        for _, s in ipairs(unsaved) do addSongButton(s[1], s[2], cat.color) end
    end
end

for i, cat in ipairs(categories) do
    local btn = Instance.new("TextButton", catScroll)
    btn.Size = UDim2.new(0, isMobile and 56 or 65, 1, -4)
    btn.LayoutOrder = i
    btn.Text = cat.name
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = isMobile and 8 or 9
    btn.BackgroundColor3 = cat.color
    btn.TextColor3 = Color3.new(1,1,1)
    btn.ZIndex = 16
    corner(btn, 7)
    btn.MouseButton1Click:Connect(function() loadCategory(cat) end)
end

loadCategory({name = "All", songs = AllSongs})

-- =========================================================
-- 🔍 TAB 3 — SEARCH TAB
-- =========================================================
local _, srchStopH = addMiniStopBar(SearchTab, 0)

local searchBox = mkTextBox(SearchTab, "Search song name...", srchStopH, INPUT_H)

local searchDisclaimer = Instance.new("TextLabel", SearchTab)
searchDisclaimer.Size = UDim2.new(1, 0, 0, 14)
searchDisclaimer.Position = UDim2.new(0, 0, 0, srchStopH + INPUT_H + 2)
searchDisclaimer.BackgroundTransparency = 1
searchDisclaimer.Text = "Results from robloxsong.com"
searchDisclaimer.TextColor3 = C_MUTED
searchDisclaimer.TextSize = isMobile and 8 or 9
searchDisclaimer.Font = Enum.Font.Gotham
searchDisclaimer.TextXAlignment = Enum.TextXAlignment.Center
searchDisclaimer.ZIndex = 14

local searchBtn = mkBtn(SearchTab, "🔍  SEARCH ONLINE", srchStopH + INPUT_H + 18, BTN_H - 4, Color3.fromRGB(0, 120, 210))

local searchList = Instance.new("ScrollingFrame", SearchTab)
searchList.Position = UDim2.new(0, 0, 0, srchStopH + INPUT_H + BTN_H + 24)
searchList.Size = UDim2.new(1, 0, 1, -(srchStopH + INPUT_H + BTN_H + 26))
searchList.AutomaticCanvasSize = Enum.AutomaticSize.Y
searchList.CanvasSize = UDim2.new(0,0,0,0)
searchList.ScrollBarThickness = isMobile and 2 or 3
searchList.ScrollBarImageColor3 = C_BORDER
searchList.BackgroundTransparency = 1
searchList.ZIndex = 14

local searchListLayout = Instance.new("UIListLayout", searchList)
searchListLayout.SortOrder = Enum.SortOrder.LayoutOrder
searchListLayout.Padding = UDim.new(0, 4)

local function searchSong(q)
    for _, c in pairs(searchList:GetChildren()) do
        if not c:IsA("UIListLayout") then c:Destroy() end
    end
    local loadingLbl = Instance.new("TextLabel", searchList)
    loadingLbl.Size = UDim2.new(1, 0, 0, 36)
    loadingLbl.Text = "🔍 Searching..."
    loadingLbl.Font = Enum.Font.GothamBold
    loadingLbl.TextSize = isMobile and 12 or 13
    loadingLbl.TextColor3 = C_MUTED
    loadingLbl.BackgroundTransparency = 1
    loadingLbl.ZIndex = 15
    task.spawn(function()
        local url = "https://robloxsong.com/search?q=" .. HttpService:UrlEncode(q)
        local ok, data = pcall(function() return game:HttpGet(url) end)
        loadingLbl:Destroy()
        if not ok then
            local errLbl = Instance.new("TextLabel", searchList)
            errLbl.Size = UDim2.new(1, 0, 0, 36)
            errLbl.Text = "Search failed. Check HttpGet permissions."
            errLbl.Font = Enum.Font.GothamBold
            errLbl.TextSize = isMobile and 11 or 12
            errLbl.TextColor3 = C_RED
            errLbl.BackgroundTransparency = 1
            errLbl.ZIndex = 15
            return
        end
        local count = 0
        for id, name in string.gmatch(data, 'song/([0-9]+)[^>]*>(.-)<') do
            name = name:gsub("<.->", ""):gsub("&amp;", "&")
            count = count + 1

            local row = Instance.new("Frame", searchList)
            row.Size = UDim2.new(1, -4, 0, isMobile and 46 or 52)
            row.BackgroundColor3 = C_CARD
            row.ZIndex = 15
            corner(row, 9)
            gradient(row, Color3.fromRGB(14, 18, 34), C_CARD, 90)

            local nameLbl = Instance.new("TextLabel", row)
            nameLbl.Size = UDim2.new(0.7, 0, 0.52, 0)
            nameLbl.Position = UDim2.new(0, 10, 0.04, 0)
            nameLbl.Text = name
            nameLbl.Font = Enum.Font.GothamBold
            nameLbl.TextSize = isMobile and 11 or 12
            nameLbl.TextColor3 = C_TEXT
            nameLbl.BackgroundTransparency = 1
            nameLbl.TextXAlignment = Enum.TextXAlignment.Left
            nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
            nameLbl.ZIndex = 16

            local idLbl = Instance.new("TextLabel", row)
            idLbl.Size = UDim2.new(0.7, 0, 0.36, 0)
            idLbl.Position = UDim2.new(0, 10, 0.56, 0)
            idLbl.Text = "ID: " .. id
            idLbl.Font = Enum.Font.Gotham
            idLbl.TextSize = isMobile and 8 or 9
            idLbl.TextColor3 = C_SUBTEXT
            idLbl.BackgroundTransparency = 1
            idLbl.TextXAlignment = Enum.TextXAlignment.Left
            idLbl.ZIndex = 16

            local playNow = Instance.new("TextButton", row)
            playNow.Size = UDim2.new(0, isMobile and 48 or 54, 0, isMobile and 26 or 30)
            playNow.Position = UDim2.new(1, isMobile and -52 or -58, 0.5, isMobile and -13 or -15)
            playNow.Text = "▶ Play"
            playNow.Font = Enum.Font.GothamBold
            playNow.TextSize = isMobile and 10 or 11
            playNow.BackgroundColor3 = Color3.fromRGB(0, 100, 200)
            playNow.TextColor3 = Color3.new(1,1,1)
            playNow.ZIndex = 16
            corner(playNow, 7)

            playNow.MouseButton1Click:Connect(function()
                pcall(function() setclipboard(id) end)
                idBox.Text = id
                currentSongName = name
                playOnHoverboard(id, name)
                updateNowPlaying()
            end)

            playNow.MouseEnter:Connect(function()
                makeTween(row, {BackgroundColor3 = Color3.fromRGB(18, 26, 52)}, 0.14):Play()
            end)
            playNow.MouseLeave:Connect(function()
                makeTween(row, {BackgroundColor3 = C_CARD}, 0.14):Play()
            end)
        end
        if count == 0 then
            local noRes = Instance.new("TextLabel", searchList)
            noRes.Size = UDim2.new(1, 0, 0, 36)
            noRes.Text = "No results found for: " .. q
            noRes.Font = Enum.Font.GothamBold
            noRes.TextSize = isMobile and 11 or 12
            noRes.TextColor3 = Color3.fromRGB(200, 90, 90)
            noRes.BackgroundTransparency = 1
            noRes.ZIndex = 15
        end
    end)
end

searchBtn.MouseButton1Click:Connect(function()
    if searchBox.Text ~= "" then searchSong(searchBox.Text) end
end)
searchBox.FocusLost:Connect(function(enter)
    if enter and searchBox.Text ~= "" then searchSong(searchBox.Text) end
end)

-- =========================================================
-- 📻 TAB 4 — FE LOCAL TAB
-- =========================================================
local _, feStopBarH = addMiniStopBar(FETab, 0)

local feScroll = Instance.new("ScrollingFrame", FETab)
feScroll.Size = UDim2.new(1, 0, 1, -feStopBarH)
feScroll.Position = UDim2.new(0, 0, 0, feStopBarH)
feScroll.BackgroundTransparency = 1
feScroll.ScrollBarThickness = isMobile and 2 or 3
feScroll.ScrollBarImageColor3 = C_GREEN
feScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
feScroll.CanvasSize = UDim2.new(0,0,0,0)
feScroll.ZIndex = 14

local fePad = Instance.new("Frame", feScroll)
fePad.Size = UDim2.new(1, 0, 0, 340)
fePad.BackgroundTransparency = 1
fePad.ZIndex = 14

local FY = 0
mkLabel(fePad, "  FE Local Sound Player", FY, LABEL_SZ, C_MUTED)
FY = FY + 15
local feBox = mkTextBox(fePad, "Enter Local Sound ID...", FY, INPUT_H)
FY = FY + INPUT_H + 6

-- Loop toggle row
local feLoopRow = Instance.new("Frame", fePad)
feLoopRow.Size = UDim2.new(1, 0, 0, 28)
feLoopRow.Position = UDim2.new(0, 0, 0, FY)
feLoopRow.BackgroundColor3 = C_CARD2
feLoopRow.ZIndex = 15
corner(feLoopRow, 8)
FY = FY + 34

local feLoopLabel = Instance.new("TextLabel", feLoopRow)
feLoopLabel.Size = UDim2.new(0.6, 0, 1, 0)
feLoopLabel.Position = UDim2.new(0, 10, 0, 0)
feLoopLabel.Text = "🔁  Loop Sound"
feLoopLabel.Font = Enum.Font.GothamBold
feLoopLabel.TextSize = isMobile and 10 or 11
feLoopLabel.TextColor3 = C_TEXT
feLoopLabel.BackgroundTransparency = 1
feLoopLabel.TextXAlignment = Enum.TextXAlignment.Left
feLoopLabel.ZIndex = 15

local feLoopOuter = Instance.new("Frame", feLoopRow)
feLoopOuter.Size = UDim2.new(0, 44, 0, 22)
feLoopOuter.Position = UDim2.new(1, -50, 0.5, -11)
feLoopOuter.BackgroundColor3 = C_GREEN
feLoopOuter.ZIndex = 15
corner(feLoopOuter, 11)

local feLoopKnob = Instance.new("Frame", feLoopOuter)
feLoopKnob.Size = UDim2.new(0, 18, 0, 18)
feLoopKnob.Position = UDim2.new(0, 24, 0.5, -9)
feLoopKnob.BackgroundColor3 = Color3.new(1,1,1)
feLoopKnob.ZIndex = 16
corner(feLoopKnob, 9)

local feLooping = true
feLoopOuter.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1
    or inp.UserInputType == Enum.UserInputType.Touch then
        feLooping = not feLooping
        feSound.Looped = feLooping
        if feLooping then
            makeTween(feLoopOuter, {BackgroundColor3 = C_GREEN}, 0.2):Play()
            makeTween(feLoopKnob, {Position = UDim2.new(0, 24, 0.5, -9)}, 0.2):Play()
        else
            makeTween(feLoopOuter, {BackgroundColor3 = Color3.fromRGB(40,42,60)}, 0.2):Play()
            makeTween(feLoopKnob, {Position = UDim2.new(0, 2, 0.5, -9)}, 0.2):Play()
        end
    end
end)

local fePBtn    = mkBtn(fePad, "▶  PLAY",          FY, BTN_H, C_GREEN)
FY = FY + BTN_H + 4
local feStopBtn = mkBtn(fePad, "⏹  STOP",          FY, BTN_H, C_RED)
FY = FY + BTN_H + 4
local fePauseBtn = mkBtn(fePad, "⏸  PAUSE / RESUME", FY, BTN_H, Color3.fromRGB(150, 90, 0))
FY = FY + BTN_H + 8

-- FE Volume slider
mkLabel(fePad, "  Local Volume", FY, LABEL_SZ, C_MUTED)
FY = FY + 15

local feVolTrack = Instance.new("Frame", fePad)
feVolTrack.Size = UDim2.new(1, -40, 0, 8)
feVolTrack.Position = UDim2.new(0, 0, 0, FY)
feVolTrack.BackgroundColor3 = Color3.fromRGB(28, 32, 52)
feVolTrack.ZIndex = 15
corner(feVolTrack, 4)

local feVolFill = Instance.new("Frame", feVolTrack)
feVolFill.Size = UDim2.new(0.7, 0, 1, 0)
feVolFill.BackgroundColor3 = C_GREEN
feVolFill.ZIndex = 16
corner(feVolFill, 4)

local feVolKnob = Instance.new("TextButton", feVolTrack)
feVolKnob.Size = UDim2.new(0, 20, 0, 20)
feVolKnob.Position = UDim2.new(0.7, -10, 0.5, -10)
feVolKnob.Text = ""
feVolKnob.BackgroundColor3 = C_GREEN
feVolKnob.ZIndex = 17
corner(feVolKnob, 10)

feSound.Volume = 0.7
local draggingFeVol = false
feVolKnob.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1
    or inp.UserInputType == Enum.UserInputType.Touch then draggingFeVol = true end
end)
feVolKnob.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1
    or inp.UserInputType == Enum.UserInputType.Touch then draggingFeVol = false end
end)
UserInputService.InputChanged:Connect(function(inp)
    if draggingFeVol and (inp.UserInputType == Enum.UserInputType.MouseMovement
    or inp.UserInputType == Enum.UserInputType.Touch) then
        local tp = feVolTrack.AbsolutePosition
        local ts = feVolTrack.AbsoluteSize
        local rel = math.clamp((inp.Position.X - tp.X) / ts.X, 0, 1)
        feVolFill.Size = UDim2.new(rel, 0, 1, 0)
        feVolKnob.Position = UDim2.new(rel, -10, 0.5, -10)
        feSound.Volume = rel
    end
end)
FY = FY + 20
fePad.Size = UDim2.new(1, 0, 0, FY + 10)

fePBtn.MouseButton1Click:Connect(function()
    if feBox.Text ~= "" then
        currentPlayMode = "FEMusic"
        feSound.SoundId = "rbxassetid://" .. feBox.Text
        feSound:Play()
        isPlaying = true
        updateNowPlaying()
        notify("🎵 FE Local: Playing", C_GREEN)
    end
end)
feStopBtn.MouseButton1Click:Connect(function()
    feSound:Stop()
    isPlaying = false
    updateNowPlaying()
    notify("⏹ FE Local: Stopped", C_RED)
end)
fePauseBtn.MouseButton1Click:Connect(function()
    if feSound.IsPlaying then
        feSound:Pause()
        notify("⏸ Paused", Color3.fromRGB(160, 120, 0))
    else
        feSound:Resume()
        notify("▶ Resumed", C_GREEN)
    end
end)

-- =========================================================
-- ⭐ TAB 5 — FAVORITES TAB
-- =========================================================
local _, favStopBarH = addMiniStopBar(FavTab, 0)

local favClearBtn = mkBtn(FavTab, "🗑  Clear All Favorites", favStopBarH, 30, Color3.fromRGB(160, 35, 35))
favClearBtn.Size = UDim2.new(1, 0, 0, 30)

local favScroll = Instance.new("ScrollingFrame", FavTab)
favScroll.Size = UDim2.new(1, 0, 1, -(favStopBarH + 34))
favScroll.Position = UDim2.new(0, 0, 0, favStopBarH + 34)
favScroll.BackgroundTransparency = 1
favScroll.ScrollBarThickness = isMobile and 2 or 3
favScroll.ScrollBarImageColor3 = C_GOLD
favScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
favScroll.CanvasSize = UDim2.new(0,0,0,0)
favScroll.ZIndex = 14

local favLayout = Instance.new("UIListLayout", favScroll)
favLayout.SortOrder = Enum.SortOrder.LayoutOrder
favLayout.Padding = UDim.new(0, 4)
Instance.new("UIPadding", favScroll).PaddingTop = UDim.new(0, 2)

local function refreshFavorites()
    for _, c in pairs(favScroll:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
    end
    if #favoritesList == 0 then
        local emptyLbl = Instance.new("TextLabel", favScroll)
        emptyLbl.Size = UDim2.new(1, 0, 0, 50)
        emptyLbl.Text = "No favorites yet!\nStar songs in the playlist to save them."
        emptyLbl.Font = Enum.Font.Gotham
        emptyLbl.TextSize = isMobile and 10 or 11
        emptyLbl.TextColor3 = C_MUTED
        emptyLbl.BackgroundTransparency = 1
        emptyLbl.TextWrapped = true
        emptyLbl.ZIndex = 15
        return
    end
    for i, fav in ipairs(favoritesList) do
        local row = Instance.new("Frame", favScroll)
        row.Size = UDim2.new(1, -4, 0, isMobile and 38 or 42)
        row.BackgroundColor3 = Color3.fromRGB(22, 20, 10)
        row.ZIndex = 15
        corner(row, 9)

        local ac2 = Instance.new("Frame", row)
        ac2.Size = UDim2.new(0, 3, 0.6, 0)
        ac2.Position = UDim2.new(0, 3, 0.2, 0)
        ac2.BackgroundColor3 = C_GOLD
        ac2.ZIndex = 16
        corner(ac2, 2)

        local sIcon = Instance.new("TextLabel", row)
        sIcon.Size = UDim2.new(0, 24, 1, 0)
        sIcon.Position = UDim2.new(0, 10, 0, 0)
        sIcon.Text = "★"
        sIcon.Font = Enum.Font.GothamBold
        sIcon.TextSize = isMobile and 13 or 15
        sIcon.TextColor3 = C_GOLD
        sIcon.BackgroundTransparency = 1
        sIcon.ZIndex = 16

        local fLbl = Instance.new("TextLabel", row)
        fLbl.Size = UDim2.new(0.5, 0, 1, 0)
        fLbl.Position = UDim2.new(0, 36, 0, 0)
        fLbl.Text = fav[2]
        fLbl.Font = Enum.Font.GothamBold
        fLbl.TextSize = isMobile and 10 or 11
        fLbl.TextColor3 = Color3.fromRGB(255, 215, 80)
        fLbl.BackgroundTransparency = 1
        fLbl.TextXAlignment = Enum.TextXAlignment.Left
        fLbl.TextTruncate = Enum.TextTruncate.AtEnd
        fLbl.ZIndex = 16

        local playFavBtn = Instance.new("TextButton", row)
        playFavBtn.Size = UDim2.new(0, isMobile and 42 or 48, 0, isMobile and 24 or 28)
        playFavBtn.Position = UDim2.new(1, isMobile and -96 or -106, 0.5, isMobile and -12 or -14)
        playFavBtn.Text = "▶ Play"
        playFavBtn.Font = Enum.Font.GothamBold
        playFavBtn.TextSize = isMobile and 9 or 10
        playFavBtn.BackgroundColor3 = Color3.fromRGB(0, 100, 200)
        playFavBtn.TextColor3 = Color3.new(1,1,1)
        playFavBtn.ZIndex = 16
        corner(playFavBtn, 6)

        local remFavBtn = Instance.new("TextButton", row)
        remFavBtn.Size = UDim2.new(0, isMobile and 42 or 48, 0, isMobile and 24 or 28)
        remFavBtn.Position = UDim2.new(1, isMobile and -48 or -52, 0.5, isMobile and -12 or -14)
        remFavBtn.Text = "✕ Del"
        remFavBtn.Font = Enum.Font.GothamBold
        remFavBtn.TextSize = isMobile and 9 or 10
        remFavBtn.BackgroundColor3 = Color3.fromRGB(170, 28, 28)
        remFavBtn.TextColor3 = Color3.new(1,1,1)
        remFavBtn.ZIndex = 16
        corner(remFavBtn, 6)

        local capturedIdx = i
        playFavBtn.MouseButton1Click:Connect(function()
            currentSongName = fav[2]
            playOnHoverboard(fav[1], fav[2])
            updateNowPlaying()
        end)
        remFavBtn.MouseButton1Click:Connect(function()
            table.remove(favoritesList, capturedIdx)
            saveFavorites()
            refreshFavorites()
            notify("Removed from Favorites", Color3.fromRGB(200, 70, 70))
        end)
    end
end

favClearBtn.MouseButton1Click:Connect(function()
    favoritesList = {}
    saveFavorites()
    refreshFavorites()
    notify("Favorites cleared", C_RED)
end)

tabButtons[5].MouseButton1Click:Connect(function() refreshFavorites() end)
refreshFavorites()

-- =========================================================
-- 🕐 TAB 6 — HISTORY TAB
-- =========================================================
local _, histStopBarH = addMiniStopBar(HistTab, 0)

local histClearBtn = mkBtn(HistTab, "🗑  Clear History", histStopBarH, 30, Color3.fromRGB(70, 35, 140))
histClearBtn.Size = UDim2.new(1, 0, 0, 30)

local histScroll = Instance.new("ScrollingFrame", HistTab)
histScroll.Size = UDim2.new(1, 0, 1, -(histStopBarH + 34))
histScroll.Position = UDim2.new(0, 0, 0, histStopBarH + 34)
histScroll.BackgroundTransparency = 1
histScroll.ScrollBarThickness = isMobile and 2 or 3
histScroll.ScrollBarImageColor3 = C_ACCENT
histScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
histScroll.CanvasSize = UDim2.new(0,0,0,0)
histScroll.ZIndex = 14

local histLayout = Instance.new("UIListLayout", histScroll)
histLayout.SortOrder = Enum.SortOrder.LayoutOrder
histLayout.Padding = UDim.new(0, 4)
Instance.new("UIPadding", histScroll).PaddingTop = UDim.new(0, 2)

local function refreshHistory()
    for _, c in pairs(histScroll:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
    end
    if #historyList == 0 then
        local emptyLbl = Instance.new("TextLabel", histScroll)
        emptyLbl.Size = UDim2.new(1, 0, 0, 50)
        emptyLbl.Text = "No history yet!\nPlay some songs first."
        emptyLbl.Font = Enum.Font.Gotham
        emptyLbl.TextSize = isMobile and 10 or 11
        emptyLbl.TextColor3 = C_MUTED
        emptyLbl.BackgroundTransparency = 1
        emptyLbl.TextWrapped = true
        emptyLbl.ZIndex = 15
        return
    end
    for i, entry in ipairs(historyList) do
        local row = Instance.new("Frame", histScroll)
        row.Size = UDim2.new(1, -4, 0, isMobile and 38 or 42)
        row.BackgroundColor3 = C_CARD
        row.ZIndex = 15
        corner(row, 9)
        gradient(row, Color3.fromRGB(13, 16, 32), C_CARD, 90)

        local ac3 = Instance.new("Frame", row)
        ac3.Size = UDim2.new(0, 3, 0.6, 0)
        ac3.Position = UDim2.new(0, 3, 0.2, 0)
        ac3.BackgroundColor3 = C_PURPLE
        ac3.ZIndex = 16
        corner(ac3, 2)

        local numLbl = Instance.new("TextLabel", row)
        numLbl.Size = UDim2.new(0, 20, 1, 0)
        numLbl.Position = UDim2.new(0, 10, 0, 0)
        numLbl.Text = tostring(i)
        numLbl.Font = Enum.Font.GothamBold
        numLbl.TextSize = 9
        numLbl.TextColor3 = C_SUBTEXT
        numLbl.BackgroundTransparency = 1
        numLbl.ZIndex = 16

        local hLbl = Instance.new("TextLabel", row)
        hLbl.Size = UDim2.new(0.56, 0, 1, 0)
        hLbl.Position = UDim2.new(0, 32, 0, 0)
        hLbl.Text = entry[2]
        hLbl.Font = Enum.Font.GothamBold
        hLbl.TextSize = isMobile and 10 or 11
        hLbl.TextColor3 = C_TEXT
        hLbl.BackgroundTransparency = 1
        hLbl.TextXAlignment = Enum.TextXAlignment.Left
        hLbl.TextTruncate = Enum.TextTruncate.AtEnd
        hLbl.ZIndex = 16

        local replayBtn = Instance.new("TextButton", row)
        replayBtn.Size = UDim2.new(0, isMobile and 52 or 60, 0, isMobile and 24 or 28)
        replayBtn.Position = UDim2.new(1, isMobile and -56 or -64, 0.5, isMobile and -12 or -14)
        replayBtn.Text = "▶ Replay"
        replayBtn.Font = Enum.Font.GothamBold
        replayBtn.TextSize = isMobile and 9 or 10
        replayBtn.BackgroundColor3 = Color3.fromRGB(0, 90, 190)
        replayBtn.TextColor3 = Color3.new(1,1,1)
        replayBtn.ZIndex = 16
        corner(replayBtn, 6)

        replayBtn.MouseButton1Click:Connect(function()
            currentSongName = entry[2]
            playOnHoverboard(entry[1], entry[2])
            updateNowPlaying()
        end)
    end
end

histClearBtn.MouseButton1Click:Connect(function()
    historyList = {}
    refreshHistory()
    notify("History cleared", C_PURPLE)
end)
tabButtons[6].MouseButton1Click:Connect(function() refreshHistory() end)
refreshHistory()

-- Wire up Now Playing stop button
npStopBtn.MouseButton1Click:Connect(function()
    stopMusic()
    feSound:Stop()
    isPlaying = false
    updateNowPlaying()
end)

-- =========================================================
-- 🌈 RGB LOOP (unchanged)
-- =========================================================
task.spawn(function()
    while true do
        if rgbEnabled then
            local hue = tick() % 5 / 5
            local color = Color3.fromHSV(hue, 1, 1)
            pcall(function() colorRemote:FireServer("NoMotorColor", color) end)
            panelStroke.Color = color
            toggleStroke.Color = color
            task.wait(0.1)
        else
            panelStroke.Color = C_BORDER
            toggleStroke.Color = C_ACCENT
            task.wait(1)
        end
    end
end)

-- =========================================================
-- 🔗 PANEL TOGGLE / CLOSE / MINIMIZE LOGIC
-- =========================================================
local panelVisible = false

toggle.MouseButton1Click:Connect(function()
    panelVisible = not panelVisible
    if panelVisible then
        panel.Visible = true
        panelShadow.Visible = true
        makeTween(panelScale, {Scale = 1}, 0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out):Play()
        task.delay(0.05, function()
            setTab(currentTabIndex)
            playlistScroll.CanvasPosition = playlistScrollPos
        end)
    else
        playlistScrollPos = playlistScroll.CanvasPosition
        makeTween(panelScale, {Scale = 0}, 0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In):Play()
        task.delay(0.24, function()
            panel.Visible = false
            panelShadow.Visible = false
        end)
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    panelVisible = false
    playlistScrollPos = playlistScroll.CanvasPosition
    makeTween(panelScale, {Scale = 0}, 0.22):Play()
    task.delay(0.24, function()
        panel.Visible = false
        panelShadow.Visible = false
    end)
end)

minBtn.MouseButton1Click:Connect(function()
    panelVisible = false
    playlistScrollPos = playlistScroll.CanvasPosition
    makeTween(panelScale, {Scale = 0}, 0.22):Play()
    task.delay(0.24, function()
        panel.Visible = false
        panelShadow.Visible = false
    end)
    notify("ARES minimized — tap toggle to reopen", C_ACCENT)
end)

-- =========================================================
-- 📛 AUTO RP NAME & SMOOTH RGB (unchanged)
-- =========================================================
task.spawn(function()
    local rpTextRemote  = RS:WaitForChild("RE"):WaitForChild("1RPNam1eTex1t")
    local rpColorRemote = RS:WaitForChild("RE"):WaitForChild("1RPNam1eColo1r")

    local nameArgs = {
        "RolePlayName",
        "\240\159\142\167\226\146\182\226\147\135\226\146\186\226\147\136 \226\147\130\226\147\138\226\147\136\226\146\190\226\146\184 \226\146\189\226\147\138\226\146\183\240\159\142\167"
    }
    pcall(function()
        rpTextRemote:FireServer(unpack(nameArgs))
    end)

    while true do
        local hue = tick() % 4 / 4
        local rgbColor = Color3.fromHSV(hue, 1, 1)
        local colorArgs = {"PickingRPNameColor", rgbColor}
        pcall(function()
            rpColorRemote:FireServer(unpack(colorArgs))
        end)
        task.wait(0.1)
    end
end)

-- =========================================================
-- 🎬 STARTUP
-- =========================================================
setTab(1)
updateNowPlaying()

task.delay(0.5, function()
    if fetchSuccess then
        notify("🔱 ARES MUSIC HUB v5.0 — LOADED!", C_ACCENT)
    else
        notify("🔱 ARES v5.0 — Playlist fetch failed! Check URL.", C_ORANGE)
    end
end)

print("✅ ARES MUSIC HUB v5.0 — ULTRA PREMIUM EDITION LOADED")
print("🌐 Playlist fetched from GitHub: " .. tostring(fetchSuccess))
print("🎵 Hindi: " .. #HindiSongs .. " | Bhojpuri: " .. #BhojpuriSongs .. " | POPULAR: " .. #PopularSongs)
print("📊 Total Songs: " .. #AllSongs)
print("📱 Mobile mode: " .. tostring(isMobile) .. " | Screen: " .. tostring(screenSize.X) .. "x" .. tostring(screenSize.Y))
print("💾 Favorites loaded: " .. #favoritesList .. " saved songs")
print("🆕 Smart Stop: Hoverboard/Skateboard → DeleteNoMotorVehicle | FE → feSound:Stop")
print("⏹ Mini Stop bar on every tab | ⏹ Stop button in Now Playing bar")
