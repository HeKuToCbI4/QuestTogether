--[[----------------------------------------------------------------------------
Config -- the settings panel, the settings, and "Copy debug info".

The Options window itself needs the client (docs/TESTING.md, A16). What is
checked here: registration picks the API that exists and survives when none does,
settings default and persist, and the debug report is complete, plain and never
broken by one bad section.
------------------------------------------------------------------------------]]

local h = require("harness")

local function fakeSettings()
    local s = { registered = {}, opened = {} }
    function s.RegisterCanvasLayoutCategory(frame, name)
        local cat = { frame = frame, name = name }
        function cat:GetID() return 42 end
        s.registered[#s.registered + 1] = cat
        return cat
    end
    function s.RegisterAddOnCategory(cat) s.addon = cat end
    function s.OpenToCategory(id) s.opened[#s.opened + 1] = id end
    return s
end

local function printed(env, needle)
    for _, line in ipairs(env.prints) do
        if line:find(needle, 1, true) then return true end
    end
    return false
end

h.test("registers with the Settings API and opens on /qt config and /qt settings",
    { globals = { Settings = fakeSettings() } },
    function(env, ns)
        local s = _G.Settings
        h.eq(#s.registered, 1, "one canvas category")
        h.eq(s.registered[1].name, "Quest Together Forever", "under the addon's name")
        h.ok(s.addon, "added to the AddOns tab")
        ns.commands.config()
        ns.commands.settings()
        h.eq(s.opened[1], 42, "/qt config opens our category by ID")
        h.eq(s.opened[2], 42, "/qt settings too")
    end)

h.test("no options API: /qt config says so, and nothing breaks", function(env, ns)
    h.noError(function() ns.commands.config() end, "/qt config")
    h.isTrue(printed(env, "not available"), "the user is told")
end)

h.test("settings: defaults before load, persisted after", function(env, ns)
    h.eq(ns.GetSetting("testOptionA"), true, "A defaults on")
    h.eq(ns.GetSetting("testOptionB"), false, "B defaults off")
    h.isFalse(ns.SetSetting("testOptionB", true), "nothing to write into before ADDON_LOADED")

    _G.QuestTogetherForeverDB = {}
    h.isTrue(ns.SetSetting("testOptionB", true), "saved")
    h.eq(_G.QuestTogetherForeverDB.settings.testOptionB, true, "in the SavedVariables table")
    h.eq(ns.GetSetting("testOptionB"), true, "read back")
    h.isFalse(ns.SetSetting("noSuchSetting", true), "unknown keys are refused")
end)

h.test("a checkbox click writes its setting", function(env, ns)
    _G.QuestTogetherForeverDB = {}
    local cb
    for _, f in ipairs(env.frames) do
        if f.settingKey == "testOptionA" then cb = f end
    end
    h.ok(cb, "found checkbox A")
    function cb:GetChecked() return false end
    cb:Fire("OnClick")
    h.eq(ns.GetSetting("testOptionA"), false, "unticked")
    function cb:GetChecked() return 1 end   -- older clients answer 1, not true
    cb:Fire("OnClick")
    h.eq(ns.GetSetting("testOptionA"), true, "ticked")
end)

h.test("the debug report has every section, in plain text", function(env, ns)
    local report = ns.BuildDebugInfo()
    for _, section in ipairs({
        "## addon", "## client", "## player and group", "## peers", "## open quest",
        "## settings panel", "## channel probe", "## realm probe", "## roster probe",
        "## status panel",
    }) do
        h.isTrue(report:find(section, 1, true) ~= nil, "has " .. section)
    end
    h.isNil(report:find("|c", 1, true), "no colour codes")
    h.isTrue(report:find("protocol revision:  " .. ns.PROTOCOL, 1, true) ~= nil, "protocol revision")
end)

h.test("ns.apiKeys names every ns.api entry, so the report can list the absent ones",
    { globals = { Settings = fakeSettings() } },
    function(env, ns)
        local listed = {}
        for _, k in ipairs(ns.apiKeys) do listed[k] = true end
        for k in pairs(ns.api) do h.isTrue(listed[k], "ns.apiKeys lists " .. k) end
        local report = ns.BuildDebugInfo()
        h.isTrue(report:find("settingsCanvas", 1, true) ~= nil, "present APIs are named")
        h.isTrue(report:find("api absent:    legacyAddPanel", 1, true) ~= nil, "absent ones too")
    end)

h.test("one broken section does not break the report", function(env, ns)
    ns.AddDebugSection("broken", function() error("boom") end)
    local report
    h.noError(function() report = ns.BuildDebugInfo() end, "build")
    h.isTrue(report:find("ERROR:", 1, true) ~= nil, "the error is reported")
    h.isTrue(report:find("## status panel", 1, true) ~= nil, "later sections still there")
end)

h.test("/qt debug opens the copy window without error", function(env, ns)
    h.noError(function() ns.commands.debug() end, "/qt debug")
    h.noError(function() ns.commands.debug() end, "and again, reusing the window")
end)
