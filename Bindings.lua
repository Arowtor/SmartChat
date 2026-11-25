local ADDON, SC = ...

-- Forever uses the Mainline key-binding API. We create named click targets and
-- assign keys with SetBindingClick rather than relying on legacy Bindings.xml.
local bindingDefs = {
    { id = "say",             label = "Say chat",               frame = "SmartChatBind_Say",             suggestions = { "CTRL-S", "CTRL-ALT-S", "CTRL-SHIFT-S", "ALT-S" } },
    { id = "global",          label = "Global / all chat view", frame = "SmartChatBind_Global",          suggestions = { "CTRL-ALT-G", "CTRL-SHIFT-ALT-G", "ALT-G", "CTRL-SHIFT-G" } },
    { id = "party",           label = "Party chat",             frame = "SmartChatBind_Party",           suggestions = { "CTRL-P", "CTRL-ALT-P", "CTRL-SHIFT-P", "ALT-P" } },
    { id = "raid",            label = "Raid chat",              frame = "SmartChatBind_Raid",            suggestions = { "CTRL-R", "CTRL-ALT-R", "CTRL-SHIFT-R", "ALT-R" } },
    { id = "guild",           label = "Guild chat",             frame = "SmartChatBind_Guild",           suggestions = { "CTRL-G", "CTRL-ALT-G", "CTRL-SHIFT-G", "ALT-G" } },
    { id = "general",         label = "General chat",            frame = "SmartChatBind_General",         suggestions = { "CTRL-J", "CTRL-ALT-J", "CTRL-SHIFT-J", "ALT-J" } },
    { id = "whisper",         label = "Whisper chat",            frame = "SmartChatBind_Whisper",         suggestions = { "CTRL-W", "CTRL-ALT-W", "CTRL-SHIFT-W", "ALT-W" } },
    { id = "nextWhisper",     label = "Next Whisper tab",        frame = "SmartChatBind_NextWhisper",     suggestions = { "CTRL-ALT-N", "CTRL-SHIFT-N", "ALT-N", "CTRL-N" } },
    { id = "previousWhisper", label = "Previous Whisper tab",    frame = "SmartChatBind_PreviousWhisper", suggestions = { "CTRL-ALT-B", "CTRL-SHIFT-B", "ALT-B", "CTRL-B" } },
    { id = "channels",        label = "Open channel selector",   frame = "SmartChatBind_Channels",        suggestions = { "CTRL-ALT-C", "CTRL-SHIFT-C", "ALT-C", "CTRL-C" } },
    { id = "whisperList",     label = "Open Social Hub",   frame = "SmartChatBind_WhisperList",     suggestions = { "CTRL-ALT-L", "CTRL-SHIFT-L", "ALT-L", "CTRL-L" } },
    { id = "settings",        label = "Open SmartChat settings", frame = "SmartChatBind_Settings",       suggestions = { "CTRL-ALT-O", "CTRL-SHIFT-O", "ALT-O", "CTRL-O" } },
    { id = "copy",            label = "Open chat copy window",  frame = "SmartChatBind_Copy",            suggestions = { "CTRL-ALT-Y", "CTRL-SHIFT-Y", "ALT-Y", "CTRL-Y" } },
}

local byId, byCommand = {}, {}
SC.bindingActions = bindingDefs

local function CommandFor(def)
    return "CLICK " .. def.frame .. ":LeftButton"
end

local function DefForId(id)
    return byId[id]
end

local function ActionName(action)
    if not action or action == "" then return "Unassigned" end
    for _, def in ipairs(bindingDefs) do
        if action == CommandFor(def) then return "SmartChat: " .. def.label end
    end
    if type(action) == "string" and action:match("^CLICK ") then
        return "another AddOn button (" .. action .. ")"
    end
    return _G["BINDING_NAME_" .. action] or action
end

local function GetActionForKey(key)
    if type(GetBindingAction) ~= "function" then return nil end
    local ok, action = pcall(GetBindingAction, key, true)
    if ok then return action end
    return nil
end

local function GetLiveKeys(def)
    if type(GetBindingKey) ~= "function" then return {} end
    local ok, a, b, c, d = pcall(GetBindingKey, CommandFor(def))
    local keys = {}
    if ok then
        for _, key in ipairs({ a, b, c, d }) do
            if type(key) == "string" and key ~= "" then keys[#keys + 1] = key end
        end
    end
    return keys
end

-- Keep the last key SmartChat assigned in SavedVariables as well as asking
-- WoW for live bindings. GetBindingKey stops returning a key after another
-- action takes it over; the saved copy lets us detect and report that conflict.
local function GetKeys(def)
    local keys, seen = GetLiveKeys(def), {}
    for _, key in ipairs(keys) do seen[key] = true end
    local saved = SC.db and SC.db.shortcutKeys and SC.db.shortcutKeys[def.id]
    if type(saved) == "string" and saved ~= "" and not seen[saved] then
        keys[#keys + 1] = saved
    end
    return keys
end

local function BuildFreeSuggestionMap()
    local suggestions, reserved = {}, {}

    -- Reserve every live or previously assigned SmartChat key first, so two
    -- different rows never show the same free suggestion.
    for _, def in ipairs(bindingDefs) do
        for _, key in ipairs(GetKeys(def)) do reserved[key] = true end
    end

    for _, def in ipairs(bindingDefs) do
        local hasLive = #GetLiveKeys(def) > 0
        local saved = SC.db and SC.db.shortcutKeys and SC.db.shortcutKeys[def.id]
        if not hasLive and not (type(saved) == "string" and saved ~= "") then
            for _, candidate in ipairs(def.suggestions or {}) do
                local action = GetActionForKey(candidate)
                if not reserved[candidate] and (not action or action == "") then
                    suggestions[def.id] = candidate
                    reserved[candidate] = true
                    break
                end
            end
        end
    end
    return suggestions
end

local function KeyLabel(key)
    if not key or key == "" then return "" end
    local parts = {}
    for part in key:gmatch("[^%-]+") do
        if part == "CTRL" then part = "Ctrl"
        elseif part == "ALT" then part = "Alt"
        elseif part == "SHIFT" then part = "Shift"
        elseif part == "META" then part = "Meta"
        else part = part:sub(1, 1):upper() .. part:sub(2):lower() end
        parts[#parts + 1] = part
    end
    return table.concat(parts, " + ")
end

local function StoreKey(id, key)
    if not SC.db then return end
    SC.db.shortcutKeys = SC.db.shortcutKeys or {}
    SC.db.shortcutKeys[id] = key
end

local function SaveCurrentBindings()
    if type(SaveBindings) ~= "function" then return false end
    local set = type(GetCurrentBindingSet) == "function" and GetCurrentBindingSet() or 1
    local ok = pcall(SaveBindings, set or 1)
    return ok
end

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local function EnsureBindingButtons()
    for _, def in ipairs(bindingDefs) do
        local button = _G[def.frame]
        if not button then
            button = CreateFrame("Button", def.frame, UIParent)
            button:SetSize(1, 1)
            button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -12, -12)
            button:SetAlpha(0)
            button:SetFrameStrata("LOW")
            button:RegisterForClicks("LeftButtonUp")
            button:Show()
            button:SetScript("OnClick", function()
                if SC.RunBindingAction then SC.RunBindingAction(def.id) end
            end)
        end
        byId[def.id] = def
        byCommand[CommandFor(def)] = def
    end
end

EnsureBindingButtons()

local function ApplyBinding(id, key, allowReplace)
    local def = DefForId(id)
    if not def then return false, "Unknown SmartChat shortcut." end
    if InCombat() then return false, "Key bindings cannot be changed during combat. Try again after combat." end
    if type(SetBindingClick) ~= "function" or type(GetBindingAction) ~= "function" then
        return false, "This client does not expose the required key-binding API." 
    end

    local command = CommandFor(def)
    local currentAction = GetActionForKey(key)
    if currentAction and currentAction ~= "" and currentAction ~= command and not allowReplace then
        return false, "occupied", currentAction
    end

    -- Keep the binding for this SmartChat action to one key. Preserve it if the
    -- requested change fails for any reason.
    local oldKeys = GetLiveKeys(def)
    for _, oldKey in ipairs(oldKeys) do
        if oldKey ~= key and type(SetBinding) == "function" then
            pcall(SetBinding, oldKey)
        end
    end

    local ok, result = pcall(SetBindingClick, key, def.frame, "LeftButton")
    if not ok or not result then
        for _, oldKey in ipairs(oldKeys) do
            pcall(SetBindingClick, oldKey, def.frame, "LeftButton")
        end
        SaveCurrentBindings()
        return false, "The game rejected that key combination. Your previous shortcut was restored."
    end

    SaveCurrentBindings()
    StoreKey(id, key)
    return true
end

function SC.AssignSmartBinding(id, key, allowReplace)
    return ApplyBinding(id, key, allowReplace)
end

function SC.ClearSmartBinding(id)
    local def = DefForId(id)
    if not def then return false, "Unknown SmartChat shortcut." end
    if InCombat() then return false, "Key bindings cannot be changed during combat. Try again after combat." end
    if type(SetBinding) ~= "function" then return false, "This client does not expose SetBinding." end
    for _, key in ipairs(GetLiveKeys(def)) do
        if GetActionForKey(key) == CommandFor(def) then pcall(SetBinding, key) end
    end
    SaveCurrentBindings()
    StoreKey(id, nil)
    return true
end

function SC.CheckBindings()
    SC.Print("checking suggested shortcuts against this character's current key map:")
    local suggestions = BuildFreeSuggestionMap()
    for _, def in ipairs(bindingDefs) do
        local candidate = suggestions[def.id]
        if candidate then
            print("  |cff55ff55FREE|r  " .. KeyLabel(candidate) .. "  -> " .. def.label)
        else
            local saved = SC.db and SC.db.shortcutKeys and SC.db.shortcutKeys[def.id]
            local live = GetLiveKeys(def)
            if #live > 0 then
                print("  |cff55ff55SMARTCHAT|r  " .. KeyLabel(live[1]) .. "  -> " .. def.label .. " (already assigned)")
            elseif saved then
                local action = GetActionForKey(saved)
                print("  |cffff5555CONFLICT|r  " .. KeyLabel(saved) .. "  -> " .. ActionName(action) .. " (previous " .. def.label .. " key)")
            else
                print("  |cff888888NO FREE SUGGESTION|r  -> " .. def.label)
            end
        end
    end
    local conflicts = SC.CheckAssignedBindingOverrides(false)
    if conflicts > 0 then
        SC.Print(conflicts .. " assigned SmartChat shortcut(s) are being intercepted by another binding.")
    else
        SC.Print("No assigned SmartChat shortcut is currently intercepted by another binding.")
    end
    SC.ListBindings()
    SC.Print("Click a key box in /sc settings > Keyboard shortcuts, or use the keyboard dock icon. Only free suggestions are shown in gray. Existing keys are never replaced without confirmation.")
end
function SC.CheckAssignedBindingOverrides(silent)
    local conflicts = 0
    for _, def in ipairs(bindingDefs) do
        for _, key in ipairs(GetKeys(def)) do
            local action = GetActionForKey(key)
            local expected = CommandFor(def)
            if action ~= expected then
                conflicts = conflicts + 1
                if not silent then
                    local detail = (not action or action == "") and "is no longer assigned" or ("is now assigned to " .. ActionName(action))
                    print("|cffff5555SmartChat shortcut warning:|r " .. key .. " " .. detail .. " (expected " .. def.label .. ").")
                end
            end
        end
    end
    if conflicts > 0 and not silent then
        SC.Print(conflicts .. " shortcut override conflict(s) detected. Review the other AddOn's override or remove the conflicting binding.")
    end
    return conflicts
end

function SC.ListBindings()
    SC.Print("currently assigned SmartChat shortcuts:")
    for _, def in ipairs(bindingDefs) do
        local keys = GetKeys(def)
        local shown = {}
        for _, key in ipairs(keys) do
            local name = (GetBindingText and GetBindingText(key, "KEY_", 1)) or key
            local action = GetActionForKey(key)
            if action ~= CommandFor(def) then name = "|cffff5555" .. name .. " (conflict)|r" end
            shown[#shown + 1] = name
        end
        print("  " .. def.label .. ": " .. (#shown > 0 and table.concat(shown, ", ") or "|cff888888not bound|r"))
    end
end

---------------------------------------------------------------------
-- The in-AddOn shortcut editor. Mainline 12.x no longer relies on legacy
-- <Binding> XML handlers; assignments are done through SetBindingClick.
---------------------------------------------------------------------
local panel
local captureAction, captureRow
local rowRecords = {}

local function CurrentKeyFor(def)
    local live = GetLiveKeys(def)
    if live[1] then return live[1], true end
    local saved = SC.db and SC.db.shortcutKeys and SC.db.shortcutKeys[def.id]
    if type(saved) == "string" and saved ~= "" then return saved, false end
    return nil, false
end

local function RefreshBindingRows()
    local suggestions = BuildFreeSuggestionMap()
    for _, row in ipairs(rowRecords) do
        if captureRow ~= row then
            local key, live = CurrentKeyFor(row.def)
            if key then
                row.keyBox:SetText(KeyLabel(key))
                row.placeholder:Hide()
                local action = GetActionForKey(key)
                if live and action == CommandFor(row.def) then
                    row.status:SetText("Assigned")
                    row.status:SetTextColor(0.35, 1, 0.45)
                    row.keyBox:SetTextColor(1, 1, 1)
                else
                    row.status:SetText("Conflict")
                    row.status:SetTextColor(1, 0.30, 0.30)
                    row.keyBox:SetTextColor(1, 0.35, 0.35)
                end
            else
                row.keyBox:SetText("")
                row.keyBox:SetTextColor(1, 1, 1)
                local suggested = suggestions[row.def.id]
                if suggested then
                    row.placeholder:SetText(KeyLabel(suggested))
                    row.status:SetText("Free suggestion")
                    row.status:SetTextColor(0.45, 0.9, 0.5)
                else
                    row.placeholder:SetText("Click to assign")
                    row.status:SetText("No free suggestion")
                    row.status:SetTextColor(0.65, 0.65, 0.65)
                end
                row.placeholder:Show()
            end
        end
    end
end

local function CloseCapture()
    local row = captureRow
    captureAction, captureRow = nil, nil
    if row and row.keyBox then
        row.keyBox:EnableKeyboard(false)
        if row.keyBox.SetPropagateKeyboardInput then
            pcall(row.keyBox.SetPropagateKeyboardInput, row.keyBox, true)
        end
        row.keyBox:ClearFocus()
    end
end

local function AskToReplace(id, key, action)
    if not StaticPopupDialogs then
        SC.Print(key .. " is already used by " .. ActionName(action) .. ". No change made.")
        RefreshBindingRows()
        return
    end
    StaticPopupDialogs.SMARTCHAT_REPLACE_KEY = StaticPopupDialogs.SMARTCHAT_REPLACE_KEY or {
        text = "The key %s is already assigned to:\n%s\n\nReplace it with this SmartChat shortcut?",
        button1 = ACCEPT,
        button2 = CANCEL,
        OnAccept = function(dialog)
            local data = dialog.data
            if data then
                local ok, why = ApplyBinding(data.id, data.key, true)
                if ok then
                    SC.Print("Shortcut assigned: " .. data.key .. " -> " .. DefForId(data.id).label)
                else
                    SC.Print(why or "Could not assign that shortcut.")
                end
                RefreshBindingRows()
            end
        end,
        OnCancel = function() RefreshBindingRows() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("SMARTCHAT_REPLACE_KEY", KeyLabel(key), ActionName(action), { id = id, key = key })
end

local function SubmitCapturedKey(id, key)
    local ok, reason, action = ApplyBinding(id, key, false)
    if ok then
        SC.Print("Shortcut assigned: " .. KeyLabel(key) .. " -> " .. DefForId(id).label)
        RefreshBindingRows()
    elseif reason == "occupied" then
        AskToReplace(id, key, action)
    else
        SC.Print(reason or "Could not assign that shortcut.")
        RefreshBindingRows()
    end
end

local function IsModifierKey(key)
    key = (key or ""):upper()
    return key == "LCTRL" or key == "RCTRL" or key == "CTRL"
        or key == "LSHIFT" or key == "RSHIFT" or key == "SHIFT"
        or key == "LALT" or key == "RALT" or key == "ALT"
        or key == "LMETA" or key == "RMETA" or key == "META"
end

local function ComposeChord(key)
    key = (key or ""):upper()
    if key == "" or key == "UNKNOWN" then return nil end
    local parts = {}
    if IsAltKeyDown and IsAltKeyDown() then parts[#parts + 1] = "ALT" end
    if IsControlKeyDown and IsControlKeyDown() then parts[#parts + 1] = "CTRL" end
    if IsShiftKeyDown and IsShiftKeyDown() then parts[#parts + 1] = "SHIFT" end
    if IsMetaKeyDown and IsMetaKeyDown() then parts[#parts + 1] = "META" end
    parts[#parts + 1] = key
    return table.concat(parts, "-")
end

local function StartCapture(def, row)
    if InCombat() then
        SC.Print("You can only change shortcuts out of combat.")
        return
    end
    if captureRow and captureRow ~= row then CloseCapture() end
    captureAction, captureRow = def, row
    row.placeholder:Hide()
    row.keyBox:SetText("Press keys... (Esc cancels)")
    row.keyBox:SetTextColor(1, 0.82, 0.25)
    row.keyBox:EnableKeyboard(true)
    if row.keyBox.SetPropagateKeyboardInput then pcall(row.keyBox.SetPropagateKeyboardInput, row.keyBox, false) end
    row.keyBox:SetFocus()
end

local function BuildPanel()
    panel = CreateFrame("Frame", "SmartChatBindingsPanel", UIParent, "BackdropTemplate")
    panel:SetSize(590, 560)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    panel:SetToplevel(true)
    panel:SetScript("OnShow", function(self)
        if SC.RaiseWindow then SC.RaiseWindow(self, "FULLSCREEN_DIALOG") end
    end)
    if SC.RegisterWindow then
        SC.RegisterWindow(panel, { 0.035, 0.040, 0.055, 1 }, { 0.55, 0.55, 0.60, 1 })
    end
    tinsert(UISpecialFrames, "SmartChatBindingsPanel")

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -18)
    title:SetText("SmartChat shortcuts")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local help = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 22, -43)
    help:SetWidth(545)
    help:SetJustifyH("LEFT")
    help:SetText("Each action has its own key box. Click a box and press the combination you want. A free suggestion appears in gray. Occupied keys are identified and require your confirmation before replacement. Changes are disabled during combat.")

    local headers = {
        { text = "Action", x = 22 },
        { text = "Shortcut key (click to record)", x = 190 },
        { text = "Status", x = 365 },
    }
    for _, h in ipairs(headers) do
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", h.x, -88)
        fs:SetText(h.text)
    end

    rowRecords = {}
    for i, def in ipairs(bindingDefs) do
        local y = -108 - (i - 1) * 28
        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", 22, y)
        label:SetWidth(128)
        label:SetJustifyH("LEFT")
        label:SetText(def.label)

        local helpButton = CreateFrame("Button", nil, panel)
        helpButton:SetSize(14, 14)
        helpButton:SetPoint("LEFT", label, "RIGHT", 3, 0)
        local helpText = helpButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        helpText:SetPoint("CENTER")
        helpText:SetText("?")
        helpText:SetTextColor(0.4, 0.8, 1)
        helpButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(def.label, 1, 1, 1)
            GameTooltip:AddLine("Assign the key combination that triggers this action. Click the adjacent key box and press the combination you want. SmartChat asks before replacing an existing key binding. Clear removes only this SmartChat shortcut.", 0.8, 0.85, 1, true)
            GameTooltip:Show()
        end)
        helpButton:SetScript("OnLeave", GameTooltip_Hide)

        local keyBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        keyBox:SetSize(156, 21)
        keyBox:SetPoint("TOPLEFT", 190, y + 3)
        keyBox:SetAutoFocus(false)
        keyBox:SetMaxLetters(36)
        keyBox:SetTextInsets(7, 6, 0, 0)
        keyBox:EnableKeyboard(false)

        local placeholder = keyBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        placeholder:SetPoint("LEFT", keyBox, "LEFT", 8, 0)
        placeholder:SetPoint("RIGHT", keyBox, "RIGHT", -5, 0)
        placeholder:SetJustifyH("LEFT")
        placeholder:SetTextColor(0.52, 0.52, 0.52)
        placeholder:EnableMouse(false)

        local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status:SetPoint("LEFT", keyBox, "RIGHT", 12, 0)
        status:SetWidth(115)
        status:SetJustifyH("LEFT")

        local clearBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        clearBtn:SetSize(52, 21)
        clearBtn:SetPoint("TOPLEFT", 520, y + 3)
        clearBtn:SetText("Clear")
        clearBtn:SetScript("OnClick", function()
            local ok, why = SC.ClearSmartBinding(def.id)
            if ok then SC.Print("Shortcut cleared: " .. def.label)
            else SC.Print(why or "Could not clear that shortcut.") end
            RefreshBindingRows()
        end)

        local row = { def = def, keyBox = keyBox, placeholder = placeholder, status = status, clear = clearBtn }
        rowRecords[#rowRecords + 1] = row

        keyBox:SetScript("OnMouseDown", function()
            StartCapture(def, row)
        end)
        keyBox:SetScript("OnKeyDown", function(self, key)
            if captureRow ~= row or captureAction ~= def then return end
            key = (key or ""):upper()
            if key == "ESCAPE" then
                CloseCapture()
                RefreshBindingRows()
                return
            end
            if IsModifierKey(key) then return end
            local chord = ComposeChord(key)
            CloseCapture()
            if chord then SubmitCapturedKey(def.id, chord) else RefreshBindingRows() end
        end)
        keyBox:SetScript("OnEditFocusLost", function()
            if captureRow == row then
                CloseCapture()
                RefreshBindingRows()
            end
        end)
        keyBox:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Click here, then press a key combination. Escape cancels.")
            GameTooltip:Show()
        end)
        keyBox:SetScript("OnLeave", GameTooltip_Hide)
    end

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 22, 17)
    hint:SetWidth(545)
    hint:SetJustifyH("LEFT")
    hint:SetText("Gray text = a currently free suggested key. Red status = the saved key is now in conflict. Clear removes this SmartChat shortcut.")

    panel:SetScript("OnShow", RefreshBindingRows)
    panel:SetScript("OnHide", function() CloseCapture(); RefreshBindingRows() end)
    RefreshBindingRows()
end

function SC.ShowBindingsPanel()
    if not panel then BuildPanel() end
    RefreshBindingRows()
    panel:Show()
    if SC.RaiseWindow then SC.RaiseWindow(panel, "FULLSCREEN_DIALOG") end
end

function SC.RunBindingAction(action)
    if not action then return end
    local tabIds = {
        say = "say", global = "global", party = "party", raid = "raid", guild = "guild",
        general = "general", whisper = "whisper",
    }
    if tabIds[action] then
        local id = tabIds[action]
        if SC._tabs and SC._tabs[id] then
            if id == "whisper" and SC.active ~= "whisper" and SC.OpenWhisperTab
                and (SC.selectedWhisper or SC.lastWhisper) then
                SC.OpenWhisperTab(SC.selectedWhisper or SC.lastWhisper)
            else
                SC.SetActive(id, false)
            end
        else
            SC.Print("That tab is hidden or unavailable. Restore it in SmartChat settings.")
        end
    elseif action == "nextWhisper" or action == "previousWhisper" then
        if SC.CycleWhisperTarget then
            SC.CycleWhisperTarget(action == "nextWhisper" and 1 or -1)
        elseif SC.ShowWhisperList then
            SC.ShowWhisperList()
        end
    elseif action == "channels" then
        if SC.ShowChannelList then SC.ShowChannelList() end
    elseif action == "whisperList" then
        if SC.ShowWhisperList then SC.ShowWhisperList() end
    elseif action == "settings" then
        if SC.ToggleSettings then SC.ToggleSettings() end
    elseif action == "copy" then
        if SC.ShowCopy then SC.ShowCopy() end
    end
end

-- Create named click targets before any key is assigned; key bindings are stored
-- by WoW itself and restored by its binding system on the next login.


---------------------------------------------------------------------
-- Watch the game's binding map. This catches a later key-map change (or
-- another AddOn overriding one of our keys) and warns without changing it.
---------------------------------------------------------------------
local bindingMonitor = CreateFrame("Frame")
local function CheckBindingsAfterUpdate(showWarning)
    local function run()
        if SC.CheckAssignedBindingOverrides then
            SC.CheckAssignedBindingOverrides(not showWarning)
        end
        if panel and panel.IsShown and panel:IsShown() then RefreshBindingRows() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.25, run) else run() end
end
pcall(bindingMonitor.RegisterEvent, bindingMonitor, "PLAYER_LOGIN")
pcall(bindingMonitor.RegisterEvent, bindingMonitor, "UPDATE_BINDINGS")
bindingMonitor:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" and SC.db then
        SC.db.shortcutKeys = SC.db.shortcutKeys or {}
        for _, def in ipairs(bindingDefs) do
            if not SC.db.shortcutKeys[def.id] then
                local live = GetLiveKeys(def)
                if live[1] then StoreKey(def.id, live[1]) end
            end
        end
    end
    -- Don't announce on every normal load. Only report a conflict if one exists.
    CheckBindingsAfterUpdate(event == "UPDATE_BINDINGS")
end)
