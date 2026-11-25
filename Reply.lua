local ADDON, SC = ...

-- Reply with a quote:  Ctrl+click on a player's name in chat.
-- Opens the chat box in the SAME channel as that message, already containing
--   @Name "start of the message.." 
-- and you type your answer after it. It is one normal chat message that
-- everybody can read (no addon needed on their side).

local QUOTE_LEN = 40

local function StripCodes(s)
    s = s:gsub("|K.-|k", "?")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|A.-|a", "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    return s
end

-- keep a whole number of characters (works for non-English text too)
local function Cut(s, n)
    if #s <= n then return s end
    local i = n
    while i > 0 do
        local b = s:byte(i + 1)
        if b and b >= 128 and b < 192 then i = i - 1 else break end
    end
    return s:sub(1, i) .. ".."
end

-- the message itself, without time stamp, badges and sender name
local function BodyFrom(line)
    local s = StripCodes(line)
    s = s:gsub("^%d+:%d+:?%d*%s*[AP]?M?%s*", "")
    for _ = 1, 4 do
        local rest = s:match("^%[[^%]]*%]%s*(.*)$")
        if not rest then break end
        s = rest
    end
    return s:match("^:%s*(.*)$") or s:match("^%a+:%s*(.*)$") or s
end

local function MessageText(lineID)
    if C_ChatInfo and C_ChatInfo.GetChatLineText then
        local ok, t = pcall(C_ChatInfo.GetChatLineText, lineID)
        if ok and type(t) == "string" and not SC.IsSecret(t) and t ~= "" then return t end
    end
    local line = SC.View and SC.View.TextByLine(lineID)
    return line and BodyFrom(line) or nil
end

-- which channel does the box have to open in?
local function Target(ctype, ctarget, name)
    if ctype == "SAY" or ctype == "YELL" or ctype == "GUILD" or ctype == "OFFICER" then return ctype end
    if ctype == "PARTY" or ctype == "PARTY_LEADER" then return SC.ResolveChatType("PARTY") end
    if ctype == "RAID" or ctype == "RAID_LEADER" or ctype == "RAID_WARNING" then return SC.ResolveChatType("RAID") end
    if ctype == "INSTANCE_CHAT" or ctype == "INSTANCE_CHAT_LEADER" then return "INSTANCE_CHAT" end
    if ctype == "WHISPER" or ctype == "WHISPER_INFORM" then return "WHISPER", name end
    if ctype == "CHANNEL" and tonumber(ctarget) then return "CHANNEL", tonumber(ctarget) end
    return nil
end

local function SoundKey(id)
    if id and id:sub(1, 2) == "w:" then return "whisper" end
    return id
end

function SC.ReplyEnabled(tabId)
    return not SC.db.replyOff[SoundKey(tabId) or "?"]
end

function SC.Reply(link)
    if SC.Lockdown() then
        SC.Print("Reply is temporarily unavailable while the game restricts chat.")
        return
    end
    local name, lineID, ctype, ctarget = link:match("^player:([^:]+):(%d+):([^:]*):?(.*)$")
    if not name then return end
    lineID = tonumber(lineID)
    local chatType, extra = Target(ctype, ctarget, name)
    if not chatType then SC.Print("cannot reply to this kind of message."); return end

    local short = SC.ShortName(name)
    local prefix = (chatType == "WHISPER") and "" or ("@" .. short .. " ")
    if not SC.Lockdown() then
        local body = MessageText(lineID)
        if body and body ~= "" then
            body = body:gsub("%s+", " ")
            prefix = prefix .. "\"" .. Cut(body, QUOTE_LEN) .. "\" "
        end
    end

    local frame = DEFAULT_CHAT_FRAME
    local eb = frame and frame.editBox
    if not eb then return end
    eb = SC.OpenChat(prefix, frame) or eb
    if chatType == "WHISPER" then
        SC.SetEditBoxTellTarget(eb, extra)
    elseif chatType == "CHANNEL" then
        SC.SetEditBoxChannelTarget(eb, extra)
    end
    SC.SetEditBoxChatType(eb, chatType)
    SC.SetEditBoxStickyType(eb, chatType)
    SC.UpdateChatHeader(eb)
    eb:SetText(prefix)
    eb:SetFocus()
    eb:SetCursorPosition(#prefix)
end

local function OnLink(self, link, text, button)
    if button ~= "LeftButton" or type(link) ~= "string" or SC.IsSecret(link) then return end
    if not link:find("^player:") then return end
    if not IsControlKeyDown() or IsShiftKeyDown() or IsAltKeyDown() then return end
    if not SC.ReplyEnabled(SC.active) then return end
    local ok, err = pcall(SC.Reply, link)
    if not ok then SC.Print("reply error: " .. tostring(err)) end
end

table.insert(SC.onLogin, function()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = _G["ChatFrame" .. i]
        if f and f.HookScript then pcall(f.HookScript, f, "OnHyperlinkClick", OnLink) end
    end
end)
