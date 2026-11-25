local ADDON, SC = ...

-- My Groups, reusable Group Templates and user-initiated Party invitations.
-- This is a Social Hub convenience feature, not a Party/Raid management UI.

local MAX_TEMPLATES = 20
local MAX_TEMPLATE_MEMBERS = 100
local templateFrame
local templateMenu
local templateRows = {}

local function Social()
    SC.db.social = SC.db.social or {}
    local s = SC.db.social
    s.groups = s.groups or {}
    s.groupOrder = s.groupOrder or {}
    s.groupTemplates = s.groupTemplates or {}
    s.groupTemplateOrder = s.groupTemplateOrder or {}
    return s
end

local function NameKey(name)
    return SC.NameKey and SC.NameKey(name) or tostring(name or ""):lower()
end

local function CleanName(value, maxLength)
    if type(value) ~= "string" then return "" end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    maxLength = maxLength or 24
    if #value > maxLength then value = value:sub(1, maxLength) end
    return value
end

local function CopyMembers(source)
    local result, seen = {}, {}
    if type(source) ~= "table" then return result end
    for key, value in pairs(source) do
        local name = type(value) == "string" and value or (type(key) == "string" and value and key or nil)
        if type(name) == "string" and name ~= "" then
            local normalized = NameKey(name)
            if normalized ~= "" and not seen[normalized] and #result < MAX_TEMPLATE_MEMBERS then
                seen[normalized] = true
                result[normalized] = name
            end
        end
    end
    return result
end

local function CountMembers(members)
    local count = 0
    for _, name in pairs(members or {}) do if type(name) == "string" and name ~= "" then count = count + 1 end end
    return count
end

local function FindTemplateName(s, wanted)
    local target = tostring(wanted or ""):lower()
    for _, name in ipairs(s.groupTemplateOrder) do
        if tostring(name):lower() == target then return name end
    end
end

function SC.GetContactGroupTemplateNames()
    local s = Social()
    local result = {}
    for _, name in ipairs(s.groupTemplateOrder) do
        if type(s.groupTemplates[name]) == "table" then result[#result + 1] = name end
    end
    return result
end

function SC.GetContactGroupTemplate(name)
    local s = Social()
    local templateName = FindTemplateName(s, name)
    local template = templateName and s.groupTemplates[templateName]
    if type(template) ~= "table" then return nil end
    return {
        name = templateName,
        members = CopyMembers(template.members),
        source = template.source,
        created = tonumber(template.created) or 0,
        updated = tonumber(template.updated) or 0,
    }
end

function SC.SaveContactGroupAsTemplate(templateName, groupName)
    local s = Social()
    templateName = CleanName(templateName, 24)
    if templateName == "" then return false, "Template name cannot be empty." end
    if type(groupName) ~= "string" or type(s.groups[groupName]) ~= "table" then return false, "Select an existing My Group first." end
    if FindTemplateName(s, templateName) then return false, "A template with that name already exists." end
    if #s.groupTemplateOrder >= MAX_TEMPLATES then return false, "The 20-template limit has been reached." end
    local members = CopyMembers(s.groups[groupName])
    if CountMembers(members) == 0 then return false, "The selected group is empty." end
    local now = time()
    s.groupTemplates[templateName] = { members = members, source = groupName, created = now, updated = now }
    s.groupTemplateOrder[#s.groupTemplateOrder + 1] = templateName
    return true, CountMembers(members)
end

function SC.SaveContactSelectionAsTemplate(templateName, names)
    local s = Social()
    templateName = CleanName(templateName, 24)
    if templateName == "" then return false, "Template name cannot be empty." end
    if FindTemplateName(s, templateName) then return false, "A template with that name already exists." end
    if #s.groupTemplateOrder >= MAX_TEMPLATES then return false, "The 20-template limit has been reached." end
    local members = CopyMembers(names)
    if CountMembers(members) == 0 then return false, "Select at least one contact." end
    local now = time()
    s.groupTemplates[templateName] = { members = members, source = "Selection", created = now, updated = now }
    s.groupTemplateOrder[#s.groupTemplateOrder + 1] = templateName
    return true, CountMembers(members)
end

function SC.UpdateContactGroupTemplateFromGroup(templateName, groupName)
    local s = Social()
    local actualName = FindTemplateName(s, templateName)
    local template = actualName and s.groupTemplates[actualName]
    if type(template) ~= "table" then return false, "The selected template no longer exists." end
    if type(s.groups[groupName]) ~= "table" then return false, "Select an existing My Group first." end
    local members = CopyMembers(s.groups[groupName])
    if CountMembers(members) == 0 then return false, "The selected group is empty." end
    template.members = members
    template.source = groupName
    template.updated = time()
    return true, CountMembers(members)
end

function SC.CreateContactGroupFromTemplate(templateName, newGroupName)
    local s = Social()
    local actualName = FindTemplateName(s, templateName)
    local template = actualName and s.groupTemplates[actualName]
    if type(template) ~= "table" then return false, "The selected template no longer exists." end
    newGroupName = CleanName(newGroupName, 24)
    if newGroupName == "" then return false, "Group name cannot be empty." end
    if SC.CreateContactGroup then
        if not SC.CreateContactGroup(newGroupName) then return false, "The group name already exists or the 30-group limit was reached." end
    else
        if s.groups[newGroupName] or #s.groupOrder >= 30 then return false, "The group already exists or the 30-group limit was reached." end
        s.groups[newGroupName] = {}
        s.groupOrder[#s.groupOrder + 1] = newGroupName
    end
    s.groups[newGroupName] = CopyMembers(template.members)
    if SC.RefreshWhisperInbox then SC.RefreshWhisperInbox() end
    return true, CountMembers(s.groups[newGroupName])
end

function SC.DeleteContactGroupTemplate(templateName)
    local s = Social()
    local actualName = FindTemplateName(s, templateName)
    if not actualName then return false end
    if SC.CreateLocalSocialRestorePoint then
        local ok, err = SC.CreateLocalSocialRestorePoint("Before deleting group template " .. actualName)
        if not ok then return false, err or "Could not create a local recovery point." end
    end
    s.groupTemplates[actualName] = nil
    for i = #s.groupTemplateOrder, 1, -1 do
        if s.groupTemplateOrder[i] == actualName then table.remove(s.groupTemplateOrder, i) end
    end
    return true
end

local function CurrentGroupMembers(groupName)
    local s = Social()
    local group = s.groups[groupName]
    if type(group) ~= "table" then return {} end
    return CopyMembers(group)
end

local function CurrentGroupContains(name)
    local key = NameKey(name)
    local total = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if IsInRaid and IsInRaid() then
        for i = 1, math.min(total, 40) do
            local unit = "raid" .. i
            local display = SC.PlayerDisplayName and SC.PlayerDisplayName(unit) or (UnitName and UnitName(unit))
            if display and NameKey(display) == key then return true end
        end
    elseif IsInGroup and IsInGroup() then
        for i = 1, math.min(math.max(total - 1, 0), 4) do
            local unit = "party" .. i
            local display = SC.PlayerDisplayName and SC.PlayerDisplayName(unit) or (UnitName and UnitName(unit))
            if display and NameKey(display) == key then return true end
        end
    end
    local playerName = UnitName and UnitName("player")
    return playerName and NameKey(playerName) == key or false
end

function SC.InviteContactsToParty(names)
    if type(names) ~= "table" or #names == 0 then return 0, 0, 0, "No contacts were selected." end
    if IsInRaid and IsInRaid() then
        return 0, #names, 0, "You are currently in a raid. Use the game's raid tools for invitations."
    end

    local partyAPI = C_PartyInfo
    local invite = (partyAPI and partyAPI.InviteUnit) or InviteUnit or InviteByName
    if type(invite) ~= "function" then return 0, #names, 0, "The Party invite API is unavailable on this client." end
    if partyAPI and type(partyAPI.CanInvite) == "function" then
        local okCan, canInvite = pcall(partyAPI.CanInvite)
        if okCan and canInvite == false then return 0, #names, 0, "The game currently does not allow you to invite players." end
    end

    local currentMembers = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if currentMembers < 1 then currentMembers = 1 end
    local slots = math.max(0, 5 - currentMembers)
    if slots == 0 then return 0, #names, 0, "Your Party is full. SmartChat does not manage Raid invitations." end

    local unique, invited, skipped, failed = {}, 0, 0, 0
    local failures = {}
    for _, rawName in ipairs(names) do
        local name = type(rawName) == "string" and rawName or nil
        local key = name and NameKey(name) or ""
        if not name or name == "" or key == "" or unique[key] then
            skipped = skipped + 1
        else
            unique[key] = true
            if CurrentGroupContains(name) then
                skipped = skipped + 1
            else
                local info = SC.GetContactInfo and SC.GetContactInfo(name) or {}
                if info.accountOnly then
                    skipped = skipped + 1
                elseif info.status == "OFFLINE" then
                    skipped = skipped + 1
                elseif invited >= slots then
                    skipped = skipped + 1
                else
                    local ok, result = pcall(invite, name)
                    if ok and result ~= false then
                        invited = invited + 1
                    else
                        failed = failed + 1
                        failures[#failures + 1] = name .. (not ok and (": " .. tostring(result)) or "")
                    end
                end
            end
        end
    end
    local detail = string.format("Party invitations sent: %d · skipped: %d · failed: %d", invited, skipped, failed)
    if #failures > 0 then detail = detail .. " · Check names or invite restrictions for: " .. table.concat(failures, ", ") end
    if SC.Print then SC.Print(detail) end
    return invited, skipped, failed, detail
end

local function ShowInviteConfirmation(names, label)
    if type(names) ~= "table" or #names == 0 or not StaticPopupDialogs then return end
    local copy = {}
    for _, name in ipairs(names) do if type(name) == "string" and name ~= "" then copy[#copy + 1] = name end end
    if #copy == 0 then return end
    StaticPopupDialogs.SMARTCHAT_INVITE_CONTACTS_TO_PARTY = StaticPopupDialogs.SMARTCHAT_INVITE_CONTACTS_TO_PARTY or {
        text = "Send Party invitations to character contacts in %s? SmartChat skips offline, account-only, already grouped and duplicate contacts. Contacts with unknown presence may still be attempted. A normal Party can contain up to five players.",
        button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(_, data)
            SC.InviteContactsToParty(data.names)
        end,
    }
    StaticPopup_Show("SMARTCHAT_INVITE_CONTACTS_TO_PARTY", tostring(label or "this selection"), nil, { names = copy })
end

function SC.PromptInviteContactGroup(groupName)
    local members = CurrentGroupMembers(groupName)
    local names = {}
    for _, name in pairs(members) do names[#names + 1] = name end
    table.sort(names, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
    ShowInviteConfirmation(names, groupName)
end

function SC.PromptInviteSelectedContacts(names)
    ShowInviteConfirmation(names, "your selected contacts")
end

local function PromptTemplateName(text, onAccept, data, successPrefix)
    if not StaticPopupDialogs then return end
    StaticPopupDialogs.SMARTCHAT_TEMPLATE_NAME = StaticPopupDialogs.SMARTCHAT_TEMPLATE_NAME or {
        text = "%s", button1 = ACCEPT, button2 = CANCEL,
        hasEditBox = true, maxLetters = 24, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(self, userData)
            local edit = self.EditBox or _G[self:GetName() .. "EditBox"]
            local value = edit and edit:GetText() or ""
            local ok, result = onAccept(value, userData)
            if ok then
                if SC.Print then SC.Print((successPrefix or "Group template saved: ") .. CleanName(value, 24) .. " (" .. tostring(result or 0) .. " members).") end
                if templateFrame and templateFrame:IsShown() then templateFrame:Refresh() end
            elseif SC.Print then
                SC.Print(tostring(result or "Could not save group template."))
            end
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            if parent.button1 then parent.button1:Click() end
        end,
    }
    local dialog = StaticPopup_Show("SMARTCHAT_TEMPLATE_NAME", text, nil, data)
    if dialog then
        local edit = dialog.EditBox or _G[dialog:GetName() .. "EditBox"]
        if edit then edit:SetText(""); edit:SetFocus() end
    end
end

function SC.PromptSaveContactGroupTemplate(groupName)
    if type(groupName) ~= "string" or groupName == "" then return end
    PromptTemplateName("Save My Group as a reusable template:", function(value, sourceGroup)
        return SC.SaveContactGroupAsTemplate(value, sourceGroup)
    end, groupName, "Group template saved: ")
end

function SC.PromptSaveSelectedContactsAsTemplate(names)
    if type(names) ~= "table" or #names == 0 then return end
    local copy = {}
    for _, name in ipairs(names) do if type(name) == "string" and name ~= "" then copy[#copy + 1] = name end end
    PromptTemplateName("Save selected contacts as a reusable group template:", function(value, selected)
        return SC.SaveContactSelectionAsTemplate(value, selected)
    end, copy, "Group template saved: ")
end

function SC.PromptCreateGroupFromTemplate(templateName)
    local template = SC.GetContactGroupTemplate(templateName)
    if not template then return end
    PromptTemplateName("Create a new My Group from template " .. template.name .. ":", function(value, sourceTemplate)
        return SC.CreateContactGroupFromTemplate(sourceTemplate, value)
    end, template.name, "My Group created: ")
end

function SC.PromptInviteContactTemplate(templateName)
    local template = SC.GetContactGroupTemplate(templateName)
    if not template then return end
    local names = {}
    for _, name in pairs(template.members) do names[#names + 1] = name end
    table.sort(names, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
    ShowInviteConfirmation(names, "template " .. template.name)
end

function SC.PromptUpdateTemplateFromGroup(templateName, groupName)
    if not templateName or not groupName then return end
    if not StaticPopupDialogs then return end
    StaticPopupDialogs.SMARTCHAT_UPDATE_GROUP_TEMPLATE = StaticPopupDialogs.SMARTCHAT_UPDATE_GROUP_TEMPLATE or {
        text = 'Replace the saved members in template "%s" with the current members of My Group "%s"?',
        button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(_, data)
            if SC.CreateLocalSocialRestorePoint then
                local saved, saveError = SC.CreateLocalSocialRestorePoint("Before updating group template " .. tostring(data.templateName))
                if not saved then if SC.Print then SC.Print(tostring(saveError or "Could not create a local recovery point.")) end; return end
            end
            local ok, result = SC.UpdateContactGroupTemplateFromGroup(data.templateName, data.groupName)
            if ok then
                if SC.Print then SC.Print("Group template updated with " .. tostring(result) .. " members.") end
                if templateFrame and templateFrame:IsShown() then templateFrame:Refresh() end
            elseif SC.Print then SC.Print(tostring(result or "Could not update template.")) end
        end,
    }
    StaticPopup_Show("SMARTCHAT_UPDATE_GROUP_TEMPLATE", templateName, groupName, { templateName = templateName, groupName = groupName })
end

function SC.PromptDeleteContactGroupTemplate(templateName)
    if not templateName or not StaticPopupDialogs then return end
    StaticPopupDialogs.SMARTCHAT_DELETE_GROUP_TEMPLATE = StaticPopupDialogs.SMARTCHAT_DELETE_GROUP_TEMPLATE or {
        text = 'Delete saved group template "%s"? Existing My Groups created from it will not change.',
        button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(_, data)
            local ok, err = SC.DeleteContactGroupTemplate(data)
            if ok then
                if SC.Print then SC.Print("Group template deleted. A local recovery point was saved.") end
                if templateFrame and templateFrame:IsShown() then templateFrame:Refresh() end
            elseif SC.Print then SC.Print(tostring(err or "Template could not be deleted.")) end
        end,
    }
    StaticPopup_Show("SMARTCHAT_DELETE_GROUP_TEMPLATE", templateName, nil, templateName)
end

function SC.ShowContactGroupTemplateMenu(anchor, sourceGroup)
    if not EasyMenu or not UIDropDownMenu_CreateInfo then return end
    if not templateMenu then templateMenu = CreateFrame("Frame", "SmartChatGroupTemplateMenu", UIParent, "UIDropDownMenuTemplate") end
    local menu = {}
    local currentTitle = UIDropDownMenu_CreateInfo(); currentTitle.text = sourceGroup and ("Current My Group: " .. sourceGroup) or "Group Templates"; currentTitle.isTitle = true; currentTitle.notCheckable = true; menu[#menu + 1] = currentTitle
    if sourceGroup then
        local save = UIDropDownMenu_CreateInfo(); save.text = "Save Current Group as Template…"; save.notCheckable = true
        save.func = function() SC.PromptSaveContactGroupTemplate(sourceGroup) end; menu[#menu + 1] = save
    end
    local names = SC.GetContactGroupTemplateNames()
    if #names > 0 then
        local title = UIDropDownMenu_CreateInfo(); title.text = "Saved Templates"; title.isTitle = true; title.notCheckable = true; menu[#menu + 1] = title
        for _, templateName in ipairs(names) do
            local tName = templateName
            local info = SC.GetContactGroupTemplate(tName)
            local count = info and CountMembers(info.members) or 0
            local item = UIDropDownMenu_CreateInfo(); item.text = string.format("%s (%d)", tName, count); item.notCheckable = true; item.hasArrow = true; item.menuList = {}
            local sub = item.menuList
            local create = UIDropDownMenu_CreateInfo(); create.text = "Create My Group from Template…"; create.notCheckable = true; create.func = function() SC.PromptCreateGroupFromTemplate(tName) end; sub[#sub + 1] = create
            local invite = UIDropDownMenu_CreateInfo(); invite.text = "Invite Template Members to Party…"; invite.notCheckable = true; invite.func = function() SC.PromptInviteContactTemplate(tName) end; sub[#sub + 1] = invite
            if sourceGroup then
                local update = UIDropDownMenu_CreateInfo(); update.text = "Update from Current My Group…"; update.notCheckable = true; update.func = function() SC.PromptUpdateTemplateFromGroup(tName, sourceGroup) end; sub[#sub + 1] = update
            end
            local delete = UIDropDownMenu_CreateInfo(); delete.text = "Delete Template…"; delete.notCheckable = true; delete.func = function() SC.PromptDeleteContactGroupTemplate(tName) end; sub[#sub + 1] = delete
            menu[#menu + 1] = item
        end
    else
        local empty = UIDropDownMenu_CreateInfo(); empty.text = "No saved templates yet"; empty.disabled = true; empty.notCheckable = true; menu[#menu + 1] = empty
    end
    EasyMenu(menu, templateMenu, anchor or UIParent, 0, 0, "MENU")
end

local function TemplateButton(parent, text, width, point, relative, relPoint, x, y, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetPoint(point, relative or parent, relPoint or point, x or 0, y or 0)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end

function SC.ShowContactGroupTemplateManager(sourceGroup, selectedNames)
    if not templateFrame then
        templateFrame = CreateFrame("Frame", "SmartChatGroupTemplateManager", UIParent, "BackdropTemplate")
        templateFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        templateFrame:SetFrameLevel(110)
        templateFrame:SetSize(570, 410)
        templateFrame:SetPoint("CENTER")
        templateFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 28, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
        templateFrame:SetBackdropColor(0.035, 0.04, 0.055, 0.98)
        templateFrame.title = templateFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        templateFrame.title:SetPoint("TOPLEFT", 18, -16)
        templateFrame.title:SetText("MY GROUP TEMPLATES")
        templateFrame.subtitle = templateFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        templateFrame.subtitle:SetPoint("TOPLEFT", templateFrame.title, "BOTTOMLEFT", 0, -5)
        templateFrame.subtitle:SetText("Save reusable contact lists. Templates do not create or invite an in-game group.")
        local close = CreateFrame("Button", nil, templateFrame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -3, -3)

        local left = CreateFrame("Frame", nil, templateFrame, "BackdropTemplate")
        left:SetPoint("TOPLEFT", 16, -62); left:SetPoint("BOTTOMLEFT", 16, 46); left:SetWidth(190)
        left:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); left:SetBackdropColor(0, 0, 0, 0.2)
        templateFrame.left = left
        local scroll = CreateFrame("ScrollFrame", nil, left, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 4, -4); scroll:SetPoint("BOTTOMRIGHT", -22, 4)
        local child = CreateFrame("Frame", nil, scroll); child:SetSize(160, 1); scroll:SetScrollChild(child)
        templateFrame.templateScroll, templateFrame.templateChild = scroll, child

        local right = CreateFrame("Frame", nil, templateFrame, "BackdropTemplate")
        right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0); right:SetPoint("BOTTOMRIGHT", templateFrame, "BOTTOMRIGHT", -16, 46)
        right:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); right:SetBackdropColor(0, 0, 0, 0.12)
        templateFrame.right = right
        templateFrame.detail = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        templateFrame.detail:SetPoint("TOPLEFT", 12, -12); templateFrame.detail:SetPoint("TOPRIGHT", -12, -12)
        templateFrame.detail:SetJustifyH("LEFT"); templateFrame.detail:SetJustifyV("TOP"); templateFrame.detail:SetWordWrap(true)

        templateFrame.saveGroup = TemplateButton(templateFrame, "Save Current Group", 122, "BOTTOMLEFT", templateFrame, "BOTTOMLEFT", 16, 12, function()
            if not templateFrame.sourceGroup then if SC.Print then SC.Print("Open Group Templates from a selected My Group first.") end; return end
            SC.PromptSaveContactGroupTemplate(templateFrame.sourceGroup)
        end)
        templateFrame.saveSelection = TemplateButton(templateFrame, "Save Selection", 96, "LEFT", templateFrame.saveGroup, "RIGHT", 6, 0, function()
            if not templateFrame.selectedNames or #templateFrame.selectedNames == 0 then return end
            SC.PromptSaveSelectedContactsAsTemplate(templateFrame.selectedNames)
        end)
        templateFrame.createGroup = TemplateButton(templateFrame, "Create My Group", 108, "LEFT", templateFrame.saveSelection, "RIGHT", 6, 0, function()
            if templateFrame.selectedTemplate then SC.PromptCreateGroupFromTemplate(templateFrame.selectedTemplate) end
        end)
        templateFrame.invite = TemplateButton(templateFrame, "Invite Members", 80, "LEFT", templateFrame.createGroup, "RIGHT", 6, 0, function()
            if templateFrame.selectedTemplate then SC.PromptInviteContactTemplate(templateFrame.selectedTemplate) end
        end)

        templateFrame:EnableMouse(true)
        tinsert(UISpecialFrames, "SmartChatGroupTemplateManager")
    end

    templateFrame.sourceGroup = sourceGroup
    templateFrame.selectedNames = selectedNames
    templateFrame.saveGroup:SetEnabled(sourceGroup ~= nil)
    templateFrame.saveSelection:SetEnabled(type(selectedNames) == "table" and #selectedNames > 0)

    function templateFrame:Refresh()
        for _, row in ipairs(templateRows) do row:Hide(); row:SetParent(nil) end
        wipe(templateRows)
        local s = Social()
        local names = SC.GetContactGroupTemplateNames()
        local child = self.templateChild
        child:SetHeight(math.max(1, #names * 30))
        for i, templateName in ipairs(names) do
            local row = CreateFrame("Button", nil, child)
            row:SetSize(158, 26); row:SetPoint("TOPLEFT", 0, -(i - 1) * 30)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 7, 0); row.text:SetPoint("RIGHT", -3, 0); row.text:SetJustifyH("LEFT")
            local info = SC.GetContactGroupTemplate(templateName)
            row.text:SetText(string.format("%s  |cff999999(%d)|r", templateName, info and CountMembers(info.members) or 0))
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            row.name = templateName
            row:SetScript("OnClick", function(self)
                templateFrame.selectedTemplate = self.name
                templateFrame:RefreshDetail()
            end)
            templateRows[#templateRows + 1] = row
        end
        if not self.selectedTemplate or not SC.GetContactGroupTemplate(self.selectedTemplate) then self.selectedTemplate = names[1] end
        self:RefreshDetail()
    end

    function templateFrame:RefreshDetail()
        local name = self.selectedTemplate
        local info = name and SC.GetContactGroupTemplate(name)
        if not info then
            self.detail:SetText("No saved templates yet.\n\nSave a My Group or a multi-selected contact list as a reusable template. You can later create a fresh My Group from it or invite its available members to your current Party.")
            self.createGroup:Disable(); self.invite:Disable()
            if self.deleteTemplate then self.deleteTemplate:Disable() end
            if self.updateTemplate then self.updateTemplate:Disable() end
            return
        end
        local names = {}
        for _, member in pairs(info.members) do names[#names + 1] = member end
        table.sort(names, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
        local lines = {
            "|cff66ccff" .. info.name .. "|r",
            string.format("Members: %d", #names),
            "Source: " .. tostring(info.source or "Unknown"),
            info.created > 0 and ("Created: " .. date("%Y-%m-%d %H:%M", info.created)) or "Created: Unknown",
            info.updated > 0 and ("Updated: " .. date("%Y-%m-%d %H:%M", info.updated)) or "",
            "",
            "|cff66ccffTEMPLATE MEMBERS|r",
        }
        for i = 1, math.min(#names, 30) do lines[#lines + 1] = string.format("%2d. %s", i, names[i]) end
        if #names > 30 then lines[#lines + 1] = string.format("...and %d more", #names - 30) end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Templates are local snapshots. Editing the source My Group does not change this template unless you choose Update."
        self.detail:SetText(table.concat(lines, "\n"))
        self.createGroup:Enable(); self.invite:Enable()
        if self.deleteTemplate then self.deleteTemplate:Enable() end
        if self.updateTemplate then self.updateTemplate:SetEnabled(self.sourceGroup ~= nil) end
    end

    if not templateFrame.updateTemplate then
        templateFrame.updateTemplate = TemplateButton(templateFrame, "Update from Group", 120, "BOTTOMLEFT", templateFrame, "BOTTOMLEFT", 16, 40, function()
            if templateFrame.selectedTemplate and templateFrame.sourceGroup then SC.PromptUpdateTemplateFromGroup(templateFrame.selectedTemplate, templateFrame.sourceGroup) end
        end)
        templateFrame.deleteTemplate = TemplateButton(templateFrame, "Delete Template", 110, "LEFT", templateFrame.updateTemplate, "RIGHT", 8, 0, function()
            if templateFrame.selectedTemplate then SC.PromptDeleteContactGroupTemplate(templateFrame.selectedTemplate) end
        end)
    end
    templateFrame:Refresh()
    templateFrame:Show()
end
