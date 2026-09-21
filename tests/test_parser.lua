--[[----------------------------------------------------------------------------
ns.ParseMessage -- the pure half of the receive path.

Text in, table or nil out. Nothing here touches the peer registry or the send
stub; those live in the other test files. A `nil` return is the parser saying
"nothing I can safely act on", and the only correct response to it is silence.
------------------------------------------------------------------------------]]

local h = require("harness")

------------------------------------------------------------------------------
-- Well-formed messages
------------------------------------------------------------------------------

h.test("parses a presence announcement", function(_, ns)
    local msg = ns.ParseMessage("2|H")
    h.ok(msg, "2|H parses")
    h.eq(msg.kind, "H", "kind")
    h.eq(msg.rev, 2, "rev")
    h.isNil(msg.questID, "H carries no quest ID")
    h.isNil(msg.status, "H carries no status")
end)

h.test("parses a query", function(_, ns)
    local msg = ns.ParseMessage("2|Q|92460")
    h.ok(msg, "2|Q|92460 parses")
    h.eq(msg.kind, "Q", "kind")
    h.eq(msg.questID, 92460, "quest ID")
    h.isNil(msg.status, "a query carries no status")
end)

h.test("parses all three answer statuses", function(_, ns)
    for _, status in ipairs({ 0, 1, 2 }) do
        local msg = ns.ParseMessage("2|A|92460|" .. status)
        h.ok(msg, "answer with status " .. status .. " parses")
        h.eq(msg.kind, "A", "kind")
        h.eq(msg.questID, 92460, "quest ID")
        h.eq(msg.status, status, "status")
    end
end)

h.test("accepts the largest allowed quest ID", function(_, ns)
    local msg = ns.ParseMessage("2|Q|2147483647")
    h.ok(msg, "2^31-1 is accepted")
    h.eq(msg.questID, 2147483647, "quest ID")
end)

------------------------------------------------------------------------------
-- Not a string at all
------------------------------------------------------------------------------

h.test("rejects non-string input without erroring", function(_, ns)
    for _, value in ipairs({ 42, true, false, {}, print }) do
        h.isNil(ns.ParseMessage(value), "input of type " .. type(value))
    end
    h.isNil(ns.ParseMessage(nil), "nil input")
end)

------------------------------------------------------------------------------
-- Malformed and truncated
------------------------------------------------------------------------------

h.test("rejects malformed and truncated payloads", function(_, ns)
    local bad = {
        "", "2", "2|", "|", "|||", "2|Q", "2|Q|", "2|A", "2|A|92460",
        "2|A|92460|", "H", "Q|92460", "2 H", "2,H", "  2|H",
    }
    for _, text in ipairs(bad) do
        h.isNil(ns.ParseMessage(text), "payload " .. h.show(text))
    end
end)

h.test("rejects an unknown kind, and is case-sensitive", function(_, ns)
    for _, text in ipairs({ "2|Z|92460", "2|q|92460", "2|a|92460|1", "2|h", "2|QQ|92460" }) do
        h.isNil(ns.ParseMessage(text), "payload " .. h.show(text))
    end
end)

h.test("rejects any revision but our own", function(_, ns)
    for _, text in ipairs({ "1|H", "3|H", "0|H", "|H", "02|H", "2.0|H", "x|H", " 2|H", "2 |H" }) do
        h.isNil(ns.ParseMessage(text), "payload " .. h.show(text))
    end
end)

------------------------------------------------------------------------------
-- Quest IDs
--
-- Zero is the sharp one: the live oracle answers `false` for it rather than
-- raising, so an unvalidated 0 would broadcast a confident "not completed" for
-- something that is not a quest.
------------------------------------------------------------------------------

h.test("rejects quest IDs that are not usable", function(_, ns)
    local bad = {
        "0", "-1", "-3", "1.5", "0.5", "2147483648", "1e99", "9999999999999999999999",
        "abc", "", " ", "nan", "inf", "0/0", "1,5", "#92460", "92460abc",
    }
    for _, id in ipairs(bad) do
        h.isNil(ns.ParseMessage("2|Q|" .. id), "query for quest ID " .. h.show(id))
        h.isNil(ns.ParseMessage("2|A|" .. id .. "|1"), "answer for quest ID " .. h.show(id))
    end
end)

------------------------------------------------------------------------------
-- Statuses
------------------------------------------------------------------------------

h.test("rejects a status outside 0, 1 and 2", function(_, ns)
    for _, status in ipairs({ "3", "-1", "0.5", "", " ", "x", "true", "10", "01x" }) do
        h.isNil(ns.ParseMessage("2|A|92460|" .. status), "status " .. h.show(status))
    end
end)

------------------------------------------------------------------------------
-- Size
------------------------------------------------------------------------------

h.test("rejects anything longer than 200 characters", function(_, ns)
    local atLimit = "2|Q|92460" .. string.rep("|", 191)
    h.eq(#atLimit, 200, "test fixture length")
    h.ok(ns.ParseMessage(atLimit), "exactly 200 characters is still parsed")
    h.isNil(ns.ParseMessage(atLimit .. "|"), "201 characters is rejected")
    h.isNil(ns.ParseMessage("2|A|92460|1" .. string.rep("x", 500)), "a very long payload")
    h.isNil(ns.ParseMessage(string.rep("|", 1000)), "a wall of delimiters")
end)

------------------------------------------------------------------------------
-- Trailing fields
--
-- CURRENT BEHAVIOUR, asserted rather than changed: fields beyond the ones a
-- kind defines are ignored, exactly as the strsplit-based parser did. Making
-- the parser strict here would be a behaviour change on the receive path, so it
-- belongs in its own PR.
------------------------------------------------------------------------------

h.test("ignores trailing fields beyond the ones a kind defines", function(_, ns)
    local q = ns.ParseMessage("2|Q|92460|junk|more")
    h.ok(q, "extra fields on a query are ignored")
    h.eq(q.questID, 92460, "quest ID")

    local a = ns.ParseMessage("2|A|92460|1|junk")
    h.ok(a, "extra fields on an answer are ignored")
    h.eq(a.status, 1, "status")

    h.ok(ns.ParseMessage("2|H|junk"), "extra fields on a presence announcement are ignored")
end)

------------------------------------------------------------------------------
-- Hostile bytes
------------------------------------------------------------------------------

h.test("never raises on hostile bytes", function(_, ns)
    local nasty = {
        "2|Q|92460\0\0", "\0\0\0", "2|A|%s|%d", "2|A|92460|1%s",
        "2|\255\254|1", string.rep("2|", 90), "2|Q|" .. string.rep("9", 150),
        "2|H\n2|H", "2||||||H", "2|A|92460|1|" .. string.rep("|", 100),
    }
    for _, text in ipairs(nasty) do
        h.noError(function() ns.ParseMessage(text) end, "parsing " .. h.show(text))
    end
end)

h.test("is a pure function -- no state, no side effects", function(env, ns)
    for _ = 1, 3 do
        local msg = ns.ParseMessage("2|A|92460|2")
        h.eq(msg.status, 2, "same answer every time")
    end
    ns.ParseMessage("2|Q|92460")
    ns.ParseMessage("2|H")
    h.eq(#env.sent, 0, "parsing sends nothing")
    h.eq(h.count(ns.peers), 0, "parsing records no peers")
end)
