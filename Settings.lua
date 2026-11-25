local ADDON, SC = ...

local panel
local soundPanel
local textPanel
local Build
local refreshers = {}
local soundPreviewHandle
local soundPreviewToken = 0
local soundPreviewLastAt = 0
local TIME_FORMATS = {
    { fmt = "%H:%M",       name = "24-hour" },
    { fmt = "%H:%M:%S",    name = "24-hour + seconds" },
    { fmt = "%I:%M %p",    name = "12-hour" },
    { fmt = "%I:%M:%S %p", name = "12-hour + seconds" },
}
local R = 350   -- x offset of the right column

local function CB(parent, label, x, y, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetSize(24, 24)
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(label)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
    return cb, fs
end

-- little "?" with a tooltip, placed right after `anchor` (any region)
local function Help(parent, anchor, text)
    local h = CreateFrame("Button", nil, parent)
    h:SetSize(16, 16)
    h:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    h.t = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h.t:SetPoint("CENTER")
    h.t:SetText("(?)")
    h.t:SetTextColor(0.4, 0.8, 1)
    h:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", GameTooltip_Hide)
    return h
end

local function GameStampOn()
    local ok, v = pcall(GetCVar, "showTimestamps")
    return ok and v ~= nil and v ~= "none" and v ~= ""
end

local function Label(parent, text, x, y, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function Btn(parent, text, x, y, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function SmallFont(b)
    pcall(function()
        b:SetNormalFontObject(GameFontNormalSmall)
        b:SetHighlightFontObject(GameFontHighlightSmall)
        b:SetDisabledFontObject(GameFontDisableSmall)
    end)
end

local function Cycle(parent, x, y, w, getText, onClick)
    local b = Btn(parent, "", x, y, w, function(self) onClick(); self:SetText(getText()) end)
    SmallFont(b)
    refreshers[#refreshers + 1] = function() b:SetText(getText()) end
    return b
end

local function NumBox(parent, x, y, get, set)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetPoint("TOPLEFT", x, y)
    eb:SetSize(50, 20)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(5)
    local function commit(self)
        local v = tonumber(self:GetText())
        if v then set(v) end
        self:SetText(tostring(get()))
        self:ClearFocus()
    end
    eb:SetScript("OnEnterPressed", commit)
    eb:SetScript("OnEditFocusLost", commit)
    refreshers[#refreshers + 1] = function() eb:SetText(tostring(get())) end
    return eb
end

local function WordBox(parent, x, y, w, getList, setList)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetPoint("TOPLEFT", x, y)
    eb:SetSize(w, 20)
    eb:SetAutoFocus(false)
    local function commit(self)
        local list = {}
        for word in self:GetText():gmatch("[^,]+") do
            word = word:gsub("^%s+", "")
            word = word:gsub("%s+$", "")
            word = word:lower()
            if word ~= "" then list[#list + 1] = word end
        end
        setList(list)
        self:ClearFocus()
    end
    eb:SetScript("OnEnterPressed", commit)
    eb:SetScript("OnEditFocusLost", commit)
    refreshers[#refreshers + 1] = function() eb:SetText(table.concat(getList(), ", ")) end
    return eb
end

local function Slider(parent, label, x, y, minV, maxV, get, set)
    local fs = Label(parent, label, x, y, "GameFontHighlightSmall")
    local sl = CreateFrame("Slider", nil, parent)
    sl:SetOrientation("HORIZONTAL")
    sl:SetSize(160, 16)
    sl:SetPoint("TOPLEFT", x + 130, y + 3)
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(0.05)
    sl:SetObeyStepOnDrag(true)
    local bg = sl:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("LEFT"); bg:SetPoint("RIGHT"); bg:SetHeight(4)
    bg:SetColorTexture(0.35, 0.35, 0.35, 1)
    sl:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local val = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    val:SetPoint("LEFT", sl, "RIGHT", 8, 0)
    sl:SetScript("OnValueChanged", function(self, v)
        val:SetText(math.floor(v * 100 + 0.5) .. "%")
        if not self.refreshing then set(v) end
    end)
    refreshers[#refreshers + 1] = function()
        sl.refreshing = true
        sl:SetValue(get())
        sl.refreshing = false
    end
    return sl, fs
end

local function NextSound(current)
    local list = SC.AvailableSounds()
    local idx = 0
    for i, k in ipairs(list) do if k == current then idx = i end end
    return list[idx % #list + 1]
end

local function SoundText(name)
    return SC.SoundDisplayName and SC.SoundDisplayName(name) or (name or "No sound")
end

local soundPickerMenu
local function ShowSoundPicker(anchor, current, onSelect)
    if not EasyMenu or not UIDropDownMenu_CreateInfo then return false end
    if not soundPickerMenu then
        soundPickerMenu = CreateFrame("Frame", "SmartChatSoundPickerMenu", UIParent, "UIDropDownMenuTemplate")
    end
    local menu = {}
    local function addTitle(title)
        local info = UIDropDownMenu_CreateInfo()
        info.text, info.isTitle, info.notCheckable = title, true, true
        menu[#menu + 1] = info
    end
    local function addChoice(value)
        local info = UIDropDownMenu_CreateInfo()
        info.text = SoundText(value)
        info.checked = (value == current)
        info.isNotRadio = true
        info.func = function() onSelect(value) end
        menu[#menu + 1] = info
    end
    addChoice("NONE")
    addTitle("Built-in WoW sounds")
    for _, value in ipairs(SC.AvailableSounds()) do
        if value ~= "NONE" and value:sub(1, 5) ~= "PACK:" then addChoice(value) end
    end
    addTitle("SmartChat Sound Pack")
    for _, value in ipairs(SC.AvailableSounds()) do
        if value:sub(1, 5) == "PACK:" then addChoice(value) end
    end
    EasyMenu(menu, soundPickerMenu, anchor, 0, 0, "MENU")
    return true
end
SC.ShowSoundPicker = ShowSoundPicker

---------------------------------------------------------------------
-- Sound & Notifications sub-page
---------------------------------------------------------------------
local function StopSoundPreview()
    soundPreviewToken = soundPreviewToken + 1
    if soundPreviewHandle and StopSound then
        pcall(StopSound, soundPreviewHandle, 0.05)
    end
    soundPreviewHandle = nil
end

local function QueueSoundPreview(tabId, volume, allowWhenHidden)
    if not SC.db or not SC.db.soundLivePreview then return end
    soundPreviewToken = soundPreviewToken + 1
    local token = soundPreviewToken
    local now = GetTime and GetTime() or 0
    local delay = math.max(0, 0.22 - (now - soundPreviewLastAt))

    local function play()
        if token ~= soundPreviewToken or (not allowWhenHidden and (not soundPanel or not soundPanel:IsShown()))
            or not SC.db.soundLivePreview then return end
        if soundPreviewHandle and StopSound then pcall(StopSound, soundPreviewHandle, 0.05) end
        soundPreviewHandle = SC.PlayKit(SC.db.soundKit[tabId], volume)
        soundPreviewLastAt = GetTime and GetTime() or now
    end

    if delay > 0 and C_Timer and C_Timer.After then
        C_Timer.After(delay, play)
    else
        play()
    end
end

local function ReturnToMainSettings()
    if soundPanel and soundPanel:IsShown() then
        soundPanel._returningToMain = true
        soundPanel:Hide()
        soundPanel._returningToMain = nil
    end
    StopSoundPreview()
    if panel then
        panel:Show()
        if SC.RaiseWindow then SC.RaiseWindow(panel, "DIALOG") end
    end
end

local function SoundTabIDs()
    local ids, seen = {}, {}
    -- Built-in tabs are always present, even when the user has hidden them.
    for _, id in ipairs({ "say", "global", "party", "raid", "guild", "general", "whisper" }) do
        if SC.TABS[id] and not seen[id] then ids[#ids + 1] = id; seen[id] = true end
    end
    -- Include custom tabs in the saved order so they can have independent volume.
    for _, id in ipairs(SC.db.order or {}) do
        if SC.TABS[id] and not seen[id] then ids[#ids + 1] = id; seen[id] = true end
    end
    return ids
end

local function BuildSoundPanel()
    if soundPanel then return end
    local db = SC.db
    db.soundVolume = db.soundVolume or {}
    if type(db.soundMasterVolume) ~= "number" then db.soundMasterVolume = 1 end

    soundPanel = CreateFrame("Frame", "SmartChatSoundSettings", UIParent, "BackdropTemplate")
    soundPanel:SetSize(730, 560)
    soundPanel:SetPoint("CENTER")
    soundPanel:SetFrameStrata("FULLSCREEN_DIALOG")
    soundPanel:SetMovable(true)
    soundPanel:EnableMouse(true)
    soundPanel:RegisterForDrag("LeftButton")
    soundPanel:SetScript("OnDragStart", soundPanel.StartMoving)
    soundPanel:SetScript("OnDragStop", soundPanel.StopMovingOrSizing)
    soundPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    soundPanel:SetToplevel(true)
    SC.RegisterWindow(soundPanel, { 0.035, 0.040, 0.055, 1 }, { 0.55, 0.55, 0.60, 1 })
    tinsert(UISpecialFrames, "SmartChatSoundSettings")

    Label(soundPanel, "Sound & Notifications", 22, -20, "GameFontNormalLarge")
    Btn(soundPanel, "Back to Settings", 520, -14, 150, ReturnToMainSettings)
    local close = CreateFrame("Button", nil, soundPanel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", ReturnToMainSettings)

    local soundRows = {}
    local function RefreshSoundRowValues()
        for id, row in pairs(soundRows) do
            local tabVolume = SC.GetTabSoundVolume(id)
            local effective = SC.GetSoundVolume(id)
            row.value:SetText(math.floor(tabVolume * 100 + 0.5) .. "% / "
                .. math.floor(effective * 100 + 0.5) .. "%")
        end
        if SC.RefreshOpenTabMenuSound then SC.RefreshOpenTabMenuSound() end
    end

    -- Distinct master section: visually separate from individual tab controls.
    local masterTitle = Label(soundPanel, "MASTER AUDIO", 24, -55, "GameFontNormalLarge")
    masterTitle:SetTextColor(0.35, 0.72, 1.00)
    local masterSlider = CreateFrame("Slider", nil, soundPanel)
    masterSlider:SetOrientation("HORIZONTAL")
    masterSlider:SetSize(285, 18)
    masterSlider:SetPoint("TOPLEFT", 170, -57)
    masterSlider:SetMinMaxValues(0, 1)
    masterSlider:SetValueStep(0.1)
    masterSlider:SetObeyStepOnDrag(true)
    local masterBG = masterSlider:CreateTexture(nil, "BACKGROUND")
    masterBG:SetPoint("LEFT"); masterBG:SetPoint("RIGHT"); masterBG:SetHeight(5)
    masterBG:SetColorTexture(0.22, 0.36, 0.48, 1)
    masterSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local masterValue = Label(soundPanel, "100%", 466, -57, "GameFontHighlight")
    local muteButton
    muteButton = Btn(soundPanel, "Mute All", 540, -51, 105, function()
        db.soundNotificationsEnabled = not (db.soundNotificationsEnabled ~= false)
        if db.soundNotificationsEnabled == false then StopSoundPreview() end
        if SC.RefreshSpeakers then SC.RefreshSpeakers() end
        muteButton:SetText(db.soundNotificationsEnabled == false and "Unmute All" or "Mute All")
        RefreshSoundRowValues()
    end)
    SmallFont(muteButton)
    Help(soundPanel, muteButton, "Mute All immediately silences SmartChat notifications and sound previews. It does not reset Master Volume or per-tab volume choices.")
    masterSlider:SetScript("OnValueChanged", function(self, value)
        if self.refreshing then return end
        db.soundMasterVolume = math.max(0, math.min(1, value))
        masterValue:SetText(math.floor(db.soundMasterVolume * 100 + 0.5) .. "%")
        RefreshSoundRowValues()
        if db.soundLivePreview then
            local active = SC.SoundTabKey and SC.SoundTabKey(SC.active or "global") or (SC.active or "global")
            if not db.soundKit[active] then active = "global" end
            QueueSoundPreview(active, SC.GetSoundVolume(active))
        end
    end)
    Help(soundPanel, masterValue, "Master Volume scales every tab's individual volume. The final sound level is Master × Tab Volume. Mute All stops every SmartChat notification and preview without resetting the saved volume levels.")

    local live = CreateFrame("CheckButton", nil, soundPanel, "UICheckButtonTemplate")
    live:SetSize(24, 24)
    live:SetPoint("TOPLEFT", 24, -91)
    local liveText = Label(soundPanel, "Live Preview", 50, -92, "GameFontHighlight")
    live:SetScript("OnClick", function(self)
        db.soundLivePreview = self:GetChecked() and true or false
        if not db.soundLivePreview then StopSoundPreview() end
    end)
    Help(soundPanel, liveText, "When enabled, moving a Master or per-tab volume slider previews the selected sound at the resulting effective volume. Preview is rate-limited while dragging. When disabled, use each row's Test button.")
    Label(soundPanel, "Sound Pack contains 10 original sounds. Each is included at 10% to 100% volume in 10% steps.",
        220, -92, "GameFontDisableSmall")
    Label(soundPanel, "Tab", 24, -129, "GameFontHighlightSmall")
    Label(soundPanel, "On", 132, -129, "GameFontHighlightSmall")
    Label(soundPanel, "Notification sound", 180, -129, "GameFontHighlightSmall")
    Label(soundPanel, "Tab / Final", 390, -129, "GameFontHighlightSmall")
    Label(soundPanel, "Test", 590, -129, "GameFontHighlightSmall")

    local scroll = CreateFrame("ScrollFrame", nil, soundPanel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 22, -147)
    scroll:SetPoint("BOTTOMRIGHT", -42, 22)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(650)
    scroll:SetScrollChild(content)

    local tabIDs = SoundTabIDs()
    content:SetHeight(math.max(1, #tabIDs * 36))

    for i, id in ipairs(tabIDs) do
        local def = SC.TABS[id]
        local y = -((i - 1) * 36)
        local row = {}
        row.name = Label(content, def.label or id, 2, y - 4, "GameFontHighlight")
        Help(content, row.name, "Settings for the " .. (def.label or id) .. " tab: turn its notification sound on or off, choose its sound, adjust its individual volume, and use Test to preview it. The displayed final volume also includes Master Volume.")

        row.enabled = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        row.enabled:SetSize(22, 22)
        row.enabled:SetPoint("TOPLEFT", 112, y + 1)
        row.enabled:SetScript("OnClick", function(self)
            db.sound[id] = self:GetChecked() and true or false
            if SC.RefreshSpeakers then SC.RefreshSpeakers() end
        end)

        row.kit = Btn(content, SoundText(db.soundKit[id]), 154, y, 220, function(self)
            local function choose(value)
                db.soundKit[id] = value
                self:SetText(SoundText(value))
                if db.soundLivePreview then QueueSoundPreview(id, SC.GetSoundVolume(id)) end
            end
            if not ShowSoundPicker(self, db.soundKit[id], choose) then
                db.soundKit[id] = NextSound(db.soundKit[id])
                self:SetText(SoundText(db.soundKit[id]))
                if db.soundLivePreview then QueueSoundPreview(id, SC.GetSoundVolume(id)) end
            end
        end)
        SmallFont(row.kit)

        row.slider = CreateFrame("Slider", nil, content)
        row.slider:SetOrientation("HORIZONTAL")
        row.slider:SetSize(105, 16)
        row.slider:SetPoint("TOPLEFT", 390, y - 2)
        row.slider:SetMinMaxValues(0, 1)
        row.slider:SetValueStep(0.1)
        row.slider:SetObeyStepOnDrag(true)
        local bg = row.slider:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("LEFT"); bg:SetPoint("RIGHT"); bg:SetHeight(4)
        bg:SetColorTexture(0.35, 0.35, 0.35, 1)
        row.slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        row.value = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.value:SetPoint("LEFT", row.slider, "RIGHT", 6, 0)
        row.value:SetWidth(70)
        row.value:SetJustifyH("LEFT")
        row.slider:SetScript("OnValueChanged", function(self, value)
            if not self.refreshing then
                db.soundVolume[id] = math.max(0, math.min(1, value))
                RefreshSoundRowValues()
                if db.soundLivePreview then QueueSoundPreview(id, SC.GetSoundVolume(id)) end
            else
                row.value:SetText(math.floor(value * 100 + 0.5) .. "% / "
                    .. math.floor(SC.GetSoundVolume(id) * 100 + 0.5) .. "%")
            end
        end)

        row.test = Btn(content, "Test", 590, y, 58, function()
            StopSoundPreview()
            SC.PlayKit(db.soundKit[id], SC.GetSoundVolume(id))
        end)
        SmallFont(row.test)
        soundRows[id] = row
    end

    local function RefreshSoundPanel()
        masterSlider.refreshing = true
        masterSlider:SetValue(math.max(0, math.min(1, tonumber(db.soundMasterVolume) or 1)))
        masterSlider.refreshing = false
        masterValue:SetText(math.floor((tonumber(db.soundMasterVolume) or 1) * 100 + 0.5) .. "%")
        muteButton:SetText(db.soundNotificationsEnabled == false and "Unmute All" or "Mute All")
        live:SetChecked(db.soundLivePreview == true)
        for id, row in pairs(soundRows) do
            row.enabled:SetChecked(db.sound[id] and true or false)
            row.kit:SetText(SoundText(db.soundKit[id]))
            row.slider.refreshing = true
            row.slider:SetValue(SC.GetTabSoundVolume(id))
            row.slider.refreshing = false
        end
        RefreshSoundRowValues()
    end

    SC.RefreshSoundSettingsUI = function()
        if soundPanel and soundPanel:IsShown() then RefreshSoundPanel() end
    end

    soundPanel:SetScript("OnShow", function()
        RefreshSoundPanel()
        if SC.RaiseWindow then SC.RaiseWindow(soundPanel, "FULLSCREEN_DIALOG") end
    end)
    soundPanel:SetScript("OnHide", function(self)
        StopSoundPreview()
        if not self._returningToMain and panel then
            panel:Show()
            if SC.RaiseWindow then SC.RaiseWindow(panel, "DIALOG") end
        end
    end)
    soundPanel:Hide()
end

-- Available even before the Sound & Notifications window has been opened.
SC.PreviewTabSound = function(tabId)
    if not SC.db or not SC.db.soundLivePreview then return end
    QueueSoundPreview(tabId, SC.GetSoundVolume(tabId), true)
end

function SC.ToggleSoundSettings()
    if not soundPanel then BuildSoundPanel() end
    if soundPanel:IsShown() then
        ReturnToMainSettings()
    else
        if not panel then Build() end
        panel:Hide()
        soundPanel:Show()
        if SC.RaiseWindow then SC.RaiseWindow(soundPanel, "FULLSCREEN_DIALOG") end
    end
end
SC.ShowSoundSettings = function()
    if not soundPanel then BuildSoundPanel() end
    if panel and panel:IsShown() then panel:Hide() end
    soundPanel:Show()
    if SC.RaiseWindow then SC.RaiseWindow(soundPanel, "FULLSCREEN_DIALOG") end
end


---------------------------------------------------------------------
-- Chat Text Appearance
-- Applies only to the main chat message frame and, optionally, its input box.
-- It does not alter message/channel colors or other game UI fonts.
---------------------------------------------------------------------
local CHAT_FONT_CHOICES = {
    { id = "DEFAULT",  label = "Blizzard Default", path = nil },
    { id = "FRIZ",     label = "Friz Quadrata",    path = "Fonts\\FRIZQT__.TTF" },
    { id = "ARIALN",   label = "Arial Narrow",     path = "Fonts\\ARIALN.TTF" },
    { id = "MORPHEUS", label = "Morpheus",         path = "Fonts\\MORPHEUS.TTF" },
    { id = "SKURRI",   label = "Skurri",           path = "Fonts\\skurri.ttf" },
}
local chatFontDefaults

local function ReadFont(region)
    if not region or type(region.GetFont) ~= "function" then return nil end
    local ok, file, size, flags = pcall(region.GetFont, region)
    if ok and type(file) == "string" and type(size) == "number" then
        return { file = file, size = size, flags = flags or "" }
    end
    return nil
end

local function CaptureChatFontDefaults()
    if chatFontDefaults then return chatFontDefaults end
    local message = ReadFont(DEFAULT_CHAT_FRAME)
    local editBox = DEFAULT_CHAT_FRAME and (DEFAULT_CHAT_FRAME.editBox or DEFAULT_CHAT_FRAME.EditBox)
    local input = ReadFont(editBox)
    local inputHeight
    if editBox and type(editBox.GetHeight) == "function" then
        local ok, height = pcall(editBox.GetHeight, editBox)
        if ok and type(height) == "number" and height > 0 then inputHeight = height end
    end
    if not message and GameFontNormal and GameFontNormal.GetFont then
        local ok, file, size, flags = pcall(GameFontNormal.GetFont, GameFontNormal)
        if ok and type(file) == "string" and type(size) == "number" then
            message = { file = file, size = size, flags = flags or "" }
        end
    end
    if message then
        chatFontDefaults = { message = message, input = input or message, inputHeight = inputHeight }
        SC.chatFontDefaults = chatFontDefaults
    end
    return chatFontDefaults
end

local function FindChatFontChoice(id)
    for _, choice in ipairs(CHAT_FONT_CHOICES) do
        if choice.id == id then return choice end
    end
    return CHAT_FONT_CHOICES[1]
end

local function CurrentChatFontSettings()
    local defaults = CaptureChatFontDefaults()
    local db = SC.db or {}
    local choice = FindChatFontChoice(db.chatFontFace or "DEFAULT")
    local file = choice.path or (defaults and defaults.message and defaults.message.file)
    local defaultSize = defaults and defaults.message and defaults.message.size or 14
    local size = tonumber(db.chatFontSize)
    if not size or size <= 0 then size = defaultSize end
    size = math.max(8, math.min(48, math.floor(size + 0.5)))
    local flags = defaults and defaults.message and defaults.message.flags or ""
    return choice, file, size, flags, defaults
end

function SC.ApplyChatTypography()
    if not SC.db then return false end
    local choice, file, size, flags, defaults = CurrentChatFontSettings()
    local frame = DEFAULT_CHAT_FRAME
    if not frame or type(frame.SetFont) ~= "function" or not file then
        SC.Print("chat font controls are unavailable on this client")
        return false
    end
    local okMessage, messageResult = pcall(frame.SetFont, frame, file, size, flags)
    if not okMessage or messageResult == false then
        SC.Print("could not apply the selected chat font; keeping the game font")
        return false
    end

    local editBox = frame.editBox or frame.EditBox
    if editBox and type(editBox.SetFont) == "function" then
        local inputFile, inputSize, inputFlags
        if SC.db.chatFontInput ~= false then
            inputFile, inputSize, inputFlags = file, size,
                (defaults and defaults.input and defaults.input.flags) or flags
            if inputFile and inputSize then
                pcall(editBox.SetFont, editBox, inputFile, inputSize, inputFlags or "")
            end
            -- Keep large input fonts from being clipped by the default single-line box.
            if defaults and defaults.inputHeight and type(editBox.SetHeight) == "function" then
                local targetHeight = math.max(defaults.inputHeight, math.min(64, size + 12))
                pcall(editBox.SetHeight, editBox, targetHeight)
            end
        else
            local original = defaults and defaults.input
            if original then inputFile, inputSize, inputFlags = original.file, original.size, original.flags end
            if inputFile and inputSize then
                pcall(editBox.SetFont, editBox, inputFile, inputSize, inputFlags or "")
            end
            if defaults and defaults.inputHeight and type(editBox.SetHeight) == "function" then
                pcall(editBox.SetHeight, editBox, defaults.inputHeight)
            end
        end
    end

    -- ScrollingMessageFrame:SetFont updates the active chat display directly;
    -- avoid rebuilding the message buffer while the size slider is being adjusted.
    if SC.RefreshChatTextSettingsUI then SC.RefreshChatTextSettingsUI() end
    return true
end

local function ReturnToMainTextSettings()
    if textPanel then
        textPanel._returningToMain = true
        textPanel:Hide()
        textPanel._returningToMain = nil
    end
    if panel then
        panel:Show()
        if SC.RaiseWindow then SC.RaiseWindow(panel, "DIALOG") end
    end
end

local function BuildTextPanel()
    local db = SC.db
    CaptureChatFontDefaults()
    textPanel = CreateFrame("Frame", "SmartChatTextAppearance", UIParent, "BackdropTemplate")
    textPanel:SetSize(540, 420)
    textPanel:SetPoint("CENTER")
    textPanel:SetFrameStrata("FULLSCREEN_DIALOG")
    textPanel:SetMovable(true)
    textPanel:EnableMouse(true)
    textPanel:RegisterForDrag("LeftButton")
    textPanel:SetScript("OnDragStart", textPanel.StartMoving)
    textPanel:SetScript("OnDragStop", textPanel.StopMovingOrSizing)
    textPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    textPanel:SetToplevel(true)
    SC.RegisterWindow(textPanel, { 0.035, 0.040, 0.055, 1 }, { 0.55, 0.55, 0.60, 1 })
    tinsert(UISpecialFrames, "SmartChatTextAppearance")

    Label(textPanel, "Chat Text Appearance", 22, -20, "GameFontNormalLarge")
    Label(textPanel, "Changes apply to all SmartChat chat tabs.", 24, -48, "GameFontDisableSmall")
    local close = CreateFrame("Button", nil, textPanel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local fontLabel = Label(textPanel, "Font family", 28, -91, "GameFontHighlight")
    local fontButton = Btn(textPanel, "", 160, -86, 250, function(self)
        local current = db.chatFontFace or "DEFAULT"
        local index = 1
        for i, choice in ipairs(CHAT_FONT_CHOICES) do if choice.id == current then index = i end end
        db.chatFontFace = CHAT_FONT_CHOICES[index % #CHAT_FONT_CHOICES + 1].id
        self:SetText(FindChatFontChoice(db.chatFontFace).label)
        SC.ApplyChatTypography()
    end)
    SmallFont(fontButton)
    Help(textPanel, fontLabel, "Choose one of the built-in World of Warcraft fonts. Blizzard Default restores the font face used by the game when SmartChat loaded. This changes chat messages only, not message or channel colors.")

    local sizeLabel = Label(textPanel, "Font size", 28, -139, "GameFontHighlight")
    local sizeSlider = CreateFrame("Slider", nil, textPanel)
    sizeSlider:SetOrientation("HORIZONTAL")
    sizeSlider:SetSize(250, 18)
    sizeSlider:SetPoint("TOPLEFT", 160, -135)
    sizeSlider:SetMinMaxValues(8, 48)
    sizeSlider:SetValueStep(1)
    sizeSlider:SetObeyStepOnDrag(true)
    local sizeBG = sizeSlider:CreateTexture(nil, "BACKGROUND")
    sizeBG:SetPoint("LEFT"); sizeBG:SetPoint("RIGHT"); sizeBG:SetHeight(5)
    sizeBG:SetColorTexture(0.22, 0.36, 0.48, 1)
    sizeSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local sizeValue = Label(textPanel, "14", 425, -137, "GameFontHighlight")
    sizeSlider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.max(8, math.min(48, math.floor(value + 0.5)))
        sizeValue:SetText(tostring(rounded))
        if not self.refreshing then
            db.chatFontSize = rounded
            SC.ApplyChatTypography()
        end
    end)
    Help(textPanel, sizeLabel, "Set the message font size from 8 to 48. Larger sizes may use more vertical space and wrap messages onto more lines. Use Reset to Blizzard Default to restore the size captured from the game.")

    local inputCheck = CreateFrame("CheckButton", nil, textPanel, "UICheckButtonTemplate")
    inputCheck:SetSize(24, 24)
    inputCheck:SetPoint("TOPLEFT", 24, -182)
    local inputLabel = Label(textPanel, "Use the same font in the chat input box", 52, -184, "GameFontHighlight")
    inputCheck:SetScript("OnClick", function(self)
        db.chatFontInput = self:GetChecked() and true or false
        SC.ApplyChatTypography()
    end)
    Help(textPanel, inputLabel, "When enabled, the game's typing box uses the selected font family and size too. When disabled, the typing box returns to its original game font. This does not change the font of other game windows.")

    local previewTitle = Label(textPanel, "Preview", 28, -225, "GameFontHighlight")
    Help(textPanel, previewTitle, "A sample preview of the selected font and size. Your actual chat colors and relationship name colors are unchanged.")
    local preview = textPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    preview:SetPoint("TOPLEFT", 30, -250)
    preview:SetWidth(470)
    preview:SetHeight(76)
    preview:SetJustifyH("LEFT")
    preview:SetJustifyV("TOP")
    preview:SetWordWrap(true)
    preview:SetText("The quick brown fox jumps over the lazy dog. 1234567890")

    local RefreshTextPanel
    local reset = Btn(textPanel, "Reset to Blizzard Default", 28, -365, 190, function()
        db.chatFontFace = "DEFAULT"
        db.chatFontSize = 0
        db.chatFontInput = true
        SC.ApplyChatTypography()
        if RefreshTextPanel then RefreshTextPanel() end
    end)
    SmallFont(reset)
    Help(textPanel, reset, "Restores the chat message font and size captured from the game when SmartChat loaded, and uses the same font in the typing box.")
    local back = Btn(textPanel, "Back to Settings", 340, -365, 145, ReturnToMainTextSettings)
    SmallFont(back)

    RefreshTextPanel = function()
        if not textPanel then return end
        local choice, file, size, flags = CurrentChatFontSettings()
        fontButton:SetText(choice.label)
        sizeSlider.refreshing = true
        sizeSlider:SetValue(size)
        sizeSlider.refreshing = false
        sizeValue:SetText(tostring(size))
        inputCheck:SetChecked(db.chatFontInput ~= false)
        if file then pcall(preview.SetFont, preview, file, size, flags or "") end
    end
    SC.RefreshChatTextSettingsUI = function()
        if textPanel and textPanel:IsShown() then RefreshTextPanel() end
    end
    textPanel:SetScript("OnShow", function()
        RefreshTextPanel()
        if SC.RaiseWindow then SC.RaiseWindow(textPanel, "FULLSCREEN_DIALOG") end
    end)
    textPanel:SetScript("OnHide", function(self)
        if not self._returningToMain and panel then
            panel:Show()
            if SC.RaiseWindow then SC.RaiseWindow(panel, "DIALOG") end
        end
    end)
    textPanel:Hide()
end

function SC.ToggleTextSettings()
    if textPanel and textPanel:IsShown() then
        ReturnToMainTextSettings()
        return
    end
    if not panel then Build() end
    if soundPanel and soundPanel:IsShown() then
        soundPanel._returningToMain = true
        soundPanel:Hide()
        soundPanel._returningToMain = nil
    end
    if not textPanel then BuildTextPanel() end
    panel:Hide()
    textPanel:Show()
    if SC.RaiseWindow then SC.RaiseWindow(textPanel, "FULLSCREEN_DIALOG") end
end
SC.ShowTextSettings = function()
    if not panel then Build() end
    if not textPanel then BuildTextPanel() end
    if panel and panel:IsShown() then panel:Hide() end
    textPanel:Show()
    if SC.RaiseWindow then SC.RaiseWindow(textPanel, "FULLSCREEN_DIALOG") end
end


Build = function()
    local db = SC.db
    panel = CreateFrame("Frame", "SmartChatSettings", UIParent, "BackdropTemplate")
    panel:SetSize(700, 700)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetBackdrop({
        -- The default Blizzard dialog artwork has built-in translucency.
        -- Use a solid texture so 100% on the opacity slider is fully opaque.
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    panel:SetToplevel(true)
    SC.RegisterWindow(panel, { 0.035, 0.040, 0.055, 1 }, { 0.55, 0.55, 0.60, 1 })
    tinsert(UISpecialFrames, "SmartChatSettings")

    Label(panel, "SmartChat " .. SC.version, 20, -18, "GameFontNormalLarge")
    Btn(panel, "Social & Journal...", 148, -14, 164, function()
        if SC.ToggleJournalSettings then SC.ToggleJournalSettings() end
    end)
    Btn(panel, "Sound & notifications...", 320, -14, 166, function()
        if SC.ToggleSoundSettings then SC.ToggleSoundSettings() end
    end)
    Btn(panel, "Keyboard shortcuts...", 492, -14, 166, function()
        if SC.ShowBindingsPanel then SC.ShowBindingsPanel() else SC.Print("shortcut editor is not loaded") end
    end)
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local textAppearanceBtn = Btn(panel, "Chat text & fonts...", 20, -43, 170, function()
        if SC.ToggleTextSettings then SC.ToggleTextSettings() end
    end)
    SmallFont(textAppearanceBtn)
    Help(panel, textAppearanceBtn, "Change the font family and size used by chat messages in every SmartChat chat tab. Optionally match the typing box. This does not change message colors, channel colors or other game UI fonts.")

    ------------------------------------------------ left column
    local y = -80
    Label(panel, "Display", 20, y)
    y = y - 24
    local cb, lab = CB(panel, "Timestamps", 20, y, function() return db.timestamps end, function(v) db.timestamps = v end)
    local fmtBtn = Cycle(panel, 118, y, 206, function()
        for _, f in ipairs(TIME_FORMATS) do
            if f.fmt == db.timeFormat then return f.name .. "  " .. date(f.fmt) end
        end
        return date(db.timeFormat)
    end, function()
        local idx = 0
        for i, f in ipairs(TIME_FORMATS) do if f.fmt == db.timeFormat then idx = i end end
        db.timeFormat = TIME_FORMATS[idx % #TIME_FORMATS + 1].fmt
    end)
    Help(panel, fmtBtn, "The Timestamps checkbox shows or hides time labels before messages. Click this button to switch the time format.\n\n24-hour = 14:23\n12-hour = 02:23 PM\n\nThe time shown on the button is the current time.")
    y = y - 26
    local gbtn = Cycle(panel, 24, y, 296, function()
        local on = GameStampOn()
        if on and db.timestamps then return "Game timestamps ON = two times! Click to fix" end
        return on and "Game timestamps: ON (click to turn off)" or "Game timestamps: OFF (click to turn on)"
    end, function()
        local ok = pcall(SetCVar, "showTimestamps", GameStampOn() and "none" or "%H:%M ")
        if not ok then SC.Print("could not change the game's timestamp setting") end
    end)
    Help(panel, gbtn, "WoW has its own timestamps (Esc > Options > Social > Timestamps), usually 12-hour. If both are on you see two times before each line. Click to turn the game's timestamps off (or back on in 24-hour format).")
    y = y - 28
    cb, lab = CB(panel, "Badges [F][B][G][P][W] next to names", 20, y, function() return db.badges end, function(v)
        db.badges = v
        if SC.RefreshContactViews then SC.RefreshContactViews() end
    end)
    Help(panel, lab, "Letters before a player's name:\nF = in your in-game friend list\nB = a Battle.net friend (the character they are playing)\nG = in your guild\nP = in your group\nW = whispered you this session\n\nNot shown during boss encounters (the game hides chat from addons then).")
    y = y - 26
    cb, lab = CB(panel, "Enable custom name colors", 20, y, function() return db.nameColors end, function(v)
        db.nameColors = v
        if SC.RefreshContactViews then SC.RefreshContactViews() end
    end)
    Help(panel, lab, "Enables SmartChat name-color options. Message text and channel colors are never changed.")
    y = y - 24
    local modeBtn = Cycle(panel, 42, y, 250, function()
        return "Name color mode: " .. ((db.nameColorMode == "class") and "Class" or "Relationship")
    end, function()
        db.nameColorMode = (db.nameColorMode == "class") and "relationship" or "class"
        if SC.RefreshContactViews then SC.RefreshContactViews() end
    end)
    Help(panel, modeBtn, "Relationship: colors names by Friend, Battle.net, Guild and Group relationships. Combined relationships blend their source colors; Guild and Group inherit the current tab colors. Class: keeps the game's original class color. This affects names only, never message text. Changes apply to new chat lines. Default: Relationship.")
    y = y - 28
    cb, lab = CB(panel, "Unread counter on tabs", 20, y, function() return db.unread end, function(v) db.unread = v; SC.RebuildTabs() end)
    Help(panel, lab, "Shows how many messages arrived on a tab you are not looking at, e.g. Party (3). (3!) means one of them was an alert.")
    y = y - 26
    cb, lab = CB(panel, "Clicking a tab also opens the typing box", 20, y,
        function() return db.clickOpensEditBox end, function(v) db.clickOpensEditBox = v end)
    Help(panel, lab, "OFF (recommended): clicking a tab only changes the visible chat. Press Enter or click the game's input box when you want to type. ON: clicking a tab also focuses the input box, like the old SmartChat behavior.")
    y = y - 26
    cb, lab = CB(panel, "Show the side icon toolbar", 20, y,
        function() return db.showDock end, function(v) db.showDock = v; if SC.ApplyDockVisibility then SC.ApplyDockVisibility() end end)
    Help(panel, lab, "Shows quick buttons beside the chat window: channels, Social Hub, settings, keyboard shortcuts, copy and new tab.")
    y = y - 26
    cb, lab = CB(panel, "Make web addresses clickable", 20, y,
        function() return db.webLinks ~= false end, function(v) db.webLinks = v end)
    Help(panel, lab, "Turns plain HTTP/HTTPS, www, Discord invite and common website addresses in chat into clickable links. Clicking opens a small copy box with the address selected; press Ctrl+C to copy it. SmartChat does not launch an external browser. Link clicks are disabled during combat. Existing WoW item, spell, quest and player links keep their normal behavior.")
    y = y - 34

    local title = Label(panel, "Hidden tabs", 20, y)
    Help(panel, title, "Tabs you hid with right-click > Hide tab appear here. Click one to bring it back.\n\nName, color, sound, position, hide and remove are all in the right-click menu of each tab on the bar.")
    y = y - 24
    local none = Label(panel, "None - every tab is visible", 28, y - 4, "GameFontDisableSmall")
    local hiddenBtns = {}
    for i = 1, 9 do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local hb = Btn(panel, "", 24 + col * 104, y - row * 24, 100, function(self)
            SC.db.hidden[self.id] = nil
            SC.RebuildTabs()
            SC.RefreshSettings()
        end)
        hb:Hide()
        hiddenBtns[i] = hb
    end
    refreshers[#refreshers + 1] = function()
        local list = {}
        for _, id in ipairs(db.order) do
            if db.hidden[id] and SC.TABS[id] then list[#list + 1] = id end
        end
        for i, hb in ipairs(hiddenBtns) do
            local id = list[i]
            if id then hb.id = id; hb:SetText(SC.TABS[id].label); hb:Show() else hb:Hide() end
        end
        none:SetShown(#list == 0)
    end
    y = y - 3 * 24 - 12

    title = Label(panel, "History", 20, y)
    Help(panel, title, "Saves chat lines on your computer and shows the latest ones when you log in. Whisper text is saved too. Lines are not saved during boss encounters.")
    y = y - 24
    cb, lab = CB(panel, "Save chat between sessions", 20, y, function() return db.historyEnabled end, function(v) db.historyEnabled = v end)
    Help(panel, lab, "When enabled, chat lines including Whisper text are saved locally in the game's SavedVariables so recent messages can be shown after you log in. This is OFF by default.")
    y = y - 28
    lab = Label(panel, "Keep days (0 = no age limit):", 28, y - 3, "GameFontHighlightSmall")
    Help(panel, lab, "Age limit for locally stored chat lines. Set to 0 to disable age-based cleanup; the maximum stored lines setting still applies.")
    NumBox(panel, 190, y, function() return db.historyDays end, function(v) db.historyDays = math.max(0, math.floor(v)); SC.PruneHistory() end)
    y = y - 26
    lab = Label(panel, "Maximum stored lines:", 28, y - 3, "GameFontHighlightSmall")
    Help(panel, lab, "Maximum number of chat lines retained locally (1-10000). This limit applies even when Keep days is set to 0.")
    NumBox(panel, 190, y, function() return db.historyMax or 1000 end, function(v) db.historyMax = math.max(1, math.min(10000, math.floor(v))); SC.PruneHistory() end)
    y = y - 26
    lab = Label(panel, "Lines to load at login:", 28, y - 3, "GameFontHighlightSmall")
    Help(panel, lab, "How many of the most recent saved lines to display when you log in. This does not change the maximum number stored.")
    NumBox(panel, 190, y, function() return db.historyLoad end, function(v) db.historyLoad = math.max(0, math.floor(v)) end); y = y - 28
    local clearHistoryButton = Btn(panel, "Clear history", 24, y, 130, function() SC.ClearHistory(); SC.Print("history cleared") end)
    Help(panel, clearHistoryButton, "Permanently clears the locally saved Chat History entries. This does not clear Player Journal events, notes, Favorites or contact groups.")
    y = y - 38

    title = Label(panel, "Word filter", 20, y)
    Help(panel, title, "Messages that contain one of these words are hidden. Separate words with commas, upper/lower case does not matter. Press Enter to save.")
    y = y - 24
    WordBox(panel, 26, y, 290, function() return db.filterWords end, function(l) db.filterWords = l end); y = y - 26
    cb, lab = CB(panel, "Mask with *** instead of hiding", 20, y, function() return db.filterMask end, function(v) db.filterMask = v end)
    Help(panel, lab, "When a message matches a filtered word, replace the word with asterisks instead of hiding the entire message.")
    
    ------------------------------------------------ right column
    y = -80
    title = Label(panel, "Reorder tabs", R, y)
    Help(panel, title, "Middle-click a tab on the bar, then scroll the mouse wheel to move it.\n\nGrabbed tab stays in the middle: the tab you grabbed stays in the center of the pop-up and the others move around it.\nMarker moves: the whole list is shown and a marker moves through it.\n\nThe pop-up closes when you click outside, move the mouse away, or press Esc.")
    y = y - 24
    local styleNames = { fixed = "Grabbed tab stays in the middle", moving = "Marker moves through the list" }
    Cycle(panel, R + 6, y, 290, function() return styleNames[db.reorderStyle] or styleNames.fixed end, function()
        db.reorderStyle = (db.reorderStyle == "moving") and "fixed" or "moving"
    end)
    y = y - 40

    title = Label(panel, "Opacity", R, y)
    Help(panel, title, "Make windows see-through.\n\nSmartChat windows: this settings window, tab menus and the copy window.\nTab bar: the dark strip behind the tabs.\nChat background: the game's own chat window background (same as Esc > Options > Social > Chat > Background Opacity).")
    y = y - 26
    local _, windowOpacityLabel = Slider(panel, "SmartChat windows", R + 8, y, 0.2, 1, function() return db.windowAlpha end,
        function(v) db.windowAlpha = v; SC.ApplyWindowAlpha() end)
    Help(panel, windowOpacityLabel, "Adjust transparency of SmartChat windows such as Settings, tab menus and the copy dialog.")
    y = y - 28
    local _, tabOpacityLabel = Slider(panel, "Tab bar", R + 8, y, 0, 1, function() return db.barAlpha end,
        function(v) db.barAlpha = v; SC.ApplyBarAlpha() end)
    Help(panel, tabOpacityLabel, "Adjust transparency of the background strip behind the chat tabs.")
    y = y - 28
    local _, chatOpacityLabel = Slider(panel, "Chat background", R + 8, y, 0, 1,
        function() return db.chatAlpha or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.oldAlpha) or 0.25 end,
        function(v) SC.ApplyChatAlpha(v) end)
    Help(panel, chatOpacityLabel, "Adjust transparency of the game's chat frame background. This changes the game's chat background opacity setting.")
    y = y - 40

    title = Label(panel, "Alerts", R, y)
    Help(panel, title, "The tab flashes and the alert sound plays when a message contains your character name or one of your extra words. Alerts work even if that tab's sound is off. Not active during boss encounters.")
    y = y - 24
    cb, lab = CB(panel, "When someone writes my character name", R, y, function() return db.alertOwnName end, function(v) db.alertOwnName = v end)
    Help(panel, lab, "Flash the matching tab and play the alert sound when a chat message contains your current character name. Alerts are disabled during boss encounters.")
    y = y - 26
    lab = Label(panel, "Extra words:", R + 8, y, "GameFontHighlightSmall")
    Help(panel, lab, "Separate words with commas, upper/lower case does not matter. Example: raid, invite, mythic. Press Enter to save.")
    y = y - 18
    WordBox(panel, R + 12, y, 300, function() return db.alertWords end, function(l) db.alertWords = l end); y = y - 28
    local alertSoundLabel = Label(panel, "Alert sound:", R + 8, y - 5, "GameFontHighlightSmall")
    Help(panel, alertSoundLabel, "Choose which sound plays when an alert is triggered. Select NONE to disable the alert sound while keeping visual tab flashes.")
    local alertSoundButton = Cycle(panel, R + 80, y, 190, function() return db.alertSound or "NONE" end, function()
        db.alertSound = NextSound(db.alertSound)
        SC.PlayKit(db.alertSound)
    end)
    Help(panel, alertSoundButton, "Click to cycle through the available alert sounds.")
    local alertTestButton = Btn(panel, "Test", R + 275, y, 50, function() SC.PlayKit(db.alertSound) end)
    Help(panel, alertTestButton, "Play the currently selected alert sound once as a preview.")
    y = y - 42

    title = Label(panel, "Keyboard shortcuts", R, y)
    Help(panel, title, "Use the Keyboard shortcuts button at the top or Open shortcut editor here to assign keys inside SmartChat. Before replacing an occupied key, SmartChat shows the current action and asks for confirmation. It also checks again when the game's binding map changes. Shortcuts are unassigned by default, and key changes are only allowed out of combat.")
    y = y - 24
    Label(panel, "Free key suggestions appear in gray inside each key field.", R + 8, y, "GameFontHighlightSmall")
    y = y - 17
    Label(panel, "Click a field and press the key combination you want.", R + 8, y, "GameFontHighlightSmall")
    y = y - 26
    Btn(panel, "Check shortcut conflicts", R + 8, y, 165, function()
        if SC.CheckBindings then SC.CheckBindings() else SC.Print("key binding diagnostics are not loaded") end
    end)
    Btn(panel, "Open shortcut editor", R + 180, y, 140, function()
        if SC.ShowBindingsPanel then SC.ShowBindingsPanel() else SC.Print("shortcut editor is not loaded") end
    end)

    panel:SetScript("OnShow", function()
        for _, r in ipairs(refreshers) do r() end
        if SC.RaiseWindow then SC.RaiseWindow(panel, "DIALOG") end
    end)
    panel:Hide()
end

-- /sc check : which game functions SmartChat needs exist on THIS client
local function RunCheck()
    local function yes(v) return v and true or false end
    local P = Enum and Enum.PartyCategory
    local tests = {
        { "Chat filter function (word filter)",       yes(ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)) },
        { "Chat edit-box header update",              yes(DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox and DEFAULT_CHAT_FRAME.editBox.UpdateHeader) },
        { "Open chat box (modern API)",               yes(ChatFrameUtil and ChatFrameUtil.OpenChat) },
        { "Get/set chat type (modern edit-box API)",  yes(DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox and DEFAULT_CHAT_FRAME.editBox.SetChatType and DEFAULT_CHAT_FRAME.editBox.GetChatType) },
        { "Set whisper target (modern edit-box API)", yes(DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox and DEFAULT_CHAT_FRAME.editBox.SetTellTarget) },
        { "Set channel target (modern edit-box API)", yes(DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox and DEFAULT_CHAT_FRAME.editBox.SetChannelTarget) },
        { "Set sticky type (modern edit-box API)",    yes(DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox and DEFAULT_CHAT_FRAME.editBox.SetStickyType) },
        { "Chat background (FCF_SetWindowAlpha)",     yes(FCF_SetWindowAlpha) },
        { "Friend list (C_FriendList.GetFriendInfo)", yes(C_FriendList and C_FriendList.GetFriendInfo) },
        { "Guild roster",                             yes(GetNumGuildMembers and GetGuildRosterInfo) },
        { "Channel list",                             yes(GetChannelList or (C_ChatInfo and C_ChatInfo.GetChannelList)) },
        { "Battle.net friends (letter B)",            yes(C_BattleNet and C_BattleNet.GetFriendAccountInfo and BNGetNumFriends) },
        { "Color picker (new API)",                   yes(ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) },
        { "Game timestamps (CVar showTimestamps)",    (function() local ok, v = pcall(GetCVar, "showTimestamps"); return ok and v ~= nil end)() },
        { "Read a chat line text (reply quote)",      yes(C_ChatInfo and C_ChatInfo.GetChatLineText) },
        { "Chat types table (display filter)",        yes(type(ChatTypeInfo) == "table" and ChatTypeInfo.PARTY and ChatTypeInfo.PARTY.id) },
        { "Clickable web link handler",                yes(SC.LinkifyWebAddresses and SC.webLinkHandlerAvailable) },
        { "Chat window Clear / messages",             yes(DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.Clear and DEFAULT_CHAT_FRAME.GetNumMessages) },
        { "Dynamic key-binding API",                  yes(SetBindingClick and GetBindingAction and GetBindingKey and SaveBindings) },
        { "Per-sound volume override (C_Sound.PlaySound)", yes(C_Sound and C_Sound.PlaySound) },
        { "Custom Sound Pack playback (PlaySoundFile)", yes(PlaySoundFile) },
        { "Instance party categories",                yes(P or LE_PARTY_CATEGORY_HOME) },
        { "Chat lockdown API  (12.x only)",           yes(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown) },
        { "Secret values API  (12.x only)",           yes(issecretvalue) },
    }
    local version, build, _, toc = GetBuildInfo()
    SC.Print("check on game " .. tostring(version) .. " (build " .. tostring(build) .. ", interface " .. tostring(toc) .. ")")
    if SC.isForever then SC.Print("Forever/Camelot client detected.") end
    local missing = 0
    for _, t in ipairs(tests) do
        print((t[2] and "  |cff55ff55OK|r      " or "  |cffff5555MISSING|r ") .. t[1])
        if not t[2] then missing = missing + 1 end
    end
    print("  sounds available: " .. (#SC.AvailableSounds() - 1) .. " (including " .. tostring(#(SC.SOUND_PACK or {})) .. " bundled sounds)")
    if missing == 0 then
        SC.Print("all checked APIs are present.")
    elseif SC.isForever then
        SC.Print(missing .. " checked API(s) are missing on Forever; send the output with your bug report.")
    else
        SC.Print(missing .. " checked API(s) are missing; optional APIs may disable related features.")
    end
end

local function RunRouteCheck()
    local tab = SC._tabs and SC._tabs[SC.active]
    local def = tab and tab.def or SC.TABS[SC.active]
    local eb = SC.GetRouteEditBox and SC.GetRouteEditBox()
        or ((ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
        or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox))
    local desired = def and SC.ResolveChatType and SC.ResolveChatType(def.chatType) or (def and def.chatType)
    local actual = eb and SC.GetEditBoxChatType and SC.GetEditBoxChatType(eb)
    local sticky = eb and SC.GetEditBoxStickyType and SC.GetEditBoxStickyType(eb)
    local function SafeValue(value)
        if value == nil then return "unavailable" end
        if SC.IsSecret and SC.IsSecret(value) then return "restricted during combat" end
        return tostring(value)
    end
    SC.Print("selected tab: " .. tostring(def and def.label or SC.active or "none"))
    SC.Print("input box: " .. tostring(eb and eb.GetName and eb:GetName() or "unknown"))
    SC.Print("wanted chat type: " .. SafeValue(desired))
    SC.Print("edit-box chat type: " .. SafeValue(actual))
    SC.Print("edit-box sticky type: " .. SafeValue(sticky))
    if desired and actual and not (SC.IsSecret and SC.IsSecret(actual)) and actual ~= desired then
        SC.Print("ROUTE MISMATCH: send the output of /sc route to the addon developer.")
    elseif desired and actual == desired then
        SC.Print("route matches the selected tab.")
    end
end

local function Toggle()
    if soundPanel and soundPanel:IsShown() then
        ReturnToMainSettings()
        return
    end
    if textPanel and textPanel:IsShown() then
        ReturnToMainTextSettings()
        return
    end
    if not panel then Build() end
    panel:SetShown(not panel:IsShown())
    if panel:IsShown() and SC.RaiseWindow then SC.RaiseWindow(panel, "DIALOG") end
end
SC.ToggleSettings = Toggle

function SC.RefreshSettings()
    if panel and panel:IsShown() then
        for _, r in ipairs(refreshers) do r() end
    end
end

-- pinned message
local pin
local function ShowPin()
    if not SC.bar then return end
    if not pin then
        pin = CreateFrame("Frame", "SmartChatPin", UIParent)
        pin:SetHeight(18)
        pin:SetPoint("BOTTOMLEFT", SC.bar, "TOPLEFT", 0, 2)
        pin.bg = pin:CreateTexture(nil, "BACKGROUND")
        pin.bg:SetAllPoints(); pin.bg:SetColorTexture(0.3, 0.25, 0, 0.5)
        pin.text = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pin.text:SetPoint("LEFT", 6, 0)
        pin.text:SetJustifyH("LEFT")
    end
    local t = SC.db.pinned
    if t and t ~= "" then
        pin.text:SetText("PIN: " .. t)
        pin:SetWidth(math.max(120, pin.text:GetStringWidth() + 14))
        pin:Show()
    else
        pin:Hide()
    end
end

SLASH_SMARTCHAT1 = "/smartchat"
SLASH_SMARTCHAT2 = "/sc"
SlashCmdList["SMARTCHAT"] = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "pin" and rest ~= "" then
        SC.db.pinned = rest; ShowPin()
    elseif cmd == "unpin" then
        SC.db.pinned = nil; ShowPin()
    elseif cmd == "pos" then
        local x, y = rest:match("^(-?%d+)%s+(-?%d+)$")
        if x then SC.db.barX, SC.db.barY = tonumber(x), tonumber(y); SC.PositionBar()
        else SC.Print("usage: /sc pos <x> <y>   (default -2 32)") end
    elseif cmd == "tabs" or cmd == "newtab" then
        if SC.ShowNewTabMenu then SC.ShowNewTabMenu(SC.bar) end
    elseif cmd == "show" and rest ~= "" then
        local want = rest:lower()
        for id, d in pairs(SC.TABS) do
            if SC.db.hidden[id] and (id == want or d.label:lower() == want) then
                SC.db.hidden[id] = nil
                SC.RebuildTabs()
                SC.Print("tab shown: " .. d.label)
                return
            end
        end
        SC.Print("no hidden tab called \"" .. rest .. "\"")
    elseif cmd == "check" then
        RunCheck()
    elseif cmd == "copy" then
        SC.ShowCopy()
    elseif cmd == "binds" then
        if SC.CheckBindings then SC.CheckBindings() else SC.Print("key binding diagnostics are not loaded") end
    elseif cmd == "route" then
        RunRouteCheck()
    elseif cmd == "dock" then
        SC.db.showDock = not SC.db.showDock
        if SC.ApplyDockVisibility then SC.ApplyDockVisibility() end
        SC.Print("side toolbar " .. (SC.db.showDock and "shown" or "hidden"))
    elseif cmd == "resetorder" then
        SC.db.order = SC.deepcopy(SC.defaultOrder); SC.RebuildTabs()
    elseif cmd == "help" then
        SC.Print("/sc settings | /sc check | /sc route | /sc binds | /sc dock | /sc newtab | /sc show <tab> | /sc copy | /sc pin <text> | /sc unpin | /sc pos <x> <y> | /sc resetorder")
    else
        Toggle()
    end
end

table.insert(SC.onLogin, function()
    CaptureChatFontDefaults()
    if SC.db and ((SC.db.chatFontFace and SC.db.chatFontFace ~= "DEFAULT")
        or (tonumber(SC.db.chatFontSize) or 0) > 0 or SC.db.chatFontInput == false) then
        SC.ApplyChatTypography()
    end
end)

table.insert(SC.onLogin, ShowPin)
