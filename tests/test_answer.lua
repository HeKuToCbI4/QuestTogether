--[[----------------------------------------------------------------------------
Answering a query, and the completion oracle behind it.

status 1 = completed, 2 = in the log right now, 0 = neither.

The important half is the silence: when the oracle cannot answer, we send
NOTHING. The asker keeps showing "?", which is the honest answer. Inventing a
"no" on our behalf is the one failure this addon exists to prevent.
------------------------------------------------------------------------------]]

local h = require("harness")

local QUEST = 92460

local function ask(ns, questID, channel)
    ns.HandleAddonMessage(ns.PREFIX, "2|Q|" .. (questID or QUEST), channel or "PARTY", "Bob")
end

------------------------------------------------------------------------------
-- The three answers
------------------------------------------------------------------------------

h.test("a completed quest answers 1", function(env, ns)
    env.completed[QUEST] = true
    ask(ns, QUEST)
    h.eq(#env.sent, 1, "one reply")
    h.eq(env.lastSent(), "2|A|" .. QUEST .. "|1", "payload")
end)

h.test("a quest in the log but not completed answers 2", function(env, ns)
    env.inLog[QUEST] = 7
    ask(ns, QUEST)
    h.eq(env.lastSent(), "2|A|" .. QUEST .. "|2", "payload")
end)

h.test("neither completed nor in the log answers 0", function(env, ns)
    ask(ns, QUEST)
    h.eq(env.lastSent(), "2|A|" .. QUEST .. "|0", "payload")
end)

h.test("completed wins over being in the log", function(env, ns)
    env.completed[QUEST] = true
    env.inLog[QUEST] = 7
    ask(ns, QUEST)
    h.eq(env.lastSent(), "2|A|" .. QUEST .. "|1", "payload")
end)

h.test("the reply goes back on the channel the query arrived on", function(env, ns)
    ask(ns, QUEST, "RAID")
    h.eq(env.sent[1].channel, "RAID", "channel")
    h.eq(env.sent[1].prefix, ns.PREFIX, "prefix")
end)

h.test("a missing log-index API still answers 0", { logIndex = false }, function(env, ns)
    ask(ns, QUEST)
    h.eq(env.lastSent(), "2|A|" .. QUEST .. "|0", "payload")
end)

h.test("an erroring log-index API still answers 0", function(env, ns)
    env.logIndex = function() error("boom") end
    ask(ns, QUEST)
    h.eq(env.lastSent(), "2|A|" .. QUEST .. "|0", "payload")
end)

------------------------------------------------------------------------------
-- Silence -- ns.SafeIsDone returns nil, and nothing goes on the wire
------------------------------------------------------------------------------

h.test("an erroring oracle stays silent and answers nil", function(env, ns)
    env.oracle = function() error("the client exploded") end

    local done, why = ns.SafeIsDone(QUEST)
    h.isNil(done, "SafeIsDone")
    h.eq(why, "call errored", "reason")

    ask(ns, QUEST)
    h.eq(#env.sent, 0, "nothing was sent")
end)

h.test("a non-boolean oracle stays silent and answers nil", function(env, ns)
    for _, value in ipairs({ "yes", 1, 0, {} }) do
        env.oracle = function() return value end
        local done, why = ns.SafeIsDone(QUEST)
        h.isNil(done, "SafeIsDone for a " .. type(value) .. " result")
        h.eq(why, "non-boolean result", "reason")
    end

    env.oracle = function() return nil end
    h.isNil(ns.SafeIsDone(QUEST), "SafeIsDone for a nil result")

    ask(ns, QUEST)
    h.eq(#env.sent, 0, "nothing was sent")
end)

h.test("a missing oracle stays silent and answers nil", { questLog = false }, function(env, ns)
    h.isNil(ns.api.isDone, "there is no completion API")

    local done, why = ns.SafeIsDone(QUEST)
    h.isNil(done, "SafeIsDone")
    h.eq(why, "no completion API", "reason")

    ask(ns, QUEST)
    h.eq(#env.sent, 0, "nothing was sent")
end)

h.test("a secret oracle result stays silent and answers nil", function(env, ns)
    local secret = {}
    env.secrets[secret] = true
    env.oracle = function() return secret end

    local done, why = ns.SafeIsDone(QUEST)
    h.isNil(done, "SafeIsDone")
    h.eq(why, "secret value", "reason")

    ask(ns, QUEST)
    h.eq(#env.sent, 0, "nothing was sent")
end)

h.test("SafeIsDone never returns false when it cannot know", function(env, ns)
    local cannotKnow = {
        function() error("boom") end,
        function() return nil end,
        function() return "false" end,
        function() return 0 end,
    }
    for i, oracle in ipairs(cannotKnow) do
        env.oracle = oracle
        h.isNil(ns.SafeIsDone(QUEST), "oracle #" .. i)
    end

    -- And it DOES pass a real boolean through, both ways.
    env.oracle = function() return false end
    h.isFalse(ns.SafeIsDone(QUEST), "a real false")
    env.oracle = function() return true end
    h.isTrue(ns.SafeIsDone(QUEST), "a real true")
end)

------------------------------------------------------------------------------
-- Queries we must not answer
------------------------------------------------------------------------------

h.test("an unusable quest ID is never answered", function(env, ns)
    env.oracle = function() return true end   -- would answer "1" for anything
    for _, id in ipairs({ "0", "-1", "1.5", "2147483648", "abc", "", "1e99" }) do
        ns.HandleAddonMessage(ns.PREFIX, "2|Q|" .. id, "PARTY", "Bob")
    end
    h.eq(#env.sent, 0, "nothing was sent")
    h.ok(ns.peers.Bob, "but the peer was still marked")
end)

h.test("a query with no send API cannot crash us", { chatInfo = false }, function(env, ns)
    h.isNil(ns.api.send, "there is no send API")
    env.completed[QUEST] = true
    h.noError(function() ask(ns, QUEST) end, "answering without a send API")
    h.eq(#env.sent, 0, "nothing was sent")
end)
