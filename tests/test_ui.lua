--[[----------------------------------------------------------------------------
UI -- the status panel's slide out from under the quest frame.

Only the mechanics are checked here: where the panel starts and stops, that the
animation ends and unhooks itself, and that it never runs without a quest frame
to hide behind. Whether it LOOKS right needs the client (docs/TESTING.md, A15).
------------------------------------------------------------------------------]]

local h = require("harness")

-- Record what the addon does to every frame it created, so the panel can be
-- found by its behaviour rather than by creation order.
local function instrument(env)
    for _, f in ipairs(env.frames) do
        f._points, f._alpha = {}, nil
        function f:SetPoint(_, _, _, x, y) self._points[#self._points + 1] = { x = x, y = y } end
        function f:SetAlpha(a) self._alpha = a end
        function f:SetFrameStrata(s) self._strata = s end
        function f:SetFrameLevel(l) self._level = l end
    end
end

local function fakeQuestFrame()
    local qf = h.NewFrame()
    qf:Show()
    function qf:GetFrameStrata() return "MEDIUM" end
    function qf:GetFrameLevel() return 5 end
    return qf
end

local function sliding(env)
    for _, f in ipairs(env.frames) do
        if f:GetScript("OnUpdate") then return f end
    end
end

h.test("the panel slides out from under the quest frame and stops", { questFrame = fakeQuestFrame() }, function(env, ns)
    env.localQuest = 783
    instrument(env)

    ns.commands.ui()
    local panel = sliding(env)
    h.ok(panel, "an animation is running")
    h.eq(panel._strata, "MEDIUM", "same strata as the quest frame")
    h.eq(panel._level, 4, "one level below it")
    h.eq(panel._alpha, 0, "starts invisible")
    local start = panel._points[#panel._points].x

    local prev = start
    for _ = 1, 10 do
        panel:Fire("OnUpdate", 0.05)
        local x = panel._points[#panel._points].x
        h.isTrue(x >= prev, "never moves back")
        prev = x
    end

    h.isNil(panel:GetScript("OnUpdate"), "the animation unhooks itself")
    h.isTrue(start < prev, "moved to the right")
    h.eq(prev, -4, "stops just under the quest frame's edge")
    h.eq(panel._alpha, 1, "ends fully opaque")
end)

h.test("switching quests with the panel up does not replay the slide", { questFrame = fakeQuestFrame() }, function(env, ns)
    env.localQuest = 783
    instrument(env)

    ns.commands.ui()
    local panel = sliding(env)
    for _ = 1, 10 do panel:Fire("OnUpdate", 0.05) end
    h.isNil(sliding(env), "first slide finished")

    _G.QuestFrame:Fire("OnShow")
    h.isNil(sliding(env), "already shown: repaint only")
end)

h.test("closing the quest frame mid-slide stops the animation", { questFrame = fakeQuestFrame() }, function(env, ns)
    instrument(env)

    ns.commands.ui()
    local panel = sliding(env)
    h.ok(panel, "an animation is running")
    panel:Fire("OnUpdate", 0.05)
    _G.QuestFrame:Fire("OnHide")

    h.isNil(panel:GetScript("OnUpdate"), "no animation left behind")
    h.isFalse(panel:IsShown(), "hidden with the quest frame")
end)

h.test("without a quest frame the panel appears in place", function(env, ns)
    instrument(env)
    h.noError(function() ns.commands.ui() end, "/qt ui solo")
    h.isNil(sliding(env), "nothing to slide from under")
end)

local function fakeParchmentPanel()
    local p = h.NewFrame()
    p:Show()
    local bg = h.NewFrame()
    function bg:GetObjectType() return "Texture" end
    function bg:GetAtlas() return "QuestBG-Parchment" end
    function bg:GetWidth() return 300 end
    function bg:GetHeight() return 400 end
    p.Bg = bg
    return p
end

h.test("the parchment is borrowed from the quest panel on screen",
    { questFrame = fakeQuestFrame(), globals = { QuestFrameDetailPanel = fakeParchmentPanel() } },
    function(env, ns)
        env.localQuest = 783
        ns.commands.ui()
        h.eq(ns.uiParchment.source, "QuestFrameDetailPanel.Bg", "found the panel's Bg")
        h.eq(ns.uiParchment.copied, "atlas QuestBG-Parchment", "copied by atlas")
    end)

h.test("no quest panel on screen: no parchment, no error", { questFrame = fakeQuestFrame() }, function(env, ns)
    h.noError(function() ns.commands.ui() end, "/qt ui with the quest frame up")
    h.isNil(ns.uiParchment.source, "nothing borrowed")
end)

local function fakeFontString(path, size, r, g, b)
    local fs = h.NewFrame()
    function fs:GetObjectType() return "FontString" end
    function fs:GetFont() return path, size, "" end
    function fs:GetTextColor() return r, g, b end
    return fs
end

h.test("on parchment the quest text's font is borrowed too", {
    questFrame = fakeQuestFrame(),
    globals = {
        QuestFrameDetailPanel = fakeParchmentPanel(),
        QuestInfoDescriptionText = fakeFontString("Fonts\FRIZQT__.TTF", 13, 0, 0, 0),
    },
}, function(env, ns)
    env.localQuest = 783
    ns.commands.ui()
    h.eq(ns.uiParchment.font, "QuestInfoDescriptionText  Fonts\FRIZQT__.TTF 13", "font source recorded")
end)

h.test("no quest font on screen: parchment still applies", {
    questFrame = fakeQuestFrame(),
    globals = { QuestFrameDetailPanel = fakeParchmentPanel() },
}, function(env, ns)
    h.noError(function() ns.commands.ui() end, "/qt ui")
    h.isNil(ns.uiParchment.font, "no font borrowed")
    h.eq(ns.uiParchment.source, "QuestFrameDetailPanel.Bg", "parchment still found")
end)
