local ADDON, SC = ...

-- Right-click a tab  -> its settings menu
-- "New" button       -> create a tab

local menu, newMenu

local BG     = { 0.05, 0.05, 0.07, 0.97 }
local BORDER = { 0.55, 0.55, 0.55, 1 }

---------------------------------------------------------------------
-- small helpers
---------------------------------------------------------------------
local function Label(parent, text, x, y, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
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

local function Help(parent, x, y, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    b:SetPoint("TOPLEFT", x, y)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER")
    fs:SetText("?")
    fs:SetTextColor(0.4, 0.8, 1)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

local function Trim(s)
    s = (s or ""):gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
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

local function SoundKey(id)
    if id:sub(1, 2) == "w:" then return "whisper" end
    return id
end

local function TypeLabel(def)
    if def.viewOnly then return "All chat / view only" end
    if def.chatType == "CHANNEL" then
        return def.channelMatch and ("Channel: " .. def.channelMatch) or "Channel"
    end
    if def.dynamic then return "Whisper" end
    for _, t in ipairs(SC.CHAT_TYPES) do if t.type == def.chatType then return t.label end end
    return def.chatType
end

local function MakeFrame(name, w)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(w, 100)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    SC.RegisterWindow(f, BG, BORDER)
    tinsert(UISpecialFrames, name)
    f:SetScript("OnHide", function() SC.HideCatcher() end)
    return f
end

local function Row(parent, h)
    local r = CreateFrame("Frame", nil, parent)
    r.h = h or 26
    r:SetSize(236, r.h)
    return r
end

-- stack the visible rows top to bottom and size the frame to fit
local function LayoutRows(f, rows)
    local y = -10
    for _, r in ipairs(rows) do
        if r.show then
            r.f:ClearAllPoints()
            r.f:SetPoint("TOPLEFT", 10, y)
            r.f:Show()
            y = y - (r.f.h + 4)
        else
            r.f:Hide()
        end
    end
    f:SetHeight(-y + 6)
end

-- open the game's color picker (new API in 10.2.5+, old API as a fallback)
function SC.PickColor(r, g, b, onChange)
    local cpf = ColorPickerFrame
    if not cpf then SC.Print("color picker not available"); return end
    local function swatch()
        local nr, ng, nb = cpf:GetColorRGB()
        onChange(nr, ng, nb)
    end
    local function cancel(prev)
        if type(prev) == "table" and prev.r then onChange(prev.r, prev.g, prev.b) else onChange(r, g, b) end
    end
    local ok, err = pcall(function()
        if cpf.SetupColorPickerAndShow then
            cpf:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false, swatchFunc = swatch, cancelFunc = cancel })
        else
            cpf.hasOpacity = false
            cpf.previousValues = { r = r, g = g, b = b }
            cpf.func, cpf.swatchFunc, cpf.cancelFunc = swatch, swatch, cancel
            cpf:SetColorRGB(r, g, b)
            cpf:Hide(); cpf:Show()
        end
    end)
    if not ok then SC.Print("could not open the color picker: " .. tostring(err)) end
end

local function Swatch(parent, x, y, getColor, onPick)
    local sw = CreateFrame("Button", nil, parent)
    sw:SetSize(60, 20)
    sw:SetPoint("TOPLEFT", x, y)
    sw.border = sw:CreateTexture(nil, "BACKGROUND")
    sw.border:SetAllPoints(); sw.border:SetColorTexture(0.6, 0.6, 0.6, 1)
    sw.tex = sw:CreateTexture(nil, "ARTWORK")
    sw.tex:SetPoint("TOPLEFT", 1, -1); sw.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    function sw:Update() local c = getColor(); self.tex:SetColorTexture(c[1], c[2], c[3], 1) end
    sw:SetScript("OnClick", function()
        local c = getColor()
        SC.PickColor(c[1], c[2], c[3], function(r, g, b) onPick({ r, g, b }); sw:Update() end)
    end)
    return sw
end

---------------------------------------------------------------------
-- tab settings menu (right-click)
---------------------------------------------------------------------
local function CurrentDef() return menu and menu.id and SC.TABS[menu.id] end

local function BuildMenu()
    menu = MakeFrame("SmartChatTabMenu", 256)
    local R = {}
    menu.rows = R

    -- title
    R.title = { f = Row(menu, 20) }
    menu.titleText = R.title.f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    menu.titleText:SetPoint("LEFT", 0, 0)

    -- name
    R.name = { f = Row(menu) }
    Label(R.name.f, "Name", 0, -6, "GameFontHighlight")
    menu.nameBox = CreateFrame("EditBox", nil, R.name.f, "InputBoxTemplate")
    menu.nameBox:SetPoint("TOPLEFT", 62, -2)
    menu.nameBox:SetSize(142, 20)
    Help(R.name.f, 216, -4, "Rename this tab. The Whisper tab uses its fixed name.")
    menu.nameBox:SetAutoFocus(false)
    menu.nameBox:SetMaxLetters(14)
    local function commitName(self)
        local txt = Trim(self:GetText())
        local d = CurrentDef()
        if d and txt ~= "" and txt ~= d.label then SC.SetTabLook(menu.id, txt:sub(1, 14)) end
        self:ClearFocus()
    end
    menu.nameBox:SetScript("OnEnterPressed", commitName)
    menu.nameBox:SetScript("OnEditFocusLost", commitName)

    -- color
    R.color = { f = Row(menu) }
    Label(R.color.f, "Color", 0, -6, "GameFontHighlight")
    menu.swatch = Swatch(R.color.f, 62, -3,
        function() local d = CurrentDef(); return d and d.color or { 1, 1, 1 } end,
        function(c) SC.SetTabLook(menu.colorId or menu.id, nil, c) end)
    Help(R.color.f, 132, -4, "Choose the color used for this tab and its tab label.")

    -- channel (custom channel tabs)
    R.channel = { f = Row(menu) }
    Label(R.channel.f, "Channel", 0, -6, "GameFontHighlight")
    menu.chBox = CreateFrame("EditBox", nil, R.channel.f, "InputBoxTemplate")
    menu.chBox:SetPoint("TOPLEFT", 62, -2)
    menu.chBox:SetSize(142, 20)
    Help(R.channel.f, 216, -4, "Match this custom tab to the name or number of a chat channel you have joined.")
    menu.chBox:SetAutoFocus(false)
    local function commitChannel(self)
        local txt = Trim(self:GetText())
        local d = CurrentDef()
        if d and d.custom and d.chatType == "CHANNEL" and txt ~= "" then d.channelMatch = txt end
        self:ClearFocus()
    end
    menu.chBox:SetScript("OnEnterPressed", commitChannel)
    menu.chBox:SetScript("OnEditFocusLost", commitChannel)

    -- sound
    R.sound = { f = Row(menu) }
    menu.soundCB = CreateFrame("CheckButton", nil, R.sound.f, "UICheckButtonTemplate")
    menu.soundCB:SetSize(24, 24); menu.soundCB:SetPoint("TOPLEFT", -2, 0)
    Label(R.sound.f, "Sound", 24, -6, "GameFontHighlight")
    Help(R.sound.f, 216, -4, "Enable or disable notification sounds for this tab.")
    menu.soundCB:SetScript("OnClick", function(self)
        SC.db.sound[SoundKey(menu.id)] = self:GetChecked() and true or false
        SC.RebuildTabs()
    end)
    R.kit = { f = Row(menu) }
    menu.kitBtn = Btn(R.kit.f, "", 0, -2, 168, function(self)
        local k = SoundKey(menu.id)
        local function choose(value)
            SC.db.soundKit[k] = value
            self:SetText(SoundText(value))
            SC.PlayKit(value, SC.GetSoundVolume and SC.GetSoundVolume(k) or 1)
        end
        if not (SC.ShowSoundPicker and SC.ShowSoundPicker(self, SC.db.soundKit[k], choose)) then
            SC.db.soundKit[k] = NextSound(SC.db.soundKit[k])
            self:SetText(SoundText(SC.db.soundKit[k]))
            SC.PlayKit(SC.db.soundKit[k], SC.GetSoundVolume and SC.GetSoundVolume(k) or 1)
        end
    end)
    SmallFont(menu.kitBtn)
    Help(R.kit.f, 220, -4, "Choose the notification sound used by this tab. The Test button previews the selected sound.")
    Btn(R.kit.f, "Test", 174, -2, 42, function()
        local k = SoundKey(menu.id)
        -- Test is an explicit audition: it ignores this tab's notification
        -- toggle, but still respects Master Mute and both volume levels.
        SC.PlayKit(SC.db.soundKit[k], SC.GetSoundVolume and SC.GetSoundVolume(k) or 1)
    end)

    -- The tab volume here edits the exact same SavedVariable used by the
    -- Sound & Notifications page. The effective value is always Master x Tab.
    R.volume = { f = Row(menu, 38) }
    Label(R.volume.f, "Tab volume", 0, -5, "GameFontHighlightSmall")
    menu.volumeSlider = CreateFrame("Slider", nil, R.volume.f)
    menu.volumeSlider:SetOrientation("HORIZONTAL")
    menu.volumeSlider:SetSize(100, 14)
    menu.volumeSlider:SetPoint("TOPLEFT", 76, -4)
    menu.volumeSlider:SetMinMaxValues(0, 1)
    menu.volumeSlider:SetValueStep(0.1)
    menu.volumeSlider:SetObeyStepOnDrag(true)
    local volBG = menu.volumeSlider:CreateTexture(nil, "BACKGROUND")
    volBG:SetPoint("LEFT"); volBG:SetPoint("RIGHT"); volBG:SetHeight(4)
    volBG:SetColorTexture(0.35, 0.35, 0.35, 1)
    menu.volumeSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    menu.volumeValue = Label(R.volume.f, "100%", 182, -5, "GameFontHighlightSmall")
    menu.volumeSummary = Label(R.volume.f, "M 100%  |  Out 100%", 76, -23, "GameFontDisableSmall")
    menu.volumeSummary:SetWidth(136)
    Help(R.volume.f, 218, -4, "Set this tab's individual volume. Final playback volume is Master Volume multiplied by Tab Volume.")

    local function RefreshMenuSoundVolume()
        local key = SoundKey(menu.id)
        local tabVolume = SC.GetTabSoundVolume and SC.GetTabSoundVolume(key) or 1
        local masterVolume = math.max(0, math.min(1, tonumber(SC.db.soundMasterVolume) or 1))
        local effective = SC.GetSoundVolume and SC.GetSoundVolume(key) or (tabVolume * masterVolume)
        menu.volumeSlider.refreshing = true
        menu.volumeSlider:SetValue(tabVolume)
        menu.volumeSlider.refreshing = false
        menu.volumeValue:SetText(math.floor(tabVolume * 100 + 0.5) .. "%")
        local suffix = SC.db.soundNotificationsEnabled == false and "  |cffff6666MUTED|r" or ""
        menu.volumeSummary:SetText("M " .. math.floor(masterVolume * 100 + 0.5)
            .. "%  |  Out " .. math.floor(effective * 100 + 0.5) .. "%" .. suffix)
    end
    menu.RefreshSoundVolume = RefreshMenuSoundVolume
    menu.volumeSlider:SetScript("OnValueChanged", function(self, value)
        if self.refreshing or not menu.id then return end
        local key = SoundKey(menu.id)
        SC.db.soundVolume = SC.db.soundVolume or {}
        SC.db.soundVolume[key] = math.max(0, math.min(1, tonumber(value) or 0))
        RefreshMenuSoundVolume()
        if SC.RefreshSoundSettingsUI then SC.RefreshSoundSettingsUI() end
        if SC.db.soundLivePreview and SC.PreviewTabSound then SC.PreviewTabSound(key) end
    end)
    menu.volumeSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Tab Volume", 1, 1, 1)
        GameTooltip:AddLine("Changes the same per-tab volume as Sound & Notifications.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Final volume = Master Volume × Tab Volume.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    menu.volumeSlider:SetScript("OnLeave", GameTooltip_Hide)

    -- display filter
    R.display = { f = Row(menu) }
    menu.displayBtn = Btn(R.display.f, "", 0, -2, 210, function()
        local tab = SC.TabFrame(menu.id)
        if tab then SC.ShowDisplayMenu(tab) end
    end)
    Help(R.display.f, 216, -4, "Choose which message categories this tab displays. This does not change where your outgoing messages are sent.")

    -- reply (Ctrl+click on a name)
    R.reply = { f = Row(menu) }
    menu.replyCB = CreateFrame("CheckButton", nil, R.reply.f, "UICheckButtonTemplate")
    menu.replyCB:SetSize(24, 24); menu.replyCB:SetPoint("TOPLEFT", -2, 0)
    Label(R.reply.f, "Reply: Ctrl+click on a name", 24, -6, "GameFontHighlightSmall")
    Help(R.reply.f, 216, -4, "When enabled, Ctrl-clicking a player's name opens a reply box in that message's channel with a short quote. This is specific to this tab.")
    menu.replyCB:SetScript("OnClick", function(self)
        SC.db.replyOff[SoundKey(menu.id)] = (not self:GetChecked()) or nil
    end)
    menu.replyCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("While this tab is active, Ctrl+click on a player's name in chat opens the box in that message's channel with a short quote of it, so you can answer. Others just see normal text.\n\nUntick to turn it off for this tab.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    menu.replyCB:SetScript("OnLeave", GameTooltip_Hide)

    -- move
    R.move = { f = Row(menu) }
    Btn(R.move.f, "< Move left", 0, -2, 98, function() SC.MoveTabBy(menu.id, -1) end)
    Btn(R.move.f, "Move right >", 106, -2, 98, function() SC.MoveTabBy(menu.id, 1) end)
    Help(R.move.f, 216, -4, "Move this tab one position left or right along the tab bar.")

    -- hide + action
    R.actions = { f = Row(menu) }
    menu.hideBtn = Btn(R.actions.f, "Hide tab", 0, -2, 98, function()
        if SC.VisibleTabCount() <= 1 then SC.Print("keep at least one tab visible."); return end
        SC.db.hidden[menu.id] = true
        menu:Hide()
        SC.RebuildTabs()
        SC.Print("tab hidden. Bring it back from /sc (Hidden tabs).")
        if SC.RefreshSettings then SC.RefreshSettings() end
    end)
    menu.actBtn = Btn(R.actions.f, "", 106, -2, 98, function()
        local d = CurrentDef()
        local id = menu.id
        menu:Hide()
        if d and d.custom then SC.RemoveCustomTab(id)
        elseif d then SC.ResetTab(id)
        else SC.CloseDynamicTab(id) end
    end)
    Help(R.actions.f, 216, -4, "Hide this tab temporarily, or use the second button to reset, remove or close it depending on the tab type.")
end

function SC.ShowTabMenu(tab)
    if not menu then BuildMenu() end
    if menu:IsShown() and menu.id == tab.id then menu:Hide() return end
    local def = tab.def
    local id = tab.id
    local dyn = def.dynamic and true or false
    menu.id = id
    menu.colorId = dyn and "whisper" or id
    local R = menu.rows

    menu.titleText:SetText(tab.label .. "  |cff888888(" .. TypeLabel(def) .. ")|r")
    menu.titleText:SetTextColor(def.color[1], def.color[2], def.color[3])

    local canRename = (not dyn) and id ~= "whisper"
    R.name.show = canRename
    menu.nameBox:SetText(def.label)
    R.color.show = true
    R.channel.show = (def.custom and def.chatType == "CHANNEL") and true or false
    menu.chBox:SetText(def.channelMatch or "")
    R.sound.show = true
    R.kit.show = true
    R.volume.show = true
    local key = SoundKey(id)
    menu.soundCB:SetChecked(SC.db.sound[key])
    menu.kitBtn:SetText(SoundText(SC.db.soundKit[key]))
    if menu.RefreshSoundVolume then menu.RefreshSoundVolume() end
    R.display.show = true
    menu.displayBtn:SetText("Display: " .. SC.DisplaySummary(id))
    SmallFont(menu.displayBtn)
    R.reply.show = true
    menu.replyCB:SetChecked(SC.ReplyEnabled(id))
    R.move.show = true
    R.actions.show = true
    menu.hideBtn:SetShown(not dyn)
    menu.actBtn:SetText(def.custom and "Remove tab" or (dyn and "Close tab" or "Reset tab"))
    menu.swatch:Update()

    LayoutRows(menu, {
        R.title, R.name, R.color, R.channel, R.sound, R.kit, R.volume, R.display, R.reply, R.move, R.actions,
    })
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", tab, "BOTTOMLEFT", 0, -2)
    menu:Show()
    SC.PopupShown(menu)
end


SC.RefreshOpenTabMenuSound = function()
    if menu and menu:IsShown() and menu.RefreshSoundVolume then menu.RefreshSoundVolume() end
end

---------------------------------------------------------------------
-- "New tab" window
---------------------------------------------------------------------
local newForm = { ctype = 1, color = { 1, 0.82, 0 } }

local function BuildNew()
    newMenu = MakeFrame("SmartChatNewTab", 256)
    local R = {}
    newMenu.rows = R

    R.title = { f = Row(newMenu, 20), show = true }
    local t = R.title.f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("LEFT", 0, 0)
    t:SetText("New tab")

    R.name = { f = Row(newMenu), show = true }
    Label(R.name.f, "Name", 0, -6, "GameFontHighlight")
    newMenu.nameBox = CreateFrame("EditBox", nil, R.name.f, "InputBoxTemplate")
    newMenu.nameBox:SetPoint("TOPLEFT", 62, -2)
    newMenu.nameBox:SetSize(142, 20)
    Help(R.name.f, 216, -4, "Enter the name that will appear on the new tab. You can rename it later from the tab's right-click menu.")
    newMenu.nameBox:SetAutoFocus(false)
    newMenu.nameBox:SetMaxLetters(14)

    R.type = { f = Row(newMenu, #SC.CHAT_TYPES * 22 + 18), show = true }
    Label(R.type.f, "Type (where what you type goes)", 0, -2, "GameFontHighlight")
    Help(R.type.f, 216, -2, "Choose the chat destination used when you type in this tab. A Channel tab targets a channel you have joined.")
    newMenu.radios = {}
    for i, t in ipairs(SC.CHAT_TYPES) do
        local cb = CreateFrame("CheckButton", nil, R.type.f, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", 0, -16 - (i - 1) * 22)
        local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        fs:SetText(t.label)
        cb:SetScript("OnClick", function()
            newForm.ctype = i
            SC.RefreshNewTypes()
        end)
        newMenu.radios[i] = cb
    end

    R.channel = { f = Row(newMenu), show = false }
    Label(R.channel.f, "Channel", 0, -6, "GameFontHighlight")
    newMenu.chBox = CreateFrame("EditBox", nil, R.channel.f, "InputBoxTemplate")
    newMenu.chBox:SetPoint("TOPLEFT", 62, -2)
    newMenu.chBox:SetSize(140, 20)
    Help(R.channel.f, 216, -4, "For a Channel tab, enter the name or number of a channel you have joined with /join.")
    newMenu.chBox:SetAutoFocus(false)

    R.color = { f = Row(newMenu), show = true }
    Label(R.color.f, "Color", 0, -6, "GameFontHighlight")
    newMenu.swatch = Swatch(R.color.f, 62, -3, function() return newForm.color end, function(c) newForm.color = c end)
    Help(R.color.f, 132, -4, "Choose the color used for the new tab.")

    R.create = { f = Row(newMenu), show = true }
    newMenu.status = nil
    R.status = { f = Row(newMenu, 34), show = true }
    newMenu.status = R.status.f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    newMenu.status:SetPoint("TOPLEFT", 0, 0)
    newMenu.status:SetWidth(236); newMenu.status:SetJustifyH("LEFT")

    Btn(R.create.f, "Create tab", 0, -2, 114, function()
        local ct = SC.CHAT_TYPES[newForm.ctype].type
        local ok, res = SC.AddCustomTab(newMenu.nameBox:GetText(), ct, newMenu.chBox:GetText(), newForm.color)
        if ok then
            newMenu:Hide()
            SC.Print("tab created: " .. Trim(newMenu.nameBox:GetText()))
        else
            newMenu.status:SetTextColor(1, 0.4, 0.4)
            newMenu.status:SetText(res)
        end
    end)
    local help = Btn(R.create.f, "?", 120, -2, 26, function() end)
    help:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Type \"Channel\" is for Trade, LookingForGroup or a channel you joined. Type part of its name (e.g. Trade) or its number. You must have joined it (/join name).\n\nAfter creating the tab, right-click it to change its name, color, sound or position.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    help:SetScript("OnLeave", GameTooltip_Hide)
end

function SC.RefreshNewTypes()
    if not newMenu then return end
    for i, cb in ipairs(newMenu.radios) do cb:SetChecked(i == newForm.ctype) end
    local R = newMenu.rows
    R.channel.show = (SC.CHAT_TYPES[newForm.ctype].type == "CHANNEL")
    LayoutRows(newMenu, { R.title, R.name, R.type, R.channel, R.color, R.create, R.status })
end

function SC.ShowNewTabMenu(anchor)
    if not newMenu then BuildNew() end
    if newMenu:IsShown() then newMenu:Hide() return end
    newMenu.nameBox:SetText("")
    newMenu.chBox:SetText("")
    newMenu.status:SetText("")
    newMenu.swatch:Update()
    SC.RefreshNewTypes()
    newMenu:ClearAllPoints()
    if anchor then newMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2) else newMenu:SetPoint("CENTER") end
    newMenu:Show()
    SC.PopupShown(newMenu)
end


---------------------------------------------------------------------
-- display window: which kinds of messages this tab shows
---------------------------------------------------------------------
local disp

local function DispCfg() return disp and disp.id and SC.GetDisplay(disp.id) end

local function SetEnabled(frame, on)
    pcall(function() frame:SetEnabled(on) end)
    frame:SetAlpha(on and 1 or 0.45)
end

local function RefreshDisplay()
    if not disp or not disp.id then return end
    local cfg = DispCfg()
    local all = (cfg == nil)
    disp.allCB:SetChecked(all)
    for key, cb in pairs(disp.catCB) do
        cb:SetChecked(all or (cfg.cats[key] and true or false))
        SetEnabled(cb, not all)
    end
    local R = disp.rows
    R.chan.show = (not all) and cfg.cats.channel and true or false
    disp.chanBox:SetText((cfg and cfg.chan) or "")
    local tab = SC.TabFrame(disp.id)
    local dyn = tab and tab.def.dynamic
    R.who.show = (not all) and dyn and true or false
    if R.who.show then
        disp.whoCB:SetChecked(cfg.whisperWith ~= nil)
        disp.whoText:SetText("Only the conversation with " .. SC.ShortName(tab.def.target))
    end
    LayoutRows(disp, { R.title, R.all, R.cats, R.chan, R.who, R.presets, R.presets2, R.hint })
end

local function BuildDisplay()
    disp = MakeFrame("SmartChatTabDisplay", 256)
    local R = {}
    disp.rows = R

    R.title = { f = Row(disp, 20), show = true }
    disp.titleText = R.title.f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    disp.titleText:SetPoint("LEFT", 0, 0)

    R.all = { f = Row(disp), show = true }
    disp.allCB = CreateFrame("CheckButton", nil, R.all.f, "UICheckButtonTemplate")
    disp.allCB:SetSize(24, 24); disp.allCB:SetPoint("TOPLEFT", -2, 0)
    Label(R.all.f, "Show everything", 24, -6, "GameFontHighlight")
    Help(R.all.f, 216, -4, "Show every message category in this tab. Turn this off to choose individual categories.")
    disp.allCB:SetScript("OnClick", function(self)
        if self:GetChecked() then SC.SetDisplay(disp.id, nil)
        else SC.SetDisplay(disp.id, { cats = SC.AllCategories() }) end
        RefreshDisplay()
    end)

    -- two columns of categories
    local perCol = math.ceil(#SC.CATEGORIES / 2)
    R.cats = { f = Row(disp, perCol * 22 + 2), show = true }
    Help(R.cats.f, 216, -2, "Select which message categories appear in this tab. These filters affect display only, not message routing.")
    disp.catCB = {}
    for i, c in ipairs(SC.CATEGORIES) do
        local col, row = math.floor((i - 1) / perCol), (i - 1) % perCol
        local cb = CreateFrame("CheckButton", nil, R.cats.f, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", col * 120, -row * 22)
        local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        fs:SetText(c.label)
        cb:SetScript("OnClick", function(self)
            local cfg = DispCfg()
            if not cfg then return end
            cfg.cats[c.key] = self:GetChecked() and true or nil
            SC.SetDisplay(disp.id, cfg)
            RefreshDisplay()
        end)
        disp.catCB[c.key] = cb
    end

    R.chan = { f = Row(disp), show = false }
    Label(R.chan.f, "Only channel", 0, -6, "GameFontHighlight")
    disp.chanBox = CreateFrame("EditBox", nil, R.chan.f, "InputBoxTemplate")
    disp.chanBox:SetPoint("TOPLEFT", 88, -2)
    disp.chanBox:SetSize(120, 20)
    Help(R.chan.f, 216, -4, "Limit this tab to a specific joined channel. Leave blank to show all selected channel messages.")
    disp.chanBox:SetAutoFocus(false)
    local function commitChan(self)
        local cfg = DispCfg()
        if cfg then
            local txt = Trim(self:GetText())
            cfg.chan = (txt ~= "") and txt or nil
            SC.SetDisplay(disp.id, cfg)
        end
        self:ClearFocus()
    end
    disp.chanBox:SetScript("OnEnterPressed", commitChan)
    disp.chanBox:SetScript("OnEditFocusLost", commitChan)

    R.who = { f = Row(disp), show = false }
    disp.whoCB = CreateFrame("CheckButton", nil, R.who.f, "UICheckButtonTemplate")
    disp.whoCB:SetSize(24, 24); disp.whoCB:SetPoint("TOPLEFT", -2, 0)
    disp.whoText = R.who.f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    disp.whoText:SetPoint("LEFT", disp.whoCB, "RIGHT", 2, 0)
    disp.whoText:SetWidth(184)
    disp.whoText:SetJustifyH("LEFT")
    Help(R.who.f, 216, -4, "For a dynamic Whisper tab, show only messages from the conversation currently assigned to it.")
    disp.whoCB:SetScript("OnClick", function(self)
        local cfg, tab = DispCfg(), SC.TabFrame(disp.id)
        if cfg and tab then
            cfg.whisperWith = self:GetChecked() and tab.def.target or nil
            SC.SetDisplay(disp.id, cfg)
        end
    end)

    R.presets = { f = Row(disp), show = true }
    disp.presetBtn = Btn(R.presets.f, "This chat + game messages", 0, -2, 210, function()
        SC.SetDisplay(disp.id, SC.PresetDisplay(disp.id))
        RefreshDisplay()
    end)
    Help(R.presets.f, 216, -4, "Apply a preset that includes this tab's chat and game/system messages.")
    R.presets2 = { f = Row(disp), show = true }
    disp.chatOnlyBtn = Btn(R.presets2.f, "This chat only", 0, -2, 98, function()
        SC.SetDisplay(disp.id, SC.PresetDisplay(disp.id, true))
        RefreshDisplay()
    end)
    disp.everyBtn = Btn(R.presets2.f, "Everything", 106, -2, 98, function()
        SC.SetDisplay(disp.id, nil)
        RefreshDisplay()
    end)

    Help(R.presets2.f, 216, -4, "Choose a ready-made preset: only this tab's chat, or everything including game messages.")
    R.hint = { f = Row(disp, 30), show = true }
    local hint = R.hint.f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 0, 0)
    hint:SetWidth(236); hint:SetJustifyH("LEFT")
    hint:SetText("Only changes what you SEE in this tab. Where your typing goes does not change. \"Game messages\" = system, loot, NPC speech, other.")
end

function SC.ShowDisplayMenu(tab)
    if not disp then BuildDisplay() end
    if disp:IsShown() and disp.id == tab.id then disp:Hide() return end
    disp.id = tab.id
    if tab.def.viewOnly then
        disp.presetBtn:SetText("All chat + game messages")
        disp.chatOnlyBtn:SetText("Chat messages only")
        disp.everyBtn:SetText("Everything")
    else
        disp.presetBtn:SetText("This chat + game messages")
        disp.chatOnlyBtn:SetText("This chat only")
        disp.everyBtn:SetText("Everything")
    end
    disp.titleText:SetText("Display: " .. tab.label)
    disp.titleText:SetTextColor(tab.def.color[1], tab.def.color[2], tab.def.color[3])
    RefreshDisplay()
    disp:ClearAllPoints()
    disp:SetPoint("TOPLEFT", tab, "BOTTOMLEFT", 0, -2)
    disp:Show()
    SC.PopupShown(disp)
end
