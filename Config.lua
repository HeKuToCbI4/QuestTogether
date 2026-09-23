--[[----------------------------------------------------------------------------
Config -- the settings panel, the settings themselves, and "Copy debug info".

  * Options -> AddOns -> Quest Together Forever, and /qtf config (or /qtf settings)
    to open it directly.
  * Two TEST checkboxes. They are stored and restored, and nothing reads them:
    this is the scaffold the real toggles (issue #9) will go into.
  * A "Copy debug info" button, and /qtf debug: a window with everything the addon
    knows about itself and the client, selected, ready for Ctrl+C. An addon cannot
    put text on the clipboard itself, so the user presses the key.

The report is assembled from ns.debugSections (Compat.lua): each module registers
what it can report on. This file registers the general sections; Diagnostics adds
its probes and UI its panel state. Nothing here calls into those modules.

Client API: the modern Settings API first, InterfaceOptions second (ns.api). The
panel registers at load, which calls the client only -- never another module.
Neither registration is measured on this client yet (docs/TESTING.md, A16).
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
---@cast ns QT.Namespace

ns.commands = ns.commands or {}

local TITLE = "Quest Together Forever"

------------------------------------------------------------------------------
-- Settings: stored in QuestTogetherForeverDB.settings
------------------------------------------------------------------------------

-- Every setting and its default. The two test options do nothing.
local DEFAULTS = {
    testOptionA = true,
    testOptionB = false,
}

-- The saved table, or nil before ADDON_LOADED (SavedVariables not loaded yet).
local function Store()
    local db = _G.QuestTogetherForeverDB
    if type(db) ~= "table" then return nil end
    if type(db.settings) ~= "table" then db.settings = {} end
    return db.settings
end

---@param key string
---@return any value   the stored value, else the default
function ns.GetSetting(key)
    local store = Store()
    local v = store and store[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

---@param key string
---@param value any
---@return boolean saved   false when the key is unknown or nothing is loaded yet
function ns.SetSetting(key, value)
    if DEFAULTS[key] == nil then return false end
    local store = Store()
    if not store then return false end
    store[key] = value
    return true
end

------------------------------------------------------------------------------
-- The debug report
------------------------------------------------------------------------------

-- Chat colour codes are noise in a pasted report.
local function Plain(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

---@return string report   plain text, one section after another
function ns.BuildDebugInfo()
    local lines = {}
    local function out(line)
        lines[#lines + 1] = Plain(ns.SafeStr(line))
    end

    out(TITLE .. " debug info")
    for _, section in ipairs(ns.debugSections) do
        out("")
        out("## " .. section.title)
        local ok, err = pcall(section.fn, out)
        if not ok then out("  ERROR: " .. ns.SafeStr(err)) end
    end
    return table.concat(lines, "\n")
end

-- Every return value, so "returned nothing" and "returned nil" stay apart.
local function Pack(...) return select("#", ...), { ... } end

local function Call(fn, ...)
    if not fn then return "no such API" end
    local n, r = Pack(pcall(fn, ...))
    if not r[1] then return "ERROR: " .. ns.SafeStr(r[2]) end
    if n == 1 then return "(nothing)" end
    local parts = {}
    for i = 2, n do parts[#parts + 1] = ns.SafeStr(r[i]) end
    return table.concat(parts, ", ")
end

local function Count(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

ns.AddDebugSection("addon", function(out)
    out("  version:            " .. ns.SafeStr(ns.AddonVersion()))
    out("  protocol revision:  " .. ns.SafeStr(ns.PROTOCOL) .. "   prefix: " .. ns.SafeStr(ns.PREFIX))
    out("  prefix registered:  " .. ns.yn(ns.IsPrefixRegistered and ns.IsPrefixRegistered()))
    out("  saved variables:    " .. ns.yn(type(_G.QuestTogetherForeverDB) == "table"))
    local keys = {}
    for k in pairs(DEFAULTS) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        out(("  setting %-12s %s"):format(k, ns.SafeStr(ns.GetSetting(k))))
    end
end)

ns.AddDebugSection("client", function(out)
    local gbi = _G.GetBuildInfo
    local ok, version, build, date, toc = false, nil, nil, nil, nil
    if gbi then ok, version, build, date, toc = pcall(gbi) end
    if ok then
        out(("  client:        %s   build %s   (%s)   toc %s"):format(ns.SafeStr(version),
            ns.SafeStr(build), ns.SafeStr(date), ns.SafeStr(toc)))
    else
        out("  GetBuildInfo:  " .. Call(gbi))
    end
    out("  GetLocale:     " .. Call(_G.GetLocale))
    out("  date:          " .. Call(_G.date, "%Y-%m-%d %H:%M:%S"))
    local present, absent = {}, {}
    for _, k in ipairs(ns.apiKeys) do
        if ns.api[k] then present[#present + 1] = k else absent[#absent + 1] = k end
    end
    out("  api present:   " .. table.concat(present, " "))
    out("  api absent:    " .. (#absent > 0 and table.concat(absent, " ") or "none"))
    -- Unmeasured: whether an addon may write the clipboard here. Recorded only.
    out("  CopyToClipboard exists: " .. ns.yn(_G.CopyToClipboard))
end)

ns.AddDebugSection("player and group", function(out)
    local key, shown = ns.PlayerKey()
    out("  player key:  " .. ns.SafeStr(key) .. "   shown as: " .. ns.SafeStr(shown))
    out("  in group:    " .. Call(_G.IsInGroup) .. "   in raid: " .. Call(_G.IsInRaid))
    out("  channel:     " .. ns.SafeStr(ns.GroupChannel()))
    local members = ns.GroupMembers()
    if not members then
        out("  roster:      unreadable")
    else
        for _, m in ipairs(members) do
            out(("  member  key [%s]  shown as [%s]%s"):format(
                ns.SafeStr(m.key), ns.SafeStr(m.display), m.isPlayer and "  (you)" or ""))
        end
    end
end)

ns.AddDebugSection("peers", function(out)
    local now = ns.Now()
    local n = 0
    for key, p in pairs(ns.peers) do
        n = n + 1
        local age = (now > 0 and type(p.lastSeen) == "number" and p.lastSeen > 0)
            and (now - p.lastSeen) .. "s ago" or "?"
        out(("  [%s] %s  compatible: %s  last seen: %s  answers: %d  on it: %d"):format(
            ns.SafeStr(key), ns.SafeStr(p.name), ns.yn(p.compatible), age,
            Count(p.answered), Count(p.onIt)))
        for qid, done in pairs(p.answered or {}) do
            out(("      quest %s  completed: %s%s"):format(ns.SafeStr(qid), ns.SafeStr(done),
                (p.onIt and p.onIt[qid]) and "  (on it)" or ""))
        end
    end
    if n == 0 then out("  none heard from") end
end)

ns.AddDebugSection("open quest", function(out)
    local qid = ns.LocalQuestID()
    if not qid then out("  none") return end
    local done, why = ns.SafeIsDone(qid)
    out(("  quest %s  completed: %s%s  in log: %s"):format(ns.SafeStr(qid), ns.SafeStr(done),
        why and (" (" .. ns.SafeStr(why) .. ")") or "", ns.SafeStr(ns.SafeInLog(qid))))
end)

------------------------------------------------------------------------------
-- Frames: shared helpers
------------------------------------------------------------------------------

-- A frame from a template, or without it when the client has no such template
-- (an unknown template is an error). None of these templates is measured here.
local function NewFrame(kind, parent, template)
    if template then
        local ok, f = pcall(CreateFrame, kind, nil, parent, template)
        if ok and f then return f, true end
    end
    return CreateFrame(kind, nil, parent), false
end

-- The popup's look: the tooltip backdrop, measured to render here (2026-09-24).
local BACKDROP = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

------------------------------------------------------------------------------
-- The copy window
------------------------------------------------------------------------------

local copyFrame, copyEdit, copyText

local function BuildCopyFrame()
    local f = NewFrame("Frame", UIParent, "BackdropTemplate")
    f:SetSize(560, 420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop and pcall(f.SetBackdrop, f, BACKDROP) then
        f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
        f:SetBackdropBorderColor(0.85, 0.66, 0.38, 1)
    else
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(f)
        bg:SetColorTexture(0, 0, 0, 0.9)
    end

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText(TITLE .. " -- debug info")

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetText("The text is selected: press Ctrl+C to copy, Esc to close.")

    local close = NewFrame("Button", f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    local scroll, templated = NewFrame("ScrollFrame", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -48)
    scroll:SetPoint("BOTTOMRIGHT", templated and -32 or -14, 14)
    if not templated then
        -- No template, no scroll bar: the mouse wheel still scrolls.
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local max = self:GetVerticalScrollRange() or 0
            local y = (self:GetVerticalScroll() or 0) - delta * 40
            self:SetVerticalScroll(math.max(0, math.min(max, y)))
        end)
    end

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject(_G.ChatFontNormal and "ChatFontNormal" or "GameFontHighlightSmall")
    edit:SetWidth(500)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    -- Read-only: typing puts the report back and selects it again.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and copyText then
            self:SetText(copyText)
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(edit)

    copyFrame, copyEdit = f, edit
end

function ns.ShowDebugInfo()
    copyText = ns.BuildDebugInfo()
    if not copyFrame then BuildCopyFrame() end
    copyEdit:SetText(copyText)
    copyFrame:Show()
    copyEdit:SetFocus()
    copyEdit:HighlightText()
end

------------------------------------------------------------------------------
-- The settings panel
------------------------------------------------------------------------------

local panel = CreateFrame("Frame")
panel.name = TITLE   -- InterfaceOptions reads the category name from here

local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
heading:SetPoint("TOPLEFT", 16, -16)
heading:SetText(TITLE)

local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
sub:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -6)

local checks = {}

local function AddCheckbox(key, label, note, y)
    local cb = NewFrame("CheckButton", panel, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", 16, y)
    cb.settingKey = key

    local text = cb:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("LEFT", cb, "RIGHT", 6, 1)
    text:SetText(label)
    local small = cb:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    small:SetPoint("LEFT", text, "RIGHT", 8, 0)
    small:SetText(note)

    cb:SetScript("OnClick", function(self)
        local on = self:GetChecked()
        ns.SetSetting(key, on == true or on == 1)
    end)
    checks[#checks + 1] = cb
    return cb
end

AddCheckbox("testOptionA", "Test option A", "(does nothing yet)", -70)
AddCheckbox("testOptionB", "Test option B", "(does nothing yet)", -102)

local copyButton = NewFrame("Button", panel, "UIPanelButtonTemplate")
copyButton:SetSize(160, 24)
copyButton:SetPoint("TOPLEFT", 20, -150)
copyButton:SetText("Copy debug info")
copyButton:SetScript("OnClick", function() ns.ShowDebugInfo() end)

local copyNote = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
copyNote:SetPoint("LEFT", copyButton, "RIGHT", 10, 0)
copyNote:SetText("Opens a window with the report selected -- then Ctrl+C.")

panel:SetScript("OnShow", function()
    sub:SetText(("Version %s   -   protocol revision %s"):format(
        ns.SafeStr(ns.AddonVersion()), ns.SafeStr(ns.PROTOCOL)))
    for _, cb in ipairs(checks) do
        cb:SetChecked(ns.GetSetting(cb.settingKey) == true)
    end
end)

------------------------------------------------------------------------------
-- Registration with the Options window
------------------------------------------------------------------------------

local category          -- the modern Settings category, when registered that way
local registeredVia     -- how the panel got in, for the debug report

local function Register()
    local api = ns.api
    if api.settingsCanvas and api.settingsAddOn then
        local ok, cat = pcall(api.settingsCanvas, panel, TITLE)
        if ok and cat and pcall(api.settingsAddOn, cat) then
            category, registeredVia = cat, "Settings (canvas layout)"
            return
        end
        registeredVia = "Settings failed: " .. ns.SafeStr(cat)
    end
    if api.legacyAddPanel and pcall(api.legacyAddPanel, panel) then
        registeredVia = "InterfaceOptions"
        return
    end
    registeredVia = registeredVia or "none: no options API on this client"
end

Register()

local function OpenSettings()
    local api = ns.api
    if api.inCombat and api.inCombat() then
        ns.Print("Cannot open the options window in combat. /qtf debug still works.")
        return
    end
    if category and api.settingsOpen then
        local id = category.GetID and category:GetID() or category.ID
        local ok, err = pcall(api.settingsOpen, id)
        if not ok then ns.Print("Could not open the options window: " .. ns.SafeStr(err)) end
        return
    end
    if registeredVia == "InterfaceOptions" and api.legacyOpen then
        -- The old API needs two calls to land on an addon's page the first time.
        pcall(api.legacyOpen, panel)
        pcall(api.legacyOpen, panel)
        return
    end
    ns.Print("The options window is not available here (" .. ns.SafeStr(registeredVia)
        .. "). /qtf debug still works.")
end

ns.commands.config   = OpenSettings
ns.commands.settings = OpenSettings
ns.commands.debug    = function() ns.ShowDebugInfo() end

ns.AddDebugSection("settings panel", function(out)
    out("  registered via:  " .. ns.SafeStr(registeredVia))
    out("  category id:     " .. ns.SafeStr(category and (category.GetID and category:GetID() or category.ID)))
end)

ns.AddHelp("/qtf config", "open the settings (also /qtf settings)")
ns.AddHelp("/qtf debug", "show the debug report, ready to copy")
