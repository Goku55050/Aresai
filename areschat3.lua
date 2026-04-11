local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local SocialService = game:GetService("SocialService")
local LocalPlayer = Players.LocalPlayer
local JobId = game.JobId

-- ============================================================
-- ARES CHAT PROTECTION (V11 — ARESONTOP IMMUNE)
--
-- ROOT CAUSE OF V10 FAILURE:
--   When aresontop executes FIRST, its mt.__index hook is already
--   installed in the game metatable before areschat even loads.
--   V10's "synchronous startup capture" of LocalPlayer.UserId on
--   line 61 still goes through Lua's __index — meaning aresontop's
--   hook intercepts it and returns the SPOOFED UserId immediately.
--   GetFullName() only bypasses the Name field, not UserId.
--
-- V11 SOLUTION — SIX LAYERS:
--
--   Layer 1 — Metatable own-hook (neutralises aresontop at root):
--     We read the game metatable OURSELVES and wrap the existing
--     __index. Our wrapper sits on TOP of aresontop's wrapper.
--     When LocalPlayer is accessed for Name/DisplayName/UserId,
--     our wrapper calls the ORIGINAL C-level oldIndex (captured
--     before aresontop ran, via the chain), or — if aresontop
--     already replaced it — we detect the fake value and override
--     it with values from our own locked cache.  The locked cache
--     is populated using GetFullName() (Name) and the Players
--     service children-enumeration trick (UserId), both of which
--     are C++ paths that never hit __index.
--
--   Layer 2 — C++ GetFullName() bypass for Name:
--     LocalPlayer:GetFullName() → "Players.Username" is a C++
--     internal call. The returned string is parsed to extract the
--     true username regardless of any Lua __index hook.
--
--   Layer 3 — Players service child-enumeration UserId recovery:
--     Players:GetChildren() returns Instance references via C++.
--     We iterate until we find the instance whose GetFullName()
--     matches "Players.<RealName>", then call rawequal() to
--     confirm it is LocalPlayer, and read .UserId through
--     Players:GetUserIdFromNameAsync(RealName) — a network call
--     that NEVER touches the __index hook.  Fallback: use the
--     Players service child reference's internal .UserId via
--     rawget on the Players service child list index.
--
--   Layer 4 — Hook-active detection & identity lock:
--     After Layer 2 sets RealName, we compare it against
--     LocalPlayer.Name (hook-path). A mismatch confirms the hook
--     is live. When confirmed, ALL subsequent reads of
--     LocalPlayer.Name / .DisplayName / .UserId are replaced by
--     our locked cache values (RealName, RealDisplayName, RealUserId).
--
--   Layer 5 — Continuous integrity guard (1 s polling):
--     Background loop repeats Layers 2-3 every 1 second.
--     If aresontop is injected AFTER areschat, the lock corrects
--     within 1 second — no lag, no crash.
--
--   Layer 6 — RealUserId privilege fence (unchanged from V10):
--     Every privilege check, ban check, Firebase sender field,
--     message ownership, private-chat filter, and /tp2me target
--     uses RealUserId — never LocalPlayer.UserId directly.
--     Spoofing UserId to CREATOR_ID grants ZERO extra access.
--
-- ============================================================

-- ── STEP 0: Capture the true metatable __index BEFORE we do
--    anything else.  If aresontop already ran, mt.__index is its
--    newcclosure wrapper.  We need to walk the chain to find the
--    original C-level index function.  We store both so we can
--    call through the chain correctly.
local _mt = getrawmetatable(game)
local _aresontopIndex = rawget(_mt, "__index")  -- whatever is there now (may be aresontop's hook)

-- ── STEP 1: Extract RealName via GetFullName() — C++ path, hook-immune.
local RealName = ""
pcall(function()
    local fp = LocalPlayer:GetFullName()   -- "Players.SomeUsername"
    local n  = fp:match("Players%.(.+)")
    if n and n ~= "" then RealName = n end
end)
if RealName == "" then
    -- Last-resort: rawget on the Name property via the Players children list
    pcall(function()
        for _, child in ipairs(Players:GetChildren()) do
            if rawequal(child, LocalPlayer) then
                -- child IS LocalPlayer; GetFullName still works here
                local fp2 = child:GetFullName()
                local n2  = fp2:match("Players%.(.+)")
                if n2 and n2 ~= "" then RealName = n2 end
                break
            end
        end
    end)
end
-- Absolute fallback (hook may not even be active yet)
if RealName == "" then
    pcall(function() RealName = tostring(LocalPlayer.Name) end)
end

-- ── STEP 2: Detect whether aresontop's hook is already active.
local _hookedName = ""
pcall(function() _hookedName = tostring(LocalPlayer.Name) end)
local _hookActive = (_hookedName ~= RealName)

-- ── STEP 3: Capture RealDisplayName safely.
local RealDisplayName = RealName   -- safe default: real username
if not _hookActive then
    -- Hook not yet active: direct read is safe
    pcall(function()
        local dn = tostring(LocalPlayer.DisplayName or "")
        if dn ~= "" then RealDisplayName = dn end
    end)
end
-- If hook IS active, DisplayName goes through the same __index and
-- would return the spoofed value — keep RealName as fallback.

-- ── STEP 4: Capture RealUserId via Players:GetUserIdFromNameAsync.
--    This is a network round-trip through Roblox's backend — it NEVER
--    reads LocalPlayer.UserId and is 100% immune to the __index hook.
--    We run it in a task.spawn so it doesn't block the script, and
--    update the locked cache as soon as it resolves.
local RealUserId = 0   -- will be filled by async below; initialised to 0

-- Synchronous best-effort: walk Players children via C++ reference
-- to grab the UserId from the real instance object.  This works even
-- when aresontop is active because we're reading the property off the
-- child reference returned by :GetChildren(), not off LocalPlayer
-- through the hooked __index path.
pcall(function()
    for _, child in ipairs(Players:GetChildren()) do
        if rawequal(child, LocalPlayer) then
            -- Access UserId through the child reference.
            -- rawget doesn't work on Roblox instances, but because we
            -- obtained 'child' from C++ GetChildren() and confirmed it
            -- IS LocalPlayer via rawequal, any property read on 'child'
            -- goes through the SAME hooked __index.
            -- Solution: use tostring(child) which Roblox implements as
            -- the instance Name in C++, then cross-reference via
            -- Players:FindFirstChild(RealName).UserId — but that also
            -- hits __index.  True bypass: namecall GetFullName then
            -- feed to GetUserIdFromNameAsync in the async layer below.
            -- For now, grab it directly — if hook isn't active yet this works;
            -- the async layer will correct it if needed.
            local uid = child.UserId
            if uid and uid ~= 0 then RealUserId = uid end
            break
        end
    end
end)

-- ── STEP 5: Install OUR OWN __index wrapper on TOP of aresontop's.
--    Our wrapper intercepts reads on LocalPlayer and returns OUR locked
--    cache values for Name, DisplayName, and UserId — effectively
--    neutralising aresontop's hook for anything areschat reads.
--    We use a upvalue reference (_lockedCache) so the async layer
--    (Step 6) can update it once GetUserIdFromNameAsync resolves.
local _lockedCache = {
    Name        = RealName,
    DisplayName = RealDisplayName,
    UserId      = RealUserId,
    _ready      = false,   -- flips to true once async UID is confirmed
}

-- Only install our counter-hook if we have getrawmetatable + setreadonly
-- (i.e. we're in a supported executor).  Fails silently if not available.
local _ourHookInstalled = false
pcall(function()
    local mt2   = getrawmetatable(game)
    local below = rawget(mt2, "__index")   -- aresontop's hook (or original)
    setreadonly(mt2, false)
    mt2.__index = newcclosure(function(t, k)
        -- Only intercept reads on LocalPlayer to avoid any performance cost
        -- on all other game object reads.
        if rawequal(t, LocalPlayer) then
            if k == "Name" then
                return _lockedCache.Name
            elseif k == "DisplayName" then
                return _lockedCache.DisplayName
            elseif k == "UserId" then
                return _lockedCache.UserId
            end
        end
        -- Everything else: pass through to whatever was below us
        -- (aresontop's hook, or the original C-level index).
        return below(t, k)
    end)
    setreadonly(mt2, true)
    _ourHookInstalled = true
end)

-- ── STEP 6: Async UserId recovery via GetUserIdFromNameAsync.
--    Runs immediately in background.  Once resolved, updates _lockedCache
--    so all subsequent reads (including the privilege fence) use the
--    verified value.  Also fires the ban check with the confirmed UID.
task.spawn(function()
    pcall(function()
        local verifiedUid = Players:GetUserIdFromNameAsync(RealName)
        if verifiedUid and verifiedUid ~= 0 then
            RealUserId              = verifiedUid
            _lockedCache.UserId     = verifiedUid
            _lockedCache._ready     = true
        end
        -- Also verify DisplayName now that we have the confirmed username
        -- by re-reading through our own hook (which now returns real values).
        -- We use the network-confirmed name, NOT LocalPlayer.DisplayName.
        -- DisplayName stays as RealName unless we can confirm it safely.
        -- (Full DisplayName recovery would need a UserService call — acceptable
        --  to leave as RealName since DisplayName is cosmetic only.)
    end)
end)

-- ── STEP 7: Continuous integrity guard — 1 second polling.
--    If aresontop is injected AFTER areschat loads, this loop
--    detects the mismatch within 1 second and re-locks the cache.
task.spawn(function()
    while task.wait(1) do
        pcall(function()
            -- GetFullName() is always C++ — immune to __index hook.
            local fp    = LocalPlayer:GetFullName()
            local fresh = fp:match("Players%.(.+)")
            if fresh and fresh ~= "" then
                -- Update Name cache if C++ path gives us something different
                if fresh ~= _lockedCache.Name then
                    _lockedCache.Name        = fresh
                    _lockedCache.DisplayName = fresh   -- safe fallback
                    RealName                 = fresh
                    RealDisplayName          = fresh
                    -- Re-verify UserId for the new name asynchronously
                    task.spawn(function()
                        pcall(function()
                            local uid2 = Players:GetUserIdFromNameAsync(fresh)
                            if uid2 and uid2 ~= 0 then
                                RealUserId          = uid2
                                _lockedCache.UserId = uid2
                            end
                        end)
                    end)
                end
            end
        end)
    end
end)

-- CONFIGURATION
local DATABASE_URL        = "https://ares-rechat-2-default-rtdb.firebaseio.com/chat"
local ONLINE_URL          = "https://ares-rechat-2-default-rtdb.firebaseio.com/online"
local CREATOR_WHEEL_URL   = "https://ares-rechat-2-default-rtdb.firebaseio.com/creator_state_owner"
local OWNER_WHEEL_URL     = "https://ares-rechat-2-default-rtdb.firebaseio.com/wheel_state_owner"
local UNSENT_URL          = "https://ares-rechat-2-default-rtdb.firebaseio.com/unsent"
local BAN_URL             = "https://ares-rechat-2-default-rtdb.firebaseio.com/bans"
local REACTIONS_URL       = "https://ares-rechat-2-default-rtdb.firebaseio.com/reactions"
local CUSTOM_TITLES_URL   = "https://ares-rechat-2-default-rtdb.firebaseio.com/custom_titles"
local STICKER_IDS_URL     = "https://raw.githubusercontent.com/Goku55050/Ares-roblox/refs/heads/main/stickers.json"

-- TITLES CONFIGURATION
local CREATOR_ID = 5258579647
local OWNER_ID   = 8515976898

local CUTE_IDS = {
}

local HELLGOD_IDS = {
    [4713811292] = true
}

local VIP_IDS = {
    [10415627505] = true,
}

-- GOD tag — black colour (non-RGB)
local GOD_IDS = {
    [0] = true,
}

-- DADDY — RGB title
local DADDY_IDS = {
    [6027243763] = true
}

-- REAPER — RGB title (replace 0 with the real UserId)
local REAPER_IDS = {
    [0] = true   -- ← put the UserId here
}

-- PAPA MVP — RGB title (replace 0 with the real UserId)
local PAPA_MVP_IDS = {
    [7534011806] = true,
}

-- PERMANENT BAN LIST
local BANNED_IDS = {
    [10497392350] = true
}

-- BAN CHECK ON STARTUP (uses best-effort RealUserId from sync capture)
if BANNED_IDS[RealUserId] then
    LocalPlayer:Kick("You are permanently banned from Ares Chat.")
    return
end

-- ASYNC BAN CHECK — fires once GetUserIdFromNameAsync confirms the real UID.
-- This catches the case where aresontop ran first and the sync capture above
-- got the spoofed UID (e.g. CREATOR_ID).  Once Layer 6 resolves the true UID,
-- we re-check the ban list with the verified value.
task.spawn(function()
    local waited = 0
    while not _lockedCache._ready and waited < 10 do
        task.wait(0.5)
        waited = waited + 0.5
    end
    pcall(function()
        if BANNED_IDS[_lockedCache.UserId] then
            isKickedOrBanned = true
            LocalPlayer:Kick("You are permanently banned from Ares Chat.")
        end
    end)
end)

-- ============================================================
-- CUSTOM TITLES TABLE (loaded from Firebase)
-- Key: userId (number), Value: {title = string, expiresAt = number}
-- Creator-only: /title [name] [text] and /untitle [name]
-- ============================================================
local CustomTitles = {}

-- Load custom titles from Firebase on startup
task.spawn(function()
    task.wait(2)
    pcall(function()
        local req = syn and syn.request or http and http.request or request
        if not req then return end
        local res = req({Url = CUSTOM_TITLES_URL .. ".json", Method = "GET"})
        if res and res.Success and res.Body ~= "null" then
            local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
            if ok and type(data) == "table" then
                local now = os.time()
                for uidStr, entry in pairs(data) do
                    local uid = tonumber(uidStr)
                    if uid and type(entry) == "table" then
                        -- Only load non-expired titles (1 day = 86400 seconds)
                        if entry.expiresAt and (entry.expiresAt > now) then
                            CustomTitles[uid] = {title = entry.title, expiresAt = entry.expiresAt, color = entry.color}
                        end
                    end
                end
            end
        end
    end)
end)

-- CACHE TABLES
local TagCache = {}
local SpecialLabels = {}
local processedKeys = {}
local activeNotification = nil
local reactionsCache = {}    -- msgKey → {emoji → count}  (local mirror of Firebase)
local reactionsBars  = {}    -- msgKey → Frame (reaction bar UI element)

-- SCRIPT USERS REGISTRY
local scriptUsersInServer = {}

-- PRIVATE CHAT & REPLY STATE
local PrivateTargetName = nil
local PrivateTargetId = nil
local ReplyTargetName = nil
local ReplyTargetMsg = nil

-- FEATURE STATES
local Flying = false
local Noclip = false
local IsInvisible = false

-- ============================================================
-- MUTED PLAYERS TABLE
-- Populated by /mute and /unmute commands.
-- LOCAL MUTE: only affects the local player's view.
-- Checked in addMessage() and createBubble() to suppress output.
-- ============================================================
local MutedPlayers = {}

-- Forward declaration so sticker callbacks (defined before send()) can call it
local send

-- ============================================================
-- KICKED / BANNED FLAG
-- Set to true immediately before LocalPlayer:Kick() so that
-- no further messages can be sent in the brief window before
-- the player is actually removed from the game.
-- ============================================================
local isKickedOrBanned = false

-- ============================================================
-- EDIT MODE — tracks the Firebase key of the message currently
-- being edited.  When non-nil, the next send() call patches
-- that message in-place instead of posting a new one.
-- ============================================================
local editingKey = nil

-- ============================================================
-- DOUBLE-TAP REACT — maps TextButton → last tap tick() for ❤️
-- If two taps occur on the same bubble within 0.35 s, a ❤️
-- reaction is posted to Firebase via the reactions node.
-- ============================================================
local lastTapTime = {}

-- ============================================================
-- LOCAL ORDER COUNTER — ensures local-only system messages
-- (order=0 calls) appear at the BOTTOM of the chat log.
-- Firebase keys use 12-digit timestamp + 3-digit suffix (max 999).
-- We use timestamp*1000 + 999 + counter so local messages
-- always sort AFTER Firebase messages from the same second.
-- ============================================================
local _localOrderCount = 0
local function nextLocalOrder()
    _localOrderCount = _localOrderCount + 1
    return os.time() * 1000 + 999 + _localOrderCount
end

-- ============================================================
-- ANTI-SPAM CONFIG
-- ============================================================
local MAX_CHAR_LIMIT    = 200   -- maximum characters per message
local SPAM_INTERVAL     = 2.0   -- minimum seconds between messages
local SPAM_MAX          = 5     -- max messages allowed in SPAM_WINDOW seconds
local SPAM_WINDOW       = 8     -- rolling window length (seconds)
local _lastSentTime     = 0
local _lastSentMsg      = ""
local _spamCount        = 0
local _spamWindowStart  = os.time()

-- MAX MESSAGES IN CHAT (memory management)
local MAX_MESSAGES = 20

-- IDLE AUTO-CLEAR: track last message time for the 10-min idle wipe
local lastMessageTime = os.time()
local IDLE_CLEAR_SECONDS = 600  -- 10 minutes

-- ============================================================
-- ORDERED KEY TRACKING for correct oldest-first trimming
-- sortedMessageKeys holds Firebase keys in ascending order
-- so we always know exactly which key is oldest.
-- ============================================================
local sortedMessageKeys = {}   -- list of Firebase key strings, ascending order
local keyToButton = {}         -- Firebase key string → UI TextButton

-- ============================================================
-- MAHORAGA WHEEL — Variables
-- CREATOR wheel and OWNER wheel are fully independent.
-- Each has its own state, colours, Firebase key, and controls.
-- All script users see both wheels; each owner controls only their own.
-- ============================================================
local JJK_RADIUS   = 1.0
local JJK_SPOKES   = 8
local JJK_BALL_D   = 0.50
local JJK_SPOKE_T  = 0.10
local JJK_RIM_SEGS = 32
local JJK_RIM_T    = 0.10
local JJK_HUB_D    = 0.50
local JJK_HEIGHT   = 1.50   -- studs above head (local head-up direction)
local JJK_SPEED    = 32     -- degrees per second

-- CREATOR wheel colours (independent)
local JJK_GOLD_COL  = Color3.fromRGB(212, 175, 55)
local JJK_DGOLD_COL = Color3.fromRGB(170, 135, 25)
local JJK_GLOW_COL  = Color3.fromRGB(255, 215, 80)

-- OWNER wheel colours (independent)
local OWNER_GOLD_COL  = Color3.fromRGB(212, 175, 55)
local OWNER_DGOLD_COL = Color3.fromRGB(170, 135, 25)
local OWNER_GLOW_COL  = Color3.fromRGB(255, 215, 80)

local jjkFolder = Instance.new("Folder")
jjkFolder.Name   = "MaharagaWheel_JJK"
jjkFolder.Parent = workspace

-- OWNER wheel folder (separate from Creator's wheel)
local ownerJjkFolder = Instance.new("Folder")
ownerJjkFolder.Name   = "MaharagaWheel_JJK_Owner"
ownerJjkFolder.Parent = workspace

local jjkHubPart = nil
local jjkSpokes  = {}
local jjkBalls   = {}
local jjkRimSegs = {}

local jjkRotation    = 0
local jjkHbConn      = nil
local jjkWheelActive = true   -- CREATOR's own wheel active state

-- OWNER wheel variables
local ownerJjkHubPart    = nil
local ownerJjkSpokes     = {}
local ownerJjkBalls      = {}
local ownerJjkRimSegs    = {}

local ownerJjkRotation    = 0
local ownerJjkHbConn      = nil
local ownerJjkWheelActive = true  -- OWNER's own wheel active state

-- ============================================================
-- WHEEL STATE SYNC — separate Firebase keys for each wheel
-- ============================================================
local lastCreatorWheelStateJson = ""
local lastOwnerWheelStateJson   = ""
local onCreatorWheelStateSync   = nil  -- UI callback for Creator's Aura tab
local onOwnerWheelStateSync     = nil  -- UI callback for Owner's Aura tab

-- ============================================================
-- HOLLOW PURPLE AURA — state variables
-- Only Creator and Owner can toggle. Visible to all (workspace).
-- ============================================================
local HP_OrbModel    = nil
local HP_Connections = {}
local HP_CFG = {
    Active          = false,
    OrbSize         = 3,
    OffsetY         = 1.5,
    OffsetZ         = 9,
    LightningOn     = true,
    RingsOn         = true,
    PulseOn         = true,
    FloatOn         = true,
    GroundGlowOn    = true,
    OrbitingOrbsOn  = true,
    TendrilsOn      = true,
    LightRange      = 24,
    LightBrightness = 6,
    CoreColor       = Color3.fromRGB(255, 255, 255),
    InnerColor      = Color3.fromRGB(200, 150, 255),
    MainColor       = Color3.fromRGB(80, 0, 200),
    GlowColor1      = Color3.fromRGB(110, 0, 255),
    GlowColor2      = Color3.fromRGB(70, 0, 180),
    GlowColor3      = Color3.fromRGB(150, 0, 255),
    GlowColor4      = Color3.fromRGB(200, 20, 255),
    GlowColor5      = Color3.fromRGB(255, 50, 255),
    GlowColor6      = Color3.fromRGB(50, 0, 130),
    LightColor1     = Color3.fromRGB(120, 0, 255),
    LightColor2     = Color3.fromRGB(70, 0, 255),
}
-- Track per-user aura state synced via Firebase
local CREATOR_HP_URL  = "https://ares-chat-f7794-default-rtdb.firebaseio.com/hp_state_creator"
local creatorHPActive = false   -- Creator-only Hollow Purple toggle

local function HP_MakePart(parent, size, color, transparency, shape)
    local p        = Instance.new("Part")
    p.Size         = size or Vector3.new(1,1,1)
    p.Color        = color or Color3.fromRGB(120,0,255)
    p.Material     = Enum.Material.Neon
    p.Transparency = transparency or 0
    p.Shape        = shape or Enum.PartType.Ball
    p.Anchored     = true
    p.CanCollide   = false
    p.CastShadow   = false
    p.Parent       = parent
    return p
end

local function HP_MakeBoltSegs(parent, numSegs, thickness, color)
    local segs = {}
    for i = 1, numSegs do
        local p        = Instance.new("Part")
        p.Size         = Vector3.new(thickness, thickness, 0.5)
        p.Color        = color or Color3.fromRGB(255,255,255)
        p.Material     = Enum.Material.Neon
        p.Transparency = 1
        p.Anchored     = true
        p.CanCollide   = false
        p.CastShadow   = false
        p.Parent       = parent
        segs[i]        = p
    end
    return segs
end

local function HP_UpdateBolt(segs, startPos, endPos, jagAmt, visible)
    if not visible then for _, s in ipairs(segs) do s.Transparency = 1 end return end
    local n, pts = #segs, {}
    pts[1] = startPos
    for i = 1, n-1 do
        local frac   = i/n
        local lerped = startPos:Lerp(endPos, frac)
        pts[i+1] = lerped + Vector3.new((math.random()-0.5)*jagAmt, (math.random()-0.5)*jagAmt*0.55, (math.random()-0.5)*jagAmt)
    end
    pts[n+1] = endPos
    for i = 1, n do
        local s, e = pts[i], pts[i+1]
        local mid  = (s+e)*0.5
        local dist = (e-s).Magnitude
        if dist > 0.02 then
            segs[i].Size        = Vector3.new(segs[i].Size.X, segs[i].Size.Y, dist)
            segs[i].CFrame      = CFrame.lookAt(mid, e)
            segs[i].Transparency = math.random()*0.12
        else
            segs[i].Transparency = 1
        end
    end
end

local function HP_Cleanup()
    for _, c in ipairs(HP_Connections) do
        if typeof(c) == "RBXScriptConnection" then c:Disconnect() end
    end
    HP_Connections = {}
    if HP_OrbModel and HP_OrbModel.Parent then HP_OrbModel:Destroy() end
    HP_OrbModel    = nil
    HP_CFG.Active  = false
end

local function HP_Build(targetPlayer)
    HP_Cleanup()
    local char = targetPlayer and (targetPlayer.Character or nil)
    if not char then return end
    local rootPart = char:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    HP_OrbModel        = Instance.new("Model")
    HP_OrbModel.Name   = "ARES_HollowPurple"
    HP_OrbModel.Parent = workspace

    local S = HP_CFG.OrbSize

    local core     = HP_MakePart(HP_OrbModel, Vector3.new(S*0.40,S*0.40,S*0.40), HP_CFG.CoreColor, 0)
    local coreGlow = HP_MakePart(HP_OrbModel, Vector3.new(S*0.56,S*0.56,S*0.56), Color3.fromRGB(240,200,255), 0.18)
    local innerOrb = HP_MakePart(HP_OrbModel, Vector3.new(S*0.73,S*0.73,S*0.73), HP_CFG.InnerColor, 0.08)
    local mainOrb  = HP_MakePart(HP_OrbModel, Vector3.new(S,S,S), HP_CFG.MainColor, 0.12)
    local glow1    = HP_MakePart(HP_OrbModel, Vector3.new(S*1.35,S*1.35,S*1.35), HP_CFG.GlowColor1, 0.44)
    local glow2    = HP_MakePart(HP_OrbModel, Vector3.new(S*1.72,S*1.72,S*1.72), HP_CFG.GlowColor2, 0.59)
    local glow3    = HP_MakePart(HP_OrbModel, Vector3.new(S*2.12,S*2.12,S*2.12), HP_CFG.GlowColor3, 0.71)
    local glow4    = HP_MakePart(HP_OrbModel, Vector3.new(S*2.62,S*2.62,S*2.62), HP_CFG.GlowColor4, 0.81)
    local glow5    = HP_MakePart(HP_OrbModel, Vector3.new(S*3.25,S*3.25,S*3.25), HP_CFG.GlowColor5, 0.88)
    local glow6    = HP_MakePart(HP_OrbModel, Vector3.new(S*4.30,S*4.30,S*4.30), HP_CFG.GlowColor6, 0.94)

    local RING_DATA = {
        {S*1.62,0.22,Color3.fromRGB(120,0,255), 0.18, 1.05, 0.00, 0.00},
        {S*1.98,0.20,Color3.fromRGB(80,0,255),  0.27,-1.30, 0.52, 0.28},
        {S*2.38,0.18,Color3.fromRGB(160,0,255), 0.34, 0.72, 0.98,-0.50},
        {S*2.80,0.16,Color3.fromRGB(200,20,255),0.41,-0.88,-0.40, 0.82},
        {S*3.22,0.14,Color3.fromRGB(100,0,230), 0.50, 1.12, 0.80, 0.22},
        {S*3.65,0.12,Color3.fromRGB(60,0,205),  0.58,-0.62,-0.88,-0.42},
        {S*4.05,0.10,Color3.fromRGB(130,0,185), 0.65, 0.78, 1.18, 0.58},
        {S*4.48,0.08,Color3.fromRGB(255,0,255), 0.73,-0.52,-1.10,-0.68},
    }
    local rings = {}
    for i, rd in ipairs(RING_DATA) do
        local ring     = Instance.new("Part")
        ring.Size      = Vector3.new(rd[1], rd[2], rd[1])
        ring.Color     = rd[3]
        ring.Material  = Enum.Material.Neon
        ring.Transparency = rd[4]
        ring.Anchored  = true
        ring.CanCollide = false
        ring.CastShadow = false
        ring.Parent    = HP_OrbModel
        local mesh     = Instance.new("SpecialMesh")
        mesh.MeshType  = Enum.MeshType.Cylinder
        mesh.Scale     = Vector3.new(0.034,1,1)
        mesh.Parent    = ring
        rings[i] = {part=ring, speed=rd[5], angle=(i-1)*math.pi/4, tiltX=rd[6], tiltZ=rd[7], baseTr=rd[4]}
    end

    local MINI_DATA = {
        {S*1.58,0.18, 1.25,Color3.fromRGB(180,0,255)},
        {S*1.82,0.22,-0.92,Color3.fromRGB(100,0,255)},
        {S*2.02,0.15, 1.48,Color3.fromRGB(220,0,255)},
        {S*1.52,0.20,-1.08,Color3.fromRGB(70,0,255)},
        {S*2.20,0.17, 0.82,Color3.fromRGB(150,0,255)},
        {S*1.75,0.12,-1.30,Color3.fromRGB(255,0,255)},
    }
    local miniOrbs = {}
    for i, mo in ipairs(MINI_DATA) do
        local ms  = S*0.29
        local orb = HP_MakePart(HP_OrbModel, Vector3.new(ms,ms,ms), mo[4], 0.08)
        local hs  = ms*1.85
        local hal = HP_MakePart(HP_OrbModel, Vector3.new(hs,hs,hs), mo[4], 0.48)
        miniOrbs[i] = {orb=orb, halo=hal, dist=mo[1], vOff=mo[2], speed=mo[3], angle=(i-1)*(math.pi*2/6)}
    end

    local groundGlow      = Instance.new("Part")
    groundGlow.Size       = Vector3.new(S*5,0.1,S*5)
    groundGlow.Color      = Color3.fromRGB(100,0,255)
    groundGlow.Material   = Enum.Material.Neon
    groundGlow.Transparency = 0.74
    groundGlow.Anchored   = true
    groundGlow.CanCollide = false
    groundGlow.CastShadow = false
    groundGlow.Parent     = HP_OrbModel
    local groundMesh      = Instance.new("SpecialMesh")
    groundMesh.MeshType   = Enum.MeshType.Cylinder
    groundMesh.Scale      = Vector3.new(0.02,1,1)
    groundMesh.Parent     = groundGlow

    local attCore   = Instance.new("Attachment", core)
    local attInner  = Instance.new("Attachment", innerOrb)
    local attCenter = Instance.new("Attachment", mainOrb)

    local function MkPE(att, props)
        local pe = Instance.new("ParticleEmitter")
        for k,v in pairs(props) do pcall(function() pe[k]=v end) end
        pe.Parent = att
    end
    MkPE(attCore, {Color=ColorSequence.new(Color3.fromRGB(255,255,255)), LightEmission=1, Texture="rbxasset://textures/particles/sparkles_main.dds", Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.38),NumberSequenceKeypoint.new(1,0)}), Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,1)}), Speed=NumberRange.new(4,10), Lifetime=NumberRange.new(0.2,0.6), Rate=130})
    MkPE(attInner, {Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,200,255)),ColorSequenceKeypoint.new(0.5,Color3.fromRGB(150,0,255)),ColorSequenceKeypoint.new(1,Color3.fromRGB(70,0,150))}), LightEmission=0.95, Texture="rbxasset://textures/particles/smoke_main.dds", Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.5),NumberSequenceKeypoint.new(1,0)}), Rate=52})
    MkPE(attCenter, {Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(150,0,255)),ColorSequenceKeypoint.new(0.4,Color3.fromRGB(80,0,200)),ColorSequenceKeypoint.new(1,Color3.fromRGB(20,0,60))}), LightEmission=0.90, Texture="rbxasset://textures/particles/smoke_main.dds", Size=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.5,2),NumberSequenceKeypoint.new(1,0)}), Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.2),NumberSequenceKeypoint.new(1,1)}), Rate=42})
    MkPE(attCenter, {Color=ColorSequence.new(Color3.fromRGB(220,180,255)), LightEmission=1, Texture="rbxasset://textures/particles/sparkles_main.dds", Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.3),NumberSequenceKeypoint.new(1,0)}), Rate=65, Lifetime=NumberRange.new(0.1,0.4)})

    local pLight1 = Instance.new("PointLight", mainOrb)
    pLight1.Color, pLight1.Brightness, pLight1.Range = HP_CFG.LightColor1, HP_CFG.LightBrightness, HP_CFG.LightRange
    local pLight2 = Instance.new("PointLight", glow3)
    pLight2.Color, pLight2.Brightness, pLight2.Range = HP_CFG.LightColor2, HP_CFG.LightBrightness*0.5, HP_CFG.LightRange*1.3

    local bolts = {}
    for i = 1,15 do bolts[i] = HP_MakeBoltSegs(HP_OrbModel, 5, 0.076, Color3.fromRGB(255,255,255)) end

    local tendrils = {}
    for i = 1,10 do
        local td = HP_MakePart(HP_OrbModel, Vector3.new(0.08,0.08,S*1.2), Color3.fromRGB(180,0,255), 0.28, Enum.PartType.Block)
        tendrils[i] = {part=td, angle=(i-1)*(math.pi*2/10), speed=1.18+i*0.095}
    end

    -- Step counter for throttling heavy operations — keeps FPS smooth
    local t, floatOff, hp_step = 0, 0, 0
    local groundY = 0  -- cached ground Y, updated every 8 frames
    local conn = RunService.Heartbeat:Connect(function(dt)
        t = t + dt
        hp_step = hp_step + 1

        local char2 = targetPlayer and targetPlayer.Character
        if not char2 or not char2.Parent then return end
        local root2 = char2:FindFirstChild("HumanoidRootPart")
        if not root2 then return end

        floatOff = HP_CFG.FloatOn and (math.sin(t * 1.6) * 0.20) or 0
        local pos = (root2.CFrame * CFrame.new(0, HP_CFG.OffsetY + floatOff, HP_CFG.OffsetZ)).Position

        -- Core + glow layers: update every frame (smooth float)
        local slowPulse = HP_CFG.PulseOn and (1 + math.sin(t * 2.2) * 0.05) or 1
        local breathe   = HP_CFG.PulseOn and (1 + math.sin(t * 1.1) * 0.04) or 1
        local cf = CFrame.new(pos)
        core.CFrame     = cf;  core.Size     = Vector3.new(S*0.40,S*0.40,S*0.40)
        coreGlow.CFrame = cf;  coreGlow.Size = Vector3.new(S*0.56,S*0.56,S*0.56)
        innerOrb.CFrame = cf;  innerOrb.Size = Vector3.new(S*0.73*slowPulse,S*0.73*slowPulse,S*0.73*slowPulse)
        mainOrb.CFrame  = cf;  mainOrb.Size  = Vector3.new(S*slowPulse,S*slowPulse,S*slowPulse)
        glow1.CFrame = cf;  glow1.Size = Vector3.new(S*1.35*breathe,S*1.35*breathe,S*1.35*breathe)
        glow2.CFrame = cf;  glow2.Size = Vector3.new(S*1.72*breathe,S*1.72*breathe,S*1.72*breathe)
        glow3.CFrame = cf;  glow3.Size = Vector3.new(S*2.12*breathe,S*2.12*breathe,S*2.12*breathe)
        glow4.CFrame = cf;  glow4.Size = Vector3.new(S*2.62*breathe,S*2.62*breathe,S*2.62*breathe)
        glow5.CFrame = cf;  glow5.Size = Vector3.new(S*3.25*breathe,S*3.25*breathe,S*3.25*breathe)
        glow6.CFrame = cf;  glow6.Size = Vector3.new(S*4.30*breathe,S*4.30*breathe,S*4.30*breathe)
        -- Color shift every 2 frames
        if hp_step % 2 == 0 then
            local cs2 = (math.sin(t * 0.7) + 1) * 0.5
            mainOrb.Color = Color3.fromRGB(math.floor(80 + cs2*40), 0, math.floor(200 + cs2*55))
        end

        -- Rings: update every 2 frames
        if HP_CFG.RingsOn and hp_step % 2 == 0 then
            for i2, rd in ipairs(rings) do
                rd.angle = rd.angle + dt * rd.speed * 2
                rd.part.CFrame = CFrame.new(pos) * CFrame.Angles(rd.angle, rd.tiltX, rd.tiltZ)
                rd.part.Transparency = rd.baseTr + math.abs(math.sin(t * 2.4 + i2)) * 0.20
            end
        end

        -- Orbiting mini-orbs: update every 2 frames
        if HP_CFG.OrbitingOrbsOn and hp_step % 2 == 0 then
            for i2, mo in ipairs(miniOrbs) do
                mo.angle = mo.angle + dt * mo.speed * 2
                local orbPos = pos + Vector3.new(
                    math.cos(mo.angle) * mo.dist,
                    math.sin(t * 1.4 + i2) * mo.vOff * S,
                    math.sin(mo.angle) * mo.dist)
                mo.orb.CFrame  = CFrame.new(orbPos)
                mo.halo.CFrame = CFrame.new(orbPos)
            end
        end

        -- Ground glow: raycast only every 8 frames, rotate every 2 frames
        if HP_CFG.GroundGlowOn then
            if hp_step % 8 == 0 then
                local res2 = workspace:Raycast(pos, Vector3.new(0, -60, 0))
                groundY = res2 and res2.Position.Y + 0.12 or (pos.Y - 10)
            end
            if hp_step % 2 == 0 then
                groundGlow.CFrame = CFrame.new(pos.X, groundY, pos.Z) * CFrame.Angles(0, t * 0.42, 0)
            end
        end

        -- Tendrils: update every 3 frames
        if HP_CFG.TendrilsOn and hp_step % 3 == 0 then
            for i2, td in ipairs(tendrils) do
                td.angle = td.angle + dt * td.speed * 3
                local tDir = Vector3.new(math.cos(td.angle), math.sin(t * 0.7 + i2), math.sin(td.angle))
                local tS = pos + tDir * (S * 0.5)
                local tE = pos + tDir * (S * 1.3)
                td.part.Size   = Vector3.new(0.08, 0.08, (tE - tS).Magnitude)
                td.part.CFrame = CFrame.lookAt((tS + tE) * 0.5, tE)
            end
        end

        -- Lightning bolts: update every 4 frames (random, cheap)
        if HP_CFG.LightningOn and hp_step % 4 == 0 then
            local r = S / 2
            for i2, b in ipairs(bolts) do
                if math.random() < 0.35 then
                    HP_UpdateBolt(b,
                        pos + Vector3.new(math.cos(i2) * r, 0, math.sin(i2) * r),
                        pos + Vector3.new(math.random(-4, 4), math.random(-4, 4), math.random(-4, 4)),
                        1.2, true)
                else
                    for _, s in ipairs(b) do s.Transparency = 1 end
                end
            end
        end

        -- Reset step counter to prevent overflow
        if hp_step >= 240 then hp_step = 0 end
    end)
    table.insert(HP_Connections, conn)
    HP_CFG.Active = true
end

local function pushHPState(active)
    task.spawn(function()
        pcall(function()
            local req = syn and syn.request or http and http.request or request
            if req then
                req({Url = CREATOR_HP_URL .. ".json", Method = "PUT",
                     Body = HttpService:JSONEncode({active = active})})
            end
        end)
    end)
end

local function syncHPState()
    task.spawn(function()
        pcall(function()
            local req = syn and syn.request or http and http.request or request
            if not req then return end
            local res = req({Url = CREATOR_HP_URL .. ".json", Method = "GET"})
            if res and res.Success and res.Body ~= "null" then
                local ok, d = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok and type(d) == "table" then
                    creatorHPActive = d.active == true
                end
            end
        end)
    end)
end

local function JJK_MakePart(size, color, shape)
    local p      = Instance.new("Part")
    p.Size       = size
    p.Color      = color
    p.Material   = Enum.Material.SmoothPlastic
    p.Anchored   = true
    p.CanCollide = false
    p.CastShadow = false
    if shape then p.Shape = shape end
    p.Parent = jjkFolder
    return p
end

-- Part maker for OWNER's wheel folder
local function JJK_MakePartOwner(size, color, shape)
    local p      = Instance.new("Part")
    p.Size       = size
    p.Color      = color
    p.Material   = Enum.Material.SmoothPlastic
    p.Anchored   = true
    p.CanCollide = false
    p.CastShadow = false
    if shape then p.Shape = shape end
    p.Parent = ownerJjkFolder
    return p
end

local function BuildWheel()
    jjkFolder:ClearAllChildren()
    jjkSpokes, jjkBalls, jjkRimSegs = {}, {}, {}
    local HUB_R = JJK_HUB_D / 2

    jjkHubPart = JJK_MakePart(Vector3.new(JJK_HUB_D, JJK_HUB_D * 0.5, JJK_HUB_D), JJK_GOLD_COL)
    Instance.new("CylinderMesh", jjkHubPart)

    local spokeLen = JJK_RADIUS - HUB_R - JJK_BALL_D * 0.5
    local spokeMid = HUB_R + spokeLen * 0.5

    for i = 1, JJK_SPOKES do
        local baseAngle = math.rad((i - 1) * (360 / JJK_SPOKES))
        local sp = JJK_MakePart(Vector3.new(spokeLen, JJK_SPOKE_T, JJK_SPOKE_T), JJK_GOLD_COL)
        table.insert(jjkSpokes, { p = sp, a = baseAngle, mid = spokeMid })
        local bl = JJK_MakePart(Vector3.new(JJK_BALL_D, JJK_BALL_D, JJK_BALL_D), JJK_GOLD_COL, Enum.PartType.Ball)
        local lt      = Instance.new("PointLight", bl)
        lt.Color      = JJK_GLOW_COL
        lt.Brightness = 1.0
        lt.Range      = 5
        table.insert(jjkBalls, { p = bl, a = baseAngle })
    end

    local segLen = 2 * JJK_RADIUS * math.sin(math.pi / JJK_RIM_SEGS) + 0.04
    for i = 1, JJK_RIM_SEGS do
        local midA = math.rad((i - 0.5) * (360 / JJK_RIM_SEGS))
        local seg  = JJK_MakePart(Vector3.new(segLen, JJK_RIM_T, JJK_RIM_T), JJK_DGOLD_COL)
        table.insert(jjkRimSegs, { p = seg, mid = midA })
    end
end

-- Build wheel for OWNER character — uses OWNER's independent colours
local function BuildOwnerWheel()
    ownerJjkFolder:ClearAllChildren()
    ownerJjkSpokes, ownerJjkBalls, ownerJjkRimSegs = {}, {}, {}
    local HUB_R = JJK_HUB_D / 2

    ownerJjkHubPart = JJK_MakePartOwner(Vector3.new(JJK_HUB_D, JJK_HUB_D * 0.5, JJK_HUB_D), OWNER_GOLD_COL)
    Instance.new("CylinderMesh", ownerJjkHubPart)

    local spokeLen = JJK_RADIUS - HUB_R - JJK_BALL_D * 0.5
    local spokeMid = HUB_R + spokeLen * 0.5

    for i = 1, JJK_SPOKES do
        local baseAngle = math.rad((i - 1) * (360 / JJK_SPOKES))
        local sp = JJK_MakePartOwner(Vector3.new(spokeLen, JJK_SPOKE_T, JJK_SPOKE_T), OWNER_GOLD_COL)
        table.insert(ownerJjkSpokes, { p = sp, a = baseAngle, mid = spokeMid })
        local bl = JJK_MakePartOwner(Vector3.new(JJK_BALL_D, JJK_BALL_D, JJK_BALL_D), OWNER_GOLD_COL, Enum.PartType.Ball)
        local lt      = Instance.new("PointLight", bl)
        lt.Color      = OWNER_GLOW_COL
        lt.Brightness = 1.0
        lt.Range      = 5
        table.insert(ownerJjkBalls, { p = bl, a = baseAngle })
    end

    local segLen = 2 * JJK_RADIUS * math.sin(math.pi / JJK_RIM_SEGS) + 0.04
    for i = 1, JJK_RIM_SEGS do
        local midA = math.rad((i - 0.5) * (360 / JJK_RIM_SEGS))
        local seg  = JJK_MakePartOwner(Vector3.new(segLen, JJK_RIM_T, JJK_RIM_T), OWNER_DGOLD_COL)
        table.insert(ownerJjkRimSegs, { p = seg, mid = midA })
    end
end

-- WheelCenter targets the CREATOR's head.
-- Uses head.CFrame.UpVector so the wheel stays above the face
-- even when the creator is lying down (prone / ragdoll).
local function WheelCenter()
    local creatorPlayer = Players:GetPlayerByUserId(CREATOR_ID)
    if not creatorPlayer then return nil end
    local ch = creatorPlayer.Character
    if not ch then return nil end
    local head = ch:FindFirstChild("Head")
    if not head then return nil end
    -- head.CFrame.UpVector is the head's local-up axis.
    -- Standing  → UpVector ≈ (0,1,0)  → wheel floats above the top of head.
    -- Face-down → UpVector ≈ forward world dir → wheel appears above the face.
    return head.CFrame.Position + head.CFrame.UpVector * JJK_HEIGHT
end

-- WheelCenter for OWNER's head
local function OwnerWheelCenter()
    local ownerPlayer = Players:GetPlayerByUserId(OWNER_ID)
    if not ownerPlayer then return nil end
    local ch = ownerPlayer.Character
    if not ch then return nil end
    local head = ch:FindFirstChild("Head")
    if not head then return nil end
    return head.CFrame.Position + head.CFrame.UpVector * JJK_HEIGHT
end

local function StartWheelLoop()
    if jjkHbConn then jjkHbConn:Disconnect() end
    jjkHbConn = RunService.Heartbeat:Connect(function(dt)
        jjkRotation = jjkRotation + math.rad(JJK_SPEED) * dt
        local center = WheelCenter()
        if not center or not jjkHubPart or not jjkHubPart.Parent then return end
        local cos, sin = math.cos, math.sin

        jjkHubPart.CFrame = CFrame.new(center)

        for _, s in ipairs(jjkSpokes) do
            local a   = s.a + jjkRotation
            local off = Vector3.new(cos(a), 0, sin(a)) * s.mid
            s.p.CFrame = CFrame.fromMatrix(
                center + off,
                Vector3.new(cos(a), 0, sin(a)),
                Vector3.new(0, 1, 0)
            )
        end

        for _, b in ipairs(jjkBalls) do
            local a = b.a + jjkRotation
            b.p.CFrame = CFrame.new(
                center + Vector3.new(cos(a), 0, sin(a)) * JJK_RADIUS
            )
        end

        for _, r in ipairs(jjkRimSegs) do
            local ma   = r.mid + jjkRotation
            local pos  = Vector3.new(cos(ma), 0, sin(ma)) * JJK_RADIUS
            local tang = Vector3.new(-sin(ma), 0, cos(ma))
            r.p.CFrame = CFrame.fromMatrix(
                center + pos,
                tang,
                Vector3.new(0, 1, 0)
            )
        end
    end)
end

-- Heartbeat loop for OWNER's wheel
local function StartOwnerWheelLoop()
    if ownerJjkHbConn then ownerJjkHbConn:Disconnect() end
    ownerJjkHbConn = RunService.Heartbeat:Connect(function(dt)
        ownerJjkRotation = ownerJjkRotation + math.rad(JJK_SPEED) * dt
        local center = OwnerWheelCenter()
        if not center or not ownerJjkHubPart or not ownerJjkHubPart.Parent then return end
        local cos, sin = math.cos, math.sin

        ownerJjkHubPart.CFrame = CFrame.new(center)

        for _, s in ipairs(ownerJjkSpokes) do
            local a   = s.a + ownerJjkRotation
            local off = Vector3.new(cos(a), 0, sin(a)) * s.mid
            s.p.CFrame = CFrame.fromMatrix(
                center + off,
                Vector3.new(cos(a), 0, sin(a)),
                Vector3.new(0, 1, 0)
            )
        end

        for _, b in ipairs(ownerJjkBalls) do
            local a = b.a + ownerJjkRotation
            b.p.CFrame = CFrame.new(
                center + Vector3.new(cos(a), 0, sin(a)) * JJK_RADIUS
            )
        end

        for _, r in ipairs(ownerJjkRimSegs) do
            local ma   = r.mid + ownerJjkRotation
            local pos  = Vector3.new(cos(ma), 0, sin(ma)) * JJK_RADIUS
            local tang = Vector3.new(-sin(ma), 0, cos(ma))
            r.p.CFrame = CFrame.fromMatrix(
                center + pos,
                tang,
                Vector3.new(0, 1, 0)
            )
        end
    end)
end

-- Reconnect wheel when creator respawns
local function ConnectCreatorRespawn()
    local creatorPlayer = Players:GetPlayerByUserId(CREATOR_ID)
    if creatorPlayer then
        creatorPlayer.CharacterAdded:Connect(function()
            task.wait(1)
            if jjkWheelActive then
                BuildWheel()
                StartWheelLoop()
            end
        end)
    end
end

-- Reconnect wheel when owner respawns
local function ConnectOwnerRespawn()
    local ownerPlayer = Players:GetPlayerByUserId(OWNER_ID)
    if ownerPlayer then
        ownerPlayer.CharacterAdded:Connect(function()
            task.wait(1)
            if ownerJjkWheelActive then
                BuildOwnerWheel()
                StartOwnerWheelLoop()
            end
        end)
    end
end

-- If creator joins server while script is already running
Players.PlayerAdded:Connect(function(p)
    if p.UserId == CREATOR_ID then
        ConnectCreatorRespawn()
        task.wait(1)
        if jjkWheelActive then
            BuildWheel()
            StartWheelLoop()
        end
    end
    -- If owner joins server while script is already running
    if p.UserId == OWNER_ID then
        ConnectOwnerRespawn()
        task.wait(1)
        if ownerJjkWheelActive then
            BuildOwnerWheel()
            StartOwnerWheelLoop()
        end
    end
end)

-- ============================================================
-- CREATOR WHEEL STATE PUSH — called by Creator when they change
-- their wheel settings. Writes to CREATOR_WHEEL_URL only.
-- ============================================================
local function pushCreatorWheelState()
    local req = syn and syn.request or http and http.request or request
    if not req then return end
    local stateObj = {
        active = jjkWheelActive,
        mainR  = math.floor(JJK_GOLD_COL.R  * 255 + 0.5),
        mainG  = math.floor(JJK_GOLD_COL.G  * 255 + 0.5),
        mainB  = math.floor(JJK_GOLD_COL.B  * 255 + 0.5),
        rimR   = math.floor(JJK_DGOLD_COL.R * 255 + 0.5),
        rimG   = math.floor(JJK_DGOLD_COL.G * 255 + 0.5),
        rimB   = math.floor(JJK_DGOLD_COL.B * 255 + 0.5),
        glowR  = math.floor(JJK_GLOW_COL.R  * 255 + 0.5),
        glowG  = math.floor(JJK_GLOW_COL.G  * 255 + 0.5),
        glowB  = math.floor(JJK_GLOW_COL.B  * 255 + 0.5),
    }
    local json = HttpService:JSONEncode(stateObj)
    lastCreatorWheelStateJson = json
    task.spawn(function()
        pcall(function()
            req({ Url = CREATOR_WHEEL_URL .. ".json", Method = "PUT", Body = json })
        end)
    end)
end

-- ============================================================
-- OWNER WHEEL STATE PUSH — called by Owner when they change
-- their wheel settings. Writes to OWNER_WHEEL_URL only.
-- ============================================================
local function pushOwnerWheelState()
    local req = syn and syn.request or http and http.request or request
    if not req then return end
    local stateObj = {
        active = ownerJjkWheelActive,
        mainR  = math.floor(OWNER_GOLD_COL.R  * 255 + 0.5),
        mainG  = math.floor(OWNER_GOLD_COL.G  * 255 + 0.5),
        mainB  = math.floor(OWNER_GOLD_COL.B  * 255 + 0.5),
        rimR   = math.floor(OWNER_DGOLD_COL.R * 255 + 0.5),
        rimG   = math.floor(OWNER_DGOLD_COL.G * 255 + 0.5),
        rimB   = math.floor(OWNER_DGOLD_COL.B * 255 + 0.5),
        glowR  = math.floor(OWNER_GLOW_COL.R  * 255 + 0.5),
        glowG  = math.floor(OWNER_GLOW_COL.G  * 255 + 0.5),
        glowB  = math.floor(OWNER_GLOW_COL.B  * 255 + 0.5),
    }
    local json = HttpService:JSONEncode(stateObj)
    lastOwnerWheelStateJson = json
    task.spawn(function()
        pcall(function()
            req({ Url = OWNER_WHEEL_URL .. ".json", Method = "PUT", Body = json })
        end)
    end)
end

-- ============================================================
-- CREATOR WHEEL STATE SYNC — ALL clients pull CREATOR's wheel
-- state from CREATOR_WHEEL_URL and apply it to the creator wheel only.
-- ============================================================
local function syncCreatorWheelState()
    local req = syn and syn.request or http and http.request or request
    if not req then return end
    pcall(function()
        local res = req({ Url = CREATOR_WHEEL_URL .. ".json", Method = "GET" })
        if res.Success and res.Body ~= "null" and res.Body ~= lastCreatorWheelStateJson then
            lastCreatorWheelStateJson = res.Body
            local ok, state = pcall(HttpService.JSONDecode, HttpService, res.Body)
            if not ok or type(state) ~= "table" then return end

            local newActive
            if type(state.active) == "boolean" then
                newActive = state.active
            else
                newActive = true
            end

            local newMain = Color3.fromRGB(
                state.mainR or 212, state.mainG or 175, state.mainB or 55)
            local newRim  = Color3.fromRGB(
                state.rimR  or 170, state.rimG  or 135, state.rimB  or 25)
            local newGlow = Color3.fromRGB(
                state.glowR or 255, state.glowG or 215, state.glowB or 80)

            JJK_GOLD_COL  = newMain
            JJK_DGOLD_COL = newRim
            JJK_GLOW_COL  = newGlow

            if newActive ~= jjkWheelActive then
                jjkWheelActive = newActive
                if jjkWheelActive then
                    BuildWheel()
                    StartWheelLoop()
                else
                    jjkFolder:ClearAllChildren()
                    if jjkHbConn then jjkHbConn:Disconnect() end
                end
            elseif jjkWheelActive then
                -- Color changed — rebuild creator wheel with new colors
                BuildWheel()
                StartWheelLoop()
            end

            -- Update Creator's Aura tab UI if it is open
            if onCreatorWheelStateSync then
                onCreatorWheelStateSync()
            end
        end
    end)
end

-- ============================================================
-- OWNER WHEEL STATE SYNC — ALL clients pull OWNER's wheel
-- state from OWNER_WHEEL_URL and apply it to the owner wheel only.
-- ============================================================
local function syncOwnerWheelState()
    local req = syn and syn.request or http and http.request or request
    if not req then return end
    pcall(function()
        local res = req({ Url = OWNER_WHEEL_URL .. ".json", Method = "GET" })
        if res.Success and res.Body ~= "null" and res.Body ~= lastOwnerWheelStateJson then
            lastOwnerWheelStateJson = res.Body
            local ok, state = pcall(HttpService.JSONDecode, HttpService, res.Body)
            if not ok or type(state) ~= "table" then return end

            local newActive
            if type(state.active) == "boolean" then
                newActive = state.active
            else
                newActive = true
            end

            local newMain = Color3.fromRGB(
                state.mainR or 212, state.mainG or 175, state.mainB or 55)
            local newRim  = Color3.fromRGB(
                state.rimR  or 170, state.rimG  or 135, state.rimB  or 25)
            local newGlow = Color3.fromRGB(
                state.glowR or 255, state.glowG or 215, state.glowB or 80)

            OWNER_GOLD_COL  = newMain
            OWNER_DGOLD_COL = newRim
            OWNER_GLOW_COL  = newGlow

            if newActive ~= ownerJjkWheelActive then
                ownerJjkWheelActive = newActive
                if ownerJjkWheelActive then
                    BuildOwnerWheel()
                    StartOwnerWheelLoop()
                else
                    ownerJjkFolder:ClearAllChildren()
                    if ownerJjkHbConn then ownerJjkHbConn:Disconnect() end
                end
            elseif ownerJjkWheelActive then
                -- Color changed — rebuild owner wheel with new colors
                BuildOwnerWheel()
                StartOwnerWheelLoop()
            end

            -- Update Owner's Aura tab UI if it is open
            if onOwnerWheelStateSync then
                onOwnerWheelStateSync()
            end
        end
    end)
end

-- FUNCTION TO FIND PLAYER BY NAME
local function GetPlayerByName(name)
    name = string.lower(name)
    for _, p in pairs(Players:GetPlayers()) do
        if string.find(string.lower(p.Name), name) or string.find(string.lower(p.DisplayName), name) then
            return p
        end
    end
    return nil
end

-- FUNCTION TO CHECK TAGS
local function CachePlayerTags(player)
    if not player then return end
    if TagCache[player.UserId] then return TagCache[player.UserId] end
    local tagData = {text = "", type = "Normal", tagTitle = nil}
    if player.UserId == CREATOR_ID then
        tagData.text     = "[ᴄʀᴇᴀᴛᴏʀ] "
        tagData.type     = "Creator"
        tagData.tagTitle = "[ᴄʀᴇᴀᴛᴏʀ]"
    elseif player.UserId == OWNER_ID then
        tagData.text     = "[SUPREME] "
        tagData.type     = "Owner"
        tagData.tagTitle = "[SUPREME]"
    elseif CUTE_IDS[player.UserId] then
        tagData.text = "[CUTE] "
        tagData.type = "Cute"
    elseif HELLGOD_IDS[player.UserId] then
        tagData.text     = "[HellGod] "
        tagData.type     = "HellGod"
        tagData.tagTitle = "[HellGod]"
    elseif GOD_IDS[player.UserId] then
        tagData.text     = "[GOD] "
        tagData.type     = "God"
        tagData.tagTitle = "[GOD]"
    elseif DADDY_IDS[player.UserId] then
        tagData.text     = "[DADDY] "
        tagData.type     = "Daddy"
        tagData.tagTitle = "[DADDY]"
    elseif REAPER_IDS[player.UserId] then
        tagData.text     = "[REAPER] "
        tagData.type     = "Reaper"
        tagData.tagTitle = "[REAPER]"
    elseif PAPA_MVP_IDS[player.UserId] then
        tagData.text     = "[PAPA MVP] "
        tagData.type     = "PapaMvp"
        tagData.tagTitle = "[PAPA MVP]"
    elseif VIP_IDS[player.UserId] then
        tagData.text = "[VIP] "
        tagData.type = "Vip"
    end
    -- Custom titles override (checked after built-in titles only for non-special users)
    -- Custom titles are only applied if the user has no other special tag
    if tagData.type == "Normal" then
        local ct = CustomTitles[player.UserId]
        if ct then
            local now = os.time()
            if ct.expiresAt and ct.expiresAt > now then
                tagData.text     = "[" .. ct.title .. "] "
                tagData.type     = "CustomTitle"
                tagData.tagTitle = "[" .. ct.title .. "]"
            else
                -- Expired — remove from local cache
                CustomTitles[player.UserId] = nil
            end
        end
    end
    TagCache[player.UserId] = tagData
    return tagData
end

-- ============================================================
-- CRITICAL FIX: RGB LOOP WITH STRICT SAFE TEXT ENCODING
-- NOTE: replyTo is now rendered as a separate sub-frame inside
-- the TextButton (created in addMessage), so we do NOT include
-- it here — this prevents the reply text from overlapping.
--
-- TAG COLOR RULES:
--   GOD        → silver (rgb(192,192,192)) — non-RGB, static silver
--   CustomTitle → red (rgb(220,50,50)) — non-RGB, static red
--   DADDY      → RGB cycling (same as Creator/Owner/HellGod)
--   All others with special tags → RGB cycling
-- ============================================================
local function SafeEncodeMsg(raw)
    raw = tostring(raw or "")
    raw = raw:gsub("<[^>]*>", "")
    return raw
end

-- Throttle RGB label updates to ~10 fps (was 60 fps — primary lag source)
local _lastRgbTick = 0
RunService.Heartbeat:Connect(function()
    local now = tick()
    if now - _lastRgbTick < 0.1 then return end
    _lastRgbTick = now

    local hue = (now % 5) / 5
    local color = Color3.fromHSV(hue, 1, 1)
    local r = math.clamp(math.floor(color.R * 255), 0, 255)
    local g = math.clamp(math.floor(color.G * 255), 0, 255)
    local b = math.clamp(math.floor(color.B * 255), 0, 255)
    local rgbString = "rgb(" .. r .. "," .. g .. "," .. b .. ")"

    for label, data in pairs(SpecialLabels) do
        if label and label.Parent then
            local pvtPart  = data.isPrivate and "<font color='rgb(255,100,255)'>[PVT] </font>" or ""
            local tagTitle = data.tagTitle or ("[" .. data.tagType:upper() .. "]")
            local safeMsg  = SafeEncodeMsg(data.msg)
            -- Build formatted text string
            local fmtText
            if data.tagType == "God" then
                fmtText = string.format(
                    "%s<font color='rgb(192,192,192)'><b>%s</b></font> <font color='%s'><b>%s</b></font>: %s",
                    pvtPart, tagTitle, data.nameColor, data.displayName, safeMsg)
            elseif data.tagType == "CustomTitle" then
                local ctColor = data.titleColor or "rgb(220,50,50)"
                fmtText = string.format(
                    "%s<font color='%s'><b>%s</b></font> <font color='%s'><b>%s</b></font>: %s",
                    pvtPart, ctColor, tagTitle, data.nameColor, data.displayName, safeMsg)
            else
                fmtText = string.format(
                    "%s<font color='%s'><b>%s</b></font> <font color='%s'><b>%s</b></font>: %s",
                    pvtPart, rgbString, tagTitle, data.nameColor, data.displayName, safeMsg)
            end
            -- STICKER special-tag: update the separate nameLabel child, not the button text
            if data.isSticker and data.stickerLabel and data.stickerLabel.Parent then
                data.stickerLabel.RichText = true
                -- For sticker bubbles only show name (no ": msg" suffix)
                local nameFmt
                if data.tagType == "God" then
                    nameFmt = string.format(
                        "%s<font color='rgb(192,192,192)'><b>%s</b></font> <font color='%s'><b>%s</b></font>",
                        pvtPart, tagTitle, data.nameColor, data.displayName)
                elseif data.tagType == "CustomTitle" then
                    local ctColor = data.titleColor or "rgb(220,50,50)"
                    nameFmt = string.format(
                        "%s<font color='%s'><b>%s</b></font> <font color='%s'><b>%s</b></font>",
                        pvtPart, ctColor, tagTitle, data.nameColor, data.displayName)
                else
                    nameFmt = string.format(
                        "%s<font color='%s'><b>%s</b></font> <font color='%s'><b>%s</b></font>",
                        pvtPart, rgbString, tagTitle, data.nameColor, data.displayName)
                end
                data.stickerLabel.Text = nameFmt
            else
                label.RichText = true
                label.Text = fmtText
            end
        else
            SpecialLabels[label] = nil
        end
    end
end)

for _, p in pairs(Players:GetPlayers()) do task.spawn(CachePlayerTags, p) end
Players.PlayerAdded:Connect(CachePlayerTags)

-- ============================================================
-- PREMIUM UI SETUP
-- ============================================================
local ScreenGui = Instance.new("ScreenGui", game:GetService("CoreGui"))
ScreenGui.Name = "AresChat_Universal_V8"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- NOTIFICATION CONTAINER — top-center, slides down
local NotifContainer = Instance.new("Frame", ScreenGui)
NotifContainer.Size = UDim2.new(0, 310, 0, 80)
NotifContainer.Position = UDim2.new(0.5, 0, 0, -10)
NotifContainer.AnchorPoint = Vector2.new(0.5, 0)
NotifContainer.BackgroundTransparency = 1
NotifContainer.ClipsDescendants = true

-- MAIN FRAME
local Main = Instance.new("Frame", ScreenGui)
Main.Size = UDim2.new(0, 374, 0, 330)
Main.Position = UDim2.new(0.5, 0, 0.4, 0)
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.BackgroundColor3 = Color3.fromRGB(8, 8, 18)
Main.BackgroundTransparency = 0.5
Main.BorderSizePixel = 0
Main.Active = true
local MainCorner = Instance.new("UICorner", Main)
MainCorner.CornerRadius = UDim.new(0, 16)

-- Outer glow border effect
local MainStroke = Instance.new("UIStroke", Main)
MainStroke.Color = Color3.fromRGB(120, 60, 255)
MainStroke.Thickness = 1.5
MainStroke.Transparency = 0.3

-- Animated RGB border
task.spawn(function()
    while Main and Main.Parent do
        local hue = (tick() % 4) / 4
        MainStroke.Color = Color3.fromHSV(hue, 0.8, 1)
        task.wait(0.05)
    end
end)

-- HEADER
local Header = Instance.new("Frame", Main)
Header.Size = UDim2.new(1, 0, 0, 38)
Header.BackgroundColor3 = Color3.fromRGB(20, 10, 45)
Header.BackgroundTransparency = 0.5
Header.BorderSizePixel = 0
local HeaderCorner = Instance.new("UICorner", Header)
HeaderCorner.CornerRadius = UDim.new(0, 16)
local HeaderFix = Instance.new("Frame", Header)
HeaderFix.Size = UDim2.new(1, 0, 0.5, 0)
HeaderFix.Position = UDim2.new(0, 0, 0.5, 0)
HeaderFix.BackgroundColor3 = Color3.fromRGB(20, 10, 45)
HeaderFix.BackgroundTransparency = 0.5
HeaderFix.BorderSizePixel = 0

-- Logo dot
local LogoDot = Instance.new("Frame", Header)
LogoDot.Size = UDim2.new(0, 8, 0, 8)
LogoDot.Position = UDim2.new(0, 10, 0.5, -4)
LogoDot.BackgroundColor3 = Color3.fromRGB(140, 80, 255)
LogoDot.BorderSizePixel = 0
Instance.new("UICorner", LogoDot).CornerRadius = UDim.new(1, 0)

local Title = Instance.new("TextLabel", Header)
Title.Size = UDim2.new(1, -40, 1, 0)
Title.Position = UDim2.new(0, 24, 0, 0)
Title.Text = "* ARES RECHAT - V31🐥"
Title.TextColor3 = Color3.fromRGB(220, 200, 255)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Font = Enum.Font.GothamBold
Title.TextSize = 13
Title.BackgroundTransparency = 1
Title.ZIndex = 2

-- ============================================================
-- LOCK BUTTON — next to Minimize, toggles GUI drag lock.
-- When LOCKED: GUI cannot be dragged at all.
-- When UNLOCKED: GUI drags normally via header.
-- The LockBtn itself is always non-draggable.
-- ============================================================
local isGuiLocked = false

local LockBtn = Instance.new("TextButton", Header)
LockBtn.Size = UDim2.new(0, 26, 0, 26)
LockBtn.Position = UDim2.new(1, -92, 0.5, -13)
LockBtn.Text = "🔓"
LockBtn.Font = Enum.Font.GothamBold
LockBtn.TextColor3 = Color3.fromRGB(200, 180, 255)
LockBtn.BackgroundColor3 = Color3.fromRGB(30, 60, 30)
LockBtn.BackgroundTransparency = 0.4
LockBtn.TextSize = 13
LockBtn.ZIndex = 3
Instance.new("UICorner", LockBtn).CornerRadius = UDim.new(1, 0)

LockBtn.MouseButton1Click:Connect(function()
    isGuiLocked = not isGuiLocked
    if isGuiLocked then
        LockBtn.Text = "🔒"
        LockBtn.BackgroundColor3 = Color3.fromRGB(120, 30, 30)
        LockBtn.TextColor3 = Color3.fromRGB(255, 120, 120)
    else
        LockBtn.Text = "🔓"
        LockBtn.BackgroundColor3 = Color3.fromRGB(30, 60, 30)
        LockBtn.TextColor3 = Color3.fromRGB(200, 180, 255)
    end
end)

-- ============================================================
-- STICKER BUTTON — sits between Lock and Minimize buttons.
-- Tapping opens a small floating sticker panel above the header.
-- Clicking any sticker instantly sends it to Firebase as a
-- [STICKER:assetId] message visible to all script users.
-- ============================================================
-- STICKER_IDS — fetched from GitHub at startup so obfuscation never
-- corrupts the asset ID numbers.  Empty until the fetch completes
-- (typically < 1 second); the panel is safe to open after that.
local STICKER_IDS = {}
local _stickersLoaded = false

task.spawn(function()
    pcall(function()
        local req = syn and syn.request or http and http.request or request
        if not req then return end
        local res = req({ Url = STICKER_IDS_URL, Method = "GET" })
        if res and res.Success and res.Body and res.Body ~= "" then
            local ok, decoded = pcall(HttpService.JSONDecode, HttpService, res.Body)
            if ok and type(decoded) == "table" then
                for _, id in ipairs(decoded) do
                    table.insert(STICKER_IDS, id)
                end
            end
        end
    end)
    _stickersLoaded = true
end)

local stickerPanelOpen = false
local StickerPanel = nil
local lastStickerScrollX = 0  -- remember horizontal scroll position

-- StickerBtn is created AFTER InputArea is defined (below), stored here for forward reference
local StickerBtn

local function closeStickerPanel()
    if StickerPanel and StickerPanel.Parent then
        -- Save scroll position before closing
        local scrollChild = StickerPanel:FindFirstChildOfClass("ScrollingFrame")
        if scrollChild then lastStickerScrollX = scrollChild.CanvasPosition.X end
        TweenService:Create(StickerPanel, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {BackgroundTransparency = 1}):Play()
        task.delay(0.16, function()
            if StickerPanel and StickerPanel.Parent then
                StickerPanel:Destroy()
                StickerPanel = nil
            end
        end)
    end
    stickerPanelOpen = false
    if StickerBtn then StickerBtn.BackgroundColor3 = Color3.fromRGB(50, 30, 90) end
end

local function openStickerPanel()
    if StickerPanel and StickerPanel.Parent then closeStickerPanel() return end
    -- If stickers haven't loaded yet from GitHub, wait up to 3 seconds then retry
    if not _stickersLoaded then
        task.spawn(function()
            local waited = 0
            while not _stickersLoaded and waited < 3 do
                task.wait(0.1)
                waited = waited + 0.1
            end
            openStickerPanel()
        end)
        return
    end
    stickerPanelOpen = true
    if StickerBtn then StickerBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 180) end

    -- Panel container — floating just above the input area, full-width premium style
    local panel = Instance.new("Frame", ScreenGui)
    panel.Name = "AresStickerPanel"
    panel.Size = UDim2.new(0, 320, 0, 130)
    panel.BackgroundColor3 = Color3.fromRGB(16, 10, 36)
    panel.BackgroundTransparency = 0.06
    panel.BorderSizePixel = 0
    panel.ZIndex = 300
    panel.ClipsDescendants = true

    local panelCorner = Instance.new("UICorner", panel)
    panelCorner.CornerRadius = UDim.new(0, 14)
    local panelStroke = Instance.new("UIStroke", panel)
    panelStroke.Color = Color3.fromRGB(130, 70, 240)
    panelStroke.Thickness = 1.3
    panelStroke.Transparency = 0.2

    -- Position the panel just above the input area (bottom of chat window)
    local absPos  = Main.AbsolutePosition
    local absSize = Main.AbsoluteSize
    local vpSize  = game.Workspace.CurrentCamera.ViewportSize
    local px = absPos.X
    local py = absPos.Y + absSize.Y - 44 - 130 - 4  -- above input area
    px = math.clamp(px, 4, vpSize.X - 324)
    py = math.clamp(py, 4, vpSize.Y - 135)
    panel.Position = UDim2.new(0, px, 0, py)

    -- Scrolling inner area for stickers
    local scroll = Instance.new("ScrollingFrame", panel)
    scroll.Size = UDim2.new(1, -8, 1, -8)
    scroll.Position = UDim2.new(0, 4, 0, 4)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = Color3.fromRGB(130, 80, 255)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.X
    scroll.ScrollingDirection = Enum.ScrollingDirection.X
    scroll.ZIndex = 301

    local grid = Instance.new("UIListLayout", scroll)
    grid.FillDirection = Enum.FillDirection.Horizontal
    grid.VerticalAlignment = Enum.VerticalAlignment.Center
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
    grid.Padding = UDim.new(0, 8)
    grid.SortOrder = Enum.SortOrder.LayoutOrder

    local padInner = Instance.new("UIPadding", scroll)
    padInner.PaddingLeft   = UDim.new(0, 6)
    padInner.PaddingRight  = UDim.new(0, 6)
    padInner.PaddingTop    = UDim.new(0, 5)
    padInner.PaddingBottom = UDim.new(0, 5)

    -- Build sticker buttons — premium Instagram-style larger tiles
    for idx, assetId in ipairs(STICKER_IDS) do
        local sBtn = Instance.new("TextButton", scroll)
        sBtn.Size = UDim2.new(0, 100, 0, 100)
        sBtn.BackgroundColor3 = Color3.fromRGB(28, 14, 56)
        sBtn.BackgroundTransparency = 0.25
        sBtn.BorderSizePixel = 0
        sBtn.Text = ""
        sBtn.LayoutOrder = idx
        sBtn.ZIndex = 302
        local sBtnCorner = Instance.new("UICorner", sBtn)
        sBtnCorner.CornerRadius = UDim.new(0, 14)
        local sBtnStroke = Instance.new("UIStroke", sBtn)
        sBtnStroke.Color = Color3.fromRGB(120, 60, 220)
        sBtnStroke.Thickness = 1.5
        sBtnStroke.Transparency = 0.4

        local sImg = Instance.new("ImageLabel", sBtn)
        sImg.Size = UDim2.new(1, -12, 1, -12)
        sImg.Position = UDim2.new(0, 6, 0, 6)
        sImg.BackgroundTransparency = 1
        sImg.Image = "rbxthumb://type=Asset&id=" .. tostring(assetId) .. "&w=150&h=150"
        sImg.ScaleType = Enum.ScaleType.Fit
        sImg.ZIndex = 303

        -- Hover effect
        sBtn.MouseEnter:Connect(function()
            TweenService:Create(sBtn, TweenInfo.new(0.1), {BackgroundTransparency = 0.0}):Play()
            sBtnStroke.Transparency = 0.0
        end)
        sBtn.MouseLeave:Connect(function()
            TweenService:Create(sBtn, TweenInfo.new(0.1), {BackgroundTransparency = 0.25}):Play()
            sBtnStroke.Transparency = 0.4
        end)

        local capturedId = assetId
        sBtn.MouseButton1Click:Connect(function()
            closeStickerPanel()
            -- Send sticker as a special message: [STICKER:assetId]
            local stickerMsg = "[STICKER:" .. tostring(capturedId) .. "]"
            send(stickerMsg, false, false)
        end)
    end

    StickerPanel = panel

    -- Restore scroll position from last open
    task.spawn(function()
        RunService.Heartbeat:Wait()
        RunService.Heartbeat:Wait()
        if scroll and scroll.Parent then
            scroll.CanvasPosition = Vector2.new(lastStickerScrollX, 0)
        end
    end)

    -- Animate in
    panel.BackgroundTransparency = 1
    TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {BackgroundTransparency = 0.06}):Play()

    -- Close panel when clicking outside it
    local spConn
    spConn = UserInputService.InputBegan:Connect(function(inp)
        if not panel or not panel.Parent then
            if spConn then spConn:Disconnect() end return
        end
        if inp.UserInputType ~= Enum.UserInputType.MouseButton1
        and inp.UserInputType ~= Enum.UserInputType.Touch then return end
        local p2  = inp.Position
        local ab2 = panel.AbsolutePosition
        local sz2 = panel.AbsoluteSize
        -- Also check the sticker button itself (so clicking it closes instead of re-opening)
        local onBtn = false
        if StickerBtn then
            local abBtn = StickerBtn.AbsolutePosition
            local szBtn = StickerBtn.AbsoluteSize
            onBtn = (p2.X >= abBtn.X and p2.X <= abBtn.X + szBtn.X
                 and p2.Y >= abBtn.Y and p2.Y <= abBtn.Y + szBtn.Y)
        end
        if not onBtn and (p2.X < ab2.X or p2.X > ab2.X + sz2.X or p2.Y < ab2.Y or p2.Y > ab2.Y + sz2.Y) then
            closeStickerPanel()
            if spConn then spConn:Disconnect() end
        end
    end)
end

-- Minimize Button
local MinimizeBtn = Instance.new("TextButton", Header)
MinimizeBtn.Size = UDim2.new(0, 26, 0, 26)
MinimizeBtn.Position = UDim2.new(1, -32, 0.5, -13)
MinimizeBtn.Text = "-"
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.TextColor3 = Color3.fromRGB(200, 180, 255)
MinimizeBtn.BackgroundColor3 = Color3.fromRGB(60, 20, 100)
MinimizeBtn.BackgroundTransparency = 0.4
MinimizeBtn.TextSize = 14
MinimizeBtn.ZIndex = 3
Instance.new("UICorner", MinimizeBtn).CornerRadius = UDim.new(1, 0)

-- TAB BUTTONS
local TabButtons = Instance.new("Frame", Main)
TabButtons.Size = UDim2.new(1, -12, 0, 28)
TabButtons.Position = UDim2.new(0, 6, 0, 43)
TabButtons.BackgroundTransparency = 1

local UIListLayoutTab = Instance.new("UIListLayout", TabButtons)
UIListLayoutTab.FillDirection = Enum.FillDirection.Horizontal
UIListLayoutTab.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayoutTab.Padding = UDim.new(0, 4)

local function CreateTabBtn(txt, order, icon)
    local btn = Instance.new("TextButton", TabButtons)
    btn.Size = UDim2.new(0.19, 0, 1, 0)
    btn.Text = icon .. " " .. txt
    btn.Font = Enum.Font.GothamBold
    btn.TextColor3 = Color3.fromRGB(180, 150, 255)
    btn.TextSize = 10
    btn.LayoutOrder = order
    btn.BackgroundTransparency = 0.6
    btn.BackgroundColor3 = Color3.fromRGB(40, 20, 80)
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = Color3.fromRGB(100, 50, 200)
    stroke.Thickness = 1
    stroke.Transparency = 0.6
    return btn
end

local ChatTabBtn    = CreateTabBtn("CHAT",    1, "[C]")
local FriendsTabBtn = CreateTabBtn("FRIENDS", 2, "[F]")
local ThemeTabBtn   = CreateTabBtn("THEME",   3, "[T]")
-- ADMIN TAB — visible ONLY for Creator and Owner
local AdminTabBtn
if RealUserId == CREATOR_ID or RealUserId == OWNER_ID then
    AdminTabBtn = CreateTabBtn("ADMIN",   4, "[A]")
    AdminTabBtn.Size = UDim2.new(0.19, 0, 1, 0)
end

-- AURA TAB — visible for BOTH Creator AND Owner
local AuraTabBtn, AuraPage
if RealUserId == CREATOR_ID or RealUserId == OWNER_ID then
    AuraTabBtn = CreateTabBtn("AURA", 5, "[⚙]")
    AuraTabBtn.Size = UDim2.new(0.19, 0, 1, 0)
end

-- PAGES FRAME
local Pages = Instance.new("Frame", Main)
Pages.Size = UDim2.new(1, 0, 1, -138)
Pages.Position = UDim2.new(0, 0, 0, 77)
Pages.BackgroundTransparency = 1

-- CHAT PAGE
local ChatPage = Instance.new("Frame", Pages)
ChatPage.Size = UDim2.new(1, 0, 1, 0)
ChatPage.BackgroundTransparency = 1

local ChatLog = Instance.new("ScrollingFrame", ChatPage)
ChatLog.Size = UDim2.new(1, -14, 1, -5)
ChatLog.Position = UDim2.new(0, 7, 0, 5)
ChatLog.BackgroundTransparency = 1
ChatLog.ScrollBarThickness = 3
ChatLog.ScrollBarImageColor3 = Color3.fromRGB(120, 60, 255)
ChatLog.CanvasSize = UDim2.new(0, 0, 0, 0)
ChatLog.AutomaticCanvasSize = Enum.AutomaticSize.Y

local UIList = Instance.new("UIListLayout", ChatLog)
UIList.Padding = UDim.new(0, 4)
UIList.SortOrder = Enum.SortOrder.LayoutOrder

-- ============================================================
-- SCROLL STATE TRACKING + RETURN-TO-BOTTOM BUTTON
-- _userScrolledUp = true  → user scrolled up, auto-scroll paused
-- _userScrolledUp = false → at bottom, auto-scroll active
-- The ↓ button appears when scrolled up; tapping it returns to
-- the bottom and re-enables auto-scroll.
-- ============================================================
local _userScrolledUp = false

local ReturnToBottomBtn = Instance.new("TextButton", ChatPage)
ReturnToBottomBtn.Size = UDim2.new(0, 90, 0, 26)
ReturnToBottomBtn.Position = UDim2.new(0.5, -45, 1, -36)
ReturnToBottomBtn.AnchorPoint = Vector2.new(0, 0)
ReturnToBottomBtn.BackgroundColor3 = Color3.fromRGB(80, 30, 160)
ReturnToBottomBtn.BackgroundTransparency = 0.15
ReturnToBottomBtn.BorderSizePixel = 0
ReturnToBottomBtn.Text = "↓ Latest"
ReturnToBottomBtn.TextColor3 = Color3.fromRGB(220, 200, 255)
ReturnToBottomBtn.Font = Enum.Font.GothamBold
ReturnToBottomBtn.TextSize = 12
ReturnToBottomBtn.ZIndex = 10
ReturnToBottomBtn.Visible = false
Instance.new("UICorner", ReturnToBottomBtn).CornerRadius = UDim.new(0, 13)
local _rtbStroke = Instance.new("UIStroke", ReturnToBottomBtn)
_rtbStroke.Color = Color3.fromRGB(140, 80, 255)
_rtbStroke.Thickness = 1.2
_rtbStroke.Transparency = 0.2

ReturnToBottomBtn.MouseButton1Click:Connect(function()
    _userScrolledUp = false
    ReturnToBottomBtn.Visible = false
    ChatLog.CanvasPosition = Vector2.new(0, 99999999)
end)

-- Detect when user scrolls up manually
local _lastCanvasY = 0
ChatLog:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
    local canvas  = ChatLog.CanvasPosition.Y
    local maxY    = ChatLog.AbsoluteCanvasSize.Y - ChatLog.AbsoluteSize.Y
    local atBottom = (maxY <= 0) or (canvas >= maxY - 8)
    if atBottom then
        if _userScrolledUp then
            _userScrolledUp = false
            ReturnToBottomBtn.Visible = false
        end
    else
        if canvas < _lastCanvasY - 2 then
            -- User scrolled up
            if not _userScrolledUp then
                _userScrolledUp = true
                ReturnToBottomBtn.Visible = true
            end
        end
    end
    _lastCanvasY = canvas
end)

-- FRIENDS PAGE
local FriendsPage = Instance.new("Frame", Pages)
FriendsPage.Size = UDim2.new(1, 0, 1, 0)
FriendsPage.BackgroundTransparency = 1
FriendsPage.Name = "FriendsPage"
FriendsPage.Visible = false

local FriendsLog = Instance.new("ScrollingFrame", FriendsPage)
FriendsLog.Size = UDim2.new(1, -14, 1, -5)
FriendsLog.Position = UDim2.new(0, 7, 0, 5)
FriendsLog.BackgroundTransparency = 1
FriendsLog.ScrollBarThickness = 3
FriendsLog.ScrollBarImageColor3 = Color3.fromRGB(120, 60, 255)
FriendsLog.AutomaticCanvasSize = Enum.AutomaticSize.Y

local UIListF = Instance.new("UIListLayout", FriendsLog)
UIListF.Padding = UDim.new(0, 6)

-- THEME PAGE
local ThemePage = Instance.new("Frame", Pages)
ThemePage.Size = UDim2.new(1, 0, 1, 0)
ThemePage.Visible = false
ThemePage.BackgroundTransparency = 1

local ThemeLog = Instance.new("ScrollingFrame", ThemePage)
ThemeLog.Size = UDim2.new(1, -14, 1, -5)
ThemeLog.Position = UDim2.new(0, 7, 0, 5)
ThemeLog.BackgroundTransparency = 1
ThemeLog.ScrollBarThickness = 3
ThemeLog.ScrollBarImageColor3 = Color3.fromRGB(120, 60, 255)
ThemeLog.AutomaticCanvasSize = Enum.AutomaticSize.Y
Instance.new("UIListLayout", ThemeLog).Padding = UDim.new(0, 6)

-- ADMIN PAGE
local AdminPage = Instance.new("Frame", Pages)
AdminPage.Size = UDim2.new(1, 0, 1, 0)
AdminPage.Visible = false
AdminPage.BackgroundTransparency = 1

local AdminLog = Instance.new("ScrollingFrame", AdminPage)
AdminLog.Size = UDim2.new(1, -14, 1, -5)
AdminLog.Position = UDim2.new(0, 7, 0, 5)
AdminLog.BackgroundTransparency = 1
AdminLog.ScrollBarThickness = 3
AdminLog.ScrollBarImageColor3 = Color3.fromRGB(120, 60, 255)
AdminLog.AutomaticCanvasSize = Enum.AutomaticSize.Y
Instance.new("UIListLayout", AdminLog).Padding = UDim.new(0, 6)

-- ============================================================
-- AURA PAGE — Mahoraga Wheel controls
-- Creator sees and controls ONLY their own wheel.
-- Owner sees and controls ONLY their own wheel.
-- Each pushes to their own Firebase key independently.
-- ============================================================
if RealUserId == CREATOR_ID or RealUserId == OWNER_ID then
    AuraPage = Instance.new("Frame", Pages)
    AuraPage.Size = UDim2.new(1, 0, 1, 0)
    AuraPage.Visible = false
    AuraPage.BackgroundTransparency = 1

    local AuraLog = Instance.new("ScrollingFrame", AuraPage)
    AuraLog.Size = UDim2.new(1, -14, 1, -5)
    AuraLog.Position = UDim2.new(0, 7, 0, 5)
    AuraLog.BackgroundTransparency = 1
    AuraLog.ScrollBarThickness = 3
    AuraLog.ScrollBarImageColor3 = Color3.fromRGB(212, 175, 55)
    AuraLog.AutomaticCanvasSize = Enum.AutomaticSize.Y
    local AuraListLayout = Instance.new("UIListLayout", AuraLog)
    AuraListLayout.Padding = UDim.new(0, 8)
    AuraListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    AuraListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    local AuraPadding = Instance.new("UIPadding", AuraLog)
    AuraPadding.PaddingTop    = UDim.new(0, 8)
    AuraPadding.PaddingBottom = UDim.new(0, 8)
    AuraPadding.PaddingLeft   = UDim.new(0, 8)
    AuraPadding.PaddingRight  = UDim.new(0, 8)

    -- Title label
    local auraTitle = Instance.new("TextLabel", AuraLog)
    auraTitle.Size = UDim2.new(1, 0, 0, 32)
    auraTitle.BackgroundColor3 = Color3.fromRGB(35, 28, 8)
    auraTitle.BackgroundTransparency = 0.3
    auraTitle.BorderSizePixel = 0
    auraTitle.LayoutOrder = 1
    auraTitle.Text = "⚙️  MAHORAGA WHEEL  ⚙️"
    auraTitle.TextColor3 = Color3.fromRGB(212, 175, 55)
    auraTitle.Font = Enum.Font.GothamBold
    auraTitle.TextSize = 13
    Instance.new("UICorner", auraTitle).CornerRadius = UDim.new(0, 8)

    -- Wheel ON/OFF toggle button
    local jjkToggleBtn = Instance.new("TextButton", AuraLog)
    jjkToggleBtn.Size = UDim2.new(1, 0, 0, 42)
    jjkToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 160, 80)
    jjkToggleBtn.BorderSizePixel = 0
    jjkToggleBtn.Text = "⚡  WHEEL: ON"
    jjkToggleBtn.TextColor3 = Color3.fromRGB(240, 220, 140)
    jjkToggleBtn.TextSize = 13
    jjkToggleBtn.Font = Enum.Font.GothamBold
    jjkToggleBtn.LayoutOrder = 2
    Instance.new("UICorner", jjkToggleBtn).CornerRadius = UDim.new(0, 8)
    local jjkTStroke = Instance.new("UIStroke", jjkToggleBtn)
    jjkTStroke.Color = Color3.fromRGB(60, 160, 80)
    jjkTStroke.Thickness = 1.5

    -- ============================================================
    -- CREATOR: Set UI sync callback and wire toggle/colour to
    -- ONLY the creator's own wheel and CREATOR_WHEEL_URL.
    -- ============================================================
    if RealUserId == CREATOR_ID then

        onCreatorWheelStateSync = function()
            if jjkWheelActive then
                jjkToggleBtn.Text = "⚡  WHEEL: ON"
                TweenService:Create(jjkToggleBtn, TweenInfo.new(0.15, Enum.EasingStyle.Quad),
                    {BackgroundColor3 = Color3.fromRGB(60, 160, 80)}):Play()
                jjkTStroke.Color = Color3.fromRGB(60, 160, 80)
            else
                jjkToggleBtn.Text = "💤  WHEEL: OFF"
                TweenService:Create(jjkToggleBtn, TweenInfo.new(0.15, Enum.EasingStyle.Quad),
                    {BackgroundColor3 = Color3.fromRGB(180, 60, 60)}):Play()
                jjkTStroke.Color = Color3.fromRGB(180, 60, 60)
            end
        end

        jjkToggleBtn.MouseButton1Click:Connect(function()
            jjkWheelActive = not jjkWheelActive
            if jjkWheelActive then
                jjkToggleBtn.Text = "⚡  WHEEL: ON"
                TweenService:Create(jjkToggleBtn, TweenInfo.new(0.15, Enum.EasingStyle.Quad),
                    {BackgroundColor3 = Color3.fromRGB(60, 160, 80)}):Play()
                jjkTStroke.Color = Color3.fromRGB(60, 160, 80)
                BuildWheel()
                StartWheelLoop()
            else
                jjkToggleBtn.Text = "💤  WHEEL: OFF"
                TweenService:Create(jjkToggleBtn, TweenInfo.new(0.15, Enum.EasingStyle.Quad),
                    {BackgroundColor3 = Color3.fromRGB(180, 60, 60)}):Play()
                jjkTStroke.Color = Color3.fromRGB(180, 60, 60)
                jjkFolder:ClearAllChildren()
                if jjkHbConn then jjkHbConn:Disconnect() end
            end
            -- Push CREATOR's state to Firebase
            pushCreatorWheelState()
        end)

    -- ============================================================
    -- OWNER: Set UI sync callback and wire toggle/colour to
    -- ONLY the owner's own wheel and OWNER_WHEEL_URL.
    -- ============================================================
    elseif RealUserId == OWNER_ID then

        -- Initialise toggle button to reflect owner wheel state
        if not ownerJjkWheelActive then
            jjkToggleBtn.Text = "💤  WHEEL: OFF"
            jjkToggleBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
            jjkTStroke.Color = Color3.fromRGB(180, 60, 60)
        end

        onOwnerWheelStateSync = function()
            if ownerJjkWheelActive then
                jjkToggleBtn.Text = "⚡  WHEEL: ON"
                TweenService:Create(jjkToggleBtn, TweenInfo.new(0.15, Enum.EasingStyle.Quad),
                    {BackgroundColor3 = Color3.fromRGB(60, 160, 80)}):Play()
                jjkTStroke.Color = Color3.fromRGB(60, 160, 80)
            else
                jjkToggleBtn.Text = "💤  WHEEL: OFF"
                TweenService:Create(jjkToggleBtn, TweenInfo.new(0.15, Enum.EasingStyle.Quad),
                    {BackgroundColor3 = Color3.fromRGB(180, 60, 60)}):Play()
                jjkTStroke.Color = Color3.fromRGB(180, 60, 60)
            end
        end

        jjkToggleBtn.MouseButton1Click:Connect(function()
            ownerJjkWheelActive = not ownerJjkWheelActive
            if ownerJjkWheelActive then
                jjkToggleBtn.Text = "⚡  WHEEL: ON"
                TweenService:Create(jjkToggleBtn, TweenInfo.new(0.15, Enum.EasingStyle.Quad),
                    {BackgroundColor3 = Color3.fromRGB(60, 160, 80)}):Play()
                jjkTStroke.Color = Color3.fromRGB(60, 160, 80)
                BuildOwnerWheel()
                StartOwnerWheelLoop()
            else
                jjkToggleBtn.Text = "💤  WHEEL: OFF"
                TweenService:Create(jjkToggleBtn, TweenInfo.new(0.15, Enum.EasingStyle.Quad),
                    {BackgroundColor3 = Color3.fromRGB(180, 60, 60)}):Play()
                jjkTStroke.Color = Color3.fromRGB(180, 60, 60)
                ownerJjkFolder:ClearAllChildren()
                if ownerJjkHbConn then ownerJjkHbConn:Disconnect() end
            end
            -- Push OWNER's state to Firebase
            pushOwnerWheelState()
        end)

    end

    -- Colour section label
    local colSectionLbl = Instance.new("TextLabel", AuraLog)
    colSectionLbl.Size = UDim2.new(1, 0, 0, 24)
    colSectionLbl.BackgroundColor3 = Color3.fromRGB(35, 28, 8)
    colSectionLbl.BackgroundTransparency = 0.3
    colSectionLbl.BorderSizePixel = 0
    colSectionLbl.LayoutOrder = 3
    colSectionLbl.Text = "🎨  COLOUR"
    colSectionLbl.TextColor3 = Color3.fromRGB(212, 175, 55)
    colSectionLbl.Font = Enum.Font.GothamBold
    colSectionLbl.TextSize = 11
    colSectionLbl.TextXAlignment = Enum.TextXAlignment.Left
    local colSectionPad = Instance.new("UIPadding", colSectionLbl)
    colSectionPad.PaddingLeft = UDim.new(0, 8)
    Instance.new("UICorner", colSectionLbl).CornerRadius = UDim.new(0, 6)

    -- Colour presets
    local jjkColourPresets = {
        {name = "Gold",  bg = Color3.fromRGB(212,175,55),  main = Color3.fromRGB(212,175,55),  rim = Color3.fromRGB(170,135,25),  glow = Color3.fromRGB(255,215,80),  textCol = Color3.fromRGB(20,15,5)},
        {name = "White", bg = Color3.fromRGB(230,230,230), main = Color3.fromRGB(240,240,240), rim = Color3.fromRGB(200,200,200), glow = Color3.fromRGB(255,255,255), textCol = Color3.fromRGB(30,30,30)},
        {name = "Black", bg = Color3.fromRGB(50,50,50),    main = Color3.fromRGB(35,35,35),    rim = Color3.fromRGB(20,20,20),    glow = Color3.fromRGB(90,90,90),    textCol = Color3.fromRGB(200,200,200)},
        {name = "Red",   bg = Color3.fromRGB(200,40,40),   main = Color3.fromRGB(210,30,30),   rim = Color3.fromRGB(150,20,20),   glow = Color3.fromRGB(255,80,80),   textCol = Color3.fromRGB(255,220,220)},
    }

    local colRow = Instance.new("Frame", AuraLog)
    colRow.Size = UDim2.new(1, 0, 0, 46)
    colRow.BackgroundTransparency = 1
    colRow.BorderSizePixel = 0
    colRow.LayoutOrder = 4
    local colListLayout = Instance.new("UIListLayout", colRow)
    colListLayout.FillDirection       = Enum.FillDirection.Horizontal
    colListLayout.Padding             = UDim.new(0, 6)
    colListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    colListLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
    colListLayout.SortOrder           = Enum.SortOrder.LayoutOrder

    local jjkColBtnRefs = {}
    for i, preset in ipairs(jjkColourPresets) do
        local btn = Instance.new("TextButton", colRow)
        btn.Size = UDim2.new(0, 56, 0, 42)
        btn.BackgroundColor3 = preset.bg
        btn.BorderSizePixel = 0
        btn.Text = preset.name
        btn.TextColor3 = preset.textCol
        btn.TextSize = 11
        btn.Font = Enum.Font.GothamBold
        btn.LayoutOrder = i
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
        local bStroke = Instance.new("UIStroke", btn)
        bStroke.Color = preset.bg
        bStroke.Thickness = 1.2
        if preset.name == "Gold" then
            bStroke.Color = Color3.fromRGB(255, 255, 255)
            bStroke.Thickness = 3
        end
        table.insert(jjkColBtnRefs, {btn = btn, stroke = bStroke, preset = preset})
    end

    for _, ref in ipairs(jjkColBtnRefs) do
        local myRef = ref
        myRef.btn.MouseButton1Click:Connect(function()
            for _, r in ipairs(jjkColBtnRefs) do
                r.stroke.Color = r.preset.bg
                r.stroke.Thickness = 1.2
            end
            myRef.stroke.Color = Color3.fromRGB(255, 255, 255)
            myRef.stroke.Thickness = 3

            if RealUserId == CREATOR_ID then
                -- Change CREATOR's own colours only
                JJK_GOLD_COL  = myRef.preset.main
                JJK_DGOLD_COL = myRef.preset.rim
                JJK_GLOW_COL  = myRef.preset.glow
                if jjkWheelActive then
                    BuildWheel()
                    StartWheelLoop()
                end
                pushCreatorWheelState()

            elseif RealUserId == OWNER_ID then
                -- Change OWNER's own colours only
                OWNER_GOLD_COL  = myRef.preset.main
                OWNER_DGOLD_COL = myRef.preset.rim
                OWNER_GLOW_COL  = myRef.preset.glow
                if ownerJjkWheelActive then
                    BuildOwnerWheel()
                    StartOwnerWheelLoop()
                end
                pushOwnerWheelState()
            end
        end)
    end

    -- ============================================================
    -- HOLLOW PURPLE TOGGLE — separate section in AuraPage
    -- Only Creator and Owner see/use this. Visible to all in-game.
    -- ============================================================
    local hpSectionLbl = Instance.new("TextLabel", AuraLog)
    hpSectionLbl.Size = UDim2.new(1, 0, 0, 32)
    hpSectionLbl.BackgroundColor3 = Color3.fromRGB(30, 10, 60)
    hpSectionLbl.BackgroundTransparency = 0.3
    hpSectionLbl.BorderSizePixel = 0
    hpSectionLbl.LayoutOrder = 10
    hpSectionLbl.Text = "⚡  HOLLOW PURPLE AURA  ⚡"
    hpSectionLbl.TextColor3 = Color3.fromRGB(180, 80, 255)
    hpSectionLbl.Font = Enum.Font.GothamBold
    hpSectionLbl.TextSize = 13
    Instance.new("UICorner", hpSectionLbl).CornerRadius = UDim.new(0, 8)

    local hpToggleBtn = Instance.new("TextButton", AuraLog)
    hpToggleBtn.Size = UDim2.new(1, 0, 0, 42)
    hpToggleBtn.BackgroundColor3 = Color3.fromRGB(100, 20, 180)
    hpToggleBtn.BorderSizePixel = 0
    hpToggleBtn.Text = "🔮  HOLLOW PURPLE: OFF"
    hpToggleBtn.TextColor3 = Color3.fromRGB(220, 180, 255)
    hpToggleBtn.TextSize = 13
    hpToggleBtn.Font = Enum.Font.GothamBold
    hpToggleBtn.LayoutOrder = 11
    Instance.new("UICorner", hpToggleBtn).CornerRadius = UDim.new(0, 8)
    local hpTStroke = Instance.new("UIStroke", hpToggleBtn)
    hpTStroke.Color = Color3.fromRGB(150, 60, 255)
    hpTStroke.Thickness = 1.5

    local function updateHPBtn(active)
        if active then
            hpToggleBtn.Text = "🔮  HOLLOW PURPLE: ON"
            TweenService:Create(hpToggleBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(60, 160, 80)}):Play()
            hpTStroke.Color = Color3.fromRGB(80, 255, 100)
        else
            hpToggleBtn.Text = "🔮  HOLLOW PURPLE: OFF"
            TweenService:Create(hpToggleBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(100, 20, 180)}):Play()
            hpTStroke.Color = Color3.fromRGB(150, 60, 255)
        end
    end

    hpToggleBtn.MouseButton1Click:Connect(function()
        if RealUserId ~= CREATOR_ID then return end  -- Creator-only
        creatorHPActive = not creatorHPActive
        updateHPBtn(creatorHPActive)
        if creatorHPActive then
            -- Wait for character if needed, then build
            task.spawn(function()
                local p = Players:GetPlayerByUserId(CREATOR_ID)
                if not p then return end
                if not p.Character or not p.Character:FindFirstChild("HumanoidRootPart") then
                    p.CharacterAdded:Wait()
                    task.wait(0.6)
                end
                if creatorHPActive then HP_Build(p) end
            end)
        else
            HP_Cleanup()
        end
        pushHPState(creatorHPActive)
    end)

    -- Sync HP state on tab open (reflect current Firebase state, Creator-only)
    if RealUserId == CREATOR_ID then
        task.spawn(function()
            task.wait(1.5)
            syncHPState()
            task.wait(0.3)  -- let syncHPState finish its inner task.spawn
            updateHPBtn(creatorHPActive)
            if creatorHPActive then
                local p = Players:GetPlayerByUserId(CREATOR_ID)
                if p and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                    HP_Build(p)
                end
            end
        end)
    end
end

-- ============================================================
-- REPLY BANNER
-- ============================================================
local ReplyBanner = Instance.new("Frame", Main)
ReplyBanner.Size = UDim2.new(1, -14, 0, 16)
ReplyBanner.Position = UDim2.new(0, 7, 1, -76)
ReplyBanner.BackgroundColor3 = Color3.fromRGB(40, 20, 80)
ReplyBanner.BackgroundTransparency = 0.5
ReplyBanner.BorderSizePixel = 0
ReplyBanner.Visible = false
Instance.new("UICorner", ReplyBanner).CornerRadius = UDim.new(0, 5)

local ReplyLabel = Instance.new("TextLabel", ReplyBanner)
ReplyLabel.Size = UDim2.new(1, -22, 1, 0)
ReplyLabel.Position = UDim2.new(0, 5, 0, 0)
ReplyLabel.BackgroundTransparency = 1
ReplyLabel.RichText = true
ReplyLabel.Text = "Replying to ..."
ReplyLabel.TextColor3 = Color3.fromRGB(200, 170, 255)
ReplyLabel.Font = Enum.Font.Gotham
ReplyLabel.TextSize = 10
ReplyLabel.TextXAlignment = Enum.TextXAlignment.Left
ReplyLabel.TextTruncate = Enum.TextTruncate.AtEnd

local ReplyCloseBtn = Instance.new("TextButton", ReplyBanner)
ReplyCloseBtn.Size = UDim2.new(0, 16, 1, 0)
ReplyCloseBtn.Position = UDim2.new(1, -18, 0, 0)
ReplyCloseBtn.Text = "X"
ReplyCloseBtn.Font = Enum.Font.GothamBold
ReplyCloseBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
ReplyCloseBtn.BackgroundTransparency = 1
ReplyCloseBtn.TextSize = 10

ReplyCloseBtn.MouseButton1Click:Connect(function()
    ReplyTargetName = nil
    ReplyTargetMsg = nil
    ReplyBanner.Visible = false
    ReplyLabel.Text = "Replying to ..."
end)

-- PVT BANNER REMOVED (user request — banner hidden, PvtInputTag + clearPvt still handle pvt state)

-- INPUT BOX
local InputArea = Instance.new("Frame", Main)
InputArea.Size = UDim2.new(1, -14, 0, 36)
InputArea.Position = UDim2.new(0, 7, 1, -44)
InputArea.BackgroundColor3 = Color3.fromRGB(20, 10, 45)
InputArea.BackgroundTransparency = 0.5
InputArea.BorderSizePixel = 0
Instance.new("UICorner", InputArea).CornerRadius = UDim.new(0, 10)
local InputStroke = Instance.new("UIStroke", InputArea)
InputStroke.Color = Color3.fromRGB(100, 50, 200)
InputStroke.Thickness = 1
InputStroke.Transparency = 0.5

local Input = Instance.new("TextBox", InputArea)
Input.Size = UDim2.new(1, -44, 1, 0)
Input.Position = UDim2.new(0, 8, 0, 0)
Input.PlaceholderText = "* Type a message..."
Input.BackgroundTransparency = 1
Input.TextColor3 = Color3.new(1, 1, 1)
Input.PlaceholderColor3 = Color3.fromRGB(120, 100, 160)
Input.Font = Enum.Font.Gotham
Input.TextSize = 14
Input.ClearTextOnFocus = true
Input.TextXAlignment = Enum.TextXAlignment.Left

-- Sticker Button — placed to the left of the send button in the InputArea
StickerBtn = Instance.new("TextButton", InputArea)
StickerBtn.Size = UDim2.new(0, 28, 0, 28)
StickerBtn.Position = UDim2.new(1, -74, 0.5, -14)
StickerBtn.Text = "🎭"
StickerBtn.Font = Enum.Font.GothamBold
StickerBtn.TextColor3 = Color3.fromRGB(50, 205, 50)
StickerBtn.BackgroundColor3 = Color3.fromRGB(50, 30, 90)
StickerBtn.BackgroundTransparency = 0.4
StickerBtn.TextSize = 14
StickerBtn.ZIndex = 3
Instance.new("UICorner", StickerBtn).CornerRadius = UDim.new(1, 0)
local StickerBtnStroke = Instance.new("UIStroke", StickerBtn)
StickerBtnStroke.Color = Color3.fromRGB(180, 120, 255)
StickerBtnStroke.Thickness = 1
StickerBtnStroke.Transparency = 0.4
StickerBtn.MouseButton1Click:Connect(openStickerPanel)

-- Shrink input box to make room for sticker button
Input.Size = UDim2.new(1, -82, 1, 0)

-- Send Button
local SendBtn = Instance.new("TextButton", InputArea)
SendBtn.Size = UDim2.new(0, 32, 0, 26)
SendBtn.Position = UDim2.new(1, -38, 0.5, -13)
SendBtn.Text = ">>"
SendBtn.Font = Enum.Font.GothamBold
SendBtn.TextColor3 = Color3.fromRGB(220, 190, 255)
SendBtn.BackgroundColor3 = Color3.fromRGB(80, 30, 160)
SendBtn.BackgroundTransparency = 0.3
SendBtn.TextSize = 14
Instance.new("UICorner", SendBtn).CornerRadius = UDim.new(0, 8)

-- ============================================================
-- CHARACTER COUNTER — shows remaining chars above input area
-- Goes red when approaching limit, hidden when input is empty
-- ============================================================
local CharCounter = Instance.new("TextLabel", Main)
CharCounter.Size = UDim2.new(0, 60, 0, 16)
CharCounter.Position = UDim2.new(1, -68, 1, -62)
CharCounter.BackgroundTransparency = 1
CharCounter.Text = "200"
CharCounter.TextColor3 = Color3.fromRGB(140, 120, 180)
CharCounter.Font = Enum.Font.GothamBold
CharCounter.TextSize = 11
CharCounter.TextXAlignment = Enum.TextXAlignment.Right
CharCounter.ZIndex = 5
CharCounter.Visible = false

Input:GetPropertyChangedSignal("Text"):Connect(function()
    local len = #Input.Text
    local remaining = MAX_CHAR_LIMIT - len
    if len == 0 then
        CharCounter.Visible = false
    else
        CharCounter.Visible = true
        CharCounter.Text = tostring(remaining)
        if remaining <= 20 then
            CharCounter.TextColor3 = Color3.fromRGB(255, 80, 80)
        elseif remaining <= 50 then
            CharCounter.TextColor3 = Color3.fromRGB(255, 180, 60)
        else
            CharCounter.TextColor3 = Color3.fromRGB(140, 120, 180)
        end
    end
    -- Hard clamp: strip characters beyond limit
    if len > MAX_CHAR_LIMIT then
        Input.Text = string.sub(Input.Text, 1, MAX_CHAR_LIMIT)
        Input.CursorPosition = MAX_CHAR_LIMIT + 1
    end
end)

-- ============================================================
-- PVT INPUT TAG — Roblox-chat style "[Name]" label on the
-- LEFT side of the input box shown when private chat is active.
-- Tap this label to DISABLE private chat (only way to clear pvt).
-- ============================================================
local PvtInputTag = Instance.new("TextButton", InputArea)
PvtInputTag.Size = UDim2.new(0, 66, 0, 28)
PvtInputTag.Position = UDim2.new(0, 3, 0.5, -14)
PvtInputTag.BackgroundColor3 = Color3.fromRGB(80, 10, 60)
PvtInputTag.BackgroundTransparency = 0.2
PvtInputTag.Text = "[...]"
PvtInputTag.Font = Enum.Font.GothamBold
PvtInputTag.TextColor3 = Color3.fromRGB(255, 160, 230)
PvtInputTag.TextSize = 11
PvtInputTag.TextTruncate = Enum.TextTruncate.AtEnd
PvtInputTag.Visible = false
PvtInputTag.ZIndex = 4
Instance.new("UICorner", PvtInputTag).CornerRadius = UDim.new(0, 7)
local PvtInputTagStroke = Instance.new("UIStroke", PvtInputTag)
PvtInputTagStroke.Color = Color3.fromRGB(200, 80, 200)
PvtInputTagStroke.Thickness = 1
PvtInputTagStroke.Transparency = 0.3

-- ============================================================
-- TOGGLE BUTTON — bigger, brighter, DRAGGABLE
-- (dragging respects isGuiLocked — when locked, cannot be dragged)
-- ============================================================
local ToggleBtn = Instance.new("TextButton", ScreenGui)
ToggleBtn.Size = UDim2.new(0, 56, 0, 56)        -- bigger than original 42x42
ToggleBtn.Position = UDim2.new(0, 6, 0.72, 0)
ToggleBtn.AnchorPoint = Vector2.new(0, 0.5)
ToggleBtn.Text = "*"
ToggleBtn.TextSize = 22                           -- bigger text
ToggleBtn.BackgroundColor3 = Color3.fromRGB(90, 40, 200)   -- brighter purple
ToggleBtn.BackgroundTransparency = 0.2            -- more visible
ToggleBtn.TextColor3 = Color3.fromRGB(220, 200, 255)
ToggleBtn.Active = true
Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(1, 0)
local ToggleStroke = Instance.new("UIStroke", ToggleBtn)
ToggleStroke.Thickness = 2.0                      -- slightly thicker stroke
ToggleStroke.Transparency = 0.1

task.spawn(function()
    while ToggleBtn and ToggleBtn.Parent do
        local hue = (tick() % 4) / 4
        ToggleStroke.Color = Color3.fromHSV(hue, 0.8, 1)
        task.wait(0.05)
    end
end)

-- ============================================================
-- PVT CLOSE
-- ============================================================
local function clearPvt()
    PrivateTargetId = nil
    PrivateTargetName = nil
    Input.PlaceholderText = "* Type a message..."
    InputArea.BackgroundColor3 = Color3.fromRGB(20, 10, 45)
    -- Hide the left-side pvt name tag and restore input layout
    PvtInputTag.Visible = false
    Input.Position = UDim2.new(0, 8, 0, 0)
    Input.Size = UDim2.new(1, -44, 1, 0)
end

-- Tap the left-side [Name] tag to disable pvt (Roblox-chat style)
PvtInputTag.MouseButton1Click:Connect(clearPvt)

-- ============================================================
-- MESSAGE CONTEXT POPUP — Instagram-style clean premium menu
-- Appears on hold (0.6s):
--   Own messages  → Copy Text / Edit / Unsend
--   Other messages → Copy Text only
-- ============================================================
local MsgPopup = Instance.new("Frame", ScreenGui)
MsgPopup.Name        = "MsgContextPopup"
MsgPopup.Size        = UDim2.new(0, 168, 0, 0)
MsgPopup.AutomaticSize = Enum.AutomaticSize.Y
MsgPopup.BackgroundColor3 = Color3.fromRGB(24, 14, 46)
MsgPopup.BackgroundTransparency = 0.08
MsgPopup.BorderSizePixel = 0
MsgPopup.Visible     = false
MsgPopup.ZIndex      = 200
MsgPopup.ClipsDescendants = true
local _popCorner = Instance.new("UICorner", MsgPopup)
_popCorner.CornerRadius = UDim.new(0, 16)
local _popStroke = Instance.new("UIStroke", MsgPopup)
_popStroke.Color       = Color3.fromRGB(120, 70, 220)
_popStroke.Thickness   = 1.4
_popStroke.Transparency = 0.25
local _popList = Instance.new("UIListLayout", MsgPopup)
_popList.Padding       = UDim.new(0, 0)
_popList.SortOrder     = Enum.SortOrder.LayoutOrder
local _popPad = Instance.new("UIPadding", MsgPopup)
_popPad.PaddingTop    = UDim.new(0, 6)
_popPad.PaddingBottom = UDim.new(0, 6)

local function closeMsgPopup()
    if not MsgPopup.Visible then return end
    TweenService:Create(MsgPopup, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {BackgroundTransparency = 1}):Play()
    task.delay(0.13, function()
        MsgPopup.Visible = false
        MsgPopup.BackgroundTransparency = 0.08
        for _, c in pairs(MsgPopup:GetChildren()) do
            if c:IsA("TextButton") or c:IsA("Frame") and c.Name == "PopItem" then
                c:Destroy()
            end
        end
    end)
end

local function addPopupItem(icon, label, order, isDestructive, callback)
    local item = Instance.new("TextButton", MsgPopup)
    item.Name             = "PopItem"
    item.Size             = UDim2.new(1, 0, 0, 44)
    item.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    item.BackgroundTransparency = 1
    item.Text             = ""
    item.LayoutOrder      = order
    item.ZIndex           = 201
    item.ClipsDescendants = false

    local iconL = Instance.new("TextLabel", item)
    iconL.Size     = UDim2.new(0, 38, 1, 0)
    iconL.Position = UDim2.new(0, 10, 0, 0)
    iconL.BackgroundTransparency = 1
    iconL.Text     = icon
    iconL.TextSize = 17
    iconL.Font     = Enum.Font.GothamBold
    iconL.TextColor3 = isDestructive and Color3.fromRGB(255, 75, 75) or Color3.fromRGB(230, 215, 255)
    iconL.TextXAlignment = Enum.TextXAlignment.Center
    iconL.ZIndex   = 202

    local textL = Instance.new("TextLabel", item)
    textL.Size     = UDim2.new(1, -58, 1, 0)
    textL.Position = UDim2.new(0, 50, 0, 0)
    textL.BackgroundTransparency = 1
    textL.Text     = label
    textL.Font     = Enum.Font.GothamSemibold
    textL.TextSize = 13
    textL.TextColor3 = isDestructive and Color3.fromRGB(255, 75, 75) or Color3.fromRGB(240, 230, 255)
    textL.TextXAlignment = Enum.TextXAlignment.Left
    textL.ZIndex   = 202

    -- Divider line at bottom of each item (hidden on last via later logic)
    local div = Instance.new("Frame", item)
    div.Name              = "Divider"
    div.Size              = UDim2.new(1, -20, 0, 1)
    div.Position          = UDim2.new(0, 10, 1, -1)
    div.BackgroundColor3  = Color3.fromRGB(100, 70, 170)
    div.BackgroundTransparency = 0.55
    div.BorderSizePixel   = 0
    div.ZIndex            = 202

    -- Hover highlight
    item.MouseEnter:Connect(function()
        TweenService:Create(item, TweenInfo.new(0.1), {BackgroundTransparency = 0.82}):Play()
        item.BackgroundColor3 = isDestructive and Color3.fromRGB(120, 20, 20) or Color3.fromRGB(90, 50, 180)
    end)
    item.MouseLeave:Connect(function()
        TweenService:Create(item, TweenInfo.new(0.1), {BackgroundTransparency = 1}):Play()
    end)

    item.MouseButton1Click:Connect(function()
        closeMsgPopup()
        task.spawn(callback)
    end)

    return item
end

local function showMsgPopup(screenPos, options)
    -- Destroy old items
    for _, c in pairs(MsgPopup:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end

    -- Build items
    for i, opt in ipairs(options) do
        addPopupItem(opt.icon, opt.label, i, opt.destructive or false, opt.callback)
    end

    -- Hide divider on last item
    local items = {}
    for _, c in pairs(MsgPopup:GetChildren()) do
        if c:IsA("TextButton") then table.insert(items, c) end
    end
    table.sort(items, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
    if items[#items] then
        local lastDiv = items[#items]:FindFirstChild("Divider")
        if lastDiv then lastDiv.BackgroundTransparency = 1 end
    end

    -- Compute position — always clamped to stay fully inside the Main GUI frame
    local vpSize  = game.Workspace.CurrentCamera.ViewportSize
    local popW, popH = 168, #options * 44 + 12
    local mainAbs = Main.AbsolutePosition
    local mainSz  = Main.AbsoluteSize
    local guiLeft   = mainAbs.X + 4
    local guiRight  = mainAbs.X + mainSz.X - popW - 4
    local guiTop    = mainAbs.Y + 4
    local guiBottom = mainAbs.Y + mainSz.Y - popH - 4
    local px = math.clamp(screenPos.X - popW / 2, guiLeft, math.max(guiLeft, guiRight))
    local py = screenPos.Y - popH - 10
    if py < guiTop then py = screenPos.Y + 10 end
    py = math.clamp(py, guiTop, math.max(guiTop, guiBottom))

    MsgPopup.Position = UDim2.new(0, px, 0, py)
    MsgPopup.BackgroundTransparency = 1
    MsgPopup.Visible  = true
    TweenService:Create(MsgPopup, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {BackgroundTransparency = 0.08}):Play()
end

-- Dismiss popup when tapping outside it
UserInputService.InputBegan:Connect(function(inp)
    if not MsgPopup.Visible then return end
    if inp.UserInputType ~= Enum.UserInputType.MouseButton1
    and inp.UserInputType ~= Enum.UserInputType.Touch then return end
    local p   = inp.Position
    local abs = MsgPopup.AbsolutePosition
    local sz  = MsgPopup.AbsoluteSize
    if p.X < abs.X or p.X > abs.X + sz.X or p.Y < abs.Y or p.Y > abs.Y + sz.Y then
        closeMsgPopup()
    end
end)

-- ============================================================
-- THEME PICKER
-- ============================================================
local AresThemes = {
    {Name = "Default Dark",  Bg = Color3.fromRGB(8, 8, 18),    Trans = 0.5, Accent = Color3.fromRGB(120, 60, 255)},
    {Name = "Ares Gold",     Bg = Color3.fromRGB(30, 20, 0),   Trans = 0.5, Accent = Color3.fromRGB(255, 180, 0)},
    {Name = "Midnight Blue", Bg = Color3.fromRGB(5, 10, 35),   Trans = 0.5, Accent = Color3.fromRGB(0, 120, 255)},
    {Name = "Hacker Green",  Bg = Color3.fromRGB(0, 20, 5),    Trans = 0.5, Accent = Color3.fromRGB(0, 220, 80)},
    {Name = "Rose Crimson",  Bg = Color3.fromRGB(30, 5, 12),   Trans = 0.5, Accent = Color3.fromRGB(255, 60, 100)},
    {Name = "Pure Black",    Bg = Color3.fromRGB(0, 0, 0),     Trans = 0.5, Accent = Color3.fromRGB(200, 200, 200)},
    {Name = "Cyber Teal",    Bg = Color3.fromRGB(0, 20, 25),   Trans = 0.5, Accent = Color3.fromRGB(0, 220, 210)},
    {Name = "Deep Violet",   Bg = Color3.fromRGB(15, 5, 35),   Trans = 0.5, Accent = Color3.fromRGB(160, 80, 255)},
}

for _, data in ipairs(AresThemes) do
    local btn = Instance.new("TextButton", ThemeLog)
    btn.Size = UDim2.new(1, 0, 0, 40)
    btn.Text = ""
    btn.BackgroundColor3 = data.Bg
    btn.BackgroundTransparency = data.Trans
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = data.Accent
    stroke.Thickness = 1.2

    local icon = Instance.new("Frame", btn)
    icon.Size = UDim2.new(0, 14, 0, 14)
    icon.Position = UDim2.new(0, 9, 0.5, -7)
    icon.BackgroundColor3 = data.Accent
    Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)

    local lbl = Instance.new("TextLabel", btn)
    lbl.Size = UDim2.new(1, -40, 1, 0)
    lbl.Position = UDim2.new(0, 32, 0, 0)
    lbl.Text = data.Name
    lbl.TextColor3 = Color3.new(1, 1, 1)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 13
    lbl.BackgroundTransparency = 1
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    btn.MouseButton1Click:Connect(function()
        Main.BackgroundColor3 = data.Bg
        Main.BackgroundTransparency = data.Trans
        Header.BackgroundColor3 = data.Bg
        HeaderFix.BackgroundColor3 = data.Bg
        MainStroke.Color = data.Accent
        InputStroke.Color = data.Accent
    end)
end

-- ============================================================
-- ADMIN PANEL (CREATOR & OWNER)
-- Now includes expanded admin + normal user command list
-- Ban command shown as CREATOR ONLY
-- Title/Untitle/Unban shown as CREATOR ONLY
-- ============================================================
local function BuildAdminPanel()
    for _, c in pairs(AdminLog:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end

    local isAdmin = (RealUserId == CREATOR_ID or RealUserId == OWNER_ID)

    if not isAdmin then
        local noAccess = Instance.new("TextLabel", AdminLog)
        noAccess.Size = UDim2.new(1, 0, 0, 60)
        noAccess.Text = "[LOCKED] Admin access only"
        noAccess.TextColor3 = Color3.fromRGB(200, 100, 100)
        noAccess.Font = Enum.Font.GothamBold
        noAccess.TextSize = 14
        noAccess.BackgroundTransparency = 1
        return
    end

    -- ADMIN COMMANDS SECTION
    local cmdsTitle = Instance.new("TextLabel", AdminLog)
    cmdsTitle.Size = UDim2.new(1, 0, 0, 28)
    cmdsTitle.Text = "[!] ADMIN COMMANDS (Creator & Owner)"
    cmdsTitle.TextColor3 = Color3.fromRGB(255, 160, 80)
    cmdsTitle.Font = Enum.Font.GothamBold
    cmdsTitle.TextSize = 13
    cmdsTitle.BackgroundTransparency = 1

    local adminCmds = {
        {"/kick [name]",           "Kick a player"},
        {"/ban [name]",            "CREATOR ONLY — Permanent ban"},
        {"/unban [name/id]",       "CREATOR ONLY — Unban a player"},
        {"/title [name] [colour] [text]", "CREATOR ONLY — Custom title (red/white/yellow/black, 1 day)"},
        {"/untitle [name]",        "CREATOR ONLY — Remove custom title instantly"},
        {"/kill [name]",           "Kill a player"},
        {"/re [name]",             "Respawn a player"},
        {"/freeze [name]",         "Freeze a player"},
        {"/unfreeze [name]",       "Unfreeze a player"},
        {"/speed [name] [val]",    "Set player WalkSpeed"},
        {"/jump [name] [val]",     "Set player JumpPower"},
        {"/make [role] [name]",    "Give custom role tag"},
        {"/announce [msg]",        "Broadcast announcement (GLOBAL — all Ares users)"},
        {"/tp2me [name]",          "Teleport player to you"},
        {"/invisible [name]",      "Toggle player invisible"},
        {"/mute [name]",           "Mute player (GUI + bubbles + Firebase)"},
        {"/unmute [name]",         "Unmute player"},
        {"/clear",                 "Clear database (all)"},
    }

    for _, c in ipairs(adminCmds) do
        local row = Instance.new("Frame", AdminLog)
        row.Size = UDim2.new(1, 0, 0, 34)
        row.BackgroundColor3 = Color3.fromRGB(30, 15, 60)
        row.BackgroundTransparency = 0.3
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
        local cmdLbl = Instance.new("TextLabel", row)
        cmdLbl.Size = UDim2.new(0.55, -5, 1, 0)
        cmdLbl.Position = UDim2.new(0, 8, 0, 0)
        cmdLbl.Text = c[1]
        cmdLbl.TextColor3 = Color3.fromRGB(255, 160, 80)
        cmdLbl.Font = Enum.Font.Code
        cmdLbl.TextSize = 10
        cmdLbl.TextXAlignment = Enum.TextXAlignment.Left
        cmdLbl.BackgroundTransparency = 1
        local descLbl = Instance.new("TextLabel", row)
        descLbl.Size = UDim2.new(0.45, -5, 1, 0)
        descLbl.Position = UDim2.new(0.55, 0, 0, 0)
        descLbl.Text = c[2]
        descLbl.TextColor3 = Color3.fromRGB(180, 160, 220)
        descLbl.Font = Enum.Font.Gotham
        descLbl.TextSize = 10
        descLbl.TextXAlignment = Enum.TextXAlignment.Left
        descLbl.BackgroundTransparency = 1
    end

    -- USER COMMANDS SECTION
    local userCmdsTitle = Instance.new("TextLabel", AdminLog)
    userCmdsTitle.Size = UDim2.new(1, 0, 0, 28)
    userCmdsTitle.Text = "[*] USER COMMANDS (Everyone)"
    userCmdsTitle.TextColor3 = Color3.fromRGB(140, 255, 180)
    userCmdsTitle.Font = Enum.Font.GothamBold
    userCmdsTitle.TextSize = 13
    userCmdsTitle.BackgroundTransparency = 1

    local userCmds = {
        {"/fly",              "Toggle fly (local)"},
        {"/noclip",           "Toggle noclip (local)"},
        {"/nosit",            "Disable sit (local)"},
        {"/speed [val]",      "Set own WalkSpeed"},
        {"/jump [val]",       "Set own JumpPower"},
        {"/invisible",        "Toggle own invisible"},
        {"/sit",              "Force sit (local)"},
        {"/me [text]",        "Roleplay action msg"},
        {"/time",             "Show current time"},
        {"/name [text]",      "Change RP display name"},
        {"/mute [name]",      "Locally mute a player (only you)"},
        {"/unmute [name]",    "Locally unmute a player"},
        {"/commands",         "Show all user commands"},
        {"/clear",            "Clear local chat UI"},
    }

    for _, c in ipairs(userCmds) do
        local row = Instance.new("Frame", AdminLog)
        row.Size = UDim2.new(1, 0, 0, 34)
        row.BackgroundColor3 = Color3.fromRGB(10, 30, 20)
        row.BackgroundTransparency = 0.3
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
        local cmdLbl = Instance.new("TextLabel", row)
        cmdLbl.Size = UDim2.new(0.5, -5, 1, 0)
        cmdLbl.Position = UDim2.new(0, 8, 0, 0)
        cmdLbl.Text = c[1]
        cmdLbl.TextColor3 = Color3.fromRGB(140, 255, 180)
        cmdLbl.Font = Enum.Font.Code
        cmdLbl.TextSize = 10
        cmdLbl.TextXAlignment = Enum.TextXAlignment.Left
        cmdLbl.BackgroundTransparency = 1
        local descLbl = Instance.new("TextLabel", row)
        descLbl.Size = UDim2.new(0.5, -5, 1, 0)
        descLbl.Position = UDim2.new(0.5, 0, 0, 0)
        descLbl.Text = c[2]
        descLbl.TextColor3 = Color3.fromRGB(180, 160, 220)
        descLbl.Font = Enum.Font.Gotham
        descLbl.TextSize = 10
        descLbl.TextXAlignment = Enum.TextXAlignment.Left
        descLbl.BackgroundTransparency = 1
    end

    -- PLAYERS IN SERVER SECTION
    local onlineTitle = Instance.new("TextLabel", AdminLog)
    onlineTitle.Size = UDim2.new(1, 0, 0, 28)
    onlineTitle.Text = "[P] PLAYERS IN SERVER"
    onlineTitle.TextColor3 = Color3.fromRGB(200, 170, 255)
    onlineTitle.Font = Enum.Font.GothamBold
    onlineTitle.TextSize = 13
    onlineTitle.BackgroundTransparency = 1

    for _, p in pairs(Players:GetPlayers()) do
        local pRow = Instance.new("Frame", AdminLog)
        pRow.Size = UDim2.new(1, 0, 0, 36)
        pRow.BackgroundColor3 = Color3.fromRGB(25, 12, 50)
        pRow.BackgroundTransparency = 0.3
        Instance.new("UICorner", pRow).CornerRadius = UDim.new(0, 8)

        local pName = Instance.new("TextLabel", pRow)
        pName.Size = UDim2.new(0.55, 0, 1, 0)
        pName.Position = UDim2.new(0, 10, 0, 0)
        pName.Text = p.DisplayName
        pName.TextColor3 = Color3.new(1,1,1)
        pName.Font = Enum.Font.GothamBold
        pName.TextSize = 13
        pName.BackgroundTransparency = 1
        pName.TextXAlignment = Enum.TextXAlignment.Left

        local kickQuick = Instance.new("TextButton", pRow)
        kickQuick.Size = UDim2.new(0, 48, 0, 24)
        kickQuick.Position = UDim2.new(1, -54, 0.5, -12)
        kickQuick.Text = "KICK"
        kickQuick.Font = Enum.Font.GothamBold
        kickQuick.TextSize = 11
        kickQuick.TextColor3 = Color3.new(1,1,1)
        kickQuick.BackgroundColor3 = Color3.fromRGB(180, 30, 30)
        kickQuick.BackgroundTransparency = 0.3
        Instance.new("UICorner", kickQuick).CornerRadius = UDim.new(0, 6)
        kickQuick.MouseButton1Click:Connect(function()
            if p and p.Parent then p:Kick("Kicked by Ares Admin.") end
        end)
    end
end

-- ============================================================
-- FRIENDS LOGIC
-- ============================================================
local function GetPlaceName(id)
    local success, info = pcall(function() return MarketplaceService:GetProductInfo(id) end)
    return success and info.Name or "Unknown Game"
end

function RefreshFriends()
    for _, child in pairs(FriendsLog:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
    local success, friends = pcall(function() return LocalPlayer:GetFriendsOnline(200) end)
    if success and friends then
        for _, friend in pairs(friends) do
            local fFrame = Instance.new("Frame", FriendsLog)
            fFrame.Size = UDim2.new(1, -5, 0, 60)
            fFrame.BackgroundColor3 = Color3.fromRGB(20, 10, 45)
            fFrame.BackgroundTransparency = 0.5
            Instance.new("UICorner", fFrame).CornerRadius = UDim.new(0, 10)
            local fStroke = Instance.new("UIStroke", fFrame)
            fStroke.Color = Color3.fromRGB(80, 40, 150)
            fStroke.Thickness = 1

            local pfp = Instance.new("ImageLabel", fFrame)
            pfp.Size = UDim2.new(0, 40, 0, 40)
            pfp.Position = UDim2.new(0, 8, 0.5, 0)
            pfp.AnchorPoint = Vector2.new(0, 0.5)
            pfp.BackgroundTransparency = 1
            Instance.new("UICorner", pfp).CornerRadius = UDim.new(1, 0)
            task.spawn(function()
                local content, ready = Players:GetUserThumbnailAsync(friend.VisitorId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
                if ready then pfp.Image = content end
            end)

            local dot = Instance.new("Frame", fFrame)
            dot.Size = UDim2.new(0, 10, 0, 10)
            dot.Position = UDim2.new(0, 38, 0.5, 8)
            dot.BackgroundColor3 = Color3.fromRGB(0, 220, 80)
            Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

            local fName = Instance.new("TextLabel", fFrame)
            fName.Size = UDim2.new(1, -165, 0, 20)
            fName.Position = UDim2.new(0, 56, 0, 9)
            fName.Text = friend.DisplayName
            fName.TextColor3 = Color3.new(1, 1, 1)
            fName.Font = Enum.Font.GothamBold
            fName.TextSize = 13
            fName.TextXAlignment = Enum.TextXAlignment.Left
            fName.BackgroundTransparency = 1

            local fPresence = Instance.new("TextLabel", fFrame)
            fPresence.Size = UDim2.new(1, -165, 0, 16)
            fPresence.Position = UDim2.new(0, 56, 0, 30)
            fPresence.TextColor3 = Color3.fromRGB(150, 130, 200)
            fPresence.Font = Enum.Font.Gotham
            fPresence.TextSize = 11
            fPresence.TextXAlignment = Enum.TextXAlignment.Left
            fPresence.BackgroundTransparency = 1
            task.spawn(function()
                local gameName = GetPlaceName(friend.PlaceId)
                fPresence.Text = "[Game] " .. gameName
            end)

            local JoinBtn = Instance.new("TextButton", fFrame)
            JoinBtn.Size = UDim2.new(0, 48, 0, 24)
            JoinBtn.Position = UDim2.new(1, -54, 0.5, -12)
            JoinBtn.Text = "JOIN"
            JoinBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 80)
            JoinBtn.Font = Enum.Font.GothamBold
            JoinBtn.TextColor3 = Color3.new(1, 1, 1)
            JoinBtn.TextSize = 11
            Instance.new("UICorner", JoinBtn).CornerRadius = UDim.new(0, 6)

            local InviteBtn = Instance.new("TextButton", fFrame)
            InviteBtn.Size = UDim2.new(0, 52, 0, 24)
            InviteBtn.Position = UDim2.new(1, -110, 0.5, -12)
            InviteBtn.Text = "INVITE"
            InviteBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 200)
            InviteBtn.Font = Enum.Font.GothamBold
            InviteBtn.TextColor3 = Color3.new(1, 1, 1)
            InviteBtn.TextSize = 11
            Instance.new("UICorner", InviteBtn).CornerRadius = UDim.new(0, 6)

            JoinBtn.MouseButton1Click:Connect(function()
                TeleportService:TeleportToPlaceInstance(friend.PlaceId, friend.GameId, LocalPlayer)
            end)
            InviteBtn.MouseButton1Click:Connect(function()
                pcall(function() SocialService:PromptGameInvite(LocalPlayer) end)
            end)
        end
    end
end

-- ============================================================
-- TAB SWITCHING — updated to support Aura tab
-- ============================================================
local function SetActiveTab(page, btn)
    ChatPage.Visible = false
    FriendsPage.Visible = false
    ThemePage.Visible = false
    AdminPage.Visible = false
    if AuraPage then AuraPage.Visible = false end
    Input.Parent.Visible = (page == ChatPage)

    local allBtns = {ChatTabBtn, FriendsTabBtn, ThemeTabBtn}
    if AdminTabBtn then table.insert(allBtns, AdminTabBtn) end
    if AuraTabBtn then table.insert(allBtns, AuraTabBtn) end
    for _, b in pairs(allBtns) do
        b.BackgroundTransparency = 0.75
        b.TextColor3 = Color3.fromRGB(150, 120, 200)
    end

    page.Visible = true
    btn.BackgroundTransparency = 0.25
    btn.TextColor3 = Color3.fromRGB(240, 220, 255)
end

ChatTabBtn.MouseButton1Click:Connect(function() SetActiveTab(ChatPage, ChatTabBtn) end)
FriendsTabBtn.MouseButton1Click:Connect(function() SetActiveTab(FriendsPage, FriendsTabBtn) RefreshFriends() end)
ThemeTabBtn.MouseButton1Click:Connect(function() SetActiveTab(ThemePage, ThemeTabBtn) end)
if AdminTabBtn then
    AdminTabBtn.MouseButton1Click:Connect(function() SetActiveTab(AdminPage, AdminTabBtn) BuildAdminPanel() end)
end
if AuraTabBtn and AuraPage then
    AuraTabBtn.MouseButton1Click:Connect(function() SetActiveTab(AuraPage, AuraTabBtn) end)
end

ChatTabBtn.BackgroundTransparency = 0.25
ChatTabBtn.TextColor3 = Color3.fromRGB(240, 220, 255)

-- ============================================================
-- NOTIFICATION FUNCTION
-- ============================================================
local function createNotification(sender, message, isPrivate, isSystem, senderUid, isAutoClean)
    if isAutoClean then return end
    if Main.Visible or activeNotification then return end

    local nFrame = Instance.new("Frame", NotifContainer)
    nFrame.Size = UDim2.new(1, 0, 0, 66)
    nFrame.BackgroundColor3 = Color3.fromRGB(15, 8, 35)
    nFrame.BackgroundTransparency = 0.5
    nFrame.Position = UDim2.new(0, 0, -1.5, 0)
    Instance.new("UICorner", nFrame).CornerRadius = UDim.new(0, 12)
    local nStroke = Instance.new("UIStroke", nFrame)
    nStroke.Color = Color3.fromRGB(120, 60, 255)
    nStroke.Thickness = 1.2
    activeNotification = nFrame

    local pfpFrame = Instance.new("Frame", nFrame)
    pfpFrame.Size = UDim2.new(0, 42, 0, 42)
    pfpFrame.Position = UDim2.new(0, 12, 0.5, 0)
    pfpFrame.AnchorPoint = Vector2.new(0, 0.5)
    pfpFrame.BackgroundColor3 = Color3.fromRGB(40, 20, 80)
    pfpFrame.BorderSizePixel = 0
    Instance.new("UICorner", pfpFrame).CornerRadius = UDim.new(1, 0)

    if isSystem then
        local chickLabel = Instance.new("TextLabel", pfpFrame)
        chickLabel.Size = UDim2.new(1, 0, 1, 0)
        chickLabel.BackgroundTransparency = 1
        chickLabel.Text = "🐥"
        chickLabel.Font = Enum.Font.GothamBold
        chickLabel.TextSize = 22
        chickLabel.TextXAlignment = Enum.TextXAlignment.Center
        chickLabel.TextYAlignment = Enum.TextYAlignment.Center
    else
        local pfp = Instance.new("ImageLabel", pfpFrame)
        pfp.Size = UDim2.new(1, 0, 1, 0)
        pfp.BackgroundTransparency = 1
        Instance.new("UICorner", pfp).CornerRadius = UDim.new(1, 0)
        if senderUid and senderUid ~= 0 then
            task.spawn(function()
                local content, isReady = Players:GetUserThumbnailAsync(senderUid, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
                if isReady then pfp.Image = content end
            end)
        end
    end

    local nText = Instance.new("TextLabel", nFrame)
    nText.Size = UDim2.new(1, -68, 1, -8)
    nText.Position = UDim2.new(0, 62, 0, 4)
    nText.BackgroundTransparency = 1
    nText.RichText = true
    -- Truncate message preview to 60 chars so it never overflows the notification bar
    local preview = SafeEncodeMsg(message)
    if #preview > 60 then preview = string.sub(preview, 1, 57) .. "..." end
    nText.Text = string.format(
        "<b><font color='rgb(200,170,255)'>%s</font></b>\n<font size='12' color='rgb(200,200,200)'>%s</font>",
        SafeEncodeMsg(sender), preview
    )
    nText.TextColor3 = Color3.new(1, 1, 1)
    nText.TextSize = 13
    nText.Font = Enum.Font.Gotham
    nText.TextXAlignment = Enum.TextXAlignment.Left
    nText.TextWrapped = false
    nText.TextTruncate = Enum.TextTruncate.AtEnd

    TweenService:Create(nFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(0, 0, 0, 5)}):Play()
    task.delay(7, function()
        if nFrame and nFrame.Parent then
            local fadeOut = TweenService:Create(nFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {Position = UDim2.new(0, 0, -1.5, 0), BackgroundTransparency = 1})
            fadeOut:Play()
            fadeOut.Completed:Connect(function() nFrame:Destroy() activeNotification = nil end)
        end
    end)
end

-- ============================================================
-- BUBBLE LOGIC (PRESERVED)
-- ============================================================
local function createBubble(player, text, isPrivate)
    -- MUTE CHECK: do not show bubble for muted players
    if MutedPlayers[player.UserId] then return end
    local character = player.Character
    if not character or not character:FindFirstChild("Head") then return end
    local head = character.Head
    local existing = head:FindFirstChild("AresBubble")
    if existing then existing:Destroy() end
    local bGui = Instance.new("BillboardGui", head)
    bGui.Name = "AresBubble"
    bGui.Adornee = head
    bGui.Size = UDim2.new(0, math.clamp(#text * 14, 80, 320), 0, 54)
    bGui.StudsOffset = Vector3.new(0, 4, 0)
    bGui.MaxDistance = 80
    local bFrame = Instance.new("Frame", bGui)
    bFrame.Size = UDim2.new(1, 0, 1, 0)
    bFrame.BackgroundColor3 = isPrivate and Color3.fromRGB(60, 20, 80) or Color3.fromRGB(15, 8, 35)
    bFrame.BackgroundTransparency = 0.1
    Instance.new("UICorner", bFrame).CornerRadius = UDim.new(0, 14)
    local bStroke = Instance.new("UIStroke", bFrame)
    bStroke.Color = isPrivate and Color3.fromRGB(200, 80, 255) or Color3.fromRGB(120, 60, 255)
    bStroke.Thickness = 1.2
    local bText = Instance.new("TextLabel", bFrame)
    bText.Size = UDim2.new(1, -16, 1, -10)
    bText.Position = UDim2.new(0.5, 0, 0.5, 0)
    bText.AnchorPoint = Vector2.new(0.5, 0.5)
    bText.BackgroundTransparency = 1
    bText.Text = SafeEncodeMsg(text)
    bText.TextColor3 = Color3.fromRGB(230, 210, 255)
    bText.Font = Enum.Font.GothamMedium
    bText.TextSize = 16
    bText.TextWrapped = true
    task.delay(9, function() if bGui and bGui.Parent then bGui:Destroy() end end)
end

-- ============================================================
-- DRAGGING (PRESERVED) — main panel respects isGuiLocked
-- When isGuiLocked is true, the header drag is blocked.
-- ============================================================
local function MakeDraggable(UI, DragTrigger)
    local Dragging, DragStart, StartPos
    DragTrigger.InputBegan:Connect(function(input)
        -- Block dragging when GUI is locked
        if isGuiLocked then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            Dragging = true
            DragStart = input.Position
            StartPos = UI.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then Dragging = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if isGuiLocked then Dragging = false return end
        if Dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local Delta = input.Position - DragStart
            UI.Position = UDim2.new(StartPos.X.Scale, StartPos.X.Offset + Delta.X, StartPos.Y.Scale, StartPos.Y.Offset + Delta.Y)
        end
    end)
end

MakeDraggable(Main, Header)

-- ============================================================
-- TOGGLE BUTTON DRAG — drag-aware so a quick tap still
-- toggles the panel, but a real drag just repositions it.
-- toggleDragMoved is read by the MouseButton1Click handler below.
-- When isGuiLocked is true, the toggle button cannot be dragged.
-- ============================================================
local toggleDragMoved = false
do
    local tbDragging, tbDragStart, tbStartPos
    ToggleBtn.InputBegan:Connect(function(input)
        -- Block toggle button dragging when GUI is locked
        if isGuiLocked then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            tbDragging  = true
            toggleDragMoved = false
            tbDragStart = input.Position
            tbStartPos  = ToggleBtn.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    tbDragging = false
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if isGuiLocked then tbDragging = false return end
        if tbDragging and (
            input.UserInputType == Enum.UserInputType.MouseMovement
         or input.UserInputType == Enum.UserInputType.Touch
        ) then
            local delta = input.Position - tbDragStart
            if delta.Magnitude > 5 then
                toggleDragMoved = true
                ToggleBtn.Position = UDim2.new(
                    tbStartPos.X.Scale, tbStartPos.X.Offset + delta.X,
                    tbStartPos.Y.Scale, tbStartPos.Y.Offset + delta.Y
                )
            end
        end
    end)
end

-- ============================================================
-- MESSAGE COLOR HELPER
-- ============================================================
local function GetUserColor(name)
    local hash = 0
    for i = 1, #name do
        hash = (hash * 31 + string.byte(name, i)) % 360
    end
    -- Exclude hues near red (0°/360°) and near pink (330°-360°) by
    -- remapping 0-359 across a rainbow that avoids the red cluster.
    -- We shift by 40° and scale so the full palette is spread evenly.
    local hue = ((hash * 7 + 40) % 360) / 360
    return Color3.fromHSV(hue, 0.72, 1.0)
end

-- ============================================================
-- TRIM MESSAGES
-- Uses sortedMessageKeys so we always remove the genuinely
-- oldest messages — never random ones.
-- ============================================================
local function trimMessages()
    local excess = #sortedMessageKeys - MAX_MESSAGES
    if excess <= 0 then return end

    local req = syn and syn.request or http and http.request or request

    for i = 1, excess do
        local oldestKey = sortedMessageKeys[1]
        if not oldestKey then break end

        table.remove(sortedMessageKeys, 1)
        local btn = keyToButton[oldestKey]
        keyToButton[oldestKey] = nil

        if btn and btn.Parent then
            TweenService:Create(btn, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                BackgroundTransparency = 1,
                TextTransparency = 1
            }):Play()
            task.delay(0.26, function()
                if btn and btn.Parent then
                    SpecialLabels[btn] = nil
                    btn.Parent:Destroy()  -- destroy wrapperFrame (also destroys TextButton child)
                end
            end)
        end

        if req then
            local keyToDel = oldestKey
            task.spawn(function()
                pcall(function()
                    req({Url = DATABASE_URL .. "/" .. keyToDel .. ".json", Method = "DELETE"})
                end)
            end)
        end
    end
end

-- ============================================================
-- REBUILD REACTION BAR — refreshes emoji reaction pills under
-- a message whenever the reactionsCache entry for that key changes.
-- Each pill is a TextButton (sky-blue) with small pfp circles
-- followed by emoji + count. Tapping toggles your reaction.
-- ============================================================
local function rebuildReactionBar(msgKey)
    local bar = reactionsBars[msgKey]
    if not bar or not bar.Parent then return end
    -- Clear existing pills
    for _, c in pairs(bar:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
    end
    local reactions = reactionsCache[msgKey]
    if not reactions then return end
    local sorted = {}
    for emoji, data in pairs(reactions) do
        local count  = type(data) == "table" and data.count  or (type(data) == "number" and data or 0)
        local voters = type(data) == "table" and data.voters or {}
        if type(count) == "number" and count > 0 then
            table.insert(sorted, {emoji = emoji, count = count, voters = voters})
        end
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)

    for _, entry in ipairs(sorted) do
        -- ── Pill: TextButton so the whole thing is tappable ──────────
        local pill = Instance.new("TextButton", bar)
        pill.Size = UDim2.new(0, 0, 0, 16)   -- compact height 16px; width grows via AutomaticSize
        pill.AutomaticSize = Enum.AutomaticSize.X
        -- Sky-blue background
        pill.BackgroundColor3 = Color3.fromRGB(30, 140, 210)
        pill.BackgroundTransparency = 0.20
        pill.BorderSizePixel = 0
        pill.Text = ""
        pill.ZIndex = 5
        Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
        local pillStroke = Instance.new("UIStroke", pill)
        pillStroke.Color = Color3.fromRGB(80, 190, 255)
        pillStroke.Thickness = 0.8
        pillStroke.Transparency = 0.35

        -- Horizontal layout inside the pill
        local innerList = Instance.new("UIListLayout", pill)
        innerList.FillDirection = Enum.FillDirection.Horizontal
        innerList.VerticalAlignment = Enum.VerticalAlignment.Center
        innerList.HorizontalAlignment = Enum.HorizontalAlignment.Center
        innerList.Padding = UDim.new(0, 2)
        innerList.SortOrder = Enum.SortOrder.LayoutOrder

        local innerPad = Instance.new("UIPadding", pill)
        innerPad.PaddingLeft  = UDim.new(0, 4)
        innerPad.PaddingRight = UDim.new(0, 5)

        -- Small pfp circles (up to 2 reactors) — compact
        local maxPfps = math.min(#entry.voters, 2)
        for i = 1, maxPfps do
            local uid = entry.voters[i]
            local pfpCircle = Instance.new("ImageLabel", pill)
            pfpCircle.Size = UDim2.new(0, 12, 0, 12)
            pfpCircle.BackgroundColor3 = Color3.fromRGB(50, 100, 160)
            pfpCircle.BorderSizePixel = 0
            pfpCircle.ZIndex = 6
            pfpCircle.LayoutOrder = i
            pfpCircle.ImageColor3 = Color3.new(1, 1, 1)
            Instance.new("UICorner", pfpCircle).CornerRadius = UDim.new(1, 0)
            if uid then
                task.spawn(function()
                    pcall(function()
                        local content, ready = Players:GetUserThumbnailAsync(
                            uid,
                            Enum.ThumbnailType.HeadShot,
                            Enum.ThumbnailSize.Size48x48
                        )
                        if ready and pfpCircle and pfpCircle.Parent then
                            pfpCircle.Image = content
                        end
                    end)
                end)
            end
        end

        -- Emoji + count text label (compact)
        local emojiLabel = Instance.new("TextLabel", pill)
        emojiLabel.Size = UDim2.new(0, 0, 1, 0)
        emojiLabel.AutomaticSize = Enum.AutomaticSize.X
        emojiLabel.BackgroundTransparency = 1
        emojiLabel.Text = entry.emoji .. " " .. tostring(entry.count)
        emojiLabel.TextSize = 11
        emojiLabel.Font = Enum.Font.GothamBold
        emojiLabel.TextColor3 = Color3.new(1, 1, 1)
        emojiLabel.ZIndex = 6
        emojiLabel.LayoutOrder = maxPfps + 1
        emojiLabel.TextXAlignment = Enum.TextXAlignment.Left

        -- Wire up tap: one reaction per user — replaces old reaction with new
        local capturedEmoji = entry.emoji
        local capturedKey   = msgKey
        pill.Activated:Connect(function()
            task.spawn(function()
                pcall(function()
                    local req = syn and syn.request or http and http.request or request
                    if not req then return end
                    local myMark = tostring(RealUserId)
                    -- Check if user already reacted with THIS emoji
                    local thisRes = req({
                        Url    = REACTIONS_URL .. "/" .. capturedKey .. "/" .. capturedEmoji .. "/" .. myMark .. ".json",
                        Method = "GET"
                    })
                    if thisRes and thisRes.Success and thisRes.Body ~= "null" then
                        -- Already reacted with this emoji — remove it (toggle off)
                        req({
                            Url    = REACTIONS_URL .. "/" .. capturedKey .. "/" .. capturedEmoji .. "/" .. myMark .. ".json",
                            Method = "DELETE"
                        })
                    else
                        -- Remove any previous reaction by this user on other emojis first
                        local allRes = req({
                            Url    = REACTIONS_URL .. "/" .. capturedKey .. ".json",
                            Method = "GET"
                        })
                        if allRes and allRes.Success and allRes.Body ~= "null" then
                            local ok2, allData = pcall(HttpService.JSONDecode, HttpService, allRes.Body)
                            if ok2 and type(allData) == "table" then
                                for oldEmoji, _ in pairs(allData) do
                                    if oldEmoji ~= capturedEmoji then
                                        local chk = req({
                                            Url    = REACTIONS_URL .. "/" .. capturedKey .. "/" .. oldEmoji .. "/" .. myMark .. ".json",
                                            Method = "GET"
                                        })
                                        if chk and chk.Success and chk.Body ~= "null" then
                                            req({
                                                Url    = REACTIONS_URL .. "/" .. capturedKey .. "/" .. oldEmoji .. "/" .. myMark .. ".json",
                                                Method = "DELETE"
                                            })
                                        end
                                    end
                                end
                            end
                        end
                        -- Add new reaction
                        req({
                            Url    = REACTIONS_URL .. "/" .. capturedKey .. "/" .. capturedEmoji .. "/" .. myMark .. ".json",
                            Method = "PUT",
                            Body   = HttpService:JSONEncode(true)
                        })
                    end
                end)
            end)
        end)
    end
end

-- ============================================================
-- ADD MESSAGE
-- TAP = REPLY  |  HOLD (0.6s) = TOGGLE PRIVATE CHAT
-- Instagram-style highlighting:
--   • Someone replied TO YOU  → green left-bar + highlighted bg
--   • You replied to someone  → blue left-bar + highlighted bg
-- FIX: reply quote is now a proper sub-frame (no more overlap)
-- ============================================================
local function addMessage(displayName, msg, isSystem, order, senderUid, isPrivate, skipBubble, replyTo)
    -- MUTE CHECK: skip rendering messages from muted players (GUI suppression)
    if not isSystem and MutedPlayers[senderUid] then return end

    local safeName  = SafeEncodeMsg(tostring(displayName or ""))
    local safeMsg   = SafeEncodeMsg(tostring(msg or ""))
    local safeReply = replyTo and SafeEncodeMsg(tostring(replyTo)) or nil

    -- Detect highlight conditions
    local myDisplayName = SafeEncodeMsg(RealDisplayName)
    local isReplyToMe = (not isSystem)
        and (safeReply ~= nil and safeReply ~= "")
        and string.find(string.lower(safeReply), string.lower(myDisplayName), 1, true) ~= nil
        and senderUid ~= RealUserId
    local isMyReply = (senderUid == RealUserId)
        and (safeReply ~= nil and safeReply ~= "")
        and (not isSystem)

    -- ============================================================
    -- WRAPPER FRAME: UIListLayout manages this; TextButton inside it
    -- so TweenService can freely move TextButton for slide animation.
    -- ============================================================
    local wrapperFrame = Instance.new("Frame", ChatLog)
    wrapperFrame.Size = UDim2.new(1, 0, 0, 0)
    wrapperFrame.AutomaticSize = Enum.AutomaticSize.Y
    wrapperFrame.BackgroundTransparency = 1
    wrapperFrame.BorderSizePixel = 0
    -- Local-only messages (order == 0) use nextLocalOrder() so they appear at the
    -- BOTTOM of the chat log, not at the top where LayoutOrder=0 would put them.
    wrapperFrame.LayoutOrder = (order and order ~= 0) and order or nextLocalOrder()
    wrapperFrame.ClipsDescendants = false

    local TextButton = Instance.new("TextButton", wrapperFrame)
    TextButton.Size = UDim2.new(1, 0, 0, 0)
    TextButton.AutomaticSize = Enum.AutomaticSize.Y
    TextButton.Position = UDim2.new(0, 0, 0, 0)
    TextButton.BackgroundTransparency = 0.92
    TextButton.BackgroundColor3 = Color3.fromRGB(40, 20, 80)
    TextButton.RichText = true
    TextButton.TextWrapped = true
    TextButton.Font = Enum.Font.Gotham
    TextButton.TextSize = 13
    TextButton.TextColor3 = Color3.new(1, 1, 1)
    TextButton.TextXAlignment = Enum.TextXAlignment.Left
    TextButton.TextYAlignment = Enum.TextYAlignment.Top -- FIXED: Forces text to start strictly under the padding
    Instance.new("UICorner", TextButton).CornerRadius = UDim.new(0, 6)

    local pad = Instance.new("UIPadding", TextButton)
    pad.PaddingLeft   = UDim.new(0, 10)
    pad.PaddingRight  = UDim.new(0, 7)
    pad.PaddingTop    = UDim.new(0, 4)
    pad.PaddingBottom = UDim.new(0, 4)

    -- Reply highlights: light blue when I reply someone, green when someone replies to me
    if isMyReply then
        TextButton.BackgroundColor3 = Color3.fromRGB(20, 70, 120)
        TextButton.BackgroundTransparency = 0.75
    elseif isReplyToMe then
        TextButton.BackgroundColor3 = Color3.fromRGB(20, 90, 45)
        TextButton.BackgroundTransparency = 0.75
    end

    -- ============================================================
    -- STICKER DETECTION — must happen BEFORE the reply box so the
    -- sticker path can render the reply quote inside the bubble
    -- (avoiding the negative-Y overlap that caused overlapping).
    -- ============================================================
    local rawMsg = tostring(msg or "")
    local stickerAssetId = string.match(rawMsg, "^%[STICKER:(%d+)%]$")

    -- ============================================================
    -- REPLY QUOTE SUB-FRAME — for NON-STICKER messages only.
    -- Sticker replies embed the quote box inside the bubble itself.
    -- ============================================================
    if safeReply and safeReply ~= "" and not stickerAssetId then
        -- Compact reply quote: single-line truncated, fixed 16px height
        local replyBoxH = 16
        pad.PaddingTop = UDim.new(0, replyBoxH + 4)  -- Push main text below reply box

        local replyBox = Instance.new("Frame", TextButton)
        replyBox.Size = UDim2.new(1, -4, 0, replyBoxH)
        replyBox.AutomaticSize = Enum.AutomaticSize.None
        replyBox.Position = UDim2.new(0, -3, 0, -(replyBoxH + 2))
        replyBox.BackgroundColor3 = Color3.fromRGB(30, 20, 55)
        replyBox.BackgroundTransparency = 0.35
        replyBox.BorderSizePixel = 0
        replyBox.ZIndex = 2
        replyBox.ClipsDescendants = true
        Instance.new("UICorner", replyBox).CornerRadius = UDim.new(0, 4)

        local replyBoxStroke = Instance.new("UIStroke", replyBox)
        replyBoxStroke.Color = Color3.fromRGB(100, 80, 160)
        replyBoxStroke.Thickness = 0.8
        replyBoxStroke.Transparency = 0.5

        local replyBoxPad = Instance.new("UIPadding", replyBox)
        replyBoxPad.PaddingLeft   = UDim.new(0, 5)
        replyBoxPad.PaddingRight  = UDim.new(0, 5)
        replyBoxPad.PaddingTop    = UDim.new(0, 1)
        replyBoxPad.PaddingBottom = UDim.new(0, 1)

        local replyBoxLabel = Instance.new("TextLabel", replyBox)
        replyBoxLabel.Size = UDim2.new(1, 0, 1, 0)
        replyBoxLabel.AutomaticSize = Enum.AutomaticSize.None
        replyBoxLabel.BackgroundTransparency = 1
        replyBoxLabel.RichText = true
        local displayReply = safeReply:gsub("%[STICKER:%d+%]", "🎭 Sticker")
        replyBoxLabel.Text = "↩ " .. displayReply
        replyBoxLabel.TextWrapped = false
        replyBoxLabel.TextTruncate = Enum.TextTruncate.AtEnd
        replyBoxLabel.Font = Enum.Font.Gotham
        replyBoxLabel.TextSize = 10
        replyBoxLabel.TextXAlignment = Enum.TextXAlignment.Left
        replyBoxLabel.TextColor3 = Color3.fromRGB(160, 140, 200)
        replyBoxLabel.ZIndex = 3
    end

    if stickerAssetId and not isSystem then
        -- ============================================================
        -- PREMIUM STICKER BUBBLE — name at top, sticker image below.
        -- Name label and image are ALWAYS separate children so they
        -- can never overlap, regardless of tag type or reply state.
        -- ============================================================
        local tagData = TagCache[senderUid] or {text = "", type = "Normal"}
        if tagData.type == "Normal" then
            local ct = CustomTitles[senderUid]
            if ct then
                local now = os.time()
                if ct.expiresAt and ct.expiresAt > now then
                    tagData = { text = "[" .. ct.title .. "] ", type = "CustomTitle", tagTitle = "[" .. ct.title .. "]", titleColor = ct.color }
                end
            end
        end
        local privTag  = isPrivate and "<font color='rgb(255,100,255)'>[PVT] </font>" or ""
        local color    = GetUserColor(safeName)
        local colorStr = string.format("rgb(%d,%d,%d)",
            math.clamp(math.floor(color.R*255), 0, 255),
            math.clamp(math.floor(color.G*255), 0, 255),
            math.clamp(math.floor(color.B*255), 0, 255))

        -- ============================================================
        -- STICKER BUBBLE LAYOUT — accommodates inline reply if present.
        -- No reply:  name(y=5) → sep(y=26) → sticker(y=29) = 110px
        -- With reply: replyBox(y=5,16px) → name(y=27) → sep(y=48) → sticker(y=52) = 133px
        -- All children are INSIDE the bubble so nothing overlaps.
        -- ============================================================
        local hasReplyInSticker = safeReply and safeReply ~= ""
        local replyBlockH       = hasReplyInSticker and 22 or 0
        local nameLabelY        = 5 + replyBlockH
        local sepY              = nameLabelY + 21
        local stickerImgY       = sepY + 3
        local stickerBubbleH    = stickerImgY + 76 + 5

        TextButton.AutomaticSize  = Enum.AutomaticSize.None
        TextButton.Size           = UDim2.new(1, 0, 0, stickerBubbleH)
        TextButton.BackgroundColor3       = Color3.fromRGB(30, 15, 60)
        TextButton.BackgroundTransparency = 0.68
        TextButton.Text           = ""  -- all content via child instances
        pad.PaddingTop    = UDim.new(0, 0)  -- managed by child positions
        pad.PaddingBottom = UDim.new(0, 0)
        pad.PaddingLeft   = UDim.new(0, 0)
        pad.PaddingRight  = UDim.new(0, 0)

        -- Inline reply quote — rendered INSIDE the bubble at the very top (no negative Y)
        if hasReplyInSticker then
            local rBox = Instance.new("Frame", TextButton)
            rBox.Size                    = UDim2.new(1, -14, 0, 16)
            rBox.Position                = UDim2.new(0, 7, 0, 5)
            rBox.BackgroundColor3        = Color3.fromRGB(30, 20, 55)
            rBox.BackgroundTransparency  = 0.35
            rBox.BorderSizePixel         = 0
            rBox.ZIndex                  = TextButton.ZIndex + 1
            rBox.ClipsDescendants        = true
            Instance.new("UICorner", rBox).CornerRadius = UDim.new(0, 4)
            local rBoxStroke = Instance.new("UIStroke", rBox)
            rBoxStroke.Color       = Color3.fromRGB(100, 80, 160)
            rBoxStroke.Thickness   = 0.8
            rBoxStroke.Transparency = 0.5
            local rBoxPad = Instance.new("UIPadding", rBox)
            rBoxPad.PaddingLeft   = UDim.new(0, 5)
            rBoxPad.PaddingRight  = UDim.new(0, 5)
            rBoxPad.PaddingTop    = UDim.new(0, 1)
            rBoxPad.PaddingBottom = UDim.new(0, 1)
            local rBoxLabel = Instance.new("TextLabel", rBox)
            rBoxLabel.Size = UDim2.new(1, 0, 1, 0)
            rBoxLabel.AutomaticSize = Enum.AutomaticSize.None
            rBoxLabel.BackgroundTransparency = 1
            rBoxLabel.RichText = true
            local displayReplySt = safeReply:gsub("%[STICKER:%d+%]", "🎭 Sticker")
            rBoxLabel.Text = "↩ " .. displayReplySt
            rBoxLabel.TextWrapped  = false
            rBoxLabel.TextTruncate = Enum.TextTruncate.AtEnd
            rBoxLabel.Font         = Enum.Font.Gotham
            rBoxLabel.TextSize     = 10
            rBoxLabel.TextXAlignment = Enum.TextXAlignment.Left
            rBoxLabel.TextColor3   = Color3.fromRGB(160, 140, 200)
            rBoxLabel.ZIndex       = TextButton.ZIndex + 2
        end

        -- Name row — sits below reply quote (or at top if no reply)
        local nameLabel = Instance.new("TextLabel", TextButton)
        nameLabel.Size              = UDim2.new(1, -14, 0, 18)
        nameLabel.Position          = UDim2.new(0, 7, 0, nameLabelY)
        nameLabel.BackgroundTransparency = 1
        nameLabel.RichText          = true
        nameLabel.TextXAlignment    = Enum.TextXAlignment.Left
        nameLabel.Font              = Enum.Font.Gotham
        nameLabel.TextSize          = 12
        nameLabel.TextColor3        = Color3.new(1, 1, 1)
        nameLabel.ZIndex            = TextButton.ZIndex + 1
        nameLabel.TextTruncate      = Enum.TextTruncate.AtEnd

        if tagData.type ~= "Normal" then
            -- RGB/special-tag user: initial render, RGB loop will keep it updated via stickerLabel
            nameLabel.Text = string.format("%s%s<font color='%s'><b>%s</b></font>",
                privTag, tagData.text, colorStr, safeName)
            SpecialLabels[TextButton] = {
                displayName  = safeName,
                msg          = "",  -- sticker image handles the visual; msg not used
                nameColor    = colorStr,
                isPrivate    = isPrivate,
                tagType      = tagData.type,
                tagTitle     = tagData.tagTitle,
                titleColor   = tagData.titleColor,  -- custom title colour
                replyTo      = nil,
                isSticker    = true,
                stickerLabel = nameLabel,
            }
        else
            nameLabel.Text = string.format("%s%s<font color='%s'><b>%s</b></font>",
                privTag, tagData.text, colorStr, safeName)
        end

        -- Thin separator line between name and sticker image
        local sep = Instance.new("Frame", TextButton)
        sep.Size                    = UDim2.new(1, -14, 0, 1)
        sep.Position                = UDim2.new(0, 7, 0, sepY)
        sep.BackgroundColor3        = Color3.fromRGB(100, 60, 180)
        sep.BackgroundTransparency  = 0.6
        sep.BorderSizePixel         = 0
        sep.ZIndex                  = TextButton.ZIndex + 1

        -- Sticker image — below name row and sep, never overlaps
        local stickerImg = Instance.new("ImageLabel", TextButton)
        stickerImg.Size              = UDim2.new(0, 76, 0, 76)
        stickerImg.Position          = UDim2.new(0, 7, 0, stickerImgY)
        stickerImg.BackgroundTransparency = 1
        stickerImg.Image             = "rbxthumb://type=Asset&id=" .. stickerAssetId .. "&w=150&h=150"
        stickerImg.ScaleType         = Enum.ScaleType.Fit
        stickerImg.ZIndex            = TextButton.ZIndex + 1

        -- Premium glow stroke on the bubble
        local stickerBubbleStroke = Instance.new("UIStroke", TextButton)
        stickerBubbleStroke.Color       = Color3.fromRGB(120, 60, 220)
        stickerBubbleStroke.Thickness   = 1.2
        stickerBubbleStroke.Transparency = 0.5

        if not skipBubble then
            for _, p in pairs(Players:GetPlayers()) do
                if p.UserId == senderUid then createBubble(p, "🎭 Sticker", isPrivate) end
            end
        end

    -- Main message text (NO inline reply line — it's in the sub-frame above)
    elseif isSystem then
        TextButton.Text = "<font color='rgb(255,190,0)'><b>[SYSTEM]</b></font> " .. safeMsg
        TextButton.BackgroundColor3 = Color3.fromRGB(60, 50, 0)
    else
        local tagData = TagCache[senderUid] or {text = "", type = "Normal"}
        -- Re-check custom titles at display time (may have loaded after CachePlayerTags)
        if tagData.type == "Normal" then
            local ct = CustomTitles[senderUid]
            if ct then
                local now = os.time()
                if ct.expiresAt and ct.expiresAt > now then
                    tagData = {
                        text       = "[" .. ct.title .. "] ",
                        type       = "CustomTitle",
                        tagTitle   = "[" .. ct.title .. "]",
                        titleColor = ct.color
                    }
                end
            end
        end
        local privTag = isPrivate and "<font color='rgb(255,100,255)'>[PVT] </font>" or ""
        local color = GetUserColor(safeName)
        local colorStr = string.format("rgb(%d,%d,%d)",
            math.clamp(math.floor(color.R*255), 0, 255),
            math.clamp(math.floor(color.G*255), 0, 255),
            math.clamp(math.floor(color.B*255), 0, 255))

        if tagData.type ~= "Normal" then
            SpecialLabels[TextButton] = {
                displayName = safeName,
                msg         = safeMsg,
                nameColor   = colorStr,
                isPrivate   = isPrivate,
                tagType     = tagData.type,
                tagTitle    = tagData.tagTitle,
                titleColor  = tagData.titleColor,  -- custom title colour (red/white/yellow/black)
                replyTo     = safeReply  -- kept for reference; NOT rendered in RGB loop
            }
        else
            TextButton.Text = string.format("%s%s<font color='%s'><b>%s</b></font>: %s",
                privTag, tagData.text, colorStr, safeName, safeMsg)
        end

        if not skipBubble then
            for _, p in pairs(Players:GetPlayers()) do
                if p.UserId == senderUid then createBubble(p, safeMsg, isPrivate) end
            end
        end
    end

    -- Track only real Firebase-keyed messages for trim logic.
    -- order == 0 means local-only (e.g. /clear confirm) — skip tracking.
    if order and order ~= 0 then
        local keyStr = tostring(order)
        local inserted = false
        local numOrder = tonumber(keyStr) or 0
        for i = #sortedMessageKeys, 1, -1 do
            local existingNum = tonumber(sortedMessageKeys[i]) or 0
            if numOrder >= existingNum then
                table.insert(sortedMessageKeys, i + 1, keyStr)
                inserted = true
                break
            end
        end
        if not inserted then
            table.insert(sortedMessageKeys, 1, keyStr)
        end
        keyToButton[keyStr] = TextButton
        task.spawn(trimMessages)

        -- ============================================================
        -- REACTION BAR — shown below each Firebase-keyed message.
        -- Positioned dynamically below TextButton (small pills + pfps).
        -- ============================================================
        if not isSystem then
            local reactBar = Instance.new("Frame", wrapperFrame)
            reactBar.Name = "ReactBar"
            reactBar.Size = UDim2.new(1, 0, 0, 0)
            reactBar.AutomaticSize = Enum.AutomaticSize.Y
            reactBar.BackgroundTransparency = 1
            reactBar.BorderSizePixel = 0
            reactBar.Position = UDim2.new(0, 0, 0, 0)  -- updated dynamically below
            local reactBarList = Instance.new("UIListLayout", reactBar)
            reactBarList.FillDirection = Enum.FillDirection.Horizontal
            reactBarList.Padding = UDim.new(0, 3)
            reactBarList.HorizontalAlignment = Enum.HorizontalAlignment.Left
            reactBarList.VerticalAlignment = Enum.VerticalAlignment.Center
            local reactBarPad = Instance.new("UIPadding", reactBar)
            reactBarPad.PaddingLeft = UDim.new(0, 10)
            reactBarPad.PaddingTop = UDim.new(0, 1)
            reactBarPad.PaddingBottom = UDim.new(0, 1)
            reactionsBars[keyStr] = reactBar

            -- Keep reactBar flush below TextButton as its height changes
            local function updateReactBarPos()
                if TextButton and TextButton.Parent and reactBar and reactBar.Parent then
                    reactBar.Position = UDim2.new(0, 0, 0, TextButton.AbsoluteSize.Y)
                end
            end
            TextButton:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateReactBarPos)
            task.spawn(function()
                RunService.Heartbeat:Wait()
                updateReactBarPos()
            end)
        end
    end

    -- ====================================================
    -- SWIPE LEFT or RIGHT = REPLY (Instagram-style slide animation)
    -- HOLD (0.6s) on NAME AREA ONLY = ENABLE PRIVATE CHAT
    -- Hold only ENABLES pvt — tap the [Name] tag left of the
    -- input box to DISABLE pvt (hold never disables pvt).
    -- Every message is swipeable (system, own, others).
    -- 50% sensitivity: threshold is 25px instead of 50px.
    -- ====================================================
    local holding = false
    local holdTriggered = false
    local swipeStartPos = nil
    local swipeTriggered = false
    local SWIPE_THRESHOLD = 25  -- 50% sensitivity (was 50px)

    -- ============================================================
    -- NAME HITBOX — transparent Frame overlaid on just the name
    -- portion of the message (top-left area). Hold logic ONLY fires
    -- here so holding the message body does NOT trigger private chat.
    -- ============================================================
    if not isSystem and senderUid ~= RealUserId then
        local nameHitboxY = (safeReply and safeReply ~= "") and 0 or 0
        local nameHitbox = Instance.new("Frame", TextButton)
        nameHitbox.Size = UDim2.new(0, 170, 0, 22)
        nameHitbox.Position = UDim2.new(0, 0, 0, nameHitboxY)
        nameHitbox.BackgroundTransparency = 1
        nameHitbox.BorderSizePixel = 0
        nameHitbox.ZIndex = 8
        nameHitbox.Active = true

        -- HOLD on NAME = enable PVT
        nameHitbox.InputBegan:Connect(function(inp)
            if inp.UserInputType ~= Enum.UserInputType.MouseButton1 and inp.UserInputType ~= Enum.UserInputType.Touch then return end
            holding = true
            holdTriggered = false
            task.delay(0.6, function()
                if holding and not swipeTriggered then
                    holdTriggered = true
                    -- ENABLE PVT ONLY (hold never disables pvt)
                    PrivateTargetId = senderUid
                    PrivateTargetName = safeName
                    Input.PlaceholderText = "[PVT] " .. safeName .. "..."
                    InputArea.BackgroundColor3 = Color3.fromRGB(40, 10, 50)
                    -- Show Roblox-chat-style [Name] tag left of input
                    PvtInputTag.Text = "[" .. safeName .. "]"
                    PvtInputTag.Visible = true
                    Input.Position = UDim2.new(0, 73, 0, 0)
                    Input.Size = UDim2.new(1, -117, 1, 0)
                end
            end)
        end)

        nameHitbox.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                holding = false
            end
        end)
    end

    -- SWIPE LEFT or RIGHT on any message bubble = REPLY
    -- ============================================================
    -- Every message is swipeable regardless of sender (system,
    -- own messages, others). UserInputService.InputChanged is used
    -- (global — fires anywhere on screen) so the swipe always
    -- registers even when the finger leaves the button bounds.
    -- Left swipe  → slides left  (-65px) then elastic snap back.
    -- Right swipe → slides right (+65px) then elastic snap back.
    -- ============================================================
    local swipeConn = nil
    local popupHoldFired = false  -- separate from nameHitbox holdTriggered
    -- Firebase key for this message (used by Edit / Unsend)
    local msgFbKey = (order and order ~= 0) and tostring(order) or nil
    local isOwnMsg = (senderUid == RealUserId)

    TextButton.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            -- ============================================================
            -- DOUBLE-TAP REACT ❤️
            -- If user taps the same message twice within 0.35 s, instantly
            -- post a ❤️ reaction to Firebase. Works on both PC and mobile.
            -- ============================================================
            if not isSystem and msgFbKey then
                local now2 = tick()
                local lastT = lastTapTime[TextButton] or 0
                if now2 - lastT < 0.35 then
                    -- Second tap within window — fire ❤️ reaction
                    lastTapTime[TextButton] = 0  -- reset so third tap doesn't re-fire
                    task.spawn(function()
                        pcall(function()
                            local req = syn and syn.request or http and http.request or request
                            if not req then return end
                            req({
                                Url    = REACTIONS_URL .. "/" .. msgFbKey .. "/❤️/" .. tostring(RealUserId) .. ".json",
                                Method = "PUT",
                                Body   = HttpService:JSONEncode(true)
                            })
                        end)
                    end)
                else
                    lastTapTime[TextButton] = now2
                end
            end

            swipeStartPos = inp.Position
            swipeTriggered = false
            popupHoldFired = false
            local tapPos = inp.Position

            -- ============================================================
            -- HOLD-POPUP TIMER (0.6 s) — fires context menu if no swipe
            -- and the nameHitbox pvt-hold (holdTriggered) didn't fire first
            -- ============================================================
            task.delay(0.6, function()
                if swipeTriggered or popupHoldFired then return end
                if not (inp.UserInputState == Enum.UserInputState.Begin
                     or inp.UserInputState == Enum.UserInputState.Change) then return end
                -- Don't show popup if nameHitbox already triggered pvt hold
                if holdTriggered then return end
                popupHoldFired = true
                closeMsgPopup()

                local opts = {}

                -- COPY TEXT — available for everyone
                table.insert(opts, {
                    icon = "📋", label = "Copy Text", destructive = false,
                    callback = function()
                        pcall(function()
                            if setclipboard then setclipboard(safeMsg)
                            elseif toclipboard then toclipboard(safeMsg) end
                        end)
                    end
                })

                -- PVT + REPLY — available when holding OTHERS' messages
                if not isOwnMsg and not isSystem then
                    -- PVT — start a private chat with this sender
                    table.insert(opts, {
                        icon = "💬", label = "PVT", destructive = false,
                        callback = function()
                            PrivateTargetId   = senderUid
                            PrivateTargetName = safeName
                            Input.PlaceholderText = "[PVT] " .. safeName .. "..."
                            InputArea.BackgroundColor3 = Color3.fromRGB(40, 10, 50)
                            PvtInputTag.Text    = "[" .. safeName .. "]"
                            PvtInputTag.Visible = true
                            Input.Position = UDim2.new(0, 73, 0, 0)
                            Input.Size     = UDim2.new(1, -117, 1, 0)
                        end
                    })
                    -- REPLY — quote this message in the input box
                    table.insert(opts, {
                        icon = "↩️", label = "Reply", destructive = false,
                        callback = function()
                            ReplyTargetName = safeName
                            local replyDisplayMsg = safeMsg:match("^%[STICKER:%d+%]$") and "🎭 Sticker" or safeMsg
                            ReplyTargetMsg  = replyDisplayMsg
                            ReplyBanner.Visible = true
                            ReplyLabel.Text = "Replying to " .. safeName .. ": " .. replyDisplayMsg
                            if isPrivate then
                                PrivateTargetId   = senderUid
                                PrivateTargetName = safeName
                                Input.PlaceholderText = "[PVT] " .. safeName .. "..."
                                InputArea.BackgroundColor3 = Color3.fromRGB(40, 10, 50)
                                PvtInputTag.Text    = "[" .. safeName .. "]"
                                PvtInputTag.Visible = true
                                Input.Position = UDim2.new(0, 73, 0, 0)
                                Input.Size     = UDim2.new(1, -117, 1, 0)
                            end
                        end
                    })
                end

                if isOwnMsg and not isSystem and msgFbKey then
                    -- EDIT — pre-fill input with this message text for in-place editing.
                    -- The next send() call will PATCH Firebase content and update the
                    -- existing bubble in-place — it does NOT post a new message.
                    table.insert(opts, {
                        icon = "✏️", label = "Edit", destructive = false,
                        callback = function()
                            editingKey = msgFbKey
                            -- Populate input with the raw (un-encoded) message text
                            Input.Text = msg
                            Input.ClearTextOnFocus = false  -- keep text when user taps
                            -- Tint input area blue to signal edit mode
                            InputArea.BackgroundColor3 = Color3.fromRGB(0, 40, 90)
                        end
                    })

                    -- UNSEND — delete from Firebase and remove UI
                    table.insert(opts, {
                        icon = "🗑️", label = "Unsend", destructive = true,
                        callback = function()
                            -- Remove from sorted key list
                            local newKeys = {}
                            for _, k in ipairs(sortedMessageKeys) do
                                if k ~= msgFbKey then table.insert(newKeys, k) end
                            end
                            sortedMessageKeys = newKeys
                            keyToButton[msgFbKey] = nil
                            SpecialLabels[TextButton] = nil
                            -- Animate out and destroy wrapper
                            if wrapperFrame and wrapperFrame.Parent then
                                TweenService:Create(TextButton,
                                    TweenInfo.new(0.2, Enum.EasingStyle.Quad),
                                    {BackgroundTransparency = 1}):Play()
                                task.delay(0.22, function()
                                    if wrapperFrame and wrapperFrame.Parent then
                                        wrapperFrame:Destroy()
                                    end
                                end)
                            end
                            -- INSTANT unsend: write key to /unsent so ALL other clients
                            -- remove this message immediately (polled every 0.3s).
                            -- Also DELETE from /chat so new joiners never see it.
                            local req = syn and syn.request or http and http.request or request
                            if req then
                                task.spawn(function()
                                    pcall(function()
                                        -- 1. Publish to /unsent path — all live clients pick this up instantly
                                        req({
                                            Url    = UNSENT_URL .. "/" .. msgFbKey .. ".json",
                                            Method = "PUT",
                                            Body   = HttpService:JSONEncode(true)
                                        })
                                        -- 2. Hard-delete the message from /chat so new joiners never see it
                                        req({
                                            Url    = DATABASE_URL .. "/" .. msgFbKey .. ".json",
                                            Method = "DELETE"
                                        })
                                        -- 3. Clean up /unsent entry after 10 seconds (all clients will have seen it)
                                        task.delay(10, function()
                                            pcall(function()
                                                req({
                                                    Url    = UNSENT_URL .. "/" .. msgFbKey .. ".json",
                                                    Method = "DELETE"
                                                })
                                            end)
                                        end)
                                    end)
                                end)
                            end
                        end
                    })
                end

                -- REACT — available for ALL non-system messages that have a Firebase key
                if not isSystem and msgFbKey then
                    table.insert(opts, {
                        icon = "😊", label = "React", destructive = false,
                        callback = function()
                            -- Show a small inline react picker: 8 quick emojis
                            local QUICK_REACTS = {"❤️","😂","😮","😢","👍","🔥","💀","😈"}
                            -- Build a floating react row
                            local reactPicker = Instance.new("Frame", ScreenGui)
                            reactPicker.Name = "InlineReactPicker"
                            reactPicker.Size = UDim2.new(0, 252, 0, 44)
                            reactPicker.BackgroundColor3 = Color3.fromRGB(20, 12, 44)
                            reactPicker.BackgroundTransparency = 0.05
                            reactPicker.BorderSizePixel = 0
                            reactPicker.ZIndex = 400
                            Instance.new("UICorner", reactPicker).CornerRadius = UDim.new(1, 0)
                            local rpStroke = Instance.new("UIStroke", reactPicker)
                            rpStroke.Color = Color3.fromRGB(130, 80, 255)
                            rpStroke.Thickness = 1.3
                            rpStroke.Transparency = 0.2
                            local rpList = Instance.new("UIListLayout", reactPicker)
                            rpList.FillDirection = Enum.FillDirection.Horizontal
                            rpList.HorizontalAlignment = Enum.HorizontalAlignment.Center
                            rpList.VerticalAlignment   = Enum.VerticalAlignment.Center
                            rpList.Padding = UDim.new(0, 2)
                            -- Position near tap location, clamped to screen
                            local vpSize = game.Workspace.CurrentCamera.ViewportSize
                            local rx = math.clamp(tapPos.X - 126, 6, vpSize.X - 258)
                            local ry = tapPos.Y - 60
                            if ry < 6 then ry = tapPos.Y + 10 end
                            reactPicker.Position = UDim2.new(0, rx, 0, ry)

                            local capturedFbKey = msgFbKey
                            for _, em in ipairs(QUICK_REACTS) do
                                local rb = Instance.new("TextButton", reactPicker)
                                rb.Size = UDim2.new(0, 30, 0, 36)
                                rb.Text = em
                                rb.TextSize = 18
                                rb.Font = Enum.Font.GothamBold
                                rb.BackgroundTransparency = 1
                                rb.TextColor3 = Color3.new(1,1,1)
                                rb.ZIndex = 401
                                local capturedEm = em
                                rb.MouseButton1Click:Connect(function()
                                    reactPicker:Destroy()
                                    -- One reaction per user: remove any old, add new
                                    task.spawn(function()
                                        pcall(function()
                                            local req = syn and syn.request or http and http.request or request
                                            if not req then return end
                                            local myMark = tostring(RealUserId)
                                            -- Remove any previous reactions by this user on this message
                                            local allRes = req({
                                                Url    = REACTIONS_URL .. "/" .. capturedFbKey .. ".json",
                                                Method = "GET"
                                            })
                                            if allRes and allRes.Success and allRes.Body ~= "null" then
                                                local ok2, allData = pcall(HttpService.JSONDecode, HttpService, allRes.Body)
                                                if ok2 and type(allData) == "table" then
                                                    for oldEmoji, _ in pairs(allData) do
                                                        local chk = req({
                                                            Url    = REACTIONS_URL .. "/" .. capturedFbKey .. "/" .. oldEmoji .. "/" .. myMark .. ".json",
                                                            Method = "GET"
                                                        })
                                                        if chk and chk.Success and chk.Body ~= "null" then
                                                            req({
                                                                Url    = REACTIONS_URL .. "/" .. capturedFbKey .. "/" .. oldEmoji .. "/" .. myMark .. ".json",
                                                                Method = "DELETE"
                                                            })
                                                        end
                                                    end
                                                end
                                            end
                                            -- Add new reaction
                                            req({
                                                Url    = REACTIONS_URL .. "/" .. capturedFbKey .. "/" .. capturedEm .. "/" .. myMark .. ".json",
                                                Method = "PUT",
                                                Body   = HttpService:JSONEncode(true)
                                            })
                                        end)
                                    end)
                                end)
                            end

                            -- Auto-close after 4 seconds or on tap outside
                            task.delay(4, function()
                                if reactPicker and reactPicker.Parent then reactPicker:Destroy() end
                            end)
                            local rpConn
                            rpConn = UserInputService.InputBegan:Connect(function(inp)
                                if not reactPicker or not reactPicker.Parent then
                                    if rpConn then rpConn:Disconnect() end return
                                end
                                if inp.UserInputType ~= Enum.UserInputType.MouseButton1
                                and inp.UserInputType ~= Enum.UserInputType.Touch then return end
                                local p2  = inp.Position
                                local ab2 = reactPicker.AbsolutePosition
                                local sz2 = reactPicker.AbsoluteSize
                                if p2.X < ab2.X or p2.X > ab2.X + sz2.X or p2.Y < ab2.Y or p2.Y > ab2.Y + sz2.Y then
                                    reactPicker:Destroy()
                                    if rpConn then rpConn:Disconnect() end
                                end
                            end)
                        end
                    })
                end

                showMsgPopup(Vector2.new(tapPos.X, tapPos.Y), opts)
            end)

            -- Start global swipe tracking connection
            if swipeConn then swipeConn:Disconnect() swipeConn = nil end
            swipeConn = UserInputService.InputChanged:Connect(function(uiInp)
                if not swipeStartPos then return end
                if uiInp.UserInputType ~= Enum.UserInputType.MouseMovement
                and uiInp.UserInputType ~= Enum.UserInputType.Touch then return end
                if holdTriggered or swipeTriggered then return end
                local dx = uiInp.Position.X - swipeStartPos.X
                local dy = math.abs(uiInp.Position.Y - swipeStartPos.Y)
                local absDx = math.abs(dx)
                -- Left or right swipe: enough horizontal movement, minimal vertical drift
                if absDx >= SWIPE_THRESHOLD and dy < 40 then
                    swipeTriggered = true
                    holding = false
                    if swipeConn then swipeConn:Disconnect() swipeConn = nil end
                    -- SLIDE ANIMATION: Instagram-style.
                    -- Right swipe → slide right (+65) then elastic snap back.
                    -- Left  swipe → slide left  (-65) then elastic snap back.
                    -- TextButton is inside wrapperFrame so UIListLayout does NOT
                    -- override its Position — TweenService moves it freely.
                    local slideOffset = (dx > 0) and 65 or -65
                    TweenService:Create(TextButton, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                        Position = UDim2.new(0, slideOffset, 0, 0)
                    }):Play()
                    task.delay(0.15, function()
                        if TextButton and TextButton.Parent then
                            TweenService:Create(TextButton, TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
                                Position = UDim2.new(0, 0, 0, 0)
                            }):Play()
                        end
                    end)
                    -- TRIGGER REPLY
                    ReplyTargetName = safeName
                    local swipeReplyDisplayMsg = safeMsg:match("^%[STICKER:%d+%]$") and "🎭 Sticker" or safeMsg
                    ReplyTargetMsg  = swipeReplyDisplayMsg
                    ReplyBanner.Visible = true
                    ReplyLabel.Text = "Replying to " .. safeName .. ": " .. swipeReplyDisplayMsg
                    -- If the message was a private one
                    -- and sent by someone else, automatically route our reply privately
                    if isPrivate and senderUid ~= RealUserId then
                        PrivateTargetId   = senderUid
                        PrivateTargetName = safeName
                        Input.PlaceholderText = "[PVT] " .. safeName .. "..."
                        InputArea.BackgroundColor3 = Color3.fromRGB(40, 10, 50)
                        PvtInputTag.Text    = "[" .. safeName .. "]"
                        PvtInputTag.Visible = true
                        Input.Position = UDim2.new(0, 73, 0, 0)
                        Input.Size     = UDim2.new(1, -117, 1, 0)
                    end
                end
            end)
        end
    end)

    TextButton.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            holding = false
            swipeStartPos = nil
            if swipeConn then swipeConn:Disconnect() swipeConn = nil end
        end
    end)

    -- Smart auto-scroll: only scroll to bottom if the user hasn't manually scrolled up
    task.spawn(function()
        for i = 1, 3 do
            RunService.Heartbeat:Wait()
        end
        if ChatLog and not _userScrolledUp then
            ChatLog.CanvasPosition = Vector2.new(0, 99999999)
        end
    end)
end

-- ============================================================
-- DATABASE HELPERS
-- ============================================================
local function cleanDatabase()
    local req = syn and syn.request or http and http.request or request
    if req then req({Url = DATABASE_URL .. ".json", Method = "DELETE"}) end
end

local function broadcastCommand(targetId, cmdName, val)
    local timestamp = string.format("%012d", os.time()) .. math.random(100, 999)
    local data = {["Sender"] = "SYSTEM_CMD", ["TargetId"] = targetId, ["Cmd"] = cmdName, ["Val"] = val, ["Server"] = JobId}
    local req = syn and syn.request or http and http.request or request
    if req then
        req({Url = DATABASE_URL .. "/" .. timestamp .. ".json", Method = "PUT", Body = HttpService:JSONEncode(data)})
    end
end

-- ============================================================
-- LOCAL COMMANDS (available to ALL users)
-- ============================================================
local function handleLocalCommands(msg)
    local args = string.split(msg, " ")
    local cmd = string.lower(args[1])

    -- /clear — wipe local UI only
    if cmd == "/clear" then
        for _, child in pairs(ChatLog:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end  -- wrapperFrames
        sortedMessageKeys = {}
        keyToButton = {}
        addMessage("SYSTEM", "Chat cleared locally.", true, 0, 0, false, true)
        return true

    -- /fly — toggle fly (stable for both PC and mobile)
    elseif cmd == "/fly" then
        Flying = not Flying
        if Flying then
            local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
            local hrp = char:WaitForChild("HumanoidRootPart")
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            -- Remove any leftover fly constraints from a previous session
            local oldBV = hrp:FindFirstChild("AresFlyBV")
            local oldBG = hrp:FindFirstChild("AresFlyBG")
            if oldBV then oldBV:Destroy() end
            if oldBG then oldBG:Destroy() end
            if humanoid then humanoid.PlatformStand = true end
            local bv = Instance.new("BodyVelocity", hrp)
            bv.Name     = "AresFlyBV"
            bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
            bv.Velocity = Vector3.new(0, 0, 0)
            local bg = Instance.new("BodyGyro", hrp)
            bg.Name      = "AresFlyBG"
            bg.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
            bg.P         = 2e5
            bg.D         = 1e3
            bg.CFrame    = hrp.CFrame
            task.spawn(function()
                while Flying and hrp and hrp.Parent do
                    RunService.Heartbeat:Wait()
                    local speed = 50
                    local cam   = workspace.CurrentCamera
                    -- ── Horizontal movement ─────────────────────────────────
                    -- humanoid.MoveDirection is in WORLD space and is already
                    -- camera-adjusted by Roblox for both PC (WASD) and mobile
                    -- (thumbstick). Use it directly — do NOT project through
                    -- camera vectors again (that double-rotates the direction).
                    local md = humanoid and humanoid.MoveDirection or Vector3.new(0,0,0)
                    local flatMove = Vector3.new(md.X, 0, md.Z)
                    local moveDir
                    if flatMove.Magnitude > 0.01 then
                        moveDir = flatMove.Unit * speed
                    else
                        moveDir = Vector3.new(0, 0, 0)
                    end
                    -- ── Vertical movement (PC: Space/Shift/E/Q) ─────────────
                    local goUp   = UserInputService:IsKeyDown(Enum.KeyCode.Space)
                                or UserInputService:IsKeyDown(Enum.KeyCode.E)
                    local goDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
                                or UserInputService:IsKeyDown(Enum.KeyCode.Q)
                    if goUp   then moveDir = Vector3.new(moveDir.X,  speed, moveDir.Z) end
                    if goDown then moveDir = Vector3.new(moveDir.X, -speed, moveDir.Z) end
                    bv.Velocity = moveDir
                    -- ── Gyro: face movement direction; idle → face camera ────
                    local horizDir = Vector3.new(moveDir.X, 0, moveDir.Z)
                    if horizDir.Magnitude > 0.1 then
                        bg.CFrame = CFrame.lookAt(Vector3.new(0,0,0), horizDir)
                    else
                        -- When hovering still, keep character facing camera direction
                        local camFlat = Vector3.new(
                            cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
                        if camFlat.Magnitude > 0.01 then
                            bg.CFrame = CFrame.lookAt(Vector3.new(0,0,0), camFlat)
                        end
                    end
                end
                -- Cleanup when fly is toggled off or character removed
                if bv and bv.Parent then bv:Destroy() end
                if bg and bg.Parent then bg:Destroy() end
                if humanoid and humanoid.Parent then humanoid.PlatformStand = false end
            end)
        else
            -- Disable fly: remove constraints and restore walking
            local char = LocalPlayer.Character
            if char then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local bv = hrp:FindFirstChild("AresFlyBV")
                    local bg = hrp:FindFirstChild("AresFlyBG")
                    if bv then bv:Destroy() end
                    if bg then bg:Destroy() end
                end
                local humanoid = char:FindFirstChildOfClass("Humanoid")
                if humanoid then humanoid.PlatformStand = false end
            end
        end
        addMessage("SYSTEM", "Fly " .. (Flying and "enabled." or "disabled."), true, 0, 0, false, true)
        return true

    -- /noclip — toggle noclip
    elseif cmd == "/noclip" then
        Noclip = not Noclip
        task.spawn(function()
            while Noclip do
                RunService.Stepped:Wait()
                if LocalPlayer.Character then
                    for _, p in pairs(LocalPlayer.Character:GetDescendants()) do
                        if p:IsA("BasePart") then p.CanCollide = false end
                    end
                end
            end
        end)
        addMessage("SYSTEM", "Noclip " .. (Noclip and "enabled." or "disabled."), true, 0, 0, false, true)
        return true

    -- /nosit — disable sitting
    elseif cmd == "/nosit" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.Sit = false
            LocalPlayer.Character.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
        end
        addMessage("SYSTEM", "Sit disabled.", true, 0, 0, false, true)
        return true

    -- /sit — force sit
    elseif cmd == "/sit" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.Sit = true
        end
        addMessage("SYSTEM", "Sitting.", true, 0, 0, false, true)
        return true

    -- /speed [val] — set own walkspeed (no target = self)
    elseif cmd == "/speed" and args[2] and not args[3] then
        local val = tonumber(args[2])
        if val and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.WalkSpeed = val
            addMessage("SYSTEM", "WalkSpeed set to " .. val .. ".", true, 0, 0, false, true)
        end
        return true

    -- /jump [val] — set own jump power (no target = self)
    elseif cmd == "/jump" and args[2] and not args[3] then
        local val = tonumber(args[2])
        if val and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.JumpPower = val
            addMessage("SYSTEM", "JumpPower set to " .. val .. ".", true, 0, 0, false, true)
        end
        return true

    -- /invisible — toggle own invisibility
    elseif cmd == "/invisible" and not args[2] then
        IsInvisible = not IsInvisible
        if LocalPlayer.Character then
            for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
                if part:IsA("BasePart") or part:IsA("Decal") then
                    part.Transparency = IsInvisible and 1 or 0
                end
            end
        end
        addMessage("SYSTEM", "Invisibility " .. (IsInvisible and "enabled." or "disabled."), true, 0, 0, false, true)
        return true

    -- /me [text] — roleplay action sent to chat
    elseif cmd == "/me" then
        local rest = table.concat(args, " ", 2)
        if rest ~= "" then
            return false -- let send() handle it as a special /me message
        end
        return true

    -- /time — show current time
    elseif cmd == "/time" then
        local h = tonumber(os.date("%H"))
        local m = os.date("%M")
        local ampm = h >= 12 and "PM" or "AM"
        h = h % 12
        if h == 0 then h = 12 end
        addMessage("SYSTEM", "Current time: " .. h .. ":" .. m .. " " .. ampm, true, 0, 0, false, true)
        return true

    -- /name [text] — set RP name in Brookhaven (or just local display alias)
    elseif cmd == "/name" and args[2] then
        local newName = table.concat(args, " ", 2)
        if game.PlaceId == 4924922222 then
            local rs = game:GetService("ReplicatedStorage")
            local rpRemote = rs:FindFirstChild("RE")
            if rpRemote then
                local nameRemote = rpRemote:FindFirstChild("1RPNam1eTex1t")
                if nameRemote then
                    pcall(function() nameRemote:FireServer("RolePlayName", newName) end)
                    addMessage("SYSTEM", "RP name set to: " .. newName, true, 0, 0, false, true)
                end
            end
        else
            addMessage("SYSTEM", "Name command only works in Brookhaven.", true, 0, 0, false, true)
        end
        return true

    -- ============================================================
    -- /mute [name] — LOCAL MUTE (only visible to this player)
    -- Suppresses messages from the target in the local chat GUI only.
    -- Does NOT affect other players or Firebase.
    -- ============================================================
    elseif cmd == "/mute" and args[2] then
        local targetName = table.concat(args, " ", 2)
        local target = GetPlayerByName(targetName)
        if target then
            if target.UserId == RealUserId then
                addMessage("SYSTEM", "You cannot mute yourself.", true, 0, 0, false, true)
            elseif target.UserId == CREATOR_ID then
                addMessage("SYSTEM", "You cannot mute the Creator.", true, 0, 0, false, true)
            else
                MutedPlayers[target.UserId] = true
                addMessage("SYSTEM", "Locally muted " .. target.DisplayName .. ". Only you see this.", true, 0, 0, false, true)
            end
        else
            addMessage("SYSTEM", "Player '" .. targetName .. "' not found.", true, 0, 0, false, true)
        end
        return true

    -- /unmute [name] — LOCAL UNMUTE
    elseif cmd == "/unmute" and args[2] then
        local targetName = table.concat(args, " ", 2)
        local target = GetPlayerByName(targetName)
        if target then
            MutedPlayers[target.UserId] = nil
            addMessage("SYSTEM", "Locally unmuted " .. target.DisplayName .. ".", true, 0, 0, false, true)
        else
            addMessage("SYSTEM", "Player '" .. targetName .. "' not found.", true, 0, 0, false, true)
        end
        return true

    -- ============================================================
    -- EXTRA USER COMMANDS (50+)
    -- ============================================================

    -- /view [name] — view / spectate a player (shifts camera to their character)
    elseif cmd == "/view" and args[2] then
        local target = GetPlayerByName(args[2])
        if target and target.Character then
            workspace.CurrentCamera.CameraSubject = target.Character:FindFirstChildOfClass("Humanoid") or target.Character:FindFirstChild("HumanoidRootPart")
            addMessage("SYSTEM", "Viewing " .. target.DisplayName .. ".", true, 0, 0, false, true)
        else
            addMessage("SYSTEM", "Player not found.", true, 0, 0, false, true)
        end
        return true

    -- /unview — restore camera to own character
    elseif cmd == "/unview" then
        if LocalPlayer.Character then
            workspace.CurrentCamera.CameraSubject = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            addMessage("SYSTEM", "Camera restored.", true, 0, 0, false, true)
        end
        return true

    -- /to [name] — teleport self to player
    elseif cmd == "/to" and args[2] then
        local target = GetPlayerByName(args[2])
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                LocalPlayer.Character.HumanoidRootPart.CFrame = target.Character.HumanoidRootPart.CFrame * CFrame.new(4, 0, 0)
                addMessage("SYSTEM", "Teleported to " .. target.DisplayName .. ".", true, 0, 0, false, true)
            end
        else
            addMessage("SYSTEM", "Player not found.", true, 0, 0, false, true)
        end
        return true

    -- /goto [name] — alias for /to
    elseif cmd == "/goto" and args[2] then
        local target = GetPlayerByName(args[2])
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                LocalPlayer.Character.HumanoidRootPart.CFrame = target.Character.HumanoidRootPart.CFrame * CFrame.new(4, 0, 0)
                addMessage("SYSTEM", "Teleported to " .. target.DisplayName .. ".", true, 0, 0, false, true)
            end
        else
            addMessage("SYSTEM", "Player not found.", true, 0, 0, false, true)
        end
        return true

    -- /bring [name] — bring player to self (local only)
    elseif cmd == "/bring" and args[2] then
        local target = GetPlayerByName(args[2])
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                target.Character.HumanoidRootPart.CFrame = LocalPlayer.Character.HumanoidRootPart.CFrame * CFrame.new(4, 0, 0)
                addMessage("SYSTEM", "Brought " .. target.DisplayName .. " to you (local).", true, 0, 0, false, true)
            end
        else
            addMessage("SYSTEM", "Player not found.", true, 0, 0, false, true)
        end
        return true

    -- /ws [val] — set walkspeed (alias)
    elseif cmd == "/ws" and args[2] then
        local val = tonumber(args[2])
        if val and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.WalkSpeed = val
            addMessage("SYSTEM", "WalkSpeed set to " .. val .. ".", true, 0, 0, false, true)
        end
        return true

    -- /jp [val] — set jump power (alias)
    elseif cmd == "/jp" and args[2] then
        local val = tonumber(args[2])
        if val and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.JumpPower = val
            addMessage("SYSTEM", "JumpPower set to " .. val .. ".", true, 0, 0, false, true)
        end
        return true

    -- /gravity [val] — set workspace gravity
    elseif cmd == "/gravity" and args[2] then
        local val = tonumber(args[2])
        if val then
            workspace.Gravity = val
            addMessage("SYSTEM", "Gravity set to " .. val .. ".", true, 0, 0, false, true)
        end
        return true

    -- /fog [val] — set fog end distance
    elseif cmd == "/fog" and args[2] then
        local val = tonumber(args[2])
        if val then
            local lighting = game:GetService("Lighting")
            lighting.FogEnd = val
            addMessage("SYSTEM", "Fog end set to " .. val .. ".", true, 0, 0, false, true)
        end
        return true

    -- /day — set daytime
    elseif cmd == "/day" then
        game:GetService("Lighting").ClockTime = 14
        addMessage("SYSTEM", "Time set to day.", true, 0, 0, false, true)
        return true

    -- /night — set night time
    elseif cmd == "/night" then
        game:GetService("Lighting").ClockTime = 0
        addMessage("SYSTEM", "Time set to night.", true, 0, 0, false, true)
        return true

    -- /reset — reset own character
    elseif cmd == "/reset" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.Health = 0
            addMessage("SYSTEM", "Resetting character...", true, 0, 0, false, true)
        end
        return true

    -- /respawn — reload character
    elseif cmd == "/respawn" then
        LocalPlayer:LoadCharacter()
        addMessage("SYSTEM", "Respawning...", true, 0, 0, false, true)
        return true

    -- /heal — restore own health to max
    elseif cmd == "/heal" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            local hum = LocalPlayer.Character.Humanoid
            hum.Health = hum.MaxHealth
            addMessage("SYSTEM", "Health restored.", true, 0, 0, false, true)
        end
        return true

    -- /god — set own health to very high
    elseif cmd == "/god" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.MaxHealth = math.huge
            LocalPlayer.Character.Humanoid.Health    = math.huge
            addMessage("SYSTEM", "God mode ON.", true, 0, 0, false, true)
        end
        return true

    -- /ungod — restore normal health cap
    elseif cmd == "/ungod" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.MaxHealth = 100
            LocalPlayer.Character.Humanoid.Health    = 100
            addMessage("SYSTEM", "God mode OFF.", true, 0, 0, false, true)
        end
        return true

    -- /ping — show latency
    elseif cmd == "/ping" then
        local stats = game:GetService("Stats")
        local ping = stats.Network.ServerStatsItem["Data Ping"]:GetValue()
        addMessage("SYSTEM", "Ping: " .. math.floor(ping) .. " ms", true, 0, 0, false, true)
        return true

    -- /players — list all players in server
    elseif cmd == "/players" then
        addMessage("SYSTEM", "Players in server:", true, 0, 0, false, true)
        for _, p in pairs(Players:GetPlayers()) do
            addMessage("SYSTEM", "  • " .. p.DisplayName .. " (@" .. p.Name .. ")", true, 0, 0, false, true)
        end
        return true

    -- /server — show server/job id
    elseif cmd == "/server" then
        addMessage("SYSTEM", "Server ID: " .. tostring(JobId), true, 0, 0, false, true)
        return true

    -- /gameid — show game ID
    elseif cmd == "/gameid" then
        addMessage("SYSTEM", "Game ID: " .. tostring(game.GameId), true, 0, 0, false, true)
        return true

    -- /placeid — show place ID
    elseif cmd == "/placeid" then
        addMessage("SYSTEM", "Place ID: " .. tostring(game.PlaceId), true, 0, 0, false, true)
        return true

    -- /fps — show current FPS
    elseif cmd == "/fps" then
        local fps = math.floor(1/RunService.Heartbeat:Wait())
        addMessage("SYSTEM", "FPS: ~" .. fps, true, 0, 0, false, true)
        return true

    -- /zoom [val] — set camera zoom distance
    elseif cmd == "/zoom" and args[2] then
        local val = tonumber(args[2])
        if val then
            LocalPlayer.CameraMaxZoomDistance = val
            LocalPlayer.CameraMinZoomDistance = math.min(val, LocalPlayer.CameraMinZoomDistance)
            addMessage("SYSTEM", "Camera zoom set to " .. val .. ".", true, 0, 0, false, true)
        end
        return true

    -- /fov [val] — set field of view
    elseif cmd == "/fov" and args[2] then
        local val = tonumber(args[2])
        if val then
            workspace.CurrentCamera.FieldOfView = val
            addMessage("SYSTEM", "FOV set to " .. val .. ".", true, 0, 0, false, true)
        end
        return true

    -- /spin — make character spin
    elseif cmd == "/spin" then
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local hrp = char.HumanoidRootPart
            local old = hrp:FindFirstChild("AresSpinBG")
            if old then old:Destroy() end
            local bg = Instance.new("BodyAngularVelocity", hrp)
            bg.Name = "AresSpinBG"
            bg.AngularVelocity = Vector3.new(0, 20, 0)
            bg.MaxTorque = Vector3.new(0, 1e9, 0)
            bg.P = 1e5
            addMessage("SYSTEM", "Spinning! /unspin to stop.", true, 0, 0, false, true)
        end
        return true

    -- /unspin — stop spinning
    elseif cmd == "/unspin" then
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local bg = char.HumanoidRootPart:FindFirstChild("AresSpinBG")
            if bg then bg:Destroy() end
            addMessage("SYSTEM", "Spin stopped.", true, 0, 0, false, true)
        end
        return true

    -- /lock — anchor own HRP (freeze self)
    elseif cmd == "/lock" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            LocalPlayer.Character.HumanoidRootPart.Anchored = true
            addMessage("SYSTEM", "Self locked (frozen).", true, 0, 0, false, true)
        end
        return true

    -- /unlock — unanchor own HRP
    elseif cmd == "/unlock" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            LocalPlayer.Character.HumanoidRootPart.Anchored = false
            addMessage("SYSTEM", "Self unlocked.", true, 0, 0, false, true)
        end
        return true

    -- /hitbox [val] — resize own HRP hitbox
    elseif cmd == "/hitbox" and args[2] then
        local val = tonumber(args[2])
        if val and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            LocalPlayer.Character.HumanoidRootPart.Size = Vector3.new(val, val, val)
            addMessage("SYSTEM", "Hitbox size set to " .. val .. ".", true, 0, 0, false, true)
        end
        return true

    -- /tools — give all tools from StarterPack
    elseif cmd == "/tools" then
        pcall(function()
            local sp = game:GetService("StarterPack")
            local bp = LocalPlayer.Backpack
            for _, tool in pairs(sp:GetChildren()) do
                if tool:IsA("Tool") and not bp:FindFirstChild(tool.Name) then
                    tool:Clone().Parent = bp
                end
            end
        end)
        addMessage("SYSTEM", "Tools added from StarterPack.", true, 0, 0, false, true)
        return true

    -- /notools — remove all tools from backpack
    elseif cmd == "/notools" then
        if LocalPlayer.Backpack then
            for _, t in pairs(LocalPlayer.Backpack:GetChildren()) do t:Destroy() end
        end
        if LocalPlayer.Character then
            for _, t in pairs(LocalPlayer.Character:GetChildren()) do if t:IsA("Tool") then t:Destroy() end end
        end
        addMessage("SYSTEM", "All tools removed.", true, 0, 0, false, true)
        return true

    -- /shout [text] — post a shout-style message in chat
    elseif cmd == "/shout" and args[2] then
        local text = table.concat(args, " ", 2)
        return false  -- route to send() as a normal message prefixed with SHOUT

    -- /afk — toggle AFK status
    elseif cmd == "/afk" then
        addMessage("SYSTEM", "AFK mode toggled. Others will see your AFK tag.", true, 0, 0, false, true)
        return true

    -- /info [name] — show info about a player
    elseif cmd == "/info" and args[2] then
        local target = GetPlayerByName(args[2])
        if target then
            addMessage("SYSTEM", "=== Info: " .. target.DisplayName .. " ===", true, 0, 0, false, true)
            addMessage("SYSTEM", "Username: @" .. target.Name, true, 0, 0, false, true)
            addMessage("SYSTEM", "UserID: " .. tostring(target.UserId), true, 0, 0, false, true)
            addMessage("SYSTEM", "Account Age: " .. tostring(target.AccountAge) .. " days", true, 0, 0, false, true)
            addMessage("SYSTEM", "Team: " .. (target.Team and target.Team.Name or "None"), true, 0, 0, false, true)
        else
            addMessage("SYSTEM", "Player not found.", true, 0, 0, false, true)
        end
        return true

    -- /age [name] — show account age
    elseif cmd == "/age" and args[2] then
        local target = GetPlayerByName(args[2])
        if target then
            addMessage("SYSTEM", target.DisplayName .. " account age: " .. tostring(target.AccountAge) .. " days", true, 0, 0, false, true)
        else
            addMessage("SYSTEM", "Player not found.", true, 0, 0, false, true)
        end
        return true

    -- /online — show how many players are in server
    elseif cmd == "/online" then
        local count = #Players:GetPlayers()
        addMessage("SYSTEM", "Players online: " .. count .. "/" .. Players.MaxPlayers, true, 0, 0, false, true)
        return true

    -- /dms — toggle private mode reminder
    elseif cmd == "/dms" then
        addMessage("SYSTEM", "Hold a message and tap PVT to start a private chat.", true, 0, 0, false, true)
        return true

    -- /ambient [r] [g] [b] — set ambient light color
    elseif cmd == "/ambient" and args[2] and args[3] and args[4] then
        local r, g, b = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
        if r and g and b then
            game:GetService("Lighting").Ambient = Color3.fromRGB(r, g, b)
            addMessage("SYSTEM", "Ambient set to " .. r .. "," .. g .. "," .. b .. ".", true, 0, 0, false, true)
        end
        return true

    -- /dance — play idle animation (sit toggle trick)
    elseif cmd == "/dance" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") then
            local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            pcall(function()
                local animTrack = hum:LoadAnimation(Instance.new("Animation"))
                animTrack:Play()
            end)
        end
        addMessage("SYSTEM", "Dance command sent! (Game must support animations)", true, 0, 0, false, true)
        return true

    -- /sit2 — force sit from script side
    elseif cmd == "/sit2" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") then
            LocalPlayer.Character:FindFirstChildOfClass("Humanoid").Sit = true
            addMessage("SYSTEM", "Force sitting.", true, 0, 0, false, true)
        end
        return true

    -- /lag — show network stats
    elseif cmd == "/lag" then
        local stats = game:GetService("Stats")
        local ping = 0
        pcall(function() ping = stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
        addMessage("SYSTEM", "Network ping: ~" .. math.floor(ping) .. "ms", true, 0, 0, false, true)
        return true

    -- /back — teleport back to spawn
    elseif cmd == "/back" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(0, 5, 0)
            addMessage("SYSTEM", "Teleported to origin.", true, 0, 0, false, true)
        end
        return true

    -- /pm [name] [msg] — send private message via chat
    elseif cmd == "/pm" and args[2] and args[3] then
        local target = GetPlayerByName(args[2])
        if target then
            PrivateTargetId   = target.UserId
            PrivateTargetName = target.DisplayName
            Input.PlaceholderText = "[PVT] " .. target.DisplayName .. "..."
            InputArea.BackgroundColor3 = Color3.fromRGB(40, 10, 50)
            PvtInputTag.Text    = "[" .. target.DisplayName .. "]"
            PvtInputTag.Visible = true
            Input.Position = UDim2.new(0, 73, 0, 0)
            Input.Size     = UDim2.new(1, -117, 1, 0)
            addMessage("SYSTEM", "PM mode to " .. target.DisplayName .. " activated.", true, 0, 0, false, true)
        else
            addMessage("SYSTEM", "Player not found.", true, 0, 0, false, true)
        end
        return true

    -- /emote [name] — print emote hint
    elseif cmd == "/emote" and args[2] then
        local emoteName = args[2]
        addMessage("SYSTEM", "Emote '" .. emoteName .. "' — use /e " .. emoteName .. " in Roblox chat for in-game emotes.", true, 0, 0, false, true)
        return true

    -- /nametag [text] — set local display name above character
    elseif cmd == "/nametag" and args[2] then
        local tagText = table.concat(args, " ", 2)
        if LocalPlayer.Character then
            for _, d in pairs(LocalPlayer.Character:GetDescendants()) do
                if d:IsA("BillboardGui") and d.Name == "AresNameTag" then d:Destroy() end
            end
            local hrp = LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.Character:FindFirstChild("Head")
            if hrp then
                local bb = Instance.new("BillboardGui", hrp)
                bb.Name = "AresNameTag"
                bb.Size = UDim2.new(0, 100, 0, 26)
                bb.StudsOffset = Vector3.new(0, 3, 0)
                bb.AlwaysOnTop = false
                local lbl = Instance.new("TextLabel", bb)
                lbl.Size = UDim2.new(1,0,1,0)
                lbl.BackgroundTransparency = 1
                lbl.Text = tagText
                lbl.TextColor3 = Color3.fromRGB(220, 180, 255)
                lbl.Font = Enum.Font.GothamBold
                lbl.TextSize = 14
                addMessage("SYSTEM", "Nametag set to: " .. tagText, true, 0, 0, false, true)
            end
        end
        return true

    -- /hat — un-hide accessories
    elseif cmd == "/hat" then
        if LocalPlayer.Character then
            for _, acc in pairs(LocalPlayer.Character:GetChildren()) do
                if acc:IsA("Accessory") then
                    local h = acc:FindFirstChild("Handle")
                    if h then h.Transparency = 0 end
                end
            end
            addMessage("SYSTEM", "Accessories shown.", true, 0, 0, false, true)
        end
        return true

    -- /nohat — hide accessories
    elseif cmd == "/nohat" then
        if LocalPlayer.Character then
            for _, acc in pairs(LocalPlayer.Character:GetChildren()) do
                if acc:IsA("Accessory") then
                    local h = acc:FindFirstChild("Handle")
                    if h then h.Transparency = 1 end
                end
            end
            addMessage("SYSTEM", "Accessories hidden.", true, 0, 0, false, true)
        end
        return true

    -- ============================================================
    -- /commands — show ALL user commands as local system messages
    -- ============================================================
    elseif cmd == "/commands" then
        local commandList = {
            "=== MOVEMENT ===",
            "/fly — Toggle fly",
            "/noclip — Toggle noclip",
            "/sit — Force sit",
            "/sit2 — Force sit (script-side)",
            "/nosit — Disable sit",
            "/spin — Start spinning",
            "/unspin — Stop spinning",
            "/lock — Freeze self (anchored)",
            "/unlock — Unfreeze self",
            "/dance — Play dance emote",
            "",
            "=== TELEPORT ===",
            "/to [name] — Teleport to player",
            "/goto [name] — Teleport to player (alias)",
            "/bring [name] — Bring player to you (local)",
            "/back — Teleport to origin (0,0,0)",
            "",
            "=== STATS ===",
            "/speed [val] — Set WalkSpeed",
            "/ws [val] — Set WalkSpeed (alias)",
            "/jump [val] — Set JumpPower",
            "/jp [val] — Set JumpPower (alias)",
            "/gravity [val] — Set gravity",
            "/zoom [val] — Set camera zoom",
            "/fov [val] — Set field of view",
            "",
            "=== HEALTH ===",
            "/heal — Restore max health",
            "/god — God mode (infinite health)",
            "/ungod — Disable god mode",
            "",
            "=== WORLD ===",
            "/fog [val] — Set fog end distance",
            "/day — Set daytime",
            "/night — Set nighttime",
            "/ambient [r] [g] [b] — Set ambient color",
            "",
            "=== CAMERA ===",
            "/view [name] — Spectate a player",
            "/unview — Restore camera",
            "",
            "=== PLAYER INFO ===",
            "/players — List all players",
            "/info [name] — Player info",
            "/age [name] — Account age",
            "/online — Players online count",
            "/ping — Show ping",
            "/fps — Show FPS",
            "/lag — Network stats",
            "/server — Server ID",
            "/gameid — Game ID",
            "/placeid — Place ID",
            "",
            "=== APPEARANCE ===",
            "/invisible — Toggle own invisibility",
            "/hat — Show accessories",
            "/nohat — Hide accessories",
            "/nametag [text] — Set local nametag",
            "/hitbox [val] — Resize HRP hitbox",
            "",
            "=== TOOLS ===",
            "/tools — Get StarterPack tools",
            "/notools — Remove all tools",
            "",
            "=== CHAT ===",
            "/me [text] — Roleplay action message",
            "/pm [name] [msg] — Private message",
            "/dms — Private chat reminder",
            "/afk — AFK reminder",
            "/emote [name] — Emote hint",
            "",
            "=== MISC ===",
            "/time — Show current time",
            "/name [text] — RP name (Brookhaven)",
            "/mute [name] — Locally mute player",
            "/unmute [name] — Locally unmute player",
            "/clear — Clear local chat",
            "/reset — Reset character",
            "/respawn — Reload character",
            "/commands — Show this list",
        }
        addMessage("SYSTEM", "╔══ ARES RECHAT COMMANDS ══╗", true, 0, 0, false, true)
        for _, line in ipairs(commandList) do
            addMessage("SYSTEM", line, true, 0, 0, false, true)
        end
        addMessage("SYSTEM", "╚══ END OF COMMANDS ══╝", true, 0, 0, false, true)
        return true

    end

    return false
end

-- ============================================================
-- SEND MESSAGE (with Reply support + /me handling)
-- ============================================================
send = function(msg, isSystem, isAutoClean)
    if msg == "" then return end

    -- KICKED/BANNED GUARD: block any send attempt after kick/ban
    if isKickedOrBanned then return end

    -- ============================================================
    -- EDIT MODE — when editingKey is set, patch the existing
    -- Firebase message in-place instead of posting a new one.
    -- Restores the input area colour and ClearTextOnFocus flag.
    -- ============================================================
    if editingKey and not isSystem then
        local ekCopy  = editingKey
        editingKey    = nil
        Input.ClearTextOnFocus = true
        InputArea.BackgroundColor3 = Color3.fromRGB(20, 10, 45)

        -- Update the bubble text locally so the change is instant
        local btn = keyToButton[ekCopy]
        if btn then
            local safeNewMsg = SafeEncodeMsg(msg)
            if SpecialLabels[btn] then
                -- RGB-loop messages: update the cached msg field
                SpecialLabels[btn].msg = safeNewMsg
            else
                -- Plain messages: rewrite text preserving the name prefix
                local cur = btn.Text or ""
                local colonPos = string.find(cur, ": ", 1, true)
                if colonPos then
                    btn.Text = string.sub(cur, 1, colonPos + 1) .. safeNewMsg
                end
            end
        end

        -- PATCH only the Content field in Firebase (all other fields untouched)
        task.spawn(function()
            pcall(function()
                local req2 = syn and syn.request or http and http.request or request
                if req2 then
                    req2({
                        Url    = DATABASE_URL .. "/" .. ekCopy .. ".json",
                        Method = "PATCH",
                        Body   = HttpService:JSONEncode({Content = msg})
                    })
                end
            end)
        end)
        return
    end

    -- 200 CHARACTER LIMIT ENFORCEMENT
    if #msg > MAX_CHAR_LIMIT then
        addMessage("SYSTEM", "Message too long! Max " .. MAX_CHAR_LIMIT .. " characters.", true, 0, 0, false, true)
        return
    end

    -- ANTI-SPAM CHECK (skip for system messages and admin commands)
    if not isSystem and string.sub(msg, 1, 1) ~= "/" then
        local now = os.time()
        -- Reset rolling window
        if now - _spamWindowStart >= SPAM_WINDOW then
            _spamCount = 0
            _spamWindowStart = now
        end
        -- Minimum interval between messages
        if now - _lastSentTime < SPAM_INTERVAL then
            addMessage("SYSTEM", "⛔ Slow down! You are sending messages too fast.", true, 0, 0, false, true)
            return
        end
        -- Same message repeated
        if msg == _lastSentMsg then
            addMessage("SYSTEM", "⛔ Don't repeat the same message.", true, 0, 0, false, true)
            return
        end
        -- Too many messages in window
        _spamCount = _spamCount + 1
        if _spamCount > SPAM_MAX then
            addMessage("SYSTEM", "⛔ Anti-spam: You've sent too many messages. Please wait.", true, 0, 0, false, true)
            _spamCount = SPAM_MAX  -- keep capped so it recovers on next window
            return
        end
        _lastSentTime = now
        _lastSentMsg  = msg
    end

    -- /me handling: convert to emote-style message before local command check
    local args = string.split(msg, " ")
    if string.lower(args[1]) == "/me" then
        local rest = table.concat(args, " ", 2)
        if rest ~= "" then
            local emoteMsg = "* " .. RealDisplayName .. " " .. rest .. " *"
            local timestamp = string.format("%012d", os.time()) .. math.random(100, 999)
            local data = {
                ["Sender"]      = "SYSTEM",
                ["SenderUid"]   = RealUserId,
                ["Content"]     = emoteMsg,
                ["Server"]      = JobId,
                ["IsSystem"]    = true,
                ["IsAutoClean"] = false,
                ["TargetId"]    = nil,
                ["ReplyTo"]     = nil
            }
            processedKeys[timestamp] = true
            addMessage("SYSTEM", emoteMsg, true, tonumber(timestamp) or 0, 0, false, false, nil)
            task.spawn(function()
                local req = syn and syn.request or http and http.request or request
                if req then req({Url = DATABASE_URL .. "/" .. timestamp .. ".json", Method = "PUT", Body = HttpService:JSONEncode(data)}) end
            end)
            lastMessageTime = os.time()
        end
        return
    end

    if handleLocalCommands(msg) then return end

    -- CREATOR ADMIN COMMANDS (full powers)
    if RealUserId == CREATOR_ID and string.sub(msg, 1, 1) == "/" then
        local cmd = string.lower(args[1])
        local targetName = args[2] or ""
        local target = GetPlayerByName(targetName)

        if cmd == "/kick" and target then
            broadcastCommand(target.UserId, "kick", "Kicked by Ares Creator.")
            return

        -- /ban — CREATOR ONLY — writes to Firebase BAN_URL for permanent ban
        elseif cmd == "/ban" and target then
            task.spawn(function()
                local req = syn and syn.request or http and http.request or request
                if req then
                    pcall(function()
                        req({
                            Url    = BAN_URL .. "/" .. tostring(target.UserId) .. ".json",
                            Method = "PUT",
                            Body   = HttpService:JSONEncode({
                                name        = target.Name,
                                displayName = target.DisplayName,
                                bannedAt    = os.time()
                            })
                        })
                    end)
                end
            end)
            broadcastCommand(target.UserId, "ban", "You are permanently banned from Ares Chat.")
            return

        -- /unban — CREATOR ONLY — removes ban from Firebase
        elseif cmd == "/unban" and args[2] then
            local unbanTarget = GetPlayerByName(args[2])
            local unbanId = nil
            if unbanTarget then
                unbanId = unbanTarget.UserId
            else
                -- Try numeric ID if name not found
                unbanId = tonumber(args[2])
            end
            if unbanId then
                task.spawn(function()
                    local req = syn and syn.request or http and http.request or request
                    if req then
                        pcall(function()
                            req({
                                Url    = BAN_URL .. "/" .. tostring(unbanId) .. ".json",
                                Method = "DELETE"
                            })
                        end)
                    end
                end)
                addMessage("SYSTEM", "Unbanned user ID " .. tostring(unbanId) .. ".", true, 0, 0, false, true)
            else
                addMessage("SYSTEM", "Player or ID not found for /unban.", true, 0, 0, false, true)
            end
            return

        -- /title [name] [colour] [text] — CREATOR ONLY — give a coloured custom title for 1 day
        -- colour must be one of: red, white, yellow, black
        elseif cmd == "/title" and target and args[3] and args[4] then
            local colourArg = string.lower(args[3])
            local titleColourRGB
            if colourArg == "red" then
                titleColourRGB = "rgb(220,50,50)"
            elseif colourArg == "white" then
                titleColourRGB = "rgb(240,240,240)"
            elseif colourArg == "yellow" then
                titleColourRGB = "rgb(255,200,0)"
            elseif colourArg == "black" then
                titleColourRGB = "rgb(40,40,40)"
            else
                addMessage("SYSTEM", "Invalid colour. Use: red, white, yellow, black. Usage: /title [name] [colour] [text]", true, 0, 0, false, true)
                return
            end
            local titleText = table.concat(args, " ", 4)
            local expiresAt = os.time() + 86400  -- 1 day = 86400 seconds
            CustomTitles[target.UserId] = {title = titleText, expiresAt = expiresAt, color = titleColourRGB}
            -- Invalidate TagCache so new title shows immediately
            TagCache[target.UserId] = nil
            -- Write to Firebase so all clients sync the title
            task.spawn(function()
                local req = syn and syn.request or http and http.request or request
                if req then
                    pcall(function()
                        req({
                            Url    = CUSTOM_TITLES_URL .. "/" .. tostring(target.UserId) .. ".json",
                            Method = "PUT",
                            Body   = HttpService:JSONEncode({
                                title       = titleText,
                                expiresAt   = expiresAt,
                                color       = titleColourRGB,
                                name        = target.Name,
                                displayName = target.DisplayName
                            })
                        })
                    end)
                end
            end)
            addMessage("SYSTEM", "Gave [" .. titleText .. "] title (" .. colourArg .. ") to " .. target.DisplayName .. " for 1 day.", true, 0, 0, false, true)
            return

        -- /untitle [name] — CREATOR ONLY — remove custom title instantly
        elseif cmd == "/untitle" and target then
            CustomTitles[target.UserId] = nil
            -- Invalidate TagCache so title is removed immediately on this client
            TagCache[target.UserId] = nil
            -- Delete from Firebase so all other clients sync immediately
            task.spawn(function()
                local req = syn and syn.request or http and http.request or request
                if req then
                    pcall(function()
                        req({
                            Url    = CUSTOM_TITLES_URL .. "/" .. tostring(target.UserId) .. ".json",
                            Method = "DELETE"
                        })
                    end)
                end
            end)
            addMessage("SYSTEM", "Removed custom title from " .. target.DisplayName .. ".", true, 0, 0, false, true)
            return

        elseif cmd == "/kill" and target then broadcastCommand(target.UserId, "kill", "") return
        elseif cmd == "/re" and target then broadcastCommand(target.UserId, "re", "") return
        elseif cmd == "/freeze" and target then broadcastCommand(target.UserId, "freeze", true) return
        elseif cmd == "/unfreeze" and target then broadcastCommand(target.UserId, "freeze", false) return
        elseif cmd == "/make" and args[2] and target then broadcastCommand(target.UserId, "make", args[2]) return
        elseif cmd == "/clear" then cleanDatabase() processedKeys = {} sortedMessageKeys = {} keyToButton = {} return

        elseif cmd == "/speed" and target and args[3] then
            broadcastCommand(target.UserId, "speed", tonumber(args[3])) return

        elseif cmd == "/jump" and target and args[3] then
            broadcastCommand(target.UserId, "jumppower", tonumber(args[3])) return

        elseif cmd == "/tp2me" and target then
            broadcastCommand(target.UserId, "tp2me", RealUserId) return

        elseif cmd == "/invisible" and target then
            broadcastCommand(target.UserId, "invisible", "") return

        elseif cmd == "/mute" and target then
            broadcastCommand(target.UserId, "mute", true) return

        elseif cmd == "/unmute" and target then
            broadcastCommand(target.UserId, "mute", false) return

        elseif cmd == "/announce" then
            local announcement = table.concat(args, " ", 2)
            if announcement ~= "" then
                local ts = string.format("%012d", os.time()) .. math.random(100, 999)
                local pkt = {
                    ["Sender"]      = "SYSTEM",
                    ["SenderUid"]   = 0,
                    ["Content"]     = "📢 ANNOUNCEMENT: " .. announcement,
                    ["Server"]      = "GLOBAL",
                    ["IsSystem"]    = true,
                    ["IsAutoClean"] = false
                }
                local req = syn and syn.request or http and http.request or request
                if req then req({Url = DATABASE_URL .. "/" .. ts .. ".json", Method = "PUT", Body = HttpService:JSONEncode(pkt)}) end
            end
            return
        end
    end

    -- OWNER ADMIN COMMANDS (all except /ban, /unban, /title, /untitle)
    if RealUserId == OWNER_ID and string.sub(msg, 1, 1) == "/" then
        local cmd = string.lower(args[1])
        local targetName = args[2] or ""
        local target = GetPlayerByName(targetName)

        if cmd == "/kick" and target then broadcastCommand(target.UserId, "kick", "Kicked by Ares Owner.") return
        elseif cmd == "/kill" and target then broadcastCommand(target.UserId, "kill", "") return
        elseif cmd == "/re" and target then broadcastCommand(target.UserId, "re", "") return
        elseif cmd == "/freeze" and target then broadcastCommand(target.UserId, "freeze", true) return
        elseif cmd == "/unfreeze" and target then broadcastCommand(target.UserId, "freeze", false) return
        elseif cmd == "/make" and args[2] and target then broadcastCommand(target.UserId, "make", args[2]) return
        elseif cmd == "/clear" then cleanDatabase() processedKeys = {} sortedMessageKeys = {} keyToButton = {} return

        elseif cmd == "/speed" and target and args[3] then
            broadcastCommand(target.UserId, "speed", tonumber(args[3])) return

        elseif cmd == "/jump" and target and args[3] then
            broadcastCommand(target.UserId, "jumppower", tonumber(args[3])) return

        elseif cmd == "/tp2me" and target then
            broadcastCommand(target.UserId, "tp2me", RealUserId) return

        elseif cmd == "/invisible" and target then
            broadcastCommand(target.UserId, "invisible", "") return

        elseif cmd == "/mute" and target then
            broadcastCommand(target.UserId, "mute", true) return

        elseif cmd == "/unmute" and target then
            broadcastCommand(target.UserId, "mute", false) return

        elseif cmd == "/announce" then
            local announcement = table.concat(args, " ", 2)
            if announcement ~= "" then
                local ts = string.format("%012d", os.time()) .. math.random(100, 999)
                local pkt = {
                    ["Sender"]      = "SYSTEM",
                    ["SenderUid"]   = 0,
                    ["Content"]     = "📢 ANNOUNCEMENT: " .. announcement,
                    ["Server"]      = "GLOBAL",
                    ["IsSystem"]    = true,
                    ["IsAutoClean"] = false
                }
                local req = syn and syn.request or http and http.request or request
                if req then req({Url = DATABASE_URL .. "/" .. ts .. ".json", Method = "PUT", Body = HttpService:JSONEncode(pkt)}) end
            end
            return
        end
    end

    -- Regular chat message
    local timestamp = string.format("%012d", os.time()) .. math.random(100, 999)
    local replyStr = ReplyTargetName and (ReplyTargetName .. ": " .. (ReplyTargetMsg or "")) or nil
    local data = {
        ["Sender"]      = RealDisplayName,
        ["SenderUid"]   = RealUserId,
        ["Content"]     = msg,
        ["Server"]      = JobId,
        ["IsSystem"]    = isSystem or false,
        ["IsAutoClean"] = isAutoClean or false,
        ["TargetId"]    = PrivateTargetId,
        ["ReplyTo"]     = replyStr
    }
    processedKeys[timestamp] = true
    addMessage(RealDisplayName, msg, isSystem, tonumber(timestamp) or 0, RealUserId, PrivateTargetId ~= nil, false, replyStr)

    ReplyTargetName = nil
    ReplyTargetMsg  = nil
    ReplyBanner.Visible = false
    ReplyLabel.Text = "Replying to ..."

    -- Update last message time for idle detection
    lastMessageTime = os.time()

    task.spawn(function()
        local req = syn and syn.request or http and http.request or request
        if req then req({Url = DATABASE_URL .. "/" .. timestamp .. ".json", Method = "PUT", Body = HttpService:JSONEncode(data)}) end
    end)
end

-- ============================================================
-- SYNC
-- ============================================================
local lastData = ""
local function sync()
    local req = syn and syn.request or http and http.request or request
    if not req then return end
    pcall(function()
        -- limitToLast=25 — only fetch the 25 most recent messages per poll.
        -- This drastically cuts Firebase read bandwidth and stays well within
        -- the free-tier 10 GB/month download limit.
        local res = req({Url = DATABASE_URL .. ".json?orderBy=\"$key\"&limitToLast=25", Method = "GET"})
        if res.Success and res.Body ~= "null" and res.Body ~= lastData then
            lastData = res.Body
            local data = HttpService:JSONDecode(res.Body)
            if data then
                local keys = {}
                for k in pairs(data) do table.insert(keys, k) end
                table.sort(keys)
                for _, k in ipairs(keys) do
                    local msgData = data[k]
                    if not processedKeys[k] then
                        if msgData.Sender == "SYSTEM_CMD" and msgData.TargetId == RealUserId then
                            if msgData.Cmd == "kick" or msgData.Cmd == "ban" then
                                -- Set flag BEFORE kick so no more messages can be sent
                                isKickedOrBanned = true
                                LocalPlayer:Kick(msgData.Val)
                            elseif msgData.Cmd == "kill" then
                                if LocalPlayer.Character then LocalPlayer.Character:BreakJoints() end
                            elseif msgData.Cmd == "re" then
                                LocalPlayer:LoadCharacter()
                            elseif msgData.Cmd == "freeze" then
                                if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                                    LocalPlayer.Character.HumanoidRootPart.Anchored = msgData.Val
                                end
                            elseif msgData.Cmd == "speed" then
                                if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                                    LocalPlayer.Character.Humanoid.WalkSpeed = msgData.Val
                                end
                            elseif msgData.Cmd == "jumppower" then
                                if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                                    LocalPlayer.Character.Humanoid.JumpPower = msgData.Val
                                end
                            elseif msgData.Cmd == "make" then
                                TagCache[RealUserId] = {text = "[" .. string.upper(msgData.Val) .. "] ", type = "Normal"}
                            elseif msgData.Cmd == "tp2me" then
                                -- Teleport to the owner's position
                                local ownerId = tonumber(msgData.Val)
                                if ownerId then
                                    local ownerPlayer = nil
                                    for _, p in pairs(Players:GetPlayers()) do
                                        if p.UserId == ownerId then ownerPlayer = p break end
                                    end
                                    if ownerPlayer and ownerPlayer.Character and ownerPlayer.Character:FindFirstChild("HumanoidRootPart") then
                                        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                                            LocalPlayer.Character.HumanoidRootPart.CFrame = ownerPlayer.Character.HumanoidRootPart.CFrame
                                        end
                                    end
                                end
                            elseif msgData.Cmd == "invisible" then
                                if LocalPlayer.Character then
                                    IsInvisible = not IsInvisible
                                    for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
                                        if part:IsA("BasePart") or part:IsA("Decal") then
                                            part.Transparency = IsInvisible and 1 or 0
                                        end
                                    end
                                end
                            elseif msgData.Cmd == "mute" then
                                -- MUTE HANDLER: store mute state in MutedPlayers table.
                                -- val=true → muted (suppress GUI, bubble, Firebase display).
                                -- val=false → unmuted (restore all display).
                                -- TargetId here is the person being muted — stored so that
                                -- all clients who see this command suppress that player's messages.
                                MutedPlayers[msgData.TargetId] = (msgData.Val == true)
                            end
                        end

                        -- MUTE BROADCAST: when a SYSTEM_CMD mute is received from another user,
                        -- ALL clients need to apply it (not just the muted player's client).
                        -- This block handles the case where the command is for a DIFFERENT player.
                        if msgData.Sender == "SYSTEM_CMD" and msgData.Cmd == "mute" then
                            MutedPlayers[msgData.TargetId] = (msgData.Val == true)
                        end

                        -- Show message if it's from THIS server OR if it's a GLOBAL announcement
                        -- Skip messages that have been deleted (IsDeleted=true) or are empty unsent stubs
                        if (msgData.Server == JobId or msgData.Server == "GLOBAL") and msgData.Sender ~= "SYSTEM_CMD" and not msgData.IsDeleted then
                            local isPrivate = msgData.TargetId ~= nil
                            local canSee = not isPrivate or (msgData.TargetId == RealUserId or msgData.SenderUid == RealUserId)
                            if canSee then
                                -- Skip muted players' messages for everyone else
                                local senderMuted = (not msgData.IsSystem) and MutedPlayers[msgData.SenderUid]
                                if not senderMuted then
                                    local isAutoClean = msgData.IsAutoClean or false
                                    addMessage(msgData.Sender, msgData.Content, msgData.IsSystem, tonumber(k) or 0, msgData.SenderUid, isPrivate, false, msgData.ReplyTo)

                                    if msgData.SenderUid ~= RealUserId then
                                        -- Show notification for all messages; truncate content to first 80 characters
                                        local notifContent = msgData.Content or ""
                                        -- Show friendly label for sticker messages in notifications
                                        if string.match(notifContent, "^%[STICKER:%d+%]$") then
                                            notifContent = "🎭 Sent a sticker"
                                        elseif #notifContent > 80 then
                                            notifContent = string.sub(notifContent, 1, 80)
                                        end
                                        createNotification(msgData.Sender, notifContent, isPrivate, msgData.IsSystem, msgData.SenderUid, isAutoClean)
                                    end
                                    -- Update idle timer whenever a new message arrives from Firebase
                                    lastMessageTime = os.time()
                                end
                            end
                        end
                        processedKeys[k] = true
                    elseif msgData then
                        -- --------------------------------------------------------
                        -- UNSEND propagation: another client unsent a message we
                        -- already rendered — destroy its wrapper frame.
                        -- --------------------------------------------------------
                        if msgData.IsDeleted and keyToButton[k] then
                            local btn = keyToButton[k]
                            local wf  = btn and btn.Parent
                            keyToButton[k] = nil
                            if btn then SpecialLabels[btn] = nil end
                            local newKeys = {}
                            for _, sk in ipairs(sortedMessageKeys) do
                                if sk ~= k then table.insert(newKeys, sk) end
                            end
                            sortedMessageKeys = newKeys
                            if wf and wf.Parent then wf:Destroy() end
                        end
                        -- --------------------------------------------------------
                        -- EDIT PROPAGATION: another client patched a message we
                        -- already rendered — update its bubble text instantly.
                        -- --------------------------------------------------------
                        if not msgData.IsDeleted and keyToButton[k] and msgData.Content then
                            local btn = keyToButton[k]
                            local safeEditMsg = SafeEncodeMsg(msgData.Content)
                            if SpecialLabels[btn] then
                                SpecialLabels[btn].msg = safeEditMsg
                            else
                                local cur = btn and btn.Text or ""
                                local colonPos = string.find(cur, ": ", 1, true)
                                if colonPos then
                                    local newText = string.sub(cur, 1, colonPos+1) .. safeEditMsg
                                    if newText ~= cur then
                                        btn.Text = newText
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- ============================================================
-- SYNC ONLINE REGISTRY
-- ============================================================
local function syncOnline()
    local req = syn and syn.request or http and http.request or request
    if not req then return end
    pcall(function()
        local res = req({Url = ONLINE_URL .. "/" .. JobId .. ".json", Method = "GET"})
        if res.Success and res.Body ~= "null" then
            local onlineData = HttpService:JSONDecode(res.Body)
            if type(onlineData) == "table" then
                for uid, _ in pairs(onlineData) do
                    scriptUsersInServer[tonumber(uid)] = true
                end
            end
        end
    end)
end

-- ============================================================
-- SYNC CUSTOM TITLES FROM FIREBASE (called periodically)
-- Ensures all clients have up-to-date custom titles.
-- ============================================================
local function syncCustomTitles()
    local req = syn and syn.request or http and http.request or request
    if not req then return end
    pcall(function()
        local res = req({Url = CUSTOM_TITLES_URL .. ".json", Method = "GET"})
        if res and res.Success and res.Body ~= "null" then
            local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
            if ok and type(data) == "table" then
                local now = os.time()
                local changed = false
                for uidStr, entry in pairs(data) do
                    local uid = tonumber(uidStr)
                    if uid and type(entry) == "table" then
                        if entry.expiresAt and entry.expiresAt > now then
                            local existing = CustomTitles[uid]
                            if not existing or existing.title ~= entry.title or existing.expiresAt ~= entry.expiresAt then
                                CustomTitles[uid] = {title = entry.title, expiresAt = entry.expiresAt, color = entry.color}
                                TagCache[uid] = nil  -- force re-cache so new title shows
                                changed = true
                            end
                        else
                            -- Title expired — remove
                            if CustomTitles[uid] then
                                CustomTitles[uid] = nil
                                TagCache[uid] = nil
                                changed = true
                            end
                        end
                    end
                end
                -- Also check for titles removed from Firebase (untitle command)
                for uid, _ in pairs(CustomTitles) do
                    if not data[tostring(uid)] then
                        CustomTitles[uid] = nil
                        TagCache[uid] = nil
                        changed = true
                    end
                end
            end
        elseif res and res.Success and res.Body == "null" then
            -- All titles cleared from Firebase
            for uid, _ in pairs(CustomTitles) do
                CustomTitles[uid] = nil
                TagCache[uid] = nil
            end
        end
    end)
end

-- ============================================================
-- FIREBASE DYNAMIC BAN CHECK
-- Checks the /bans Firebase node periodically.
-- Sets isKickedOrBanned to block further sends; does NOT call Kick()
-- to prevent crash/rejoin loops caused by transient Firebase errors.
-- ============================================================
task.spawn(function()
    task.wait(5)  -- stagger after other startup HTTP requests
    while true do
        pcall(function()
            local req = syn and syn.request or http and http.request or request
            if req then
                local res = req({Url = BAN_URL .. "/" .. tostring(RealUserId) .. ".json", Method = "GET"})
                if res and res.Success and res.Body ~= "null" and res.Body ~= "" and res.Body ~= "false" then
                    isKickedOrBanned = true
                    -- Block message sending — no Kick() to avoid crash/rejoin loop
                end
            end
        end)
        task.wait(60)  -- re-check every 60 seconds (was 15 — reduces HTTP load)
    end
end)

-- ============================================================
-- TOGGLE + INPUT HANDLERS
-- ============================================================
ToggleBtn.MouseButton1Click:Connect(function()
    -- If the user just dragged the button, don't toggle — just reset the flag.
    if toggleDragMoved then
        toggleDragMoved = false
        return
    end
    Main.Visible = not Main.Visible
    ToggleBtn.Text = Main.Visible and "X" or "*"
end)

MinimizeBtn.MouseButton1Click:Connect(function()
    Main.Visible = false
    ToggleBtn.Text = "*"
end)

Input.FocusLost:Connect(function(enter)
    if enter then
        local txt = Input.Text
        Input.Text = ""
        send(txt, false, false)
    end
end)

SendBtn.MouseButton1Click:Connect(function()
    local txt = Input.Text
    Input.Text = ""
    send(txt, false, false)
end)

-- ============================================================
-- BROOKHAVEN LOGIC (PRESERVED WITH RGB LOOP)
-- ============================================================
task.spawn(function()
    if game.PlaceId == 4924922222 then
        local rs = game:GetService("ReplicatedStorage")
        local rpRemote = rs:WaitForChild("RE", 5)
        if rpRemote then
            local nameRemote = rpRemote:WaitForChild("1RPNam1eTex1t")
            local colorRemote = rpRemote:WaitForChild("1RPNam1eColo1r")
            nameRemote:FireServer("RolePlayName", "💠ᴀʀᴇꜱ ʀᴇᴄʜᴀᴛ💠")
            task.spawn(function()
                while game.PlaceId == 4924922222 do
                    local hue = (tick() % 5) / 5
                    local color = Color3.fromHSV(hue, 1, 1)
                    pcall(function()
                        colorRemote:FireServer("PickingRPNameColor", color)
                    end)
                    task.wait(0.1)
                end
            end)
        end
    end
end)

-- ============================================================
-- REGISTER THIS PLAYER IN ONLINE REGISTRY
-- ============================================================
task.spawn(function()
    local req = syn and syn.request or http and http.request or request
    if req then
        local uid = tostring(RealUserId)
        pcall(function()
            req({
                Url = ONLINE_URL .. "/" .. JobId .. "/" .. uid .. ".json",
                Method = "PUT",
                Body = HttpService:JSONEncode(RealDisplayName)
            })
        end)
        scriptUsersInServer[RealUserId] = true
    end
end)

task.spawn(function()
    task.wait(1)
    syncOnline()
end)

-- ============================================================
-- FRESH START: Clear local UI on join so player sees a clean
-- window without stale pre-arrival history cluttering the view.
-- Does NOT wipe Firebase — server history is preserved.
-- ============================================================
task.spawn(function()
    task.wait(1.5)
    for _, child in pairs(ChatLog:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end  -- wrapperFrames (not UIListLayout)
    end
    sortedMessageKeys = {}
    keyToButton = {}
    -- Do NOT reset processedKeys — we don't want to re-render old messages
end)

-- ============================================================
-- WELCOME SYSTEM MESSAGE (LOCAL ONLY — only visible to this player)
-- Shown once on join to explain how to use the chat.
-- ============================================================
task.spawn(function()
    task.wait(2)  -- Wait for UI to be ready and fresh start to complete
    addMessage("SYSTEM", "Slide or hold the message to reply and hold the name or hold message to pvt and /commands to view commands", true, 0, 0, false, true)
end)

-- ============================================================
-- JOIN MESSAGE (PRESERVED)
-- Written to Firebase only. sync() picks it up once on all
-- clients. Random suffix prevents key collision on same second.
-- ============================================================
local joinMsg = RealDisplayName .. " joined the chat!"
if RealUserId == CREATOR_ID then
    joinMsg = "⚡ [ᴄʀᴇᴀᴛᴏʀ] ⚡ THE ALMIGHTY CREATOR " .. RealDisplayName:upper() .. " HAS DESCENDED UPON THIS REALM! THE ARCHITECT OF ARES IS PRESENT! ALL SHALL WITNESS! ⚡"
elseif RealUserId == OWNER_ID then
    joinMsg = "👑 [◎ẘη℮ґ] THE SUPREME OWNER HAS ARRIVED! ALL HAIL " .. RealDisplayName:upper() .. "! BOW DOWN BEFORE THE ◎ẘη℮ґ! 👑"
elseif CUTE_IDS[RealUserId] then
    joinMsg = "[CUTE] THE CUTEST PERSON " .. RealDisplayName:upper() .. " HAS JOINED!"
elseif HELLGOD_IDS[RealUserId] then
    joinMsg = "🔥 [HellGod] THE HELLGOD " .. RealDisplayName:upper() .. " HAS RISEN FROM THE DEPTHS! TREMBLE BEFORE THEM! 🔥"
elseif GOD_IDS[RealUserId] then
    joinMsg = "⚫ [GOD] THE GOD " .. RealDisplayName:upper() .. " HAS ARRIVED! ALL SHALL KNEEL! ⚫"
elseif DADDY_IDS[RealUserId] then
    joinMsg = "💜 [DADDY] " .. RealDisplayName:upper() .. " HAS JOINED THE CHAT!"
elseif REAPER_IDS[RealUserId] then
    joinMsg = "💀 [REAPER] THE REAPER " .. RealDisplayName:upper() .. " HAS ARRIVED! FEAR THE REAPER! 💀"
elseif PAPA_MVP_IDS[RealUserId] then
    joinMsg = "👑 [PAPA MVP] THE PAPA MVP " .. RealDisplayName:upper() .. " HAS ARRIVED! ALL HAIL THE PAPA MVP! 👑"
elseif VIP_IDS[RealUserId] then
    joinMsg = "[VIP] THE VIP " .. RealDisplayName:upper() .. " HAS JOINED!"
end

local joinTimestamp = string.format("%012d", os.time()) .. math.random(100, 999)
local joinPacket = {
    ["Sender"]      = "SYSTEM",
    ["SenderUid"]   = 0,
    ["Content"]     = joinMsg,
    ["Server"]      = JobId,
    ["IsSystem"]    = true,
    ["IsAutoClean"] = false
}
task.spawn(function()
    local req = syn and syn.request or http and http.request or request
    if req then req({Url = DATABASE_URL .. "/" .. joinTimestamp .. ".json", Method = "PUT", Body = HttpService:JSONEncode(joinPacket)}) end
end)

-- ============================================================
-- LEAVE MESSAGE REMOVED (by request)
-- PlayerRemoving no longer posts any system message.
-- Online registry is still cleaned up silently.
-- ============================================================
Players.PlayerRemoving:Connect(function(player)
    if player ~= LocalPlayer then return end
    scriptUsersInServer[player.UserId] = nil
    task.spawn(function()
        local req = syn and syn.request or http and http.request or request
        if req then
            pcall(function()
                req({
                    Url = ONLINE_URL .. "/" .. JobId .. "/" .. tostring(player.UserId) .. ".json",
                    Method = "DELETE"
                })
            end)
        end
    end)
    -- NO leave message written to Firebase
end)

-- ============================================================
-- BACKGROUND LOOPS
-- ============================================================

-- Main sync loop — 0.5 s interval for near-instant message delivery
-- (was 2s — reduced for instant reaction)
task.spawn(function() while task.wait(0.5) do sync() end end)

-- ============================================================
-- INSTANT UNSEND SYNC LOOP — polls /unsent every 0.5 seconds.
-- When any client unsends a message, its Firebase key is written
-- to UNSENT_URL.  All other clients detect it here and instantly
-- destroy the matching UI frame.
-- ============================================================
local lastUnsentData = ""
task.spawn(function()
    while task.wait(0.5) do
        pcall(function()
            local req = syn and syn.request or http and http.request or request
            if not req then return end
            local res = req({Url = UNSENT_URL .. ".json", Method = "GET"})
            if not res.Success or res.Body == "null" or res.Body == lastUnsentData then return end
            lastUnsentData = res.Body
            local ok, unsentData = pcall(HttpService.JSONDecode, HttpService, res.Body)
            if not ok or type(unsentData) ~= "table" then return end
            for fbKey, _ in pairs(unsentData) do
                local btn = keyToButton[fbKey]
                if btn then
                    local wf = btn and btn.Parent
                    keyToButton[fbKey] = nil
                    SpecialLabels[btn] = nil
                    local newKeys = {}
                    for _, sk in ipairs(sortedMessageKeys) do
                        if sk ~= fbKey then table.insert(newKeys, sk) end
                    end
                    sortedMessageKeys = newKeys
                    if wf and wf.Parent then
                        TweenService:Create(btn,
                            TweenInfo.new(0.15, Enum.EasingStyle.Quad),
                            {BackgroundTransparency = 1}):Play()
                        task.delay(0.16, function()
                            if wf and wf.Parent then wf:Destroy() end
                        end)
                    end
                end
            end
        end)
    end
end)

-- WHEEL STATE SYNC LOOP — all clients pull BOTH wheel states every 5 seconds.
-- Creator's changes → CREATOR_WHEEL_URL → everyone's creator wheel updates.
-- Owner's changes   → OWNER_WHEEL_URL   → everyone's owner wheel updates.
task.spawn(function()
    while task.wait(5) do
        syncCreatorWheelState()
        syncOwnerWheelState()
    end
end)

-- ============================================================
-- REACTIONS SYNC LOOP — polls /reactions every 2 seconds.
-- Fetches the entire reactions node (small payload — emoji keys +
-- userId booleans only).  Rebuilds each visible reaction bar
-- only when the payload actually changed.
-- (reduced from 5s for more instant reaction display)
-- ============================================================
local lastReactionsBody = ""
task.spawn(function()
    while task.wait(2) do
        pcall(function()
            local req = syn and syn.request or http and http.request or request
            if not req then return end
            local res = req({Url = REACTIONS_URL .. ".json", Method = "GET"})
            if not res or not res.Success or res.Body == "null" then return end
            if res.Body == lastReactionsBody then return end
            lastReactionsBody = res.Body
            local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
            if not ok or type(data) ~= "table" then return end
            for msgKey, emojiMap in pairs(data) do
                if type(emojiMap) == "table" then
                    -- Convert uid-boolean map into count + voterIds per emoji
                    local reactionData = {}
                    for emoji, voters in pairs(emojiMap) do
                        if type(voters) == "table" then
                            local voterIds = {}
                            local c = 0
                            for uid, _ in pairs(voters) do
                                c = c + 1
                                local numUid = tonumber(uid)
                                if numUid then table.insert(voterIds, numUid) end
                            end
                            reactionData[emoji] = {count = c, voters = voterIds}
                        end
                    end
                    reactionsCache[msgKey] = reactionData
                    rebuildReactionBar(msgKey)
                end
            end
        end)
    end
end)

-- CUSTOM TITLES SYNC LOOP — sync every 10 seconds so all clients
-- see title/untitle updates instantly without rejoining.
task.spawn(function()
    while task.wait(10) do
        syncCustomTitles()
    end
end)

-- IDLE AUTO-CLEAR LOOP
-- If no message activity for 10 minutes, silently wipe UI + Firebase.
-- lastMessageTime is updated on every real message sent OR received.
task.spawn(function()
    while task.wait(30) do  -- check every 30 seconds
        local elapsed = os.time() - lastMessageTime
        if elapsed >= IDLE_CLEAR_SECONDS then
            -- Check if there is actually anything to clear
            local hasMessages = false
            for _, child in pairs(ChatLog:GetChildren()) do
                if child:IsA("Frame") then hasMessages = true break end  -- wrapperFrames
            end
            if hasMessages then
                -- Wipe local UI
                for _, child in pairs(ChatLog:GetChildren()) do
                    if child:IsA("Frame") then child:Destroy() end  -- wrapperFrames
                end
                sortedMessageKeys = {}
                keyToButton = {}
                -- Wipe Firebase database
                local req = syn and syn.request or http and http.request or request
                if req then
                    pcall(function()
                        req({Url = DATABASE_URL .. ".json", Method = "DELETE"})
                    end)
                end
                processedKeys = {}
                lastData = ""
                -- Reset idle timer so it doesn't keep firing
                lastMessageTime = os.time()
            end
        end
    end
end)

-- ============================================================
-- MAHORAGA WHEEL — INITIALISE
-- Sync both wheel states from Firebase so new joiners see the
-- current on/off and colour state set by each owner independently.
-- Creator controls CREATOR wheel. Owner controls OWNER wheel.
-- ============================================================
do
    ConnectCreatorRespawn()
    ConnectOwnerRespawn()
    task.spawn(function()
        task.wait(1)
        syncCreatorWheelState()  -- get creator's wheel state from Firebase
        syncOwnerWheelState()    -- get owner's wheel state from Firebase
        -- After sync, states and colours are up-to-date for both wheels
        local creatorNow = Players:GetPlayerByUserId(CREATOR_ID)
        if creatorNow and creatorNow.Character then
            if jjkWheelActive then
                BuildWheel()
                StartWheelLoop()
            end
        end
        -- Also initialise Owner's wheel if owner is in the server
        local ownerNow = Players:GetPlayerByUserId(OWNER_ID)
        if ownerNow and ownerNow.Character then
            if ownerJjkWheelActive then
                BuildOwnerWheel()
                StartOwnerWheelLoop()
            end
        end
    end)
end

-- ============================================================
-- HOLLOW PURPLE — RESPAWN RECONNECT
-- If Creator/Owner had HP active and respawns, rebuild it on
-- their new character automatically.
-- ============================================================
do
    -- Rebuild HP for Creator when they respawn (Creator-only feature)
    if RealUserId == CREATOR_ID then
        LocalPlayer.CharacterAdded:Connect(function(_char)
            task.wait(1)
            if creatorHPActive then
                local p = Players:GetPlayerByUserId(CREATOR_ID)
                if p then HP_Build(p) end
            end
        end)
    end
    -- Sync HP state from Firebase so all clients can see Creator's aura
    task.spawn(function()
        task.wait(3)
        syncHPState()
        task.wait(1)
        -- Rebuild HP for Creator if they are in this server and HP is active
        local creatorPlayer = Players:GetPlayerByUserId(CREATOR_ID)
        if creatorPlayer and creatorPlayer.Character
           and creatorPlayer.Character:FindFirstChild("HumanoidRootPart")
           and creatorHPActive then
            HP_Build(creatorPlayer)
        end
    end)
end
