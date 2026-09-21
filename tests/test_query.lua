--[[----------------------------------------------------------------------------
Query and auto-ask -- what the user is told, and how often the group is asked.

Two regressions from the second two-client run (2026-09-21):

  * the 3-second summary repeated every live answer line word for word;
  * re-opening a quest never asked again, so a peer who had accepted the quest in
    the meantime stayed "no - has not completed it" in the popup forever.
------------------------------------------------------------------------------]]

local h = require("harness")

local QUEST = 783

local function answer(ns, status, sender)
    ns.HandleAddonMessage(ns.PREFIX, "2|A|" .. QUEST .. "|" .. status, "PARTY", sender or "Bob")
end

local function printed(env, needle)
    local n = 0
    for _, line in ipairs(env.prints) do
        if line:find(needle, 1, true) then n = n + 1 end
    end
    return n
end

-- The UI's event frame: the only one that listens to BOTH a quest event and the
-- roster (Diagnostics traces quest events, but not the roster).
local function uiFrame(env)
    for _, f in ipairs(env.frames) do
        if f:IsEventRegistered("QUEST_DETAIL") and f:IsEventRegistered("GROUP_ROSTER_UPDATE") then
            return f
        end
    end
end

local function queries(env)
    local n = 0
    for _, m in ipairs(env.sent) do
        if m.payload == "2|Q|" .. QUEST then n = n + 1 end
    end
    return n
end

h.test("an answer is printed once, not again in the summary", function(env, ns)
    env.groupNames.party1 = "Bob"
    h.isTrue(ns.Ask(QUEST), "the ask went out")
    answer(ns, 2)
    env.flushTimers()
    h.eq(printed(env, "Bob: on it now"), 1, "one line for Bob, live")
    h.eq(printed(env, "no answer from"), 0, "everybody answered: no summary at all")
end)

h.test("the summary lists only the members who did not answer", function(env, ns)
    env.groupNames.party1 = "Bob"
    env.groupNames.party2 = "Carol"
    env.groupSize = 3
    ns.Ask(QUEST)
    answer(ns, 1)
    env.flushTimers()
    h.eq(printed(env, "Bob: yes"), 1, "Bob once")
    h.eq(printed(env, "no answer from"), 1, "a summary heading")
    h.eq(printed(env, "Carol: ?  (no addon heard from)"), 1, "Carol is the one still unknown")
end)

h.test("an answer cached before the ask is still reported", function(env, ns)
    env.groupNames.party1 = "Bob"
    answer(ns, 0)                 -- arrives while nothing is pending: no live line
    ns.Ask(QUEST)
    env.flushTimers()             -- Bob does not answer this time
    h.eq(printed(env, "Bob: no - has not completed it"), 1, "reported by the summary instead")
end)

h.test("re-opening a quest asks again once the dedupe window has passed", function(env, ns)
    local f = uiFrame(env)
    h.ok(f, "found the UI event frame")
    env.localQuest = QUEST

    f:Fire("OnEvent", "QUEST_DETAIL"); env.flushTimers()
    f:Fire("OnEvent", "QUEST_DETAIL"); env.flushTimers()
    h.eq(queries(env), 1, "a re-fired event for the same opening asks once")

    env.now = env.now + 60
    f:Fire("OnEvent", "QUEST_DETAIL"); env.flushTimers()
    h.eq(queries(env), 2, "opening it again later asks again")
end)

h.test("a quest in progress or ready to turn in is asked about too", function(env, ns)
    local f = uiFrame(env)
    env.localQuest = QUEST
    f:Fire("OnEvent", "QUEST_PROGRESS"); env.flushTimers()
    h.eq(queries(env), 1, "QUEST_PROGRESS asks")
    env.now = env.now + 60
    f:Fire("OnEvent", "QUEST_COMPLETE"); env.flushTimers()
    h.eq(queries(env), 2, "QUEST_COMPLETE asks")
end)

h.test("auto-ask stays silent", function(env, ns)
    env.groupNames.party1 = "Bob"
    env.localQuest = QUEST
    uiFrame(env):Fire("OnEvent", "QUEST_DETAIL"); env.flushTimers()
    answer(ns, 2)
    env.flushTimers()
    h.eq(printed(env, "Asking your group"), 0, "no ask line")
    h.eq(printed(env, "on it now"), 0, "no answer line in chat")
end)
