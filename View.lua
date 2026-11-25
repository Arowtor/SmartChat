local ADDON, SC = ...

-- Per-tab display filter for the main chat window.
-- Every line that reaches the main chat frame is remembered together with its
-- type (party, guild, whisper, system, loot ...). The active tab decides which
-- types are shown. Changing tab rebuilds the window from the remembered lines.
-- No chat windows are created or removed.

local View = {}
SC.View = View
SC.dynDisplay = {}   -- display settings of whisper tabs (this session only)

local BUFFER_MAX = 800
local buffer = {}

SC.CATEGORIES = {
    { key = "say",      label = "Say" },
    { key = "emote",    label = "Emotes" },
    { key = "yell",     label = "Yell" },
    { key = "party",    label = "Party" },
    { key = "raid",     label = "Raid" },
    { key = "instance", label = "Instance" },
    { key = "guild",    label = "Guild" },
    { key = "officer",  label = "Officer" },
    { key = "whisper",  label = "Whispers" },
    { key = "channel",  label = "Channels" },
    { key = "system",   label = "System" },
    { key = "loot",     label = "Loot / XP" },
    { key = "npc",      label = "NPC speech" },
    { key = "other",    label = "Other" },
}

local CAT = {
    SAY = "say", EMOTE = "emote", TEXT_EMOTE = "emote", YELL = "yell",
    PARTY = "party", PARTY_LEADER = "party", PARTY_GUIDE = "party",
    RAID = "raid", RAID_LEADER = "raid", RAID_WARNING = "raid",
    INSTANCE_CHAT = "instance", INSTANCE_CHAT_LEADER = "instance",
    GUILD = "guild", GUILD_ACHIEVEMENT = "guild", COMMUNITIES_GUILD = "guild", OFFICER = "officer",
    WHISPER = "whisper", WHISPER_INFORM = "whisper", REPLY = "whisper",
    BN_WHISPER = "whisper", BN_WHISPER_INFORM = "whisper",
    COMMUNITIES_CHANNEL = "channel",
    SYSTEM = "system", ERRORS = "system", IGNORED = "system", FILTERED = "system", RESTRICTED = "system",
    LOOT = "loot", MONEY = "loot", CURRENCY = "loot", SKILL = "loot", TRADESKILLS = "loot",
    OPENING = "loot", PET_INFO = "loot",
}

-- Each regular tab is strict about its own chat stream. Nearby emotes stay
-- with Say; Yell, Instance and Officer have their own stream/filter.
local PRESET = {
    SAY = { "say", "emote" }, YELL = { "yell" }, PARTY = { "party" },
    RAID = { "raid" }, GUILD = { "guild" }, OFFICER = { "officer" },
    INSTANCE_CHAT = { "instance" }, CHANNEL = { "channel" }, WHISPER = { "whisper" },
}
-- Non-chat game notices remain visible in regular tabs. Unknown/other lines
-- are Global-only by default so an unrecognized chat type cannot leak.
local EXTRAS = { "system", "loot", "npc" }

local idMap
local function BuildIdMap()
    idMap = {}
    if type(ChatTypeInfo) == "table" then
        for k, v in pairs(ChatTypeInfo) do
            if type(v) == "table" and type(v.id) == "number" then idMap[v.id] = k end
        end
    end
end

local function CategoryOf(key)
    local c = CAT[key]
    if c then return c end
    if key:find("^CHANNEL") or key == "COMMUNITIES_CHANNEL" then return "channel" end
    if key:find("^MONSTER") or key:find("^RAID_BOSS") then return "npc" end
    if key:find("^COMBAT") then return "loot" end
    return "other"
end

function View.Classify(text, id)
    -- Unclassified lines are treated as "other", not as universally visible.
    -- This prevents unknown chat types from leaking into every channel tab;
    -- Global still shows them because it has no restrictive display preset.
    if type(id) ~= "number" then return { cat = "other" } end
    if not idMap then BuildIdMap() end
    local key = idMap[id]
    local info = { cat = key and CategoryOf(key) or "other", key = key }
    info.lineID = tonumber(text:match("|Hplayer:[^:|]+:(%d+)"))
    if info.cat == "whisper" then
        info.who = text:match("|Hplayer:([^:|]+)")
    elseif info.cat == "channel" then
        local n, name = text:match("|Hchannel:[^:|]+:(%d+)|h%[([^%]]*)%]|h")
        info.chanNum = tonumber(n)
        info.chanText = name and name:lower()
    end
    return info
end

local function Visible(cfg, info)
    if not cfg then return true end
    if not cfg.cats[info.cat] then return false end
    if info.cat == "whisper" and cfg.whisperWith and info.who then
        if SC.NameKey(info.who) ~= SC.NameKey(cfg.whisperWith) then return false end
    end
    if info.cat == "channel" and cfg.chan and cfg.chan ~= "" then
        local n = tonumber(cfg.chan)
        if n then
            if info.chanNum ~= n then return false end
        elseif not (info.chanText and info.chanText:find(cfg.chan:lower(), 1, true)) then
            return false
        end
    end
    return true
end

local function CfgKey(cfg)
    if not cfg then return "ALL" end
    local t = {}
    for _, c in ipairs(SC.CATEGORIES) do if cfg.cats[c.key] then t[#t + 1] = c.key end end
    return table.concat(t, ",") .. "|" .. tostring(cfg.whisperWith) .. "|" .. tostring(cfg.chan)
end

---------------------------------------------------------------------
-- settings access
---------------------------------------------------------------------
function SC.GetDisplay(id)
    if not id then return nil end
    if id:sub(1, 2) == "w:" then return SC.dynDisplay[id] end
    return SC.db and SC.db.display[id]
end

-- cfg = nil  ->  show everything
function SC.SetDisplay(id, cfg)
    if id:sub(1, 2) == "w:" then SC.dynDisplay[id] = cfg else SC.db.display[id] = cfg end
    if id == SC.active then View.Refresh(true) end
end

function SC.AllCategories()
    local cats = {}
    for _, c in ipairs(SC.CATEGORIES) do cats[c.key] = true end
    return cats
end

local function DefOf(id)
    if SC.TABS[id] then return SC.TABS[id] end
    local t = SC.TabFrame and SC.TabFrame(id)
    return t and t.def
end

-- "this tab's own chat". strict = nothing else; otherwise game messages
-- (system, loot, NPC speech, other) stay visible too.
function SC.PresetDisplay(id, strict)
    local def = DefOf(id)
    if not def then return nil end
    if def.dynamic then return { cats = { whisper = true }, whisperWith = def.target } end
    if def.viewOnly then
        if not strict then return nil end -- Global defaults to every visible chat/game line.
        local cfg = { cats = {} }
        for _, key in ipairs({ "say", "emote", "yell", "party", "raid", "instance", "guild", "officer", "whisper", "channel" }) do
            cfg.cats[key] = true
        end
        return cfg
    end
    local list = PRESET[def.chatType]
    if not list then return nil end
    local cfg = { cats = {} }
    for _, k in ipairs(list) do cfg.cats[k] = true end
    if not strict then
        for _, k in ipairs(EXTRAS) do cfg.cats[k] = true end
    end
    if def.chatType == "CHANNEL" then
        -- Built-in General is channel 1; custom channel tabs use their exact
        -- name/number. Never let the General tab silently include every channel.
        cfg.chan = def.channelMatch or def.channel
    end
    return cfg
end

-- The previous defaults grouped related streams (for example Guild+Officer,
-- Party+Instance) and included "other" in every tab. Migrate only those old
-- generated presets to the stricter defaults; preserve filters the user edited.
local LEGACY_PRESET = {
    SAY = { "say", "emote", "yell" }, YELL = { "yell" }, PARTY = { "party", "instance" },
    RAID = { "raid", "instance" }, GUILD = { "guild", "officer" }, OFFICER = { "officer" },
    INSTANCE_CHAT = { "instance" }, CHANNEL = { "channel" }, WHISPER = { "whisper" },
}
local LEGACY_EXTRAS = { "system", "loot", "npc", "other" }

local function LegacyPresetDisplay(id)
    local def = DefOf(id)
    if not def or def.dynamic or def.viewOnly then return nil end
    local list = LEGACY_PRESET[def.chatType]
    if not list then return nil end
    local cfg = { cats = {} }
    for _, key in ipairs(list) do cfg.cats[key] = true end
    for _, key in ipairs(LEGACY_EXTRAS) do cfg.cats[key] = true end
    if def.chatType == "CHANNEL" then cfg.chan = def.channelMatch end
    return cfg
end

local function SameDisplay(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    local ac, bc = a.cats or {}, b.cats or {}
    for _, item in ipairs(SC.CATEGORIES) do
        if (ac[item.key] and true or false) ~= (bc[item.key] and true or false) then return false end
    end
    if tostring(a.chan or "") ~= tostring(b.chan or "") then return false end
    if tostring(a.whisperWith or "") ~= tostring(b.whisperWith or "") then return false end
    return true
end

function SC.ApplyDisplayDefaults()
    local db = SC.db
    db.display = db.display or {}
    local version = tonumber(db.displayDefaultsVersion) or 0
    if version >= 2 then return end

    for id in pairs(SC.TABS) do
        local current = db.display[id]
        local legacy = LegacyPresetDisplay(id)
        local isLegacyDefault = legacy and current and SameDisplay(current, legacy)
        if current == nil or isLegacyDefault then
            db.display[id] = SC.PresetDisplay(id)
        end
    end

    db.displayDefaultsApplied = true -- retained for backwards compatibility
    db.displayDefaultsVersion = 2
end

function SC.DisplaySummary(id)
    return SC.GetDisplay(id) and "Custom" or "Everything"
end

---------------------------------------------------------------------
-- called for every line sent to the main chat frame
-- returns false when the line must stay hidden in the current tab
---------------------------------------------------------------------
function View.Add(frame, orig, text, r, g, b, id, ...)
    frame.smartchatOrig = orig
    local info = View.Classify(text, id)
    info.text, info.r, info.g, info.b, info.id = text, r, g, b, id
    info.extra = { n = select("#", ...), ... }
    buffer[#buffer + 1] = info
    if #buffer > BUFFER_MAX + 100 then
        for _ = 1, 100 do table.remove(buffer, 1) end
    end
    return Visible(SC.GetDisplay(SC.active), info)
end

-- rebuild the chat window for the active tab
function View.Refresh(force)
    local frame = DEFAULT_CHAT_FRAME
    local orig = frame and frame.smartchatOrig
    if not orig then return end
    local cfg = SC.GetDisplay(SC.active)
    local key = CfgKey(cfg)
    if not force and key == View.key then return end
    if SC.Lockdown() then return end   -- text is hidden from addons right now; try again later
    View.key = key
    frame:Clear()
    for _, info in ipairs(buffer) do
        if Visible(cfg, info) then
            orig(frame, info.text, info.r, info.g, info.b, info.id, unpack(info.extra, 1, info.extra.n))
        end
    end
end

-- text of a remembered line, by the game's chat line id
function View.TextByLine(lineID)
    for i = #buffer, 1, -1 do
        if buffer[i].lineID == lineID then return buffer[i].text end
    end
    return nil
end
