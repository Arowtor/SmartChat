local ADDON, SC = ...

local bar, dock, channelBtn, settingsBtn, shortcutBtn, socialBtn, copyBtn, newBtn, listFrame, channelFrame, overlay, catcher, copyFrame
local whisperContactPane, whisperContactScroll, whisperContactChild, whisperContactEmpty, whisperContactHeader
local whisperContactButtons = {}
local RefreshInbox, RefreshWhisperContacts
local tabs = {}       -- id -> button
local runtime = {}    -- ordered ids currently shown
SC._tabs = tabs
SC._runtimeTabs = runtime
SC.whisperList = {}   -- names, most recent first
SC.whisperMessages = {} -- session-only conversation preview, keyed by normalized character name
SC.whisperUnread = {} -- unread counts per contact while another conversation is selected
SC.selectedWhisper = nil
SC.active = nil
SC.applied = nil

-- Guild Manager reads only the client-provided roster and caches the result
-- until GUILD_ROSTER_UPDATE. No polling or additional network requests.
local guildManagerCache
local function GetGuildManagerData(forceRefresh)
    if guildManagerCache and not forceRefresh then return guildManagerCache end
    local data = {
        available = false, guildName = nil, members = {}, byKey = {},
        total = 0, statusCounts = { ONLINE = 0, OFFLINE = 0, AFK = 0, DND = 0, UNKNOWN = 0 },
        classCounts = {}, rankCounts = {}, levelValues = {}, achievementValues = {},
        lastOnlineBuckets = { recent7 = 0, recent30 = 0, recent90 = 0, older = 0, unknown = 0 },
    }
    if not (IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then
        guildManagerCache = data
        return data
    end
    local okGuild, guildName = false, nil
    if type(GetGuildInfo) == "function" then okGuild, guildName = pcall(GetGuildInfo, "player") end
    if okGuild and type(guildName) == "string" and guildName ~= "" then data.guildName = guildName end
    local okCount, count = pcall(GetNumGuildMembers)
    if not okCount or type(count) ~= "number" or count < 0 then
        guildManagerCache = data
        return data
    end
    data.available = true
    data.total = count
    local levelSum, levelCount = 0, 0
    local achievementSum, achievementCount = 0, 0
    local maxLevel = 0
    for index = 1, math.min(count, 1000) do
        local ok, name, rankName, rankIndex, level, classDisplayName, zone, publicNote, officerNote,
            isOnline, statusCode, classFile, achievementPoints, achievementRank, isMobile, canSoR,
            repStanding, guid = pcall(GetGuildRosterInfo, index)
        if ok and type(name) == "string" and name ~= "" then
            local status = "UNKNOWN"
            if type(isOnline) == "boolean" then
                if not isOnline then status = "OFFLINE"
                elseif tonumber(statusCode) == 1 then status = "AFK"
                elseif tonumber(statusCode) == 2 then status = "DND"
                else status = "ONLINE" end
            end
            local numericLevel = tonumber(level)
            local numericRank = tonumber(rankIndex)
            local numericAchievement = tonumber(achievementPoints)
            local row = {
                name = name, rankName = rankName, rankIndex = numericRank,
                level = numericLevel, className = classDisplayName,
                classFile = classFile, classKey = tostring(classFile or classDisplayName or "UNKNOWN"):upper(),
                zone = zone, status = status,
                achievementPoints = numericAchievement, achievementRank = tonumber(achievementRank),
                isMobile = isMobile and true or false, publicNote = publicNote,
                lastOnlineHours = nil, index = index,
            }
            if numericLevel and numericLevel > 0 then
                data.levelValues[#data.levelValues + 1] = numericLevel
                levelSum, levelCount = levelSum + numericLevel, levelCount + 1
                if numericLevel > maxLevel then maxLevel = numericLevel end
            end
            if numericAchievement and numericAchievement >= 0 then
                data.achievementValues[#data.achievementValues + 1] = numericAchievement
                achievementSum, achievementCount = achievementSum + numericAchievement, achievementCount + 1
            end
            data.statusCounts[status] = (data.statusCounts[status] or 0) + 1
            local classLabel = (type(classDisplayName) == "string" and classDisplayName ~= "") and classDisplayName or (classFile or "Unknown")
            data.classCounts[classLabel] = (data.classCounts[classLabel] or 0) + 1
            local rankLabel = (type(rankName) == "string" and rankName ~= "") and rankName or "Unknown Rank"
            local rankKey = numericRank ~= nil and tostring(numericRank) or rankLabel
            local rankEntry = data.rankCounts[rankKey]
            if not rankEntry then
                rankEntry = { key = rankKey, name = rankLabel, rankIndex = numericRank, count = 0 }
                data.rankCounts[rankKey] = rankEntry
            end
            rankEntry.count = rankEntry.count + 1
            if status == "OFFLINE" and type(GetGuildRosterLastOnline) == "function" then
                local okLast, years, months, days, hours = pcall(GetGuildRosterLastOnline, index)
                if okLast and (years ~= nil or months ~= nil or days ~= nil or hours ~= nil) then
                    row.lastOnlineHours = (((tonumber(years) or 0) * 12 + (tonumber(months) or 0)) * 30.5 + (tonumber(days) or 0)) * 24 + (tonumber(hours) or 0)
                    local h = row.lastOnlineHours
                    if h <= 24 * 7 then data.lastOnlineBuckets.recent7 = data.lastOnlineBuckets.recent7 + 1
                    elseif h <= 24 * 30 then data.lastOnlineBuckets.recent30 = data.lastOnlineBuckets.recent30 + 1
                    elseif h <= 24 * 90 then data.lastOnlineBuckets.recent90 = data.lastOnlineBuckets.recent90 + 1
                    else data.lastOnlineBuckets.older = data.lastOnlineBuckets.older + 1 end
                else
                    data.lastOnlineBuckets.unknown = data.lastOnlineBuckets.unknown + 1
                end
            elseif status == "OFFLINE" then
                data.lastOnlineBuckets.unknown = data.lastOnlineBuckets.unknown + 1
            end
            local key = SC.NameKey and SC.NameKey(name) or name:lower()
            data.members[#data.members + 1] = row
            data.byKey[key] = row
        end
    end
    table.sort(data.levelValues)
    table.sort(data.achievementValues)
    local function median(values)
        local n = #values
        if n == 0 then return nil end
        if n % 2 == 1 then return values[(n + 1) / 2] end
        return (values[n / 2] + values[n / 2 + 1]) / 2
    end
    data.levelCount, data.averageLevel, data.medianLevel, data.highestLevel = levelCount, levelCount > 0 and (levelSum / levelCount) or nil, median(data.levelValues), maxLevel > 0 and maxLevel or nil
    data.achievementCount = achievementCount
    data.averageAchievement = achievementCount > 0 and (achievementSum / achievementCount) or nil
    data.medianAchievement = median(data.achievementValues)
    table.sort(data.members, function(a, b)
        local ar, br = tonumber(a.rankIndex), tonumber(b.rankIndex)
        if ar and br and ar ~= br then return ar < br end
        if ar and not br then return true end
        if br and not ar then return false end
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)
    data.classes = {}
    for label, members in pairs(data.classCounts) do data.classes[#data.classes + 1] = { name = label, count = members } end
    table.sort(data.classes, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.name < b.name end)
    data.ranks = {}
    for _, rank in pairs(data.rankCounts) do data.ranks[#data.ranks + 1] = rank end
    table.sort(data.ranks, function(a, b)
        if a.rankIndex ~= nil and b.rankIndex ~= nil and a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end
        if a.rankIndex ~= nil then return true end
        if b.rankIndex ~= nil then return false end
        return a.name < b.name
    end)
    data.topAchievements = {}
    for _, row in ipairs(data.members) do
        if row.achievementPoints ~= nil then data.topAchievements[#data.topAchievements + 1] = row end
    end
    table.sort(data.topAchievements, function(a, b)
        if a.achievementPoints ~= b.achievementPoints then return a.achievementPoints > b.achievementPoints end
        return a.name:lower() < b.name:lower()
    end)
    -- Classic/Forever normally caps at 60. If the client exposes a cap constant,
    -- prefer it; otherwise use the highest observed level for safe bucket bounds.
    data.levelCapKnown = tonumber(_G.MAX_PLAYER_LEVEL) ~= nil
    data.levelCap = tonumber(_G.MAX_PLAYER_LEVEL) or (maxLevel > 0 and math.ceil(maxLevel / 10) * 10 or nil)
    data.maxLevelCount = 0
    if data.levelCapKnown and data.levelCap then
        for _, row in ipairs(data.members) do if row.level and row.level >= data.levelCap then data.maxLevelCount = data.maxLevelCount + 1 end end
    end
    data.levelBuckets = {}
    local bucketMax = data.levelCap or maxLevel
    if bucketMax and bucketMax > 0 then
        for first = 1, bucketMax, 10 do
            local last = math.min(first + 9, bucketMax)
            local bucket = { min = first, max = last, count = 0 }
            for _, row in ipairs(data.members) do
                if row.level and row.level >= first and row.level <= last then bucket.count = bucket.count + 1 end
            end
            data.levelBuckets[#data.levelBuckets + 1] = bucket
        end
    end
    if C_GuildInfo and type(C_GuildInfo.GetMOTD) == "function" then
        local ok, value = pcall(C_GuildInfo.GetMOTD)
        if ok and type(value) == "string" then data.motd = value end
    elseif type(GetGuildMOTD) == "function" then
        local ok, value = pcall(GetGuildMOTD)
        if ok and type(value) == "string" then data.motd = value end
    end
    if C_GuildInfo and type(C_GuildInfo.GetInfoText) == "function" then
        local ok, value = pcall(C_GuildInfo.GetInfoText)
        if ok and type(value) == "string" then data.infoText = value end
    end
    guildManagerCache = data
    return data
end

local function GuildRowMatchesFilter(row, filter)
    if not filter then return true end
    if not row then return false end
    if filter.kind == "status" then return row.status == filter.value end
    if filter.kind == "class" then return row.classKey == filter.value end
    if filter.kind == "level" then return row.level and row.level >= filter.min and row.level <= filter.max or false end
    if filter.kind == "rank" then return tostring(row.rankIndex ~= nil and row.rankIndex or row.rankName) == tostring(filter.value) end
    if filter.kind == "achievement" then
        if row.achievementPoints == nil then return false end
        if filter.min and row.achievementPoints < filter.min then return false end
        if filter.max and row.achievementPoints > filter.max then return false end
        return true
    end
    if filter.kind == "lastOnline" then
        if row.lastOnlineHours == nil then return filter.value == "unknown" and row.status == "OFFLINE" end
        if filter.value == "7" then return row.lastOnlineHours <= 24 * 7 end
        if filter.value == "30" then return row.lastOnlineHours > 24 * 7 and row.lastOnlineHours <= 24 * 30 end
        if filter.value == "90" then return row.lastOnlineHours > 24 * 30 and row.lastOnlineHours <= 24 * 90 end
        if filter.value == "older" then return row.lastOnlineHours > 24 * 90 end
    end
    return true
end

local guildEvents = CreateFrame("Frame")
for _, eventName in ipairs({ "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" }) do pcall(guildEvents.RegisterEvent, guildEvents, eventName) end
guildEvents:SetScript("OnEvent", function(_, event)
    guildManagerCache = nil
    if event == "PLAYER_GUILD_UPDATE" and listFrame then
        listFrame.guildRequested = nil
        if IsInGuild and IsInGuild() then
            local requester = C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster
            if type(requester) == "function" and C_Timer and C_Timer.After then C_Timer.After(0.25, function() pcall(requester) end) end
        end
    end
    if listFrame and listFrame:IsShown() and listFrame.category == "guild" and RefreshInbox then
        if C_Timer and C_Timer.After then
            C_Timer.After(0.15, function() if listFrame and listFrame:IsShown() and listFrame.category == "guild" and RefreshInbox then RefreshInbox() end end)
        else
            RefreshInbox()
        end
    end
end)

local function PlayFor(tabId)
    local key = SC.SoundTabKey and SC.SoundTabKey(tabId) or tabId
    SC.PlayKit(SC.db.soundKit[key], SC.GetSoundVolume and SC.GetSoundVolume(key) or 1)
end

---------------------------------------------------------------------
-- Popup helpers: click outside closes, leaving with the mouse closes
---------------------------------------------------------------------
local function EnsureCatcher()
    if catcher then return catcher end
    catcher = CreateFrame("Frame", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN")
    catcher:EnableMouse(true)
    catcher:Hide()
    catcher:SetScript("OnMouseDown", function(self)
        if self.popup then self.popup:Hide() end
    end)
    return catcher
end

local function PopupShown(frame)
    local c = EnsureCatcher()
    if c.popup and c.popup ~= frame and c.popup:IsShown() then c.popup:Hide() end
    c.popup = frame
    c:Show()
    frame.outTime = 0
end
SC.PopupShown = PopupShown
function SC.HideCatcher() if catcher then catcher:Hide() end end

local function WatchMouse(frame, delay, extra)
    frame:SetScript("OnUpdate", function(self, elapsed)
        local over = false
        if self.IsMouseOver then over = self:IsMouseOver()
        elseif MouseIsOver then over = MouseIsOver(self) end
        if not over and extra and extra.IsMouseOver then over = extra:IsMouseOver() end
        if over then
            self.outTime = 0
        else
            self.outTime = (self.outTime or 0) + elapsed
            if self.outTime > delay then self:Hide() end
        end
    end)
end

---------------------------------------------------------------------
-- Edit box routing (we never call SendChatMessage ourselves; the
-- game's own edit box sends, so this works under Midnight rules)
---------------------------------------------------------------------
local function UpdateHeader(eb)
    SC.UpdateChatHeader(eb)
end

local function ResolveType(def)
    local t = def.chatType
    if t == "PARTY" or t == "RAID" then
        local P = Enum and Enum.PartyCategory
        local home = P and P.Home or LE_PARTY_CATEGORY_HOME
        local inst = P and P.Instance or LE_PARTY_CATEGORY_INSTANCE
        if IsInGroup(inst) and not IsInGroup(home) then return "INSTANCE_CHAT" end
    end
    return t
end

SC.UpdateHeader = UpdateHeader
-- party / raid chat becomes instance chat when you are in an instance group
function SC.ResolveChatType(chatType) return ResolveType({ chatType = chatType }) end

-- channel number for a CHANNEL tab: fixed number, or found by (part of) its name
local function ResolveChannel(def)
    local m = def.channelMatch
    if not m then return def.channel end
    local n = tonumber(m)
    if n then return n end
    local getter = GetChannelList or (C_ChatInfo and C_ChatInfo.GetChannelList)
    if not getter then return nil end
    local ok, list = pcall(function() return { getter() } end)
    if not ok or type(list) ~= "table" then return nil end
    local needle = m:lower()
    for i = 1, #list, 3 do
        local id, name = list[i], list[i + 1]
        if type(name) == "string" and name:lower():find(needle, 1, true) then return id end
    end
    return nil
end

-- returns true on success, or false + reason (the box is then left untouched)
local function Apply(eb)
    if not eb then return false end
    local tab = tabs[SC.active]
    if not tab then return false end
    local def = tab.def
    -- Global is a display-only aggregate. It must not change the destination
    -- selected for typing; preserve the last channel chosen from a real tab.
    if def.viewOnly then return true end
    local ctype = ResolveType(def)
    local applied = { chatType = ctype }
    if ctype == "WHISPER" then
        local target = def.target or SC.lastWhisper
        if not target then return false, "Nobody has whispered you yet." end
        SC.SetEditBoxTellTarget(eb, target)
        SC.SetEditBoxChatType(eb, "WHISPER")
        applied.target = target
    elseif ctype == "CHANNEL" then
        local idx = ResolveChannel(def)
        if not idx then
            return false, "Channel \"" .. tostring(def.channelMatch or def.channel) .. "\" not found. Join it first (e.g. /join name)."
        end
        SC.SetEditBoxChannelTarget(eb, idx)
        SC.SetEditBoxChatType(eb, "CHANNEL")
    else
        SC.SetEditBoxChatType(eb, ctype)
    end
    SC.SetEditBoxStickyType(eb, ctype)
    SC.applied = applied
    UpdateHeader(eb)

    -- Do not silently claim success if this client rejected the requested route.
    -- The selected type is also applied to the hidden edit box when a tab is clicked,
    -- so ChatFrameUtil.OpenChat sees the correct sticky destination before it opens.
    local actual = SC.GetEditBoxChatType(eb)
    if actual ~= nil and not SC.IsSecret(actual) and actual ~= ctype then
        return false, "The game kept " .. tostring(actual) .. " instead of " .. tostring(ctype) .. "."
    end
    return true
end

-- On show: apply the active tab, unless the game itself just opened the box
-- for a different explicit action (reply with R, click on a name, ...).
local function OnBoxShow(eb)
    -- Chat edit-box attributes can be restricted/secret during some encounters.
    if SC.Lockdown() then return end
    local cur = SC.GetEditBoxChatType(eb)
    if SC.IsSecret(cur) then return end
    local a = SC.applied
    if a and cur ~= a.chatType then return end
    if cur == "WHISPER" and a then
        local tt = SC.GetEditBoxTellTarget(eb)
        if SC.IsSecret(tt) then return end
        if type(tt) == "string" and tt ~= "" and SC.NameKey(tt) ~= SC.NameKey(a.target) then return end
    end
    Apply(eb)   -- if it fails we simply leave the game's own channel alone
end

-- Return the edit box the game itself will use for a new message. In the
-- modern "IM" chat style this can be a last-active/docked chat window rather
-- than DEFAULT_CHAT_FRAME.editBox. Routing only the default edit box makes
-- tab selection appear to work while the actual input still sends as SAY.
local function GetRouteEditBox()
    if ChatFrameUtil and ChatFrameUtil.ChooseBoxForSend then
        local ok, eb = pcall(ChatFrameUtil.ChooseBoxForSend)
        if ok and eb then return eb end
    end
    if ChatFrameUtil and ChatFrameUtil.GetActiveWindow then
        local ok, eb = pcall(ChatFrameUtil.GetActiveWindow)
        if ok and eb then return eb end
    end
    return DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox or nil
end
SC.GetRouteEditBox = GetRouteEditBox

local function OpenBox()
    -- Do not manipulate the game's chat edit box while chat is locked down.
    if SC.Lockdown() then return end
    local eb = GetRouteEditBox()
    if not eb then return end
    local frame = eb.chatFrame or DEFAULT_CHAT_FRAME
    if not eb:IsShown() then
        eb = SC.OpenChat("", frame) or eb
    end
    local ok, why = Apply(eb)
    if not ok then
        SC.Print(why or "this tab cannot be used right now.")
        eb:SetText("")
        eb:Hide()
        return
    end
    eb:SetFocus()
end

---------------------------------------------------------------------
-- Tab buttons
---------------------------------------------------------------------
local function RefreshLabel(t)
    local s = t.label
    if SC.db.unread and (t.unread or 0) > 0 then
        s = s .. " |cffff5555(" .. t.unread .. (t.alert and "!" or "") .. ")|r"
    end
    t.text:SetText(s)
end

local function Flash(tab)
    if not tab or tab.flashing then return end
    tab.flashing = true
    tab.hl:SetAlpha(0)
    tab.flash:Play()
end

local function StopFlash(tab)
    if not tab then return end
    tab.flashing = false
    tab.flash:Stop()
    tab.hl:SetAlpha(0)
end

local function SpeakerKey(tab)
    return tab.def.dynamic and "whisper" or tab.id
end

local function UpdateSpeaker(tab)
    if not tab or not tab.spk or not tab.spk.tex then return end
    local on = SC.db.soundNotificationsEnabled ~= false and SC.db.sound[SpeakerKey(tab)] and true or false
    -- Keep the speaker glyph visible in both states. Some Forever UI packs do
    -- not render the old VoiceChat-Muted variant consistently, so use one
    -- known speaker texture and tint it to communicate ON/OFF.
    tab.spk.tex:SetTexture("Interface\\Common\\VoiceChat-Speaker")
    if on then
        tab.spk.tex:SetVertexColor(0.55, 1.00, 0.60, 1)
    else
        tab.spk.tex:SetVertexColor(0.68, 0.68, 0.72, 1)
    end
    tab.spk:Show()
end

function SC.RefreshSpeakers()
    for _, tab in pairs(tabs) do UpdateSpeaker(tab) end
end

local CloseDynamic, StartReorder, SaveOrder
local SetWhisperContactVisibility

local function CreateTab(id, def)
    local b = CreateFrame("Button", nil, bar)
    b.id, b.def = id, def
    b.label, b.unread, b.alert = def.label, 0, false
    b:SetHeight(22)
    b:EnableMouse(true)
    b:RegisterForClicks("AnyUp")
    -- Tabs are reordered within the horizontal tab strip; they are not free-
    -- moving windows. Keep drag handling custom so the tab never leaves the row.
    b:RegisterForDrag("LeftButton")

    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.08, 0.08, 0.08, 0.85)

    b.hl = b:CreateTexture(nil, "ARTWORK")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(def.color[1], def.color[2], def.color[3], 1)
    b.hl:SetAlpha(0)

    b.sel = b:CreateTexture(nil, "OVERLAY")
    b.sel:SetPoint("BOTTOMLEFT"); b.sel:SetPoint("BOTTOMRIGHT"); b.sel:SetHeight(2)
    b.sel:SetColorTexture(def.color[1], def.color[2], def.color[3], 1)
    b.sel:Hide()

    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetTextColor(def.color[1], def.color[2], def.color[3])

    b.spk = CreateFrame("Button", nil, b)
    b.spk:SetSize(16, 16)
    b.spk:SetPoint("RIGHT", -4, 0)
    b.spk:SetFrameLevel(b:GetFrameLevel() + 2)
    b.spk.tex = b.spk:CreateTexture(nil, "OVERLAY")
    b.spk.tex:SetAllPoints()
    -- Reserve a real area for the icon so long labels/unread counts cannot
    -- paint over it. This also restores the speaker on Say and General tabs.
    b.text:SetPoint("RIGHT", b.spk, "LEFT", -4, 0)
    b.spk:SetScript("OnClick", function()
        local k = SpeakerKey(b)
        SC.db.sound[k] = not SC.db.sound[k]
        for _, t in pairs(tabs) do UpdateSpeaker(t) end
    end)
    b.spk:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if SC.db.soundNotificationsEnabled == false then
            GameTooltip:SetText("All SmartChat sounds are muted", 0.68, 0.68, 0.72)
        else
            local enabled = SC.db.sound[SpeakerKey(b)] and true or false
            GameTooltip:SetText(enabled and "Sound alerts: ON" or "Sound alerts: OFF",
                enabled and 0.55 or 0.68, enabled and 1 or 0.68, enabled and 0.60 or 0.72)
        end
        GameTooltip:AddLine("Click to toggle sound for this tab", 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)
    b.spk:SetScript("OnLeave", GameTooltip_Hide)

    b.flash = b.hl:CreateAnimationGroup()
    b.flash:SetLooping("BOUNCE")
    local a = b.flash:CreateAnimation("Alpha")
    a:SetFromAlpha(0); a:SetToAlpha(0.55); a:SetDuration(0.5)

    b:SetScript("OnDragStart", function(self)
        if self._dragging or not bar or not GetCursorPosition then return end
        local scale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        local cursorX = GetCursorPosition() / scale
        local barLeft = bar:GetLeft()
        local tabLeft = self:GetLeft()
        if not barLeft or not tabLeft then return end

        self._dragging = true
        self._dragGrabOffset = cursorX - tabLeft
        self._dragStartLeft = tabLeft
        self:SetAlpha(0.60)
        self:SetFrameLevel(bar:GetFrameLevel() + 20)
        -- The tab follows the pointer horizontally only. Its Y anchor always
        -- remains centered in the tab strip, so it cannot be dragged around
        -- the screen like a movable window.
        self:ClearAllPoints()
        self:SetPoint("LEFT", bar, "LEFT", tabLeft - barLeft, 0)
        self:SetScript("OnUpdate", function(tab)
            if not tab._dragging or not bar or not GetCursorPosition then return end
            local currentScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
            local x = GetCursorPosition() / currentScale
            local left = bar:GetLeft()
            local width = bar:GetWidth() or 0
            local tabWidth = tab:GetWidth() or 0
            if not left or width <= 0 then return end
            local minLeft = left + 4
            local maxLeft = math.max(minLeft, left + width - tabWidth - 4)
            local wantedLeft = x - (tab._dragGrabOffset or 0)
            wantedLeft = math.max(minLeft, math.min(maxLeft, wantedLeft))
            tab:ClearAllPoints()
            tab:SetPoint("LEFT", bar, "LEFT", wantedLeft - left, 0)
        end)
    end)
    b:SetScript("OnDragStop", function(self)
        if not self._dragging then return end
        self:SetScript("OnUpdate", nil)
        self._dragging = nil
        self:SetAlpha(1)
        self:SetFrameLevel(bar:GetFrameLevel() + 1)
        self._skipClickUntil = (GetTime and GetTime() or 0) + 0.35

        local moved = false
        if GetCursorPosition and bar then
            local scale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
            local cursorX, cursorY = GetCursorPosition()
            cursorX, cursorY = cursorX / scale, cursorY / scale
            local top, bottom = bar:GetTop(), bar:GetBottom()
            -- A drop is accepted only in the tab strip (with a small margin).
            -- Releasing elsewhere cancels the drag and restores the old order.
            local onRow = top and bottom and cursorY <= top + 8 and cursorY >= bottom - 8
            if onRow and SC.MoveTabToPosition then
                moved = SC.MoveTabToPosition(self.id, cursorX) and true or false
            end
        end
        self._dragGrabOffset = nil
        self._dragStartLeft = nil
        -- Layout returns the dragged button to the row's canonical anchor and
        -- applies the new order. If released outside the strip, this simply
        -- restores the previous order.
        SC.Layout()
    end)
    b:SetScript("OnClick", function(self, button)
        if self._skipClickUntil and GetTime and GetTime() <= self._skipClickUntil then
            self._skipClickUntil = nil
            return
        end
        if button == "MiddleButton" then
            StartReorder(self.id)
        elseif button == "RightButton" then
            if SC.ShowTabMenu then SC.ShowTabMenu(self) end
        else
            SC.SetActive(self.id)
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.label)
        GameTooltip:AddLine("Click: show this chat", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag: move tab", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: tab settings", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Middle-click: alternate reorder menu", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    RefreshLabel(b)
    UpdateSpeaker(b)
    tabs[id] = b
    return b
end

function SC.Layout()
    local x = 4
    for _, id in ipairs(runtime) do
        local t = tabs[id]
        local w = math.max(64, t.text:GetStringWidth() + 38)
        t:SetWidth(w)
        -- Do not snap the actively dragged tab back on incidental layout
        -- refreshes (e.g. unread counters). Its custom drag updater keeps it
        -- locked to the same horizontal row until the mouse is released.
        if not t._dragging then
            t:ClearAllPoints()
            t:SetPoint("LEFT", bar, "LEFT", x, 0)
        end
        t:Show()
        x = x + w + 3
    end
    bar:SetWidth(x + 4)
end

function SC.SetActive(id, open)
    if open == nil then open = SC.db.clickOpensEditBox and true or false end
    if not tabs[id] or SC.db.hidden[id] then id = runtime[1] end
    if not id then return end
    SC.active = id
    if id == "whisper" and SC.SelectWhisperContact then
        local selected = SC.selectedWhisper or SC.lastWhisper
        if selected then SC.SelectWhisperContact(selected, false) end
    end
    if SetWhisperContactVisibility then SetWhisperContactVisibility(id == "whisper") end
    if not tabs[id].def.dynamic then SC.db.activeTab = id end
    for tid, t in pairs(tabs) do t.sel:SetShown(tid == id) end
    local t = tabs[id]
    StopFlash(t)
    t.unread, t.alert = 0, false
    RefreshLabel(t)
    SC.Layout()
    if SC.View then SC.View.Refresh(false) end
    if open then
        OpenBox()
    elseif not t.def.viewOnly then
        -- Apply the route even while the game's edit box is hidden. Global is
        -- intentionally excluded because it is a read-only aggregate view.
        local eb = GetRouteEditBox()
        if eb and not SC.Lockdown() then
            local ok, why = Apply(eb)
            if not ok and why then SC.Print(why) end
            local def = tabs[id] and tabs[id].def
            if def then
                local ctype = ResolveType(def)
                local P = Enum and Enum.PartyCategory
                local home = P and P.Home or LE_PARTY_CATEGORY_HOME
                local inst = P and P.Instance or LE_PARTY_CATEGORY_INSTANCE
                if ctype == "PARTY" and not IsInGroup(home) then
                    SC.Print("Party chat is unavailable until you join a party. WoW may switch the input back to Say.")
                elseif ctype == "RAID" and not IsInRaid(home) then
                    SC.Print("Raid chat is unavailable until you join a raid. WoW may switch the input back to Say.")
                elseif ctype == "INSTANCE_CHAT" and not IsInGroup(home) then
                    SC.Print("Instance chat is unavailable until you join a raid/party.")
                elseif ctype == "GUILD" and not IsInGuild() then
                    SC.Print("Guild chat is unavailable because this character is not in a guild.")
                end
            end
        else
            SC.applied = nil
        end
    end
end

function CloseDynamic(id)
    local t = tabs[id]
    if not t then return end
    StopFlash(t)
    t:Hide()
    tabs[id] = nil
    SC.dynDisplay[id] = nil
    for i, v in ipairs(runtime) do if v == id then table.remove(runtime, i) break end end
    if SC.active == id then SC.SetActive("whisper", false) end
    SC.Layout()
end

-- repaint a tab after its name / color changed
local function Paint(b, c)
    b.hl:SetColorTexture(c[1], c[2], c[3], 1)
    b.sel:SetColorTexture(c[1], c[2], c[3], 1)
    b.text:SetTextColor(c[1], c[2], c[3])
end

function SC.RefreshTabLook(id)
    local t, def = tabs[id], SC.TABS[id]
    if not t or not def then return end
    Paint(t, def.color)
    if id ~= "whisper" then t.label = def.label end
    RefreshLabel(t)
    if id == "whisper" then
        for _, d in pairs(tabs) do
            if d.def.dynamic then d.def.color = def.color; Paint(d, def.color) end
        end
    end
    SC.Layout()
end

SC.CloseDynamicTab = function(id) return CloseDynamic(id) end
SC.TabFrame = function(id) return tabs[id] end
SC.VisibleTabCount = function() return #runtime end

---------------------------------------------------------------------
-- Whispers
---------------------------------------------------------------------
local function TouchWhisper(name)
    local key = SC.NameKey(name)
    for i, n in ipairs(SC.whisperList) do
        if SC.NameKey(n) == key then table.remove(SC.whisperList, i) break end
    end
    table.insert(SC.whisperList, 1, name)
    while #SC.whisperList > 20 do table.remove(SC.whisperList) end
end

local function UpdateWhisperLabel()
    local t = tabs.whisper
    if not t then return end
    -- There is exactly one built-in Whisper tab. Contact names live in its
    -- secondary tab strip instead of creating one main chat tab per player.
    t.label = "Whisper"
    RefreshLabel(t)
    SC.Layout()
end

function SC.SelectWhisperContact(name, activate)
    if type(name) == "string" and name ~= "" then
        SC.selectedWhisper = name
        SC.lastWhisper = name
        if SC.db then SC.db.selectedWhisper = name end
        SC.whisperUnread[SC.NameKey(name)] = nil
        if SC.SetDisplay then
            SC.SetDisplay("whisper", { cats = { whisper = true }, whisperWith = name })
        elseif SC.db and SC.db.display then
            SC.db.display.whisper = { cats = { whisper = true }, whisperWith = name }
        end
    elseif not SC.selectedWhisper and SC.lastWhisper then
        SC.selectedWhisper = SC.lastWhisper
    end

    if SC.View and SC.active == "whisper" then SC.View.Refresh(true) end
    if RefreshWhisperContacts then RefreshWhisperContacts() end
    if activate ~= false then SC.SetActive("whisper", false) end
    return true
end

function SC.OpenWhisperTab(name)
    -- Compatibility entry point used by the Social Hub and existing bindings.
    -- It selects a contact inside the one built-in Whisper tab; it never adds a tab.
    return SC.SelectWhisperContact(name, true)
end

function SC.CycleWhisperTarget(direction)
    local names = SC.whisperList or {}
    if #names == 0 then
        if SC.ShowWhisperList then SC.ShowWhisperList() end
        return
    end
    local current = 0
    for i, name in ipairs(names) do
        if SC.selectedWhisper and SC.NameKey(name) == SC.NameKey(SC.selectedWhisper) then current = i; break end
    end
    local step = direction and direction < 0 and -1 or 1
    local nextIndex = current == 0 and (step > 0 and 1 or #names) or ((current - 1 + step) % #names) + 1
    SC.SelectWhisperContact(names[nextIndex], true)
end

local function StatusColor(status)
    if status == "ONLINE" then return 0.20, 0.85, 0.38 end
    if status == "AFK" then return 0.92, 0.72, 0.20 end
    if status == "DND" then return 0.92, 0.48, 0.22 end
    if status == "OFFLINE" then return 0.52, 0.55, 0.60 end
    return 0.38, 0.55, 0.72
end

local function ContactLabel(name)
    local prefix = SC.ContactBadgeMarkup and SC.ContactBadgeMarkup(name, false) or ""
    if prefix == "" and SC.db and SC.db.badges then
        local rel = SC.Relation and SC.Relation(name) or ""
        prefix = rel ~= "" and ("|cff999999[" .. rel .. "]|r ") or ""
    end
    local r, g, b = SC.GetContactNameColor and SC.GetContactNameColor(name)
    local label = SC.ShortName(name)
    if r then label = string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), label) end
    return prefix .. label
end

local whisperLayout = nil
local WHISPER_PANE_GAP = 3

local function GetMainChatFrame()
    return ChatFrame1 or DEFAULT_CHAT_FRAME
end

local function CaptureWhisperLayout()
    if whisperLayout and whisperLayout.active then return true end
    local chat = GetMainChatFrame()
    if not chat or not chat.GetLeft then return false end
    local left, right = chat:GetLeft(), chat:GetRight()
    local top, bottom = chat:GetTop(), chat:GetBottom()
    local width, height = chat:GetWidth(), chat:GetHeight()
    if not (left and right and top and bottom and width and height) or width < 240 or height < 80 then
        return false
    end

    local points = {}
    local count = chat.GetNumPoints and chat:GetNumPoints() or 0
    for i = 1, count do
        local point, relativeTo, relativePoint, x, y = chat:GetPoint(i)
        points[#points + 1] = { point, relativeTo, relativePoint, x, y }
    end

    local sideWidth = math.max(88, math.min(148, width * 0.22))
    if width - sideWidth - WHISPER_PANE_GAP < 190 then
        sideWidth = math.max(76, width - 193 - WHISPER_PANE_GAP)
    end

    whisperLayout = {
        active = true,
        chat = chat,
        points = points,
        left = left,
        right = right,
        top = top,
        bottom = bottom,
        width = width,
        height = height,
        sideWidth = sideWidth,
        applying = true,
    }

    -- Reserve a real strip for the contact list and let the game's own
    -- ScrollingMessageFrame render the selected conversation in the remaining
    -- area. This keeps message wrapping and the native edit box intact.
    chat:ClearAllPoints()
    chat:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left + sideWidth + WHISPER_PANE_GAP, bottom)
    chat:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
    whisperLayout.applying = false
    return true
end

local function PositionWhisperContactPane()
    if not whisperContactPane or not whisperLayout or not whisperLayout.active then return end
    local layout = whisperLayout
    whisperContactPane:ClearAllPoints()
    whisperContactPane:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", layout.left, layout.bottom)
    whisperContactPane:SetSize(layout.sideWidth, layout.height)

    if whisperContactScroll then
        whisperContactScroll:ClearAllPoints()
        whisperContactScroll:SetPoint("TOPLEFT", whisperContactPane, "TOPLEFT", 3, -25)
        whisperContactScroll:SetPoint("BOTTOMRIGHT", whisperContactPane, "BOTTOMRIGHT", -3, 4)
    end
    if whisperContactChild then whisperContactChild:SetWidth(math.max(1, layout.sideWidth - 10)) end
end

local function RestoreWhisperLayout()
    if not whisperLayout or not whisperLayout.active then return end
    local layout, chat = whisperLayout, whisperLayout.chat
    if chat then
        chat:ClearAllPoints()
        if layout.userAdjusted then
            -- A resize/move performed while Whisper was open is retained after
            -- leaving Whisper rather than snapping back to the old dimensions.
            chat:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", layout.left, layout.bottom)
            chat:SetSize(layout.width, layout.height)
        elseif #layout.points > 0 then
            for _, p in ipairs(layout.points) do
                if p[2] then
                    chat:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0)
                else
                    chat:SetPoint(p[1], p[3], p[4] or 0, p[5] or 0)
                end
            end
        else
            chat:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", layout.left, layout.bottom)
            chat:SetSize(layout.width, layout.height)
        end
    end
    whisperLayout = nil
    if whisperContactPane then whisperContactPane:Hide() end
    if SC.PositionBar then SC.PositionBar() end
    if SC.PositionDock then SC.PositionDock() end
end

local function CreateWhisperContactButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(31)
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.bg:SetColorTexture(0.08, 0.08, 0.08, 0.85)

    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints()
    button.highlight:SetColorTexture(1, 1, 1, 0.10)

    button.selected = button:CreateTexture(nil, "OVERLAY")
    button.selected:SetPoint("BOTTOMLEFT", 0, 0)
    button.selected:SetPoint("BOTTOMRIGHT", 0, 0)
    button.selected:SetHeight(2)
    local whisperColor = (SC.TABS.whisper and SC.TABS.whisper.color) or { 1, 0.5, 1 }
    button.selected:SetColorTexture(whisperColor[1], whisperColor[2], whisperColor[3], 1)
    button.selected:Hide()

    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetPoint("TOPLEFT", 6, -3)
    button.text:SetPoint("TOPRIGHT", -15, -3)
    button.text:SetJustifyH("LEFT")
    button.text:SetWordWrap(false)

    button.meta = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    button.meta:SetPoint("TOPLEFT", 6, -17)
    button.meta:SetPoint("TOPRIGHT", -15, -17)
    button.meta:SetJustifyH("LEFT")
    button.meta:SetWordWrap(false)

    button.statusDot = button:CreateTexture(nil, "OVERLAY")
    button.statusDot:SetSize(5, 5)
    button.statusDot:SetPoint("RIGHT", -6, -7)

    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" and SC.ShowContactMenu then
            SC.ShowContactMenu(self.contactName, self)
        else
            SC.SelectWhisperContact(self.contactName, true)
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.contactName or "Whisper")
        local info = self.contactName and SC.GetContactInfo and SC.GetContactInfo(self.contactName) or {}
        if info.status then GameTooltip:AddLine(info.status, 0.65, 0.8, 1) end
        local class = SC.ContactClassName and SC.ContactClassName(info) or info.class or "Unknown"
        local level = info.level and ("Level " .. info.level) or "Level unknown"
        GameTooltip:AddLine(class .. "  Â·  " .. level, 0.8, 0.8, 0.8)
        if info.zone and info.zone ~= "" then GameTooltip:AddLine(info.zone, 0.65, 0.65, 0.65) end
        local unread = self.contactName and (SC.whisperUnread[SC.NameKey(self.contactName)] or 0) or 0
        if unread > 0 then GameTooltip:AddLine(unread .. " unread message(s)", 1, 0.82, 0.2) end
        GameTooltip:AddLine("Click to show this conversation", 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

local function CreateWhisperContactPane()
    if whisperContactPane then return end
    whisperContactPane = CreateFrame("Frame", "SmartChatWhisperContacts", UIParent)
    whisperContactPane:SetFrameStrata("MEDIUM")
    whisperContactPane:SetFrameLevel((GetMainChatFrame() and GetMainChatFrame():GetFrameLevel() or 1) + 3)

    whisperContactPane.bg = whisperContactPane:CreateTexture(nil, "BACKGROUND")
    whisperContactPane.bg:SetAllPoints()
    whisperContactPane.bg:SetColorTexture(0.025, 0.028, 0.035, 0.92)

    whisperContactPane.divider = whisperContactPane:CreateTexture(nil, "BORDER")
    whisperContactPane.divider:SetPoint("TOPRIGHT", 0, 0)
    whisperContactPane.divider:SetPoint("BOTTOMRIGHT", 0, 0)
    whisperContactPane.divider:SetWidth(1)
    whisperContactPane.divider:SetColorTexture(0.30, 0.32, 0.36, 0.75)

    whisperContactHeader = whisperContactPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    whisperContactHeader:SetPoint("TOPLEFT", 6, -7)
    whisperContactHeader:SetPoint("TOPRIGHT", -5, -7)
    whisperContactHeader:SetJustifyH("LEFT")
    whisperContactHeader:SetText("WHISPERS")

    whisperContactScroll = CreateFrame("ScrollFrame", nil, whisperContactPane)
    whisperContactScroll:EnableMouseWheel(true)
    whisperContactChild = CreateFrame("Frame", nil, whisperContactScroll)
    whisperContactChild:SetHeight(1)
    whisperContactScroll:SetScrollChild(whisperContactChild)
    whisperContactScroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, (whisperContactChild:GetHeight() or 0) - (self:GetHeight() or 0))
        local current = self:GetVerticalScroll() or 0
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * 48)))
    end)

    whisperContactEmpty = whisperContactPane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    whisperContactEmpty:SetPoint("TOPLEFT", 6, -36)
    whisperContactEmpty:SetPoint("TOPRIGHT", -6, -36)
    whisperContactEmpty:SetJustifyH("LEFT")
    whisperContactEmpty:SetWordWrap(true)
    whisperContactEmpty:SetText("No conversations yet")
    whisperContactPane:Hide()
end

RefreshWhisperContacts = function()
    if not whisperContactPane then return end
    local names = SC.whisperList or {}
    local rowHeight, gap = 31, 1
    local width = math.max(1, (whisperLayout and whisperLayout.sideWidth or 100) - 10)

    for i, name in ipairs(names) do
        local button = whisperContactButtons[i]
        if not button then
            button = CreateWhisperContactButton(whisperContactChild)
            whisperContactButtons[i] = button
        end
        local unread = SC.whisperUnread[SC.NameKey(name)] or 0
        local label = ContactLabel(name) .. (unread > 0 and (" |cffffcc55(" .. unread .. ")|r") or "")
        local info = SC.GetContactInfo and SC.GetContactInfo(name) or { status = "UNKNOWN" }
        local className = SC.ContactClassName and SC.ContactClassName(info) or info.class or "Unknown"
        local levelText = info.level and ("Lv. " .. info.level) or "Lv. ?"
        button.contactName = name
        button.text:SetText(label)
        button.meta:SetText(className .. "  Â·  " .. levelText)
        button:SetHeight(rowHeight)
        button:SetWidth(width)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", whisperContactChild, "TOPLEFT", 0, -((i - 1) * (rowHeight + gap)))
        button:SetPoint("TOPRIGHT", whisperContactChild, "TOPRIGHT", 0, -((i - 1) * (rowHeight + gap)))

        local selected = SC.selectedWhisper and SC.NameKey(SC.selectedWhisper) == SC.NameKey(name)
        button.selected:SetShown(selected and true or false)
        local r, g, b = SC.GetContactNameColor and SC.GetContactNameColor(name)
        if r then button.text:SetTextColor(r, g, b) else button.text:SetTextColor(0.86, 0.86, 0.90) end
        local sr, sg, sb = StatusColor(info.status)
        button.statusDot:SetColorTexture(sr, sg, sb, 1)
        button:Show()
    end
    for i = #names + 1, #whisperContactButtons do whisperContactButtons[i]:Hide() end

    whisperContactChild:SetWidth(width)
    whisperContactChild:SetHeight(math.max(1, #names * (rowHeight + gap)))
    if whisperContactScroll then whisperContactScroll:SetVerticalScroll(0) end
    if whisperContactEmpty then whisperContactEmpty:SetShown(#names == 0) end
    PositionWhisperContactPane()
end

SetWhisperContactVisibility = function(show)
    if show then
        CreateWhisperContactPane()
        if not CaptureWhisperLayout() then return end
        PositionWhisperContactPane()
        RefreshWhisperContacts()
        whisperContactPane:Show()
        if SC.PositionBar then SC.PositionBar() end
        if SC.PositionDock then SC.PositionDock() end
    else
        RestoreWhisperLayout()
    end
end

local SOCIAL_CATEGORIES = {
    { key = "overview", label = "Overview" },
    { key = "insights", label = "Insights" },
    { key = "all", label = "Contacts" },
    { key = "friends", label = "Friends" },
    { key = "guild", label = "Guild" },
    { key = "group", label = "Group" },
    { key = "whispers", label = "Whispers" },
    { key = "bnet", label = "BNet" },
    { key = "favorites", label = "Favorites" },
    { key = "notes", label = "Notes" },
    { key = "recent", label = "Recent" },
    { key = "groups", label = "Groups" },
    { key = "journal", label = "Journal" },
    { key = "activity", label = "Activity" },
    { key = "ignored", label = "Ignored" },
    { key = "networkMap", label = "Network" },
}

local GUILD_MANAGER_SECTIONS = {
    { key = "overview", label = "Overview", width = 72 },
    { key = "roster", label = "Roster", width = 64 },
    { key = "levelClass", label = "Level & Class", width = 92 },
    { key = "rankAchievements", label = "Rank & Achievements", width = 128 },
    { key = "activity", label = "Activity", width = 70 },
    { key = "analytics", label = "Analytics", width = 76 },
}

local PROFILE_SECTIONS
local SOCIAL_CATEGORY_WIDTHS = { overview = 58, insights = 56, all = 52, friends = 52, guild = 44, group = 44, whispers = 58, bnet = 42, favorites = 56, notes = 42, recent = 48, groups = 48, journal = 50, activity = 50, ignored = 48, networkMap = 74 }
local function EnsureHubPreferences()
    local social = SC.db.social
    social.hub = social.hub or {}
    local hub = social.hub
    hub.categoryVisibility = hub.categoryVisibility or {}
    hub.categoryOrder = hub.categoryOrder or {}
    hub.profileVisibility = hub.profileVisibility or {}
    hub.profileOrder = hub.profileOrder or {}
    local defaultCategoryOrder, defaultProfileOrder = {}, {}
    for _, item in ipairs(SOCIAL_CATEGORIES) do
        defaultCategoryOrder[#defaultCategoryOrder + 1] = item.key
        if hub.categoryVisibility[item.key] == nil then hub.categoryVisibility[item.key] = true end
    end
    for _, item in ipairs(PROFILE_SECTIONS or {}) do
        defaultProfileOrder[#defaultProfileOrder + 1] = item.key
        if hub.profileVisibility[item.key] == nil then hub.profileVisibility[item.key] = true end
    end
    if #hub.categoryOrder == 0 then hub.categoryOrder = defaultCategoryOrder end
    if #hub.profileOrder == 0 then hub.profileOrder = defaultProfileOrder end
    if hub.categoryVisibility.overview == false then hub.categoryVisibility.overview = true end
    if hub.profileVisibility.overview == false then hub.profileVisibility.overview = true end
    if hub.rowStyle ~= "compact" and hub.rowStyle ~= "comfortable" then hub.rowStyle = "comfortable" end
    if hub.showStatusDot == nil then hub.showStatusDot = true end
    if hub.showRelationshipBadges == nil then hub.showRelationshipBadges = true end
    if hub.showClassLevel == nil then hub.showClassLevel = true end
    if hub.showContactGroups == nil then hub.showContactGroups = true end
    if hub.showFavoritePinMarkers == nil then hub.showFavoritePinMarkers = true end
    if type(hub.networkMapEnabled) ~= "boolean" then hub.networkMapEnabled = false end
    if hub.networkMapLayout ~= "node" and hub.networkMapLayout ~= "radial" and hub.networkMapLayout ~= "mind" then hub.networkMapLayout = "node" end
    if type(hub.networkMapAnimations) ~= "boolean" then hub.networkMapAnimations = true end
    if type(hub.networkMapReduceMotion) ~= "boolean" then hub.networkMapReduceMotion = false end
    if hub.networkMapMaxNodes ~= 12 and hub.networkMapMaxNodes ~= 24 and hub.networkMapMaxNodes ~= 36 and hub.networkMapMaxNodes ~= 48 then hub.networkMapMaxNodes = 24 end
    local validNetworkFilters = { all = true, friends = true, guild = true, group = true, bnet = true, whispers = true, favorites = true, personal = true, recorded = true }
    if type(hub.networkMapFilter) ~= "string" or not validNetworkFilters[hub.networkMapFilter] then hub.networkMapFilter = "all" end
    if hub.networkMapZoom ~= 80 and hub.networkMapZoom ~= 100 and hub.networkMapZoom ~= 120 then hub.networkMapZoom = 100 end
    if hub.networkMapTheme ~= "midnight" and hub.networkMapTheme ~= "neon" and hub.networkMapTheme ~= "minimal" then hub.networkMapTheme = "midnight" end
    return hub
end

local function OrderedItems(source, orderKey)
    local prefs = EnsureHubPreferences()
    local sourceByKey, ordered, seen = {}, {}, {}
    for _, item in ipairs(source) do sourceByKey[item.key] = item end
    local order = prefs[orderKey] or {}
    for _, key in ipairs(order) do
        local item = sourceByKey[key]
        if item and not seen[key] then
            ordered[#ordered + 1] = item
            seen[key] = true
        end
    end
    for _, item in ipairs(source) do
        if not seen[item.key] then ordered[#ordered + 1] = item end
    end
    prefs[orderKey] = {}
    for _, item in ipairs(ordered) do prefs[orderKey][#prefs[orderKey] + 1] = item.key end
    return ordered
end

local function OrderedSocialCategories()
    return OrderedItems(SOCIAL_CATEGORIES, "categoryOrder")
end

local function OrderedProfileSections()
    return OrderedItems(PROFILE_SECTIONS, "profileOrder")
end

local function MoveOrderedKey(order, key, direction)
    local index
    for i, value in ipairs(order) do if value == key then index = i break end end
    if not index then return false end
    local target = index + direction
    if target < 1 or target > #order then return false end
    order[index], order[target] = order[target], order[index]
    return true
end

local function ApplySocialCategoryLayout()
    if not listFrame or not listFrame.categoryButtons then return end
    local hub = EnsureHubPreferences()
    local x, row, visibleCount = 10, 0, 0
    local maxX = math.max(180, (listFrame:GetWidth() or 840) - 10)
    for _, item in ipairs(OrderedSocialCategories()) do
        local button = listFrame.categoryButtons[item.key]
        if button then
            local visible = hub.categoryVisibility[item.key] ~= false or item.key == "overview"
            button:SetShown(visible)
            if visible then
                local width = SOCIAL_CATEGORY_WIDTHS[item.key] or 52
                if x > 10 and (x + width) > maxX then
                    row = row + 1
                    x = 10
                end
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", listFrame, "TOPLEFT", x, -29 - (row * 25))
                x = x + width + 3
                visibleCount = visibleCount + 1
            end
        end
    end
    listFrame.categoryRows = row + 1
    local extraY = math.max(0, row) * 25
    if listFrame.searchBox then
        listFrame.searchBox:ClearAllPoints()
        listFrame.searchBox:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 14, -57 - extraY)
    end
    if listFrame.left then
        listFrame.left:ClearAllPoints()
        listFrame.left:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 10, -84 - extraY)
        listFrame.left:SetPoint("BOTTOMLEFT", listFrame, "BOTTOMLEFT", 10, 10)
    end
    if listFrame.right and listFrame.left and listFrame.category ~= "networkMap" then
        listFrame.right:ClearAllPoints()
        listFrame.right:SetPoint("TOPLEFT", listFrame.left, "TOPRIGHT", 10, 0)
        listFrame.right:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -10, 10)
    end
    if listFrame.category and hub.categoryVisibility[listFrame.category] == false then
        listFrame.category = "overview"
        listFrame.mode = "overview"
        listFrame.profileSection = "overview"
    end
end

local function ApplyProfileSectionLayout()
    if not listFrame or not listFrame.profileSectionButtons then return end
    local hub = EnsureHubPreferences()
    local x = 4
    for _, item in ipairs(OrderedProfileSections()) do
        local button = listFrame.profileSectionButtons[item.key]
        if button then
            local visible = hub.profileVisibility[item.key] ~= false or item.key == "overview"
            button:SetShown(visible and listFrame.selectedName ~= nil)
            if visible then
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", listFrame.right, "TOPLEFT", x, -64)
                x = x + item.width + 4
            end
        end
    end
    if listFrame.profileSection and hub.profileVisibility[listFrame.profileSection] == false then
        listFrame.profileSection = "overview"
        listFrame.mode = "profile"
    end
end

local CONTACT_FILTERS = {
    { key = "all", label = "All" },
    { key = "available", label = "Available" },
    { key = "online", label = "Online" },
    { key = "offline", label = "Offline" },
    { key = "afk", label = "AFK" },
    { key = "dnd", label = "DND" },
    { key = "unknown", label = "Unknown" },
    { key = "favorites", label = "Favorites" },
    { key = "pinned", label = "Pinned" },
    { key = "unread", label = "Unread" },
    { key = "notes", label = "Has Notes" },
}
local CONTACT_FILTER_BY_KEY = {}
for _, item in ipairs(CONTACT_FILTERS) do CONTACT_FILTER_BY_KEY[item.key] = item end

local function GetContactFilterMode(social)
    social = social or (SC.db and SC.db.social) or {}
    local mode = social.contactFilterMode
    if not CONTACT_FILTER_BY_KEY[mode] then
        -- Migrate the old Online only checkbox without changing its meaning.
        mode = social.onlineOnly and "available" or "all"
        social.contactFilterMode = mode
    end
    return mode
end

local function HasSavedContactNote(name)
    local note = SC.GetContactNote and SC.GetContactNote(name)
    return type(note) == "table" and ((type(note.text) == "string" and note.text ~= "") or (type(note.tags) == "table" and #note.tags > 0)) or false
end

local function ContactMatchesFilter(name, info, mode)
    local key = SC.NameKey(name)
    local status = type(info) == "table" and info.status or "UNKNOWN"
    local unread = tonumber(SC.whisperUnread and SC.whisperUnread[key]) or 0
    if mode == "all" or not mode then return true end
    if mode == "available" then return status == "ONLINE" or status == "AFK" or status == "DND" end
    if mode == "online" then return status == "ONLINE" end
    if mode == "offline" then return status == "OFFLINE" end
    if mode == "afk" then return status == "AFK" end
    if mode == "dnd" then return status == "DND" end
    if mode == "unknown" then return status == "UNKNOWN" or status == nil end
    if mode == "favorites" then return SC.IsFavorite and SC.IsFavorite(name) or false end
    if mode == "pinned" then return SC.IsContactPinned and SC.IsContactPinned(name) or false end
    if mode == "unread" then return unread > 0 end
    if mode == "notes" then return HasSavedContactNote(name) end
    return true
end

local function CollectSocialContacts(category, bypassFilters)
    local names, seen, infos = {}, {}, {}
    local function add(name)
        if type(name) ~= "string" or name == "" then return end
        local key = SC.NameKey(name)
        local playerName = SC.PlayerDisplayName and SC.PlayerDisplayName("player")
        if key == "" or (playerName and key == SC.NameKey(playerName)) or seen[key] then return end
        seen[key] = true
        names[#names + 1] = name
    end

    local function addFriends()
        local api = C_FriendList
        if not (api and api.GetFriendInfoByIndex and api.GetNumFriends) then return end
        local okCount, count = pcall(api.GetNumFriends)
        if not okCount or type(count) ~= "number" then return end
        for i = 1, count do
            local ok, info = pcall(api.GetFriendInfoByIndex, i)
            if ok and type(info) == "table" then add(info.name) end
        end
    end

    local function addGuild()
        local guildData = GetGuildManagerData()
        for _, member in ipairs(guildData.members or {}) do add(member.name) end
    end

    local function addGroup()
        local total = (GetNumGroupMembers and GetNumGroupMembers()) or (GetNumRaidMembers and GetNumRaidMembers()) or 0
        if IsInRaid and IsInRaid() then
            for i = 1, math.min(total, 40) do
                local unit = "raid" .. i
                local name = SC.PlayerDisplayName and SC.PlayerDisplayName(unit) or (UnitName and UnitName(unit))
                if name and name ~= "" then add(name) end
            end
        elseif IsInGroup and IsInGroup() then
            for i = 1, math.min(math.max(total - 1, 0), 4) do
                local unit = "party" .. i
                local name = SC.PlayerDisplayName and SC.PlayerDisplayName(unit) or (UnitName and UnitName(unit))
                if name and name ~= "" then add(name) end
            end
        end
    end

    local function addWhispers()
        for _, name in ipairs(SC.whisperList or {}) do add(name) end
    end

    local function addIgnored()
        local api = C_FriendList
        if not (api and api.GetNumIgnores and api.GetIgnoreName) then return end
        local okCount, count = pcall(api.GetNumIgnores)
        if not okCount or type(count) ~= "number" then return end
        for i = 1, count do
            local ok, name = pcall(api.GetIgnoreName, i)
            if ok then add(name) end
        end
    end

    local function addBnet()
        for _, info in pairs(SC.bnetCache or {}) do
            if type(info) == "table" then
                local name = info.name
                if not name and info.character then
                    name = info.character
                    if info.realm and info.realm ~= "" then name = name .. "-" .. info.realm:gsub("%s", "") end
                end
                add(name)
            end
        end
    end

    local function addFavorites()
        local favorites = SC.db.social and SC.db.social.favorites or {}
        for _, name in pairs(favorites) do add(name) end
    end

    local function addRecent()
        addWhispers()
        if SC.GetJournalRecentNames then
            for _, name in ipairs(SC.GetJournalRecentNames()) do add(name) end
        end
    end

    local function addGroups()
        local groups = SC.db.social and SC.db.social.groups or {}
        local selectedGroup = listFrame and listFrame.selectedGroup
        if selectedGroup and selectedGroup ~= "All" then
            local group = groups[selectedGroup]
            if type(group) == "table" then for _, name in pairs(group) do add(name) end end
        else
            for _, group in pairs(groups) do
                if type(group) == "table" then for _, name in pairs(group) do add(name) end end
            end
        end
    end

    local function addNotes()
        local journal = SC.db.journal or {}
        for _, note in pairs(journal.notes or {}) do
            if type(note) == "table" and ((type(note.text) == "string" and note.text ~= "") or (type(note.tags) == "table" and #note.tags > 0)) then
                add(note.name)
            end
        end
    end

    local function addJournalNames()
        addNotes()
        if SC.GetJournalRecentNames then
            for _, name in ipairs(SC.GetJournalRecentNames()) do add(name) end
        end
    end

    local insightRank = {}
    local function addInsights()
        addFriends(); addGuild(); addGroup(); addBnet(); addWhispers(); addFavorites(); addJournalNames()
        local localGroups = SC.db and SC.db.social and SC.db.social.groups or {}
        for _, members in pairs(localGroups) do
            if type(members) == "table" then for _, memberName in pairs(members) do add(memberName) end end
        end
        local journal = SC.db and SC.db.journal or {}
        local stats = SC.GetSocialIntelligenceStats and SC.GetSocialIntelligenceStats(tonumber(journal.timelineDays) or 0) or { topContacts = {}, recommendations = {} }
        if listFrame then listFrame.intelligenceStats = stats end
        for i, person in ipairs(stats.topContacts or {}) do
            add(person.name)
            insightRank[SC.NameKey(person.name)] = i
        end
        for _, recommendation in ipairs(stats.recommendations or {}) do add(recommendation.name) end
    end

    if category == "friends" then
        addFriends()
    elseif category == "guild" then
        addGuild()
    elseif category == "group" then
        addGroup()
    elseif category == "whispers" then
        addWhispers()
    elseif category == "bnet" then
        addBnet()
    elseif category == "ignored" then
        addIgnored()
    elseif category == "favorites" then
        addFavorites()
    elseif category == "notes" then
        addNotes()
    elseif category == "recent" then
        addRecent()
    elseif category == "groups" then
        addGroups()
    elseif category == "journal" or category == "activity" then
        addJournalNames()
    elseif category == "insights" then
        addInsights()
    elseif category == "overview" then
        addFriends()
        addGuild()
        addGroup()
        addBnet()
        addWhispers()
        addFavorites()
        addGroups()
        addIgnored()
        addJournalNames()
    else
        addFriends()
        addGuild()
        addGroup()
        addBnet()
        addWhispers()
        addFavorites()
        addGroups()
        addIgnored()
        addJournalNames()
    end

    -- Global view filters are performed once per collected contact. The same
    -- cached API result is reused for sorting and row rendering in this pass.
    local social = SC.db.social or {}
    local filterMode = GetContactFilterMode(social)
    local search = listFrame and listFrame.searchBox and listFrame.searchBox:GetText() or ""
    search = type(search) == "string" and search:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    if search == "search contacts..." then search = "" end
    local filtered = {}
    for _, name in ipairs(names) do
        local key = SC.NameKey(name)
        local info = SC.GetContactInfo and SC.GetContactInfo(name) or { status = "UNKNOWN" }
        infos[key] = info
        local visible = bypassFilters or ContactMatchesFilter(name, info, filterMode)
        if not bypassFilters and visible and category == "guild" and listFrame and listFrame.guildDrillFilter then
            local guildRow = GetGuildManagerData().byKey[key]
            visible = GuildRowMatchesFilter(guildRow, listFrame.guildDrillFilter)
        end
        if not bypassFilters and visible and search ~= "" then
            local fields = {}
            local function addSearchField(value)
                if type(value) == "number" then value = tostring(value) end
                if type(value) == "string" and value ~= "" then fields[#fields + 1] = value end
            end
            addSearchField(SC.ShortName(name)); addSearchField(info.class); addSearchField(info.classFile)
            addSearchField(info.zone); addSearchField(info.rank); addSearchField(info.battleTag)
            addSearchField(info.bnetAccountName); addSearchField(info.realm)
            addSearchField(info.status); addSearchField(info.level); addSearchField(info.role)
            addSearchField(info.guildName); addSearchField(info.gameLabel)
            if category == "guild" then
                local guildRow = GetGuildManagerData().byKey[key]
                if guildRow then
                    addSearchField(guildRow.achievementPoints); addSearchField(guildRow.achievementRank)
                    addSearchField(guildRow.lastOnlineHours)
                end
            end
            for _, character in ipairs(info.bnetCharacters or {}) do addSearchField(character.name) end
            for _, game in ipairs(info.bnetGames or {}) do
                addSearchField(game.gameLabel); addSearchField(game.character); addSearchField(game.realm); addSearchField(game.richPresence)
            end
            if SC.IsFavorite and SC.IsFavorite(name) then addSearchField("favorite favorites") end
            if SC.IsContactPinned and SC.IsContactPinned(name) then addSearchField("pinned") end
            local unread = tonumber(SC.whisperUnread and SC.whisperUnread[key]) or 0
            if unread > 0 then addSearchField("unread") end
            for _, groupName in ipairs(SC.GetContactGroups and SC.GetContactGroups(name) or {}) do addSearchField(groupName) end
            local note = SC.GetContactNote and SC.GetContactNote(name)
            if note then
                addSearchField(note.text)
                for _, tag in ipairs(note.tags or {}) do addSearchField(tag) end
            end
            local haystack = table.concat(fields, " "):lower()
            if not haystack:find(search, 1, true) then visible = false end
        end
        if visible then filtered[#filtered + 1] = name end
    end
    names = filtered

    local mode = social.sortMode or "status"
    if category ~= "guild" and mode == "achievement" then mode = "status"; social.sortMode = "status" end
    local ranks = {}
    for _, name in ipairs(names) do
        local info = infos[SC.NameKey(name)] or {}
        if info.status == "ONLINE" then ranks[SC.NameKey(name)] = 1
        elseif info.status == "AFK" or info.status == "DND" then ranks[SC.NameKey(name)] = 2
        elseif info.status == "OFFLINE" then ranks[SC.NameKey(name)] = 3
        else ranks[SC.NameKey(name)] = 4 end
    end
    local recentRank = {}
    for i, name in ipairs(SC.whisperList or {}) do recentRank[SC.NameKey(name)] = i end
    table.sort(names, function(a, b)
        local ka, kb = SC.NameKey(a), SC.NameKey(b)
        if category == "insights" then
            local ia, ib = insightRank[ka] or 99999, insightRank[kb] or 99999
            if ia ~= ib then return ia < ib end
        end
        if category == "notes" then
            local journal = SC.db.journal or {}
            local na, nb = (journal.notes or {})[ka] or {}, (journal.notes or {})[kb] or {}
            local ta, tb = tonumber(na.updated) or 0, tonumber(nb.updated) or 0
            if ta ~= tb then return ta > tb end
            return SC.ShortName(a):lower() < SC.ShortName(b):lower()
        end
        local pinned = social.pinned or {}
        local favorites = social.favorites or {}
        local pa, pb = pinned[ka] and 1 or 0, pinned[kb] and 1 or 0
        if pa ~= pb then return pa > pb end
        local fa, fb = favorites[ka] and 1 or 0, favorites[kb] and 1 or 0
        if fa ~= fb then return fa > fb end
        if category == "bnet" and mode == "status" then
            local ia, ib = infos[ka] or {}, infos[kb] or {}
            local aa = tostring(ia.bnetAccountName or ia.battleTag or ia.name or ""):lower()
            local ab = tostring(ib.bnetAccountName or ib.battleTag or ib.name or ""):lower()
            if aa ~= ab then return aa < ab end
            return SC.ShortName(a):lower() < SC.ShortName(b):lower()
        end
        if mode == "name" then return SC.ShortName(a):lower() < SC.ShortName(b):lower() end
        if mode == "recent" then
            local ra, rb = recentRank[ka] or 9999, recentRank[kb] or 9999
            if ra ~= rb then return ra < rb end
            return SC.ShortName(a):lower() < SC.ShortName(b):lower()
        end
        if mode == "unread" then
            local ua = tonumber(SC.whisperUnread and SC.whisperUnread[ka]) or 0
            local ub = tonumber(SC.whisperUnread and SC.whisperUnread[kb]) or 0
            if ua ~= ub then return ua > ub end
            local ra, rb = ranks[ka] or 4, ranks[kb] or 4
            if ra ~= rb then return ra < rb end
            return SC.ShortName(a):lower() < SC.ShortName(b):lower()
        end
        if mode == "rank" then
            local ia, ib = infos[ka] or {}, infos[kb] or {}
            local ra, rb = tonumber(ia.rankIndex), tonumber(ib.rankIndex)
            if ra and rb and ra ~= rb then return ra < rb end
            if ra and not rb then return true end
            if rb and not ra then return false end
            return SC.ShortName(a):lower() < SC.ShortName(b):lower()
        end
        if mode == "level" then
            local ia, ib = infos[ka] or {}, infos[kb] or {}
            local la, lb = tonumber(ia.level), tonumber(ib.level)
            if la and lb and la ~= lb then return la > lb end
            if la and not lb then return true end
            if lb and not la then return false end
            return SC.ShortName(a):lower() < SC.ShortName(b):lower()
        end
        if mode == "class" then
            local ia, ib = infos[ka] or {}, infos[kb] or {}
            local ca, cb = tostring(ia.class or ""):lower(), tostring(ib.class or ""):lower()
            if ca ~= cb then return ca < cb end
            return SC.ShortName(a):lower() < SC.ShortName(b):lower()
        end
        if mode == "achievement" and category == "guild" then
            local roster = GetGuildManagerData()
            local aa = roster.byKey[ka] and tonumber(roster.byKey[ka].achievementPoints)
            local ab = roster.byKey[kb] and tonumber(roster.byKey[kb].achievementPoints)
            if aa and ab and aa ~= ab then return aa > ab end
            if aa and not ab then return true end
            if ab and not aa then return false end
            return SC.ShortName(a):lower() < SC.ShortName(b):lower()
        end
        if category == "whispers" or category == "recent" then
            local ra, rb = recentRank[ka] or 9999, recentRank[kb] or 9999
            if ra ~= rb then return ra < rb end
        end
        local ra, rb = ranks[ka] or 4, ranks[kb] or 4
        if ra ~= rb then return ra < rb end
        return SC.ShortName(a):lower() < SC.ShortName(b):lower()
    end)
    return names
end

local function CountSelectedContacts()
    local count = 0
    for _ in pairs((listFrame and listFrame.multiSelected) or {}) do count = count + 1 end
    return count
end

local function GetSelectedContactNames()
    local result = {}
    for _, name in pairs((listFrame and listFrame.multiSelected) or {}) do
        if type(name) == "string" and name ~= "" then result[#result + 1] = name end
    end
    table.sort(result, function(a, b) return SC.ShortName(a):lower() < SC.ShortName(b):lower() end)
    return result
end

local function ToggleMultiSelected(name)
    if type(name) ~= "string" or name == "" then return end
    listFrame.multiSelected = listFrame.multiSelected or {}
    local key = SC.NameKey(name)
    if listFrame.multiSelected[key] then listFrame.multiSelected[key] = nil
    else listFrame.multiSelected[key] = name end
end

local function ApplyBulkContactAction(action, groupName)
    local names = GetSelectedContactNames()
    if #names == 0 then
        SC.Print("Select at least one contact first.")
        return
    end
    local social = SC.db.social or {}
    social.favorites = social.favorites or {}
    social.pinned = social.pinned or {}
    social.groups = social.groups or {}
    local changed = 0
    if action == "favorite" or action == "unfavorite" then
        for _, name in ipairs(names) do
            local key = SC.NameKey(name)
            if action == "favorite" then social.favorites[key] = name else social.favorites[key] = nil end
            changed = changed + 1
        end
    elseif action == "pin" or action == "unpin" then
        for _, name in ipairs(names) do
            local key = SC.NameKey(name)
            if action == "pin" then social.pinned[key] = name else social.pinned[key] = nil end
            changed = changed + 1
        end
    elseif action == "addgroup" and type(groupName) == "string" and type(social.groups[groupName]) == "table" then
        local group = social.groups[groupName]
        for _, name in ipairs(names) do
            local key = SC.NameKey(name)
            if not group[key] then changed = changed + 1 end
            group[key] = name
        end
    elseif action == "removegroup" and type(groupName) == "string" and type(social.groups[groupName]) == "table" then
        local group = social.groups[groupName]
        for _, name in ipairs(names) do
            local key = SC.NameKey(name)
            if group[key] then group[key] = nil; changed = changed + 1 end
        end
    end
    if SC.RefreshWhisperInbox then SC.RefreshWhisperInbox() end
    SC.Print(string.format("Bulk action completed for %d selected contact(s).", changed))
end

local function AddBulkMenuItem(menu, label, callback, disabled)
    local info = UIDropDownMenu_CreateInfo()
    info.text, info.func, info.notCheckable, info.disabled = label, callback, true, disabled or false
    menu[#menu + 1] = info
end

local function ShowBulkContactMenu(anchor)
    if not EasyMenu or not UIDropDownMenu_CreateInfo then return end
    local selected = GetSelectedContactNames()
    local menu = {}
    local heading = UIDropDownMenu_CreateInfo()
    heading.text = string.format("Selected contacts: %d", #selected)
    heading.isTitle, heading.notCheckable = true, true
    menu[#menu + 1] = heading
    AddBulkMenuItem(menu, "Select All Visible", function()
        listFrame.multiSelected = listFrame.multiSelected or {}
        for _, name in ipairs(listFrame.visibleNames or {}) do listFrame.multiSelected[SC.NameKey(name)] = name end
        RefreshInbox()
    end, not listFrame.visibleNames or #listFrame.visibleNames == 0)
    AddBulkMenuItem(menu, "Clear Selection", function()
        wipe(listFrame.multiSelected or {})
        RefreshInbox()
    end, #selected == 0)

    local sep = UIDropDownMenu_CreateInfo(); sep.text = "Favorites and Pins"; sep.isTitle = true; sep.notCheckable = true; menu[#menu + 1] = sep
    AddBulkMenuItem(menu, "Add Selected to Favorites", function() ApplyBulkContactAction("favorite") end, #selected == 0)
    AddBulkMenuItem(menu, "Remove Selected from Favorites", function() ApplyBulkContactAction("unfavorite") end, #selected == 0)
    AddBulkMenuItem(menu, "Pin Selected", function() ApplyBulkContactAction("pin") end, #selected == 0)
    AddBulkMenuItem(menu, "Unpin Selected", function() ApplyBulkContactAction("unpin") end, #selected == 0)

    local groupTitle = UIDropDownMenu_CreateInfo(); groupTitle.text = "Personal Groups"; groupTitle.isTitle = true; groupTitle.notCheckable = true; menu[#menu + 1] = groupTitle
    local groups = SC.db.social and SC.db.social.groups or {}
    local order = SC.db.social and SC.db.social.groupOrder or {}
    for _, groupName in ipairs(order) do
        local g = groupName
        AddBulkMenuItem(menu, "Add Selected to: " .. g, function() ApplyBulkContactAction("addgroup", g) end, #selected == 0)
    end
    if listFrame.category == "groups" and listFrame.selectedGroup and listFrame.selectedGroup ~= "All" and type(groups[listFrame.selectedGroup]) == "table" then
        local currentGroup = listFrame.selectedGroup
        AddBulkMenuItem(menu, "Remove Selected from: " .. currentGroup, function() ApplyBulkContactAction("removegroup", currentGroup) end, #selected == 0)
    end
    AddBulkMenuItem(menu, "Create Group from Selectionâ¦", function()
        if SC.PromptCreateContactGroupFromSelection then SC.PromptCreateContactGroupFromSelection(GetSelectedContactNames()) end
    end, #selected == 0)
    AddBulkMenuItem(menu, "Save Selection as Group Templateâ¦", function()
        if SC.PromptSaveSelectedContactsAsTemplate then SC.PromptSaveSelectedContactsAsTemplate(GetSelectedContactNames()) end
    end, #selected == 0)
    AddBulkMenuItem(menu, "Invite Selected to Partyâ¦", function()
        if SC.PromptInviteSelectedContacts then SC.PromptInviteSelectedContacts(GetSelectedContactNames()) end
    end, #selected == 0)
    EasyMenu(menu, listFrame.bulkMenu, anchor or UIParent, 0, 0, "MENU")
end

local function CreateSocialRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(36)
    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("TOPLEFT", 20, -3)
    row.nameText:SetPoint("TOPRIGHT", -3, -3)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)
    row.metaText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.metaText:SetPoint("TOPLEFT", 20, -18)
    row.metaText:SetPoint("TOPRIGHT", -3, -18)
    row.metaText:SetJustifyH("LEFT")
    row.metaText:SetWordWrap(false)
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(7, 7)
    row.dot:SetPoint("LEFT", 7, 0)
    row.multiMark = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.multiMark:SetPoint("RIGHT", -4, 0)
    row.multiMark:SetJustifyH("RIGHT")
    row.multiMark:Hide()
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetColorTexture(0.16, 0.34, 0.52, 0.42)
    row.selected:Hide()
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.10)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" and SC.ShowContactMenu then
            SC.ShowContactMenu(self.name, self)
        elseif listFrame.selectionMode then
            ToggleMultiSelected(self.name)
            RefreshInbox()
        else
            if not listFrame.selectedName or SC.NameKey(listFrame.selectedName) ~= SC.NameKey(self.name) then
                listFrame.comparePartner = nil
            end
            listFrame.selectedName = self.name
            if listFrame.mode ~= "journal" then
                listFrame.mode = "profile"
                if listFrame.category == "journal" then
                    listFrame.profileSection = "history"
                elseif listFrame.category == "notes" then
                    listFrame.profileSection = "notes"
                else
                    listFrame.profileSection = "overview"
                end
            end
            RefreshInbox()
        end
    end)
    return row
end

local function SetHubTranscript(value)
    if not listFrame or not listFrame.transcript then return end
    listFrame.transcript:SetWidth(math.max(120, (listFrame.transcriptScroll:GetWidth() or 200) - 8))
    listFrame.transcript:SetText(value or "")
    local height = math.max(28, (listFrame.transcript:GetStringHeight() or 16) + 8)
    listFrame.transcriptChild:SetWidth(listFrame.transcript:GetWidth())
    listFrame.transcriptChild:SetHeight(math.max(height, listFrame.transcriptScroll:GetHeight() or 1))
    listFrame.transcriptScroll:SetVerticalScroll(0)
end

local JOURNAL_TYPE_FILTERS = {
    { key = "all", label = "All activity" },
    { key = "social", label = "Social" },
    { key = "group", label = "Group" },
    { key = "communication", label = "Whispers" },
    { key = "presence", label = "Presence" },
    { key = "notes", label = "Notes" },
    { key = "quests", label = "Quests" },
}
local JOURNAL_PERIOD_FILTERS = {
    { key = 0, label = "All time" },
    { key = 7, label = "7 days" },
    { key = 30, label = "30 days" },
    { key = 90, label = "90 days" },
}
PROFILE_SECTIONS = {
    { key = "overview", label = "Overview", width = 76 },
    { key = "history", label = "History", width = 68 },
    { key = "notes", label = "Notes", width = 62 },
    { key = "relationship", label = "Relationship", width = 96 },
    { key = "network", label = "Connections", width = 90 },
    { key = "shared", label = "Shared", width = 62 },
}

local function JournalEventTimeLabel(event, formatString)
    local started = tonumber(event and event.t) or time()
    local latest = tonumber(event and event.last) or started
    local firstLabel = date(formatString or "%Y-%m-%d %H:%M", started)
    if event and event.type == "whisper" and latest > started then
        local endFormat = date("%Y-%m-%d", started) == date("%Y-%m-%d", latest) and "%H:%M" or (formatString or "%Y-%m-%d %H:%M")
        return firstLabel .. " â " .. date(endFormat, latest)
    end
    return firstLabel
end

local function JournalEventTitleLabel(event, fallback)
    local title = tostring(event and (event.title or event.type) or fallback or "Activity")
    local count = tonumber(event and event.count) or 0
    if event and event.type == "whisper" and count > 1 then
        title = title .. " Â· " .. tostring(count) .. " interactions"
    end
    return title
end

local function JournalFilterLabel()
    local journal = SC.db and SC.db.journal or {}
    local typeKey, days = journal.timelineType or "all", tonumber(journal.timelineDays) or 0
    local typeLabel, periodLabel = "All activity", "All time"
    for _, item in ipairs(JOURNAL_TYPE_FILTERS) do if item.key == typeKey then typeLabel = item.label break end end
    for _, item in ipairs(JOURNAL_PERIOD_FILTERS) do if item.key == days then periodLabel = item.label break end end
    return typeLabel, periodLabel
end

local function AppendBnetAccountSummary(lines, info, selectedName)
    if type(info) ~= "table" or not info.bnetAccountName then return end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cff66ccffBATTLE.NET ACCOUNT|r  " .. tostring(info.bnetAccountName)
    local gameCount = tonumber(info.bnetGameAccountCount) or 0
    local characterCount = tonumber(info.bnetCharacterCount) or 0
    lines[#lines + 1] = string.format("Game accounts reported by the client: %d  Â·  WoW characters currently reported: %d", gameCount, characterCount)
    if info.bnetAccountStatus and info.bnetAccountStatus ~= "UNKNOWN" then
        lines[#lines + 1] = "Account presence: " .. tostring(info.bnetAccountStatus)
    elseif info.bnetAppearOffline then
        lines[#lines + 1] = "Account presence: Unknown / Appear Offline"
    end
    local games = info.bnetGames or {}
    if #games > 0 then
        lines[#lines + 1] = "|cff66ccffREPORTED GAME ACCOUNTS|r"
        for i = 1, math.min(#games, 8) do
            local game = games[i]
            local label = tostring(game.gameLabel or "Other game")
            if game.character and game.character ~= "" then
                label = label .. ": " .. tostring(game.character)
                if game.realm and game.realm ~= "" then label = label .. " Â· " .. tostring(game.realm) end
                local characterClass = game.class
                if characterClass and characterClass ~= "" then label = label .. " Â· " .. tostring(characterClass) end
                if tonumber(game.level) then label = label .. " Â· Lv. " .. tostring(game.level) end
                if game.zone and game.zone ~= "" then label = label .. " Â· " .. tostring(game.zone) end
                local reportedFullName = game.character
                if game.realm and game.realm ~= "" then reportedFullName = reportedFullName .. "-" .. game.realm:gsub("%s", "") end
                if selectedName and (SC.NameKey(reportedFullName) == SC.NameKey(selectedName) or SC.NameKey(game.character) == SC.NameKey(selectedName)) then
                    label = label .. " Â· Selected"
                end
            elseif game.richPresence and game.richPresence ~= "" then
                label = label .. " Â· " .. tostring(game.richPresence)
            end
            label = label .. " Â· " .. tostring(game.status or "UNKNOWN")
            lines[#lines + 1] = "  " .. label
        end
        if #games > 8 then lines[#lines + 1] = string.format("  + %d more reported game accounts", #games - 8) end
    else
        lines[#lines + 1] = "No game-account details were exposed by the client in this session."
    end
    lines[#lines + 1] = "|cff888888This is the currently reported game-account data, not a complete roster of every character on the Battle.net account.|r"
end

local function GuildPercent(value, total)
    if not total or total <= 0 then return "0%" end
    return string.format("%.1f%%", (value or 0) * 100 / total)
end

local function GuildSafeText(value)
    if type(value) ~= "string" or value == "" then return "Unknown" end
    return value:gsub("|", "||")
end

local function BuildGuildDrillItems(data, section)
    local items = {}
    local function add(label, filter, tip)
        items[#items + 1] = { label = label, filter = filter, tip = tip or label }
    end
    if section == "overview" or section == "roster" then
        add("All", nil, "Show all visible Guild members.")
        add("Online", { kind = "status", value = "ONLINE" }, "Show members who are currently online.")
        add("AFK", { kind = "status", value = "AFK" }, "Show members whose status is AFK.")
        add("DND", { kind = "status", value = "DND" }, "Show members whose status is Do Not Disturb.")
        add("Offline", { kind = "status", value = "OFFLINE" }, "Show members who are offline.")
        add("Unknown", { kind = "status", value = "UNKNOWN" }, "Show members whose presence is not known.")
    elseif section == "levelClass" then
        for _, bucket in ipairs(data.levelBuckets or {}) do
            add(string.format("Lv. %d-%d (%d)", bucket.min, bucket.max, bucket.count), { kind = "level", min = bucket.min, max = bucket.max }, string.format("Show Guild members from level %d to %d.", bucket.min, bucket.max))
        end
        for i = 1, math.min(12 - #items, #(data.classes or {})) do
            local class = data.classes[i]
            local matchKey
            for _, row in ipairs(data.members) do
                local label = (row.className and row.className ~= "" and row.className) or row.classFile or "Unknown"
                if label == class.name then matchKey = row.classKey break end
            end
            if matchKey then add(string.format("%s (%d)", class.name, class.count), { kind = "class", value = matchKey }, "Show " .. class.name .. " members.") end
        end
    elseif section == "rankAchievements" then
        for i = 1, math.min(6, #(data.ranks or {})) do
            local rank = data.ranks[i]
            add(string.format("%s (%d)", rank.name:sub(1, 15), rank.count), { kind = "rank", value = rank.key }, "Show members with Guild rank " .. rank.name .. ".")
        end
        add("0-999 AP", { kind = "achievement", min = 0, max = 999 }, "Show members with 0 to 999 Achievement Points.")
        add("1k-4.9k AP", { kind = "achievement", min = 1000, max = 4999 }, "Show members with 1,000 to 4,999 Achievement Points.")
        add("5k-9.9k AP", { kind = "achievement", min = 5000, max = 9999 }, "Show members with 5,000 to 9,999 Achievement Points.")
        add("10k+ AP", { kind = "achievement", min = 10000 }, "Show members with at least 10,000 Achievement Points.")
    elseif section == "activity" then
        add("Online", { kind = "status", value = "ONLINE" }, "Show members who are online.")
        add("AFK", { kind = "status", value = "AFK" }, "Show members who are AFK.")
        add("DND", { kind = "status", value = "DND" }, "Show members who are DND.")
        add("Offline", { kind = "status", value = "OFFLINE" }, "Show offline Guild members.")
        add("Last 7d", { kind = "lastOnline", value = "7" }, "Show members last online within 7 days.")
        add("8-30d", { kind = "lastOnline", value = "30" }, "Show members last online 8 to 30 days ago.")
        add("31-90d", { kind = "lastOnline", value = "90" }, "Show members last online 31 to 90 days ago.")
        add("90d+", { kind = "lastOnline", value = "older" }, "Show members last online more than 90 days ago.")
        add("Unknown age", { kind = "lastOnline", value = "unknown" }, "Show offline members with no last-online age supplied by the client.")
    elseif section == "analytics" then
        for i = 1, math.min(6, #(data.classes or {})) do
            local class = data.classes[i]
            for _, row in ipairs(data.members) do
                local label = (row.className and row.className ~= "" and row.className) or row.classFile or "Unknown"
                if label == class.name then
                    add(class.name, { kind = "class", value = row.classKey }, "Filter the roster to " .. class.name .. ".")
                    break
                end
            end
        end
        for _, bucket in ipairs(data.levelBuckets or {}) do
            if #items >= 12 then break end
            add(string.format("Lv %d-%d", bucket.min, bucket.max), { kind = "level", min = bucket.min, max = bucket.max }, string.format("Filter the roster to levels %d-%d.", bucket.min, bucket.max))
        end
    end
    return items
end

local function RefreshGuildDrillButtons(data, section)
    if not listFrame or not listFrame.guildDrillButtons then return 0 end
    local items = BuildGuildDrillItems(data, section)
    if listFrame.guildDrillFilter then
        table.insert(items, 1, { label = "Clear Filter", filter = false, tip = "Clear the Guild Manager drill-down filter." })
    end
    local visibleRows = math.ceil(math.min(#items, #listFrame.guildDrillButtons) / 6)
    for i, button in ipairs(listFrame.guildDrillButtons) do
        local item = items[i]
        if item and i <= #listFrame.guildDrillButtons then
            local col, row = (i - 1) % 6, math.floor((i - 1) / 6)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", listFrame.right, "TOPLEFT", 4 + col * 96, -91 - row * 23)
            button:SetText(item.label)
            button.filter = item.filter
            button.tip = item.tip
            button:SetScript("OnClick", function(self)
                if self.filter == false then listFrame.guildDrillFilter = nil else listFrame.guildDrillFilter = self.filter end
                listFrame.guildSection = "roster"
                listFrame.mode = "guild"
                listFrame.selectedName = nil
                RefreshInbox()
            end)
            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(self.tip or self:GetText(), 1, 1, 1, true)
                GameTooltip:AddLine("The Guild roster on the left will be filtered. Search and the global contact filter continue to apply.", 0.75, 0.85, 1, true)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", GameTooltip_Hide)
            button:Show()
        else
            button:Hide()
        end
    end
    return visibleRows
end

local function RenderGuildManagerView(names)
    if not listFrame then return end
    local data = GetGuildManagerData()
    local section = listFrame.guildSection or "overview"
    local sectionLabels = { overview = "Guild Overview", roster = "Guild Roster", levelClass = "Level & Class", rankAchievements = "Rank & Achievements", activity = "Guild Activity", analytics = "Guild Analytics" }
    listFrame.header:SetText(data.guildName or "Guild Manager")
    local c = data.statusCounts or {}
    local onlineLike = (c.ONLINE or 0) + (c.AFK or 0) + (c.DND or 0)
    listFrame.status:SetText(string.format("%d MEMBERS  Â·  %d ONLINE", #data.members, onlineLike))
    listFrame.status:SetTextColor(0.40, 0.80, 1)
    local detailText = "Guild Roster data supplied by the game client. Analytics are calculated locally when this section is opened."
    if not data.available then detailText = "You are not currently in a Guild, or the Guild Roster API is unavailable." end
    if data.available and data.guildName then detailText = detailText .. "  Â·  " .. data.guildName end
    listFrame.details:SetText(detailText)
    local filterRows = RefreshGuildDrillButtons(data, section)
    if listFrame.contentLine then
        listFrame.contentLine:ClearAllPoints()
        listFrame.contentLine:SetPoint("TOPLEFT", 4, filterRows > 1 and -145 or -119)
        listFrame.contentLine:SetPoint("TOPRIGHT", -4, filterRows > 1 and -145 or -119)
    end
    if listFrame.transcriptScroll then
        listFrame.transcriptScroll:ClearAllPoints()
        listFrame.transcriptScroll:SetPoint("TOPLEFT", 4, filterRows > 1 and -154 or -128)
        listFrame.transcriptScroll:SetPoint("BOTTOMRIGHT", -22, 36)
    end
    if listFrame.guildRosterRefreshButton then
        listFrame.guildRosterRefreshButton:ClearAllPoints()
        listFrame.guildRosterRefreshButton:ClearAllPoints()
        listFrame.guildRosterRefreshButton:SetPoint("TOPRIGHT", listFrame.right, "TOPRIGHT", -4, -64)
        listFrame.guildRosterRefreshButton:SetShown(data.available and true or false)
    end
    if not data.available then
        SetHubTranscript("|cff66ccffGUILD MANAGER|r\n\n|cff888888You are not currently in a Guild, or the client has not supplied a Guild Roster.|r\n\nJoin a Guild or refresh the roster to see Guild analytics.")
        return
    end
    local lines = { "|cff66ccff" .. string.upper(sectionLabels[section] or "Guild Manager") .. "|r", "|cff888888" .. tostring(#data.members) .. " roster entries Â· calculations from the current local Guild Roster|r", "" }
    if section == "overview" then
        lines[#lines + 1] = string.format("Members: %d  Â·  Online: %d  Â·  Offline: %d  Â·  AFK: %d  Â·  DND: %d  Â·  Unknown: %d", #data.members, c.ONLINE or 0, c.OFFLINE or 0, c.AFK or 0, c.DND or 0, c.UNKNOWN or 0)
        lines[#lines + 1] = string.format("Level: average %s  Â·  median %s  Â·  highest observed %s", data.averageLevel and string.format("%.1f", data.averageLevel) or "n/a", data.medianLevel and string.format("%.1f", data.medianLevel) or "n/a", data.highestLevel or "n/a")
        if data.levelCapKnown then lines[#lines + 1] = string.format("Max-level members: %d (Level %d)", data.maxLevelCount or 0, data.levelCap) end
        lines[#lines + 1] = string.format("Achievement Points: average %s  Â·  median %s  Â·  members with data %d", data.averageAchievement and string.format("%.0f", data.averageAchievement) or "n/a", data.medianAchievement and string.format("%.0f", data.medianAchievement) or "n/a", data.achievementCount or 0)
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cff66ccffCLASS MIX|r"
        for i = 1, math.min(8, #(data.classes or {})) do local item = data.classes[i]; lines[#lines + 1] = string.format("  %s  Â·  %d (%s)", item.name, item.count, GuildPercent(item.count, #data.members)) end
        if data.motd and data.motd ~= "" then lines[#lines + 1] = ""; lines[#lines + 1] = "|cff66ccffMESSAGE OF THE DAY|r"; lines[#lines + 1] = data.motd end
        if data.infoText and data.infoText ~= "" then lines[#lines + 1] = ""; lines[#lines + 1] = "|cff66ccffGUILD INFORMATION|r"; lines[#lines + 1] = data.infoText end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Use the quick filters above to open the matching members in the roster on the left."
    elseif section == "roster" then
        lines[#lines + 1] = string.format("Showing %d of %d roster members.", #names, #data.members)
        if listFrame.guildDrillFilter then lines[#lines + 1] = "A Guild statistic filter is active. Use Clear Filter above to return to the full roster." end
        lines[#lines + 1] = "Use the search box, status filter, and Sort control to narrow or order this list. Select a member to open their existing Player Profile."
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Sort modes include status, name, recent, unread, Guild Rank, Level, Class and Achievement Points."
    elseif section == "levelClass" then
        lines[#lines + 1] = string.format("Average Level: %s  Â·  Median Level: %s  Â·  Highest observed: %s", data.averageLevel and string.format("%.1f", data.averageLevel) or "n/a", data.medianLevel and string.format("%.1f", data.medianLevel) or "n/a", data.highestLevel or "n/a")
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cff66ccffLEVEL DISTRIBUTION|r"
        for _, bucket in ipairs(data.levelBuckets or {}) do lines[#lines + 1] = string.format("  Level %d-%d  Â·  %d members  Â·  %s", bucket.min, bucket.max, bucket.count, GuildPercent(bucket.count, #data.members)) end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cff66ccffCLASS DISTRIBUTION|r"
        for _, item in ipairs(data.classes or {}) do lines[#lines + 1] = string.format("  %s  Â·  %d members  Â·  %s", item.name, item.count, GuildPercent(item.count, #data.members)) end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Select a Level or Class filter above to show matching members in the left roster."
    elseif section == "rankAchievements" then
        lines[#lines + 1] = "|cff66ccffGUILD RANKS|r"
        for _, item in ipairs(data.ranks or {}) do lines[#lines + 1] = string.format("  %s  Â·  %d members  Â·  %s", item.name, item.count, GuildPercent(item.count, #data.members)) end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cff66ccffACHIEVEMENT POINTS|r"
        if (data.achievementCount or 0) == 0 then
            lines[#lines + 1] = "|cff888888Achievement Points are not exposed by the current Guild Roster API response.|r"
        else
            lines[#lines + 1] = string.format("Members with Achievement Points: %d / %d", data.achievementCount, #data.members)
            lines[#lines + 1] = string.format("Average: %.0f  Â·  Median: %.0f", data.averageAchievement or 0, data.medianAchievement or 0)
            lines[#lines + 1] = "Top members by Achievement Points:"
            for i = 1, math.min(8, #(data.topAchievements or {})) do local member = data.topAchievements[i]; lines[#lines + 1] = string.format("  %d. %s  Â·  %d AP", i, member.name, member.achievementPoints) end
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Use the Rank or Achievement filters above to drill into the roster."
    elseif section == "activity" then
        lines[#lines + 1] = string.format("Current presence: Online %d  Â·  AFK %d  Â·  DND %d  Â·  Offline %d  Â·  Unknown %d", c.ONLINE or 0, c.AFK or 0, c.DND or 0, c.OFFLINE or 0, c.UNKNOWN or 0)
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cff66ccffOFFLINE LAST-ONLINE AGE|r"
        lines[#lines + 1] = string.format("  Within 7 days: %d", data.lastOnlineBuckets.recent7 or 0)
        lines[#lines + 1] = string.format("  8-30 days: %d", data.lastOnlineBuckets.recent30 or 0)
        lines[#lines + 1] = string.format("  31-90 days: %d", data.lastOnlineBuckets.recent90 or 0)
        lines[#lines + 1] = string.format("  More than 90 days: %d", data.lastOnlineBuckets.older or 0)
        lines[#lines + 1] = string.format("  Unknown age: %d", data.lastOnlineBuckets.unknown or 0)
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Last-online age is supplied by the client and is approximate. Zone is the last reported zone, not necessarily a current location for offline members."
    elseif section == "analytics" then
        lines[#lines + 1] = string.format("Roster: %d members  Â·  Level data: %d  Â·  Achievement data: %d", #data.members, data.levelCount or 0, data.achievementCount or 0)
        lines[#lines + 1] = string.format("Average Level: %s  Â·  Average Achievement Points: %s", data.averageLevel and string.format("%.1f", data.averageLevel) or "n/a", data.averageAchievement and string.format("%.0f", data.averageAchievement) or "n/a")
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cff66ccffCLASS COMPOSITION|r"
        for _, item in ipairs(data.classes or {}) do lines[#lines + 1] = string.format("  %s  Â·  %d (%s)", item.name, item.count, GuildPercent(item.count, #data.members)) end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cff66ccffRANK COMPOSITION|r"
        for _, item in ipairs(data.ranks or {}) do lines[#lines + 1] = string.format("  %s  Â·  %d (%s)", item.name, item.count, GuildPercent(item.count, #data.members)) end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "All charts and summaries are derived from the current local roster. Missing API values are excluded from averages rather than treated as zero."
    end
    SetHubTranscript(table.concat(lines, "\n\n"))
end

---------------------------------------------------------------------
-- Optional Network Map: an in-window, lazy-built node canvas.
-- The map reads existing contact/Journal sources only after the user
-- explicitly enables it or requests a refresh. It never polls.
---------------------------------------------------------------------
local NETWORK_MAP_RELATIONS = {
    { key = "friends", label = "Friends", color = { 0.24, 0.78, 0.48 } },
    { key = "guild", label = "Guild", color = { 0.58, 0.43, 0.84 } },
    { key = "group", label = "Current Group", color = { 0.88, 0.67, 0.28 } },
    { key = "bnet", label = "Battle.net", color = { 0.25, 0.67, 0.95 } },
    { key = "whispers", label = "Whispers", color = { 0.22, 0.78, 0.78 } },
    { key = "favorites", label = "Favorites", color = { 0.94, 0.76, 0.31 } },
    { key = "personal", label = "My Groups", color = { 0.76, 0.58, 0.37 } },
    { key = "recorded", label = "Recorded Partners", color = { 0.42, 0.68, 0.82 } },
}

local NETWORK_MAP_FILTERS = {
    { key = "all", label = "All Connections" },
    { key = "friends", label = "Friends" },
    { key = "guild", label = "Guild" },
    { key = "group", label = "Current Group" },
    { key = "bnet", label = "Battle.net" },
    { key = "whispers", label = "Whispers" },
    { key = "favorites", label = "Favorites" },
    { key = "personal", label = "My Groups" },
    { key = "recorded", label = "Recorded Partners" },
}

local function StopNetworkMapAnimations()
    if not listFrame then return end
    local function stopPool(pool, hide, alpha)
        for _, object in ipairs(pool or {}) do
            if object._networkAnim then pcall(object._networkAnim.Stop, object._networkAnim) end
            for _, childKey in ipairs({ "glow", "halo", "spark" }) do
                local child = object[childKey]
                if child then
                    for _, animationKey in ipairs({ "_networkGlowAnim", "_networkHaloAnim", "_networkSparkAnim" }) do
                        if child[animationKey] then pcall(child[animationKey].Stop, child[animationKey]) end
                    end
                    if child.SetAlpha then child:SetAlpha(0) end
                end
            end
            if object.SetAlpha then object:SetAlpha(alpha == nil and 1 or alpha) end
            if hide and object.Hide then object:Hide() end
        end
    end
    stopPool(listFrame.networkNodePool, false, 1)
    stopPool(listFrame.networkLinePool, false, 1)
    stopPool(listFrame.networkGlowLinePool, false, 1)
    stopPool(listFrame.networkCoreLinePool, false, 1)
    stopPool(listFrame.networkPulsePool, true, 0)
    stopPool(listFrame.networkSparklePool, false, 0)
end

local function HideNetworkMapPage()
    if not listFrame then return end
    StopNetworkMapAnimations()
    for _, key in ipairs({ "networkEnableButton", "networkLayoutButton", "networkFilterButton", "networkAnimationButton", "networkMotionButton", "networkLimitButton", "networkRefreshButton", "networkDisableButton", "networkThemeButton", "networkZoomButton", "networkFitButton", "networkOpenProfileButton", "networkWhisperButton", "networkSelectionLabel" }) do
        if listFrame[key] then listFrame[key]:Hide() end
    end
    listFrame.networkMapDirty = true
    if listFrame.networkScroll then
        listFrame.networkScroll:SetNetworkMapEnabled(false)
        listFrame.networkScroll:SetScript("OnUpdate", nil)
        listFrame.networkScroll._networkPanStart = nil
        listFrame.networkScroll:Hide()
    end
end

local function EnsureNetworkMapUI()
    if not listFrame or not listFrame.right then return end
    local right = listFrame.right
    if listFrame.networkEnableButton then return end

    local enable = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
    enable:SetSize(154, 24)
    enable:SetPoint("TOPLEFT", right, "TOPLEFT", 4, -66)
    enable:SetText("Enable Network Map")
    enable:SetScript("OnClick", function()
        local hub = EnsureHubPreferences()
        hub.networkMapEnabled = true
        listFrame.networkMapDirty = true
        RefreshInbox()
    end)
    enable:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Enable the optional Network Map", 1, 1, 1)
        GameTooltip:AddLine("Build a visual snapshot from contacts and relationship data already available to SmartChat. No separate tracking or background polling is started.", 0.75, 0.85, 1, true)
        GameTooltip:Show()
    end)
    enable:SetScript("OnLeave", GameTooltip_Hide)
    listFrame.networkEnableButton = enable

    local function makeNetworkButton(key, width, x, label, callback, tooltip)
        local button = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetPoint("TOPLEFT", right, "TOPLEFT", x, -66)
        button:SetText(label)
        button:SetScript("OnClick", callback)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(label, 1, 1, 1)
            if tooltip then GameTooltip:AddLine(tooltip, 0.75, 0.85, 1, true) end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        listFrame[key] = button
        return button
    end

    local x = 4
    makeNetworkButton("networkLayoutButton", 104, x, "Layout: Node", function()
        local hub = EnsureHubPreferences()
        local modes = { "node", "radial", "mind" }
        local index = 1
        for i, mode in ipairs(modes) do if mode == hub.networkMapLayout then index = i break end end
        hub.networkMapLayout = modes[index % #modes + 1]
        listFrame.networkMapDirty = true
        RefreshInbox()
    end, "Cycle between Node Graph, Radial and Mind Map layouts.")
    x = x + 108
    makeNetworkButton("networkFilterButton", 118, x, "Filter: All", function()
        local hub = EnsureHubPreferences()
        local index = 1
        for i, item in ipairs(NETWORK_MAP_FILTERS) do if item.key == hub.networkMapFilter then index = i break end end
        hub.networkMapFilter = NETWORK_MAP_FILTERS[index % #NETWORK_MAP_FILTERS + 1].key
        listFrame.networkMapDirty = true
        RefreshInbox()
    end, "Show all connections or focus on one relationship type.")
    x = x + 122
    makeNetworkButton("networkAnimationButton", 86, x, "Animation: On", function()
        local hub = EnsureHubPreferences()
        hub.networkMapAnimations = not hub.networkMapAnimations
        listFrame.networkMapDirty = true
        RefreshInbox()
    end, "Enable or disable all Network Map motion: ambient shimmer, flowing connection pulses, node glow and staggered node entrances.")
    x = x + 90
    makeNetworkButton("networkMotionButton", 100, x, "Reduce Motion: Off", function()
        local hub = EnsureHubPreferences()
        hub.networkMapReduceMotion = not hub.networkMapReduceMotion
        listFrame.networkMapDirty = true
        RefreshInbox()
    end, "Reduce Motion suppresses all looping shimmer, traveling pulses and entrance transitions while keeping the map fully usable.")
    x = x + 104
    makeNetworkButton("networkLimitButton", 78, x, "Nodes: 24", function()
        local hub = EnsureHubPreferences()
        local limits = { 12, 24, 36, 48 }
        local index = 2
        for i, value in ipairs(limits) do if value == hub.networkMapMaxNodes then index = i break end end
        hub.networkMapMaxNodes = limits[index % #limits + 1]
        listFrame.networkMapDirty = true
        RefreshInbox()
    end, "Set the maximum number of contact nodes shown. Radial layout uses a safer visual cap.")
    x = x + 82
    makeNetworkButton("networkRefreshButton", 72, x, "Refresh", function()
        listFrame.networkMapDirty = true
        RefreshInbox()
    end, "Rebuild the map from the latest available Friends, Guild, Group, Battle.net, Whisper, My Groups and Journal data.")
    x = x + 76
    makeNetworkButton("networkDisableButton", 74, x, "Disable", function()
        local hub = EnsureHubPreferences()
        hub.networkMapEnabled = false
        listFrame.networkMapDirty = true
        listFrame.networkMapBuilt = false
        StopNetworkMapAnimations()
        if listFrame.networkScroll then listFrame.networkScroll:Hide() end
        if listFrame.networkCanvas then
            listFrame.networkCanvas:Hide()
            for _, node in ipairs(listFrame.networkNodePool or {}) do
                node:Hide()
                node.data = nil
                if node.title then node.title:SetText("") end
                if node.meta then node.meta:SetText("") end
            end
            for _, line in ipairs(listFrame.networkLinePool or {}) do line:Hide() end
            for _, line in ipairs(listFrame.networkGlowLinePool or {}) do line:Hide() end
            for _, line in ipairs(listFrame.networkCoreLinePool or {}) do line:Hide() end
            for _, pulse in ipairs(listFrame.networkPulsePool or {}) do pulse:Hide() end
            for _, sparkle in ipairs(listFrame.networkSparklePool or {}) do sparkle:Hide() end
            for _, gridLine in ipairs(listFrame.networkGridLinePool or {}) do gridLine:Hide() end
        end
        if listFrame.networkEmptyText then listFrame.networkEmptyText:Hide() end
        listFrame.networkSelectedName = nil
        RefreshInbox()
    end, "Turn off the visual map and release its rendered node/edge contents. Source data in other SmartChat sections is preserved.")

    local themeButton = makeNetworkButton("networkThemeButton", 102, 4, "Theme: Midnight", function()
        local hub = EnsureHubPreferences()
        local themes = { "midnight", "neon", "minimal" }
        local index = 1
        for i, theme in ipairs(themes) do if theme == hub.networkMapTheme then index = i break end end
        hub.networkMapTheme = themes[index % #themes + 1]
        listFrame.networkMapDirty = true
        RefreshInbox()
    end, "Choose Midnight, Neon or Minimal visual styling. This only changes the Network Map canvas.")
    themeButton:ClearAllPoints()
    themeButton:SetPoint("TOPLEFT", right, "TOPLEFT", 4, -91)

    local zoomButton = makeNetworkButton("networkZoomButton", 82, 110, "Zoom: 100%", function()
        local hub = EnsureHubPreferences()
        local zooms = { 80, 100, 120 }
        local index = 2
        for i, value in ipairs(zooms) do if value == hub.networkMapZoom then index = i break end end
        hub.networkMapZoom = zooms[index % #zooms + 1]
        listFrame.networkMapDirty = true
        RefreshInbox()
    end, "Scale node spacing and node sizes. Use the scroll area to pan around larger layouts.")
    zoomButton:ClearAllPoints()
    zoomButton:SetPoint("TOPLEFT", right, "TOPLEFT", 110, -91)

    local fitButton = makeNetworkButton("networkFitButton", 86, 196, "Fit / Reset", function()
        local hub = EnsureHubPreferences()
        hub.networkMapZoom = 100
        listFrame.networkMapDirty = true
        if listFrame.networkScroll then
            listFrame.networkScroll:SetHorizontalScroll(0)
            listFrame.networkScroll:SetVerticalScroll(0)
        end
        RefreshInbox()
    end, "Restore 100% zoom and return the map view to the top-left starting position.")
    fitButton:ClearAllPoints()
    fitButton:SetPoint("TOPLEFT", right, "TOPLEFT", 196, -91)

    local selection = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    selection:SetPoint("TOPLEFT", right, "TOPLEFT", 5, -117)
    selection:SetPoint("TOPRIGHT", right, "TOPRIGHT", -5, -117)
    selection:SetJustifyH("LEFT")
    selection:SetWordWrap(false)
    selection:SetText("Select a contact node")
    listFrame.networkSelectionLabel = selection

    local openProfile = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
    openProfile:SetSize(104, 22)
    openProfile:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 4, 3)
    openProfile:SetText("Open Profile")
    openProfile:SetScript("OnClick", function()
        local name = listFrame.networkSelectedName
        if not name then return end
        listFrame.category = "all"
        listFrame.mode = "profile"
        listFrame.profileSection = "overview"
        listFrame.selectedName = name
        RefreshInbox()
    end)
    listFrame.networkOpenProfileButton = openProfile

    local whisper = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
    whisper:SetSize(86, 22)
    whisper:SetPoint("LEFT", openProfile, "RIGHT", 5, 0)
    whisper:SetText("Whisper")
    whisper:SetScript("OnClick", function()
        local name = listFrame.networkSelectedName
        if name and SC.OpenWhisperTab then
            SC.OpenWhisperTab(name)
            listFrame:Hide()
        end
    end)
    listFrame.networkWhisperButton = whisper
    openProfile:Disable(); whisper:Disable()

end

local function EnsureNetworkMapCanvas()
    if not listFrame or not listFrame.right then return end
    if listFrame.networkScroll and listFrame.networkCanvas then return end
    local right = listFrame.right
    local scroll = CreateFrame("ScrollFrame", nil, right, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", right, "TOPLEFT", 4, -140)
    scroll:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -22, 32)
    scroll:EnableMouse(true)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll, "BackdropTemplate")
    child:SetSize(940, 520)
    child:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    child:SetBackdropColor(0.018, 0.028, 0.046, 0.98)
    child:SetBackdropBorderColor(0.16, 0.24, 0.34, 0.85)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        if IsShiftKeyDown and IsShiftKeyDown() and self.SetHorizontalScroll then
            local current = self.GetHorizontalScroll and self:GetHorizontalScroll() or 0
            local maxScroll = math.max(0, (child:GetWidth() or 1) - (self:GetWidth() or 1))
            self:SetHorizontalScroll(math.max(0, math.min(maxScroll, current - delta * 48)))
        else
            local current = self:GetVerticalScroll() or 0
            local maxScroll = math.max(0, (child:GetHeight() or 1) - (self:GetHeight() or 1))
            self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * 48)))
        end
    end)

    local hubOrMapEnabled = false
    local function stopNetworkPan(frame)
        frame._networkPanStart = nil
        frame:SetScript("OnUpdate", nil)
    end
    local function beginNetworkPan(frame, button)
        if button ~= "LeftButton" or not hubOrMapEnabled then return end
        if not GetCursorPosition then return end
        local mouseX, mouseY = GetCursorPosition()
        local scale = frame:GetEffectiveScale() or 1
        frame._networkPanStart = {
            x = mouseX, y = mouseY, scale = scale,
            horizontal = scroll:GetHorizontalScroll() or 0,
            vertical = scroll:GetVerticalScroll() or 0,
        }
        scroll:SetScript("OnUpdate", function(self)
            local start = self._networkPanStart
            if not start then stopNetworkPan(self); return end
            local currentX, currentY = GetCursorPosition()
            local dx = (currentX - start.x) / start.scale
            local dy = (currentY - start.y) / start.scale
            local maxH = math.max(0, (child:GetWidth() or 1) - (self:GetWidth() or 1))
            local maxV = math.max(0, (child:GetHeight() or 1) - (self:GetHeight() or 1))
            self:SetHorizontalScroll(math.max(0, math.min(maxH, start.horizontal - dx)))
            self:SetVerticalScroll(math.max(0, math.min(maxV, start.vertical + dy)))
        end)
    end
    -- Panning only installs an OnUpdate handler while the user is dragging.
    -- There is no permanent update loop when the map is idle.
    scroll:SetScript("OnMouseDown", function(self, button) beginNetworkPan(self, button) end)
    scroll:SetScript("OnMouseUp", function(self) stopNetworkPan(self) end)
    scroll:SetScript("OnHide", function(self) stopNetworkPan(self) end)
    child:EnableMouse(true)
    child:SetScript("OnMouseDown", function(self, button) beginNetworkPan(scroll, button) end)
    child:SetScript("OnMouseUp", function() stopNetworkPan(scroll) end)
    -- The map page updates this lightweight gate when it is shown.
    scroll.SetNetworkMapEnabled = function(_, enabled) hubOrMapEnabled = enabled and true or false end

    listFrame.networkScroll = scroll
    listFrame.networkCanvas = child
    listFrame.networkNodePool = {}
    listFrame.networkLinePool = {}
    scroll:Hide()
end

local function BuildNetworkMapSnapshot()
    local hubPrefs = EnsureHubPreferences()
    local filterKey = hubPrefs.networkMapFilter or "all"
    local nodesByKey, hubs = {}, {}
    local playerName = SC.PlayerDisplayName and SC.PlayerDisplayName("player") or (UnitName and UnitName("player")) or ""
    local playerKey = SC.NameKey(playerName)

    local function ensureNode(name)
        if type(name) ~= "string" or name == "" then return nil end
        local key = SC.NameKey(name)
        if key == "" or key == playerKey then return nil end
        local node = nodesByKey[key]
        if not node then
            node = { key = key, name = name, relations = {}, personalGroups = {} }
            nodesByKey[key] = node
        end
        return node
    end

    local function addSource(source, names)
        if filterKey ~= "all" and filterKey ~= source.key then return end
        local seen, members = {}, {}
        for _, name in ipairs(names or {}) do
            local node = ensureNode(name)
            if node and not seen[node.key] then
                seen[node.key] = true
                node.relations[source.key] = true
                members[#members + 1] = node
            end
        end
        if #members > 0 then
            hubs[#hubs + 1] = { key = source.key, label = source.label, color = source.color, members = members, count = #members }
        end
    end

    for _, source in ipairs(NETWORK_MAP_RELATIONS) do
        if source.key == "personal" then
            if filterKey == "all" or filterKey == "personal" then
            local names, seen = {}, {}
            local social = SC.db.social or {}
            for _, groupName in ipairs(social.groupOrder or {}) do
                local members = social.groups and social.groups[groupName]
                if type(members) == "table" then
                    for _, name in pairs(members) do
                        local node = ensureNode(name)
                        if node then
                            node.relations.personal = true
                            node.personalGroups[#node.personalGroups + 1] = groupName
                            if not seen[node.key] then seen[node.key] = true; names[#names + 1] = name end
                        end
                    end
                end
            end
            addSource(source, names)
            end
        elseif source.key == "recorded" then
            if filterKey == "all" or filterKey == "recorded" then
            local names, seen = {}, {}
            local journal = SC.db.journal or {}
            for _, event in ipairs(journal.events or {}) do
                if event.type == "group" and type(event.names) == "table" then
                    for _, name in ipairs(event.names) do
                        local node = ensureNode(name)
                        if node then
                            node.relations.recorded = true
                            if not seen[node.key] then seen[node.key] = true; names[#names + 1] = name end
                        end
                    end
                end
            end
            addSource(source, names)
            end
        else
            if filterKey == "all" or filterKey == source.key then
                addSource(source, CollectSocialContacts(source.key, true))
            end
        end
    end

    local contacts = {}
    for _, node in pairs(nodesByKey) do
        node.info = SC.GetContactInfo and SC.GetContactInfo(node.name) or { status = "UNKNOWN" }
        node.status = node.info.status or "UNKNOWN"
        node.class = node.info.class or "Unknown"
        node.level = tonumber(node.info.level)
        node.favorite = SC.IsFavorite and SC.IsFavorite(node.name) or false
        node.pinned = SC.IsContactPinned and SC.IsContactPinned(node.name) or false
        table.sort(node.personalGroups, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
        contacts[#contacts + 1] = node
    end
    table.sort(contacts, function(a, b)
        local aPriority = (a.pinned and 100 or 0) + (a.favorite and 50 or 0) + (function() local n=0; for _ in pairs(a.relations) do n=n+1 end; return n end)()
        local bPriority = (b.pinned and 100 or 0) + (b.favorite and 50 or 0) + (function() local n=0; for _ in pairs(b.relations) do n=n+1 end; return n end)()
        if aPriority ~= bPriority then return aPriority > bPriority end
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)

    local visibleLimit = tonumber(hubPrefs.networkMapMaxNodes) or 24
    if hubPrefs.networkMapLayout == "radial" then visibleLimit = math.min(visibleLimit, 16) end
    local totalContacts = #contacts
    local visible = {}
    for i = 1, math.min(totalContacts, visibleLimit) do visible[#visible + 1] = contacts[i] end
    local visibleKeys = {}
    for _, node in ipairs(visible) do visibleKeys[node.key] = true end
    for _, relation in ipairs(hubs) do
        local kept = {}
        for _, node in ipairs(relation.members) do if visibleKeys[node.key] then kept[#kept + 1] = node end end
        relation.members = kept
        relation.count = #kept
    end
    local compactHubs = {}
    for _, relation in ipairs(hubs) do if relation.count > 0 then compactHubs[#compactHubs + 1] = relation end end
    return visible, compactHubs, totalContacts, math.max(0, totalContacts - #visible)
end

local function NetworkMapColor(status)
    local colors = {
        ONLINE = { 0.28, 0.86, 0.55 }, OFFLINE = { 0.48, 0.54, 0.62 },
        AFK = { 0.92, 0.72, 0.32 }, DND = { 0.91, 0.48, 0.28 }, UNKNOWN = { 0.35, 0.62, 0.82 },
    }
    return colors[status] or colors.UNKNOWN
end

local function AcquireNetworkNode(index, canvas)
    local node = listFrame.networkNodePool[index]
    if not node then
        node = CreateFrame("Button", nil, canvas, "BackdropTemplate")
        node:SetFrameLevel(canvas:GetFrameLevel() + 3)
        node:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        node.glow = node:CreateTexture(nil, "BACKGROUND")
        node.glow:SetTexture("Interface\\Buttons\\WHITE8X8")
        node.glow:SetPoint("TOPLEFT", node, "TOPLEFT", -4, 4)
        node.glow:SetPoint("BOTTOMRIGHT", node, "BOTTOMRIGHT", 4, -4)
        if node.glow.SetBlendMode then node.glow:SetBlendMode("ADD") end
        node.halo = node:CreateTexture(nil, "ARTWORK")
        node.halo:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        node.halo:SetSize(38, 38)
        node.halo:SetPoint("LEFT", node, "LEFT", 1, 0)
        if node.halo.SetBlendMode then node.halo:SetBlendMode("ADD") end
        node.spark = node:CreateTexture(nil, "OVERLAY")
        node.spark:SetTexture("Interface\\Cooldown\\star4")
        node.spark:SetSize(15, 15)
        node.spark:SetPoint("TOPRIGHT", node, "TOPRIGHT", -3, -2)
        if node.spark.SetBlendMode then node.spark:SetBlendMode("ADD") end
        node.title = node:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        node.title:SetPoint("TOPLEFT", 37, -6)
        node.title:SetPoint("TOPRIGHT", -18, -6)
        node.title:SetJustifyH("LEFT")
        node.title:SetWordWrap(false)
        node.meta = node:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        node.meta:SetPoint("BOTTOMLEFT", 37, 6)
        node.meta:SetPoint("BOTTOMRIGHT", -18, 6)
        node.meta:SetJustifyH("LEFT")
        node.meta:SetWordWrap(false)
        node.statusDot = node:CreateTexture(nil, "OVERLAY")
        node.statusDot:SetSize(7, 7)
        node.statusDot:SetPoint("RIGHT", -7, 0)
        node:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        listFrame.networkNodePool[index] = node
    end
    node:SetParent(canvas)
    node:Show()
    return node
end

local function AcquireNetworkLineFromPool(index, canvas, poolName, drawLayer)
    local pool = listFrame[poolName]
    if not pool then pool = {}; listFrame[poolName] = pool end
    local line = pool[index]
    if not line then
        line = canvas:CreateLine(nil, drawLayer or "BORDER")
        pool[index] = line
    end
    line:ClearAllPoints()
    line:Show()
    return line
end

local function SetNetworkLine(index, canvas, x1, y1, x2, y2, color, thickness, alpha)
    local glow = AcquireNetworkLineFromPool(index, canvas, "networkGlowLinePool", "BORDER")
    glow:SetThickness((thickness or 2) * 3.2)
    glow:SetColorTexture(color[1], color[2], color[3], math.min(0.24, (alpha or 0.48) * 0.28))
    glow:SetStartPoint("TOPLEFT", canvas, x1, -y1)
    glow:SetEndPoint("TOPLEFT", canvas, x2, -y2)

    local line = AcquireNetworkLineFromPool(index, canvas, "networkLinePool", "ARTWORK")
    line:SetThickness(thickness or 2)
    line:SetColorTexture(color[1], color[2], color[3], alpha or 0.48)
    line:SetStartPoint("TOPLEFT", canvas, x1, -y1)
    line:SetEndPoint("TOPLEFT", canvas, x2, -y2)

    local core = AcquireNetworkLineFromPool(index, canvas, "networkCoreLinePool", "OVERLAY")
    core:SetThickness(math.max(0.8, (thickness or 2) * 0.52))
    core:SetColorTexture(
        math.min(1, color[1] * 0.58 + 0.42),
        math.min(1, color[2] * 0.58 + 0.42),
        math.min(1, color[3] * 0.58 + 0.42),
        math.min(0.68, (alpha or 0.48) * 0.62)
    )
    core:SetStartPoint("TOPLEFT", canvas, x1, -y1)
    core:SetEndPoint("TOPLEFT", canvas, x2, -y2)
end

local function StartNetworkAlphaLoop(owner, fieldName, lowAlpha, highAlpha, duration, delay)
    if not owner or not owner.CreateAnimationGroup then return nil end
    local group = owner[fieldName]
    if not group then
        local ok, created = pcall(owner.CreateAnimationGroup, owner)
        if not ok or not created then return nil end
        group = created
        local okAlpha, alpha = pcall(group.CreateAnimation, group, "Alpha")
        if not okAlpha or not alpha then return nil end
        pcall(alpha.SetFromAlpha, alpha, lowAlpha or 0.12)
        pcall(alpha.SetToAlpha, alpha, highAlpha or 0.85)
        pcall(alpha.SetDuration, alpha, duration or 1.8)
        if delay and alpha.SetStartDelay then pcall(alpha.SetStartDelay, alpha, delay) end
        if alpha.SetSmoothing then pcall(alpha.SetSmoothing, alpha, "IN_OUT") end
        if group.SetLooping then pcall(group.SetLooping, group, "BOUNCE") end
        owner[fieldName] = group
    end
    if owner.SetAlpha then owner:SetAlpha(1) end
    pcall(group.Stop, group)
    pcall(group.Play, group)
    return group
end

local function AnimateNetworkNode(node, index, preferences)
    local motion = preferences.networkMapAnimations and not preferences.networkMapReduceMotion
    if not motion then
        node:SetAlpha(1)
        if node.glow then node.glow:SetAlpha(0.16) end
        if node.halo then node.halo:SetAlpha(0.42) end
        if node.spark then node.spark:SetAlpha(0.55) end
        return
    end
    local group = node._networkAnim
    if not group and node.CreateAnimationGroup then
        local ok, animationGroup = pcall(node.CreateAnimationGroup, node)
        if ok and animationGroup then
            group = animationGroup
            local okAnimation, alpha = pcall(group.CreateAnimation, group, "Alpha")
            if okAnimation and alpha then
                pcall(alpha.SetFromAlpha, alpha, 0.04)
                pcall(alpha.SetToAlpha, alpha, 1)
                pcall(alpha.SetDuration, alpha, 0.42)
                if alpha.SetStartDelay then pcall(alpha.SetStartDelay, alpha, math.min(0.85, math.max(0, (index - 1) * 0.025))) end
                if alpha.SetSmoothing then pcall(alpha.SetSmoothing, alpha, "OUT") end
                node._networkAnim = group
            else
                group = nil
            end
        end
    end
    node:SetAlpha(1)
    if group then pcall(group.Stop, group); pcall(group.Play, group) end
    if node.glow then StartNetworkAlphaLoop(node.glow, "_networkGlowAnim", 0.06, 0.30, 2.1, (index % 7) * 0.11) end
    if node.halo then StartNetworkAlphaLoop(node.halo, "_networkHaloAnim", 0.16, 0.70, 2.6, (index % 5) * 0.13) end
    if node.spark then StartNetworkAlphaLoop(node.spark, "_networkSparkAnim", 0.10, 0.96, 1.55, (index % 9) * 0.09) end
end

local function AcquireNetworkPulse(index, canvas)
    local pool = listFrame.networkPulsePool
    if not pool then pool = {}; listFrame.networkPulsePool = pool end
    local pulse = pool[index]
    if not pulse then
        pulse = CreateFrame("Frame", nil, canvas)
        pulse:SetSize(18, 18)
        pulse.texture = pulse:CreateTexture(nil, "OVERLAY")
        pulse.texture:SetTexture("Interface\\Cooldown\\star4")
        pulse.texture:SetAllPoints(pulse)
        if pulse.texture.SetBlendMode then pulse.texture:SetBlendMode("ADD") end
        pulse:SetFrameLevel(canvas:GetFrameLevel() + 2)
        pool[index] = pulse
    end
    pulse:SetParent(canvas)
    pulse:Show()
    return pulse
end

local function AnimateNetworkPulse(index, canvas, x1, y1, x2, y2, zoom, color, preferences)
    if not preferences.networkMapAnimations or preferences.networkMapReduceMotion then return end
    local pulse = AcquireNetworkPulse(index, canvas)
    pulse:ClearAllPoints()
    pulse:SetPoint("CENTER", canvas, "TOPLEFT", x1 * zoom, -y1 * zoom)
    pulse.texture:SetVertexColor(color[1], color[2], color[3], 1)
    local group = pulse._networkAnim
    if not group then
        local ok, created = pcall(pulse.CreateAnimationGroup, pulse)
        if not ok or not created then pulse:Hide(); return end
        group = created
        local okMove, move = pcall(group.CreateAnimation, group, "Translation")
        local okAlpha, alpha = pcall(group.CreateAnimation, group, "Alpha")
        if not okMove or not move or not okAlpha or not alpha then pulse:Hide(); return end
        pulse._networkMove = move
        pcall(alpha.SetFromAlpha, alpha, 0.08)
        pcall(alpha.SetToAlpha, alpha, 1)
        pcall(alpha.SetDuration, alpha, 2.1)
        if group.SetLooping then pcall(group.SetLooping, group, "REPEAT") end
        pulse._networkAnim = group
    end
    if pulse._networkMove and pulse._networkMove.SetOffset then
        pcall(pulse._networkMove.SetOffset, pulse._networkMove, (x2 - x1) * zoom, -(y2 - y1) * zoom)
        pcall(pulse._networkMove.SetDuration, pulse._networkMove, 2.0 + (index % 5) * 0.22)
    end
    if pulse._networkMove and pulse._networkMove.SetSmoothing then pcall(pulse._networkMove.SetSmoothing, pulse._networkMove, "IN_OUT") end
    pulse:SetAlpha(1)
    pcall(group.Stop, group)
    pcall(group.Play, group)
end

local function EnsureNetworkMapDecorations(canvas)
    if not listFrame.networkHeaderTitle then
        local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", canvas, "TOPLEFT", 22, -12)
        title:SetText("SMARTCHAT  /  SOCIAL NETWORK")
        listFrame.networkHeaderTitle = title
        local subtitle = canvas:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -2)
        subtitle:SetText("RELATIONSHIP CONSTELLATION  â¢  CONTACT INTELLIGENCE  â¢  LIVE PRESENCE")
        listFrame.networkHeaderSubtitle = subtitle
        local rule = canvas:CreateTexture(nil, "ARTWORK")
        rule:SetTexture("Interface\\Buttons\\WHITE8X8")
        rule:SetPoint("TOPLEFT", canvas, "TOPLEFT", 22, -48)
        rule:SetSize(310, 1)
        listFrame.networkHeaderRule = rule
    end
    if not listFrame.networkGridLinePool then listFrame.networkGridLinePool = {} end
    if not listFrame.networkSparklePool then listFrame.networkSparklePool = {} end
end

local function RenderNetworkMapDecorations(canvas, width, height, zoom, theme, preferences)
    EnsureNetworkMapDecorations(canvas)
    local titleColor = theme.header or theme.root
    listFrame.networkHeaderTitle:SetTextColor(titleColor[1], titleColor[2], titleColor[3])
    listFrame.networkHeaderSubtitle:SetTextColor(theme.neutral[1], theme.neutral[2], theme.neutral[3], 0.88)
    listFrame.networkHeaderRule:SetVertexColor(titleColor[1], titleColor[2], titleColor[3], 0.42)

    local gridIndex = 0
    local gridColor = theme.grid or { 0.18, 0.28, 0.42 }
    local function gridLine(x1, y1, x2, y2)
        gridIndex = gridIndex + 1
        local line = listFrame.networkGridLinePool[gridIndex]
        if not line then
            line = canvas:CreateLine(nil, "BACKGROUND")
            listFrame.networkGridLinePool[gridIndex] = line
        end
        line:SetThickness(1)
        line:SetColorTexture(gridColor[1], gridColor[2], gridColor[3], 0.18)
        line:SetStartPoint("TOPLEFT", canvas, x1 * zoom, -y1 * zoom)
        line:SetEndPoint("TOPLEFT", canvas, x2 * zoom, -y2 * zoom)
        line:Show()
    end
    for x = 48, width - 1, 48 do gridLine(x, 0, x, height) end
    for y = 72, height - 1, 48 do gridLine(0, y, width, y) end
    for i = gridIndex + 1, #listFrame.networkGridLinePool do listFrame.networkGridLinePool[i]:Hide() end

    local motion = preferences.networkMapAnimations and not preferences.networkMapReduceMotion
    local sparkleCount = 30
    for i = 1, sparkleCount do
        local sparkle = listFrame.networkSparklePool[i]
        if not sparkle then
            sparkle = CreateFrame("Frame", nil, canvas)
            sparkle.texture = sparkle:CreateTexture(nil, "OVERLAY")
            sparkle.texture:SetTexture("Interface\\Cooldown\\star4")
            sparkle.texture:SetAllPoints(sparkle)
            if sparkle.texture.SetBlendMode then sparkle.texture:SetBlendMode("ADD") end
            listFrame.networkSparklePool[i] = sparkle
        end
        local size = 5 + (i % 4) * 2
        local x = 18 + ((i * 137) % math.max(1, width - 36))
        local y = 70 + ((i * 89) % math.max(1, height - 90))
        sparkle:SetSize(size, size)
        sparkle:ClearAllPoints()
        sparkle:SetPoint("CENTER", canvas, "TOPLEFT", x * zoom, -y * zoom)
        local tint = (i % 3 == 0) and (theme.secondary or theme.root) or titleColor
        sparkle.texture:SetVertexColor(tint[1], tint[2], tint[3], 1)
        sparkle:Show()
        if motion then
            StartNetworkAlphaLoop(sparkle, "_networkAnim", 0.08, 0.86, 1.6 + (i % 7) * 0.31, (i % 11) * 0.17)
        else
            if sparkle._networkAnim then pcall(sparkle._networkAnim.Stop, sparkle._networkAnim) end
            sparkle:SetAlpha(0.28 + (i % 4) * 0.07)
        end
    end
    for i = sparkleCount + 1, #listFrame.networkSparklePool do listFrame.networkSparklePool[i]:Hide() end
end

local function PlaceNetworkNode(node, canvas, x, y, width, height)
    node:ClearAllPoints()
    node:SetSize(width, height)
    node:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, -y)
    node.networkX, node.networkY = x + width / 2, y + height / 2
end

local function RenderNetworkMapSnapshot()
    if not listFrame then return end
    EnsureNetworkMapCanvas()
    if not listFrame.networkCanvas then return end
    local hub = EnsureHubPreferences()
    local canvas = listFrame.networkCanvas
    local zoom = (tonumber(hub.networkMapZoom) or 100) / 100
    zoom = math.max(0.8, math.min(1.2, zoom))
    local themes = {
        midnight = { background = { 0.010, 0.018, 0.038, 0.995 }, border = { 0.18, 0.34, 0.52, 0.96 }, root = { 0.26, 0.72, 1.00 }, header = { 0.40, 0.84, 1.00 }, secondary = { 0.68, 0.40, 1.00 }, grid = { 0.16, 0.30, 0.48 }, neutral = { 0.40, 0.60, 0.82 }, lineAlpha = 0.70, lineThickness = 2.4 },
        neon = { background = { 0.006, 0.012, 0.028, 0.998 }, border = { 0.22, 0.38, 0.64, 1.00 }, root = { 0.12, 0.88, 1.00 }, header = { 0.18, 0.96, 1.00 }, secondary = { 0.92, 0.26, 0.86 }, grid = { 0.20, 0.32, 0.58 }, neutral = { 0.40, 0.72, 0.96 }, lineAlpha = 0.86, lineThickness = 2.8 },
        minimal = { background = { 0.026, 0.034, 0.050, 0.99 }, border = { 0.28, 0.36, 0.48, 0.92 }, root = { 0.55, 0.74, 0.92 }, header = { 0.66, 0.80, 0.94 }, secondary = { 0.52, 0.64, 0.82 }, grid = { 0.24, 0.32, 0.44 }, neutral = { 0.52, 0.62, 0.74 }, lineAlpha = 0.40, lineThickness = 1.7 },
    }
    local theme = themes[hub.networkMapTheme] or themes.midnight
    StopNetworkMapAnimations()
    for _, node in ipairs(listFrame.networkNodePool or {}) do node:Hide() end
    for _, line in ipairs(listFrame.networkLinePool or {}) do line:Hide() end
    for _, line in ipairs(listFrame.networkGlowLinePool or {}) do line:Hide() end
    for _, line in ipairs(listFrame.networkCoreLinePool or {}) do line:Hide() end
    for _, pulse in ipairs(listFrame.networkPulsePool or {}) do pulse:Hide() end

    local contacts, hubs, totalContacts, omitted = BuildNetworkMapSnapshot()
    local layout = hub.networkMapLayout or "node"
    local filterLabel = "All Connections"
    for _, item in ipairs(NETWORK_MAP_FILTERS) do if item.key == hub.networkMapFilter then filterLabel = item.label break end end

    local width, height = 980, 520
    local positions, hubPositions = {}, {}
    local contactWidth, contactHeight = 166, 50
    local hubWidth, hubHeight = 146, 44
    local rootWidth, rootHeight = 154, 58
    local rootX, rootY

    if layout == "radial" then
        width, height = 1200, 940
        local radialCenterX, radialCenterY = 600, 470
        rootX, rootY = radialCenterX - rootWidth / 2, radialCenterY - rootHeight / 2
        for i, relation in ipairs(hubs) do
            local angle = (-math.pi / 2) + ((i - 1) * (2 * math.pi / math.max(1, #hubs)))
            local centerX, centerY = radialCenterX + math.cos(angle) * 190, radialCenterY + math.sin(angle) * 190
            hubPositions[relation.key] = { x = centerX - 134 / 2, y = centerY - 42 / 2, width = 134, height = 42 }
        end
        for i, person in ipairs(contacts) do
            local angle = (-math.pi / 2) + ((i - 1) * (2 * math.pi / math.max(1, #contacts)))
            local centerX, centerY = radialCenterX + math.cos(angle) * 376, radialCenterY + math.sin(angle) * 376
            positions[person.key] = { x = centerX - 132 / 2, y = centerY - 48 / 2, width = 132, height = 48 }
        end
        contactWidth, contactHeight = 132, 48
        hubWidth, hubHeight = 134, 42
    elseif layout == "mind" then
        local grouped, groupRows = {}, {}
        for _, relation in ipairs(hubs) do grouped[relation.key] = {}; groupRows[relation.key] = 0 end
        for _, person in ipairs(contacts) do
            local primary
            for _, relation in ipairs(hubs) do if person.relations[relation.key] then primary = relation.key break end end
            primary = primary or (hubs[1] and hubs[1].key)
            if primary then grouped[primary][#grouped[primary] + 1] = person end
        end
        local y = 104
        for _, relation in ipairs(hubs) do
            local members = grouped[relation.key] or {}
            local rows = math.ceil(#members / 2)
            local blockHeight = math.max(58, rows * 64)
            hubPositions[relation.key] = { x = 284, y = y + blockHeight / 2 - hubHeight / 2, width = hubWidth, height = hubHeight }
            for i, person in ipairs(members) do
                local col = (i - 1) % 2
                local row = math.floor((i - 1) / 2)
                positions[person.key] = { x = 506 + col * 220, y = y + row * 64, width = contactWidth, height = contactHeight }
            end
            y = y + blockHeight + 20
        end
        height = math.max(470, y + 30)
        rootX, rootY = 26, height / 2 - rootHeight / 2
    else -- Node Graph
        local rows = math.ceil(#contacts / 2)
        height = math.max(530, rows * 66 + 168)
        rootX, rootY = 26, height / 2 - rootHeight / 2
        for i, relation in ipairs(hubs) do
            local y = (#hubs == 1) and (height / 2 - hubHeight / 2) or (104 + (i - 1) * (height - 160) / ( #hubs - 1))
            hubPositions[relation.key] = { x = 282, y = y, width = hubWidth, height = hubHeight }
        end
        for i, person in ipairs(contacts) do
            local col = (i - 1) % 2
            local row = math.floor((i - 1) / 2)
            positions[person.key] = { x = 516 + col * 222, y = 104 + row * 66, width = contactWidth, height = contactHeight }
        end
    end

    canvas:SetSize(width * zoom, height * zoom)
    canvas:SetBackdropColor(theme.background[1], theme.background[2], theme.background[3], theme.background[4])
    canvas:SetBackdropBorderColor(theme.border[1], theme.border[2], theme.border[3], theme.border[4])
    RenderNetworkMapDecorations(canvas, width, height, zoom, theme, hub)
    local lineIndex = 0
    local pulseIndex = 0
    local function addLine(x1, y1, x2, y2, color, thickness, alpha)
        -- A short cubic-Bezier polyline gives the connections a softer,
        -- compositor-style curve without an expensive animation or shader.
        local dx, dy = x2 - x1, y2 - y1
        local length = math.sqrt(dx * dx + dy * dy)
        local curve = math.min(42, length * 0.11)
        local ox, oy = 0, 0
        if length > 0 then ox, oy = (-dy / length) * curve, (dx / length) * curve end
        local c1x, c1y = x1 + dx * 0.32 + ox, y1 + dy * 0.32 + oy
        local c2x, c2y = x1 + dx * 0.68 + ox, y1 + dy * 0.68 + oy
        local previousX, previousY = x1, y1
        local segments = 5
        for step = 1, segments do
            local t = step / segments
            local u = 1 - t
            local px = (u * u * u * x1) + (3 * u * u * t * c1x) + (3 * u * t * t * c2x) + (t * t * t * x2)
            local py = (u * u * u * y1) + (3 * u * u * t * c1y) + (3 * u * t * t * c2y) + (t * t * t * y2)
            lineIndex = lineIndex + 1
            SetNetworkLine(lineIndex, canvas, previousX * zoom, previousY * zoom, px * zoom, py * zoom, color, (thickness or theme.lineThickness) * zoom, alpha or theme.lineAlpha)
            previousX, previousY = px, py
        end
        if pulseIndex < 28 and hub.networkMapAnimations and not hub.networkMapReduceMotion then
            pulseIndex = pulseIndex + 1
            AnimateNetworkPulse(pulseIndex, canvas, x1, y1, x2, y2, zoom, color, hub)
        end
    end

    local rootCenterX, rootCenterY = rootX + rootWidth / 2, rootY + rootHeight / 2
    for _, relation in ipairs(hubs) do
        local pos = hubPositions[relation.key]
        if pos then
            local centerX, centerY = pos.x + pos.width / 2, pos.y + pos.height / 2
            addLine(rootCenterX, rootCenterY, centerX, centerY, relation.color, 3, 0.34)
            for _, person in ipairs(relation.members) do
                local personPos = positions[person.key]
                if personPos then
                    addLine(centerX, centerY, personPos.x + personPos.width / 2, personPos.y + personPos.height / 2, relation.color, 2, 0.50)
                end
            end
        end
    end

    local nodeIndex = 0
    local function createNode(kind, data, x, y, w, h, accent)
        nodeIndex = nodeIndex + 1
        local node = AcquireNetworkNode(nodeIndex, canvas)
        PlaceNetworkNode(node, canvas, x * zoom, y * zoom, w * zoom, h * zoom)
        node.data = data
        node.kind = kind
        node.networkAccent = accent
        node:SetBackdropColor(kind == "root" and theme.root[1] * 0.30 or (kind == "hub" and 0.055 or 0.035), kind == "root" and theme.root[2] * 0.28 or (kind == "hub" and 0.075 or 0.055), kind == "root" and theme.root[3] * 0.30 or (kind == "hub" and 0.11 or 0.085), 0.98)
        node:SetBackdropBorderColor(accent[1], accent[2], accent[3], kind == "contact" and 0.96 or 1)
        if node.glow then
            node.glow:SetVertexColor(accent[1], accent[2], accent[3], 1)
            node.glow:SetAlpha(0.16)
        end
        if node.halo then
            node.halo:SetVertexColor(accent[1], accent[2], accent[3], 1)
            node.halo:SetAlpha(0.48)
        end
        if node.spark then
            node.spark:SetVertexColor(accent[1], accent[2], accent[3], 1)
            node.spark:SetAlpha(0.62)
        end
        if not node.accentStrip then
            node.accentStrip = node:CreateTexture(nil, "OVERLAY")
            node.accentStrip:SetPoint("TOPLEFT", node, "TOPLEFT", 1, -4)
            node.accentStrip:SetPoint("BOTTOMLEFT", node, "BOTTOMLEFT", 1, 4)
            node.accentStrip:SetWidth(3)
        end
        node.accentStrip:SetColorTexture(accent[1], accent[2], accent[3], 0.95)
        node.accentStrip:Show()
        if kind == "root" then
            node.title:SetText("MY CHARACTER")
            node.title:SetTextColor(0.90, 0.95, 1)
            local player = SC.PlayerDisplayName and SC.PlayerDisplayName("player") or (UnitName and UnitName("player")) or "Player"
            local className = UnitClass and select(1, UnitClass("player")) or ""
            local level = UnitLevel and UnitLevel("player") or nil
            local meta = tostring(player)
            if className and className ~= "" then meta = meta .. " Â· " .. className end
            if level then meta = meta .. " Â· Lv. " .. tostring(level) end
            node.meta:SetText(meta)
            node.statusDot:Hide()
            node:SetScript("OnEnter", nil)
            node:SetScript("OnLeave", nil)
            node:SetScript("OnClick", function()
                hub.networkMapFilter = "all"
                listFrame.networkMapDirty = true
                RefreshInbox()
            end)
        elseif kind == "hub" then
            node.title:SetText(data.label)
            node.title:SetTextColor(accent[1], accent[2], accent[3])
            node.meta:SetText(tostring(data.count) .. (data.count == 1 and " contact" or " contacts"))
            node.statusDot:Hide()
            node:SetScript("OnClick", function()
                hub.networkMapFilter = data.key
                listFrame.networkMapDirty = true
                RefreshInbox()
            end)
            node:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(data.label, 1, 1, 1)
                GameTooltip:AddLine(tostring(data.count) .. " contact(s) in this relationship category.", 0.75, 0.85, 1, true)
                GameTooltip:AddLine("Click to focus this connection type. Click the root node to show all.", 0.75, 0.85, 1, true)
                GameTooltip:Show()
            end)
            node:SetScript("OnLeave", GameTooltip_Hide)
        else
            local info = data.info or {}
            local badge = SC.ContactBadgeMarkup and SC.ContactBadgeMarkup(data.name, false) or ""
            node.title:SetText(badge .. (SC.ShortName and SC.ShortName(data.name) or data.name))
            local cr, cg, cb
            if SC.GetContactNameColor then cr, cg, cb = SC.GetContactNameColor(data.name) end
            node.title:SetTextColor(cr or 0.88, cg or 0.92, cb or 1)
            local meta = tostring(data.class or "Unknown")
            if data.level then meta = meta .. " Â· Lv. " .. tostring(data.level) end
            if data.favorite then meta = meta .. " Â· â" end
            if data.pinned then meta = meta .. " Â· â" end
            node.meta:SetText(meta)
            local statusColor = NetworkMapColor(data.status)
            node.statusDot:SetColorTexture(statusColor[1], statusColor[2], statusColor[3], 1)
            node.statusDot:Show()
            node:SetScript("OnClick", function(self, mouseButton)
                if mouseButton == "RightButton" then
                    if SC.ShowContactMenu then SC.ShowContactMenu(data.name, self) end
                    return
                end
                listFrame.networkSelectedName = data.name
                listFrame.networkSelectionLabel:SetText("Selected: " .. tostring(SC.ShortName(data.name)))
                listFrame.networkOpenProfileButton:Enable()
                listFrame.networkWhisperButton:Enable()
                for _, other in ipairs(listFrame.networkNodePool or {}) do
                    if other.kind == "contact" and other.data then
                        if other.data.key == data.key then other:SetBackdropBorderColor(1, 0.82, 0.28, 1)
                        else
                            local original = other.networkAccent or theme.neutral
                            other:SetBackdropBorderColor(original[1], original[2], original[3], 0.84)
                        end
                    end
                end
            end)
            node:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(data.name, 1, 1, 1)
                GameTooltip:AddLine(tostring(data.class or "Unknown") .. (data.level and (" Â· Level " .. tostring(data.level)) or ""), 0.75, 0.85, 1)
                GameTooltip:AddLine("Status: " .. tostring(data.status or "UNKNOWN"), statusColor[1], statusColor[2], statusColor[3])
                local rels = {}
                for _, relation in ipairs(NETWORK_MAP_RELATIONS) do if data.relations[relation.key] then rels[#rels + 1] = relation.label end end
                if #rels > 0 then GameTooltip:AddLine("Connections: " .. table.concat(rels, ", "), 0.75, 0.85, 1, true) end
                if #data.personalGroups > 0 then GameTooltip:AddLine("My Groups: " .. table.concat(data.personalGroups, ", "), 0.75, 0.85, 1, true) end
                GameTooltip:AddLine("Left-click to select. Right-click for contact actions.", 0.65, 0.75, 0.85, true)
                GameTooltip:Show()
            end)
            node:SetScript("OnLeave", GameTooltip_Hide)
        end
        AnimateNetworkNode(node, nodeIndex, hub)
        return node
    end

    local rootAccent = { theme.root[1], theme.root[2], theme.root[3] }
    createNode("root", {}, rootX, rootY, rootWidth, rootHeight, rootAccent)
    for _, relation in ipairs(hubs) do
        local pos = hubPositions[relation.key]
        if pos then createNode("hub", relation, pos.x, pos.y, pos.width, pos.height, relation.color) end
    end
    for _, person in ipairs(contacts) do
        local pos = positions[person.key]
        if pos then
            local accent = { theme.neutral[1], theme.neutral[2], theme.neutral[3] }
            local cr, cg, cb = SC.GetContactNameColor and SC.GetContactNameColor(person.name)
            if cr and cg and cb then accent = { cr, cg, cb }
            else
                for _, relation in ipairs(hubs) do if person.relations[relation.key] then accent = relation.color; break end end
            end
            createNode("contact", person, pos.x, pos.y, pos.width, pos.height, accent)
        end
    end

    for i = nodeIndex + 1, #(listFrame.networkNodePool or {}) do listFrame.networkNodePool[i]:Hide() end
    for i = lineIndex + 1, #(listFrame.networkLinePool or {}) do listFrame.networkLinePool[i]:Hide() end
    for i = lineIndex + 1, #(listFrame.networkGlowLinePool or {}) do listFrame.networkGlowLinePool[i]:Hide() end
    for i = lineIndex + 1, #(listFrame.networkCoreLinePool or {}) do listFrame.networkCoreLinePool[i]:Hide() end
    for i = pulseIndex + 1, #(listFrame.networkPulsePool or {}) do
        local pulse = listFrame.networkPulsePool[i]
        if pulse._networkAnim then pcall(pulse._networkAnim.Stop, pulse._networkAnim) end
        pulse:Hide()
    end
    listFrame.networkScroll:SetHorizontalScroll(0)
    listFrame.networkScroll:SetVerticalScroll(0)
    listFrame.networkSelectedName = nil
    listFrame.networkSelectionLabel:SetText("Select a contact node")
    listFrame.networkOpenProfileButton:Disable()
    listFrame.networkWhisperButton:Disable()

    local note = tostring(#contacts) .. " visible contact(s) Â· " .. tostring(#hubs) .. " relationship type(s) Â· " .. filterLabel .. " Â· " .. tostring(math.floor(zoom * 100 + 0.5)) .. "% Â· " .. string.upper(hub.networkMapTheme or "midnight")
    if omitted > 0 then note = note .. " Â· " .. tostring(omitted) .. " more not shown" end
    if layout == "radial" and totalContacts > 16 then note = note .. " Â· Radial layout is capped at 16 to prevent overlap" end
    if #contacts == 0 then
        if not listFrame.networkEmptyText then
            listFrame.networkEmptyText = canvas:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            listFrame.networkEmptyText:SetPoint("CENTER", canvas, "CENTER", 0, 0)
            listFrame.networkEmptyText:SetWidth(520)
            listFrame.networkEmptyText:SetJustifyH("CENTER")
            listFrame.networkEmptyText:SetWordWrap(true)
        end
        listFrame.networkEmptyText:SetText("No relationship data is available for this filter yet. SmartChat only displays connections supplied by the game or already recorded locally; it does not invent links.")
        listFrame.networkEmptyText:Show()
    elseif listFrame.networkEmptyText then
        listFrame.networkEmptyText:Hide()
    end
    listFrame.networkSelectionLabel:SetText(note)
    listFrame.networkMapDirty = false
    listFrame.networkSnapshotTime = time()
end

local function RenderNetworkMapPage()
    if not listFrame then return end
    EnsureNetworkMapUI()
    local hub = EnsureHubPreferences()
    listFrame.header:SetText("NETWORK MAP")
    listFrame.status:SetText(hub.networkMapEnabled and "ENABLED Â· ON-DEMAND SNAPSHOT" or "OPTIONAL Â· DISABLED BY DEFAULT")
    listFrame.status:SetTextColor(hub.networkMapEnabled and 0.35 or 0.78, hub.networkMapEnabled and 0.82 or 0.70, hub.networkMapEnabled and 0.58 or 0.38)
    listFrame.details:SetText("Explore an animated relationship constellation with luminous node cards, layered glowing links, flowing connection pulses and ambient star effects. The map is created only after you enable it or request a refresh. Drag empty canvas to pan; use the wheel to scroll and Shift+wheel for horizontal movement. No separate tracking, internet access or background polling is started.")
    listFrame.transcriptScroll:Hide()
    listFrame.contentLine:Hide()
    listFrame.networkEnableButton:SetShown(not hub.networkMapEnabled)
    local keys = { "networkLayoutButton", "networkFilterButton", "networkAnimationButton", "networkMotionButton", "networkLimitButton", "networkRefreshButton", "networkDisableButton", "networkThemeButton", "networkZoomButton", "networkFitButton", "networkSelectionLabel", "networkOpenProfileButton", "networkWhisperButton" }
    for _, key in ipairs(keys) do if listFrame[key] then listFrame[key]:SetShown(hub.networkMapEnabled) end end
    if hub.networkMapEnabled then
        EnsureNetworkMapCanvas()
        local layoutLabels = { node = "Layout: Node", radial = "Layout: Radial", mind = "Layout: Mind Map" }
        listFrame.networkLayoutButton:SetText(layoutLabels[hub.networkMapLayout] or layoutLabels.node)
        local filterLabel = "All"
        for _, item in ipairs(NETWORK_MAP_FILTERS) do if item.key == hub.networkMapFilter then filterLabel = item.label break end end
        listFrame.networkFilterButton:SetText("Filter: " .. filterLabel)
        listFrame.networkAnimationButton:SetText("Animation: " .. (hub.networkMapAnimations and "On" or "Off"))
        listFrame.networkMotionButton:SetText("Reduce Motion: " .. (hub.networkMapReduceMotion and "On" or "Off"))
        listFrame.networkLimitButton:SetText("Nodes: " .. tostring(hub.networkMapMaxNodes or 24))
        local themeNames = { midnight = "Midnight", neon = "Neon", minimal = "Minimal" }
        listFrame.networkThemeButton:SetText("Theme: " .. (themeNames[hub.networkMapTheme] or "Midnight"))
        listFrame.networkZoomButton:SetText("Zoom: " .. tostring(hub.networkMapZoom or 100) .. "%")
        listFrame.networkScroll:SetNetworkMapEnabled(true)
        listFrame.networkScroll:Show()
        if listFrame.networkMapDirty or not listFrame.networkMapBuilt then
            RenderNetworkMapSnapshot()
            listFrame.networkMapBuilt = true
        end
    else
        StopNetworkMapAnimations()
        if listFrame.networkScroll then listFrame.networkScroll:SetNetworkMapEnabled(false); listFrame.networkScroll:Hide() end
        SetHubTranscript("|cff66ccffOPTIONAL NETWORK MAP|r\n\nThe visual map is disabled by default. Enable it only when you want to explore a richly animated relationship constellation built from your existing Friends, Guild, Battle.net, Whisper, current Group, My Groups and recorded group-partner connections.\n\nEnabling the map does not start tracking. It reads data already available in other Social Hub sections and builds a visual snapshot on demand. Disable it at any time; your contacts, Journal and other saved data remain untouched.\n\n|cff888888Choose Enable Network Map to create the first snapshot and start its visual effects. No map canvas, contact nodes, particles or animations are created before you enable it; no separate window will open.|r")
        listFrame.transcriptScroll:Show()
        listFrame.networkEnableButton:Show()
    end
end


RefreshInbox = function()
    if not listFrame or not listFrame:IsShown() then return end
    local hubPrefs = EnsureHubPreferences()
    local category = listFrame.category or "all"
    if hubPrefs.categoryVisibility[category] == false then category = "overview"; listFrame.category = category; listFrame.mode = "overview" end
    local isNetworkMapCategory = category == "networkMap"
    local canMultiSelect = category ~= "overview" and category ~= "insights" and category ~= "activity" and not isNetworkMapCategory
    if not canMultiSelect and listFrame.selectionMode then
        listFrame.selectionMode = false
        wipe(listFrame.multiSelected or {})
    end
    local profileSection = listFrame.profileSection or "overview"
    if hubPrefs.profileVisibility[profileSection] == false then profileSection = "overview"; listFrame.profileSection = profileSection; listFrame.mode = "profile" end
    local isInsightsDashboard = category == "insights" and listFrame.mode == "insights"
    local isGuildManager = category == "guild" and listFrame.mode == "guild"
    if isNetworkMapCategory then
        if listFrame.left then listFrame.left:Hide() end
        if listFrame.searchBox then listFrame.searchBox:Hide() end
        for _, key in ipairs({ "filterButton", "sortButton", "newGroupButton", "groupFilterButton", "selectModeButton", "bulkActionsButton" }) do
            if listFrame[key] then listFrame[key]:Hide() end
        end
        if listFrame.activityTypeButton then listFrame.activityTypeButton:Hide() end
        if listFrame.activityPeriodButton then listFrame.activityPeriodButton:Hide() end
        if listFrame.sharedCompareButton then listFrame.sharedCompareButton:Hide() end
        if listFrame.favoriteButton then listFrame.favoriteButton:Hide() end
        if listFrame.pinButton then listFrame.pinButton:Hide() end
        if listFrame.quickNoteButton then listFrame.quickNoteButton:Hide() end
        if listFrame.journalButton then listFrame.journalButton:Hide() end
        if listFrame.deleteNoteButton then listFrame.deleteNoteButton:Hide() end
        if listFrame.openButton then listFrame.openButton:Hide() end
        if listFrame.contentLine then listFrame.contentLine:Hide() end
        for _, card in ipairs(listFrame.dashboardCards or {}) do card:Hide() end
        for _, button in pairs(listFrame.profileSectionButtons or {}) do button:Hide() end
        for _, button in pairs(listFrame.guildTabButtons or {}) do button:Hide() end
        if listFrame.guildRosterRefreshButton then listFrame.guildRosterRefreshButton:Hide() end
        for _, button in ipairs(listFrame.guildDrillButtons or {}) do button:Hide() end
        local contentTop = -84 - (math.max(1, listFrame.categoryRows or 1) - 1) * 25
        listFrame.right:ClearAllPoints()
        listFrame.right:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 10, contentTop)
        listFrame.right:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -10, 10)
        RenderNetworkMapPage()
        return
    else
        HideNetworkMapPage()
        if listFrame.details then listFrame.details:SetWidth(290) end
        if listFrame.left then listFrame.left:Show() end
        if listFrame.searchBox then listFrame.searchBox:Show() end
        if listFrame.filterButton then listFrame.filterButton:Show() end
        if listFrame.sortButton then listFrame.sortButton:Show() end
        if listFrame.newGroupButton then listFrame.newGroupButton:Show() end
        if listFrame.selectModeButton then listFrame.selectModeButton:SetShown(canMultiSelect) end
        if listFrame.bulkActionsButton then listFrame.bulkActionsButton:SetShown(canMultiSelect and listFrame.selectionMode) end
        if listFrame.favoriteButton then listFrame.favoriteButton:Show() end
        if listFrame.pinButton then listFrame.pinButton:Show() end
        if listFrame.quickNoteButton then listFrame.quickNoteButton:Show() end
        if listFrame.journalButton then listFrame.journalButton:Show() end
        if listFrame.deleteNoteButton then listFrame.deleteNoteButton:Show() end
        if listFrame.openButton then listFrame.openButton:Show() end
        if listFrame.transcriptScroll then listFrame.transcriptScroll:Show() end
        if listFrame.contentLine then listFrame.contentLine:Show() end
        listFrame.right:ClearAllPoints()
        listFrame.right:SetPoint("TOPLEFT", listFrame.left, "TOPRIGHT", 10, 0)
        listFrame.right:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -10, 10)
    end
    if not isGuildManager then
        if listFrame.guildRosterRefreshButton then listFrame.guildRosterRefreshButton:Hide() end
        for _, button in ipairs(listFrame.guildDrillButtons or {}) do button:Hide() end
        if listFrame.contentLine then
            listFrame.contentLine:ClearAllPoints()
            listFrame.contentLine:SetPoint("TOPLEFT", 4, -116)
            listFrame.contentLine:SetPoint("TOPRIGHT", -4, -116)
        end
        if listFrame.transcriptScroll then
            listFrame.transcriptScroll:ClearAllPoints()
            listFrame.transcriptScroll:SetPoint("TOPLEFT", 4, -125)
            listFrame.transcriptScroll:SetPoint("BOTTOMRIGHT", -22, 36)
        end
    end
    local journalView = category == "activity" or listFrame.mode == "journal" or profileSection == "history"
    local relationshipView = profileSection == "relationship"
    local networkView = profileSection == "network"
    local sharedView = profileSection == "shared"
    if listFrame.sharedCompareButton then listFrame.sharedCompareButton:Hide() end
    if listFrame.activityTypeButton then
        listFrame.activityTypeButton:SetShown(journalView and not relationshipView and not sharedView and not networkView and not isInsightsDashboard and not isGuildManager)
        listFrame.activityPeriodButton:SetShown((journalView or relationshipView or sharedView or networkView or isInsightsDashboard) and not isGuildManager)
        if relationshipView or networkView or isInsightsDashboard then
            listFrame.activityPeriodButton:ClearAllPoints()
            listFrame.activityPeriodButton:SetPoint("TOPLEFT", listFrame.right, "TOPLEFT", 4, -90)
        elseif sharedView then
            listFrame.sharedCompareButton:ClearAllPoints()
            listFrame.sharedCompareButton:SetPoint("TOPLEFT", listFrame.right, "TOPLEFT", 4, -90)
            listFrame.sharedCompareButton:Show()
            listFrame.activityPeriodButton:ClearAllPoints()
            listFrame.activityPeriodButton:SetPoint("LEFT", listFrame.sharedCompareButton, "RIGHT", 5, 0)
        else
            listFrame.sharedCompareButton:Hide()
            listFrame.activityPeriodButton:ClearAllPoints()
            listFrame.activityPeriodButton:SetPoint("LEFT", listFrame.activityTypeButton, "RIGHT", 5, 0)
        end
        local typeLabel, periodLabel = JournalFilterLabel()
        listFrame.activityTypeButton:SetText("Type: " .. typeLabel)
        listFrame.activityPeriodButton:SetText(periodLabel)
    end
    if category == "groups" and listFrame.selectedGroup and listFrame.selectedGroup ~= "All" then
        local groups = SC.db.social and SC.db.social.groups or {}
        if not groups[listFrame.selectedGroup] then listFrame.selectedGroup = "All" end
    end
    local names = CollectSocialContacts(category)
    listFrame.visibleNames = names
    local categoryLabel = "CONTACTS"
    for _, item in ipairs(OrderedSocialCategories()) do
        if item.key == category then categoryLabel = string.upper(item.label) .. "  Â·  " .. #names end
    end
    if category == "groups" and listFrame.selectedGroup and listFrame.selectedGroup ~= "All" then
        categoryLabel = categoryLabel .. "  Â·  " .. listFrame.selectedGroup
    end
    local currentFilter = CONTACT_FILTER_BY_KEY[GetContactFilterMode(SC.db.social or {})]
    if currentFilter and currentFilter.key ~= "all" then categoryLabel = categoryLabel .. "  Â·  " .. currentFilter.label end
    listFrame.listTitle:SetText(categoryLabel)
    if listFrame.groupFilterButton then listFrame.groupFilterButton:SetShown(category == "groups") end

    if listFrame.stats then
        local friends, online, guild, unread, whispers, ignored = 0, 0, 0, 0, 0, 0
        if SC.GetSocialStats then friends, online, guild, unread, whispers, ignored = SC.GetSocialStats() end
        local bnetCount = tonumber(SC.bnetAccountCount) or 0
        listFrame.stats:SetText(string.format("F %d (%d online)  Â·  G %d  Â·  BNet %d  Â·  W %d  Â·  Unread %d  Â·  Ignored %d", friends or 0, online or 0, guild or 0, bnetCount, whispers or 0, unread or 0, ignored or 0))
    end
    if listFrame.sortButton then
        local sort = (SC.db.social and SC.db.social.sortMode) or "status"
        local labels = { status = "Sort: Status", name = "Sort: Name", recent = "Sort: Recent", unread = "Sort: Unread", rank = "Sort: Guild Rank", level = "Sort: Level", class = "Sort: Class", achievement = "Sort: Achievements" }
        listFrame.sortButton:SetText(labels[sort] or labels.status)
    end
    if listFrame.filterButton then
        local social = SC.db.social or {}
        local filterMode = GetContactFilterMode(social)
        local item = CONTACT_FILTER_BY_KEY[filterMode] or CONTACT_FILTER_BY_KEY.all
        listFrame.filterButton:SetText("Filter: " .. item.label)
    end
    local selectedCount = CountSelectedContacts()
    if listFrame.selectModeButton then
        listFrame.selectModeButton:SetShown(canMultiSelect)
        listFrame.selectModeButton:SetText(listFrame.selectionMode and ("Select (" .. selectedCount .. ")") or "Select")
    end
    if listFrame.bulkActionsButton then
        listFrame.bulkActionsButton:SetShown(canMultiSelect and listFrame.selectionMode)
        listFrame.bulkActionsButton:SetText("Actions (" .. selectedCount .. ")")
        if selectedCount > 0 then listFrame.bulkActionsButton:Enable() else listFrame.bulkActionsButton:Disable() end
    end
    if listFrame.groupFilterButton then
        local selectedGroup = listFrame.selectedGroup or "All"
        local memberCount = 0
        if selectedGroup ~= "All" then
            local group = SC.db.social and SC.db.social.groups and SC.db.social.groups[selectedGroup]
            if type(group) == "table" then for _, name in pairs(group) do if name then memberCount = memberCount + 1 end end end
            local shortName = #selectedGroup > 14 and (selectedGroup:sub(1, 12) .. "â¦") or selectedGroup
            listFrame.groupFilterButton:SetText(string.format("Group: %s (%d)", shortName, memberCount))
        else
            listFrame.groupFilterButton:SetText("Group: All")
        end
    end

    local isDashboard = category == "overview" and listFrame.mode == "overview"
    if listFrame.dashboardCards then
        local stats = SC.GetSocialOverviewStats and SC.GetSocialOverviewStats() or {}
        local groupCount = tonumber(stats.groups) or 0
        local cardValues = {
            { value = string.format("%d / %d", tonumber(stats.onlineFriends) or 0, tonumber(stats.friends) or 0), hint = "online / total" },
            { value = tostring(tonumber(stats.guildMembers) or 0), hint = "current roster" },
            { value = tostring(tonumber(stats.unreadWhispers) or 0), hint = string.format("unread Â· %d chats", tonumber(stats.whisperContacts) or 0) },
            { value = tostring(tonumber(stats.favorites) or 0), hint = string.format("pinned Â· %d", tonumber(stats.pinned) or 0) },
            { value = tostring(groupCount), hint = string.format("groups Â· %d member links", tonumber(stats.groupMemberLinks) or 0) },
        }
        for i, card in ipairs(listFrame.dashboardCards) do
            card.value:SetText(cardValues[i].value)
            card.hint:SetText(cardValues[i].hint)
            card:SetShown(isDashboard)
        end
        if listFrame.details then listFrame.details:SetShown(not isDashboard) end
    end

    local selectedStillVisible = false
    if listFrame.selectedName then
        for _, name in ipairs(names) do
            if SC.NameKey(name) == SC.NameKey(listFrame.selectedName) then selectedStillVisible = true; break end
        end
    end
    if not selectedStillVisible then
        if (category == "insights" and listFrame.mode == "insights") or isGuildManager then
            listFrame.selectedName = nil
        else
            listFrame.selectedName = names[1]
        end
    end

    local showProfileSections = listFrame.selectedName ~= nil
        and not (category == "overview" and listFrame.mode == "overview")
        and not (category == "insights" and listFrame.mode == "insights")
        and not (category == "activity" and listFrame.mode ~= "journal")
    if listFrame.profileSectionButtons then
        ApplyProfileSectionLayout()
        for _, item in ipairs(OrderedProfileSections()) do
            local button = listFrame.profileSectionButtons[item.key]
            if button then
                button:SetShown(showProfileSections and (hubPrefs.profileVisibility[item.key] ~= false or item.key == "overview"))
                local active = profileSection == item.key
                local fs = button:GetFontString()
                if fs then fs:SetTextColor(active and 1 or 0.82, active and 0.82 or 0.82, active and 0.18 or 0.82) end
            end
        end
    end
    if listFrame.guildTabButtons then
        for _, item in ipairs(GUILD_MANAGER_SECTIONS) do
            local button = listFrame.guildTabButtons[item.key]
            if button then
                button:SetShown(category == "guild" and isGuildManager)
                local active = (listFrame.guildSection or "overview") == item.key
                local fs = button:GetFontString()
                if fs then fs:SetTextColor(active and 1 or 0.82, active and 0.82 or 0.82, active and 0.18 or 0.82) end
            end
        end
    end
    if listFrame.guildBackButton then listFrame.guildBackButton:SetShown(category == "guild" and not isGuildManager and listFrame.mode == "profile") end
    if listFrame.guildDrillResetButton then listFrame.guildDrillResetButton:Hide() end

    local child = listFrame.listChild
    for i, name in ipairs(names) do
        local row = listFrame.rows[i]
        if not row then
            row = CreateSocialRow(child)
            listFrame.rows[i] = row
        end
        local info = SC.GetContactInfo and SC.GetContactInfo(name) or { status = "UNKNOWN" }
        row.name = name
        local marker = ""
        if hubPrefs.showFavoritePinMarkers then
            if SC.IsContactPinned and SC.IsContactPinned(name) then marker = "|cffffd166â|r "
            elseif SC.IsFavorite and SC.IsFavorite(name) then marker = "|cffffd166â|r " end
        end
        local displayName = hubPrefs.showRelationshipBadges and ContactLabel(name) or SC.ShortName(name)
        if not hubPrefs.showRelationshipBadges then
            local cr, cg, cb = SC.GetContactNameColor and SC.GetContactNameColor(name)
            if cr then displayName = string.format("|cff%02x%02x%02x%s|r", math.floor(cr * 255 + 0.5), math.floor(cg * 255 + 0.5), math.floor(cb * 255 + 0.5), displayName) end
        end
        row.nameText:SetText(marker .. displayName)
        local class = SC.ContactClassName and SC.ContactClassName(info) or info.class or "Unknown class"
        local level = info.level and ("Lv. " .. info.level) or "Lv. ?"
        local groups = SC.GetContactGroups and SC.GetContactGroups(name) or {}
        local groupText = (hubPrefs.showContactGroups and #groups > 0) and (" Â· " .. table.concat(groups, ", ")) or ""
        local unread = SC.whisperUnread and (SC.whisperUnread[SC.NameKey(name)] or 0) or 0
        local unreadText = unread > 0 and (" Â· " .. unread .. " unread") or ""
        local metaParts = {}
        if info.accountOnly then
            metaParts[#metaParts + 1] = info.gameLabel or "Battle.net account"
            metaParts[#metaParts + 1] = info.status or "UNKNOWN"
        elseif category == "notes" then
            local note = SC.GetContactNote and SC.GetContactNote(name) or { tags = {}, text = "" }
            if note.tags and #note.tags > 0 then
                metaParts[#metaParts + 1] = table.concat(note.tags, " Â· ")
            elseif note.text and note.text ~= "" then
                metaParts[#metaParts + 1] = note.text:gsub("%s+", " "):sub(1, 58)
            else
                metaParts[#metaParts + 1] = "Personal note"
            end
        else
            if category == "guild" then
                if info.rank and info.rank ~= "" then metaParts[#metaParts + 1] = info.rank end
                local guildRow = GetGuildManagerData().byKey[SC.NameKey(name)]
                if guildRow and guildRow.achievementPoints ~= nil then metaParts[#metaParts + 1] = "AP " .. tostring(guildRow.achievementPoints) end
                if guildRow and guildRow.status == "OFFLINE" and guildRow.lastOnlineHours ~= nil then
                    local hours = guildRow.lastOnlineHours
                    local age = hours < 24 and (tostring(math.floor(hours + 0.5)) .. "h") or (tostring(math.floor(hours / 24 + 0.5)) .. "d")
                    metaParts[#metaParts + 1] = "Last online " .. age
                end
            end
            if category == "bnet" then
                if info.bnetAccountName and info.bnetAccountName ~= "" then metaParts[#metaParts + 1] = "Account: " .. info.bnetAccountName end
                if info.realm and info.realm ~= "" then metaParts[#metaParts + 1] = "Realm: " .. info.realm end
                if (tonumber(info.bnetGameAccountCount) or 0) > 1 then metaParts[#metaParts + 1] = tostring(info.bnetGameAccountCount) .. " reported game accounts" end
            end
            if hubPrefs.showClassLevel then
                metaParts[#metaParts + 1] = class
                metaParts[#metaParts + 1] = level
            end
            if category == "group" and info.role and info.role ~= "NONE" then metaParts[#metaParts + 1] = info.role end
            if category == "guild" and info.zone and info.zone ~= "" then metaParts[#metaParts + 1] = info.zone end
            if groupText ~= "" then metaParts[#metaParts + 1] = groupText:gsub("^ Â· ", "") end
            if unreadText ~= "" then metaParts[#metaParts + 1] = unreadText:gsub("^ Â· ", "") end
        end
        local meta = table.concat(metaParts, " Â· ")
        row.metaText:SetText(meta)
        row.metaText:SetShown(meta ~= "")
        row.selected:SetShown(listFrame.selectedName and SC.NameKey(listFrame.selectedName) == SC.NameKey(name))
        local r, g, b = StatusColor(info.status)
        row.dot:SetColorTexture(r, g, b, 1)
        row.dot:SetShown(hubPrefs.showStatusDot)
        local multiMode = listFrame.selectionMode and true or false
        local isMultiSelected = listFrame.multiSelected and listFrame.multiSelected[SC.NameKey(name)] ~= nil
        row.multiMark:SetText(isMultiSelected and "|cff66dd99[x]|r" or "|cff888888[ ]|r")
        row.multiMark:SetShown(multiMode)
        row.nameText:ClearAllPoints()
        row.nameText:SetPoint("TOPLEFT", hubPrefs.showStatusDot and 20 or 7, -3)
        row.nameText:SetPoint("TOPRIGHT", multiMode and -25 or -3, -3)
        row.metaText:ClearAllPoints()
        row.metaText:SetPoint("TOPLEFT", hubPrefs.showStatusDot and 20 or 7, -18)
        row.metaText:SetPoint("TOPRIGHT", multiMode and -25 or -3, -18)
        local rowHeight = hubPrefs.rowStyle == "compact" and 29 or 36
        local rowStep = hubPrefs.rowStyle == "compact" and 30 or 37
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * rowStep)
        row:SetPoint("TOPRIGHT", -2, -2 - (i - 1) * rowStep)
        row:Show()
    end
    for i = #names + 1, #listFrame.rows do listFrame.rows[i]:Hide() end
    local rowStep = hubPrefs.rowStyle == "compact" and 30 or 37
    child:SetHeight(math.max(1, #names * rowStep + 4))
    listFrame.scroll:SetVerticalScroll(0)

    for _, item in ipairs(OrderedSocialCategories()) do
        local button = listFrame.categoryButtons[item.key]
        if button then
            local active = item.key == category
            button:GetFontString():SetTextColor(active and 1 or 0.82, active and 0.82 or 0.82, active and 0.18 or 0.82)
        end
    end

    local selected = listFrame.selectedName
    if isGuildManager then
        for _, actionButton in ipairs({ listFrame.favoriteButton, listFrame.pinButton, listFrame.quickNoteButton, listFrame.journalButton, listFrame.deleteNoteButton, listFrame.openButton }) do
            if actionButton then actionButton:Hide() end
        end
    elseif selected and not isInsightsDashboard then
        for _, actionButton in ipairs({ listFrame.favoriteButton, listFrame.pinButton, listFrame.quickNoteButton, listFrame.journalButton, listFrame.deleteNoteButton, listFrame.openButton }) do
            if actionButton then actionButton:Show() end
        end
        local info = SC.GetContactInfo and SC.GetContactInfo(selected) or { status = "UNKNOWN" }
        listFrame.header:SetText(ContactLabel(selected))
        local statusText = info.status or "UNKNOWN"
        local r, g, b = StatusColor(statusText)
        listFrame.status:SetText(statusText)
        listFrame.status:SetTextColor(r, g, b)
        local details = {}
        local displayClass = SC.ContactClassName and SC.ContactClassName(info) or info.class
        if not info.accountOnly and displayClass and displayClass ~= "Unknown" then details[#details + 1] = displayClass end
        if info.level then details[#details + 1] = "Level " .. info.level end
        if info.zone and info.zone ~= "" then details[#details + 1] = info.zone end
        if info.rank and info.rank ~= "" then details[#details + 1] = "Guild rank: " .. info.rank end
        if category == "guild" then
            local guildRow = GetGuildManagerData().byKey[SC.NameKey(selected)]
            if guildRow and guildRow.achievementPoints ~= nil then details[#details + 1] = "Achievement Points: " .. tostring(guildRow.achievementPoints) end
            if guildRow and guildRow.achievementRank ~= nil and guildRow.achievementRank > 0 then details[#details + 1] = "Guild Achievement Rank: " .. tostring(guildRow.achievementRank) end
        end
        local rel = SC.Relation and SC.Relation(selected) or ""
        if rel ~= "" then details[#details + 1] = "Relationships: " .. rel:gsub("F", "Friend "):gsub("B", "Battle.net "):gsub("G", "Guild "):gsub("P", "Group ") end
        local groups = SC.GetContactGroups and SC.GetContactGroups(selected) or {}
        if #groups > 0 then details[#details + 1] = "Contact groups: " .. table.concat(groups, ", ") end
        local note = SC.GetContactNote and SC.GetContactNote(selected) or { tags = {} }
        if note.tags and #note.tags > 0 then details[#details + 1] = "Tags: " .. table.concat(note.tags, ", ") end
        if info.battleTag and info.battleTag ~= "" then details[#details + 1] = "BattleTag: " .. info.battleTag end
        if info.bnetAccountName and info.bnetAccountName ~= "" then details[#details + 1] = "BNet account: " .. info.bnetAccountName end
        if (tonumber(info.bnetGameAccountCount) or 0) > 0 then details[#details + 1] = "Reported game accounts: " .. tostring(info.bnetGameAccountCount) end
        if (tonumber(info.bnetCharacterCount) or 0) > 1 then details[#details + 1] = "Reported WoW characters: " .. tostring(info.bnetCharacterCount) end
        if info.character and info.character ~= selected then details[#details + 1] = "Playing: " .. info.character end
        if info.role and info.role ~= "NONE" then details[#details + 1] = "Group role: " .. info.role end
        if info.accountOnly then
            details[#details + 1] = "Battle.net account (no active WoW character available)"
            if info.gameLabel and info.gameLabel ~= "" then details[#details + 1] = "Game: " .. info.gameLabel end
            if info.lastOnlineTime and info.lastOnlineTime > 0 then details[#details + 1] = "Last online: " .. date("%Y-%m-%d %H:%M", info.lastOnlineTime) end
        end
        listFrame.details:SetText(#details > 0 and table.concat(details, "  |  ") or "No additional player information available")

        if category == "overview" and listFrame.mode == "overview" then
            listFrame.header:SetText("Social Overview")
            listFrame.status:SetText("YOUR SOCIAL SPACE")
            listFrame.status:SetTextColor(0.4, 0.8, 1)
            listFrame.details:SetText("Your contacts, groups and local activity in one place. Select a summary card above for quick access.")
            local events = SC.GetRecentJournalEvents and SC.GetRecentJournalEvents(12) or {}
            local lines = { "|cff66ccffSMARTCHAT SOCIAL DASHBOARD|r", "", "Choose a summary card above or a category tab to jump straight to the people and tools you need.", "Right-click any contact for quick actions. Use Groups to organize players into your own lists." }
            if SC.db.journal and SC.db.journal.enabled then
                lines[#lines + 1] = ""
                lines[#lines + 1] = "|cff66ccffRECENT ACTIVITY|r"
                if #events == 0 then
                    lines[#lines + 1] = "|cff888888No local activity recorded yet.|r"
                else
                    for i = 1, math.min(#events, 8) do
                        local event = events[i]
                        local namesText = table.concat(event.names or {}, ", ")
                        lines[#lines + 1] = "|cff888888" .. JournalEventTimeLabel(event, "%m-%d %H:%M") .. "|r  |cffffffff" .. JournalEventTitleLabel(event, "Activity") .. "|r"
                        if namesText ~= "" then lines[#lines + 1] = "    |cff66ccff" .. namesText .. "|r" end
                    end
                end
            else
                lines[#lines + 1] = ""
                lines[#lines + 1] = "|cffffcc66Player Journal is currently off.|r Enable it in Settings > Social & Journal to build a private local history."
            end
            SetHubTranscript(table.concat(lines, "\n\n"))
            listFrame.journalButton:SetText("View Activity")
        elseif category == "activity" and listFrame.mode ~= "journal" then
            listFrame.header:SetText("Recent Social Activity")
            listFrame.status:SetText("LOCAL HISTORY")
            listFrame.status:SetTextColor(0.4, 0.8, 1)
            listFrame.details:SetText("Recent events recorded on this character. Select a player and choose Player History for their individual timeline.")
            local journal = SC.db.journal or {}
            local filterType, filterDays = journal.timelineType or "all", tonumber(journal.timelineDays) or 0
            local events = SC.GetRecentJournalEvents and SC.GetRecentJournalEvents(40, filterType, filterDays) or {}
            local typeLabel, periodLabel = JournalFilterLabel()
            local lines = { "|cff66ccffRECENT ACTIVITY Â· LOCAL|r", "|cff888888Filter: " .. typeLabel .. " Â· " .. periodLabel .. "|r" }
            if not (SC.db.journal and SC.db.journal.enabled) then
                lines[#lines + 1] = "|cffffcc66Automatic tracking is disabled.|r Enable it in Settings > Social & Journal."
            end
            if #events == 0 then
                lines[#lines + 1] = "|cff888888No social activity has been recorded yet.|r"
            else
                for i = 1, #events do
                    local event = events[i]
                    local namesText = table.concat(event.names or {}, ", ")
                    lines[#lines + 1] = "|cff888888" .. JournalEventTimeLabel(event, "%Y-%m-%d %H:%M") .. "|r  |cffffffff" .. JournalEventTitleLabel(event, "Activity") .. "|r"
                    if namesText ~= "" then lines[#lines + 1] = "    |cff66ccff" .. namesText .. "|r" end
                    if event.detail and event.detail ~= "" then lines[#lines + 1] = "    |cffaaaaaa" .. tostring(event.detail) .. "|r" end
                    if event.type == "group" and event.sessionKind then
                        local extra = event.sessionKind
                        if tonumber(event.groupSize) and event.groupSize > 0 then extra = extra .. " Â· Group size " .. event.groupSize end
                        if event.difficultyName and event.difficultyName ~= "" then extra = extra .. " Â· " .. event.difficultyName end
                        lines[#lines + 1] = "    |cff66ccff" .. extra .. "|r"
                    end
                end
            end
            SetHubTranscript(table.concat(lines, "\n\n"))
            listFrame.journalButton:SetText("Player History")
        elseif profileSection == "notes" then
            listFrame.details:SetText("Private notes and quick tags saved locally for " .. tostring(SC.ShortName and SC.ShortName(selected) or selected) .. ".")
            local note = SC.GetContactNote and SC.GetContactNote(selected) or { tags = {}, text = "" }
            local lines = { "|cff66ccffPERSONAL NOTES|r", "" }
            if note.tags and #note.tags > 0 then
                lines[#lines + 1] = "|cff66ccffQUICK TAGS|r"
                lines[#lines + 1] = table.concat(note.tags, "  Â·  ")
                lines[#lines + 1] = ""
            else
                lines[#lines + 1] = "|cff888888No quick tags saved for this player yet.|r"
                lines[#lines + 1] = ""
            end
            lines[#lines + 1] = "|cff66ccffPERSONAL NOTE|r"
            lines[#lines + 1] = (note.text and note.text ~= "") and note.text or "|cff888888No personal note. You can add one with Quick Note.|r"
            if note.updated and note.updated > 0 then lines[#lines + 1] = ""; lines[#lines + 1] = "|cff888888Last updated: " .. date("%Y-%m-%d %H:%M", note.updated) .. "|r" end
            SetHubTranscript(table.concat(lines, "\n\n"))
            listFrame.journalButton:SetText("View History")
        elseif profileSection == "relationship" then
            local summary = SC.GetJournalPlayerSummary and SC.GetJournalPlayerSummary(selected) or {}
            local groups = SC.GetContactGroups and SC.GetContactGroups(selected) or {}
            local relation = SC.Relation and SC.Relation(selected) or ""
            local journal = SC.db.journal or {}
            local days = tonumber(journal.timelineDays) or 0
            local events = SC.GetJournalEventsFor and SC.GetJournalEventsFor(selected, 30, "social", days) or {}
            listFrame.details:SetText("Current relationship signals and recorded changes. History only includes events collected while Player Journal tracking was enabled.")
            local lines = { "|cff66ccffRELATIONSHIP OVERVIEW|r", "" }
            local relationNames = {}
            if relation:find("F", 1, true) then relationNames[#relationNames + 1] = "Friend" end
            if relation:find("B", 1, true) then relationNames[#relationNames + 1] = "Battle.net" end
            if relation:find("G", 1, true) then relationNames[#relationNames + 1] = "Guild" end
            if relation:find("P", 1, true) then relationNames[#relationNames + 1] = "Party / Raid" end
            lines[#lines + 1] = "Current in-game relationships: " .. (#relationNames > 0 and table.concat(relationNames, ", ") or "No current relationship detected")
            lines[#lines + 1] = "Favorites: " .. ((SC.IsFavorite and SC.IsFavorite(selected)) and "Yes" or "No") .. "  Â·  Pinned: " .. ((SC.IsContactPinned and SC.IsContactPinned(selected)) and "Yes" or "No")
            lines[#lines + 1] = "Personal groups: " .. (#groups > 0 and table.concat(groups, ", ") or "None")
            if summary.firstFriendAdded then lines[#lines + 1] = "First recorded Friend add: " .. date("%Y-%m-%d", summary.firstFriendAdded) end
            if summary.firstGuildJoined then lines[#lines + 1] = "First recorded Guild join: " .. date("%Y-%m-%d", summary.firstGuildJoined) end
            lines[#lines + 1] = ""
            lines[#lines + 1] = "|cff66ccffMOST FREQUENT GROUP PARTNERS|r"
            if summary.groupPartners and #summary.groupPartners > 0 then
                for i, partner in ipairs(summary.groupPartners) do
                    lines[#lines + 1] = string.format("%d. %s  Â·  %d recorded group sessions together", i, tostring(partner.name), tonumber(partner.sessions) or 0)
                end
            else
                lines[#lines + 1] = "|cff888888No shared group sessions recorded yet.|r"
            end
            lines[#lines + 1] = ""
            lines[#lines + 1] = "|cff66ccffRELATIONSHIP HISTORY|r"
            if #events == 0 then
                lines[#lines + 1] = "|cff888888No relationship changes recorded for this player in the selected period.|r"
            else
                for i = 1, math.min(#events, 18) do
                    local event = events[i]
                    lines[#lines + 1] = "|cff888888" .. JournalEventTimeLabel(event, "%Y-%m-%d %H:%M") .. "|r  |cffffffff" .. JournalEventTitleLabel(event, "Relationship event") .. "|r"
                    if event.detail and event.detail ~= "" then lines[#lines + 1] = "    |cffaaaaaa" .. tostring(event.detail) .. "|r" end
                end
            end
            SetHubTranscript(table.concat(lines, "\n\n"))
            listFrame.journalButton:SetText("View History")
        elseif networkView then
            local journal = SC.db.journal or {}
            local days = tonumber(journal.timelineDays) or 0
            local network = SC.GetPlayerRelationshipNetwork and SC.GetPlayerRelationshipNetwork(selected, days) or {}
            listFrame.details:SetText("Known connections built from current Guild data, your private contact groups and recorded shared group sessions. The game does not reveal another player's Friend List.")
            local period = days > 0 and (tostring(days) .. " days") or "All recorded history"
            local lines = { "|cff66ccffRELATIONSHIP NETWORK|r", "|cff888888" .. period .. " Â· Evidence-based connections only|r", "" }
            if network.currentGuild then
                lines[#lines + 1] = "|cff66ccffCURRENT GUILD CONNECTIONS|r  " .. tostring(network.currentGuild)
                lines[#lines + 1] = "Known current Guild roster members: " .. tostring(#(network.guildmates or {}))
                for i = 1, math.min(12, #(network.guildmates or {})) do
                    local member = network.guildmates[i]
                    local meta = {}
                    if member.rank ~= "" then meta[#meta + 1] = member.rank end
                    if member.class ~= "" then meta[#meta + 1] = member.class end
                    if member.level then meta[#meta + 1] = "Lv. " .. member.level end
                    lines[#lines + 1] = "  " .. tostring(member.name) .. (#meta > 0 and ("  Â·  " .. table.concat(meta, " / ")) or "")
                end
                if #network.guildmates > 12 then lines[#lines + 1] = "  + " .. tostring(#network.guildmates - 12) .. " more Guild members" end
                lines[#lines + 1] = ""
            end
            lines[#lines + 1] = "|cff66ccffRECORDED GROUP CONNECTIONS|r"
            if #(network.groupPartners or {}) == 0 then
                lines[#lines + 1] = "|cff888888No shared group sessions are recorded for this period.|r"
            else
                for i = 1, math.min(12, #network.groupPartners) do
                    local partner = network.groupPartners[i]
                    lines[#lines + 1] = string.format("  %s  Â·  %d shared session(s)", tostring(partner.name), tonumber(partner.sessions) or 0)
                end
            end
            if #(network.personalGroups or {}) > 0 then
                lines[#lines + 1] = ""
                lines[#lines + 1] = "|cff66ccffYOUR PERSONAL GROUPS|r"
                for _, group in ipairs(network.personalGroups) do
                    lines[#lines + 1] = string.format("  %s  Â·  %d other member(s)", tostring(group.name), #(group.members or {}))
                    for i = 1, math.min(6, #(group.members or {})) do lines[#lines + 1] = "    " .. tostring(group.members[i]) end
                end
            end
            if #(network.battleNetCharacters or {}) > 0 then
                lines[#lines + 1] = ""
                lines[#lines + 1] = "|cff66ccffREPORTED CHARACTERS ON THE SAME BATTLE.NET ACCOUNT|r"
                for i = 1, math.min(8, #network.battleNetCharacters) do
                    local character = network.battleNetCharacters[i]
                    local label = tostring(character.name)
                    if character.realm and character.realm ~= "" then label = label .. " Â· " .. character.realm end
                    if character.class and character.class ~= "" then label = label .. " Â· " .. character.class end
                    if character.level then label = label .. " Â· Lv. " .. character.level end
                    lines[#lines + 1] = "  " .. label
                end
            end
            lines[#lines + 1] = ""
            lines[#lines + 1] = "|cff888888Mutual friends are not shown because the game does not expose other players' Friend Lists. Group co-presence does not prove dungeon completion or exact simultaneous presence.|r"
            SetHubTranscript(table.concat(lines, "\n\n"))
            listFrame.journalButton:SetText("View History")
        elseif sharedView then
            local summary = SC.GetJournalPlayerSummary and SC.GetJournalPlayerSummary(selected) or {}
            local partners = summary.allGroupPartners or summary.groupPartners or {}
            local compareName = listFrame.comparePartner
            local compareFound = false
            for _, partner in ipairs(partners) do
                if compareName and SC.NameKey(partner.name) == SC.NameKey(compareName) then compareFound = true break end
            end
            if not compareFound then
                listFrame.comparePartner = partners[1] and partners[1].name or nil
                compareName = listFrame.comparePartner
            end
            if listFrame.sharedCompareButton then
                listFrame.sharedCompareButton:SetText(compareName and ("Compare: " .. tostring(SC.ShortName(compareName))) or "Compare: None")
                if #partners > 0 then listFrame.sharedCompareButton:Enable() else listFrame.sharedCompareButton:Disable() end
            end
            local journal = SC.db.journal or {}
            local days = tonumber(journal.timelineDays) or 0
            listFrame.details:SetText("Recorded group sessions shared by two players. Attendance times are tracked per player and do not imply exact simultaneous overlap or dungeon completion.")
            local lines = { "|cff66ccffSHARED GROUP HISTORY|r", "", "Player: " .. tostring(SC.ShortName(selected)) }
            if not compareName then
                lines[#lines + 1] = "|cff888888No shared group partners are recorded for this player yet.|r"
                lines[#lines + 1] = "Enable Player Journal and record a group session with another known player to build this comparison."
            else
                lines[#lines + 1] = "Compared with: " .. tostring(SC.ShortName(compareName))
                local shared = SC.GetJournalSharedGroupSessions and SC.GetJournalSharedGroupSessions(selected, compareName, 40, days) or { sessions = {}, count = 0 }
                local firstMinutes = math.floor((tonumber(shared.firstSeconds) or 0) / 60)
                local secondMinutes = math.floor((tonumber(shared.secondSeconds) or 0) / 60)
                lines[#lines + 1] = string.format("Recorded shared sessions: %d  Â·  %s: %d min  Â·  %s: %d min", shared.count or 0, SC.ShortName(selected), firstMinutes, SC.ShortName(compareName), secondMinutes)
                if (tonumber(shared.estimatedSessions) or 0) > 0 then
                    lines[#lines + 1] = "|cffffcc66" .. tostring(shared.estimatedSessions) .. " older session(s) use estimated attendance.|r"
                end
                lines[#lines + 1] = ""
                if #shared.sessions == 0 then
                    lines[#lines + 1] = "|cff888888No shared group sessions found in the selected time range.|r"
                else
                    for i, session in ipairs(shared.sessions) do
                        local leftMinutes = math.floor((tonumber(session.firstSeconds) or 0) / 60)
                        local rightMinutes = math.floor((tonumber(session.secondSeconds) or 0) / 60)
                        local dateText = date("%Y-%m-%d %H:%M", session.t or time())
                        lines[#lines + 1] = string.format("|cff888888%s|r  |cffffffff%s|r", dateText, tostring(session.title or "Group session"))
                        local meta = { tostring(session.sessionKind or "Group") }
                        if session.groupSize and session.groupSize > 0 then meta[#meta + 1] = "Group size " .. session.groupSize end
                        if session.difficultyName and session.difficultyName ~= "" then meta[#meta + 1] = session.difficultyName end
                        if session.locations and session.locations ~= "" then meta[#meta + 1] = session.locations:gsub(" | ", ", ") end
                        lines[#lines + 1] = "    |cff66ccff" .. table.concat(meta, " Â· ") .. "|r"
                        lines[#lines + 1] = string.format("    %s: %d min (%d visit%s)  Â·  %s: %d min (%d visit%s)",
                            SC.ShortName(selected), leftMinutes, session.firstIntervals or 1, (session.firstIntervals or 1) == 1 and "" or "s",
                            SC.ShortName(compareName), rightMinutes, session.secondIntervals or 1, (session.secondIntervals or 1) == 1 and "" or "s")
                        if session.estimated then lines[#lines + 1] = "    |cffffcc66Estimated attendance from older history|r" end
                        lines[#lines + 1] = ""
                    end
                end
            end
            SetHubTranscript(table.concat(lines, "\n\n"))
            listFrame.journalButton:SetText("View History")
        elseif listFrame.mode == "journal" or profileSection == "history" then
            listFrame.details:SetText("Local interaction history for " .. tostring(SC.ShortName and SC.ShortName(selected) or selected) .. ". Use the filters below to narrow the timeline.")
            local journal = SC.db.journal or {}
            local filterType, filterDays = journal.timelineType or "all", tonumber(journal.timelineDays) or 0
            local events = SC.GetJournalEventsFor and SC.GetJournalEventsFor(selected, 50, filterType, filterDays) or {}
            local summary = SC.GetJournalPlayerSummary and SC.GetJournalPlayerSummary(selected) or {}
            local groupMinutes = math.floor((tonumber(summary.groupDuration) or 0) / 60)
            local typeLabel, periodLabel = JournalFilterLabel()
            local lines = {
                "|cff66ccffPLAYER JOURNAL Â· LOCAL HISTORY|r",
                string.format("|cffaaaaaaRecorded events: %d  Â·  Group sessions: %d  Â·  Group time: %d min%s|r", summary.totalEvents or 0, summary.groupSessions or 0, groupMinutes,
                    (tonumber(summary.estimatedGroupSessions) or 0) > 0 and (" Â· " .. tostring(summary.estimatedGroupSessions) .. " older sessions estimated") or ""),
                string.format("|cffaaaaaaWhisper interactions: %d (%d in / %d out)  Â·  Friend changes: %d  Â·  Guild changes: %d|r", summary.whispers or 0, summary.incomingWhispers or 0, summary.outgoingWhispers or 0, summary.friendEvents or 0, summary.guildEvents or 0),
                "|cff888888Filter: " .. typeLabel .. " Â· " .. periodLabel .. "|r",
            }
            if summary.first then lines[#lines + 1] = "|cff888888First recorded: " .. date("%Y-%m-%d", summary.first) .. "  Â·  Last: " .. date("%Y-%m-%d", summary.last or summary.first) .. "|r" end
            if summary.locations and #summary.locations > 0 then lines[#lines + 1] = "|cff888888Recorded locations: " .. table.concat(summary.locations, ", ") .. "|r" end
            if not (SC.db.journal and SC.db.journal.enabled) then
                lines[#lines + 1] = "|cffffcc66Automatic tracking is disabled.|r Enable it in Settings > Social & Journal."
            end
            if #events == 0 then
                lines[#lines + 1] = "|cff888888No recorded events for this player yet.|r"
            else
                for i = 1, #events do
                    local event = events[i]
                    lines[#lines + 1] = "|cff888888" .. JournalEventTimeLabel(event, "%Y-%m-%d %H:%M") .. "|r  |cffffffff" .. JournalEventTitleLabel(event, "Activity") .. "|r"
                    if event.detail and event.detail ~= "" then lines[#lines + 1] = "    |cffaaaaaa" .. tostring(event.detail) .. "|r" end
                    if event.type == "group" then
                        local meta = {}
                        if event.sessionKind and event.sessionKind ~= "" then meta[#meta + 1] = event.sessionKind end
                        if tonumber(event.groupSize) and event.groupSize > 0 then meta[#meta + 1] = "Group size " .. event.groupSize end
                        if event.difficultyName and event.difficultyName ~= "" then meta[#meta + 1] = event.difficultyName end
                        if #meta > 0 then lines[#lines + 1] = "    |cff66ccff" .. table.concat(meta, " Â· ") .. "|r" end
                        local attendance = SC.GetJournalGroupAttendance and SC.GetJournalGroupAttendance(event, selected)
                        if attendance then
                            local minutes = math.floor((attendance.seconds or 0) / 60)
                            local attendanceText = "Your time in this group: " .. minutes .. " min"
                            if attendance.intervals and attendance.intervals > 1 then attendanceText = attendanceText .. " Â· " .. attendance.intervals .. " visits" end
                            if attendance.estimated then attendanceText = attendanceText .. " Â· estimated from older history" end
                            lines[#lines + 1] = "    |cff88ccee" .. attendanceText .. "|r"
                        end
                    end
                end
            end
            if note.tags and #note.tags > 0 then lines[#lines + 1] = ""; lines[#lines + 1] = "|cff66ccffPERSONAL TAGS|r  " .. table.concat(note.tags, " Â· ") end
            if note.text and note.text ~= "" then lines[#lines + 1] = "|cff66ccffNOTE|r  " .. note.text end
            SetHubTranscript(table.concat(lines, "\n\n"))
            if category == "journal" then
                listFrame.journalButton:SetText("All Contacts")
            elseif category == "activity" then
                listFrame.journalButton:SetText("Back to Activity")
            else
                listFrame.journalButton:SetText("Back to Profile")
            end
        elseif info.accountOnly then
            local lines = {
                "|cff66ccffBATTLE.NET ACCOUNT|r",
                "This friend is available as a Battle.net account, but the game has not supplied an active WoW character.",
                "You can keep Favorites, Pins, Groups and personal notes for this account. Whisper and Party actions require a WoW character name.",
            }
            if info.lastOnlineTime and info.lastOnlineTime > 0 then
                lines[#lines + 1] = "Last online: " .. date("%Y-%m-%d %H:%M", info.lastOnlineTime)
            end
            AppendBnetAccountSummary(lines, info, selected)
            SetHubTranscript(table.concat(lines, "\n\n"))
            listFrame.journalButton:SetText("View Journal")
        else
            local summary = SC.GetJournalPlayerSummary and SC.GetJournalPlayerSummary(selected) or {}
            local note = SC.GetContactNote and SC.GetContactNote(selected) or { tags = {}, text = "" }
            local messages = SC.whisperMessages[SC.NameKey(selected)] or {}
            local lines = { "|cff66ccffPLAYER OVERVIEW|r", "" }
            AppendBnetAccountSummary(lines, info, selected)
            lines[#lines + 1] = string.format("Recorded interactions: %d  Â·  Group sessions: %d  Â·  Shared group time: %d min", summary.totalEvents or 0, summary.groupSessions or 0, math.floor((tonumber(summary.groupDuration) or 0) / 60))
            lines[#lines + 1] = string.format("Whisper interactions: %d  Â·  Friend changes: %d  Â·  Guild changes: %d  Â·  Presence changes: %d", summary.whispers or 0, summary.friendEvents or 0, summary.guildEvents or 0, summary.presenceEvents or 0)
            if summary.first then lines[#lines + 1] = "First recorded interaction: " .. date("%Y-%m-%d", summary.first) .. "  Â·  Last: " .. date("%Y-%m-%d", summary.last or summary.first) end
            if summary.lastGroupAt and summary.lastGroupAt > 0 then lines[#lines + 1] = "Last shared group session: " .. date("%Y-%m-%d %H:%M", summary.lastGroupAt) end
            if summary.lastWhisperAt and summary.lastWhisperAt > 0 then lines[#lines + 1] = "Last Whisper interaction: " .. date("%Y-%m-%d %H:%M", summary.lastWhisperAt) end
            if summary.locations and #summary.locations > 0 then lines[#lines + 1] = "Recorded locations: " .. table.concat(summary.locations, ", ") end
            local playerInsights = SC.GetSocialPlayerInsights and SC.GetSocialPlayerInsights(selected, tonumber((SC.db.journal or {}).timelineDays) or 0)
            if playerInsights then
                lines[#lines + 1] = string.format("Recent insight: %d group session(s), %d Whisper interaction(s), %d tracked group minute(s) in the selected period", tonumber(playerInsights.groupSessions) or 0, tonumber(playerInsights.whispers) or 0, math.floor((tonumber(playerInsights.groupSeconds) or 0) / 60))
            end
            if not (SC.db.journal and SC.db.journal.enabled) then
                lines[#lines + 1] = "|cffffcc66Automatic Player Journal tracking is off. Enable it in Settings > Social & Journal to collect future local history.|r"
            end
            if summary.estimatedGroupSessions and summary.estimatedGroupSessions > 0 then
                lines[#lines + 1] = "|cffffcc66" .. tostring(summary.estimatedGroupSessions) .. " older group sessions use estimated attendance.|r"
            end
            if summary.groupPartners and #summary.groupPartners > 0 then
                lines[#lines + 1] = ""
                lines[#lines + 1] = "|cff66ccffMOST FREQUENT GROUP PARTNERS|r"
                for i, partner in ipairs(summary.groupPartners) do
                    lines[#lines + 1] = string.format("%s  Â·  %d sessions", tostring(partner.name), tonumber(partner.sessions) or 0)
                end
            end
            if note.tags and #note.tags > 0 then
                lines[#lines + 1] = ""
                lines[#lines + 1] = "|cff66ccffPERSONAL TAGS|r  " .. table.concat(note.tags, " Â· ")
            end
            if note.text and note.text ~= "" then lines[#lines + 1] = "|cff66ccffPERSONAL NOTE|r  " .. note.text end
            if #messages > 0 then
                lines[#lines + 1] = ""
                lines[#lines + 1] = "|cff66ccffRECENT WHISPER Â· THIS SESSION ONLY|r"
                local first = math.max(1, #messages - 4)
                for i = first, #messages do
                    local m = messages[i]
                    local stamp = date("%H:%M", m.time or time())
                    local who = m.out and "You" or SC.ShortName(selected)
                    local color = m.out and "ffb8b8b8" or "ffffffff"
                    lines[#lines + 1] = "|cff888888" .. stamp .. "|r  |c" .. color .. who .. ":|r " .. tostring(m.text or "")
                end
            end
            if summary.totalEvents == 0 and #messages == 0 and #note.tags == 0 and (note.text or "") == "" then
                lines[#lines + 1] = "|cff888888No local history or notes yet. Use Quick Note to add a few tags, or enable Player Journal to begin recording events.|r"
            end
            SetHubTranscript(table.concat(lines, "\n\n"))
            listFrame.journalButton:SetText("View History")
        end

        listFrame.favoriteButton:SetText((SC.IsFavorite and SC.IsFavorite(selected)) and "â Favorite" or "+ Favorite")
        listFrame.pinButton:SetText((SC.IsContactPinned and SC.IsContactPinned(selected)) and "â Pinned" or "+ Pin")
        listFrame.openButton:SetText(info.accountOnly and "No WoW Character" or "Open Whisper")
        if info.accountOnly then listFrame.openButton:Disable() else listFrame.openButton:Enable() end
        listFrame.quickNoteButton:Enable()
        listFrame.journalButton:Enable()
        listFrame.favoriteButton:Enable()
        listFrame.pinButton:Enable()
        local selectedNote = SC.GetContactNote and SC.GetContactNote(selected) or { tags = {}, text = "" }
        local hasSavedNote = (selectedNote.tags and #selectedNote.tags > 0) or (selectedNote.text and selectedNote.text ~= "")
        if listFrame.deleteNoteButton then
            if hasSavedNote then listFrame.deleteNoteButton:Enable() else listFrame.deleteNoteButton:Disable() end
        end
        if category == "overview" and listFrame.mode == "overview" then
            listFrame.openButton:Disable()
            listFrame.favoriteButton:Disable()
            listFrame.pinButton:Disable()
            listFrame.quickNoteButton:Disable()
            listFrame.journalButton:Enable()
            if listFrame.deleteNoteButton then listFrame.deleteNoteButton:Disable() end
        end
    else
        if isGuildManager then
            RenderGuildManagerView(names)
            listFrame.openButton:Disable()
            listFrame.favoriteButton:Disable()
            listFrame.pinButton:Disable()
            listFrame.quickNoteButton:Disable()
            listFrame.journalButton:Disable()
            if listFrame.deleteNoteButton then listFrame.deleteNoteButton:Disable() end
        elseif category == "insights" and listFrame.mode == "insights" then
            local journal = SC.db.journal or {}
            local days = tonumber(journal.timelineDays) or 0
            local stats = listFrame.intelligenceStats or (SC.GetSocialIntelligenceStats and SC.GetSocialIntelligenceStats(days)) or {}
            listFrame.header:SetText("Social Intelligence")
            listFrame.status:SetText(journal.enabled and "LOCAL INSIGHTS" or "JOURNAL DISABLED")
            listFrame.status:SetTextColor(0.4, 0.8, 1)
            listFrame.details:SetText("Discover frequent group partners, recurring Whisper contacts and relationship signals from your locally recorded history. Suggestions never change contacts automatically.")
            local period = days > 0 and (tostring(days) .. " days") or "All recorded history"
            local lines = { "|cff66ccffSMARTCHAT SOCIAL INTELLIGENCE|r", "|cff888888" .. period .. " Â· Calculated locally from recorded events|r", "" }
            lines[#lines + 1] = string.format("Events: %d  Â·  Known players: %d  Â·  Group sessions: %d  Â·  Group duration: %d min", tonumber(stats.events) or 0, tonumber(stats.uniquePlayers) or 0, tonumber(stats.groupSessions) or 0, tonumber(stats.groupMinutes) or 0)
            lines[#lines + 1] = string.format("Whisper interactions: %d  Â·  Friend changes: %d  Â·  Guild changes: %d  Â·  Presence changes: %d  Â·  Quest roster events: %d", tonumber(stats.whisperInteractions) or 0, tonumber(stats.friendChanges) or 0, tonumber(stats.guildChanges) or 0, tonumber(stats.presenceChanges) or 0, tonumber(stats.questEvents) or 0)
            lines[#lines + 1] = ""
            lines[#lines + 1] = "|cff66ccffFREQUENT GROUP PARTNERS|r"
            if #(stats.topGroupPartners or {}) == 0 then lines[#lines + 1] = "|cff888888No group partner ranking is available for this period.|r" end
            for i = 1, math.min(6, #(stats.topGroupPartners or {})) do
                local person = stats.topGroupPartners[i]
                lines[#lines + 1] = string.format("  %s  Â·  %d session(s)  Â·  %d min tracked", tostring(person.name), tonumber(person.groupSessions) or 0, math.floor((tonumber(person.groupSeconds) or 0) / 60))
            end
            lines[#lines + 1] = ""
            lines[#lines + 1] = "|cff66ccffMOST ACTIVE WHISPER CONTACTS|r"
            if #(stats.topWhisperContacts or {}) == 0 then lines[#lines + 1] = "|cff888888No Whisper interaction history is available for this period.|r" end
            for i = 1, math.min(5, #(stats.topWhisperContacts or {})) do
                local person = stats.topWhisperContacts[i]
                lines[#lines + 1] = string.format("  %s  Â·  %d interaction(s)", tostring(person.name), tonumber(person.whispers) or 0)
            end
            lines[#lines + 1] = ""
            lines[#lines + 1] = "|cff66ccffMOST VISITED RECORDED LOCATIONS|r"
            if #(stats.topLocations or {}) == 0 then lines[#lines + 1] = "|cff888888No location history is available.|r" end
            for i = 1, math.min(5, #(stats.topLocations or {})) do
                local location = stats.topLocations[i]
                lines[#lines + 1] = string.format("  %s  Â·  %d session(s)", tostring(location.name), tonumber(location.sessions) or 0)
            end
            lines[#lines + 1] = ""
            lines[#lines + 1] = "|cff66ccffSUGGESTIONS|r"
            if not journal.enabled then
                lines[#lines + 1] = "|cffffcc66Player Journal is off. Enable it in Settings > Social & Journal to build future insights.|r"
            elseif #(stats.recommendations or {}) == 0 then
                lines[#lines + 1] = "|cff888888No suggestions yet. Keep recording normal social activity; SmartChat will only suggest actions when recorded counts support them.|r"
            else
                for i = 1, math.min(8, #(stats.recommendations or {})) do
                    local suggestion = stats.recommendations[i]
                    local actionText = suggestion.action == "pin" and "Consider Pin" or "Consider Favorite"
                    lines[#lines + 1] = string.format("  %s  Â·  %s  Â·  %s", tostring(suggestion.name), tostring(suggestion.reason), actionText)
                end
            end
            lines[#lines + 1] = ""
            lines[#lines + 1] = "|cff888888Select a discovered contact on the left to open their profile. Right-click for actions. All suggestions are optional and based only on your local recorded history.|r"
            SetHubTranscript(table.concat(lines, "\n\n"))
            listFrame.openButton:Disable(); listFrame.favoriteButton:Disable(); listFrame.pinButton:Disable(); listFrame.quickNoteButton:Disable(); listFrame.journalButton:Disable()
            if listFrame.deleteNoteButton then listFrame.deleteNoteButton:Disable() end
        elseif category == "overview" then
            listFrame.header:SetText("Social Overview")
            listFrame.status:SetText("YOUR SOCIAL SPACE")
            listFrame.status:SetTextColor(0.4, 0.8, 1)
            listFrame.details:SetText("No contacts have been found yet. Friends, Guild, Party, Whispers and recent activity will appear here when available.")
            SetHubTranscript("|cff66ccffWELCOME TO SMARTCHAT SOCIAL HUB|r\n\nBrowse the categories above to manage your contacts. You can add Favorites, Pin contacts, create private groups and keep local notes.")
            listFrame.openButton:Disable()
            listFrame.favoriteButton:Disable()
            listFrame.pinButton:Disable()
            listFrame.quickNoteButton:Disable()
            listFrame.journalButton:SetText("View Activity")
            listFrame.journalButton:Enable()
        elseif category == "activity" then
            listFrame.header:SetText("Recent Social Activity")
            listFrame.status:SetText("LOCAL HISTORY")
            listFrame.status:SetTextColor(0.4, 0.8, 1)
            listFrame.details:SetText("Enable Player Journal to begin recording local social events. No network connection is used.")
            SetHubTranscript("|cff66ccffRECENT ACTIVITY Â· LOCAL|r\n\n|cff888888No recorded events yet. Enable Player Journal in Settings > Social & Journal.|r")
        elseif category == "notes" then
            listFrame.header:SetText("Personal Notes")
            listFrame.status:SetText("LOCAL ONLY")
            listFrame.status:SetTextColor(0.4, 0.8, 1)
            listFrame.details:SetText("Your private notes and quick tags are stored locally. Select a player to review, edit or delete their note.")
            SetHubTranscript("|cff66ccffPERSONAL NOTES|r\n\n|cff888888No saved notes yet. Select a contact and use Quick Note to add ready-made tags or an optional personal note.|r")
        else
            listFrame.header:SetText("No contacts in this section")
            listFrame.status:SetText(" ")
            listFrame.details:SetText("This list is empty or the game has not supplied contact data yet.")
            SetHubTranscript("|cff888888Try another section, or check your in-game Friends and Guild lists.|r")
        end
        listFrame.openButton:Disable()
        listFrame.favoriteButton:Disable()
        listFrame.pinButton:Disable()
        listFrame.quickNoteButton:Disable()
        listFrame.journalButton:Disable()
        if listFrame.deleteNoteButton then listFrame.deleteNoteButton:Disable() end
        listFrame.openButton:SetText("No Contact Selected")
    end
end

local function HubSettingsHelp(parent, anchor, text)
    local help = CreateFrame("Button", nil, parent)
    help:SetSize(16, 16)
    help:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    help.label = help:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    help.label:SetPoint("CENTER")
    help.label:SetText("?")
    help.label:SetTextColor(0.35, 0.78, 1)
    help:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    help:SetScript("OnLeave", GameTooltip_Hide)
    return help
end

local function EnsureSocialNotificationSettings()
    SC.db.socialNotifications = SC.db.socialNotifications or {}
    local n = SC.db.socialNotifications
    local defaults = {
        enabled = false, friendOnline = true, friendOffline = false,
        friendChanges = true, guildChanges = false, guildPresence = false,
        groupChanges = false, bnetPresence = false,
    }
    for key, value in pairs(defaults) do if n[key] == nil then n[key] = value end end
    return n
end

local function RefreshHubSettingsRows()
    if not listFrame or not listFrame.settingsRows then return end
    local rows = listFrame.settingsRows
    local hub = EnsureHubPreferences()
    local y = -10
    local function placeHeader(key, text)
        local fs = rows.headers[key]
        fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", rows.child, "TOPLEFT", 8, y); fs:SetText(text)
        y = y - 23
    end
    local function placePreference(key, label, value, helpText)
        local row = rows.preferences[key]
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", rows.child, "TOPLEFT", 2, y)
        row.check:SetChecked(value and true or false)
        row.label:SetText(label)
        row.help:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(helpText, 1, 1, 1, true); GameTooltip:Show()
        end)
        row.help:SetScript("OnLeave", GameTooltip_Hide)
        row:Show(); y = y - 25
    end
    placeHeader("display", "CONTACT LIST APPEARANCE")
    placePreference("statusDot", "Show status indicator", hub.showStatusDot, "Show a small Online, Offline, AFK, DND or Unknown dot beside each contact. This changes only the Social Hub list.")
    placePreference("badges", "Show relationship badges", hub.showRelationshipBadges, "Show the existing [F], [B], [G] and [P] relationship markers beside contact names.")
    placePreference("classLevel", "Show Class and Level", hub.showClassLevel, "Show available class and level information in the smaller line below each contact name.")
    placePreference("groups", "Show personal group labels", hub.showContactGroups, "Show the names of your private SmartChat groups beneath contacts. Does not change in-game Guild or Party membership.")
    placePreference("pinMarkers", "Show Favorite / Pin markers", hub.showFavoritePinMarkers, "Show the star and diamond markers for Favorites and pinned contacts.")

    local style = rows.styleButton
    style:ClearAllPoints(); style:SetPoint("TOPLEFT", rows.child, "TOPLEFT", 8, y - 1)
    style:SetText("Contact rows: " .. (hub.rowStyle == "compact" and "Compact" or "Comfortable"))
    y = y - 31

    placeHeader("categories", "VISIBLE CATEGORIES  Â·  USE â / â TO REORDER")
    local categoryIndex = 0
    for _, item in ipairs(OrderedSocialCategories()) do
        categoryIndex = categoryIndex + 1
        local row = rows.categories[item.key]
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", rows.child, "TOPLEFT", 2, y)
        row.check:SetChecked(hub.categoryVisibility[item.key] ~= false or item.key == "overview")
        if item.key == "overview" then row.check:Disable() else row.check:Enable() end
        row.label:SetText(item.label)
        row.up:SetEnabled(categoryIndex > 2)
        row.down:SetEnabled(categoryIndex < #SOCIAL_CATEGORIES)
        row:Show(); y = y - 24
    end

    placeHeader("profiles", "PLAYER PROFILE SECTIONS  Â·  USE â / â TO REORDER")
    local profileIndex = 0
    for _, item in ipairs(OrderedProfileSections()) do
        profileIndex = profileIndex + 1
        local row = rows.profiles[item.key]
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", rows.child, "TOPLEFT", 2, y)
        row.check:SetChecked(hub.profileVisibility[item.key] ~= false or item.key == "overview")
        if item.key == "overview" then row.check:Disable() else row.check:Enable() end
        row.label:SetText(item.label)
        row.up:SetEnabled(profileIndex > 2)
        row.down:SetEnabled(profileIndex < #PROFILE_SECTIONS)
        row:Show(); y = y - 24
    end

    local n = EnsureSocialNotificationSettings()
    placeHeader("notifications", "SOCIAL NOTIFICATIONS")
    placePreference("notifyMaster", "Enable Social Notifications", n.enabled, "Enable SmartChat's small social notification toasts. This is separate from Player Journal history tracking.")
    placePreference("notifyFriendOnline", "Friend comes online", n.friendOnline, "Show a toast when a known Friend changes to Online after the initial login baseline.")
    placePreference("notifyFriendOffline", "Friend goes offline", n.friendOffline, "Show a toast when a known Friend changes to Offline. Turn off to reduce notification noise.")
    placePreference("notifyFriendChanges", "Friend list changes", n.friendChanges, "Show a toast when a player is added to or removed from your in-game Friend List.")
    placePreference("notifyGuildChanges", "Guild member joins or leaves", n.guildChanges, "Show a toast when the Guild roster detects a member joining or leaving.")
    placePreference("notifyGuildPresence", "Guild member presence changes", n.guildPresence, "Show a toast for Guild member Online or Offline changes. This can be noisy in a large Guild.")
    placePreference("notifyGroupChanges", "Party / Raid member joins or leaves", n.groupChanges, "Show a toast when a member joins or leaves your current Party or Raid.")
    placePreference("notifyBnetPresence", "Battle.net friend presence changes", n.bnetPresence, "Show a toast for known Battle.net account presence changes. Unknown and Appear Offline are not treated as Offline.")

    rows.child:SetHeight(math.max(1, -y + 12))
end

local function BuildHubSettingsPanel()
    if not listFrame or listFrame.settingsPanel then return end
    local panel = CreateFrame("Frame", "SmartChatHubSettingsPanel", listFrame, "BackdropTemplate")
    panel:SetAllPoints(listFrame)
    panel:SetFrameLevel(listFrame:GetFrameLevel() + 30)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(0.025, 0.03, 0.045, 0.985)
    panel:SetBackdropBorderColor(0.36, 0.48, 0.62, 1)
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 16, -12)
    panel.title:SetText("SOCIAL HUB CUSTOMIZATION")
    local done = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    done:SetSize(68, 22); done:SetPoint("TOPRIGHT", -12, -8); done:SetText("Done")
    done:SetScript("OnClick", function() panel:Hide(); RefreshInbox() end)
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -40); scroll:SetPoint("BOTTOMRIGHT", -32, 42)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(770); child:SetHeight(900)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local maximum = math.max(0, (child:GetHeight() or 1) - (self:GetHeight() or 1))
        self:SetVerticalScroll(math.max(0, math.min(maximum, current - delta * 34)))
    end)
    local rows = { child = child, headers = {}, preferences = {}, categories = {}, profiles = {} }
    panel.rows = rows
    listFrame.settingsRows = rows
    local function header(key)
        local fs = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetTextColor(0.35, 0.78, 1)
        rows.headers[key] = fs
    end
    for _, key in ipairs({ "display", "categories", "profiles", "notifications" }) do header(key) end

    local function createPreference(key, setter)
        local row = CreateFrame("Frame", nil, child)
        row:SetSize(750, 23)
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(22, 22); row.check:SetPoint("LEFT", 1, 0)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
        row.help = CreateFrame("Button", nil, row)
        row.help:SetSize(16, 16); row.help:SetPoint("LEFT", row.label, "RIGHT", 4, 0)
        row.help.text = row.help:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.help.text:SetPoint("CENTER"); row.help.text:SetText("?"); row.help.text:SetTextColor(0.35, 0.78, 1)
        row.check:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false); RefreshHubSettingsRows(); ApplySocialCategoryLayout(); ApplyProfileSectionLayout(); RefreshInbox() end)
        row.check.key = key
        rows.preferences[key] = row
    end
    createPreference("statusDot", function(v) EnsureHubPreferences().showStatusDot = v end)
    createPreference("badges", function(v) EnsureHubPreferences().showRelationshipBadges = v end)
    createPreference("classLevel", function(v) EnsureHubPreferences().showClassLevel = v end)
    createPreference("groups", function(v) EnsureHubPreferences().showContactGroups = v end)
    createPreference("pinMarkers", function(v) EnsureHubPreferences().showFavoritePinMarkers = v end)
    createPreference("notifyMaster", function(v) EnsureSocialNotificationSettings().enabled = v end)
    createPreference("notifyFriendOnline", function(v) EnsureSocialNotificationSettings().friendOnline = v end)
    createPreference("notifyFriendOffline", function(v) EnsureSocialNotificationSettings().friendOffline = v end)
    createPreference("notifyFriendChanges", function(v) EnsureSocialNotificationSettings().friendChanges = v end)
    createPreference("notifyGuildChanges", function(v) EnsureSocialNotificationSettings().guildChanges = v end)
    createPreference("notifyGuildPresence", function(v) EnsureSocialNotificationSettings().guildPresence = v end)
    createPreference("notifyGroupChanges", function(v) EnsureSocialNotificationSettings().groupChanges = v end)
    createPreference("notifyBnetPresence", function(v) EnsureSocialNotificationSettings().bnetPresence = v end)

    rows.styleButton = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
    rows.styleButton:SetSize(180, 22)
    rows.styleButton:SetScript("OnClick", function()
        local hub = EnsureHubPreferences()
        hub.rowStyle = hub.rowStyle == "compact" and "comfortable" or "compact"
        RefreshHubSettingsRows(); RefreshInbox()
    end)
    rows.styleHelpAnchor = rows.styleButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rows.styleHelpAnchor:SetPoint("LEFT", rows.styleButton, "RIGHT", 8, 0)
    rows.styleHelpAnchor:SetText("Contact row density")
    HubSettingsHelp(panel, rows.styleHelpAnchor, "Compact uses shorter contact rows. Comfortable gives each contact more vertical spacing. This affects only the Social Hub list, not the Whisper tab.")

    local function createOrderedRow(collection, key, label, kind)
        local row = CreateFrame("Frame", nil, child)
        row:SetSize(750, 22)
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(22, 22); row.check:SetPoint("LEFT", 1, 0)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.check, "RIGHT", 2, 0); row.label:SetWidth(540); row.label:SetJustifyH("LEFT")
        row.up = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.up:SetSize(22, 20); row.up:SetPoint("RIGHT", -28, 0); row.up:SetText("â")
        row.down = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.down:SetSize(22, 20); row.down:SetPoint("RIGHT", -2, 0); row.down:SetText("â")
        row.check:SetScript("OnClick", function(self)
            local hub = EnsureHubPreferences()
            local vis = kind == "category" and hub.categoryVisibility or hub.profileVisibility
            if kind == "category" and key == "overview" or kind == "profile" and key == "overview" then
                self:SetChecked(true); return
            end
            vis[key] = self:GetChecked() and true or false
            ApplySocialCategoryLayout(); ApplyProfileSectionLayout(); RefreshHubSettingsRows(); RefreshInbox()
        end)
        row.up:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Move this item up", 1, 1, 1); GameTooltip:Show() end)
        row.up:SetScript("OnLeave", GameTooltip_Hide)
        row.down:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Move this item down", 1, 1, 1); GameTooltip:Show() end)
        row.down:SetScript("OnLeave", GameTooltip_Hide)
        local helpText = (kind == "category") and "Show or hide this Social Hub category. Use the arrows to change its position in the category bar. Overview is always available." or "Show or hide this Player Profile section. Use the arrows to change its order. Overview is always available."
        HubSettingsHelp(row, row.label, helpText)
        row.up:SetScript("OnClick", function()
            local order = EnsureHubPreferences()[kind == "category" and "categoryOrder" or "profileOrder"]
            if MoveOrderedKey(order, key, -1) then ApplySocialCategoryLayout(); ApplyProfileSectionLayout(); RefreshHubSettingsRows(); RefreshInbox() end
        end)
        row.down:SetScript("OnClick", function()
            local order = EnsureHubPreferences()[kind == "category" and "categoryOrder" or "profileOrder"]
            if MoveOrderedKey(order, key, 1) then ApplySocialCategoryLayout(); ApplyProfileSectionLayout(); RefreshHubSettingsRows(); RefreshInbox() end
        end)
        collection[key] = row
        return row
    end
    for _, item in ipairs(SOCIAL_CATEGORIES) do createOrderedRow(rows.categories, item.key, item.label, "category") end
    for _, item in ipairs(PROFILE_SECTIONS) do createOrderedRow(rows.profiles, item.key, item.label, "profile") end

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(170, 24); reset:SetPoint("BOTTOMLEFT", 14, 10); reset:SetText("Reset Layout Defaults")
    reset:SetScript("OnClick", function()
        local hub = EnsureHubPreferences()
        hub.categoryVisibility = {}; hub.categoryOrder = {}
        for _, item in ipairs(SOCIAL_CATEGORIES) do hub.categoryVisibility[item.key] = true; hub.categoryOrder[#hub.categoryOrder + 1] = item.key end
        hub.profileVisibility = {}; hub.profileOrder = {}
        for _, item in ipairs(PROFILE_SECTIONS) do hub.profileVisibility[item.key] = true; hub.profileOrder[#hub.profileOrder + 1] = item.key end
        hub.rowStyle = "comfortable"
        hub.showStatusDot, hub.showRelationshipBadges, hub.showClassLevel = true, true, true
        hub.showContactGroups, hub.showFavoritePinMarkers = true, true
        ApplySocialCategoryLayout(); ApplyProfileSectionLayout(); RefreshHubSettingsRows(); RefreshInbox()
    end)
    HubSettingsHelp(panel, reset, "Restore the default Social Hub category order, visible sections and contact-list appearance. Does not reset Friends, Favorites, Notes, Journal data or notification choices.")
    listFrame.settingsPanel = panel
    RefreshHubSettingsRows()
    panel:Hide()
end

local function ToggleHubSettingsPanel()
    if not listFrame then return end
    BuildHubSettingsPanel()
    if listFrame.settingsPanel:IsShown() then
        listFrame.settingsPanel:Hide()
    else
        RefreshHubSettingsRows()
        listFrame.settingsPanel:Show()
        listFrame.settingsPanel:Raise()
    end
end

local function ShowList()
    if not listFrame then
        listFrame = CreateFrame("Frame", "SmartChatSocialHub", UIParent, "BackdropTemplate")
        listFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        listFrame:SetFrameLevel(80)
        listFrame:SetClampedToScreen(true)
        listFrame:SetSize(840, 500)
        listFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        listFrame:SetBackdropColor(0.035, 0.04, 0.055, 0.97)
        listFrame:SetBackdropBorderColor(0.35, 0.42, 0.52, 1)
        listFrame.rows = {}
        listFrame.categoryButtons = {}
        listFrame.category = "overview"
        listFrame.mode = "overview"
        listFrame.profileSection = "overview"
        listFrame:SetScript("OnHide", function()
            if catcher then catcher:Hide() end
            if listFrame and listFrame.settingsPanel then listFrame.settingsPanel:Hide() end
            StopNetworkMapAnimations()
        end)
        WatchMouse(listFrame, 1.0, socialBtn)
        tinsert(UISpecialFrames, "SmartChatSocialHub")

        listFrame.title = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        listFrame.title:SetPoint("TOPLEFT", 12, -9)
        listFrame.title:SetText("SOCIAL HUB")
        listFrame.stats = listFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        listFrame.stats:SetPoint("LEFT", listFrame.title, "RIGHT", 18, 0)
        listFrame.stats:SetJustifyH("LEFT")
        local close = CreateFrame("Button", nil, listFrame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() listFrame:Hide() end)
        listFrame.hubSettingsButton = CreateFrame("Button", nil, listFrame, "UIPanelButtonTemplate")
        listFrame.hubSettingsButton:SetSize(82, 22)
        listFrame.hubSettingsButton:SetPoint("TOPRIGHT", -34, -4)
        listFrame.hubSettingsButton:SetText("Customize")
        listFrame.hubSettingsButton:SetScript("OnClick", ToggleHubSettingsPanel)
        listFrame.hubSettingsButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Customize Social Hub", 1, 1, 1)
            GameTooltip:AddLine("Choose visible categories, reorder sections, adjust contact rows and control social notifications.", 0.75, 0.85, 1, true)
            GameTooltip:Show()
        end)
        listFrame.hubSettingsButton:SetScript("OnLeave", GameTooltip_Hide)
        listFrame.stats:SetWidth(560)
        listFrame.stats:SetWordWrap(false)

        for _, item in ipairs(OrderedSocialCategories()) do
            local key, label = item.key, item.label
            local button = CreateFrame("Button", nil, listFrame, "UIPanelButtonTemplate")
            button:SetSize(SOCIAL_CATEGORY_WIDTHS[key] or 52, 22)
            button:SetText(label)
            if key == "networkMap" then
                button:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText("Optional Network Map", 1, 1, 1)
                    GameTooltip:AddLine("This visual view is disabled until you enable it inside this page. It uses existing Social Hub data and does not open a separate window.", 0.75, 0.85, 1, true)
                    GameTooltip:Show()
                end)
                button:SetScript("OnLeave", GameTooltip_Hide)
            end
            button:SetScript("OnClick", function()
                listFrame.category = key
                listFrame.mode = key == "overview" and "overview" or (key == "insights" and "insights" or (key == "guild" and "guild" or (key == "networkMap" and "networkMap" or "profile")))
                if key == "guild" or key == "insights" or key == "networkMap" then listFrame.selectedName = nil end
                if key == "guild" then listFrame.guildSection = "overview"; listFrame.guildDrillFilter = nil end
                if key == "journal" then
                    listFrame.profileSection = "history"
                elseif key == "notes" then
                    listFrame.profileSection = "notes"
                else
                    listFrame.profileSection = "overview"
                end
                if key == "groups" and not listFrame.selectedGroup then listFrame.selectedGroup = "All" end
                RefreshInbox()
            end)
            listFrame.categoryButtons[key] = button
        end
        ApplySocialCategoryLayout()

        listFrame.searchBox = CreateFrame("EditBox", nil, listFrame, "InputBoxTemplate")
        listFrame.searchBox:SetSize(210, 20)
        listFrame.searchBox:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 14, -57)
        listFrame.searchBox:SetAutoFocus(false)
        listFrame.searchBox:SetMaxLetters(40)
        listFrame.searchBox:SetText("Search contacts...")
        listFrame.searchBox:SetScript("OnTextChanged", function() if listFrame:IsShown() then RefreshInbox() end end)
        listFrame.searchBox:SetScript("OnEditFocusGained", function(self)
            if self:GetText() == "Search contacts..." then self:SetText("") end
        end)
        listFrame.searchBox:SetScript("OnEditFocusLost", function(self)
            if self:GetText() == "" then self:SetText("Search contacts...") end
        end)
        listFrame.searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        listFrame.searchBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

        listFrame.filterButton = CreateFrame("Button", nil, listFrame, "UIPanelButtonTemplate")
        listFrame.filterButton:SetSize(102, 22)
        listFrame.filterButton:SetPoint("LEFT", listFrame.searchBox, "RIGHT", 8, 0)
        listFrame.filterButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        listFrame.filterButton:SetScript("OnClick", function(self, mouseButton)
            local social = SC.db.social or {}
            local current = GetContactFilterMode(social)
            local nextMode = "all"
            if mouseButton == "RightButton" then
                nextMode = "all"
            else
                local index = 1
                for i, item in ipairs(CONTACT_FILTERS) do if item.key == current then index = i break end end
                nextMode = CONTACT_FILTERS[index % #CONTACT_FILTERS + 1].key
            end
            social.contactFilterMode = nextMode
            social.onlineOnly = false
            RefreshInbox()
        end)
        listFrame.filterButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Quick Contact Filter", 1, 1, 1)
            GameTooltip:AddLine("Left-click to cycle: All, Available, Online, Offline, AFK, DND, Unknown, Favorites, Pinned, Unread and Has Notes.", 0.75, 0.85, 1, true)
            GameTooltip:AddLine("Right-click to reset the filter to All. The filter works together with Search and the selected category.", 0.75, 0.85, 1, true)
            GameTooltip:Show()
        end)
        listFrame.filterButton:SetScript("OnLeave", GameTooltip_Hide)

        listFrame.sortButton = CreateFrame("Button", nil, listFrame, "UIPanelButtonTemplate")
        listFrame.sortButton:SetSize(105, 22)
        listFrame.sortButton:SetPoint("LEFT", listFrame.filterButton, "RIGHT", 6, 0)
        listFrame.sortButton:SetScript("OnClick", function(self)
            local social = SC.db.social
            local modes = { "status", "name", "recent", "unread", "rank", "level", "class" }
            if listFrame.category == "guild" then modes[#modes + 1] = "achievement" end
            local idx = 1
            for i, mode in ipairs(modes) do if social.sortMode == mode then idx = i break end end
            social.sortMode = modes[idx % #modes + 1]
            RefreshInbox()
        end)
        listFrame.sortButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Sort Contacts", 1, 1, 1)
            GameTooltip:AddLine("Cycle through status, name, recent activity, unread messages, Guild Rank, Level and Class.", 0.75, 0.85, 1, true)
            GameTooltip:Show()
        end)
        listFrame.sortButton:SetScript("OnLeave", GameTooltip_Hide)
        listFrame.newGroupButton = CreateFrame("Button", nil, listFrame, "UIPanelButtonTemplate")
        listFrame.newGroupButton:SetSize(96, 22)
        listFrame.newGroupButton:SetPoint("LEFT", listFrame.sortButton, "RIGHT", 6, 0)
        listFrame.newGroupButton:SetText("New Group")
        listFrame.newGroupButton:SetScript("OnClick", function()
            if SC.PromptCreateContactGroup then SC.PromptCreateContactGroup() end
        end)
        listFrame.groupFilterButton = CreateFrame("Button", nil, listFrame, "UIPanelButtonTemplate")
        listFrame.groupFilterButton:SetSize(116, 22)
        listFrame.groupFilterButton:SetPoint("LEFT", listFrame.newGroupButton, "RIGHT", 6, 0)
        listFrame.groupFilterButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        listFrame.groupFilterButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Left-click to cycle groups. Right-click a group for rename, delete, templates and Party invites. Right-click All to create a group or open templates.", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        listFrame.groupFilterButton:SetScript("OnLeave", GameTooltip_Hide)
        listFrame.groupMenu = CreateFrame("Frame", "SmartChatGroupManageMenu", UIParent, "UIDropDownMenuTemplate")
        listFrame.groupFilterButton:SetScript("OnClick", function(self, mouseButton)
            local social = SC.db.social or {}
            local groups = social.groupOrder or {}
            if mouseButton == "RightButton" then
                local selectedGroup = listFrame.selectedGroup
                if selectedGroup and selectedGroup ~= "All" and social.groups and social.groups[selectedGroup] then
                    local menu = {}
                    local title = UIDropDownMenu_CreateInfo()
                    title.text = selectedGroup
                    title.isTitle = true
                    title.notCheckable = true
                    menu[#menu + 1] = title
                    local rename = UIDropDownMenu_CreateInfo()
                    rename.text = "Rename Group"
                    rename.notCheckable = true
                    rename.func = function() if SC.PromptRenameContactGroup then SC.PromptRenameContactGroup(selectedGroup) end end
                    menu[#menu + 1] = rename
                    local remove = UIDropDownMenu_CreateInfo()
                    remove.text = "Delete Group"
                    remove.notCheckable = true
                    remove.func = function() if SC.PromptDeleteContactGroup then SC.PromptDeleteContactGroup(selectedGroup) end end
                    menu[#menu + 1] = remove
                    local toolsTitle = UIDropDownMenu_CreateInfo()
                    toolsTitle.text = "Group Tools"
                    toolsTitle.isTitle = true
                    toolsTitle.notCheckable = true
                    menu[#menu + 1] = toolsTitle
                    local saveTemplate = UIDropDownMenu_CreateInfo()
                    saveTemplate.text = "Save as Templateâ¦"
                    saveTemplate.notCheckable = true
                    saveTemplate.func = function() if SC.PromptSaveContactGroupTemplate then SC.PromptSaveContactGroupTemplate(selectedGroup) end end
                    menu[#menu + 1] = saveTemplate
                    local inviteOnline = UIDropDownMenu_CreateInfo()
                    inviteOnline.text = "Invite Available Members to Partyâ¦"
                    inviteOnline.notCheckable = true
                    inviteOnline.func = function() if SC.PromptInviteContactGroup then SC.PromptInviteContactGroup(selectedGroup) end end
                    menu[#menu + 1] = inviteOnline
                    local templates = UIDropDownMenu_CreateInfo()
                    templates.text = "Manage Group Templatesâ¦"
                    templates.notCheckable = true
                    templates.func = function() if SC.ShowContactGroupTemplateManager then SC.ShowContactGroupTemplateManager(selectedGroup) end end
                    menu[#menu + 1] = templates
                    if EasyMenu then EasyMenu(menu, listFrame.groupMenu, self, 0, 0, "MENU") end
                else
                    local menu = {}
                    local create = UIDropDownMenu_CreateInfo()
                    create.text = "Create New Groupâ¦"
                    create.notCheckable = true
                    create.func = function() if SC.PromptCreateContactGroup then SC.PromptCreateContactGroup() end end
                    menu[#menu + 1] = create
                    local templates = UIDropDownMenu_CreateInfo()
                    templates.text = "Manage Group Templatesâ¦"
                    templates.notCheckable = true
                    templates.func = function() if SC.ShowContactGroupTemplateManager then SC.ShowContactGroupTemplateManager(nil) end end
                    menu[#menu + 1] = templates
                    if EasyMenu then EasyMenu(menu, listFrame.groupMenu, self, 0, 0, "MENU") end
                end
                return
            end
            local choices = { "All" }
            for _, groupName in ipairs(groups) do choices[#choices + 1] = groupName end
            local current = 1
            for i, groupName in ipairs(choices) do if groupName == (listFrame.selectedGroup or "All") then current = i break end end
            listFrame.selectedGroup = choices[current % #choices + 1]
            RefreshInbox()
        end)
        listFrame.groupFilterButton:Hide()
        listFrame.bulkMenu = CreateFrame("Frame", "SmartChatBulkContactMenu", UIParent, "UIDropDownMenuTemplate")
        listFrame.selectModeButton = CreateFrame("Button", nil, listFrame, "UIPanelButtonTemplate")
        listFrame.selectModeButton:SetSize(68, 22)
        listFrame.selectModeButton:SetPoint("LEFT", listFrame.groupFilterButton, "RIGHT", 6, 0)
        listFrame.selectModeButton:SetText("Select")
        listFrame.selectModeButton:SetScript("OnClick", function()
            listFrame.selectionMode = not listFrame.selectionMode
            if not listFrame.selectionMode then wipe(listFrame.multiSelected or {}) end
            RefreshInbox()
        end)
        listFrame.selectModeButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Multi-select contacts", 1, 1, 1)
            GameTooltip:AddLine("Enable selection mode, then click contact rows to select several players. Right-click still opens the normal contact menu.", 0.75, 0.85, 1, true)
            GameTooltip:Show()
        end)
        listFrame.selectModeButton:SetScript("OnLeave", GameTooltip_Hide)
        listFrame.bulkActionsButton = CreateFrame("Button", nil, listFrame, "UIPanelButtonTemplate")
        listFrame.bulkActionsButton:SetSize(82, 22)
        listFrame.bulkActionsButton:SetPoint("LEFT", listFrame.selectModeButton, "RIGHT", 6, 0)
        listFrame.bulkActionsButton:SetText("Actions (0)")
        listFrame.bulkActionsButton:SetScript("OnClick", function(self) ShowBulkContactMenu(self) end)
        listFrame.bulkActionsButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Bulk contact actions", 1, 1, 1)
            GameTooltip:AddLine("Apply local Favorites, Pins and personal-group changes to all selected contacts. This does not modify the in-game Friend, Guild or Ignore lists.", 0.75, 0.85, 1, true)
            GameTooltip:Show()
        end)
        listFrame.bulkActionsButton:SetScript("OnLeave", GameTooltip_Hide)
        listFrame.selectModeButton:Hide(); listFrame.bulkActionsButton:Hide()

        local left = CreateFrame("Frame", nil, listFrame, "BackdropTemplate")
        left:SetPoint("TOPLEFT", 10, -84)
        left:SetPoint("BOTTOMLEFT", 10, 10)
        left:SetWidth(190)
        left:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        left:SetBackdropColor(0, 0, 0, 0.22)
        listFrame.left = left
        listFrame.listTitle = left:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        listFrame.listTitle:SetPoint("TOPLEFT", 8, -7)
        listFrame.listTitle:SetText("CONTACTS")

        local sf = CreateFrame("ScrollFrame", nil, left, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 4, -24)
        sf:SetPoint("BOTTOMRIGHT", -24, 4)
        sf:EnableMouseWheel(true)
        local child = CreateFrame("Frame", nil, sf)
        child:SetWidth(158)
        child:SetHeight(1)
        sf:SetScrollChild(child)
        sf:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll() or 0
            self:SetVerticalScroll(math.max(0, math.min((child:GetHeight() or 1) - (self:GetHeight() or 1), current - delta * 42)))
        end)
        listFrame.scroll, listFrame.listChild = sf, child

        local right = CreateFrame("Frame", nil, listFrame)
        right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
        right:SetPoint("BOTTOMRIGHT", -10, 10)
        listFrame.right = right
        listFrame.header = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        listFrame.header:SetPoint("TOPLEFT", 4, -2)
        listFrame.header:SetWidth(290)
        listFrame.header:SetJustifyH("LEFT")
        listFrame.status = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        listFrame.status:SetPoint("TOPRIGHT", -4, -3)
        listFrame.details = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        listFrame.details:SetPoint("TOPLEFT", listFrame.header, "BOTTOMLEFT", 0, -7)
        listFrame.details:SetWidth(290)
        listFrame.details:SetJustifyH("LEFT")
        listFrame.details:SetWordWrap(true)
        listFrame.dashboardCards = {}
        local dashboardDestinations = { "friends", "guild", "whispers", "favorites", "groups" }
        local dashboardLabels = { "FRIENDS", "GUILD", "WHISPERS", "FAVORITES", "MY GROUPS" }
        local dashboardTips = {
            "Open your in-game Friends list.",
            "Browse the current Guild roster.",
            "Review recent Whisper contacts and unread conversations.",
            "Open your saved favorite contacts.",
            "Manage your private SmartChat contact groups.",
        }
        for i = 1, 5 do
            local card = CreateFrame("Button", nil, right, "BackdropTemplate")
            card:SetSize(110, 68)
            card:SetPoint("TOPLEFT", right, "TOPLEFT", 4 + (i - 1) * 116, -38)
            card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            card:SetBackdropColor(0.065, 0.085, 0.12, 0.96)
            card:SetBackdropBorderColor(0.22, 0.34, 0.48, 0.9)
            card.title = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            card.title:SetPoint("TOPLEFT", 7, -7)
            card.title:SetText(dashboardLabels[i])
            card.value = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            card.value:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
            card.value:SetJustifyH("LEFT")
            card.hint = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            card.hint:SetPoint("BOTTOMLEFT", 7, 6)
            card.hint:SetPoint("BOTTOMRIGHT", -5, 6)
            card.hint:SetJustifyH("LEFT")
            card.hint:SetWordWrap(false)
            card.destination = dashboardDestinations[i]
            local cardTip = dashboardTips[i]
            card:SetScript("OnClick", function(self)
                listFrame.category = self.destination
                listFrame.mode = self.destination == "guild" and "guild" or "profile"
                listFrame.profileSection = "overview"
                if self.destination == "guild" then
                    listFrame.guildSection = "overview"
                    listFrame.guildDrillFilter = nil
                    listFrame.selectedName = nil
                end
                RefreshInbox()
            end)
            card:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(cardTip, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            card:SetScript("OnLeave", GameTooltip_Hide)
            card:SetScript("OnMouseDown", function(self) self:SetBackdropColor(0.10, 0.15, 0.22, 1) end)
            card:SetScript("OnMouseUp", function(self) self:SetBackdropColor(0.065, 0.085, 0.12, 0.96) end)
            listFrame.dashboardCards[i] = card
            card:Hide()
        end
        listFrame.profileSectionButtons = {}
        local profileX = 4
        for _, section in ipairs(PROFILE_SECTIONS) do
            local sectionKey, sectionLabel, sectionWidth = section.key, section.label, section.width
            local button = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
            button:SetSize(sectionWidth, 20)
            button:SetPoint("TOPLEFT", right, "TOPLEFT", profileX, -64)
            button:SetText(sectionLabel)
            button:SetScript("OnClick", function()
                listFrame.profileSection = sectionKey
                listFrame.mode = sectionKey == "history" and "journal" or "profile"
                RefreshInbox()
            end)
            listFrame.profileSectionButtons[sectionKey] = button
            profileX = profileX + sectionWidth + 4
            button:Hide()
        end
        ApplyProfileSectionLayout()
        listFrame.guildTabButtons = {}
        local guildX = 4
        for _, section in ipairs(GUILD_MANAGER_SECTIONS) do
            local sectionKey, sectionLabel, sectionWidth = section.key, section.label, section.width
            local button = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
            button:SetSize(sectionWidth, 20)
            button:SetPoint("TOPLEFT", right, "TOPLEFT", guildX, -64)
            button:SetText(sectionLabel)
            button:SetScript("OnClick", function()
                listFrame.guildSection = sectionKey
                listFrame.mode = "guild"
                listFrame.selectedName = nil
                listFrame.guildDrillFilter = nil
                RefreshInbox()
            end)
            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(sectionLabel, 1, 1, 1)
                GameTooltip:AddLine("Guild Manager section. Statistics are calculated from the current Guild Roster supplied by the game.", 0.75, 0.85, 1, true)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", GameTooltip_Hide)
            listFrame.guildTabButtons[sectionKey] = button
            guildX = guildX + sectionWidth + 3
            button:Hide()
        end
        listFrame.guildBackButton = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
        listFrame.guildBackButton:SetSize(126, 20)
        listFrame.guildBackButton:SetPoint("TOPLEFT", right, "TOPLEFT", 4, -64)
        listFrame.guildBackButton:SetText("< Guild Manager")
        listFrame.guildBackButton:SetScript("OnClick", function()
            listFrame.mode = "guild"
            listFrame.selectedName = nil
            listFrame.guildDrillFilter = nil
            RefreshInbox()
        end)
        listFrame.guildBackButton:Hide()
        listFrame.guildDrillButtons = {}
        for i = 1, 12 do
            local button = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
            button:SetSize(92, 20)
            button:SetPoint("TOPLEFT", right, "TOPLEFT", 4 + ((i - 1) % 6) * 96, -91 - math.floor((i - 1) / 6) * 23)
            button:Hide()
            listFrame.guildDrillButtons[i] = button
        end
        listFrame.guildRosterRefreshButton = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
        listFrame.guildRosterRefreshButton:SetSize(90, 20)
        listFrame.guildRosterRefreshButton:SetText("Refresh")
        listFrame.guildRosterRefreshButton:Hide()
        listFrame.guildRosterRefreshButton:SetScript("OnClick", function()
            local requester = C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster
            if type(requester) == "function" then pcall(requester) end
            guildManagerCache = nil
            if C_Timer and C_Timer.After then C_Timer.After(0.2, function() if listFrame and listFrame:IsShown() then RefreshInbox() end end) else RefreshInbox() end
        end)
        listFrame.guildRosterRefreshButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Refresh Guild Roster", 1, 1, 1)
            GameTooltip:AddLine("Requests the current Guild Roster from the game. The client may ignore requests made within 10 seconds of the previous request.", 0.75, 0.85, 1, true)
            GameTooltip:Show()
        end)
        listFrame.guildRosterRefreshButton:SetScript("OnLeave", GameTooltip_Hide)
        listFrame.guildDrillResetButton = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
        listFrame.guildDrillResetButton:SetSize(88, 20)
        listFrame.guildDrillResetButton:SetPoint("TOPRIGHT", right, "TOPRIGHT", -4, -91)
        listFrame.guildDrillResetButton:SetText("Clear Filter")
        listFrame.guildDrillResetButton:Hide()
        listFrame.guildDrillResetButton:SetScript("OnClick", function()
            listFrame.guildDrillFilter = nil
            listFrame.guildSection = "roster"
            RefreshInbox()
        end)
        listFrame.guildDrillResetButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Clear Guild drill-down filter", 1, 1, 1)
            GameTooltip:Show()
        end)
        listFrame.guildDrillResetButton:SetScript("OnLeave", GameTooltip_Hide)
        listFrame.activityTypeButton = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
        listFrame.activityTypeButton:SetSize(132, 20)
        listFrame.activityTypeButton:SetPoint("TOPLEFT", right, "TOPLEFT", 4, -90)
        listFrame.activityTypeButton:RegisterForClicks("LeftButtonUp")
        listFrame.activityTypeButton:SetScript("OnClick", function()
            local journal = SC.db.journal or {}
            local current, nextIndex = journal.timelineType or "all", 1
            for i, item in ipairs(JOURNAL_TYPE_FILTERS) do if item.key == current then nextIndex = i % #JOURNAL_TYPE_FILTERS + 1 break end end
            journal.timelineType = JOURNAL_TYPE_FILTERS[nextIndex].key
            RefreshInbox()
        end)
        listFrame.activityTypeButton:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Cycle the event type shown in Activity and Player Journal timelines."); GameTooltip:Show() end)
        listFrame.activityTypeButton:SetScript("OnLeave", GameTooltip_Hide)
        listFrame.activityPeriodButton = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
        listFrame.activityPeriodButton:SetSize(82, 20)
        listFrame.activityPeriodButton:SetPoint("LEFT", listFrame.activityTypeButton, "RIGHT", 5, 0)
        listFrame.activityPeriodButton:SetScript("OnClick", function()
            local journal = SC.db.journal or {}
            local current, nextIndex = tonumber(journal.timelineDays) or 0, 1
            for i, item in ipairs(JOURNAL_PERIOD_FILTERS) do if item.key == current then nextIndex = i % #JOURNAL_PERIOD_FILTERS + 1 break end end
            journal.timelineDays = JOURNAL_PERIOD_FILTERS[nextIndex].key
            RefreshInbox()
        end)
        listFrame.activityPeriodButton:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Cycle the time range shown in Activity and Player Journal timelines."); GameTooltip:Show() end)
        listFrame.activityPeriodButton:SetScript("OnLeave", GameTooltip_Hide)
        listFrame.sharedCompareButton = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
        listFrame.sharedCompareButton:SetSize(154, 20)
        listFrame.sharedCompareButton:SetPoint("TOPLEFT", right, "TOPLEFT", 4, -90)
        listFrame.sharedCompareButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        listFrame.sharedCompareButton:SetScript("OnClick", function(self, mouseButton)
            local selected = listFrame.selectedName
            if not selected then return end
            local summary = SC.GetJournalPlayerSummary and SC.GetJournalPlayerSummary(selected) or {}
            local partners = summary.allGroupPartners or summary.groupPartners or {}
            if #partners == 0 then return end
            local currentIndex = 0
            for i, partner in ipairs(partners) do
                if listFrame.comparePartner and SC.NameKey(partner.name) == SC.NameKey(listFrame.comparePartner) then currentIndex = i break end
            end
            if mouseButton == "RightButton" then
                currentIndex = currentIndex <= 1 and #partners or currentIndex - 1
            else
                currentIndex = currentIndex >= #partners and 1 or currentIndex + 1
            end
            listFrame.comparePartner = partners[currentIndex].name
            RefreshInbox()
        end)
        listFrame.sharedCompareButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Compare recorded group sessions", 1, 1, 1)
            GameTooltip:AddLine("Left-click: next shared group partner. Right-click: previous partner.", 0.75, 0.85, 1, true)
            GameTooltip:Show()
        end)
        listFrame.sharedCompareButton:SetScript("OnLeave", GameTooltip_Hide)
        listFrame.activityTypeButton:Hide(); listFrame.activityPeriodButton:Hide(); listFrame.sharedCompareButton:Hide()
        local line = right:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.35, 0.42, 0.52, 0.7)
        line:SetPoint("TOPLEFT", 4, -116)
        line:SetPoint("TOPRIGHT", -4, -116)
        line:SetHeight(1)
        listFrame.contentLine = line
        listFrame.transcriptScroll = CreateFrame("ScrollFrame", nil, right, "UIPanelScrollFrameTemplate")
        listFrame.transcriptScroll:SetPoint("TOPLEFT", 4, -125)
        listFrame.transcriptScroll:SetPoint("BOTTOMRIGHT", -22, 36)
        listFrame.transcriptScroll:EnableMouseWheel(true)
        listFrame.transcriptChild = CreateFrame("Frame", nil, listFrame.transcriptScroll)
        listFrame.transcriptScroll:SetScrollChild(listFrame.transcriptChild)
        listFrame.transcript = listFrame.transcriptChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        listFrame.transcript:SetPoint("TOPLEFT", 0, 0)
        listFrame.transcript:SetJustifyH("LEFT")
        listFrame.transcript:SetJustifyV("TOP")
        listFrame.transcript:SetWordWrap(true)
        listFrame.transcript:SetSpacing(2)
        listFrame.transcriptScroll:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll() or 0
            local maxScroll = math.max(0, (listFrame.transcriptChild:GetHeight() or 1) - (self:GetHeight() or 1))
            self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * 36)))
        end)
        local function makeActionButton(width, point, label, callback)
            local b = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
            b:SetSize(width, 23); b:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", point, 3); b:SetText(label)
            b:SetScript("OnClick", callback)
            return b
        end
        listFrame.favoriteButton = makeActionButton(82, 2, "+ Favorite", function()
            if listFrame.selectedName then SC.ToggleFavorite(listFrame.selectedName); RefreshInbox() end
        end)
        listFrame.pinButton = makeActionButton(68, 88, "+ Pin", function()
            if listFrame.selectedName then SC.ToggleContactPin(listFrame.selectedName); RefreshInbox() end
        end)
        listFrame.quickNoteButton = makeActionButton(88, 160, "Quick Note", function()
            if listFrame.selectedName and SC.ShowQuickNote then SC.ShowQuickNote(listFrame.selectedName) end
        end)
        listFrame.journalButton = makeActionButton(100, 252, "View History", function()
            if listFrame.category == "overview" and listFrame.mode == "overview" then
                listFrame.category = "activity"
                listFrame.mode = "profile"
                listFrame.profileSection = "overview"
            elseif listFrame.category == "activity" and listFrame.mode ~= "journal" then
                listFrame.mode = "journal"
                listFrame.profileSection = "history"
            elseif listFrame.category == "journal" then
                listFrame.category = "all"
                listFrame.mode = "profile"
                listFrame.profileSection = "overview"
            elseif listFrame.mode == "journal" then
                listFrame.mode = "profile"
                listFrame.profileSection = "overview"
            else
                listFrame.mode = "journal"
                listFrame.profileSection = "history"
            end
            RefreshInbox()
        end)
        listFrame.deleteNoteButton = makeActionButton(88, 356, "Delete Note", function()
            if listFrame.selectedName and SC.PromptDeleteContactNote then SC.PromptDeleteContactNote(listFrame.selectedName) end
        end)
        local open = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
        open:SetSize(118, 23)
        open:SetPoint("BOTTOMRIGHT", -4, 3)
        open:SetText("Open Whisper")
        open:SetScript("OnClick", function()
            local name = listFrame.selectedName
            if name then
                SC.OpenWhisperTab(name)
                listFrame:Hide()
            end
        end)
        listFrame.openButton = open
        BuildHubSettingsPanel()
    end

    if listFrame:IsShown() then listFrame:Hide(); return end
    if socialBtn then socialBtn.notify = false end
    if socialBtn and socialBtn.icon then socialBtn.icon:SetVertexColor(1, 1, 1, 1) end
    if not listFrame.guildRequested and IsInGuild and IsInGuild() then
        listFrame.guildRequested = true
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            pcall(C_GuildInfo.GuildRoster)
        elseif GuildRoster then
            pcall(GuildRoster)
        end
    end
    local chatWidth = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.GetWidth and DEFAULT_CHAT_FRAME:GetWidth() or 520
    local panelWidth = math.max(820, math.min(840, chatWidth + 320))
    listFrame:SetSize(panelWidth, 500)
    listFrame.left:SetWidth(190)
    listFrame.listChild:SetWidth(158)
    listFrame.header:SetWidth(panelWidth - 190 - 54)
    listFrame.details:SetWidth(panelWidth - 190 - 54)
    listFrame.category = listFrame.category or "overview"
    listFrame.mode = listFrame.mode or (listFrame.category == "overview" and "overview" or (listFrame.category == "guild" and "guild" or "profile"))
    if listFrame.category == "guild" and not listFrame.guildSection then listFrame.guildSection = "overview" end
    ApplySocialCategoryLayout()
    ApplyProfileSectionLayout()
    listFrame:ClearAllPoints()
    if whisperLayout and whisperLayout.active then
        listFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", whisperLayout.left, whisperLayout.bottom + 18)
    else
        listFrame:SetPoint("BOTTOMLEFT", DEFAULT_CHAT_FRAME or UIParent, "BOTTOMLEFT", 0, 18)
    end
    listFrame:Show()
    RefreshInbox()
    PopupShown(listFrame)
end
SC.RefreshWhisperInbox = RefreshInbox
SC.RefreshWhisperContacts = RefreshWhisperContacts
SC.ShowWhisperList = ShowList
SC.OnContactGroupRenamed = function(oldName, newName)
    if listFrame and listFrame.selectedGroup == oldName then listFrame.selectedGroup = newName end
    if listFrame and listFrame:IsShown() then RefreshInbox() end
end

function SC.ShowSocialPlayerJournal(name)
    if type(name) ~= "string" or name == "" then return end
    if not listFrame or not listFrame:IsShown() then ShowList() end
    if not listFrame or not listFrame:IsShown() then return end
    listFrame.category = "all"
    listFrame.mode = "profile"
    listFrame.profileSection = "history"
    listFrame.selectedName = name
    RefreshInbox()
end

---------------------------------------------------------------------
-- Incoming notifications (called from Chat.lua, secret-safe args)
---------------------------------------------------------------------
function SC.OnIncoming(tabId, event, author, alerted, allowSound, message)
    local isOutgoing = event == "CHAT_MSG_WHISPER_INFORM" or event == "CHAT_MSG_BN_WHISPER_INFORM"
    local isIncoming = event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER"
    local isBnetWhisper = event == "CHAT_MSG_BN_WHISPER" or event == "CHAT_MSG_BN_WHISPER_INFORM"
    -- Record ordinary whispers once on the Whisper stream and Battle.net
    -- whispers once on Global; the same contact list feeds both interfaces.
    local recordConversation = tabId == "whisper" or (isBnetWhisper and tabId == "global")
    if recordConversation and (isOutgoing or isIncoming) and author then
        TouchWhisper(author)
        if SC.RecordJournalWhisper then SC.RecordJournalWhisper(author, isIncoming) end
        local key = SC.NameKey(author)
        SC.whisperMessages[key] = SC.whisperMessages[key] or {}
        if message and type(message) == "string" then
            local bucket = SC.whisperMessages[key]
            bucket[#bucket + 1] = { text = message, out = isOutgoing, time = time() }
            while #bucket > 30 do table.remove(bucket, 1) end
        end
        SC.lastWhisper = author
        local selectedChanged = false
        if isOutgoing then
            SC.selectedWhisper = author
            SC.whisperUnread[key] = nil
            selectedChanged = true
        elseif not SC.selectedWhisper then
            SC.selectedWhisper = author
            selectedChanged = true
        end
        if isIncoming and (SC.active ~= "whisper" or SC.NameKey(SC.selectedWhisper or "") ~= key) then
            SC.whisperUnread[key] = (SC.whisperUnread[key] or 0) + 1
        end
        if selectedChanged and SC.db then SC.db.selectedWhisper = SC.selectedWhisper end
        if selectedChanged and SC.SetDisplay and SC.active == "whisper" then
            -- Keep the main Whisper tab filtered to the selected conversation.
            SC.SetDisplay("whisper", { cats = { whisper = true }, whisperWith = SC.selectedWhisper })
        end
        if RefreshWhisperContacts then RefreshWhisperContacts() end
        if listFrame and listFrame:IsShown() then RefreshInbox() end
    end
    if isOutgoing then return end
    if author and SC.NameKey(author) == SC.NameKey(SC.PlayerDisplayName("player")) then return end
    if SC.db.hidden[tabId] then return end

    local target = tabs[tabId]
    if tabId == "whisper" or (isBnetWhisper and isIncoming) then
        if tabId == "whisper" then target = tabs.whisper end
        if socialBtn then
            socialBtn.notify = true
            if socialBtn.icon then socialBtn.icon:SetVertexColor(1, 0.35, 0.35, 1) end
        end
    end
    if target and SC.active ~= target.id then
        Flash(target)
        if SC.db.unread then
            target.unread = (target.unread or 0) + 1
            if alerted then target.alert = true end
            RefreshLabel(target)
            SC.Layout()
        end
    end
    if not allowSound or SC.db.soundNotificationsEnabled == false then return end
    if alerted then
        local volume = SC.GetSoundVolume and SC.GetSoundVolume(tabId) or 1
        SC.PlayKit(SC.db.alertSound, volume)
    elseif SC.db.sound[tabId] then
        PlayFor(tabId)
    end
end

---------------------------------------------------------------------
-- Reorder: middle-click a tab, then scroll
---------------------------------------------------------------------
local OV_ROWS = 7

SaveOrder = function()
    local newOrder, seen = {}, {}
    for _, id in ipairs(runtime) do
        if SC.TABS[id] then newOrder[#newOrder + 1] = id; seen[id] = true end
    end
    for _, id in ipairs(SC.db.order) do
        if SC.TABS[id] and not seen[id] then newOrder[#newOrder + 1] = id end
    end
    SC.db.order = newOrder
end

local function RefreshOverlay()
    if not overlay or not overlay.tabId then return end
    local n = #runtime
    local idx
    for i, id in ipairs(runtime) do if id == overlay.tabId then idx = i break end end
    if not idx then return end

    if SC.db.reorderStyle == "moving" then
        -- whole list, the gold marker moves through it
        local shown = math.min(n, OV_ROWS)
        local first = overlay.scrollTop or 1
        if idx < first then first = idx
        elseif idx > first + shown - 1 then first = idx - shown + 1 end
        first = math.max(1, math.min(first, n - shown + 1))
        overlay.scrollTop = first
        for r = 1, OV_ROWS do
            local fs = overlay.rows[r]
            local id = (r <= shown) and runtime[first + r - 1] or nil
            local t = id and tabs[id]
            if t then
                if id == overlay.tabId then
                    fs:SetText("> " .. t.label .. " <"); fs:SetTextColor(1, 0.82, 0)
                else
                    fs:SetText(t.label); fs:SetTextColor(0.65, 0.65, 0.65)
                end
            else
                fs:SetText("")
            end
        end
        overlay:SetHeight(shown * 18 + 8 + 16)
    else
        -- fixed: the grabbed tab stays in the middle, the others move around it
        for r = 1, OV_ROWS do
            local fs = overlay.rows[r]
            if r <= 5 then
                local id = runtime[idx + r - 3]
                local t = id and tabs[id]
                if r == 3 then
                    fs:SetText("> " .. tabs[overlay.tabId].label .. " <"); fs:SetTextColor(1, 0.82, 0)
                elseif t then
                    fs:SetText(t.label); fs:SetTextColor(0.65, 0.65, 0.65)
                else
                    fs:SetText("")
                end
            else
                fs:SetText("")
            end
        end
        overlay:SetHeight(5 * 18 + 8 + 16)
    end
end

local function CloseReorder()
    if overlay and overlay:IsShown() then overlay:Hide() end
end

local function MoveTab(id, dir)
    for i, v in ipairs(runtime) do
        if v == id then
            local j = i + dir
            if j >= 1 and j <= #runtime then
                runtime[i], runtime[j] = runtime[j], runtime[i]
                SaveOrder()
                SC.Layout()
            end
            return
        end
    end
end

-- Move a tab directly onto another tab (drag-and-drop).
function SC.MoveTabTo(sourceId, targetId)
    if not sourceId or not targetId or sourceId == targetId then return false end
    local from, to
    for i, id in ipairs(runtime) do
        if id == sourceId then from = i end
        if id == targetId then to = i end
    end
    if not from or not to then return false end
    local target = tabs[targetId]
    local insertBefore = true
    if target and GetCursorPosition then
        local mouseX = GetCursorPosition() / (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1)
        local centerX = target:GetCenter()
        if centerX then insertBefore = mouseX < centerX end
    end
    local moving = table.remove(runtime, from)
    -- Re-find the target after removing the dragged tab, then insert before/after
    -- according to which half of the target the mouse was released over.
    to = nil
    for i, id in ipairs(runtime) do if id == targetId then to = i break end end
    if not to then return false end
    table.insert(runtime, insertBefore and to or (to + 1), moving)
    SaveOrder()
    SC.Layout()
    return true
end

-- Reorder by the horizontal release position. This also works when the
-- cursor is released in the gap between tabs, not only directly over a tab.
function SC.MoveTabToPosition(sourceId, cursorX)
    if not sourceId or type(cursorX) ~= "number" then return false end
    local reordered, found = {}, false
    for _, id in ipairs(runtime) do
        if id == sourceId then found = true else reordered[#reordered + 1] = id end
    end
    if not found then return false end

    local insertAt = #reordered + 1
    for i, id in ipairs(reordered) do
        local frame = tabs[id]
        if frame then
            local left, right = frame:GetLeft(), frame:GetRight()
            if left and right and cursorX < ((left + right) / 2) then
                insertAt = i
                break
            end
        end
    end
    table.insert(reordered, insertAt, sourceId)
    wipe(runtime)
    for _, id in ipairs(reordered) do runtime[#runtime + 1] = id end
    SaveOrder()
    SC.Layout()
    return true
end

function StartReorder(id)
    if not overlay then
        overlay = CreateFrame("Frame", "SmartChatReorder", UIParent, "BackdropTemplate")
        overlay:SetFrameStrata("FULLSCREEN_DIALOG")
        overlay:SetSize(150, OV_ROWS * 18 + 8 + 16)
        overlay:EnableMouse(true)
        overlay:EnableMouseWheel(true)
        overlay:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        overlay:SetBackdropColor(0.03, 0.03, 0.03, 0.96)
        overlay:SetBackdropBorderColor(1, 0.82, 0, 1)
        overlay.rows = {}
        for i = 1, OV_ROWS do
            local fs = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetPoint("TOP", 0, -4 - (i - 1) * 18)
            overlay.rows[i] = fs
        end
        local hint = overlay:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("BOTTOM", 0, 4)
        hint:SetText("scroll = move | click = done")
        overlay:SetScript("OnMouseWheel", function(self, delta)
            MoveTab(self.tabId, delta > 0 and -1 or 1)
            RefreshOverlay()
        end)
        overlay:SetScript("OnMouseDown", CloseReorder)
        overlay:SetScript("OnHide", function(self)
            self.tabId = nil
            if catcher then catcher:Hide() end
            SaveOrder()
        end)
        WatchMouse(overlay, 0.6)
        tinsert(UISpecialFrames, "SmartChatReorder")
    end
    if overlay:IsShown() then CloseReorder() return end
    local t = tabs[id]
    local x, y = t:GetCenter()
    overlay.tabId = id
    overlay.scrollTop = nil
    overlay:ClearAllPoints()
    overlay:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y + (SC.db.reorderStyle == "moving" and 0 or 8))
    overlay:Show()
    PopupShown(overlay)
    RefreshOverlay()
end

function SC.MoveTabBy(id, dir)
    MoveTab(id, dir)
    SaveOrder()
end

---------------------------------------------------------------------
-- Copy chat text
---------------------------------------------------------------------
local function StripCodes(s)
    s = s:gsub("|K.-|k", "?")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|A.-|a", "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    return s
end

local function ShowCopy()
    if not copyFrame then
        copyFrame = CreateFrame("Frame", "SmartChatCopy", UIParent, "BackdropTemplate")
        copyFrame:SetSize(460, 340)
        copyFrame:SetPoint("CENTER")
        copyFrame:SetFrameStrata("DIALOG")
        copyFrame:SetMovable(true)
        copyFrame:EnableMouse(true)
        copyFrame:RegisterForDrag("LeftButton")
        copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
        copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
        copyFrame:SetBackdrop({
            -- The stock dialog background artwork is translucent even at alpha 1.
            -- A solid WHITE8X8 base lets the SmartChat opacity slider control the
            -- actual background opacity from fully opaque down to transparent.
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
        copyFrame:SetToplevel(true)
        SC.RegisterWindow(copyFrame, { 0.035, 0.040, 0.055, 1 }, { 0.55, 0.55, 0.60, 1 })
        local title = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 20, -16)
        title:SetText("Copy chat  -  Ctrl+C to copy, Esc to close")
        local close = CreateFrame("Button", nil, copyFrame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        local sf = CreateFrame("ScrollFrame", "SmartChatCopyScroll", copyFrame, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 18, -40)
        sf:SetPoint("BOTTOMRIGHT", -36, 16)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal or GameFontHighlight)
        eb:SetWidth(400)
        eb:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
        sf:SetScrollChild(eb)
        copyFrame.eb = eb
        copyFrame.sf = sf
        tinsert(UISpecialFrames, "SmartChatCopy")
    end
    local frame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
    local lines, skipped = {}, 0
    local ok, n = pcall(frame.GetNumMessages, frame)
    if not ok or type(n) ~= "number" then
        SC.Print("copy is not available on this client")
        return
    end
    for i = math.max(1, n - 300 + 1), n do
        local ok2, text = pcall(frame.GetMessageInfo, frame, i)
        if ok2 and text and not SC.IsSecret(text) and type(text) == "string" then
            lines[#lines + 1] = StripCodes(text)
        else
            skipped = skipped + 1
        end
    end
    local body = table.concat(lines, "\n")
    if skipped > 0 then body = body .. "\n[" .. skipped .. " hidden lines skipped]" end
    copyFrame.eb:SetText(body)
    copyFrame.eb:SetHeight(math.max(250, (#lines + 2) * 14))
    copyFrame:Show()
    copyFrame.eb:SetFocus()
    copyFrame.eb:HighlightText()
end

SC.ShowCopy = ShowCopy

---------------------------------------------------------------------
-- Build / rebuild
---------------------------------------------------------------------
function SC.RebuildTabs()
    local db = SC.db
    if type(db.whisperContacts) ~= "table" then db.whisperContacts = {} end
    SC.whisperList = db.whisperContacts
    SC.selectedWhisper = type(db.selectedWhisper) == "string" and db.selectedWhisper or SC.selectedWhisper
    SC.lastWhisper = SC.lastWhisper or SC.selectedWhisper
    local seen, order = {}, {}
    for _, id in ipairs(db.order) do
        if SC.TABS[id] and not seen[id] then order[#order + 1] = id; seen[id] = true end
    end
    -- Existing installations get Global beside Say rather than appended after
    -- every tab in their saved custom order.
    if not seen.global then
        local insertAt = 1
        for i, id in ipairs(order) do if id == "say" then insertAt = i + 1; break end end
        table.insert(order, insertAt, "global")
        seen.global = true
    end
    for _, id in ipairs(SC.defaultOrder) do
        if not seen[id] then order[#order + 1] = id end
    end
    db.order = order

    local dyn = {}
    for _, id in ipairs(runtime) do if tabs[id] and tabs[id].def.dynamic then dyn[#dyn + 1] = id end end

    -- frames of custom tabs that were removed
    for id, t in pairs(tabs) do
        if not t.def.dynamic and not SC.TABS[id] then
            StopFlash(t)
            t:Hide()
            tabs[id] = nil
        end
    end

    wipe(runtime)
    for _, id in ipairs(order) do
        if not tabs[id] then CreateTab(id, SC.TABS[id]) end
        if db.hidden[id] then tabs[id]:Hide() else runtime[#runtime + 1] = id end
    end
    for _, id in ipairs(dyn) do runtime[#runtime + 1] = id end
    for _, t in pairs(tabs) do UpdateSpeaker(t); RefreshLabel(t) end
    SC.Layout()
    if not (SC.active and tabs[SC.active] and tabs[SC.active]:IsShown()) then
        SC.SetActive(db.activeTab, false)
    end
end

function SC.ApplyBarAlpha()
    if bar and bar.bg then bar.bg:SetColorTexture(0, 0, 0, SC.db.barAlpha) end
end

function SC.PositionBar()
    if not bar then return end
    bar:ClearAllPoints()
    if whisperLayout and whisperLayout.active then
        bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
            whisperLayout.left + SC.db.barX, whisperLayout.top + SC.db.barY)
        PositionWhisperContactPane()
    else
        bar:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", SC.db.barX, SC.db.barY)
    end
end

function SC.PositionDock()
    if not dock then return end
    dock:ClearAllPoints()
    -- The utility icons stay beside the full chat window while Whisper is active.
    if whisperLayout and whisperLayout.active then
        dock:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", whisperLayout.left - 4, whisperLayout.top)
    else
        dock:SetPoint("TOPRIGHT", ChatFrame1, "TOPLEFT", -4, 0)
    end
    dock:SetShown(SC.db.showDock ~= false)
end

function SC.ApplyDockVisibility()
    if dock then dock:SetShown(SC.db.showDock ~= false) end
end

local function CreateDockButton(parent, texture, tooltip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)

    if texture == "SMARTCHAT_KEYBOARD_ICON" then
        -- Draw a small keyboard from standard solid textures so the shortcut
        -- button is visible even if a client build lacks a keyboard icon asset.
        local outer = b:CreateTexture(nil, "ARTWORK")
        outer:SetTexture("Interface\\Buttons\\WHITE8X8")
        outer:SetSize(22, 16)
        outer:SetPoint("CENTER", b, "CENTER", 0, 0)
        outer:SetColorTexture(0.08, 0.09, 0.11, 1)

        local face = b:CreateTexture(nil, "ARTWORK")
        face:SetTexture("Interface\\Buttons\\WHITE8X8")
        face:SetSize(20, 14)
        face:SetPoint("CENTER", outer, "CENTER")
        face:SetColorTexture(0.78, 0.82, 0.88, 1)

        local function KeyCap(x, y, w, h)
            local cap = b:CreateTexture(nil, "OVERLAY")
            cap:SetTexture("Interface\\Buttons\\WHITE8X8")
            cap:SetSize(w, h)
            cap:SetPoint("CENTER", face, "CENTER", x, y)
            cap:SetColorTexture(0.13, 0.16, 0.20, 1)
            return cap
        end
        for _, y in ipairs({ 3, -1 }) do
            for _, x in ipairs({ -6, -2, 2, 6 }) do
                KeyCap(x, y, 2.8, 2.1)
            end
        end
        KeyCap(0, -5, 8.5, 1.8)
        b.keyboardParts = { outer, face }
    else
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.icon:SetTexture(texture)
    end

    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

local function ShowChannelList()
    if not channelFrame then
        channelFrame = CreateFrame("Frame", "SmartChatChannelList", UIParent, "BackdropTemplate")
        channelFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        channelFrame:SetWidth(176)
        channelFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        channelFrame:SetBackdropColor(0.04, 0.04, 0.05, 0.96)
        channelFrame:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
        channelFrame.rows = {}
        channelFrame.title = channelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        channelFrame.title:SetPoint("TOPLEFT", 9, -8)
        channelFrame.title:SetText("Chat channels")
        channelFrame:SetScript("OnHide", function() if catcher then catcher:Hide() end end)
        WatchMouse(channelFrame, 0.8, channelBtn)
        tinsert(UISpecialFrames, "SmartChatChannelList")
    end
    if channelFrame:IsShown() then channelFrame:Hide(); return end
    for _, row in ipairs(channelFrame.rows) do row:Hide() end
    local y = -28
    local rowIndex = 0
    for _, id in ipairs(runtime) do
        local tab = tabs[id]
        if tab then
            rowIndex = rowIndex + 1
            local row = channelFrame.rows[rowIndex]
            if not row then
                row = CreateFrame("Button", nil, channelFrame)
                row:SetHeight(21)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", 7, 0)
                row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
                row.highlight:SetAllPoints()
                row.highlight:SetColorTexture(1, 1, 1, 0.12)
                row:SetScript("OnClick", function(self)
                    channelFrame:Hide()
                    SC.SetActive(self.tabId)
                end)
                row:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.label)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", GameTooltip_Hide)
                channelFrame.rows[#channelFrame.rows + 1] = row
            end
            row.tabId, row.label = id, tab.label
            row.text:SetText((SC.active == id and "|cffffd100â¢ |r" or "  ") .. tab.label)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 3, y)
            row:SetPoint("TOPRIGHT", -3, y)
            row:Show()
            y = y - 21
        end
    end
    for i = rowIndex + 1, #channelFrame.rows do channelFrame.rows[i]:Hide() end
    channelFrame:SetHeight(math.max(52, -y + 5))
    channelFrame:ClearAllPoints()
    channelFrame:SetPoint("TOPLEFT", channelBtn, "TOPRIGHT", 4, 0)
    channelFrame:Show()
    PopupShown(channelFrame)
end
SC.ShowChannelList = ShowChannelList

table.insert(SC.onLogin, function()
    bar = CreateFrame("Frame", "SmartChatBar", UIParent)
    bar:SetHeight(26)
    bar:SetFrameStrata("MEDIUM")
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    SC.bar = bar
    SC.PositionBar()

    dock = CreateFrame("Frame", "SmartChatDock", UIParent, "BackdropTemplate")
    dock:SetFrameStrata("MEDIUM")
    dock:SetSize(28, 145)
    dock:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    dock:SetBackdropColor(0.015, 0.015, 0.02, 0.58)
    dock:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    dock:SetClampedToScreen(true)
    SC.dock = dock

    local function PlaceDockButton(button, index)
        button:ClearAllPoints()
        button:SetPoint("TOP", dock, "TOP", 0, -3 - (index - 1) * 28)
    end

    channelBtn = CreateDockButton(dock, "Interface\\Icons\\INV_Misc_ChatChannel", "Chat channels", ShowChannelList)
    PlaceDockButton(channelBtn, 1)

    socialBtn = CreateDockButton(dock, "Interface\\Icons\\INV_Misc_GroupLooking", "Social Hub", ShowList)
    PlaceDockButton(socialBtn, 2)

    settingsBtn = CreateDockButton(dock, "Interface\\Buttons\\UI-OptionsButton", "SmartChat settings", function()
        if SC.ToggleSettings then SC.ToggleSettings() end
    end)
    PlaceDockButton(settingsBtn, 3)

    shortcutBtn = CreateDockButton(dock, "SMARTCHAT_KEYBOARD_ICON", "Keyboard shortcuts", function()
        if SC.ShowBindingsPanel then SC.ShowBindingsPanel() end
    end)
    PlaceDockButton(shortcutBtn, 4)

    copyBtn = CreateDockButton(dock, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", "Copy recent chat", ShowCopy)
    PlaceDockButton(copyBtn, 5)

    newBtn = CreateDockButton(dock, "Interface\\Buttons\\UI-PlusButton-Up", "Create a new chat tab", function(self)
        if SC.ShowNewTabMenu then SC.ShowNewTabMenu(self) end
    end)
    PlaceDockButton(newBtn, 6)

    dock:SetHeight(6 * 28 + 6)
    SC.PositionDock()

    SC.ApplyBarAlpha()
    CreateWhisperContactPane()
    if ChatFrame1 and ChatFrame1.HookScript then
        ChatFrame1:HookScript("OnSizeChanged", function(frame)
            if whisperLayout and whisperLayout.active and not whisperLayout.applying then
                -- Keep the narrow contact rail fitted if the chat frame is resized
                -- while Whisper is active.
                local left, right = frame:GetLeft(), frame:GetRight()
                local top, bottom = frame:GetTop(), frame:GetBottom()
                if left and right and top and bottom then
                    whisperLayout.left = left - whisperLayout.sideWidth - WHISPER_PANE_GAP
                    whisperLayout.right, whisperLayout.top, whisperLayout.bottom = right, top, bottom
                    whisperLayout.width = right - whisperLayout.left
                    whisperLayout.height = top - bottom
                    whisperLayout.userAdjusted = true
                    PositionWhisperContactPane()
                    if SC.PositionBar then SC.PositionBar() end
                    if SC.PositionDock then SC.PositionDock() end
                end
            end
        end)
    end
    SC.RebuildTabs()
    if SC.db.chatAlpha then C_Timer.After(1, function() SC.ApplyChatAlpha(SC.db.chatAlpha) end) end

    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb then
            eb:HookScript("OnShow", OnBoxShow)
            eb:HookScript("OnHide", function(self) Apply(self) end)
        end
    end
end)
