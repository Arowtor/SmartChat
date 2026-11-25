local ADDON, SC = ...

---------------------------------------------------------------------
-- Social data helpers: Favorites, pins, private contact groups and notes.
-- All data is local to SavedVariables. No network requests are made.
---------------------------------------------------------------------
local function EnsureSocial()
    SC.db.social = SC.db.social or {}
    local s = SC.db.social
    s.favorites = s.favorites or {}
    s.pinned = s.pinned or {}
    s.groups = s.groups or {}
    s.groupOrder = s.groupOrder or {}
    s.groupTemplates = s.groupTemplates or {}
    s.groupTemplateOrder = s.groupTemplateOrder or {}
    s.sortMode = s.sortMode or "status"
    s.onlineOnly = s.onlineOnly and true or false
    return s
end

local function EnsureJournal()
    SC.db.journal = SC.db.journal or {}
    local j = SC.db.journal
    if j.enabled == nil then j.enabled = false end
    if j.trackFriends == nil then j.trackFriends = true end
    if j.trackGuild == nil then j.trackGuild = true end
    if j.trackGroups == nil then j.trackGroups = true end
    if j.trackWhispers == nil then j.trackWhispers = true end
    if j.trackQuests == nil then j.trackQuests = false end
    if j.trackPresence == nil then j.trackPresence = false end
    if j.trackGuildPresence == nil then j.trackGuildPresence = false end
    if j.trackGroupRoster == nil then j.trackGroupRoster = false end
    if type(j.retentionDays) ~= "number" then j.retentionDays = 90 end
    if type(j.maxEvents) ~= "number" then j.maxEvents = 500 end
    j.timelineType = j.timelineType or "all"
    j.timelineDays = tonumber(j.timelineDays) or 0
    j.events = j.events or {}
    j.notes = j.notes or {}
    j.friendSnapshot = j.friendSnapshot or nil
    j.guildSnapshot = j.guildSnapshot or nil
    return j
end

local function EnsureNotifications()
    SC.db.socialNotifications = SC.db.socialNotifications or {}
    local n = SC.db.socialNotifications
    if n.enabled == nil then n.enabled = false end
    if n.friendOnline == nil then n.friendOnline = true end
    if n.friendOffline == nil then n.friendOffline = false end
    if n.friendChanges == nil then n.friendChanges = true end
    if n.guildChanges == nil then n.guildChanges = false end
    if n.guildPresence == nil then n.guildPresence = false end
    if n.groupChanges == nil then n.groupChanges = false end
    if n.bnetPresence == nil then n.bnetPresence = false end
    return n
end

local DEFAULT_GROUPS = { "Dungeon Buddies", "Raid Team", "Trading Partners", "Old Friends" }
local function InitializeGroups()
    local s = EnsureSocial()
    for _, name in ipairs(DEFAULT_GROUPS) do
        if type(s.groups[name]) ~= "table" then s.groups[name] = {} end
        local found = false
        for _, existing in ipairs(s.groupOrder) do if existing == name then found = true break end end
        if not found then s.groupOrder[#s.groupOrder + 1] = name end
    end
end

local function Key(name)
    return SC.NameKey and SC.NameKey(name) or tostring(name or ""):lower()
end

-- Ephemeral index only: this is rebuilt from SavedVariables on demand and is
-- never persisted. It keeps Whisper metadata aggregation O(1) per message.
local whisperEventIndex, whisperEventIndexReady = {}, false
local function RebuildWhisperEventIndex()
    wipe(whisperEventIndex)
    local events = EnsureJournal().events
    for i = 1, #events do
        local event = events[i]
        if type(event) == "table" and event.type == "whisper" then
            for _, name in ipairs(event.names or {}) do
                local key = Key(name)
                if key ~= "" then
                    local previous = whisperEventIndex[key]
                    local stamp = tonumber(event.last) or tonumber(event.t) or 0
                    local previousStamp = previous and (tonumber(previous.last) or tonumber(previous.t) or 0) or -1
                    if not previous or stamp >= previousStamp then whisperEventIndex[key] = event end
                end
            end
        end
    end
    whisperEventIndexReady = true
end

---------------------------------------------------------------------
-- Lightweight, opt-in social notification toast. Event-driven only;
-- no OnUpdate polling and no network activity.
---------------------------------------------------------------------
local toastFrame, toastQueue, toastBusy, toastSerial = nil, {}, false, 0
local DisplayNextToast
local function EnsureSocialToast()
    if toastFrame then return toastFrame end
    toastFrame = CreateFrame("Button", "SmartChatSocialNotification", UIParent, "BackdropTemplate")
    toastFrame:SetSize(300, 72)
    toastFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -26, -170)
    toastFrame:SetFrameStrata("DIALOG")
    toastFrame:SetFrameLevel(220)
    toastFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    toastFrame:SetBackdropColor(0.035, 0.045, 0.065, 0.97)
    toastFrame:SetBackdropBorderColor(0.25, 0.55, 0.78, 0.95)
    toastFrame.title = toastFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    toastFrame.title:SetPoint("TOPLEFT", 12, -10)
    toastFrame.title:SetPoint("TOPRIGHT", -12, -10)
    toastFrame.title:SetJustifyH("LEFT")
    toastFrame.body = toastFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    toastFrame.body:SetPoint("TOPLEFT", toastFrame.title, "BOTTOMLEFT", 0, -5)
    toastFrame.body:SetPoint("TOPRIGHT", toastFrame.title, "BOTTOMRIGHT", 0, -5)
    toastFrame.body:SetJustifyH("LEFT")
    toastFrame.body:SetWordWrap(true)
    toastFrame:SetScript("OnClick", function(self)
        self:Hide()
        toastSerial = toastSerial + 1
        toastBusy = false
        if SC.ShowWhisperList then SC.ShowWhisperList() end
        DisplayNextToast()
    end)
    toastFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("SmartChat Social Hub", 1, 1, 1)
        GameTooltip:AddLine("Click to open Social Hub", 0.75, 0.85, 1)
        GameTooltip:Show()
    end)
    toastFrame:SetScript("OnLeave", GameTooltip_Hide)
    toastFrame:Hide()
    return toastFrame
end

DisplayNextToast = function()
    if toastBusy or #toastQueue == 0 then return end
    toastBusy = true
    local item = table.remove(toastQueue, 1)
    local frame = EnsureSocialToast()
    toastSerial = toastSerial + 1
    local serial = toastSerial
    frame.title:SetText(item.title or "Social Activity")
    frame.body:SetText(item.detail or "")
    frame:Show()
    C_Timer.After(5, function()
        if not frame or not frame:IsShown() or serial ~= toastSerial then return end
        frame:Hide()
        toastBusy = false
        DisplayNextToast()
    end)
end

function SC.NotifySocial(kind, title, detail)
    if not SC.db then return false end
    local n = EnsureNotifications()
    if not n.enabled or n[kind] ~= true then return false end
    if #toastQueue >= 4 then table.remove(toastQueue, 1) end
    toastQueue[#toastQueue + 1] = { title = title, detail = detail }
    DisplayNextToast()
    return true
end

function SC.IsSocialNotificationsEnabled()
    return EnsureNotifications().enabled and true or false
end

function SC.IsFavorite(name)
    local s = EnsureSocial()
    return name and s.favorites[Key(name)] ~= nil or false
end

function SC.IsContactPinned(name)
    local s = EnsureSocial()
    return name and s.pinned[Key(name)] ~= nil or false
end

function SC.ToggleFavorite(name)
    if type(name) ~= "string" or name == "" then return false end
    local s, key = EnsureSocial(), Key(name)
    if s.favorites[key] then s.favorites[key] = nil else s.favorites[key] = name end
    if SC.RefreshWhisperInbox then SC.RefreshWhisperInbox() end
    return s.favorites[key] ~= nil
end

function SC.ToggleContactPin(name)
    if type(name) ~= "string" or name == "" then return false end
    local s, key = EnsureSocial(), Key(name)
    if s.pinned[key] then s.pinned[key] = nil else s.pinned[key] = name end
    if SC.RefreshWhisperInbox then SC.RefreshWhisperInbox() end
    return s.pinned[key] ~= nil
end

function SC.GetContactGroups(name)
    local s, result, key = EnsureSocial(), {}, Key(name)
    for _, groupName in ipairs(s.groupOrder) do
        local group = s.groups[groupName]
        if type(group) == "table" and group[key] then result[#result + 1] = groupName end
    end
    return result
end

function SC.CreateContactGroup(name)
    if type(name) ~= "string" then return false end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false end
    if #name > 24 then name = name:sub(1, 24) end
    local s = EnsureSocial()
    if s.groups[name] then return false end
    if #s.groupOrder >= 30 then return false end
    s.groups[name] = {}
    s.groupOrder[#s.groupOrder + 1] = name
    if SC.RefreshWhisperInbox then SC.RefreshWhisperInbox() end
    return true
end

function SC.DeleteContactGroup(groupName)
    if type(groupName) ~= "string" or groupName == "" then return false end
    local s = EnsureSocial()
    if not s.groups[groupName] then return false end
    s.groups[groupName] = nil
    for i = #s.groupOrder, 1, -1 do
        if s.groupOrder[i] == groupName then table.remove(s.groupOrder, i) end
    end
    if SC.RefreshWhisperInbox then SC.RefreshWhisperInbox() end
    return true
end

function SC.RenameContactGroup(oldName, newName)
    if type(oldName) ~= "string" or type(newName) ~= "string" then return false, "Invalid group name." end
    newName = newName:gsub("^%s+", ""):gsub("%s+$", "")
    if newName == "" then return false, "Group name cannot be empty." end
    if #newName > 24 then newName = newName:sub(1, 24) end
    local s = EnsureSocial()
    if type(s.groups[oldName]) ~= "table" then return false, "The selected group no longer exists." end
    if oldName == newName then return true end
    local wanted = newName:lower()
    for existing in pairs(s.groups) do
        if existing ~= oldName and tostring(existing):lower() == wanted then
            return false, "A group with that name already exists."
        end
    end
    local members = s.groups[oldName]
    s.groups[oldName] = nil
    s.groups[newName] = members
    for i, groupName in ipairs(s.groupOrder) do
        if groupName == oldName then s.groupOrder[i] = newName end
    end
    if SC.OnContactGroupRenamed then
        SC.OnContactGroupRenamed(oldName, newName)
    elseif SC.RefreshWhisperInbox then
        SC.RefreshWhisperInbox()
    end
    return true
end

function SC.GetContactGroupStats()
    local s = EnsureSocial()
    local groupCount, memberLinks, uniqueMembers = 0, 0, {}
    for _, groupName in ipairs(s.groupOrder or {}) do
        local members = s.groups[groupName]
        if type(members) == "table" then
            groupCount = groupCount + 1
            for key, name in pairs(members) do
                if name then
                    memberLinks = memberLinks + 1
                    uniqueMembers[key] = true
                end
            end
        end
    end
    local uniqueCount = 0
    for _ in pairs(uniqueMembers) do uniqueCount = uniqueCount + 1 end
    return groupCount, memberLinks, uniqueCount
end

function SC.ToggleContactGroup(name, groupName)
    if type(name) ~= "string" or type(groupName) ~= "string" then return false end
    local s = EnsureSocial()
    if type(s.groups[groupName]) ~= "table" then s.groups[groupName] = {}; s.groupOrder[#s.groupOrder + 1] = groupName end
    local group, key = s.groups[groupName], Key(name)
    if group[key] then group[key] = nil else group[key] = name end
    if SC.RefreshWhisperInbox then SC.RefreshWhisperInbox() end
    return group[key] ~= nil
end

function SC.GetSocialStats()
    local s = EnsureSocial()
    local friends, online = 0, 0
    local api = C_FriendList
    if api and api.GetNumFriends then
        local ok, count = pcall(api.GetNumFriends)
        if ok and type(count) == "number" then friends = count end
    end
    if api and api.GetNumOnlineFriends then
        local ok, count = pcall(api.GetNumOnlineFriends)
        if ok and type(count) == "number" then online = count
        elseif api.GetFriendInfoByIndex then
            for i = 1, friends do
                local okInfo, info = pcall(api.GetFriendInfoByIndex, i)
                if okInfo and type(info) == "table" and info.connected then online = online + 1 end
            end
        end
    elseif api and api.GetFriendInfoByIndex then
        for i = 1, friends do
            local okInfo, info = pcall(api.GetFriendInfoByIndex, i)
            if okInfo and type(info) == "table" and info.connected then online = online + 1 end
        end
    end
    local guildCount = IsInGuild and IsInGuild() and GetNumGuildMembers and (GetNumGuildMembers() or 0) or 0
    local ignored = 0
    if api and api.GetNumIgnores then
        local ok, count = pcall(api.GetNumIgnores)
        if ok and type(count) == "number" then ignored = count end
    end
    local unread = 0
    for _, count in pairs(SC.whisperUnread or {}) do unread = unread + (tonumber(count) or 0) end
    return friends, online, guildCount, unread, #((SC.whisperList) or {}), ignored
end

function SC.GetSocialOverviewStats()
    local friends, online, guild, unread, whispers, ignored = SC.GetSocialStats()
    local social, journal = EnsureSocial(), EnsureJournal()
    local favorites, pinned = 0, 0
    for _ in pairs(social.favorites or {}) do favorites = favorites + 1 end
    for _ in pairs(social.pinned or {}) do pinned = pinned + 1 end
    local groupCount, groupLinks, uniqueGroupMembers = SC.GetContactGroupStats()
    local notes = 0
    for _, note in pairs(journal.notes or {}) do
        if type(note) == "table" and ((note.text and note.text ~= "") or (note.tags and #note.tags > 0)) then notes = notes + 1 end
    end
    return {
        friends = friends or 0, onlineFriends = online or 0, guildMembers = guild or 0,
        unreadWhispers = unread or 0, whisperContacts = whispers or 0, ignored = ignored or 0,
        favorites = favorites, pinned = pinned, groups = groupCount,
        groupMemberLinks = groupLinks, uniqueGroupMembers = uniqueGroupMembers,
        notes = notes, journalEvents = #journal.events,
        journalEnabled = journal.enabled and true or false,
    }
end

---------------------------------------------------------------------
-- Player Journal: optional, local-only, event-driven and capped.
-- No polling loops, message text storage, or network traffic.
---------------------------------------------------------------------
local QUICK_TAGS = {
    "Helpful Player", "Friendly", "Good Tank", "Good Healer", "Good DPS",
    "Reliable", "Dungeon Friend", "Raid Teammate", "Good Trader", "Crafter",
    "Guild Contact", "PvP Partner", "Plays Evenings", "Good Leader",
    "Quest Partner", "Old Friend",
}
SC.JournalQuickTags = QUICK_TAGS

local function IsTrackingEnabled(kind)
    local j = EnsureJournal()
    if not j.enabled then return false end
    if kind == "friend" then return j.trackFriends end
    if kind == "guild" then return j.trackGuild end
    if kind == "group" then return j.trackGroups end
    if kind == "whisper" then return j.trackWhispers end
    if kind == "quest" then return j.trackQuests end
    return true
end

local function EventMatchesName(event, key)
    if not event or type(event.names) ~= "table" then return false end
    for _, name in ipairs(event.names) do if Key(name) == key then return true end end
    return false
end

function SC.PruneJournal()
    local j = EnsureJournal()
    local now = time()
    local keepDays = math.max(0, tonumber(j.retentionDays) or 90)
    local cutoff = keepDays > 0 and (now - keepDays * 86400) or nil
    local removed = false
    for i = #j.events, 1, -1 do
        local e = j.events[i]
        local newest = type(e) == "table" and (tonumber(e.last) or tonumber(e.t) or 0) or 0
        if type(e) ~= "table" or (cutoff and newest < cutoff) then
            table.remove(j.events, i)
            removed = true
        end
    end
    local maxEvents = math.max(50, math.min(2000, tonumber(j.maxEvents) or 500))
    while #j.events > maxEvents do table.remove(j.events, 1); removed = true end
    if removed then whisperEventIndexReady = false; wipe(whisperEventIndex) end
end

function SC.AddJournalEvent(kind, names, title, detail, extra)
    local j = EnsureJournal()
    if not j.enabled then return false end
    local clean, seen = {}, {}
    if type(names) == "string" then names = { names } end
    for _, name in ipairs(names or {}) do
        if type(name) == "string" and name ~= "" then
            local key = Key(name)
            if key ~= "" and not seen[key] then clean[#clean + 1] = name; seen[key] = true end
        end
    end
    if #clean == 0 then return false end
    local event = { t = time(), type = kind, title = title or kind, detail = detail or "", names = clean }
    if type(extra) == "table" then
        for k, v in pairs(extra) do
            if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then event[k] = v end
        end
    end
    j.events[#j.events + 1] = event
    if kind == "whisper" then
        for _, name in ipairs(clean) do whisperEventIndex[Key(name)] = event end
        whisperEventIndexReady = true
    end
    SC.PruneJournal()
    return true
end

function SC.RecordJournalWhisper(name, incoming)
    if not IsTrackingEnabled("whisper") or type(name) ~= "string" then return end
    local j, key, now = EnsureJournal(), Key(name), time()
    if key == "" then return end
    if not whisperEventIndexReady then RebuildWhisperEventIndex() end
    local last = whisperEventIndex[key]
    local lastStamp = last and (tonumber(last.last) or tonumber(last.t) or 0) or 0
    if last and (now - lastStamp) >= 0 and (now - lastStamp) <= 900 then
        last.last = now
        last.count = (tonumber(last.count) or 1) + 1
        if incoming then last.incoming = (tonumber(last.incoming) or 0) + 1 else last.outgoing = (tonumber(last.outgoing) or 0) + 1 end
    else
        SC.AddJournalEvent("whisper", { name }, "Whisper interaction", "Message content is not stored.", {
            last = now, count = 1, incoming = incoming and 1 or 0, outgoing = incoming and 0 or 1,
        })
    end
end

local JOURNAL_FILTERS = {
    social = { friend = true, guild = true, guild_context = true, group_member = true, presence = true, guild_presence = true, bnet_presence = true },
    group = { group = true, group_member = true },
    communication = { whisper = true },
    presence = { presence = true, guild_presence = true, bnet_presence = true },
    guild = { guild = true, guild_context = true },
    notes = { note = true },
    quests = { quest = true },
}

local function JournalEventMatches(event, typeFilter, days)
    if typeFilter and typeFilter ~= "all" then
        local allowed = JOURNAL_FILTERS[typeFilter]
        if allowed then
            if not allowed[event.type] then return false end
        elseif event.type ~= typeFilter then
            return false
        end
    end
    days = tonumber(days) or 0
    if days > 0 and (tonumber(event.last) or tonumber(event.t) or 0) < (time() - days * 86400) then
        return false
    end
    return true
end

local function SortJournalEventsNewest(events)
    table.sort(events, function(a, b)
        local aLast = tonumber(a.last) or tonumber(a.t) or 0
        local bLast = tonumber(b.last) or tonumber(b.t) or 0
        if aLast ~= bLast then return aLast > bLast end
        return (tonumber(a.t) or 0) > (tonumber(b.t) or 0)
    end)
    return events
end

function SC.GetJournalEventsFor(name, limit, typeFilter, days)
    local j, key, result = EnsureJournal(), Key(name), {}
    if key == "" then return result end
    for i = 1, #j.events do
        local event = j.events[i]
        if EventMatchesName(event, key) and JournalEventMatches(event, typeFilter, days) then
            result[#result + 1] = event
        end
    end
    SortJournalEventsNewest(result)
    if limit then
        local max = math.max(0, tonumber(limit) or #result)
        while #result > max do table.remove(result) end
    end
    return result
end

function SC.GetRecentJournalEvents(limit, typeFilter, days)
    local events, j = {}, EnsureJournal()
    local max = math.max(1, math.min(100, tonumber(limit) or 30))
    for i = 1, #j.events do
        local event = j.events[i]
        if JournalEventMatches(event, typeFilter, days) then events[#events + 1] = event end
    end
    SortJournalEventsNewest(events)
    while #events > max do table.remove(events) end
    return events
end

-- Per-player attendance is stored compactly on each group-session event.
-- The separators are control characters that cannot occur in WoW character names.
local ATTENDANCE_ITEM_SEP = string.char(1)
local ATTENDANCE_FIELD_SEP = string.char(2)

local function ParseAttendance(value)
    local parsed = {}
    if type(value) ~= "string" or value == "" then return parsed end
    for item in (value .. ATTENDANCE_ITEM_SEP):gmatch("(.-)" .. ATTENDANCE_ITEM_SEP) do
        local name, seconds, intervals = item:match("^(.-)" .. ATTENDANCE_FIELD_SEP .. "(%d+)" .. ATTENDANCE_FIELD_SEP .. "(%d+)$")
        if name and name ~= "" then
            parsed[Key(name)] = { name = name, seconds = tonumber(seconds) or 0, intervals = tonumber(intervals) or 1 }
        end
    end
    return parsed
end

function SC.GetJournalGroupAttendance(event, name)
    if type(event) ~= "table" or type(name) ~= "string" then return nil end
    local parsed = ParseAttendance(event.attendance)
    local row = parsed[Key(name)]
    if row then return { seconds = row.seconds, intervals = row.intervals, estimated = false } end
    -- Older history recorded the full session duration for every participant.
    -- Preserve visibility, but identify it as estimated rather than precise.
    if event.type == "group" and EventMatchesName(event, Key(name)) then
        return { seconds = tonumber(event.duration) or 0, intervals = 1, estimated = true }
    end
    return nil
end

function SC.GetJournalPlayerSummary(name)
    local j, key = EnsureJournal(), Key(name)
    local summary = {
        totalEvents = 0, groupSessions = 0, groupDuration = 0, estimatedGroupSessions = 0,
        whispers = 0, incomingWhispers = 0, outgoingWhispers = 0,
        friendEvents = 0, guildEvents = 0, presenceEvents = 0, questEvents = 0,
        first = nil, last = nil, locations = {}, groupPartners = {}, uniqueGroupPartners = 0,
        firstFriendAdded = nil, firstGuildJoined = nil, lastGroupAt = nil, lastWhisperAt = nil,
        allGroupPartners = {},
    }
    if key == "" then return summary end
    local seenLocations, partnerMap = {}, {}
    for _, event in ipairs(j.events) do
        if EventMatchesName(event, key) then
            local stamp = tonumber(event.t) or 0
            local lastStamp = tonumber(event.last) or stamp
            summary.totalEvents = summary.totalEvents + 1
            if stamp > 0 and (not summary.first or stamp < summary.first) then summary.first = stamp end
            if lastStamp > 0 and (not summary.last or lastStamp > summary.last) then summary.last = lastStamp end
            if event.type == "group" then
                local attendance = SC.GetJournalGroupAttendance and SC.GetJournalGroupAttendance(event, name)
                local attendedSeconds = attendance and attendance.seconds or 0
                if not attendance then attendedSeconds = tonumber(event.duration) or 0 end
                if attendedSeconds > 0 then
                    summary.groupSessions = summary.groupSessions + 1
                    summary.groupDuration = summary.groupDuration + attendedSeconds
                    if attendance and attendance.estimated then
                        summary.estimatedGroupSessions = summary.estimatedGroupSessions + 1
                    end
                    if lastStamp > (summary.lastGroupAt or 0) then summary.lastGroupAt = lastStamp end
                    -- Count other recorded players only when they appear in the same
                    -- real group-session event. This is co-presence, not a claim of
                    -- completing an objective together.
                    for _, partnerName in ipairs(event.names or {}) do
                        local partnerKey = Key(partnerName)
                        if partnerKey ~= "" and partnerKey ~= key then
                            local partnerAttendance = SC.GetJournalGroupAttendance and SC.GetJournalGroupAttendance(event, partnerName)
                            if partnerAttendance and (tonumber(partnerAttendance.seconds) or 0) > 0 then
                                local partner = partnerMap[partnerKey]
                                if not partner then
                                    partner = { name = partnerName, sessions = 0, last = 0 }
                                    partnerMap[partnerKey] = partner
                                end
                                partner.sessions = partner.sessions + 1
                                if lastStamp > partner.last then partner.last = lastStamp end
                            end
                        end
                    end
                end
                local locs = tostring(event.locations or event.location or "")
                for loc in locs:gmatch("[^|]+") do
                    loc = loc:gsub("^%s+", ""):gsub("%s+$", "")
                    if loc ~= "" and not seenLocations[loc] and #summary.locations < 8 then
                        seenLocations[loc] = true
                        summary.locations[#summary.locations + 1] = loc
                    end
                end
            elseif event.type == "whisper" then
                summary.whispers = summary.whispers + (tonumber(event.count) or 1)
                summary.incomingWhispers = summary.incomingWhispers + (tonumber(event.incoming) or 0)
                summary.outgoingWhispers = summary.outgoingWhispers + (tonumber(event.outgoing) or 0)
                if lastStamp > (summary.lastWhisperAt or 0) then summary.lastWhisperAt = lastStamp end
            elseif event.type == "friend" then
                summary.friendEvents = summary.friendEvents + 1
                local title = tostring(event.title or ""):lower()
                if title:find("added", 1, true) and (not summary.firstFriendAdded or stamp < summary.firstFriendAdded) then
                    summary.firstFriendAdded = stamp
                end
            elseif event.type == "guild" or event.type == "guild_context" then
                summary.guildEvents = summary.guildEvents + 1
                local title = tostring(event.title or ""):lower()
                if title:find("joined", 1, true) and (not summary.firstGuildJoined or stamp < summary.firstGuildJoined) then
                    summary.firstGuildJoined = stamp
                end
            elseif event.type == "presence" or event.type == "guild_presence" or event.type == "bnet_presence" then
                summary.presenceEvents = summary.presenceEvents + 1
            elseif event.type == "quest" then
                summary.questEvents = summary.questEvents + 1
            end
        end
    end
    for _, partner in pairs(partnerMap) do summary.allGroupPartners[#summary.allGroupPartners + 1] = partner end
    table.sort(summary.allGroupPartners, function(a, b)
        if a.sessions ~= b.sessions then return a.sessions > b.sessions end
        if a.last ~= b.last then return a.last > b.last end
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)
    summary.uniqueGroupPartners = #summary.allGroupPartners
    for i = 1, math.min(5, #summary.allGroupPartners) do
        summary.groupPartners[i] = summary.allGroupPartners[i]
    end
    return summary
end

-- Return only recorded group-session events in which both players have
-- attendance. The result describes membership in the same tracked session;
-- it does not claim exact simultaneous overlap or dungeon completion.
function SC.GetJournalSharedGroupSessions(firstName, secondName, limit, days)
    local result = { sessions = {}, count = 0, firstSeconds = 0, secondSeconds = 0,
        estimatedSessions = 0, firstName = firstName, secondName = secondName }
    if type(firstName) ~= "string" or type(secondName) ~= "string" then return result end
    local firstKey, secondKey = Key(firstName), Key(secondName)
    if firstKey == "" or secondKey == "" or firstKey == secondKey then return result end
    local j = EnsureJournal()
    local maxRows = math.max(1, math.min(100, tonumber(limit) or 30))
    local dayCount = tonumber(days) or 0
    local cutoff = dayCount > 0 and (time() - dayCount * 86400) or 0
    for i = #j.events, 1, -1 do
        local event = j.events[i]
        local stamp = tonumber(event.t) or 0
        if event.type == "group" and stamp >= cutoff
            and EventMatchesName(event, firstKey) and EventMatchesName(event, secondKey) then
            local firstAttendance = SC.GetJournalGroupAttendance and SC.GetJournalGroupAttendance(event, firstName)
            local secondAttendance = SC.GetJournalGroupAttendance and SC.GetJournalGroupAttendance(event, secondName)
            if firstAttendance and secondAttendance
                and (tonumber(firstAttendance.seconds) or 0) > 0
                and (tonumber(secondAttendance.seconds) or 0) > 0 then
                local row = {
                    t = stamp, ended = tonumber(event.ended) or 0,
                    title = tostring(event.title or "Group session"),
                    detail = tostring(event.detail or ""),
                    locations = tostring(event.locations or event.location or ""),
                    sessionKind = tostring(event.sessionKind or "Group"),
                    difficultyName = tostring(event.difficultyName or ""),
                    groupSize = tonumber(event.groupSize) or 0,
                    firstSeconds = tonumber(firstAttendance.seconds) or 0,
                    secondSeconds = tonumber(secondAttendance.seconds) or 0,
                    firstIntervals = tonumber(firstAttendance.intervals) or 1,
                    secondIntervals = tonumber(secondAttendance.intervals) or 1,
                    estimated = firstAttendance.estimated or secondAttendance.estimated or false,
                }
                result.sessions[#result.sessions + 1] = row
                result.count = result.count + 1
                result.firstSeconds = result.firstSeconds + row.firstSeconds
                result.secondSeconds = result.secondSeconds + row.secondSeconds
                if row.estimated then result.estimatedSessions = result.estimatedSessions + 1 end
                if #result.sessions >= maxRows then break end
            end
        end
    end
    return result
end

-- Social Intelligence: read-only insights derived from the bounded local Journal.
-- Nothing is persisted by these calculations; they run only when a Social Hub
-- Insights page or a player Network section is opened.
local function IntelligencePerson(map, name, excludedKey)
    local key = Key(name)
    if key == "" or (excludedKey and key == excludedKey) then return nil end
    local person = map[key]
    if not person then
        person = {
            name = name, events = 0, groupSessions = 0, groupSeconds = 0,
            estimatedGroupSessions = 0, whispers = 0, incomingWhispers = 0,
            outgoingWhispers = 0, friendChanges = 0, guildChanges = 0,
            presenceChanges = 0, questEvents = 0, first = nil, last = 0,
            score = 0,
        }
        map[key] = person
    end
    return person
end

function SC.GetSocialIntelligenceStats(days)
    local journal = EnsureJournal()
    local playerName = SC.PlayerDisplayName and SC.PlayerDisplayName("player") or (UnitName and UnitName("player"))
    local playerKey = Key(playerName)
    local dayCount = math.max(0, tonumber(days) or 0)
    local cutoff = dayCount > 0 and (time() - dayCount * 86400) or 0
    local result = {
        days = dayCount, events = 0, uniquePlayers = 0, groupSessions = 0,
        groupMinutes = 0, whisperInteractions = 0, friendChanges = 0,
        guildChanges = 0, presenceChanges = 0, questEvents = 0,
        people = {}, topContacts = {}, topGroupPartners = {}, topWhisperContacts = {},
        topLocations = {}, recommendations = {}, journalEnabled = journal.enabled and true or false,
    }
    local people, locationMap = {}, {}
    for _, event in ipairs(journal.events or {}) do
        local stamp = tonumber(event.last) or tonumber(event.t) or 0
        if stamp >= cutoff then
            result.events = result.events + 1
            local eventNames = type(event.names) == "table" and event.names or {}
            for _, name in ipairs(eventNames) do
                local person = IntelligencePerson(people, name, playerKey)
                if person then
                    person.events = person.events + 1
                    if stamp > person.last then person.last = stamp end
                    local firstStamp = tonumber(event.t) or stamp
                    if firstStamp > 0 and (not person.first or firstStamp < person.first) then person.first = firstStamp end
                end
            end

            if event.type == "group" then
                result.groupSessions = result.groupSessions + 1
                local duration = tonumber(event.duration) or 0
                if duration <= 0 and tonumber(event.started) and tonumber(event.ended) then
                    duration = math.max(0, tonumber(event.ended) - tonumber(event.started))
                end
                result.groupMinutes = result.groupMinutes + math.floor(duration / 60)
                local locations = tostring(event.locations or event.location or "")
                for location in locations:gmatch("[^|]+") do
                    location = location:gsub("^%s+", ""):gsub("%s+$", "")
                    if location ~= "" then locationMap[location] = (locationMap[location] or 0) + 1 end
                end
                for _, name in ipairs(eventNames) do
                    local person = IntelligencePerson(people, name, playerKey)
                    local attendance = person and SC.GetJournalGroupAttendance and SC.GetJournalGroupAttendance(event, name)
                    if person and attendance and (tonumber(attendance.seconds) or 0) > 0 then
                        person.groupSessions = person.groupSessions + 1
                        person.groupSeconds = person.groupSeconds + (tonumber(attendance.seconds) or 0)
                        if attendance.estimated then person.estimatedGroupSessions = person.estimatedGroupSessions + 1 end
                    end
                end
            elseif event.type == "whisper" then
                local count = tonumber(event.count) or 1
                result.whisperInteractions = result.whisperInteractions + count
                for _, name in ipairs(eventNames) do
                    local person = IntelligencePerson(people, name, playerKey)
                    if person then
                        person.whispers = person.whispers + count
                        person.incomingWhispers = person.incomingWhispers + (tonumber(event.incoming) or 0)
                        person.outgoingWhispers = person.outgoingWhispers + (tonumber(event.outgoing) or 0)
                    end
                end
            elseif event.type == "friend" then
                result.friendChanges = result.friendChanges + 1
                for _, name in ipairs(eventNames) do local person = IntelligencePerson(people, name, playerKey); if person then person.friendChanges = person.friendChanges + 1 end end
            elseif event.type == "guild" or event.type == "guild_context" then
                result.guildChanges = result.guildChanges + 1
                for _, name in ipairs(eventNames) do local person = IntelligencePerson(people, name, playerKey); if person then person.guildChanges = person.guildChanges + 1 end end
            elseif event.type == "presence" or event.type == "guild_presence" or event.type == "bnet_presence" then
                result.presenceChanges = result.presenceChanges + 1
                for _, name in ipairs(eventNames) do local person = IntelligencePerson(people, name, playerKey); if person then person.presenceChanges = person.presenceChanges + 1 end end
            elseif event.type == "quest" then
                result.questEvents = result.questEvents + 1
                for _, name in ipairs(eventNames) do local person = IntelligencePerson(people, name, playerKey); if person then person.questEvents = person.questEvents + 1 end end
            end
        end
    end

    local sorted = {}
    for _, person in pairs(people) do
        person.score = (person.groupSessions * 4) + person.whispers + (person.friendChanges * 1.5) + person.guildChanges + (person.presenceChanges * 0.25)
        sorted[#sorted + 1] = person
    end
    table.sort(sorted, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.last ~= b.last then return a.last > b.last end
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)
    result.people = sorted
    result.uniquePlayers = #sorted
    for i = 1, math.min(10, #sorted) do result.topContacts[#result.topContacts + 1] = sorted[i] end

    local groupRows, whisperRows = {}, {}
    for _, person in ipairs(sorted) do
        if person.groupSessions > 0 then groupRows[#groupRows + 1] = person end
        if person.whispers > 0 then whisperRows[#whisperRows + 1] = person end
    end
    table.sort(groupRows, function(a, b) if a.groupSessions ~= b.groupSessions then return a.groupSessions > b.groupSessions end return a.last > b.last end)
    table.sort(whisperRows, function(a, b) if a.whispers ~= b.whispers then return a.whispers > b.whispers end return a.last > b.last end)
    for i = 1, math.min(8, #groupRows) do result.topGroupPartners[#result.topGroupPartners + 1] = groupRows[i] end
    for i = 1, math.min(8, #whisperRows) do result.topWhisperContacts[#result.topWhisperContacts + 1] = whisperRows[i] end

    for location, count in pairs(locationMap) do result.topLocations[#result.topLocations + 1] = { name = location, sessions = count } end
    table.sort(result.topLocations, function(a, b) if a.sessions ~= b.sessions then return a.sessions > b.sessions end return a.name:lower() < b.name:lower() end)
    while #result.topLocations > 6 do table.remove(result.topLocations) end

    -- Recommendations are transparent prompts based on recorded counts only.
    -- They never edit Favorites, Pins or contact groups automatically.
    for _, person in ipairs(sorted) do
        local isFavorite = SC.IsFavorite and SC.IsFavorite(person.name)
        local isPinned = SC.IsContactPinned and SC.IsContactPinned(person.name)
        if person.groupSessions >= 2 and not isFavorite then
            result.recommendations[#result.recommendations + 1] = {
                name = person.name, reason = string.format("Recorded in %d shared group sessions", person.groupSessions), action = "favorite",
            }
        elseif person.whispers >= 4 and not isPinned then
            result.recommendations[#result.recommendations + 1] = {
                name = person.name, reason = string.format("%d recorded Whisper interactions", person.whispers), action = "pin",
            }
        elseif person.events >= 8 and not isFavorite then
            result.recommendations[#result.recommendations + 1] = {
                name = person.name, reason = string.format("%d recorded social interactions", person.events), action = "favorite",
            }
        end
        if #result.recommendations >= 8 then break end
    end
    return result
end

function SC.GetSocialPlayerInsights(name, days)
    local key = Key(name)
    local summary = SC.GetJournalPlayerSummary and SC.GetJournalPlayerSummary(name) or {}
    local stats = SC.GetSocialIntelligenceStats(days)
    local selected
    for _, person in ipairs(stats.people or {}) do
        if Key(person.name) == key then selected = person break end
    end
    selected = selected or { name = name, events = 0, groupSessions = 0, groupSeconds = 0, whispers = 0, friendChanges = 0, guildChanges = 0, presenceChanges = 0, questEvents = 0, score = 0 }
    selected.summary = summary
    selected.days = tonumber(days) or 0
    return selected
end

function SC.GetSocialDiscoveries(days)
    local stats = SC.GetSocialIntelligenceStats(days)
    return stats.topContacts or {}
end

function SC.GetSocialRecommendations(days)
    local stats = SC.GetSocialIntelligenceStats(days)
    return stats.recommendations or {}
end

function SC.GetPlayerRelationshipNetwork(name, days)
    local result = { groupPartners = {}, personalGroups = {}, guildmates = {}, battleNetCharacters = {}, notes = {}, currentGuild = nil }
    if type(name) ~= "string" or name == "" then return result end
    local maxDays = math.max(0, tonumber(days) or 0)
    local cutoff = maxDays > 0 and (time() - maxDays * 86400) or 0
    local partnerMap = {}
    local journal = EnsureJournal()
    local key = Key(name)
    for _, event in ipairs(journal.events or {}) do
        local stamp = tonumber(event.last) or tonumber(event.t) or 0
        if event.type == "group" and stamp >= cutoff and EventMatchesName(event, key) then
            local ownAttendance = SC.GetJournalGroupAttendance and SC.GetJournalGroupAttendance(event, name)
            if ownAttendance and (tonumber(ownAttendance.seconds) or 0) > 0 then
                for _, peerName in ipairs(event.names or {}) do
                    local peerKey = Key(peerName)
                    if peerKey ~= "" and peerKey ~= key then
                        local peerAttendance = SC.GetJournalGroupAttendance and SC.GetJournalGroupAttendance(event, peerName)
                        if peerAttendance and (tonumber(peerAttendance.seconds) or 0) > 0 then
                            local peer = partnerMap[peerKey]
                            if not peer then peer = { name = peerName, sessions = 0, last = 0, seconds = 0 }; partnerMap[peerKey] = peer end
                            peer.sessions = peer.sessions + 1
                            peer.seconds = peer.seconds + (tonumber(peerAttendance.seconds) or 0)
                            if stamp > peer.last then peer.last = stamp end
                        end
                    end
                end
            end
        end
    end
    for _, partner in pairs(partnerMap) do result.groupPartners[#result.groupPartners + 1] = partner end
    table.sort(result.groupPartners, function(a, b) if a.sessions ~= b.sessions then return a.sessions > b.sessions end if a.last ~= b.last then return a.last > b.last end return tostring(a.name):lower() < tostring(b.name):lower() end)

    local social = EnsureSocial()
    for _, groupName in ipairs(social.groupOrder or {}) do
        local members = social.groups[groupName]
        if type(members) == "table" and members[key] then
            local peers = {}
            for peerKey, peerName in pairs(members) do
                if peerName and peerKey ~= key then peers[#peers + 1] = peerName end
            end
            table.sort(peers, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
            result.personalGroups[#result.personalGroups + 1] = { name = groupName, members = peers }
        end
    end

    local relation = SC.Relation and SC.Relation(name) or ""
    if relation:find("G", 1, true) and IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        result.currentGuild = (GetGuildInfo and GetGuildInfo("player")) or "Current Guild"
        local seen = {}
        for i = 1, math.min(GetNumGuildMembers() or 0, 1000) do
            local memberName, rankName, rankIndex, level, className, zone, _, _, online = GetGuildRosterInfo(i)
            if memberName and Key(memberName) ~= key and not seen[Key(memberName)] then
                seen[Key(memberName)] = true
                result.guildmates[#result.guildmates + 1] = { name = memberName, rank = rankName or "", level = tonumber(level), class = className or "", zone = zone or "", online = type(online) == "boolean" and online or nil }
            end
        end
    end

    local info = SC.GetContactInfo and SC.GetContactInfo(name) or {}
    for _, character in ipairs(info.bnetCharacters or {}) do
        local characterName = character.name or character.character
        if type(characterName) == "string" and characterName ~= "" and Key(characterName) ~= key then
            result.battleNetCharacters[#result.battleNetCharacters + 1] = {
                name = characterName, realm = character.realm or "", class = character.class or "", level = tonumber(character.level), status = character.status or "UNKNOWN",
            }
        end
    end

    if #result.groupPartners > 0 then result.notes[#result.notes + 1] = "Recorded group co-presence is based on saved sessions; it does not prove objective completion or exact simultaneous presence." end
    if #result.guildmates > 0 then result.notes[#result.notes + 1] = "Guild connections reflect the current Guild roster exposed by the game." end
    if #result.personalGroups > 0 then result.notes[#result.notes + 1] = "Personal group connections are your own local SmartChat lists." end
    result.mutualFriendsAvailable = false
    result.notes[#result.notes + 1] = "The game does not expose another player's Friend List, so mutual-friend relationships cannot be verified." 
    return result
end

function SC.GetJournalRecentNames()
    local j, names, seen = EnsureJournal(), {}, {}
    local playerName = SC.PlayerDisplayName and SC.PlayerDisplayName("player") or (UnitName and UnitName("player"))
    local playerKey = Key(playerName)
    for i = #j.events, 1, -1 do
        local event = j.events[i]
        for _, name in ipairs(event.names or {}) do
            local key = Key(name)
            if key ~= "" and key ~= playerKey and not seen[key] then names[#names + 1] = name; seen[key] = true end
        end
    end
    return names
end

function SC.GetContactNote(name)
    local j = EnsureJournal()
    local note = j.notes[Key(name)]
    if type(note) ~= "table" then note = { tags = {}, text = "" } end
    if type(note.tags) ~= "table" then note.tags = {} end
    if type(note.text) ~= "string" then note.text = "" end
    return note
end

function SC.SaveContactNote(name, tags, textValue)
    if type(name) ~= "string" or name == "" then return false end
    local j, clean, seen = EnsureJournal(), {}, {}
    for _, tag in ipairs(tags or {}) do
        if type(tag) == "string" and tag ~= "" and not seen[tag] then clean[#clean + 1] = tag; seen[tag] = true end
    end
    textValue = type(textValue) == "string" and textValue:sub(1, 500) or ""
    local noteKey = Key(name)
    if not j.notes[noteKey] then
        local noteCount, oldestKey, oldestTime = 0, nil, math.huge
        for existingKey, existing in pairs(j.notes) do
            if type(existing) == "table" then
                noteCount = noteCount + 1
                local updated = tonumber(existing.updated) or 0
                if updated < oldestTime then oldestTime, oldestKey = updated, existingKey end
            end
        end
        if noteCount >= 500 and oldestKey then j.notes[oldestKey] = nil end
    end
    j.notes[noteKey] = { name = name, tags = clean, text = textValue, updated = time() }
    if SC.AddJournalEvent and j.enabled then
        SC.AddJournalEvent("note", { name }, "Personal note updated", #clean > 0 and table.concat(clean, ", ") or "Personal note saved")
    end
    if SC.RefreshWhisperInbox then SC.RefreshWhisperInbox() end
    return true
end


function SC.DeleteContactNote(name)
    if type(name) ~= "string" or name == "" then return false end
    local j = EnsureJournal()
    local key = Key(name)
    if not j.notes[key] then return false end
    j.notes[key] = nil
    if SC.RefreshWhisperInbox then SC.RefreshWhisperInbox() end
    return true
end

local function SerializeAttendanceMap(map)
    local records = {}
    for _, person in pairs(map or {}) do
        if type(person) == "table" and type(person.name) == "string" and person.name ~= "" then
            records[#records + 1] = person.name .. ATTENDANCE_FIELD_SEP
                .. tostring(math.max(0, math.floor(tonumber(person.seconds) or 0))) .. ATTENDANCE_FIELD_SEP
                .. tostring(math.max(1, math.floor(tonumber(person.intervals) or 1)))
        end
    end
    table.sort(records)
    return table.concat(records, ATTENDANCE_ITEM_SEP)
end

-- Removes only this player's local Journal references. Shared group/quest events
-- remain for the other participants, with this player removed from their names
-- and attendance payload. In-game Friends/Guild/Ignore lists are never changed.
function SC.ClearPlayerJournalData(name)
    if type(name) ~= "string" or name == "" then return false, "Invalid player name." end
    local j, key = EnsureJournal(), Key(name)
    if key == "" then return false, "Invalid player name." end
    local removedEvents, updatedEvents = 0, 0
    for i = #j.events, 1, -1 do
        local event = j.events[i]
        if EventMatchesName(event, key) then
            local kept, found = {}, false
            for _, eventName in ipairs(event.names or {}) do
                if Key(eventName) == key then found = true else kept[#kept + 1] = eventName end
            end
            if found then
                if #kept == 0 then
                    table.remove(j.events, i)
                    removedEvents = removedEvents + 1
                else
                    event.names = kept
                    if event.type == "group" and type(event.attendance) == "string" then
                        local attendance = ParseAttendance(event.attendance)
                        attendance[key] = nil
                        event.attendance = SerializeAttendanceMap(attendance)
                    end
                    updatedEvents = updatedEvents + 1
                end
            end
        end
    end
    if j.notes[key] then j.notes[key] = nil end
    whisperEventIndexReady = false; wipe(whisperEventIndex)
    if type(j.activeGroup) == "table" then
        j.activeGroup.participants = j.activeGroup.participants or {}
        j.activeGroup.participants[key] = nil
        local kept = {}
        for _, eventName in ipairs(j.activeGroup.names or {}) do
            if Key(eventName) ~= key then kept[#kept + 1] = eventName end
        end
        j.activeGroup.names = kept
    end
    if SC.RefreshWhisperInbox then SC.RefreshWhisperInbox() end
    return true, { removed = removedEvents, updated = updatedEvents }
end

function SC.ClearJournalEventHistory()
    local j = EnsureJournal()
    local count = #j.events
    if count == 0 then return true, 0 end
    if SC.CreateLocalSocialRestorePoint then
        local ok, err = SC.CreateLocalSocialRestorePoint("Before clearing Journal history")
        if not ok then return false, err or "Could not create a recovery point." end
    end
    wipe(j.events)
    whisperEventIndexReady = false; wipe(whisperEventIndex)
    if SC.RefreshWhisperInbox then SC.RefreshWhisperInbox() end
    return true, count
end

local function CurrentGroupMembers()
    local result, seen = {}, {}
    local total = (GetNumGroupMembers and GetNumGroupMembers()) or (GetNumRaidMembers and GetNumRaidMembers()) or 0
    local units = {}
    if IsInRaid and IsInRaid() then
        for i = 1, math.min(total, 40) do units[#units + 1] = "raid" .. i end
    elseif IsInGroup and IsInGroup() then
        for i = 1, math.min(math.max(total - 1, 0), 4) do units[#units + 1] = "party" .. i end
    end
    local playerName = SC.PlayerDisplayName and SC.PlayerDisplayName("player") or (UnitName and UnitName("player"))
    for _, unit in ipairs(units) do
        local name = SC.PlayerDisplayName and SC.PlayerDisplayName(unit) or (UnitName and UnitName(unit))
        if name and name ~= "" and Key(name) ~= Key(playerName) and not seen[Key(name)] then
            seen[Key(name)] = true
            result[#result + 1] = name
        end
    end
    return result
end

local function CurrentInstanceInfo()
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or "Unknown area"
    local data = { name = zone, instanceType = "none", difficultyID = 0, difficultyName = "", maxPlayers = 0, instanceID = 0 }
    if GetInstanceInfo then
        local ok, name, instanceType, difficultyID, difficultyName, maxPlayers, _, _, instanceID = pcall(GetInstanceInfo)
        if ok then
            data.name = (type(name) == "string" and name ~= "" and name) or data.name
            data.instanceType = type(instanceType) == "string" and instanceType or "none"
            data.difficultyID = tonumber(difficultyID) or 0
            data.difficultyName = type(difficultyName) == "string" and difficultyName or ""
            data.maxPlayers = tonumber(maxPlayers) or 0
            data.instanceID = tonumber(instanceID) or 0
        end
    end
    return data
end

local function CurrentLocation()
    local meta = { name = nil, instanceType = "none" }
    if GetInstanceInfo then
        local ok, name, instanceType = pcall(GetInstanceInfo)
        if ok then meta.name, meta.instanceType = name, instanceType end
    end
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or "Unknown area"
    if meta.name and meta.name ~= "" and meta.instanceType and meta.instanceType ~= "none" then return meta.name end
    return zone
end

local function AddSessionLocation(active, location)
    if not active or type(location) ~= "string" or location == "" then return end
    active.locations = active.locations or {}
    for _, previous in ipairs(active.locations) do if previous == location then return end end
    if #active.locations < 12 then active.locations[#active.locations + 1] = location end
end

local function CaptureGroupSessionMeta(active)
    if not active then return end
    local meta = CurrentInstanceInfo()
    active.lastLocation = meta.name or CurrentLocation()
    if meta.instanceType and meta.instanceType ~= "none" then active.instanceType = meta.instanceType end
    if (tonumber(meta.difficultyID) or 0) > 0 then active.difficultyID = meta.difficultyID end
    if meta.difficultyName and meta.difficultyName ~= "" then active.difficultyName = meta.difficultyName end
    if (tonumber(meta.instanceID) or 0) > 0 then active.instanceID = meta.instanceID end
    if (tonumber(meta.maxPlayers) or 0) > 0 then active.maxPlayers = meta.maxPlayers end
    local count = (GetNumGroupMembers and GetNumGroupMembers()) or (GetNumRaidMembers and GetNumRaidMembers()) or 0
    active.maxGroupSize = math.max(tonumber(active.maxGroupSize) or 0, tonumber(count) or 0)
    active.sessionKind = (IsInRaid and IsInRaid()) and "Raid" or ((IsInGroup and IsInGroup()) and "Party" or "Group")
    AddSessionLocation(active, active.lastLocation)
end

local function BuildAttendanceString(active, endedAt)
    local records = {}
    for _, person in pairs((active and active.participants) or {}) do
        local seconds = tonumber(person.seconds) or 0
        if person.activeSince then seconds = seconds + math.max(0, endedAt - (tonumber(person.activeSince) or endedAt)) end
        records[#records + 1] = tostring(person.name or "") .. ATTENDANCE_FIELD_SEP
            .. tostring(math.floor(seconds + 0.5)) .. ATTENDANCE_FIELD_SEP
            .. tostring(math.max(1, tonumber(person.intervals) or 1))
    end
    table.sort(records)
    return table.concat(records, ATTENDANCE_ITEM_SEP)
end

local function FinalizeGroupSession(j, title, endedAt)
    j = j or EnsureJournal()
    local active = j.activeGroup
    if not active or type(active.names) ~= "table" or #active.names == 0 then j.activeGroup = nil; return end
    local ended = tonumber(endedAt) or time()
    local started = tonumber(active.started) or ended
    local duration = math.max(0, ended - started)
    local locations = active.locations or { active.location or CurrentLocation() }
    local detail = table.concat(locations, " â ") .. " Â· " .. math.floor(duration / 60) .. " min"
    if active.instanceType and active.instanceType ~= "none" and active.difficultyName and active.difficultyName ~= "" then
        detail = detail .. " Â· " .. active.difficultyName
    end
    local attendance = BuildAttendanceString(active, ended)
    SC.AddJournalEvent("group", active.names, title or "Group session", detail, {
        started = started, ended = ended, duration = duration,
        location = active.lastLocation or active.location or "",
        locations = table.concat(locations, " | "),
        instanceType = active.instanceType or "none",
        difficultyName = active.difficultyName or "",
        difficultyID = tonumber(active.difficultyID) or 0,
        instanceID = tonumber(active.instanceID) or 0,
        maxPlayers = tonumber(active.maxPlayers) or 0,
        groupSize = tonumber(active.maxGroupSize) or 0,
        sessionKind = active.sessionKind or "Group",
        attendance = attendance,
    })
    j.activeGroup = nil
end

local function SyncGroupAttendance(active, members, now)
    active.participants = active.participants or {}
    active.names = active.names or {}
    local current, seenNames = {}, {}
    for _, name in ipairs(active.names) do seenNames[Key(name)] = true end
    for _, name in ipairs(members or {}) do current[Key(name)] = name end

    for key, person in pairs(active.participants) do
        if person.activeSince and not current[key] then
            person.seconds = (tonumber(person.seconds) or 0) + math.max(0, now - (tonumber(person.activeSince) or now))
            person.activeSince = nil
            person.lastLeft = now
        end
    end

    for key, name in pairs(current) do
        local person = active.participants[key]
        if not person then
            person = { name = name, seconds = 0, activeSince = now, intervals = 1 }
            active.participants[key] = person
        else
            person.name = name
            if not person.activeSince then
                person.activeSince = now
                person.intervals = (tonumber(person.intervals) or 1) + 1
            end
        end
        if not seenNames[key] then
            active.names[#active.names + 1] = name
            seenNames[key] = true
        end
    end
end

local function UpdateGroupSession()
    if not IsTrackingEnabled("group") then return end
    local j = EnsureJournal()
    local members = CurrentGroupMembers()
    local now = time()
    local active = j.activeGroup
    if #members == 0 then
        if active then FinalizeGroupSession(j, "Group session ended", now) end
        return
    end
    if not active then
        active = { started = now, names = {}, participants = {}, location = CurrentLocation(), locations = {} }
        j.activeGroup = active
    end
    SyncGroupAttendance(active, members, now)
    active.lastUpdated = now
    CaptureGroupSessionMeta(active)
end

local function PresenceStatus(info, onlineValue, statusValue)
    info = type(info) == "table" and info or {}
    local status = statusValue or info.status
    local text = type(status) == "string" and status:upper() or ""
    if info.afk or status == 1 or text:find("AFK", 1, true) then return "AFK" end
    if info.dnd or status == 2 or text:find("DND", 1, true) or text:find("BUSY", 1, true) then return "DND" end
    local online = onlineValue
    if online == nil then online = info.connected end
    if type(online) == "boolean" then return online and "ONLINE" or "OFFLINE" end
    return "UNKNOWN"
end

local lastFriendStates, lastGuildStates, lastGroupMembers, lastBnetStates = {}, {}, {}, {}
local lastGuildIdentity = nil
local presenceReady = false
local friendRosterReady, guildRosterReady, groupRosterReady, bnetRosterReady = false, false, false, false

local function ReadFriendRoster()
    local names, states = {}, {}
    local api = C_FriendList
    if not (api and api.GetNumFriends and api.GetFriendInfoByIndex) then return nil, nil, false end
    local okN, count = pcall(api.GetNumFriends)
    if not okN or type(count) ~= "number" then return nil, nil, false end
    for i = 1, count do
        local ok, info = pcall(api.GetFriendInfoByIndex, i)
        if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            local key = Key(info.name)
            names[key] = info.name
            states[key] = { name = info.name, status = PresenceStatus(info) }
        end
    end
    return names, states, true
end

local function ReadGuildRoster()
    local names, states = {}, {}
    if not (IsInGuild and IsInGuild()) then return names, states, nil end
    if not (GetNumGuildMembers and GetGuildRosterInfo and GetGuildInfo) then return nil, nil, nil end
    local guildName = GetGuildInfo("player")
    if type(guildName) ~= "string" or guildName == "" then return nil, nil, nil end
    local count = GetNumGuildMembers() or 0
    if count == 0 then return nil, nil, nil end -- guild roster is not ready yet
    for i = 1, count do
        local ok, name, rankName, rankIndex, level, className, zone, publicNote, officerNote, online, status, classFile = pcall(GetGuildRosterInfo, i)
        if ok and type(name) == "string" and name ~= "" then
            local key = Key(name)
            names[key] = name
            states[key] = { name = name, status = PresenceStatus({}, online, status), rank = rankName, zone = zone }
        end
    end
    return names, states, guildName
end

local function ReadGroupRoster()
    local names = {}
    for _, name in ipairs(CurrentGroupMembers()) do names[Key(name)] = name end
    return names
end

local function ReadBnetPresence()
    local states, seen = {}, {}
    for key, info in pairs(SC.bnetCache or {}) do
        if type(info) == "table" then
            local display = info.character or info.name or key
            local stable = info.accountKey and ("account:" .. tostring(info.accountKey))
                or (info.accountID and ("account:" .. tostring(info.accountID)) or ("name:" .. Key(display)))
            local status = (info.appearOffline or info.bnetAppearOffline) and "UNKNOWN"
                or (info.accountStatus or info.status or "UNKNOWN")
            local existing = states[stable]
            if not existing or (existing.status ~= "ONLINE" and status == "ONLINE") then
                states[stable] = { name = display, status = status }
            end
            seen[stable] = true
        end
    end
    return states
end

local function CopyMap(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

local function PresenceEvent(kind, name, oldStatus, newStatus, source)
    if not name or oldStatus == newStatus or newStatus == "UNKNOWN" or oldStatus == "UNKNOWN" then return end
    local j = EnsureJournal()
    local isOnline = newStatus == "ONLINE"
    local isOffline = newStatus == "OFFLINE"
    if kind == "friend" then
        if j.enabled and j.trackPresence then
            SC.AddJournalEvent("presence", { name }, "Friend is " .. newStatus, "Friend presence changed from " .. oldStatus .. " to " .. newStatus .. ".", { source = source or "Friend" })
        end
        if isOnline then SC.NotifySocial("friendOnline", "Friend online", name .. " is now online.")
        elseif isOffline then SC.NotifySocial("friendOffline", "Friend offline", name .. " is now offline.") end
    elseif kind == "guild" then
        if j.enabled and j.trackGuildPresence then
            SC.AddJournalEvent("guild_presence", { name }, "Guild member is " .. newStatus, "Guild presence changed from " .. oldStatus .. " to " .. newStatus .. ".")
        end
        if isOnline or isOffline then SC.NotifySocial("guildPresence", "Guild member status", name .. (isOnline and " is now online." or " is now offline.")) end
    elseif kind == "bnet" then
        if j.enabled and j.trackPresence then
            SC.AddJournalEvent("bnet_presence", { name }, "Battle.net friend is " .. newStatus, "Battle.net presence changed from " .. oldStatus .. " to " .. newStatus .. ".")
        end
        if isOnline or isOffline then SC.NotifySocial("bnetPresence", "Battle.net friend status", name .. (isOnline and " is now online." or " is now offline.")) end
    end
end

local function ComparePresence(previous, current, kind)
    for key, now in pairs(current or {}) do
        local before = previous and previous[key]
        if before and now then
            PresenceEvent(kind, now.name or before.name, before.status, now.status, kind == "bnet" and "Battle.net" or nil)
        end
    end
end

local function CompareMembership(previous, current, kind)
    if not presenceReady or type(previous) ~= "table" or type(current) ~= "table" then return end
    for key, name in pairs(current) do
        if not previous[key] then
            if kind == "friend" then SC.NotifySocial("friendChanges", "Friend added", name .. " was added to your Friend List.")
            elseif kind == "guild" then SC.NotifySocial("guildChanges", "Guild member joined", name .. " joined your Guild.")
            elseif kind == "group" then
                if EnsureJournal().enabled and EnsureJournal().trackGroupRoster then
                    SC.AddJournalEvent("group_member", { name }, "Joined your group", "Group roster changed at " .. CurrentLocation() .. ".")
                end
                SC.NotifySocial("groupChanges", "Group member joined", name .. " joined your group.")
            end
        end
    end
    for key, name in pairs(previous) do
        if not current[key] then
            if kind == "friend" then SC.NotifySocial("friendChanges", "Friend removed", name .. " was removed from your Friend List.")
            elseif kind == "guild" then SC.NotifySocial("guildChanges", "Guild member left", name .. " left your Guild.")
            elseif kind == "group" then
                if EnsureJournal().enabled and EnsureJournal().trackGroupRoster then
                    SC.AddJournalEvent("group_member", { name }, "Left your group", "Group roster changed at " .. CurrentLocation() .. ".")
                end
                SC.NotifySocial("groupChanges", "Group member left", name .. " left your group.")
            end
        end
    end
end

local function SnapshotFriends(isBaseline)
    local j = EnsureJournal()
    local current, states, available = ReadFriendRoster()
    if not available or type(current) ~= "table" or type(states) ~= "table" then return end
    local firstBaseline = isBaseline or not friendRosterReady
    if j.enabled and j.trackFriends then
        if not firstBaseline and j.friendSnapshot then
            for key, name in pairs(current) do
                if not j.friendSnapshot[key] then SC.AddJournalEvent("friend", { name }, "Added to Friends", "Friend list relationship started.") end
            end
            for key, name in pairs(j.friendSnapshot) do
                if not current[key] then SC.AddJournalEvent("friend", { name }, "Removed from Friends", "Friend list relationship ended.") end
            end
        end
        j.friendSnapshot = CopyMap(current)
    end
    if presenceReady and friendRosterReady and not isBaseline then
        local previousNames = {}
        for key, value in pairs(lastFriendStates or {}) do previousNames[key] = value.name end
        CompareMembership(previousNames, current, "friend")
        ComparePresence(lastFriendStates, states, "friend")
    end
    lastFriendStates = states
    friendRosterReady = true
end

local function SnapshotGuild(isBaseline)
    local j = EnsureJournal()
    local current, states, guildIdentity = ReadGuildRoster()
    if current == nil then return end -- roster may still be loading
    local firstBaseline = isBaseline or not guildRosterReady
    local identityChanged = not firstBaseline and guildRosterReady and lastGuildIdentity ~= guildIdentity

    -- A character changing or leaving Guild changes the roster context. Do not
    -- misreport every member of the old Guild as having left the Guild itself.
    if identityChanged and j.enabled and j.trackGuild then
        local playerName = SC.PlayerDisplayName and SC.PlayerDisplayName("player") or (UnitName and UnitName("player"))
        if playerName and playerName ~= "" then
            local title, detail
            if lastGuildIdentity and guildIdentity then
                title = "Changed Guild"
                detail = "Your character changed Guild from " .. tostring(lastGuildIdentity) .. " to " .. tostring(guildIdentity) .. "."
            elseif lastGuildIdentity then
                title = "Left Guild"
                detail = "Your character left " .. tostring(lastGuildIdentity) .. "."
            elseif guildIdentity then
                title = "Joined Guild"
                detail = "Your character joined " .. tostring(guildIdentity) .. "."
            end
            if title then SC.AddJournalEvent("guild_context", { playerName }, title, detail, { oldGuild = lastGuildIdentity or "", newGuild = guildIdentity or "" }) end
        end
    end

    if j.enabled and j.trackGuild then
        if not firstBaseline and j.guildSnapshot and not identityChanged then
            for key, name in pairs(current) do
                if not j.guildSnapshot[key] then SC.AddJournalEvent("guild", { name }, "Joined Guild", "Guild roster membership detected.") end
            end
            for key, name in pairs(j.guildSnapshot) do
                if not current[key] then SC.AddJournalEvent("guild", { name }, "Left Guild", "Guild roster membership ended.") end
            end
        end
        j.guildSnapshot = CopyMap(current)
    end
    if presenceReady and guildRosterReady and not isBaseline and not identityChanged then
        local previousNames = {}
        for key, value in pairs(lastGuildStates or {}) do previousNames[key] = value.name end
        CompareMembership(previousNames, current, "guild")
        ComparePresence(lastGuildStates, states, "guild")
    end
    lastGuildStates = states
    lastGuildIdentity = guildIdentity
    guildRosterReady = true
end

local function SnapshotGroup(isBaseline)
    local current = ReadGroupRoster()
    if presenceReady and groupRosterReady and not isBaseline then CompareMembership(lastGroupMembers, current, "group") end
    lastGroupMembers = current
    groupRosterReady = true
end

local function PrimePresenceSnapshots()
    local _, friendStates, friendAvailable = ReadFriendRoster()
    local _, guildStates, guildIdentity = ReadGuildRoster()
    lastFriendStates = friendStates or {}
    lastGuildStates = guildStates or {}
    lastGuildIdentity = guildIdentity
    lastGroupMembers = ReadGroupRoster()
    lastBnetStates = ReadBnetPresence()
    friendRosterReady = friendAvailable == true
    guildRosterReady = guildStates ~= nil
    groupRosterReady = true
    bnetRosterReady = SC.bnetCacheReady and true or false
    presenceReady = true
end

function SC.OnBnetCacheRefreshed()
    local current = ReadBnetPresence()
    if presenceReady and bnetRosterReady then ComparePresence(lastBnetStates, current, "bnet") end
    lastBnetStates = current
    bnetRosterReady = true
end

local journalEvents = CreateFrame("Frame")
local function SafeRegister(event)
    pcall(journalEvents.RegisterEvent, journalEvents, event)
end
for _, event in ipairs({
    "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE",
    "GROUP_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "QUEST_TURNED_IN",
    "SOCIAL_UI_FRIENDS_LIST_SYSTEM_STATUS_UPDATED", "LEGACY_FRIEND_SYSTEM_STATUS_UPDATED",
}) do SafeRegister(event) end

journalEvents:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(4, function()
            if not SC.db then return end
            local journal = EnsureJournal()
            if journal.enabled and journal.activeGroup then
                local lastKnown = tonumber(journal.activeGroup.lastUpdated) or tonumber(journal.activeGroup.started) or time()
                FinalizeGroupSession(journal, "Previous group session (interrupted)", lastKnown)
            end
            SnapshotFriends(true)
            SnapshotGuild(true)
            SnapshotGroup(true)
            PrimePresenceSnapshots()
            if journal.enabled then UpdateGroupSession() end
        end)
        return
    end
    if event == "PLAYER_LOGOUT" then
        local j = EnsureJournal()
        if j.enabled and j.activeGroup and IsTrackingEnabled("group") then
            FinalizeGroupSession(j, "Group session ended")
        end
        return
    end
    if not SC.db then return end
    if event == "FRIENDLIST_UPDATE" or event == "SOCIAL_UI_FRIENDS_LIST_SYSTEM_STATUS_UPDATED"
        or event == "LEGACY_FRIEND_SYSTEM_STATUS_UPDATED" then SnapshotFriends(false); return end
    if event == "GUILD_ROSTER_UPDATE" then SnapshotGuild(false); return end
    if event == "GROUP_ROSTER_UPDATE" then
        SnapshotGroup(false)
        UpdateGroupSession()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
        if not presenceReady then
            SnapshotGroup(true)
        else
            UpdateGroupSession()
        end
        return
    end
    if event == "QUEST_TURNED_IN" and IsTrackingEnabled("quest") then
        local questID = tonumber(arg1)
        local title = questID and C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
        local names = CurrentGroupMembers()
        if #names > 0 then
            local meta = CurrentInstanceInfo()
            SC.AddJournalEvent("quest", names, "Quest turned in", (title or (questID and ("Quest #" .. questID)) or "Quest") .. " Â· group roster present at turn-in", {
                questID = questID or 0, location = meta.name or CurrentLocation(), instanceType = meta.instanceType or "none",
                groupSize = (GetNumGroupMembers and GetNumGroupMembers()) or 0,
            })
        end
    end
end)

function SC.ResetJournalBaselines()
    local j = EnsureJournal()
    j.friendSnapshot, j.guildSnapshot = nil, nil
    C_Timer.After(2, function()
        if not SC.db then return end
        SnapshotFriends(true)
        SnapshotGuild(true)
        SnapshotGroup(true)
        if j.enabled then UpdateGroupSession() end
    end)
end

---------------------------------------------------------------------
-- Lazy Player Journal window. Timeline rows are built only when opened.
---------------------------------------------------------------------
local journalFrame, noteFrame, settingsFrame, groupPopup
local function EnsureJournalWindow()
    if journalFrame then return journalFrame end
    journalFrame = CreateFrame("Frame", "SmartChatPlayerJournal", UIParent, "BackdropTemplate")
    journalFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    journalFrame:SetFrameLevel(90)
    journalFrame:SetSize(610, 430)
    journalFrame:SetPoint("CENTER")
    journalFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    journalFrame:SetBackdropColor(0.035, 0.04, 0.055, 0.98)
    journalFrame:SetBackdropBorderColor(0.35, 0.42, 0.52, 1)
    journalFrame.title = journalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    journalFrame.title:SetPoint("TOPLEFT", 14, -12)
    local close = CreateFrame("Button", nil, journalFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -3)
    local add = CreateFrame("Button", nil, journalFrame, "UIPanelButtonTemplate")
    add:SetSize(116, 23); add:SetPoint("TOPRIGHT", close, "TOPLEFT", -2, -2); add:SetText("Quick Note")
    add:SetScript("OnClick", function() if journalFrame.name then SC.ShowQuickNote(journalFrame.name) end end)
    local back = CreateFrame("Button", nil, journalFrame, "UIPanelButtonTemplate")
    back:SetSize(92, 23); back:SetPoint("TOPRIGHT", add, "TOPLEFT", -4, 0); back:SetText("Social Hub")
    back:SetScript("OnClick", function() journalFrame:Hide(); if SC.ShowWhisperList then SC.ShowWhisperList() end end)
    journalFrame.content = journalFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    journalFrame.content:SetPoint("TOPLEFT", 16, -48)
    journalFrame.content:SetPoint("BOTTOMRIGHT", -16, 16)
    journalFrame.content:SetJustifyH("LEFT")
    journalFrame.content:SetJustifyV("TOP")
    journalFrame.content:SetWordWrap(true)
    journalFrame.content:SetSpacing(3)
    tinsert(UISpecialFrames, "SmartChatPlayerJournal")
    return journalFrame
end

function SC.ShowPlayerJournal(name)
    if type(name) ~= "string" or name == "" then return end
    if SC.ShowSocialPlayerJournal then return SC.ShowSocialPlayerJournal(name) end
    local frame = EnsureJournalWindow()
    frame.name = name
    local info = SC.GetContactInfo and SC.GetContactInfo(name) or {}
    local className = SC.ContactClassName and SC.ContactClassName(info) or info.class or "Unknown class"
    frame.title:SetText((SC.ShortName and SC.ShortName(name) or name) .. " â Player Journal")
    local lines = { "|cffaaaaaa" .. className .. " Â· Level " .. tostring(info.level or "?") .. " Â· " .. tostring(info.status or "UNKNOWN") .. "|r", "" }
    if not EnsureJournal().enabled then
        lines[#lines + 1] = "|cffffcc66Automatic history is disabled.|r"
        lines[#lines + 1] = "Enable Player Journal in Settings > Social & Journal to start recording local events."
        lines[#lines + 1] = "Personal notes and tags can still be saved."
    end
    local events = SC.GetJournalEventsFor(name, 30)
    if #events == 0 then
        lines[#lines + 1] = "|cff888888No recorded history for this player yet.|r"
    else
        lines[#lines + 1] = "|cff66ccffTIMELINE|r"
        for i = 1, #events do
            local e = events[i]
            local stamp = date("%Y-%m-%d %H:%M", e.t or time())
            local title = tostring(e.title or e.type or "Activity")
            local detail = tostring(e.detail or "")
            lines[#lines + 1] = "|cff888888" .. stamp .. "|r  |cffffffff" .. title .. "|r"
            if detail ~= "" then lines[#lines + 1] = "    |cffaaaaaa" .. detail .. "|r" end
        end
    end
    local note = SC.GetContactNote(name)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cff66ccffPERSONAL TAGS|r"
    if #note.tags > 0 then lines[#lines + 1] = table.concat(note.tags, " Â· ") else lines[#lines + 1] = "|cff888888No tags yet.|r" end
    lines[#lines + 1] = "|cff66ccffPERSONAL NOTE|r"
    lines[#lines + 1] = note.text ~= "" and note.text or "|cff888888No personal note.|r"
    frame.content:SetText(table.concat(lines, "\n"))
    frame:Show()
end

---------------------------------------------------------------------
-- Quick Notes: one-click tags plus optional short free text.
---------------------------------------------------------------------
local function RefreshNoteTags()
    if not noteFrame or not noteFrame.name then return end
    for _, button in ipairs(noteFrame.tagButtons or {}) do
        local active = noteFrame.selectedTags[button.tag]
        button.bg:SetColorTexture(active and 0.14 or 0.08, active and 0.34 or 0.09, active and 0.48 or 0.12, 0.95)
    end
end

function SC.ShowQuickNote(name)
    if type(name) ~= "string" or name == "" then return end
    if not noteFrame then
        noteFrame = CreateFrame("Frame", "SmartChatQuickNote", UIParent, "BackdropTemplate")
        noteFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        noteFrame:SetFrameLevel(100)
        noteFrame:SetSize(390, 440)
        noteFrame:SetPoint("CENTER")
        noteFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        noteFrame:SetBackdropColor(0.035, 0.04, 0.055, 0.98)
        noteFrame:SetBackdropBorderColor(0.35, 0.42, 0.52, 1)
        noteFrame.title = noteFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        noteFrame.title:SetPoint("TOPLEFT", 12, -12)
        local close = CreateFrame("Button", nil, noteFrame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -3, -3)
        local hint = noteFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", 14, -36)
        hint:SetText("Select ready-made tags. Extra text is optional.")
        noteFrame.tagButtons, noteFrame.selectedTags = {}, {}
        for i, tag in ipairs(QUICK_TAGS) do
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            local b = CreateFrame("Button", nil, noteFrame)
            b:SetSize(176, 28)
            b:SetPoint("TOPLEFT", 14 + col * 182, -58 - row * 32)
            b.bg = b:CreateTexture(nil, "BACKGROUND")
            b.bg:SetAllPoints(); b.bg:SetColorTexture(0.08, 0.09, 0.12, 0.95)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("CENTER"); b.text:SetText(tag)
            b.tag = tag
            b:SetScript("OnClick", function(self)
                noteFrame.selectedTags[self.tag] = not noteFrame.selectedTags[self.tag] or nil
                RefreshNoteTags()
            end)
            noteFrame.tagButtons[#noteFrame.tagButtons + 1] = b
        end
        local noteLabel = noteFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noteLabel:SetPoint("TOPLEFT", 14, -322)
        noteLabel:SetText("Optional personal note")
        local eb = CreateFrame("EditBox", nil, noteFrame, "InputBoxTemplate")
        eb:SetPoint("TOPLEFT", 17, -344)
        eb:SetSize(345, 38)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(500)
        noteFrame.editBox = eb
        local save = CreateFrame("Button", nil, noteFrame, "UIPanelButtonTemplate")
        save:SetSize(112, 25); save:SetPoint("BOTTOMRIGHT", -14, 12); save:SetText("Save Note")
        save:SetScript("OnClick", function()
            local tags = {}
            for _, tag in ipairs(QUICK_TAGS) do if noteFrame.selectedTags[tag] then tags[#tags + 1] = tag end end
            SC.SaveContactNote(noteFrame.name, tags, noteFrame.editBox:GetText() or "")
            noteFrame:Hide()
            if journalFrame and journalFrame:IsShown() and journalFrame.name == noteFrame.name then SC.ShowPlayerJournal(noteFrame.name) end
            SC.Print("personal note saved for " .. tostring(noteFrame.name))
        end)
        tinsert(UISpecialFrames, "SmartChatQuickNote")
    end
    local note = SC.GetContactNote(name)
    noteFrame.name = name
    noteFrame.title:SetText("Quick Note â " .. (SC.ShortName and SC.ShortName(name) or name))
    noteFrame.selectedTags = {}
    for _, tag in ipairs(note.tags or {}) do noteFrame.selectedTags[tag] = true end
    noteFrame.editBox:SetText(note.text or "")
    RefreshNoteTags()
    noteFrame:Show()
end

---------------------------------------------------------------------
-- Contact context menu and group creation.
---------------------------------------------------------------------
local contextMenu
local function PrepareAddFriendCommand(name)
    local command = "/friend " .. tostring(name)
    if ChatFrame_OpenChat then
        ChatFrame_OpenChat(command, DEFAULT_CHAT_FRAME)
        SC.Print("Press Enter to send the Add Friend command.")
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox then
        local editBox = DEFAULT_CHAT_FRAME.editBox
        if ChatEdit_ActivateChat then ChatEdit_ActivateChat(editBox) end
        editBox:SetText(command)
        SC.Print("Press Enter to send the Add Friend command.")
    else
        SC.Print("Use /friend " .. tostring(name) .. " to add this player.")
    end
end

local function AddMenuItem(menu, label, fn, disabled)
    local info = UIDropDownMenu_CreateInfo()
    info.text, info.func, info.notCheckable, info.disabled = label, fn, true, disabled or false
    menu[#menu + 1] = info
end

function SC.ShowContactMenu(name, anchor)
    if not EasyMenu or not UIDropDownMenu_CreateInfo then
        if SC.ShowQuickNote then SC.ShowQuickNote(name) end
        return
    end
    if not contextMenu then contextMenu = CreateFrame("Frame", "SmartChatContactContextMenu", UIParent, "UIDropDownMenuTemplate") end
    local menu = {}
    local contactInfo = SC.GetContactInfo and SC.GetContactInfo(name) or {}
    if contactInfo.accountOnly then
        AddMenuItem(menu, "No active WoW character available", function() end, true)
    else
        AddMenuItem(menu, "Open Whisper", function() SC.OpenWhisperTab(name) end)
    end
    AddMenuItem(menu, SC.IsFavorite(name) and "Remove Favorite" or "Add to Favorites", function() SC.ToggleFavorite(name) end)
    AddMenuItem(menu, SC.IsContactPinned(name) and "Unpin Contact" or "Pin Contact", function() SC.ToggleContactPin(name) end)
    AddMenuItem(menu, "Add Quick Note", function() SC.ShowQuickNote(name) end)
    AddMenuItem(menu, "View Player Journal", function() SC.ShowPlayerJournal(name) end)

    local groups = EnsureSocial().groupOrder
    if #groups > 0 then
        local title = UIDropDownMenu_CreateInfo(); title.text = "Contact Groups"; title.isTitle = true; title.notCheckable = true; menu[#menu + 1] = title
        for _, groupName in ipairs(groups) do
            local g = groupName
            local members = EnsureSocial().groups[g] or {}
            AddMenuItem(menu, (members[Key(name)] and "Remove from " or "Add to ") .. g, function() SC.ToggleContactGroup(name, g) end)
        end
    end
    local friend = SC.Relation and SC.Relation(name) or ""
    if contactInfo.accountOnly then
        AddMenuItem(menu, "Player actions require a WoW character", function() end, true)
    elseif friend:find("F", 1, true) then
        AddMenuItem(menu, "Remove Friend", function()
            local api = C_FriendList
            local fn = api and api.RemoveFriend or RemoveFriend
            if fn then
                local ok, result = pcall(fn, name)
                if not ok then SC.Print("WoW did not allow friend removal: " .. tostring(result)) end
            end
        end)
    else
        AddMenuItem(menu, "Prepare Add Friend", function() PrepareAddFriendCommand(name) end)
    end
    if not contactInfo.accountOnly then
        AddMenuItem(menu, "Invite to Party", function()
            if SC.InviteContactsToParty then
                SC.InviteContactsToParty({ name })
            else
                SC.Print("Party invite helper is unavailable. Reload the UI and try again.")
            end
        end)
    end

    local ignored = false
    local api = C_FriendList
    if api and api.IsIgnored then
        local ok, value = pcall(api.IsIgnored, name)
        ignored = ok and value and true or false
    elseif api and api.IsOnIgnoredList then
        local ok, value = pcall(api.IsOnIgnoredList, name)
        ignored = ok and value and true or false
    end
    if not ignored and api and api.GetNumIgnores and api.GetIgnoreName then
        local okCount, count = pcall(api.GetNumIgnores)
        if okCount and type(count) == "number" then
            for i = 1, count do
                local okName, ignoredName = pcall(api.GetIgnoreName, i)
                if okName and type(ignoredName) == "string" and Key(ignoredName) == Key(name) then ignored = true break end
            end
        end
    end
    if contactInfo.accountOnly then
        AddMenuItem(menu, "Ignore requires a WoW character name", function() end, true)
    elseif ignored then
        AddMenuItem(menu, "Remove from Ignore", function()
            local fn = api and api.DelIgnore
            if fn then pcall(fn, name) end
        end)
    else
        AddMenuItem(menu, "Ignore Player", function()
            local fn = api and api.AddIgnore
            if fn then
                local ok, result = pcall(fn, name)
                if not ok or result == false then SC.Print("Could not add player to Ignore.") end
            else
                SC.Print("Ignore API is unavailable on this client.")
            end
        end)
    end
    AddMenuItem(menu, "Clear Local Journal Data", function()
        if SC.PromptClearPlayerJournalData then SC.PromptClearPlayerJournalData(name) end
    end)
    EasyMenu(menu, contextMenu, anchor or UIParent, 0, 0, "MENU")
end

function SC.PromptDeleteContactNote(name)
    if type(name) ~= "string" or name == "" or not StaticPopupDialogs then return end
    StaticPopupDialogs.SMARTCHAT_DELETE_CONTACT_NOTE = StaticPopupDialogs.SMARTCHAT_DELETE_CONTACT_NOTE or {
        text = "Delete the private note and quick tags for %s? Journal events and in-game relationships will remain.",
        button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(_, data)
            if SC.CreateLocalSocialRestorePoint then
                local saved, saveError = SC.CreateLocalSocialRestorePoint("Before deleting note for " .. tostring(data))
                if not saved then SC.Print(tostring(saveError or "Could not create a recovery point.")); return end
            end
            if SC.DeleteContactNote(data) then
                SC.Print("personal note deleted for " .. tostring(data) .. ". A local recovery point was saved.")
            else
                SC.Print("no saved note exists for " .. tostring(data))
            end
        end,
    }
    StaticPopup_Show("SMARTCHAT_DELETE_CONTACT_NOTE", name, nil, name)
end

function SC.PromptClearPlayerJournalData(name)
    if type(name) ~= "string" or name == "" or not StaticPopupDialogs then return end
    StaticPopupDialogs.SMARTCHAT_CLEAR_PLAYER_JOURNAL = StaticPopupDialogs.SMARTCHAT_CLEAR_PLAYER_JOURNAL or {
        text = "Clear SmartChat's local Journal history and private note for %s? Favorites, Pins, personal groups and the in-game Friend/Guild/Ignore lists will not change.",
        button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(_, data)
            if SC.CreateLocalSocialRestorePoint then
                local saved, saveError = SC.CreateLocalSocialRestorePoint("Before clearing Journal data for " .. tostring(data))
                if not saved then SC.Print(tostring(saveError or "Could not create a recovery point.")); return end
            end
            local ok, result = SC.ClearPlayerJournalData(data)
            if ok then
                SC.Print(string.format("local Journal data cleared for %s (%d events removed, %d shared events updated). A recovery point was saved.", tostring(data), result.removed or 0, result.updated or 0))
            else
                SC.Print(tostring(result or "Could not clear local Journal data."))
            end
        end,
    }
    StaticPopup_Show("SMARTCHAT_CLEAR_PLAYER_JOURNAL", name, nil, name)
end

local function PromptCreateGroup()
    if not StaticPopupDialogs then return end
    StaticPopupDialogs.SMARTCHAT_CREATE_CONTACT_GROUP = StaticPopupDialogs.SMARTCHAT_CREATE_CONTACT_GROUP or {
        text = "Create a SmartChat contact group:", button1 = ACCEPT, button2 = CANCEL,
        hasEditBox = true, maxLetters = 24, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(self)
            local edit = self.EditBox or _G[self:GetName() .. "EditBox"]
            local value = edit and edit:GetText() or ""
            if SC.CreateContactGroup(value) then SC.Print("contact group created: " .. value) else SC.Print("group name is empty, already exists, or the 30-group limit was reached") end
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            local button = parent.button1
            if button then button:Click() end
        end,
    }
    StaticPopup_Show("SMARTCHAT_CREATE_CONTACT_GROUP")
end
SC.PromptCreateContactGroup = PromptCreateGroup

function SC.PromptCreateContactGroupFromSelection(names)
    if type(names) ~= "table" or #names == 0 or not StaticPopupDialogs then return end
    local selected, seen = {}, {}
    for _, name in ipairs(names) do
        if type(name) == "string" and name ~= "" then
            local key = Key(name)
            if key ~= "" and not seen[key] then
                seen[key] = true
                selected[#selected + 1] = name
            end
        end
    end
    if #selected == 0 then return end
    StaticPopupDialogs.SMARTCHAT_CREATE_GROUP_FROM_SELECTION = StaticPopupDialogs.SMARTCHAT_CREATE_GROUP_FROM_SELECTION or {
        text = "Create a SmartChat group with %d selected contact(s):", button1 = ACCEPT, button2 = CANCEL,
        hasEditBox = true, maxLetters = 24, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(self, data)
            local edit = self.EditBox or _G[self:GetName() .. "EditBox"]
            local value = edit and edit:GetText() or ""
            if not SC.CreateContactGroup(value) then
                SC.Print("group name is empty, already exists, or the 30-group limit was reached")
                return
            end
            local group = EnsureSocial().groups[value]
            for _, name in ipairs(data or {}) do group[Key(name)] = name end
            if SC.RefreshWhisperInbox then SC.RefreshWhisperInbox() end
            SC.Print(string.format("created group %s with %d selected contact(s)", value, #(data or {})))
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            local button = parent.button1
            if button then button:Click() end
        end,
    }
    StaticPopup_Show("SMARTCHAT_CREATE_GROUP_FROM_SELECTION", #selected, nil, selected)
end

local function PromptRenameGroup(groupName)
    if type(groupName) ~= "string" or groupName == "" or not StaticPopupDialogs then return end
    StaticPopupDialogs.SMARTCHAT_RENAME_CONTACT_GROUP = StaticPopupDialogs.SMARTCHAT_RENAME_CONTACT_GROUP or {
        text = 'Rename contact group "%s":', button1 = ACCEPT, button2 = CANCEL,
        hasEditBox = true, maxLetters = 24, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(self, oldName)
            local edit = self.EditBox or _G[self:GetName() .. "EditBox"]
            local value = edit and edit:GetText() or ""
            local ok, err = SC.RenameContactGroup(oldName, value)
            if ok then
                SC.Print("contact group renamed: " .. oldName .. " â " .. value)
            else
                SC.Print(tostring(err or "Could not rename contact group."))
            end
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            local button = parent.button1
            if button then button:Click() end
        end,
    }
    local dialog = StaticPopup_Show("SMARTCHAT_RENAME_CONTACT_GROUP", groupName, nil, groupName)
    if dialog then
        local edit = dialog.EditBox or _G[dialog:GetName() .. "EditBox"]
        if edit then edit:SetText(groupName); edit:HighlightText(); edit:SetFocus() end
    end
end
SC.PromptRenameContactGroup = PromptRenameGroup

local function PromptDeleteGroup(groupName)
    if not groupName or not StaticPopupDialogs then return end
    StaticPopupDialogs.SMARTCHAT_DELETE_CONTACT_GROUP = StaticPopupDialogs.SMARTCHAT_DELETE_CONTACT_GROUP or {
        text = 'Delete contact group "%s"?', button1 = YES, button2 = NO,
        timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(_, data)
            if SC.CreateLocalSocialRestorePoint then
                local saved, saveError = SC.CreateLocalSocialRestorePoint("Before deleting contact group " .. tostring(data))
                if not saved then SC.Print(tostring(saveError or "Could not create a recovery point.")); return end
            end
            if SC.DeleteContactGroup(data) then SC.Print("contact group deleted: " .. tostring(data) .. ". A local recovery point was saved.") end
        end,
    }
    StaticPopup_Show("SMARTCHAT_DELETE_CONTACT_GROUP", groupName, nil, groupName)
end
SC.PromptDeleteContactGroup = PromptDeleteGroup

---------------------------------------------------------------------
-- Local Social Backup / Restore. Portable text format; no chat messages,
-- account credentials, Battle.net IDs or game chat history are exported.
---------------------------------------------------------------------
local BACKUP_HEADER = "SMARTCHAT_SOCIAL_BACKUP|1"
local BACKUP_MAX_BYTES = 400000

local function BackupEncode(value)
    local textValue = tostring(value == nil and "" or value)
    textValue = textValue:gsub("%%", "%%25"):gsub("|", "%%7C")
    textValue = textValue:gsub("\t", "%%09"):gsub("\r", "%%0D"):gsub("\n", "%%0A")
        :gsub(string.char(1), "%%01"):gsub(string.char(2), "%%02")
    return textValue
end

local function BackupDecode(value)
    return (tostring(value or ""):gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function BackupSplit(line)
    local fields = {}
    for field in (tostring(line or "") .. "|"):gmatch("(.-)|") do fields[#fields + 1] = BackupDecode(field) end
    return fields
end

local function BackupJoin(values)
    local result = {}
    for _, value in ipairs(values or {}) do result[#result + 1] = tostring(value or "") end
    return table.concat(result, string.char(1))
end

local function BackupUnjoin(value, maxItems)
    local result = {}
    for part in (tostring(value or "") .. string.char(1)):gmatch("(.-)" .. string.char(1)) do
        if part ~= "" then result[#result + 1] = part end
        if #result >= (maxItems or 100) then break end
    end
    return result
end

function SC.ExportSocialBackup()
    local social, journal = EnsureSocial(), EnsureJournal()
    local lines = { BACKUP_HEADER }
    for _, name in pairs(social.favorites) do lines[#lines + 1] = "F|" .. BackupEncode(name) end
    for _, name in pairs(social.pinned) do lines[#lines + 1] = "P|" .. BackupEncode(name) end
    for _, groupName in ipairs(social.groupOrder) do
        lines[#lines + 1] = "G|" .. BackupEncode(groupName)
        local group = social.groups[groupName] or {}
        for _, name in pairs(group) do lines[#lines + 1] = "M|" .. BackupEncode(groupName) .. "|" .. BackupEncode(name) end
    end
    for _, templateName in ipairs(social.groupTemplateOrder or {}) do
        local template = social.groupTemplates and social.groupTemplates[templateName]
        if type(template) == "table" then
            lines[#lines + 1] = "T|" .. BackupEncode(templateName)
            for _, name in pairs(template.members or {}) do
                lines[#lines + 1] = "TM|" .. BackupEncode(templateName) .. "|" .. BackupEncode(name)
            end
        end
    end
    for _, note in pairs(journal.notes) do
        if type(note) == "table" and type(note.name) == "string" then
            lines[#lines + 1] = table.concat({ "N", BackupEncode(note.name), BackupEncode(BackupJoin(note.tags or {})), BackupEncode(note.text or ""), BackupEncode(note.updated or 0) }, "|")
        end
    end
    for _, event in ipairs(journal.events) do
        if type(event) == "table" then
            local fields = {
                "E", event.t or 0, event.type or "", event.title or "", event.detail or "", BackupJoin(event.names or {}),
                event.last or 0, event.count or 0, event.incoming or 0, event.outgoing or 0,
                event.duration or 0, event.started or 0, event.ended or 0, event.location or "", event.locations or "",
                event.instanceType or "", event.difficultyName or "", event.difficultyID or 0,
                event.instanceID or 0, event.groupSize or 0, event.maxPlayers or 0, event.sessionKind or "",
                event.questID or 0, event.attendance or "",
            }
            for i = 2, #fields do fields[i] = BackupEncode(fields[i]) end
            lines[#lines + 1] = table.concat(fields, "|")
        end
    end
    local output = table.concat(lines, "\n")
    if #output > BACKUP_MAX_BYTES then return nil, "Backup is too large. Reduce the stored history or retention period and try again." end
    return output
end

function SC.PreviewSocialBackup(input)
    if type(input) ~= "string" or input == "" then return nil, "Paste a SmartChat backup first." end
    if #input > BACKUP_MAX_BYTES then return nil, "Backup exceeds the 400 KB safety limit." end
    local normalized = input:gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = {}
    for line in (normalized .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then lines[#lines + 1] = line end
        if #lines > 6000 then return nil, "Backup contains too many records." end
    end
    if not lines[1] or lines[1] ~= BACKUP_HEADER then return nil, "Unsupported or invalid SmartChat backup header." end

    local preview = {
        favorites = 0, pins = 0, groups = 0, members = 0,
        templates = 0, templateMembers = 0,
        notes = 0, events = 0, invalid = 0, records = 0,
        bytes = #input,
    }
    local backupTemplateNames = {}
    for index = 2, #lines do
        local f = BackupSplit(lines[index])
        local record = f[1]
        local valid = false
        if record == "F" or record == "P" then
            valid = type(f[2]) == "string" and f[2] ~= "" and #f[2] <= 80
            if valid then preview[record == "F" and "favorites" or "pins"] = preview[record == "F" and "favorites" or "pins"] + 1 end
        elseif record == "G" then
            valid = type(f[2]) == "string" and f[2] ~= "" and #f[2] <= 24
            if valid then preview.groups = preview.groups + 1 end
        elseif record == "M" then
            valid = type(f[2]) == "string" and f[2] ~= "" and #f[2] <= 24 and type(f[3]) == "string" and f[3] ~= "" and #f[3] <= 80
            if valid then preview.members = preview.members + 1 end
        elseif record == "T" then
            valid = type(f[2]) == "string" and f[2] ~= "" and #f[2] <= 24
            if valid then
                preview.templates = preview.templates + 1
                backupTemplateNames[f[2]:lower()] = true
            end
        elseif record == "TM" then
            valid = type(f[2]) == "string" and f[2] ~= "" and #f[2] <= 24 and type(f[3]) == "string" and f[3] ~= "" and #f[3] <= 80 and backupTemplateNames[tostring(f[2] or ""):lower()] == true
            if valid then preview.templateMembers = preview.templateMembers + 1 end
        elseif record == "N" then
            valid = type(f[2]) == "string" and f[2] ~= "" and #f[2] <= 80
            if valid then preview.notes = preview.notes + 1 end
        elseif record == "E" then
            local stamp = tonumber(f[2])
            local names = BackupUnjoin(f[6], 40)
            valid = stamp ~= nil and stamp > 0 and type(f[3]) == "string" and f[3] ~= "" and #names > 0
            if valid then preview.events = preview.events + 1 end
        end
        if valid then preview.records = preview.records + 1 else preview.invalid = preview.invalid + 1 end
    end
    preview.empty = preview.records == 0
    preview.valid = preview.invalid == 0 and not preview.empty
    return preview
end

-- One local restore point protects the current social data before an external
-- import. This is stored in SavedVariables, not as an operating-system file.
local function CopySavedValue(value, depth, budget)
    if type(value) ~= "table" then
        if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then return value end
        return nil
    end
    depth = depth or 0
    budget = budget or { left = 100000 }
    if depth > 12 or budget.left <= 0 then return nil end
    local copy = {}
    for key, child in pairs(value) do
        budget.left = budget.left - 1
        local keyType = type(key)
        if keyType == "string" or keyType == "number" then
            local childCopy = CopySavedValue(child, depth + 1, budget)
            if childCopy ~= nil then copy[key] = childCopy end
        end
        if budget.left <= 0 then break end
    end
    return copy
end

function SC.CreateLocalSocialRestorePoint(label)
    if not SC.db then return false, "SavedVariables are not ready." end
    SC.db.socialBackup = SC.db.socialBackup or {}
    local point = {
        created = time(), label = tostring(label or "Manual restore point"):sub(1, 60),
        social = CopySavedValue(SC.db.social or {}) or {},
        journal = CopySavedValue(SC.db.journal or {}) or {},
    }
    SC.db.socialBackup.restorePoint = point
    return true, point
end

function SC.GetLocalSocialRestorePoint()
    local backup = SC.db and SC.db.socialBackup
    local point = backup and backup.restorePoint
    if type(point) == "table" and type(point.social) == "table" and type(point.journal) == "table" then return point end
    return nil
end

function SC.RestoreLocalSocialRestorePoint()
    local point = SC.GetLocalSocialRestorePoint()
    if not point then return false, "No local restore point is available." end
    local currentSocial = CopySavedValue(SC.db.social or {}) or {}
    local currentJournal = CopySavedValue(SC.db.journal or {}) or {}
    SC.db.social = CopySavedValue(point.social) or {}
    SC.db.journal = CopySavedValue(point.journal) or {}
    whisperEventIndexReady = false; wipe(whisperEventIndex)
    point.social, point.journal = currentSocial, currentJournal
    point.created = time()
    point.label = "Previous local state (swap-back available)"
    if SC.RefreshWhisperInbox then SC.RefreshWhisperInbox() end
    if SC.RefreshWhisperContacts then SC.RefreshWhisperContacts() end
    return true, point
end

function SC.ImportSocialBackup(input)
    local preview, previewError = SC.PreviewSocialBackup(input)
    if not preview then return false, previewError end
    if preview.invalid > 0 then
        return false, string.format("Backup contains %d invalid record(s). Validate a clean backup before importing.", preview.invalid)
    end
    if preview.empty then return false, "This backup contains no restorable records." end
    local lines = {}
    local normalized = input:gsub("\r\n", "\n"):gsub("\r", "\n")
    for line in (normalized .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then lines[#lines + 1] = line end
    end

    local restoreOK, restoreResult = SC.CreateLocalSocialRestorePoint("Before backup import")
    if not restoreOK then return false, restoreResult end
    local social, journal = EnsureSocial(), EnsureJournal()
    local imported = { favorites = 0, pins = 0, groups = 0, members = 0, templates = 0, templateMembers = 0, notes = 0, events = 0 }
    local localNoteCount = 0
    for _, note in pairs(journal.notes) do if type(note) == "table" then localNoteCount = localNoteCount + 1 end end
    local knownEvents = {}
    for _, event in ipairs(journal.events) do
        local namesKey = BackupJoin(event.names or {})
        knownEvents[tostring(event.t or 0) .. "|" .. tostring(event.type or "") .. "|" .. tostring(event.title or "") .. "|" .. namesKey] = true
    end

    for index = 2, #lines do
        local f = BackupSplit(lines[index])
        local record = f[1]
        if record == "F" or record == "P" then
            local name = tostring(f[2] or ""):sub(1, 80)
            if name ~= "" then
                local target = record == "F" and social.favorites or social.pinned
                local key = Key(name)
                if not target[key] then target[key] = name; imported[record == "F" and "favorites" or "pins"] = imported[record == "F" and "favorites" or "pins"] + 1 end
            end
        elseif record == "G" then
            local name = tostring(f[2] or ""):sub(1, 24)
            if name ~= "" and not social.groups[name] and #social.groupOrder < 30 then
                social.groups[name] = {}; social.groupOrder[#social.groupOrder + 1] = name; imported.groups = imported.groups + 1
            end
        elseif record == "M" then
            local groupName, name = tostring(f[2] or ""):sub(1, 24), tostring(f[3] or ""):sub(1, 80)
            if groupName ~= "" and name ~= "" then
                if not social.groups[groupName] and #social.groupOrder < 30 then social.groups[groupName] = {}; social.groupOrder[#social.groupOrder + 1] = groupName end
                local group = social.groups[groupName]
                if type(group) == "table" and not group[Key(name)] then group[Key(name)] = name; imported.members = imported.members + 1 end
            end
        elseif record == "T" then
            local templateName = tostring(f[2] or ""):sub(1, 24)
            social.groupTemplates = social.groupTemplates or {}; social.groupTemplateOrder = social.groupTemplateOrder or {}
            local exists = false
            for _, existing in ipairs(social.groupTemplateOrder) do if tostring(existing):lower() == templateName:lower() then exists = true; break end end
            if templateName ~= "" and not exists and #social.groupTemplateOrder < 20 then
                social.groupTemplates[templateName] = { members = {}, source = "Imported", created = time(), updated = time() }
                social.groupTemplateOrder[#social.groupTemplateOrder + 1] = templateName
                imported.templates = imported.templates + 1
            end
        elseif record == "TM" then
            local templateName, name = tostring(f[2] or ""):sub(1, 24), tostring(f[3] or ""):sub(1, 80)
            local actualName
            for _, existing in ipairs(social.groupTemplateOrder or {}) do if tostring(existing):lower() == templateName:lower() then actualName = existing; break end end
            local template = actualName and social.groupTemplates and social.groupTemplates[actualName]
            if type(template) == "table" then template.members = template.members or {} end
            if type(template) == "table" and name ~= "" and not template.members[Key(name)] then
                template.members[Key(name)] = name
                imported.templateMembers = imported.templateMembers + 1
            end
        elseif record == "N" then
            local name = tostring(f[2] or ""):sub(1, 80)
            if name ~= "" then
                local key, tags, textValue, updated = Key(name), BackupUnjoin(f[3], 32), tostring(f[4] or ""):sub(1, 500), tonumber(f[5]) or 0
                local localNote = journal.notes[key]
                if type(localNote) ~= "table" then
                    if localNoteCount >= 500 then
                        name = nil
                    else
                        localNote = { name = name, tags = {}, text = "", updated = 0 }
                        localNoteCount = localNoteCount + 1
                    end
                end
                if name then
                local tagSet, mergedTags = {}, {}
                for _, tag in ipairs(localNote.tags or {}) do if type(tag) == "string" and not tagSet[tag] then mergedTags[#mergedTags + 1] = tag; tagSet[tag] = true end end
                for _, tag in ipairs(tags) do if type(tag) == "string" and tag ~= "" and not tagSet[tag] then mergedTags[#mergedTags + 1] = tag; tagSet[tag] = true end end
                if updated >= (tonumber(localNote.updated) or 0) then localNote.text = textValue; localNote.updated = updated end
                localNote.name, localNote.tags = localNote.name or name, mergedTags
                journal.notes[key] = localNote
                imported.notes = imported.notes + 1
                end
            end
        elseif record == "E" then
            local t, kind, title = tonumber(f[2]), tostring(f[3] or ""), tostring(f[4] or "")
            local names = BackupUnjoin(f[6], 40)
            if t and t > 0 and kind ~= "" and #names > 0 then
                local signature = tostring(t) .. "|" .. kind .. "|" .. title .. "|" .. BackupJoin(names)
                if not knownEvents[signature] then
                    local event = {
                        t = t, type = kind:sub(1, 32), title = title:sub(1, 120), detail = tostring(f[5] or ""):sub(1, 300), names = names,
                        last = ((tonumber(f[7]) or 0) > 0 and tonumber(f[7])) or t, count = tonumber(f[8]) or nil, incoming = tonumber(f[9]) or nil,
                        outgoing = tonumber(f[10]) or nil, duration = tonumber(f[11]) or nil,
                        started = tonumber(f[12]) or nil, ended = tonumber(f[13]) or nil,
                        location = tostring(f[14] or ""):sub(1, 100), locations = tostring(f[15] or ""):sub(1, 400),
                        instanceType = tostring(f[16] or ""):sub(1, 20), difficultyName = tostring(f[17] or ""):sub(1, 60),
                        difficultyID = tonumber(f[18]) or nil, instanceID = tonumber(f[19]) or nil,
                        groupSize = tonumber(f[20]) or nil, maxPlayers = tonumber(f[21]) or nil,
                        sessionKind = tostring(f[22] or ""):sub(1, 20), questID = tonumber(f[23]) or nil,
                        attendance = tostring(f[24] or ""):sub(1, 8000),
                    }
                    journal.events[#journal.events + 1] = event
                    knownEvents[signature] = true
                    imported.events = imported.events + 1
                end
            end
        end
    end
    table.sort(journal.events, function(a, b)
        return (tonumber(type(a) == "table" and a.t or 0) or 0) < (tonumber(type(b) == "table" and b.t or 0) or 0)
    end)
    whisperEventIndexReady = false; wipe(whisperEventIndex)
    SC.PruneJournal()
    if SC.RefreshWhisperInbox then SC.RefreshWhisperInbox() end
    if SC.RefreshWhisperContacts then SC.RefreshWhisperContacts() end
    return true, imported
end

local backupFrame
function SC.ShowSocialBackup()
    local function CountValues(source)
        local total = 0
        for _, value in pairs(source or {}) do if value then total = total + 1 end end
        return total
    end
    local function BackupStats()
        local social, journal = EnsureSocial(), EnsureJournal()
        local members, templateMembers = 0, 0
        for _, groupName in ipairs(social.groupOrder or {}) do
            members = members + CountValues(social.groups[groupName])
        end
        for _, templateName in ipairs(social.groupTemplateOrder or {}) do
            templateMembers = templateMembers + CountValues(social.groupTemplates and social.groupTemplates[templateName] and social.groupTemplates[templateName].members)
        end
        local notes, events = 0, 0
        for _, note in pairs(journal.notes or {}) do if type(note) == "table" then notes = notes + 1 end end
        for _, event in ipairs(journal.events or {}) do if type(event) == "table" then events = events + 1 end end
        return {
            favorites = CountValues(social.favorites), pins = CountValues(social.pinned),
            groups = #(social.groupOrder or {}), members = members,
            templates = #(social.groupTemplateOrder or {}), templateMembers = templateMembers,
            notes = notes, events = events,
        }
    end
    local function SummaryText(stats)
        return string.format("Favorites  %d     Pins  %d     Groups  %d     Group Templates  %d     Template Members  %d     Notes  %d     Events  %d",
            stats.favorites or 0, stats.pins or 0, stats.groups or 0, stats.templates or 0, stats.templateMembers or 0, stats.notes or 0, stats.events or 0)
    end
    local function MakeText(parent, template, point, x, y, width, textValue)
        local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
        fs:SetPoint(point or "TOPLEFT", parent, point or "TOPLEFT", x or 0, y or 0)
        if width then fs:SetWidth(width) end
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP"); fs:SetWordWrap(true)
        fs:SetText(textValue or "")
        return fs
    end
    local function MakeEditBox(parent, scroll, width, height)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetMaxLetters(BACKUP_MAX_BYTES)
        edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
        edit:SetWidth(width); edit:SetHeight(height); edit:SetTextInsets(8, 8, 8, 8)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        local function UpdateHeight()
            local measured = edit.GetStringHeight and (edit:GetStringHeight() or height) or height
            edit:SetHeight(math.min(12000, math.max(height, measured + 22)))
        end
        edit:SetScript("OnTextChanged", UpdateHeight)
        scroll:SetScrollChild(edit)
        scroll:SetScript("OnSizeChanged", function(self) edit:SetWidth(math.max(300, self:GetWidth() - 6)) end)
        return edit, UpdateHeight
    end
    if not backupFrame then
        backupFrame = CreateFrame("Frame", "SmartChatSocialBackup", UIParent, "BackdropTemplate")
        backupFrame:SetFrameStrata("FULLSCREEN_DIALOG"); backupFrame:SetFrameLevel(105)
        backupFrame:SetSize(700, 555); backupFrame:SetPoint("CENTER")
        backupFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
        backupFrame:SetBackdropColor(0.035, 0.04, 0.055, 1)
        backupFrame:SetScript("OnShow", function(self)
            if SC.RaiseWindow then SC.RaiseWindow(self, "FULLSCREEN_DIALOG") end
        end)
        local title = backupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 20, -18); title:SetText("Social Data Backup")
        local subtitle = backupFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
        subtitle:SetText("Local only  Â·  No internet  Â·  Whisper message text is never included")
        local close = CreateFrame("Button", nil, backupFrame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -4, -4)

        local function CreatePage(name)
            local page = CreateFrame("Frame", nil, backupFrame)
            page:SetPoint("TOPLEFT", 18, -88); page:SetPoint("BOTTOMRIGHT", -18, 18)
            page:Hide()
            return page
        end
        local exportPage, importPage, localPage = CreatePage("export"), CreatePage("import"), CreatePage("local")
        backupFrame.exportPage, backupFrame.importPage, backupFrame.localPage = exportPage, importPage, localPage

        local function CreateTab(label, x)
            local b = CreateFrame("Button", nil, backupFrame, "UIPanelButtonTemplate")
            b:SetSize(130, 26); b:SetPoint("TOPLEFT", 20 + x, -54); b:SetText(label)
            return b
        end
        backupFrame.exportTab = CreateTab("Export Backup", 0)
        backupFrame.importTab = CreateTab("Import Backup", 136)
        backupFrame.localTab = CreateTab("Local Save", 272)
        local function ShowPage(pageName)
            local isExport, isImport, isLocal = pageName == "export", pageName == "import", pageName == "local"
            exportPage:SetShown(isExport); importPage:SetShown(isImport); localPage:SetShown(isLocal)
            backupFrame.exportTab:SetEnabled(not isExport)
            backupFrame.importTab:SetEnabled(not isImport)
            backupFrame.localTab:SetEnabled(not isLocal)
            if isLocal and backupFrame.RefreshLocalSave then backupFrame.RefreshLocalSave() end
        end
        backupFrame.exportTab:SetScript("OnClick", function() ShowPage("export") end)
        backupFrame.importTab:SetScript("OnClick", function() ShowPage("import") end)
        backupFrame.localTab:SetScript("OnClick", function() ShowPage("local") end)

        -- Local Save page: normal in-game data is already persisted by WoW's
        -- SavedVariables system. Portable export/import is only for moving data.
        MakeText(localPage, "GameFontNormal", "TOPLEFT", 4, -2, 620, "Automatic local saving")
        MakeText(localPage, "GameFontHighlightSmall", "TOPLEFT", 4, -25, 640,
            "SmartChat stores your Social Hub data in its SavedVariables. WoW writes this data on logout or reload. You do not need Ctrl+C or Ctrl+V during normal play, and no internet connection is used.")
        local localStatus = MakeText(localPage, "GameFontHighlight", "TOPLEFT", 4, -86, 640, "Local data is stored automatically by the game.")
        backupFrame.localStatus = localStatus
        local pointStatus = MakeText(localPage, "GameFontHighlightSmall", "TOPLEFT", 4, -126, 640, "No extra restore point has been created yet.")
        backupFrame.pointStatus = pointStatus
        local function RefreshLocalSave()
            local point = SC.GetLocalSocialRestorePoint and SC.GetLocalSocialRestorePoint()
            if point then
                pointStatus:SetText("Recovery point: " .. tostring(point.label or "Local restore point") .. "\nCreated: " .. date("%Y-%m-%d %H:%M:%S", tonumber(point.created) or time()) .. "\nA single previous-state snapshot is kept locally. Creating a new one replaces it.")
                backupFrame.restoreLocalButton:Enable()
            else
                pointStatus:SetText("No extra restore point exists. Your current data is still saved normally by WoW SavedVariables.")
                backupFrame.restoreLocalButton:Disable()
            end
        end
        backupFrame.RefreshLocalSave = RefreshLocalSave
        local createLocalButton = CreateFrame("Button", nil, localPage, "UIPanelButtonTemplate")
        createLocalButton:SetSize(145, 25); createLocalButton:SetPoint("TOPLEFT", localPage, "TOPLEFT", 4, -180)
        createLocalButton:SetText("Create Restore Point")
        createLocalButton:SetScript("OnClick", function()
            local ok, point = SC.CreateLocalSocialRestorePoint("Manual local restore point")
            if ok then localStatus:SetText("Restore point created locally. No file or clipboard action was needed."); RefreshLocalSave()
            else localStatus:SetText(tostring(point or "Could not create restore point.")) end
        end)
        backupFrame.restoreLocalButton = CreateFrame("Button", nil, localPage, "UIPanelButtonTemplate")
        backupFrame.restoreLocalButton:SetSize(150, 25); backupFrame.restoreLocalButton:SetPoint("LEFT", createLocalButton, "RIGHT", 10, 0)
        backupFrame.restoreLocalButton:SetText("Restore Previous State")
        backupFrame.restoreLocalButton:SetScript("OnClick", function()
            if not StaticPopupDialogs then return end
            StaticPopupDialogs.SMARTCHAT_RESTORE_LOCAL_POINT = StaticPopupDialogs.SMARTCHAT_RESTORE_LOCAL_POINT or {
                text = "Restore the previous local Social Hub and Player Journal state? Current data will be swapped into the restore point so you can switch back.",
                button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
                OnAccept = function()
                    local ok, result = SC.RestoreLocalSocialRestorePoint()
                    if ok then localStatus:SetText("Local data restored. The previous current state is now available as the swap-back point.")
                    else localStatus:SetText(tostring(result or "Restore failed.")) end
                    RefreshLocalSave()
                end,
            }
            StaticPopup_Show("SMARTCHAT_RESTORE_LOCAL_POINT")
        end)
        backupFrame.restoreLocalButton:Disable()
        createLocalButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Create a one-time local recovery copy of Favorites, Pins, Groups, Group Templates, Notes and Player Journal events. It stays in SavedVariables and is not exported.")
            GameTooltip:Show()
        end)
        createLocalButton:SetScript("OnLeave", GameTooltip_Hide)
        backupFrame.restoreLocalButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Swap the saved recovery point with the current local Social Hub and Player Journal data. A confirmation appears first.")
            GameTooltip:Show()
        end)
        backupFrame.restoreLocalButton:SetScript("OnLeave", GameTooltip_Hide)
        MakeText(localPage, "GameFontDisableSmall", "TOPLEFT", 4, -224, 640,
            "Portable Export / Import is only needed when moving Social Hub data to another installation or keeping an external copy. That transfer still uses manual copy and paste because AddOns cannot freely write files or access the operating-system clipboard.")

        -- Export page: a clear 3-step workflow.
        MakeText(exportPage, "GameFontNormal", "TOPLEFT", 4, -2, 620, "Create a portable backup")
        MakeText(exportPage, "GameFontHighlightSmall", "TOPLEFT", 4, -25, 640,
            "1. Generate your backup.  2. Select the text and press Ctrl+C.  3. Paste it into a plain-text file (for example, SmartChat-Backup.txt) and save it outside the game.")
        local statsLabel = MakeText(exportPage, "GameFontHighlightSmall", "TOPLEFT", 4, -67, 650, "Current data: " .. SummaryText(BackupStats()))
        backupFrame.statsLabel = statsLabel
        local exportScroll = CreateFrame("ScrollFrame", nil, exportPage, "UIPanelScrollFrameTemplate")
        exportScroll:SetPoint("TOPLEFT", 2, -98); exportScroll:SetPoint("BOTTOMRIGHT", -28, 72)
        local exportEdit, updateExportHeight = MakeEditBox(exportPage, exportScroll, 620, 270)
        backupFrame.exportEdit, backupFrame.exportScroll = exportEdit, exportScroll
        local exportStatus = MakeText(exportPage, "GameFontHighlightSmall", "BOTTOMLEFT", 4, 48, 650, "No backup generated yet.")
        backupFrame.exportStatus = exportStatus
        local function Button(parent, label, width, point, relative, relPoint, x, y, callback)
            local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
            b:SetSize(width, 25); b:SetPoint(point, relative or parent, relPoint or point, x or 0, y or 0)
            b:SetText(label); b:SetScript("OnClick", callback)
            return b
        end
        Button(exportPage, "Generate & Select", 125, "BOTTOMLEFT", exportPage, "BOTTOMLEFT", 2, 10, function()
            local output, err = SC.ExportSocialBackup()
            if not output then exportStatus:SetText(err or "Export failed."); return end
            exportEdit:SetText(output); updateExportHeight(); exportScroll:SetVerticalScroll(0)
            exportEdit:SetFocus(); exportEdit:HighlightText()
            local stats = BackupStats()
            statsLabel:SetText("Current data: " .. SummaryText(stats))
            exportStatus:SetText(string.format("Backup generated and selected Â· %.1f KB Â· %d records. Press Ctrl+C, then paste into a text file and save it.", #output / 1024, stats.favorites + stats.pins + stats.groups + stats.members + stats.templates + stats.templateMembers + stats.notes + stats.events))
        end)
        Button(exportPage, "Select All Text", 115, "LEFT", exportPage, "BOTTOMLEFT", 135, 10, function()
            if exportEdit:GetText() == "" then exportStatus:SetText("Generate a backup first."); return end
            exportEdit:SetFocus(); exportEdit:HighlightText()
            exportStatus:SetText("Backup text selected. Press Ctrl+C, then paste it into a text file and save it.")
        end)
        Button(exportPage, "Clear", 72, "LEFT", exportPage, "BOTTOMLEFT", 258, 10, function()
            exportEdit:SetText(""); exportScroll:SetVerticalScroll(0); exportStatus:SetText("Export box cleared.")
        end)

        -- Import page: paste, validate, review, then merge.
        MakeText(importPage, "GameFontNormal", "TOPLEFT", 4, -2, 620, "Restore a SmartChat backup")
        MakeText(importPage, "GameFontHighlightSmall", "TOPLEFT", 4, -25, 640,
            "1. Open your saved .txt backup.  2. Copy all text and paste it into the box below with Ctrl+V.  3. Validate and review the contents before merging.")
        local importScroll = CreateFrame("ScrollFrame", nil, importPage, "UIPanelScrollFrameTemplate")
        importScroll:SetPoint("TOPLEFT", 2, -66); importScroll:SetPoint("BOTTOMRIGHT", -28, 168)
        local importEdit, updateImportHeight = MakeEditBox(importPage, importScroll, 620, 230)
        backupFrame.importEdit, backupFrame.importScroll = importEdit, importScroll
        local previewTitle = importPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        previewTitle:SetPoint("TOPLEFT", importScroll, "BOTTOMLEFT", 4, -10)
        previewTitle:SetText("Backup preview")
        local previewLabel = importPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        previewLabel:SetPoint("TOPLEFT", previewTitle, "BOTTOMLEFT", 0, -6)
        previewLabel:SetWidth(640); previewLabel:SetJustifyH("LEFT"); previewLabel:SetJustifyV("TOP"); previewLabel:SetWordWrap(true)
        previewLabel:SetText("Paste a backup, then choose Validate Backup.")
        backupFrame.previewLabel = previewLabel
        local importStatus = MakeText(importPage, "GameFontHighlightSmall", "BOTTOMLEFT", 4, 48, 650, "Nothing imported yet.")
        backupFrame.importStatus = importStatus
        local validatedText
        local mergeButton
        local function InvalidatePreview()
            validatedText = nil
            if mergeButton then mergeButton:SetEnabled(false) end
            previewLabel:SetText("Backup changed. Validate it again before importing.")
        end
        importEdit:SetScript("OnTextChanged", function()
            updateImportHeight(); InvalidatePreview()
        end)
        Button(importPage, "Focus Paste Box", 112, "BOTTOMLEFT", importPage, "BOTTOMLEFT", 2, 10, function()
            importEdit:SetFocus(); importEdit:SetCursorPosition(0)
            importStatus:SetText("Paste your backup text here with Ctrl+V.")
        end)
        Button(importPage, "Validate Backup", 112, "LEFT", importPage, "BOTTOMLEFT", 120, 10, function()
            local textValue = importEdit:GetText() or ""
            local preview, err = SC.PreviewSocialBackup(textValue)
            if not preview then
                validatedText = nil; mergeButton:SetEnabled(false)
                previewLabel:SetText("Validation failed: " .. tostring(err))
                importStatus:SetText("Nothing was changed.")
                return
            end
            validatedText = (preview.invalid == 0 and not preview.empty) and textValue or nil
            mergeButton:SetEnabled(validatedText ~= nil)
            previewLabel:SetText(string.format(
                "|cff66ccffBackup contents|r\nFavorites: %d  Â·  Pins: %d  Â·  Groups: %d  Â·  Members: %d\nTemplates: %d  Â·  Template Members: %d  Â·  Notes: %d  Â·  Events: %d\nTotal records: %d  Â·  File size: %.1f KB  Â·  Invalid rows: %d\n%s",
                preview.favorites, preview.pins, preview.groups, preview.members, preview.templates, preview.templateMembers, preview.notes, preview.events,
                preview.records, (preview.bytes or 0) / 1024, preview.invalid,
                preview.invalid > 0 and "|cffff6666Invalid rows found. Import is disabled until you provide a clean backup.|r" or (preview.empty and "|cffffcc66No restorable records were found in this backup.|r" or "|cff66dd88Valid backup. Import will merge missing data and keep existing local data.|r")))
            importStatus:SetText(preview.invalid > 0 and "Validation found invalid rows. No data was changed." or (preview.empty and "The backup is empty. Nothing can be imported." or "Backup validated. Review the summary, then choose Import & Merge."))
        end)
        mergeButton = Button(importPage, "Import & Merge", 112, "LEFT", importPage, "BOTTOMLEFT", 238, 10, function()
            local currentText = importEdit:GetText() or ""
            if not validatedText or currentText ~= validatedText then
                mergeButton:SetEnabled(false); importStatus:SetText("Validate the current backup text before importing."); return
            end
            local ok, result = SC.ImportSocialBackup(currentText)
            if not ok then
                mergeButton:SetEnabled(false); validatedText = nil
                importStatus:SetText(result or "Import failed."); return
            end
            mergeButton:SetEnabled(false); validatedText = nil
            importStatus:SetText(string.format("Merge complete: %d favorites, %d pins, %d groups, %d members, %d templates, %d template members, %d notes and %d events processed.",
                result.favorites, result.pins, result.groups, result.members, result.templates, result.templateMembers, result.notes, result.events))
            previewLabel:SetText(previewLabel:GetText() .. "\n|cff66dd88Import completed. You can clear the box or keep it for reference.|r")
        end)
        Button(importPage, "Clear", 72, "LEFT", importPage, "BOTTOMLEFT", 356, 10, function()
            importEdit:SetText(""); importScroll:SetVerticalScroll(0); validatedText = nil
            mergeButton:SetEnabled(false); previewLabel:SetText("Paste a backup, then choose Validate Backup.")
            importStatus:SetText("Import box cleared. Your saved Social Hub data was not changed.")
        end)
        mergeButton:SetEnabled(false)
        backupFrame:EnableMouse(true)
        tinsert(UISpecialFrames, "SmartChatSocialBackup")
        ShowPage("export")
    end
    backupFrame.statsLabel:SetText("Current data: " .. SummaryText(BackupStats()))
    backupFrame:Show()
    if SC.RaiseWindow then SC.RaiseWindow(backupFrame, "FULLSCREEN_DIALOG") end
    backupFrame.exportPage:Show()
    backupFrame.importPage:Hide()
    backupFrame.localPage:Hide()
    backupFrame.exportTab:SetEnabled(false)
    backupFrame.importTab:SetEnabled(true)
    backupFrame.localTab:SetEnabled(true)
end

---------------------------------------------------------------------
-- Settings window: opt-in journal, low-cost tracking and retention.
---------------------------------------------------------------------
local function SettingsHelp(parent, anchor, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18); b:SetPoint("LEFT", anchor, "RIGHT", 3, 0)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER"); fs:SetText("(?)"); fs:SetTextColor(0.4, 0.8, 1)
    b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(text, 1, 1, 1, 1, true); GameTooltip:Show() end)
    b:SetScript("OnLeave", GameTooltip_Hide)
end

local function BuildJournalSettings()
    if settingsFrame then return settingsFrame end
    settingsFrame = CreateFrame("Frame", "SmartChatJournalSettings", UIParent, "BackdropTemplate")
    settingsFrame:SetFrameStrata("FULLSCREEN_DIALOG"); settingsFrame:SetSize(560, 700); settingsFrame:SetPoint("CENTER")
    settingsFrame:SetToplevel(true); settingsFrame:EnableMouse(true)
    settingsFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    settingsFrame:SetBackdropColor(0.035, 0.04, 0.055, 1)
    settingsFrame:SetScript("OnShow", function(self)
        if SC.RaiseWindow then SC.RaiseWindow(self, "FULLSCREEN_DIALOG") end
    end)
    settingsFrame.title = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    settingsFrame.title:SetPoint("TOPLEFT", 18, -18); settingsFrame.title:SetText("Social & Journal Settings")
    local close = CreateFrame("Button", nil, settingsFrame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -4, -4)
    local y = -54
    local function label(text)
        local fs = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", 22, y); fs:SetText(text); y = y - 25
        return fs
    end
    local function checkbox(text, key, help)
        local cb = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 20, y); cb:SetSize(24, 24)
        local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 0); fs:SetText(text)
        cb:SetScript("OnClick", function(self)
            local j = EnsureJournal()
            local newValue = self:GetChecked() and true or false
            -- Close and save the active attendance interval before a user turns
            -- off Journal or group tracking; never silently discard the session.
            if key == "enabled" and j.enabled and not newValue and j.activeGroup then
                FinalizeGroupSession(j, "Group session ended (Journal tracking disabled)")
            elseif key == "trackGroups" and j.enabled and j.trackGroups and not newValue and j.activeGroup then
                FinalizeGroupSession(j, "Group session ended (Group tracking disabled)")
            end
            j[key] = newValue
            if key == "enabled" and j.enabled then SC.ResetJournalBaselines() end
            if key == "enabled" and not j.enabled then j.activeGroup = nil end
            if key == "trackFriends" or key == "trackGuild" then
                if j.enabled and j[key] then SC.ResetJournalBaselines() end
            end
            if key == "trackGroups" then
                if not j.trackGroups then j.activeGroup = nil
                elseif j.enabled then C_Timer.After(2, UpdateGroupSession) end
            end
            if key == "trackPresence" then
                local _, currentFriendStates, friendAvailable = ReadFriendRoster()
                lastFriendStates = currentFriendStates or {}
                lastBnetStates = ReadBnetPresence()
                friendRosterReady = friendAvailable == true
                bnetRosterReady = SC.bnetCacheReady and true or false
            elseif key == "trackGuildPresence" then
                local _, currentGuildStates, currentGuildIdentity = ReadGuildRoster()
                lastGuildStates = currentGuildStates or {}
                lastGuildIdentity = currentGuildIdentity
                guildRosterReady = currentGuildStates ~= nil
            elseif key == "trackGroupRoster" then
                lastGroupMembers = ReadGroupRoster()
                groupRosterReady = true
            end
        end)
        cb:SetChecked(EnsureJournal()[key] and true or false)
        SettingsHelp(settingsFrame, fs, help)
        y = y - 27
        return cb
    end
    label("Automatic local history")
    checkbox("Enable Player Journal", "enabled", "When enabled, SmartChat records selected social events locally in SavedVariables. No network requests are made. This is OFF by default. Existing notes are kept when tracking is disabled.")
    checkbox("Track Friend list changes", "trackFriends", "Record when a player is added to or removed from your in-game Friend list. The first snapshot is a baseline and is not recorded as new activity.")
    checkbox("Track Guild membership changes", "trackGuild", "Record guild joins and departures detected by comparing Guild Roster snapshots. Ordinary online/offline changes are not recorded as membership events.")
    checkbox("Track Group and Dungeon sessions", "trackGroups", "Record the players grouped with you, the zone or instance name, and session duration when the group ends. It does not claim that a dungeon was completed.")
    checkbox("Track Whisper interaction dates", "trackWhispers", "Record interaction dates and approximate counts only. Whisper message text is never copied into Player Journal.")
    checkbox("Track Quest turn-ins with a group present", "trackQuests", "Record your own quest turn-in and the names in your group at that moment. This does not mean every group member completed the quest.")
    checkbox("Track Friend and Battle.net presence changes", "trackPresence", "Record known Online, Offline, AFK and DND status changes for Friends and Battle.net contacts. Unknown or Appear Offline states are not treated as Offline.")
    checkbox("Track Guild member presence changes", "trackGuildPresence", "Record known Guild member Online/Offline and AFK/DND changes. This can create many events in a large Guild, so it is OFF by default.")
    checkbox("Track Group member joins and leaves", "trackGroupRoster", "Record when a known player joins or leaves your Party or Raid. Group sessions are tracked separately.")
    local historyInfo = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    historyInfo:SetPoint("TOPLEFT", 28, y - 2)
    historyInfo:SetWidth(500); historyInfo:SetJustifyH("LEFT"); historyInfo:SetWordWrap(true)
    historyInfo:SetText("History starts when tracking is enabled; past sessions and old relationship changes cannot be recovered retroactively. Whisper message text is never stored.")
    y = y - 38
    label("Storage limits")
    local function numberBox(caption, key, minV, maxV, width)
        local fs = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 28, y - 4); fs:SetText(caption)
        local eb = CreateFrame("EditBox", nil, settingsFrame, "InputBoxTemplate")
        eb:SetSize(width or 60, 20); eb:SetPoint("LEFT", fs, "RIGHT", 10, 0); eb:SetAutoFocus(false); eb:SetNumeric(true); eb:SetMaxLetters(4)
        eb:SetText(tostring(EnsureJournal()[key]))
        local function commit(self)
            local v = tonumber(self:GetText())
            if v then EnsureJournal()[key] = math.max(minV, math.min(maxV, v)) end
            self:SetText(tostring(EnsureJournal()[key])); self:ClearFocus(); SC.PruneJournal()
        end
        eb:SetScript("OnEnterPressed", commit); eb:SetScript("OnEditFocusLost", commit)
        SettingsHelp(settingsFrame, fs, key == "retentionDays" and "Number of days to retain automatic events. Set 0 to keep history until the maximum event count is reached." or "Maximum number of automatic journal events stored across all players. Oldest events are removed first.")
        y = y - 28
    end
    numberBox("Retention days (0 = no age limit)", "retentionDays", 0, 3650, 56)
    numberBox("Maximum events", "maxEvents", 50, 2000, 64)
    y = y - 2
    label("In-game social notifications")
    local function notificationCheckbox(text, key, help)
        local cb = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 20, y); cb:SetSize(24, 24)
        local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 0); fs:SetText(text)
        cb:SetScript("OnClick", function(self)
            local n = EnsureNotifications()
            n[key] = self:GetChecked() and true or false
        end)
        cb:SetChecked(EnsureNotifications()[key] and true or false)
        SettingsHelp(settingsFrame, fs, help)
        y = y - 27
        return cb
    end
    notificationCheckbox("Enable Social Notifications", "enabled", "Enable small in-game toast notifications for selected social events. OFF by default. This setting is independent from Player Journal history tracking.")
    notificationCheckbox("Friend comes online", "friendOnline", "Show a toast when a known Friend changes to Online after the initial login baseline.")
    notificationCheckbox("Friend goes offline", "friendOffline", "Show a toast when a known Friend changes to Offline. OFF by default to reduce noise.")
    notificationCheckbox("Friend list changes", "friendChanges", "Show a toast when a player is added to or removed from your in-game Friend List.")
    notificationCheckbox("Guild member joins or leaves", "guildChanges", "Show a toast when the Guild roster detects a member joining or leaving. OFF by default.")
    notificationCheckbox("Guild member presence changes", "guildPresence", "Show a toast for Guild member Online/Offline changes. This may be noisy in a large Guild and is OFF by default.")
    notificationCheckbox("Party/Raid member joins or leaves", "groupChanges", "Show a toast when a member joins or leaves your current Party or Raid.")
    notificationCheckbox("Battle.net friend presence changes", "bnetPresence", "Show a toast when a Battle.net friend with a known account identity changes Online/Offline state. Unknown and Appear Offline are not treated as Offline.")
    local clear = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
    clear:SetSize(150, 24); clear:SetPoint("BOTTOMLEFT", 22, 16); clear:SetText("Clear Event History")
    clear:SetScript("OnClick", function()
        if not StaticPopupDialogs then return end
        StaticPopupDialogs.SMARTCHAT_CLEAR_ALL_JOURNAL = StaticPopupDialogs.SMARTCHAT_CLEAR_ALL_JOURNAL or {
            text = "Clear all completed Player Journal events? A local recovery point will be created first. Personal notes, Favorites, Pins, Groups and the current active group session will remain.",
            button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function()
                local ok, count = SC.ClearJournalEventHistory()
                if ok then SC.Print("Player Journal history cleared (" .. tostring(count) .. " events). A local recovery point was saved.")
                else SC.Print(tostring(count or "Could not clear Journal history.")) end
            end,
        }
        StaticPopup_Show("SMARTCHAT_CLEAR_ALL_JOURNAL")
    end)
    SettingsHelp(settingsFrame, clear, "Clear completed Journal events only after confirmation. SmartChat first creates a local restore point. Notes, Favorites, Pins and personal groups are preserved.")
    local backup = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
    backup:SetSize(132, 24); backup:SetPoint("BOTTOMRIGHT", -22, 16); backup:SetText("Backup / Restore")
    backup:SetScript("OnClick", function() SC.ShowSocialBackup() end)
    SettingsHelp(settingsFrame, backup, "Export or merge your local Favorites, Pins, private contact groups, reusable Group Templates, Player Journal notes and event metadata. This does not include Whisper text, chat history or Battle.net account identifiers. The backup is plain text and stays on your computer unless you choose to share it.")
    local info = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    info:SetPoint("BOTTOMLEFT", clear, "BOTTOMRIGHT", 12, 4)
    info:SetText("Notes and tags are preserved.")
    tinsert(UISpecialFrames, "SmartChatJournalSettings")
    return settingsFrame
end

function SC.ToggleJournalSettings()
    local frame = BuildJournalSettings()
    frame:SetShown(not frame:IsShown())
    if frame:IsShown() and SC.RaiseWindow then SC.RaiseWindow(frame, "FULLSCREEN_DIALOG") end
end

table.insert(SC.onLogin, function()
    InitializeGroups()
    SC.PruneJournal()
end)
