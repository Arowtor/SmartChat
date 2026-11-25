local ADDON, SC = ...

---------------------------------------------------------------------
-- External web links in chat.
-- Plain URLs become local-only addon hyperlinks. Clicking one opens a small
-- copy box; SmartChat never launches an external browser or contacts a server.
---------------------------------------------------------------------
local URL_COLOR = "ff71d5ff"
local popup

local function EncodeURL(value)
    return (value:gsub("([^%w%-%._~])", function(ch)
        return string.format("%%%02X", string.byte(ch))
    end))
end

local function DecodeURL(value)
    if type(value) ~= "string" then return nil end
    return (value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function NormalizeURL(value)
    if type(value) ~= "string" or value == "" then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value:match("^https?://") then return value end
    if value:match("^[%w%-%.]+%.[%a]+") then return "https://" .. value end
    return nil
end

local KNOWN_TLDS = {
    com=true, net=true, org=true, gg=true, io=true, co=true, tv=true, me=true,
    dev=true, app=true, info=true, biz=true, xyz=true, online=true, wiki=true,
    eu=true, uk=true, de=true, fr=true, es=true, it=true, ru=true, us=true,
    ca=true, au=true, jp=true, cn=true, nl=true, ir=true, pro=true, store=true,
    shop=true, live=true, site=true, tech=true, ai=true, game=true, gov=true,
    edu=true, mil=true, cloud=true, gg=true,
}

local function TrimURLTail(value)
    while value ~= "" do
        local last = value:sub(-1)
        if last == "." or last == "," or last == "!" or last == "?"
            or last == ";" or last == ":" or last == ")" or last == "]" or last == "}" then
            value = value:sub(1, -2)
        else
            break
        end
    end
    return value
end

local function ValidBareDomain(value)
    local host = value:match("^([^/:?#]+)")
    if not host or not host:find(".", 1, true) then return false end
    local tld = host:match("%.([%a]+)$")
    return tld and KNOWN_TLDS[tld:lower()] == true or false
end

local function IsBoundary(text, index)
    if index <= 1 then return true end
    local prev = text:sub(index - 1, index - 1)
    return not prev:match("[%w_@%-]")
end

local function CandidateAt(text, index)
    local tail = text:sub(index)
    local first = text:sub(index, index):lower()
    local value

    if first == "h" then
        value = tail:match("^(https?://[^%s|<>]+)")
    elseif first == "w" then
        value = tail:match("^(www%.[^%s|<>]+)")
    elseif first == "d" then
        value = tail:match("^(discord%.gg/[^%s|<>]+)")
            or tail:match("^(discord%.com/invite/[^%s|<>]+)")
    end

    -- Also accept common bare domains with a path, e.g. wowhead.com/item/123.
    if not value and first:match("[%a%d]") then
        local possible = tail:match("^([%w][%w%.%-]*%.[%a][%a]+[^%s|<>]*)")
        if possible and ValidBareDomain(possible) then value = possible end
    end

    if not value then return nil end
    value = TrimURLTail(value)
    if #value < 7 or #value > 512 then return nil end
    local normalized = NormalizeURL(value)
    if not normalized then return nil end
    -- Do not accept URLs containing control characters or hyperlink delimiters.
    if normalized:find("[%c|<>]") then return nil end
    return value, normalized
end

local function SkipMarkup(text, index)
    local token = text:sub(index, index + 1)
    if token == "|H" then
        local payloadEnd = text:find("|h", index + 2, true)
        if payloadEnd then
            local labelEnd = text:find("|h", payloadEnd + 2, true)
            return (labelEnd or payloadEnd) + 2
        end
    elseif token == "|T" then
        local ending = text:find("|t", index + 2, true)
        if ending then return ending + 2 end
    elseif token == "|A" then
        local ending = text:find("|a", index + 2, true)
        if ending then return ending + 2 end
    elseif token == "|c" then
        return math.min(#text + 1, index + 10)
    elseif token == "|r" or token == "||" then
        return index + 2
    end
    return index + 1
end

function SC.LinkifyWebAddresses(text)
    if not SC.db or SC.db.webLinks == false or not SC.webLinkHandlerAvailable
        or type(text) ~= "string" or text == "" then return text end
    -- Fast path: most chat lines do not contain a period or a URL scheme.
    if not text:find(".", 1, true) then return text end

    local out = {}
    local segmentStart, i = 1, 1
    while i <= #text do
        if text:sub(i, i) == "|" then
            i = SkipMarkup(text, i)
        elseif IsBoundary(text, i) then
            local shown, normalized = CandidateAt(text, i)
            if shown then
                out[#out + 1] = text:sub(segmentStart, i - 1)
                local link = "|c" .. URL_COLOR .. "|Haddon:SmartChat:url:" .. EncodeURL(normalized)
                    .. "|h" .. shown .. "|h|r"
                out[#out + 1] = link
                i = i + #shown
                segmentStart = i
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    if segmentStart == 1 then return text end
    out[#out + 1] = text:sub(segmentStart)
    return table.concat(out)
end

local function EnsurePopup()
    if popup then return popup end
    popup = CreateFrame("Frame", "SmartChatURLCopyPopup", UIParent, "BackdropTemplate")
    popup:SetSize(440, 116)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(110)
    popup:SetClampedToScreen(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
    popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 24,
        insets = { left = 7, right = 7, top = 7, bottom = 7 },
    })
    popup:SetBackdropColor(0.035, 0.04, 0.055, 0.98)
    popup:SetBackdropBorderColor(0.45, 0.55, 0.68, 1)

    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 15, -12)
    title:SetText("Copy Web Link")

    local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    popup.urlBox = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
    popup.urlBox:SetPoint("TOPLEFT", 18, -42)
    popup.urlBox:SetPoint("TOPRIGHT", -18, -42)
    popup.urlBox:SetHeight(24)
    popup.urlBox:SetAutoFocus(false)
    popup.urlBox:SetFontObject(ChatFontNormal)
    popup.urlBox:SetScript("OnEnterPressed", function() popup:Hide() end)
    popup.urlBox:SetScript("OnEscapePressed", function() popup:Hide() end)

    local hint = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 18, 15)
    hint:SetText("Press Ctrl+C to copy. Press Enter or Escape to close.")

    popup:SetScript("OnHide", function()
        if popup.urlBox then popup.urlBox:ClearFocus() end
    end)
    tinsert(UISpecialFrames, "SmartChatURLCopyPopup")
    return popup
end

function SC.ShowURLCopyPopup(url)
    if type(url) ~= "string" or not url:match("^https?://") then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    local frame = EnsurePopup()
    frame.urlBox:SetText(url)
    frame:ClearAllPoints()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale() or 1
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    frame:Show()
    frame.urlBox:SetFocus()
    frame.urlBox:HighlightText()
    return true
end

local function HandleSmartChatLink(link, text, button)
    if type(link) ~= "string" then return end
    local encoded = link:match("^addon:SmartChat:url:(.+)$")
    if not encoded then return end
    if button and button ~= "LeftButton" then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local url = DecodeURL(encoded)
    if url and url:match("^https?://") and not url:find("[%c|<>]") then
        SC.ShowURLCopyPopup(url)
    end
end

local registered = false
if EventRegistry and EventRegistry.RegisterCallback then
    local ok = pcall(EventRegistry.RegisterCallback, EventRegistry, "SetItemRef", function(_, link, text, button)
        HandleSmartChatLink(link, text, button)
    end)
    registered = ok
end

-- Older clients may not expose EventRegistry. This is a non-secure hook on the
-- chat hyperlink dispatcher, never on protected SetItemRef itself.
if not registered and hooksecurefunc and ChatFrame_OnHyperlinkShow then
    local ok = pcall(hooksecurefunc, "ChatFrame_OnHyperlinkShow", function(_, link, text, button)
        HandleSmartChatLink(link, text, button)
    end)
    registered = ok
end
SC.webLinkHandlerAvailable = registered and true or false

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:SetScript("OnEvent", function()
    if popup and popup:IsShown() then popup:Hide() end
end)
