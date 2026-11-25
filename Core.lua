local ADDON, SC = ...
_G.SmartChat = SC
SC.version = "0.7.41-network-map-visual-effects"
local _, _, _, interfaceVersion = GetBuildInfo()
SC.isForever = type(interfaceVersion) == "number" and interfaceVersion >= 16000 and interfaceVersion < 17000
SC.onLogin = {}

-- Forever has no cross-realm character names. A hyphen may separate a
-- character's surname, so do not use Ambiguate() there (it treats the suffix
-- as a realm). These helpers keep names comparable across chat links/events.
function SC.NameKey(name)
    if type(name) ~= "string" then return "" end
    if SC.isForever then
        local normalized = name:lower():gsub("%-", " "):gsub("%s+", " ")
        return (normalized:gsub("^%s+", ""):gsub("%s+$", ""))
    end
    if Ambiguate then return Ambiguate(name, "none"):lower() end
    return name:lower()
end

function SC.ShortName(name)
    if type(name) ~= "string" then return "" end
    if SC.isForever then return (name:gsub("%-", " ")) end
    if Ambiguate then return Ambiguate(name, "short") end
    return name
end

function SC.PlayerDisplayName(unit)
    local name, surname
    if UnitName then name, surname = UnitName(unit) end
    if SC.isForever and type(surname) == "string" and surname ~= "" then
        return tostring(name or "") .. " " .. surname
    end
    if type(name) == "string" and name ~= "" then return name end
    if GetUnitName then
        local ok, fullName = pcall(GetUnitName, unit, true)
        if ok and type(fullName) == "string" then return fullName end
    end
    return ""
end

function SC.WhisperTabID(name)
    return "w:" .. SC.NameKey(name)
end

---------------------------------------------------------------------
-- Tab definitions (static tabs). Private conversations share one Whisper tab.
---------------------------------------------------------------------
SC.TABS = {
    say     = { label = "Say",     chatType = "SAY",     color = { 1.00, 1.00, 1.00 } },
    global  = { label = "Global",  chatType = "SAY",     viewOnly = true, color = { 1.00, 0.82, 0.20 } },
    party   = { label = "Party",   chatType = "PARTY",   color = { 0.67, 0.67, 1.00 } },
    raid    = { label = "Raid",    chatType = "RAID",    color = { 1.00, 0.50, 0.00 } },
    guild   = { label = "Guild",   chatType = "GUILD",   color = { 0.25, 1.00, 0.25 } },
    general = { label = "General", chatType = "CHANNEL", channel = 1, color = { 1.00, 0.75, 0.75 } },
    whisper = { label = "Whisper", chatType = "WHISPER", color = { 1.00, 0.50, 1.00 } },
}
SC.defaultOrder = { "say", "global", "party", "raid", "guild", "general", "whisper" }

---------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------
SC.defaults = {
    activeTab = "global",
    order = { "say", "global", "party", "raid", "guild", "general", "whisper" },
    hidden = {},
    sound = { say = false, global = false, party = true, raid = true, guild = true, general = false, whisper = true },
    soundKit = { say = "PACK:wood_tap", global = "PACK:crystal_ping", party = "PACK:digital_pop", raid = "PACK:alert_pulse",
                 guild = "PACK:warm_ding", general = "PACK:soft_pluck", whisper = "PACK:soft_bell" },
    soundVolume = { say = 1, global = 1, party = 1, raid = 1, guild = 1, general = 1, whisper = 1 },
    soundMasterVolume = 1,
    soundNotificationsEnabled = true, -- Mute All toggle; preserves all volume settings
    soundLivePreview = false,         -- preview sound while adjusting volume sliders
    reorderStyle = "fixed",     -- retained for compatibility with older saved settings
    clickOpensEditBox = false,   -- tab click changes view only by default
    showDock = true,             -- show the vertical utility dock beside chat
    shortcutKeys = {},           -- SmartChat action -> last key assigned by the in-AddOn editor
    unread = true,              -- unread counter on tabs
    alertOwnName = true,        -- flash + sound when someone writes your character name
    alertWords = {},
    alertSound = "READY_CHECK",
    barX = -2, barY = 32,

    timestamps = true,
    timeFormat = "%H:%M",
    badges = true,
    nameColors = true,
    nameColorMode = "relationship", -- relationship or class (preserve the game's class color)
    webLinks = true, -- turn plain web and Discord addresses into copyable chat hyperlinks
    chatFontFace = "DEFAULT", -- DEFAULT, FRIZ, ARIALN, MORPHEUS or SKURRI
    chatFontSize = 0, -- 0 = use the font size configured by the game
    chatFontInput = true, -- use the selected chat font for the typing box too
    badgeColors = { F = "ff55ff55", B = "ff33ccff", G = "ff6699ff", P = "ffffff55", W = "ffcc66ff" },
    -- Independent identity colors. Guild and group colors are inherited live
    -- from their tab colors; every multi-relationship color is calculated
    -- from the current source colors in Chat.lua (not stored as fixed combos).
    -- Legacy G/P/combination values in older SavedVariables are ignored.
    colors = {
        F = { 0.30, 1.00, 0.30 },
        B = { 0.20, 0.70, 1.00 },
    },

    filterWords = {},
    filterMask = false,

    historyEnabled = false,
    historyDays = 7,      -- 0 = keep forever
    historyLoad = 100,    -- lines replayed at login
    historyMax = 1000,    -- hard cap on stored lines
    history = {},

    pinned = nil,
    whisperContacts = {}, -- recent private conversation contacts, shared by Whisper and Social Hub
    selectedWhisper = nil,

    social = {
        favorites = {},
        pinned = {},
        groups = {
            ["Dungeon Buddies"] = {},
            ["Raid Team"] = {},
            ["Trading Partners"] = {},
            ["Old Friends"] = {},
        },
        groupOrder = { "Dungeon Buddies", "Raid Team", "Trading Partners", "Old Friends" },
        sortMode = "status", -- status, name, recent
        onlineOnly = false,
        hub = {
            categoryVisibility = {
                overview = true, all = true, friends = true, guild = true,
                group = true, whispers = true, bnet = true, favorites = true,
                notes = true, recent = true, groups = true, journal = true,
                activity = true, ignored = true, networkMap = true,
            },
            categoryOrder = { "overview", "all", "friends", "guild", "group", "whispers", "bnet", "favorites", "notes", "recent", "groups", "journal", "activity", "ignored", "networkMap" },
            profileVisibility = { overview = true, history = true, notes = true, relationship = true, shared = true },
            profileOrder = { "overview", "history", "notes", "relationship", "shared" },
            rowStyle = "comfortable", -- compact or comfortable
            showStatusDot = true,
            showRelationshipBadges = true,
            showClassLevel = true,
            showContactGroups = true,
            showFavoritePinMarkers = true,
            networkMapEnabled = false, -- opt-in visual map; no graph is built until explicitly enabled
            networkMapLayout = "node", -- node, radial or mind
            networkMapAnimations = true,
            networkMapReduceMotion = false,
            networkMapMaxNodes = 24,
            networkMapFilter = "all",
            networkMapZoom = 100,
            networkMapTheme = "midnight",
        },
    },
    journal = {
        enabled = false, -- opt-in: no automatic social history until enabled
        trackFriends = true,
        trackGuild = true,
        trackGroups = true,
        trackWhispers = true,
        trackQuests = false,
        trackPresence = false,
        trackGuildPresence = false,
        trackGroupRoster = false,
        retentionDays = 90, -- 0 = no age limit; maxEvents still applies
        maxEvents = 500,
        events = {},
        notes = {},
    },
    socialNotifications = {
        enabled = false, -- opt-in; no popups until enabled
        friendOnline = true,
        friendOffline = false,
        friendChanges = true,
        guildChanges = false,
        guildPresence = false,
        groupChanges = false,
        bnetPresence = false,
    },

    customTabs = {},     -- user-made tabs, see SC.AddCustomTab
    customSeq = 0,
    override = {},       -- per-tab name/color changes of the built-in tabs
    display = {},        -- per-tab display filter (nil = show everything), see View.lua
    replyOff = {},       -- tabs where Ctrl+click reply is switched off
    windowAlpha = 1,     -- opacity of SmartChat windows (settings, tab menus, copy)
    barAlpha = 0.35,     -- opacity of the tab bar background
    -- chatAlpha is only stored once you move the "Chat background" slider
}

local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = deepcopy(v) end
    return c
end
SC.deepcopy = deepcopy

local NO_MERGE = { order = true, filterWords = true, alertWords = true, history = true, customTabs = true }
local function merge(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = deepcopy(v)
        elseif type(v) == "table" and type(dst[k]) == "table" and not NO_MERGE[k] then
            merge(dst[k], v)
        end
    end
end

---------------------------------------------------------------------
-- Midnight (12.x) safety helpers: chat text/names can be "secret values"
-- during encounters. We never touch them in that case.
---------------------------------------------------------------------
function SC.IsSecret(v)
    if issecretvalue then return issecretvalue(v) and true or false end
    return false
end

function SC.Safe(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v ~= nil and SC.IsSecret(v) then return false end
    end
    return true
end

function SC.Lockdown()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, res = pcall(C_ChatInfo.InChatMessagingLockdown)
        return ok and res and true or false
    end
    return false
end

-- Original SmartChat Sound Pack: ten short notification sounds. Each sound
-- ships with ten pre-rendered gain levels (10%..100%) so custom files can
-- be volume-controlled without changing the game's global audio CVars.
SC.SOUND_PACK = {
    { id = "soft_bell",    label = "Soft Bell" },
    { id = "crystal_ping", label = "Crystal Ping" },
    { id = "wood_tap",     label = "Wood Tap" },
    { id = "digital_pop",  label = "Digital Pop" },
    { id = "double_chime", label = "Double Chime" },
    { id = "bubble_drop",  label = "Bubble Drop" },
    { id = "warm_ding",    label = "Warm Ding" },
    { id = "soft_pluck",   label = "Soft Pluck" },
    { id = "star_spark",   label = "Star Spark" },
    { id = "alert_pulse",  label = "Alert Pulse" },
}
SC.SOUND_CHOICES = {
    "TELL_MESSAGE", "UI_BNET_TOAST", "MAP_PING", "READY_CHECK", "RAID_WARNING",
    "IG_MAINMENU_OPEN", "IG_QUEST_LIST_OPEN", "AUCTION_WINDOW_OPEN", "IG_CHARACTER_INFO_OPEN",
    "UI_RAID_BOSS_WHISPER_WARNING", "IG_PLAYER_INVITE", "IG_ABILITY_OPEN", "LEVEL_UP",
    "QUEST_ACTIVE", "GS_LOGIN", "UI_QUEST_ROLLING_FORWARD_01",
}

function SC.AvailableSounds()
    local list = { "NONE" }
    for _, k in ipairs(SC.SOUND_CHOICES) do
        if SOUNDKIT and SOUNDKIT[k] then list[#list + 1] = k end
    end
    for _, sound in ipairs(SC.SOUND_PACK) do list[#list + 1] = "PACK:" .. sound.id end
    return list
end

function SC.SoundDisplayName(name)
    if not name or name == "NONE" then return "No sound" end
    if type(name) == "string" and name:sub(1, 5) == "PACK:" then
        local id = name:sub(6)
        for _, sound in ipairs(SC.SOUND_PACK) do
            if sound.id == id then return sound.label .. "  |cff55ccff[Pack]|r" end
        end
        return "Missing pack sound"
    end
    return name
end

function SC.SoundTabKey(tabId)
    if type(tabId) == "string" and tabId:sub(1, 2) == "w:" then return "whisper" end
    return tabId
end

function SC.GetTabSoundVolume(tabId)
    local key = SC.SoundTabKey(tabId)
    local value = SC.db and SC.db.soundVolume and SC.db.soundVolume[key]
    if type(value) ~= "number" then return 1 end
    return math.max(0, math.min(1, value))
end

-- Effective level = per-tab level multiplied by Master Volume. Mute All
-- returns zero without changing either stored level.
function SC.GetSoundVolume(tabId)
    if not SC.db or SC.db.soundNotificationsEnabled == false then return 0 end
    local master = tonumber(SC.db.soundMasterVolume) or 1
    master = math.max(0, math.min(1, master))
    return SC.GetTabSoundVolume(tabId) * master
end

local function PlaySoundPack(name, volume)
    local id = name:sub(6)
    local known = false
    for _, sound in ipairs(SC.SOUND_PACK) do if sound.id == id then known = true break end end
    if not known or type(PlaySoundFile) ~= "function" then return nil end
    local step = math.floor(volume * 10 + 0.5)
    step = math.max(1, math.min(10, step)) * 10
    local path = "Interface\\AddOns\\" .. ADDON .. "\\Sounds\\" .. id .. "_" .. string.format("%03d", step) .. ".ogg"
    local ok, success, handle = pcall(PlaySoundFile, path, "Master")
    if ok and success then return handle end
    return nil
end

-- Play either a bundled Sound Pack file or a built-in SoundKit. The pack uses
-- discrete pre-rendered 10% steps; SoundKit sounds use volumeOverride.
function SC.PlayKit(name, volume)
    if not name or name == "NONE" then return nil end
    if not SC.db or SC.db.soundNotificationsEnabled == false then return nil end
    if volume == nil then
        volume = (tonumber(SC.db.soundMasterVolume) or 1)
    end
    volume = math.max(0, math.min(1, tonumber(volume) or 1))
    if volume <= 0 then return nil end

    if type(name) == "string" and name:sub(1, 5) == "PACK:" then
        return PlaySoundPack(name, volume)
    end

    local id = SOUNDKIT and SOUNDKIT[name]
    if not id then return nil end
    if C_Sound and type(C_Sound.PlaySound) == "function" then
        local ok, willPlay, handle = pcall(C_Sound.PlaySound, id, "Master", false, false, nil, volume)
        if ok then return willPlay and handle or nil end
    end
    if type(PlaySound) == "function" then
        local ok, willPlay, handle = pcall(PlaySound, id, "Master")
        if ok and willPlay then return handle end
    end
    return nil
end

function SC.Print(...)
    print("|cff33ccffSmartChat:|r", ...)
end

---------------------------------------------------------------------
-- Chat edit-box compatibility. Forever uses the modern EditBox methods;
-- older clients can still use the legacy attributes as a fallback.
---------------------------------------------------------------------
function SC.GetEditBoxChatType(eb)
    if not eb then return nil end
    if eb.GetChatType then
        local ok, value = pcall(eb.GetChatType, eb)
        if ok then return value end
    end
    if eb.GetAttribute then
        local ok, value = pcall(eb.GetAttribute, eb, "chatType")
        if ok then return value end
    end
    return nil
end

function SC.SetEditBoxChatType(eb, chatType)
    if not eb then return false end
    if eb.SetChatType then return pcall(eb.SetChatType, eb, chatType) end
    if eb.SetAttribute then return pcall(eb.SetAttribute, eb, "chatType", chatType) end
    return false
end

function SC.GetEditBoxTellTarget(eb)
    if not eb then return nil end
    if eb.GetTellTarget then
        local ok, value = pcall(eb.GetTellTarget, eb)
        if ok then return value end
    end
    if eb.GetAttribute then
        local ok, value = pcall(eb.GetAttribute, eb, "tellTarget")
        if ok then return value end
    end
    return nil
end

function SC.SetEditBoxTellTarget(eb, target)
    if not eb then return false end
    if eb.SetTellTarget then return pcall(eb.SetTellTarget, eb, target) end
    if eb.SetAttribute then return pcall(eb.SetAttribute, eb, "tellTarget", target) end
    return false
end

function SC.SetEditBoxChannelTarget(eb, target)
    if not eb then return false end
    if eb.SetChannelTarget then return pcall(eb.SetChannelTarget, eb, target) end
    if eb.SetAttribute then return pcall(eb.SetAttribute, eb, "channelTarget", target) end
    return false
end

function SC.SetEditBoxStickyType(eb, chatType)
    if not eb then return false end
    if eb.SetStickyType then return pcall(eb.SetStickyType, eb, chatType) end
    if eb.SetAttribute then return pcall(eb.SetAttribute, eb, "stickyType", chatType) end
    return false
end

function SC.GetEditBoxStickyType(eb)
    if not eb then return nil end
    if eb.GetStickyType then
        local ok, value = pcall(eb.GetStickyType, eb)
        if ok then return value end
    end
    if eb.GetAttribute then
        local ok, value = pcall(eb.GetAttribute, eb, "stickyType")
        if ok then return value end
    end
    return nil
end

function SC.UpdateChatHeader(eb)
    if not eb then return false end
    if eb.UpdateHeader then return pcall(eb.UpdateHeader, eb) end
    if ChatEdit_UpdateHeader then return pcall(ChatEdit_UpdateHeader, eb) end
    return false
end

function SC.OpenChat(text, chatFrame)
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        local ok, editBox = pcall(ChatFrameUtil.OpenChat, text or "", chatFrame)
        if ok then
            if editBox then return editBox end
            if ChatFrameUtil.GetActiveWindow then
                local activeOK, active = pcall(ChatFrameUtil.GetActiveWindow)
                if activeOK and active then return active end
            end
            return chatFrame and chatFrame.editBox or nil
        end
    end
    if ChatFrame_OpenChat then
        local ok = pcall(ChatFrame_OpenChat, text or "", chatFrame)
        if ok then return chatFrame and chatFrame.editBox end
    end
    local editBox = chatFrame and chatFrame.editBox
    if editBox and editBox.Show then pcall(editBox.Show, editBox) end
    return editBox
end

function SC.Hex(c)
    local function b(x) return math.floor(math.max(0, math.min(1, x)) * 255 + 0.5) end
    return string.format("%02x%02x%02x", b(c[1]), b(c[2]), b(c[3]))
end

---------------------------------------------------------------------
-- Windows opacity
---------------------------------------------------------------------
SC.windows = {}
-- bg / border = { r, g, b, a } base colors of the frame's backdrop
function SC.RegisterWindow(frame, bg, border)
    SC.windows[#SC.windows + 1] = { f = frame, bg = bg or { 1, 1, 1, 1 }, border = border or { 1, 1, 1, 1 } }
    if SC.db then SC.ApplyWindowAlpha() end
end

-- Bring an independent SmartChat window above its parent/settings window.
-- FULLSCREEN_DIALOG is above DIALOG; frame levels are advanced on each show so
-- the most recently opened SmartChat child panel is the visible top window.
SC._windowRaiseLevel = SC._windowRaiseLevel or 200
function SC.RaiseWindow(frame, strata)
    if not frame then return false end
    if strata and frame.SetFrameStrata then
        pcall(frame.SetFrameStrata, frame, strata)
    end
    if frame.SetToplevel then pcall(frame.SetToplevel, frame, true) end
    SC._windowRaiseLevel = (tonumber(SC._windowRaiseLevel) or 200) + 10
    if SC._windowRaiseLevel > 60000 then SC._windowRaiseLevel = 200 end
    if frame.SetFrameLevel then pcall(frame.SetFrameLevel, frame, SC._windowRaiseLevel) end
    if frame.Raise then pcall(frame.Raise, frame) end
    return true
end

function SC.ApplyWindowAlpha()
    local a = SC.db and SC.db.windowAlpha or 1
    for _, w in ipairs(SC.windows) do
        if w.f.SetBackdropColor then
            w.f:SetBackdropColor(w.bg[1], w.bg[2], w.bg[3], w.bg[4] * a)
            w.f:SetBackdropBorderColor(w.border[1], w.border[2], w.border[3], w.border[4] * a)
        end
    end
end

-- background of the game's own chat window(s)
function SC.ApplyChatAlpha(a)
    SC.db.chatAlpha = a
    if not FCF_SetWindowAlpha then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = _G["ChatFrame" .. i]
        if f then pcall(FCF_SetWindowAlpha, f, a) end
    end
end

---------------------------------------------------------------------
-- Tab look (name / color) of built-in tabs
---------------------------------------------------------------------
local function copyColor(c) return { c[1], c[2], c[3] } end

function SC.CaptureBase()
    SC.BASE = {}
    for id, d in pairs(SC.TABS) do SC.BASE[id] = { label = d.label, color = copyColor(d.color) } end
end

function SC.ApplyOverrides()
    for id, ov in pairs(SC.db.override) do
        local d = SC.TABS[id]
        if d and not d.custom and SC.BASE[id] then
            if ov.label then d.label = ov.label end
            if ov.color then d.color = copyColor(ov.color) end
        end
    end
end

-- label / color may be nil to leave that part alone
function SC.SetTabLook(id, label, color)
    local d = SC.TABS[id]
    if not d then return end
    if d.custom then
        if label then d.label = label end
        if color then d.color = copyColor(color) end
    else
        local ov = SC.db.override[id]
        if not ov then ov = {}; SC.db.override[id] = ov end
        if label then ov.label = label; d.label = label end
        if color then ov.color = copyColor(color); d.color = copyColor(color) end
    end
    if SC.RefreshTabLook then SC.RefreshTabLook(id) end
end

function SC.ResetTab(id)
    local d, base = SC.TABS[id], SC.BASE and SC.BASE[id]
    if not d or d.custom or not base then return end
    SC.db.override[id] = nil
    d.label, d.color = base.label, copyColor(base.color)
    SC.db.sound[id] = SC.defaults.sound[id]
    SC.db.soundKit[id] = SC.defaults.soundKit[id]
    SC.db.soundVolume[id] = SC.defaults.soundVolume[id] or 1
    SC.db.hidden[id] = nil
    SC.db.display[id] = SC.PresetDisplay and SC.PresetDisplay(id) or nil
    if SC.RefreshTabLook then SC.RefreshTabLook(id) end
    if SC.RebuildTabs then SC.RebuildTabs() end
    if SC.View then SC.View.Refresh(true) end
end

---------------------------------------------------------------------
-- Custom tabs
---------------------------------------------------------------------
SC.CHAT_TYPES = {
    { type = "SAY",           label = "Say" },
    { type = "YELL",          label = "Yell" },
    { type = "PARTY",         label = "Party" },
    { type = "RAID",          label = "Raid" },
    { type = "GUILD",         label = "Guild" },
    { type = "OFFICER",       label = "Officer" },
    { type = "INSTANCE_CHAT", label = "Instance" },
    { type = "CHANNEL",       label = "Channel (Trade, LFG, custom...)" },
}

-- which chat events belong to a tab of each type (used for flash / sound / unread)
SC.TYPE_EVENTS = {
    SAY           = { "CHAT_MSG_SAY", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" },
    YELL          = { "CHAT_MSG_YELL" },
    PARTY         = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_PARTY_GUIDE" },
    RAID          = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING" },
    GUILD         = { "CHAT_MSG_GUILD", "CHAT_MSG_GUILD_ACHIEVEMENT", "CHAT_MSG_COMMUNITIES_GUILD" },
    OFFICER       = { "CHAT_MSG_OFFICER" },
    INSTANCE_CHAT = { "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" },
    CHANNEL       = { "CHAT_MSG_CHANNEL" },
}

SC.PALETTE = {
    { 1.00, 0.82, 0.00 }, { 0.40, 0.80, 1.00 }, { 0.50, 1.00, 0.50 }, { 1.00, 0.50, 0.50 },
    { 1.00, 0.60, 0.20 }, { 0.80, 0.50, 1.00 }, { 0.30, 1.00, 0.90 }, { 1.00, 1.00, 1.00 },
}
SC.MAX_CUSTOM = 8

function SC.LoadCustomTabs()
    for _, c in ipairs(SC.db.customTabs) do SC.TABS[c.id] = c end
end

function SC.AddCustomTab(label, chatType, channelMatch, color)
    local db = SC.db
    if #db.customTabs >= SC.MAX_CUSTOM then return false, "Maximum " .. SC.MAX_CUSTOM .. " custom tabs." end
    label = (label or ""):gsub("^%s+", "")
    label = label:gsub("%s+$", "")
    if label == "" then return false, "Give the tab a name." end
    label = label:sub(1, 14)
    if not SC.TYPE_EVENTS[chatType] then return false, "Unknown chat type." end
    channelMatch = (channelMatch or ""):gsub("^%s+", "")
    channelMatch = channelMatch:gsub("%s+$", "")
    if chatType == "CHANNEL" and channelMatch == "" then
        return false, "Type the channel name (or number) for a Channel tab."
    end
    color = color or SC.PALETTE[1]
    db.customSeq = (db.customSeq or 0) + 1
    local id = "c" .. db.customSeq
    local c = {
        id = id, label = label, chatType = chatType, custom = true,
        channelMatch = (chatType == "CHANNEL") and channelMatch or nil,
        color = { color[1], color[2], color[3] },
    }
    table.insert(db.customTabs, c)
    SC.TABS[id] = c
    if SC.PresetDisplay then db.display[id] = SC.PresetDisplay(id) end
    table.insert(db.order, id)
    db.sound[id] = true
    db.soundKit[id] = "PACK:soft_bell"
    db.soundVolume[id] = 1
    if SC.RebuildTabs then SC.RebuildTabs() end
    return true, id
end

function SC.RemoveCustomTab(id)
    local db = SC.db
    for i, c in ipairs(db.customTabs) do
        if c.id == id then table.remove(db.customTabs, i) break end
    end
    SC.TABS[id] = nil
    for i, v in ipairs(db.order) do if v == id then table.remove(db.order, i) break end end
    db.hidden[id], db.sound[id], db.soundKit[id], db.soundVolume[id], db.display[id] = nil, nil, nil, nil, nil
    if db.activeTab == id then db.activeTab = "party" end
    if SC.RebuildTabs then SC.RebuildTabs() end
end

---------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        SmartChatDB = SmartChatDB or {}
        merge(SmartChatDB, SC.defaults)
        SC.db = SmartChatDB
        SC.CaptureBase()
        SC.ApplyOverrides()
        SC.LoadCustomTabs()
        if SC.ApplyDisplayDefaults then SC.ApplyDisplayDefaults() end
    elseif event == "PLAYER_LOGIN" then
        for _, fn in ipairs(SC.onLogin) do
            local ok, err = pcall(fn)
            if not ok then print("|cffff4444SmartChat error:|r", err) end
        end
    end
end)
