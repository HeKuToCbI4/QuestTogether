--[[----------------------------------------------------------------------------
The dispatcher -- who gets listened to, and what hostile input may do.

Everything arriving here comes from another client, so the standard is absolute:
no Lua error, ever, whatever the four arguments are (docs/ROADMAP.md, testing
strategy layer 3). Core wraps this call in pcall as a second line of defence;
these tests check it never needs it.
------------------------------------------------------------------------------]]

local h = require("harness")

local QUEST = 92460

------------------------------------------------------------------------------
-- Messages we must ignore
------------------------------------------------------------------------------

h.test("another addon's prefix is ignored", function(env, ns)
    env.completed[QUEST] = true
    ns.HandleAddonMessage("OTHER", "2|Q|" .. QUEST, "PARTY", "Bob")
    ns.HandleAddonMessage("", "2|H", "PARTY", "Bob")
    ns.HandleAddonMessage(nil, "2|H", "PARTY", "Bob")
    h.eq(h.count(ns.peers), 0, "no peer was recorded")
    h.eq(#env.sent, 0, "nothing was sent")
end)

h.test("our own messages are ignored", function(env, ns)
    env.completed[QUEST] = true
    ns.HandleAddonMessage(ns.PREFIX, "2|H", "PARTY", "Tester")
    ns.HandleAddonMessage(ns.PREFIX, "2|Q|" .. QUEST, "PARTY", "Tester")
    ns.HandleAddonMessage(ns.PREFIX, "2|A|" .. QUEST .. "|1", "PARTY", "Tester")
    h.eq(h.count(ns.peers), 0, "we never become our own peer")
    h.eq(#env.sent, 0, "we never answer ourselves")
end)

h.test("our own messages are ignored across realms too", function(env, ns)
    ns.HandleAddonMessage(ns.PREFIX, "2|Q|" .. QUEST, "PARTY", "Tester-Ravencrest")
    h.eq(h.count(ns.peers), 0, "the bare name matched us")
    h.eq(#env.sent, 0, "nothing was sent")
end)

h.test("a sender we cannot read is ignored", function(env, ns)
    for _, sender in ipairs({ 42, true, {}, print }) do
        ns.HandleAddonMessage(ns.PREFIX, "2|H", "PARTY", sender)
    end
    ns.HandleAddonMessage(ns.PREFIX, "2|H", "PARTY", nil)
    h.eq(h.count(ns.peers), 0, "no peer was recorded")
    h.eq(#env.sent, 0, "nothing was sent")
end)

h.test("an oversized message never reaches the peer registry", function(env, ns)
    local huge = "2|Q|" .. QUEST .. string.rep("|", 200)
    h.ok(#huge > 200, "test fixture is oversized")
    ns.HandleAddonMessage(ns.PREFIX, huge, "PARTY", "Bob")
    h.eq(h.count(ns.peers), 0, "the peer was not even marked")
    h.eq(#env.sent, 0, "nothing was sent")
end)

h.test("a non-string body never reaches the peer registry", function(env, ns)
    for _, text in ipairs({ 2, true, {}, print }) do
        ns.HandleAddonMessage(ns.PREFIX, text, "PARTY", "Bob")
    end
    ns.HandleAddonMessage(ns.PREFIX, nil, "PARTY", "Bob")
    h.eq(h.count(ns.peers), 0, "no peer was recorded")
    h.eq(#env.sent, 0, "nothing was sent")
end)

------------------------------------------------------------------------------
-- Messages we do listen to
------------------------------------------------------------------------------

h.test("every message from another player marks the sender", function(_, ns)
    local messages = { "2|H", "2|Q|" .. QUEST, "2|A|" .. QUEST .. "|1", "2|Z|nonsense",
                       "2|Q|0", "1|H", "2|", "" }
    for i, text in ipairs(messages) do
        local sender = "Peer" .. i
        ns.HandleAddonMessage(ns.PREFIX, text, "PARTY", sender)
        h.ok(ns.peers[sender], "message " .. h.show(text) .. " marked the sender")
    end
end)

h.test("the peer is announced once, not on every message", function(env, ns)
    for _ = 1, 5 do
        ns.HandleAddonMessage(ns.PREFIX, "2|H", "PARTY", "Bob")
    end
    h.eq(#env.prints, 1, "one 'has the addon' line")
    h.eq(ns.peers.Bob.lastSeen, env.now, "lastSeen was refreshed")
end)

------------------------------------------------------------------------------
-- Hostile input
------------------------------------------------------------------------------

h.test("hostile input never raises", function(env, ns)
    local bodies = {
        "", "|", "||||||||", "2", "2|", "2|A", "2|A|", "2|A||", "2|A|||",
        "2|Q|" .. string.rep("9", 100), "2|A|1e308|1", "2|A|-1e308|0",
        "2|Q|0", "2|Q|-0", "2|Q|0x7fffffff", "2|A|92460|1e0",
        "\0", "2|H\0", "2|\255\254\253|1", "%s%d%q", "2|A|%d|%d",
        string.rep("|", 199), string.rep("2", 199), "2|H|" .. string.rep("x", 190),
    }
    local senders = { "Bob", "Bob-Realm", "-", "", "Tester", "\0", string.rep("z", 300) }

    for _, body in ipairs(bodies) do
        for _, sender in ipairs(senders) do
            for _, channel in ipairs({ "PARTY", "RAID", "WHISPER" }) do
                h.noError(function()
                    ns.HandleAddonMessage(ns.PREFIX, body, channel, sender)
                end, "body " .. h.show(body) .. " from " .. h.show(sender))
            end
        end
    end

    -- Odd channels and prefixes, once each.
    for _, channel in ipairs({ 42, {}, true }) do
        h.noError(function()
            ns.HandleAddonMessage(ns.PREFIX, "2|H", channel, "Bob")
        end, "a channel of type " .. type(channel))
    end
    h.noError(function() ns.HandleAddonMessage(ns.PREFIX, "2|H", nil, "Bob") end, "a nil channel")

    -- And the registry is still coherent afterwards.
    h.ok(ns.peers.Bob, "Bob is known")
    h.isNil(ns.peers.Tester, "we are still not our own peer")
end)

h.test("a hostile peer cannot make us answer for a quest we were not asked about",
function(env, ns)
    env.completed[QUEST] = true
    env.completed[1] = true
    ns.HandleAddonMessage(ns.PREFIX, "2|Q|" .. QUEST, "PARTY", "Bob")
    h.eq(#env.sent, 1, "one reply")
    h.eq(env.lastSent(), "2|A|" .. QUEST .. "|1", "about the quest we were asked about")
end)
