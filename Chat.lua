local ADDON, SC = ...

SC.whispered = {}   -- [name] = true, whispers during this session
SC.guildCache = {}  -- [name] = true
SC.bnetCache = {}   -- [name] = true, characters of your Battle.net friends

local MAP = {
    -- Built-in tabs receive only their own stream. Instance and Officer are
    -- available through custom tabs and Global, not folded into Party/Guild.
    CHAT_MSG_SAY = "say", CHAT_MSG_EMOTE = "say", CHAT_MSG_TEXT_EMOTE = "say",
    CHAT_MSG_PARTY = "party", CHAT_MSG_PARTY_LEADER = "party", CHAT_MSG_PARTY_GUIDE = "party",
    CHAT_MSG_RAID = "raid", CHAT_MSG_RAID_LEADER = "raid", CHAT_MSG_RAID_WARNING = "raid",
    CHAT_MSG_GUILD = "guild", CHAT_MSG_GUILD_ACHIEVEMENT = "guild", CHAT_MSG_COMMUNITIES_GUILD = "guild",
    CHAT_MSG_CHANNEL = "general",
    CHAT_MSG_WHISPER = "whisper", CHAT_MSG_WHISPER_INFORM = "whisper",
}

-- Events included in the Global view. It includes every built-in/custom chat
-- channel event plus common social chat streams that do not have their own
-- dedicated tab in SmartChat.
SC.GlobalEvents = {}
for e in pairs(MAP) do SC.GlobalEvents[e] = true end
for _, list in pairs(SC.TYPE_EVENTS) do
    for _, e in ipairs(list) do SC.GlobalEvents[e] = true end
end
for _, e in ipairs({
    "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_GUILD_ACHIEVEMENT", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_COMMUNITIES_CHANNEL", "CHAT_MSG_COMMUNITIES_GUILD",
}) do
    SC.GlobalEvents[e] = true
end

-- every event we listen to: built-in tabs + global view + custom tabs
SC.AllEvents = {}
for e in pairs(SC.GlobalEvents) do SC.AllEvents[e] = true end
for _, list in pairs(SC.TYPE_EVENTS) do
    for _, e in ipairs(list) do SC.AllEvents[e] = true end
end

local function ListHas(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

-- which tabs does this chat event belong to? (built-in first, then custom)
function SC.TabsForEvent(event, chIndex, chBase)
    local res = {}
    local b = MAP[event]
    if b then
        if event ~= "CHAT_MSG_CHANNEL" or (not SC.IsSecret(chIndex) and chIndex == 1) then
            res[#res + 1] = b
        end
    end
    if SC.GlobalEvents[event] then
        res[#res + 1] = "global"
    end
    for _, c in ipairs(SC.db.customTabs) do
        local evs = SC.TYPE_EVENTS[c.chatType]
        if evs and ListHas(evs, event) then
            if c.chatType ~= "CHANNEL" then
                res[#res + 1] = c.id
            elseif c.channelMatch and not SC.IsSecret(chIndex) and not SC.IsSecret(chBase) then
                local n = tonumber(c.channelMatch)
                if n then
                    if chIndex == n then res[#res + 1] = c.id end
                elseif type(chBase) == "string" and chBase:lower():find(c.channelMatch:lower(), 1, true) then
                    res[#res + 1] = c.id
                end
            end
        end
    end
    return res
end

---------------------------------------------------------------------
-- Relationship and presence lookup (F = friend, B = Battle.net, G = guild, P = group)
local function FriendInfo(name)
    if C_FriendList and C_FriendList.GetFriendInfo then
        local ok, info = pcall(C_FriendList.GetFriendInfo, name)
        if ok and type(info) == "table" then return info end
    end
    return nil
end

local function RefreshContactViews()
    if SC.RefreshWhisperContacts then pcall(SC.RefreshWhisperContacts) end
    if SC.RefreshWhisperInbox then pcall(SC.RefreshWhisperInbox) end
end
SC.RefreshContactViews = RefreshContactViews

local function NormalizePresence(statusValue, online, afk, dnd)
    local statusText = type(statusValue) == "string" and statusValue:upper() or ""
    if afk or statusValue == 1 or statusText:find("AFK", 1, true) then return "AFK" end
    if dnd or statusValue == 2 or statusText:find("DND", 1, true) or statusText:find("BUSY", 1, true) then return "DND" end
    if type(online) == "boolean" then return online and "ONLINE" or "OFFLINE" end
    return "UNKNOWN"
end

local guildPending
local function RefreshGuild()
    guildPending = nil
    wipe(SC.guildCache)
    if not IsInGuild() then
        RefreshContactViews()
        return
    end
    for i = 1, (GetNumGuildMembers() or 0) do
        local name, rankName, rankIndex, level, className, zone, publicNote, officerNote, online, status, classFile,
            achievementPoints, achievementRank, isMobile = GetGuildRosterInfo(i)
        if name then
            local isOnline
            if type(online) == "boolean" then isOnline = online end
            local lastOnlineHours
            if not isOnline and type(GetGuildRosterLastOnline) == "function" then
                local ok, years, months, days, hours = pcall(GetGuildRosterLastOnline, i)
                if ok and (years ~= nil or months ~= nil or days ~= nil or hours ~= nil) then
                    lastOnlineHours = (((tonumber(years) or 0) * 12 + (tonumber(months) or 0)) * 30.5 + (tonumber(days) or 0)) * 24 + (tonumber(hours) or 0)
                end
            end
            SC.guildCache[SC.NameKey(name)] = {
                online = isOnline, status = NormalizePresence(status, isOnline), level = tonumber(level),
                class = className, classFile = classFile, zone = zone, rank = rankName, rankIndex = tonumber(rankIndex),
                achievementPoints = tonumber(achievementPoints), achievementRank = tonumber(achievementRank),
                isMobile = isMobile and true or false, lastOnlineHours = lastOnlineHours,
                source = "Guild", updated = GetTime and GetTime() or 0,
            }
        end
    end
    RefreshContactViews()
end

-- Battle.net friends: cache the WoW character currently associated with each game account.
local bnetPending
local function SafeBnetText(value)
    if type(value) ~= "string" or SC.IsSecret(value) then return nil end
    -- Do not expose hidden K-string account names as literal UI text.
    if value:find("|K", 1, true) or value:find("|k", 1, true) then return nil end
    value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value ~= "" and value or nil
end

local function RefreshBnet()
    bnetPending = nil
    wipe(SC.bnetCache)
    SC.bnetAccounts = {}
    SC.bnetAccountOrder = {}
    SC.bnetAccountCount = 0
    SC.bnetCharacterCount = 0
    if not (C_BattleNet and C_BattleNet.GetFriendAccountInfo and BNGetNumFriends) then
        SC.bnetCacheReady = false
        RefreshContactViews()
        return
    end
    local okN, n = pcall(BNGetNumFriends)
    if not okN or type(n) ~= "number" then
        SC.bnetCacheReady = false
        RefreshContactViews()
        return
    end
    SC.bnetAccountCount = n

    local function GameLabel(client)
        if client == (BNET_CLIENT_WOW or "WoW") then return "World of Warcraft" end
        if client == (BNET_CLIENT_APP or "App") or client == "BSAp" then return "Battle.net App" end
        if client and client ~= "" then return client end
        return "Other game"
    end

    local function NewAccountRecord(account, index)
        local battleTag = SafeBnetText(account.battleTag)
        local display = battleTag or SafeBnetText(account.accountName)
        if not display then display = "Battle.net Friend " .. tostring(index) end
        local accountID = tonumber(account.bnetAccountID)
        -- Account IDs and friend indexes are session-only. They are never saved
        -- into Social Hub SavedVariables or portable backups.
        local accountKey = battleTag and ("tag:" .. battleTag:lower())
            or (accountID and ("id:" .. tostring(accountID)) or ("friend:" .. tostring(index)))
        local game = type(account.gameAccountInfo) == "table" and account.gameAccountInfo or nil
        local lastOnlineTime = tonumber(account.lastOnlineTime)
        local appearOffline = account.appearOffline or (game and game.isAppearOffline)
        local online
        if not appearOffline then
            if type(account.isOnline) == "boolean" then online = account.isOnline end
            if game and type(game.isOnline) == "boolean" then online = game.isOnline end
            if online == nil and lastOnlineTime and lastOnlineTime > 0 then online = false end
        end
        local afk = account.isAFK or (game and game.isGameAFK)
        local dnd = account.isDND or (game and game.isGameBusy)
        local status = appearOffline and "UNKNOWN" or NormalizePresence(account.status or (game and game.status), online, afk, dnd)
        local record = {
            key = accountKey, name = display, battleTag = battleTag,
            accountID = accountID, friendIndex = index,
            online = online, status = status, appearOffline = appearOffline and true or false,
            lastOnlineTime = lastOnlineTime, gameAccounts = {}, gameAccountMap = {},
            characters = {}, characterMap = {},
            updated = GetTime and GetTime() or 0,
        }
        SC.bnetAccounts[accountKey] = record
        SC.bnetAccountOrder[#SC.bnetAccountOrder + 1] = accountKey
        return record
    end

    local function AddGameAccount(record, ga, account, gameIndex)
        if type(ga) ~= "table" then return nil end
        local client = SafeBnetText(ga.clientProgram)
        local character = SafeBnetText(ga.characterName)
        local realm = SafeBnetText(ga.realmDisplayName) or SafeBnetText(ga.realmName)
        local gameID = tonumber(ga.gameAccountID)
        local gameKey
        if gameID then
            gameKey = "id:" .. tostring(gameID)
        elseif character and character ~= "" then
            gameKey = table.concat({ tostring(client or "?"), character, tostring(realm or "") }, ":"):lower()
        elseif SafeBnetText(ga.richPresence) then
            gameKey = table.concat({ tostring(client or "?"), SafeBnetText(ga.richPresence) }, ":"):lower()
        else
            gameKey = table.concat({ tostring(client or "?"), tostring(gameIndex or "") }, ":"):lower()
        end
        local entry = record.gameAccountMap[gameKey]
        local online
        if type(ga.isOnline) == "boolean" then
            online = ga.isOnline
        elseif account and type(account.isOnline) == "boolean" then
            online = account.isOnline
        end
        local appearOffline = ga.isAppearOffline or (account and account.appearOffline)
        if appearOffline then online = nil end
        local status = appearOffline and "UNKNOWN" or NormalizePresence(
            ga.status or (account and account.status), online,
            ga.isGameAFK or ga.afk or ga.isAFK,
            ga.isGameBusy or ga.dnd or ga.isDND or ga.busy or ga.isBusy
        )
        if not entry then
            entry = {
                key = gameKey, gameAccountID = gameID, clientProgram = client,
                gameLabel = GameLabel(client), online = online, status = status,
                appearOffline = appearOffline and true or false,
                character = character, realm = realm,
                zone = SafeBnetText(ga.areaName) or SafeBnetText(ga.zoneName),
                class = SafeBnetText(ga.className) or SafeBnetText(ga.class),
                classFile = SafeBnetText(ga.classFilename) or SafeBnetText(ga.classFile),
                level = tonumber(ga.characterLevel or ga.level),
                faction = SafeBnetText(ga.factionName), race = SafeBnetText(ga.raceName),
                richPresence = SafeBnetText(ga.richPresence),
                canSummon = ga.canSummon and true or false,
            }
            record.gameAccountMap[gameKey] = entry
            record.gameAccounts[#record.gameAccounts + 1] = entry
        else
            -- The account's primary gameAccountInfo and indexed game-account
            -- list can describe the same account. Fill missing fields only.
            entry.character = entry.character or character
            entry.realm = entry.realm or realm
            entry.zone = entry.zone or SafeBnetText(ga.areaName) or SafeBnetText(ga.zoneName)
            entry.class = entry.class or SafeBnetText(ga.className) or SafeBnetText(ga.class)
            entry.classFile = entry.classFile or SafeBnetText(ga.classFilename) or SafeBnetText(ga.classFile)
            entry.level = entry.level or tonumber(ga.characterLevel or ga.level)
            local presenceRank = { UNKNOWN = 0, OFFLINE = 1, AFK = 2, DND = 2, ONLINE = 3 }
            if (presenceRank[status] or 0) > (presenceRank[entry.status] or 0) then
                entry.status, entry.online = status, online
            end
            entry.canSummon = entry.canSummon or (ga.canSummon and true or false)
        end

        local wowClient = BNET_CLIENT_WOW or "WoW"
        if client == wowClient and character and character ~= "" then
            local full = character
            if realm and realm ~= "" then full = full .. "-" .. realm:gsub("%s", "") end
            local charKey = SC.NameKey(full)
            if not record.characterMap[charKey] then
                local characterEntry = {
                    name = full, character = character, realm = realm,
                    class = entry.class, classFile = entry.classFile, level = entry.level,
                    zone = entry.zone, status = entry.status, online = entry.online,
                    gameAccountID = gameID,
                }
                record.characterMap[charKey] = characterEntry
                record.characters[#record.characters + 1] = characterEntry
            end
            SC.bnetCache[charKey] = {
                online = entry.online, status = entry.status, name = full,
                character = character, realm = realm, class = entry.class, classFile = entry.classFile,
                level = entry.level, zone = entry.zone, battleTag = record.battleTag,
                source = "Battle.net", accountOnly = false, gameLabel = "World of Warcraft",
                accountID = record.accountID, accountKey = record.key, accountName = record.name,
                gameAccountID = gameID, appearOffline = entry.appearOffline,
                updated = GetTime and GetTime() or 0,
            }
            return charKey
        end
        return nil
    end

    for i = 1, n do
        local ok, account = pcall(C_BattleNet.GetFriendAccountInfo, i)
        if ok and type(account) == "table" then
            local record = NewAccountRecord(account, i)
            local seenGames = {}
            local function addAccountGame(ga, gameIndex)
                if type(ga) ~= "table" then return end
                local client = SafeBnetText(ga.clientProgram)
                local character = SafeBnetText(ga.characterName)
                local realm = SafeBnetText(ga.realmDisplayName) or SafeBnetText(ga.realmName)
                local id = tonumber(ga.gameAccountID)
                local key
                if id then
                    key = "id:" .. tostring(id)
                elseif character and character ~= "" then
                    key = table.concat({ tostring(client or "?"), character, tostring(realm or "") }, ":"):lower()
                elseif SafeBnetText(ga.richPresence) then
                    key = table.concat({ tostring(client or "?"), SafeBnetText(ga.richPresence) }, ":"):lower()
                else
                    key = table.concat({ tostring(client or "?"), tostring(gameIndex or "") }, ":"):lower()
                end
                if seenGames[key] then return end
                seenGames[key] = true
                AddGameAccount(record, ga, account, gameIndex)
            end

            addAccountGame(account.gameAccountInfo, 0)
            if C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendGameAccountInfo then
                local okM, count = pcall(C_BattleNet.GetFriendNumGameAccounts, i)
                if okM and type(count) == "number" then
                    for j = 1, count do
                        local okG, gameInfo = pcall(C_BattleNet.GetFriendGameAccountInfo, i, j)
                        if okG then addAccountGame(gameInfo, j) end
                    end
                end
            end

            table.sort(record.characters, function(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end)
            table.sort(record.gameAccounts, function(a, b)
                if a.clientProgram ~= b.clientProgram then return tostring(a.clientProgram or ""):lower() < tostring(b.clientProgram or ""):lower() end
                return tostring(a.character or a.gameLabel or ""):lower() < tostring(b.character or b.gameLabel or ""):lower()
            end)
            record.characterCount = #record.characters
            record.gameAccountCount = #record.gameAccounts
            if not record.appearOffline then
                local hasOnline, hasAFK, hasDND, hasOffline = false, false, false, false
                for _, game in ipairs(record.gameAccounts) do
                    if game.status == "ONLINE" then hasOnline = true
                    elseif game.status == "AFK" then hasAFK = true
                    elseif game.status == "DND" then hasDND = true
                    elseif game.status == "OFFLINE" then hasOffline = true end
                end
                if hasOnline then
                    record.status, record.online = "ONLINE", true
                elseif hasDND then
                    record.status, record.online = "DND", true
                elseif hasAFK then
                    record.status, record.online = "AFK", true
                elseif hasOffline or record.online == false or (record.lastOnlineTime and record.lastOnlineTime > 0) then
                    record.status, record.online = "OFFLINE", false
                else
                    record.status, record.online = "UNKNOWN", nil
                end
            else
                record.status, record.online = "UNKNOWN", nil
            end
            for _, characterEntry in ipairs(record.characters) do
                local cache = SC.bnetCache[SC.NameKey(characterEntry.name)]
                if cache then
                    cache.accountKey = record.key
                    cache.accountName = record.name
                    cache.bnetGameAccountCount = record.gameAccountCount
                    cache.bnetCharacterCount = record.characterCount
                    cache.bnetCharacters = record.characters
                    cache.bnetGames = record.gameAccounts
                    cache.accountStatus = record.status
                    cache.accountLastOnlineTime = record.lastOnlineTime
                    cache.bnetAppearOffline = record.appearOffline
                end
            end
            if record.characterCount == 0 then
                local primaryGame = type(account.gameAccountInfo) == "table" and account.gameAccountInfo or record.gameAccounts[1]
                local client = primaryGame and SafeBnetText(primaryGame.clientProgram)
                local gameLabel = GameLabel(client)
                local displayKey = SC.NameKey(record.name)
                SC.bnetCache[displayKey] = {
                    name = record.name, battleTag = record.battleTag,
                    online = record.online, status = record.status,
                    source = "Battle.net", accountOnly = true, gameLabel = gameLabel,
                    lastOnlineTime = record.lastOnlineTime, appearOffline = record.appearOffline,
                    accountID = record.accountID, accountKey = record.key, accountName = record.name,
                    bnetGameAccountCount = record.gameAccountCount, bnetCharacterCount = 0,
                    bnetGames = record.gameAccounts, bnetCharacters = record.characters,
                    accountStatus = record.status, accountLastOnlineTime = record.lastOnlineTime,
                    bnetAppearOffline = record.appearOffline,
                    updated = GetTime and GetTime() or 0,
                }
            end
        end
    end

    SC.bnetCharacterCount = 0
    for _, info in pairs(SC.bnetCache) do
        if type(info) == "table" and not info.accountOnly and info.source == "Battle.net" then
            SC.bnetCharacterCount = SC.bnetCharacterCount + 1
        end
    end
    SC.bnetCacheReady = true
    RefreshContactViews()
    if SC.OnBnetCacheRefreshed then pcall(SC.OnBnetCacheRefreshed) end
end
function SC.ScheduleBnetRefresh()
    if not bnetPending then bnetPending = true; C_Timer.After(2, RefreshBnet) end
end

local GroupInfo
local function InGroup(name)
    return GroupInfo and GroupInfo(name) ~= nil or false
end

function SC.Relation(name)
    local rel = ""
    local key = SC.NameKey(name)
    if FriendInfo(name) then rel = rel .. "F" end
    if SC.bnetCache[key] then rel = rel .. "B" end
    if SC.guildCache[key] then rel = rel .. "G" end
    if InGroup(name) then rel = rel .. "P" end
    return rel, SC.whispered[key] and true or false
end

local function ClassFileFromName(className)
    if type(className) ~= "string" then return nil end
    local maps = { LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }
    for _, map in ipairs(maps) do
        if type(map) == "table" then
            for file, localized in pairs(map) do if localized == className then return file end end
        end
    end
    return className:upper():gsub("%s+", "")
end

function SC.ContactClassName(info)
    if type(info) ~= "table" then return "Unknown" end
    local token = info.classFile or ClassFileFromName(info.class)
    if type(token) == "string" then
        if type(LOCALIZED_CLASS_NAMES_MALE) == "table" and LOCALIZED_CLASS_NAMES_MALE[token] then
            return LOCALIZED_CLASS_NAMES_MALE[token]
        end
        if type(LOCALIZED_CLASS_NAMES_FEMALE) == "table" and LOCALIZED_CLASS_NAMES_FEMALE[token] then
            return LOCALIZED_CLASS_NAMES_FEMALE[token]
        end
    end
    return info.class or "Unknown"
end

GroupInfo = function(name)
    local raid = IsInRaid and IsInRaid()
    local total = (GetNumGroupMembers and GetNumGroupMembers()) or (GetNumRaidMembers and GetNumRaidMembers()) or 0
    local units = {}
    if raid then
        for i = 1, math.min(total, 40) do units[#units + 1] = "raid" .. i end
    else
        if IsInGroup and IsInGroup() then
            for i = 1, math.min(math.max(total - 1, 0), 4) do units[#units + 1] = "party" .. i end
        end
    end
    for _, unit in ipairs(units) do
        local unitName = SC.PlayerDisplayName and SC.PlayerDisplayName(unit) or (UnitName and UnitName(unit))
        if unitName and SC.NameKey(unitName) == SC.NameKey(name) then
            local className, classFile = UnitClass(unit)
            local level = UnitLevel(unit)
            local connected = not UnitIsConnected or UnitIsConnected(unit)
            local afk = UnitIsAFK and UnitIsAFK(unit) or false
            local dnd = UnitIsDND and UnitIsDND(unit) or false
            return {
                online = connected and true or false,
                status = NormalizePresence(nil, connected and true or false, afk, dnd),
                level = level, class = className, classFile = classFile,
                role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil,
                source = "Group",
            }
        end
    end
end

function SC.GetContactInfo(name)
    local key = SC.NameKey(name)
    local info = { name = name, status = "UNKNOWN", source = nil }
    local friend = FriendInfo(name)
    local guild = SC.guildCache[key]
    local bnet = SC.bnetCache[key]
    local group = GroupInfo(name)

    local bestPresenceType, bestSourcePriority = 0, 0
    local function setPresence(status, sourcePriority)
        if status ~= "AFK" and status ~= "DND" and status ~= "ONLINE" and status ~= "OFFLINE" then return end
        -- Explicit AFK/DND state takes precedence over simple online/offline flags.
        local presenceType = (status == "AFK" or status == "DND") and 2 or 1
        if presenceType > bestPresenceType or (presenceType == bestPresenceType and sourcePriority > bestSourcePriority) then
            info.status = status
            bestPresenceType, bestSourcePriority = presenceType, sourcePriority
        end
    end

    local function merge(src)
        if type(src) ~= "table" then return end
        local level = tonumber(src.level)
        if not info.level and level and level > 0 then info.level = level end
        local class = src.class or src.className or src.classFile
        if not info.class and type(class) == "string" and class ~= "" and class:lower() ~= "unknown" then
            info.class = class
        end
        local classFile = src.classFile or ClassFileFromName(class)
        if not info.classFile and type(classFile) == "string" and classFile ~= "" and classFile:upper() ~= "UNKNOWN" then
            info.classFile = classFile
        end
        local zone = src.zone or src.areaName or src.area
        if not info.zone and type(zone) == "string" and zone ~= "" and zone:lower() ~= "unknown" then info.zone = zone end
        info.battleTag = info.battleTag or src.battleTag
        info.rank = info.rank or src.rank
        info.role = info.role or src.role
        if info.rankIndex == nil and tonumber(src.rankIndex) ~= nil then info.rankIndex = tonumber(src.rankIndex) end
        info.accountOnly = info.accountOnly or (src.accountOnly and true or false)
        info.gameLabel = info.gameLabel or src.gameLabel
        info.lastOnlineTime = info.lastOnlineTime or tonumber(src.lastOnlineTime)
        info.source = info.source or src.source
    end

    if friend then
        merge({ level = friend.level, class = friend.className, classFile = friend.classFile, zone = friend.area, source = "Friend" })
        local friendOnline = friend.connected
        if type(friendOnline) ~= "boolean" then friendOnline = friend.isOnline end
        setPresence(NormalizePresence(friend.status, friendOnline, friend.afk, friend.dnd or friend.busy), 4)
    end
    if group then
        merge(group)
        setPresence(group.status or NormalizePresence(nil, group.online), 5)
    end
    if guild then
        merge(guild)
        setPresence(guild.status or NormalizePresence(nil, guild.online), 3)
    end
    if bnet then
        merge(bnet)
        setPresence(bnet.status or NormalizePresence(nil, bnet.online), 2)
        info.character = bnet.character
        info.realm = bnet.realm
        -- Account/game-account relationships are session-only API data. Keep
        -- them in memory for the Social Hub, never in SavedVariables.
        info.bnetAccountKey = bnet.accountKey
        info.bnetAccountName = bnet.accountName or bnet.battleTag
        info.bnetGameAccountCount = tonumber(bnet.bnetGameAccountCount) or 0
        info.bnetCharacterCount = tonumber(bnet.bnetCharacterCount) or 0
        info.bnetCharacters = bnet.bnetCharacters
        info.bnetGames = bnet.bnetGames
        info.bnetAccountStatus = bnet.accountStatus
        info.bnetAccountLastOnlineTime = bnet.accountLastOnlineTime
        info.bnetAppearOffline = bnet.bnetAppearOffline
    end

    if not info.class then info.class = "Unknown" end
    local seen = SC.whisperSeen and SC.whisperSeen[key]
    if info.status == "UNKNOWN" and seen and GetTime and (GetTime() - seen) < 90 then
        info.status = "ONLINE"
    end
    return info
end

local function BadgeString(rel, whispered)
    local bc = SC.db.badgeColors
    local out = ""
    for letter in rel:gmatch(".") do
        out = out .. "|c" .. bc[letter] .. letter .. "|r"
    end
    if whispered then out = out .. "|c" .. bc.W .. "W|r" end
    if out ~= "" then out = "|cff888888[|r" .. out .. "|cff888888]|r " end
    return out
end

-- Reuse the exact same relationship badge palette in contact lists and chat lines.
function SC.ContactBadgeMarkup(name, includeWhisper)
    if not SC.db or not SC.db.badges then return "" end
    local rel, whispered = SC.Relation(name)
    return BadgeString(rel or "", includeWhisper and whispered or false)
end

---------------------------------------------------------------------
-- Line decoration: badges, name colors, timestamps.
-- Done by wrapping AddMessage on the chat frames.
---------------------------------------------------------------------
local myName

-- Relationship colors are sourced dynamically:
--   F / B = independent friend / Battle.net colors in SavedVariables
--   G     = the current Guild tab color (including the user's tab override)
--   P     = current Party or Raid tab color, based on the unit's group type
-- Every combination is calculated from these current source colors. We do not
-- use old saved combination colors, so changing a tab color updates future
-- chat lines without requiring a reload.
local function RelationshipSourceColor(letter, name)
    if letter == "G" then
        local tab = SC.TABS and SC.TABS.guild
        if tab and type(tab.color) == "table" then return tab.color end
    elseif letter == "P" then
        local inRaid = false
        if name and UnitInRaid then
            local ok, result = pcall(UnitInRaid, name)
            inRaid = ok and result and true or false
        end
        local tab = SC.TABS and SC.TABS[inRaid and "raid" or "party"]
        if tab and type(tab.color) == "table" then return tab.color end
    end

    local colors = SC.db and SC.db.colors
    local color = colors and colors[letter]
    if type(color) == "table" then return color end
    return nil
end

local function ColorFor(rel, name)
    local r, g, b, n = 0, 0, 0, 0
    for letter in rel:gmatch(".") do
        local c = RelationshipSourceColor(letter, name)
        if c and c[1] and c[2] and c[3] then
            r, g, b, n = r + c[1], g + c[2], b + c[3], n + 1
        end
    end
    if n == 0 then return nil end
    return { r / n, g / n, b / n }
end

function SC.GetContactNameColor(name)
    if not SC.db or not SC.db.nameColors then return nil end
    local mode = SC.db.nameColorMode or "relationship"
    if mode == "relationship" then
        local rel = SC.Relation(name)
        if rel and rel ~= "" then
            local color = ColorFor(rel, name)
            if color then return color[1], color[2], color[3] end
        end
    end
    local info = SC.GetContactInfo and SC.GetContactInfo(name)
    local classFile = info and info.classFile
    local classColor = classFile and ((CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFile]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]))
    if classColor then return classColor.r, classColor.g, classColor.b end
    return nil
end

local function Transform(text)
    local db = SC.db
    myName = myName or SC.PlayerDisplayName("player")

    if db.badges or db.nameColors then
        text = text:gsub("(|Hplayer:([^:|]+)[^|]*|h)%[(.-)%]|h", function(open, who, disp)
            local name = who
            if SC.NameKey(name) == SC.NameKey(myName) then return nil end
            local rel, w = SC.Relation(name)
            if rel == "" and not w then return nil end
            local out = ""
            if db.badges then out = SC.ContactBadgeMarkup(name, true) end
            local col = db.nameColors and (db.nameColorMode or "relationship") == "relationship" and rel ~= "" and ColorFor(rel, name)
            if col then
                local plain = disp:gsub("|c%x%x%x%x%x%x%x%x", "")
                plain = plain:gsub("|r", "")
                disp = "|cff" .. SC.Hex(col) .. plain .. "|r"
            end
            return out .. open .. "[" .. disp .. "]|h"
        end)
    end

    -- Web addresses are converted only in the local display string. Existing
    -- Blizzard item/player/spell/achievement hyperlinks remain untouched.
    if db.webLinks ~= false and SC.LinkifyWebAddresses then
        local ok, linked = pcall(SC.LinkifyWebAddresses, text)
        if ok and type(linked) == "string" then text = linked end
    end

    if db.timestamps and not SC.replaying then
        text = "|cff888888" .. date(db.timeFormat) .. "|r " .. text
    end
    return text
end

local function WrapFrame(frame)
    if not frame or frame.smartchatWrapped then return end
    frame.smartchatWrapped = true
    local orig = frame.AddMessage
    frame.AddMessage = function(self, text, ...)
        if text ~= nil and not SC.IsSecret(text) and type(text) == "string" and not SC.Lockdown() then
            local ok, res = pcall(Transform, text)
            if ok and type(res) == "string" then text = res end
            if self == DEFAULT_CHAT_FRAME and SC.View then
                local ok2, show = pcall(SC.View.Add, self, orig, text, ...)
                if ok2 and show == false then return end
            end
        end
        return orig(self, text, ...)
    end
end

---------------------------------------------------------------------
-- Alerts: your character name or custom words
---------------------------------------------------------------------
local function IsAlert(msg)
    local db = SC.db
    local low = msg:lower()
    if db.alertOwnName then
        myName = myName or SC.PlayerDisplayName("player")
        if myName and myName ~= "" and low:find(myName:lower(), 1, true) then return true end
    end
    for _, w in ipairs(db.alertWords) do
        if w ~= "" and low:find(w, 1, true) then return true end
    end
    return false
end

---------------------------------------------------------------------
-- Word filter
---------------------------------------------------------------------
local function Mask(msg, w)
    local out, low, i = "", msg:lower(), 1
    while true do
        local s, e = low:find(w, i, true)
        if not s then out = out .. msg:sub(i); break end
        out = out .. msg:sub(i, s - 1) .. string.rep("*", e - s + 1)
        i = e + 1
    end
    return out
end

local function WordFilter(_, _, msg, ...)
    if not SC.db or SC.Lockdown() or SC.IsSecret(msg) or type(msg) ~= "string" then return false end
    local words = SC.db.filterWords
    if not words or #words == 0 then return false end
    local low = msg:lower()
    local changed = false
    for _, w in ipairs(words) do
        if w ~= "" and low:find(w, 1, true) then
            if not SC.db.filterMask then return true end
            msg = Mask(msg, w)
            low = msg:lower()
            changed = true
        end
    end
    if changed then return false, msg, ... end
    return false
end

local function RegisterFilters()
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if not add then SC.Print("word filter unavailable (API not found)"); return end
    for eventName in pairs(SC.AllEvents) do
        if eventName ~= "CHAT_MSG_WHISPER_INFORM" then
            -- Forever can reject unknown event names; one unsupported event
            -- must not prevent the remaining filters from being registered.
            pcall(add, eventName, WordFilter)
        end
    end
end

---------------------------------------------------------------------
-- History
---------------------------------------------------------------------
function SC.PruneHistory()
    local db = SC.db
    local h = db.history
    if db.historyDays and db.historyDays > 0 then
        local cutoff = time() - db.historyDays * 86400
        while h[1] and (h[1].t or 0) < cutoff do table.remove(h, 1) end
    end
    while #h > db.historyMax do table.remove(h, 1) end
end

function SC.ReplayHistory()
    local db = SC.db
    local h = db.history
    if not db.historyEnabled or db.historyLoad <= 0 or #h == 0 then return end
    local start = math.max(1, #h - db.historyLoad + 1)
    SC.replaying = true
    DEFAULT_CHAT_FRAME:AddMessage("|cff888888--- SmartChat history ---|r")
    for i = start, #h do
        local e = h[i]
        local def = SC.TABS[e.ch]
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff888888[%s] [%s] %s%s: %s|r",
            date(db.timeFormat, e.t or 0), def and def.label or e.lab or tostring(e.ch),
            e.out and "-> " or "", tostring(e.who or "?"), tostring(e.msg or "")))
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff888888--- end of history ---|r")
    SC.replaying = false
end

function SC.ClearHistory()
    wipe(SC.db.history)
end

---------------------------------------------------------------------
-- Incoming chat events: history + notify Tabs (flash/sound/whisper list)
---------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function SafeRegisterEvent(frame, eventName)
    local ok = pcall(frame.RegisterEvent, frame, eventName)
    return ok
end
for e in pairs(SC.AllEvents) do SafeRegisterEvent(ev, e) end
SafeRegisterEvent(ev, "GUILD_ROSTER_UPDATE")
SafeRegisterEvent(ev, "FRIENDLIST_UPDATE")
SafeRegisterEvent(ev, "GROUP_ROSTER_UPDATE")
SafeRegisterEvent(ev, "UNIT_FLAGS")
ev:SetScript("OnEvent", function(_, event, msg, author, _, _, _, _, _, chIndex, chBase)
    if event == "GUILD_ROSTER_UPDATE" then
        if not guildPending then guildPending = true; C_Timer.After(2, RefreshGuild) end
        return
    end
    if event == "FRIENDLIST_UPDATE" or event == "GROUP_ROSTER_UPDATE" then
        RefreshContactViews()
        return
    end
    if event == "UNIT_FLAGS" then
        local unit = msg
        if type(unit) == "string" and (unit == "player" or unit:match("^party%d+$") or unit:match("^raid%d+$")) then
            RefreshContactViews()
        end
        return
    end
    if event:find("^BN_") or event == "PLAYER_ENTERING_WORLD" then
        SC.ScheduleBnetRefresh()
        return
    end
    if not SC.db then return end
    local tabsFor = SC.TabsForEvent(event, chIndex, chBase)
    if #tabsFor == 0 then return end

    local safeAuthor = SC.Safe(author) and type(author) == "string" and author or nil
    if safeAuthor and (event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM"
        or event == "CHAT_MSG_BN_WHISPER" or event == "CHAT_MSG_BN_WHISPER_INFORM") then
        local key = SC.NameKey(safeAuthor)
        SC.whispered[key] = true
        SC.whisperSeen = SC.whisperSeen or {}
        if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then SC.whisperSeen[key] = GetTime and GetTime() or 0 end
    end

    local alerted = false
    if event ~= "CHAT_MSG_WHISPER" and event ~= "CHAT_MSG_WHISPER_INFORM"
        and event ~= "CHAT_MSG_BN_WHISPER" and event ~= "CHAT_MSG_BN_WHISPER_INFORM" and safeAuthor
        and not SC.Lockdown() and SC.Safe(msg) and type(msg) == "string"
        and SC.NameKey(safeAuthor) ~= SC.NameKey(SC.PlayerDisplayName("player")) then
        alerted = IsAlert(msg)
    end

    if SC.OnIncoming then
        -- Update unread counters for every matching tab, but play a sound only
        -- once. Prefer the currently selected matching tab (including the single
        -- Whisper tab); otherwise use the first matching tab with sound enabled.
        local function NotifyTarget(tabId)
            -- All private conversations are grouped under the single Whisper tab.
            return tabId
        end
        local function SoundKey(tabId)
            if type(tabId) == "string" and tabId:sub(1, 2) == "w:" then return "whisper" end
            return tabId
        end
        local soundIndex
        if alerted then
            for i, tabId in ipairs(tabsFor) do
                if NotifyTarget(tabId) == SC.active then soundIndex = i; break end
            end
            soundIndex = soundIndex or 1
        else
            for i, tabId in ipairs(tabsFor) do
                if NotifyTarget(tabId) == SC.active and SC.db.sound[SoundKey(tabId)] then
                    soundIndex = i; break
                end
            end
            if not soundIndex then
                for i, tabId in ipairs(tabsFor) do
                    if SC.db.sound[SoundKey(tabId)] then soundIndex = i; break end
                end
            end
        end
        for i, tabId in ipairs(tabsFor) do
            local ok, err = pcall(SC.OnIncoming, tabId, event, safeAuthor, alerted, i == soundIndex, (SC.Safe(msg) and type(msg) == "string") and msg or nil)
            if not ok then SC.Print("OnIncoming error:", err) end
        end
    end

    if SC.db.historyEnabled and not SC.Lockdown() and SC.Safe(msg, author)
        and type(msg) == "string" and safeAuthor then
        local h = SC.db.history
        local first = tabsFor[1]
        local def = SC.TABS[first]
        h[#h + 1] = { t = time(), ch = first, lab = def and def.label, who = safeAuthor, msg = msg,
                      out = (event == "CHAT_MSG_WHISPER_INFORM" or event == "CHAT_MSG_BN_WHISPER_INFORM") or nil }
        if #h > SC.db.historyMax + 50 then SC.PruneHistory() end
    end
end)

table.insert(SC.onLogin, function()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do WrapFrame(_G["ChatFrame" .. i]) end
    RegisterFilters()
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    for _, e in ipairs({ "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE",
                         "BN_FRIEND_LIST_SIZE_CHANGED", "PLAYER_ENTERING_WORLD" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    SC.ScheduleBnetRefresh()
    SC.PruneHistory()
    C_Timer.After(2, function() SC.ReplayHistory() end)
end)
