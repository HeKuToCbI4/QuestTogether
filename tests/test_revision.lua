--[[----------------------------------------------------------------------------
An unknown protocol revision.

We cannot safely read a format we do not know, and guessing risks sending a
reply the other side would misread. So: remember them, mark them incompatible,
answer nothing, parse nothing.
------------------------------------------------------------------------------]]

local h = require("harness")

local QUEST = 92460

local function receive(ns, text, sender)
    ns.HandleAddonMessage(ns.PREFIX, text, "PARTY", sender or "Bob")
end

h.test("an unknown revision marks the peer incompatible", function(_, ns)
    receive(ns, "1|H")
    local peer = ns.peers.Bob
    h.ok(peer, "the peer is still remembered")
    h.isFalse(peer.compatible, "compatible")
end)

h.test("an unknown revision is never answered", function(env, ns)
    env.completed[QUEST] = true
    receive(ns, "1|Q|" .. QUEST)
    receive(ns, "3|Q|" .. QUEST)
    receive(ns, "99|Q|" .. QUEST)
    h.eq(#env.sent, 0, "nothing was sent")
    h.isFalse(ns.peers.Bob.compatible, "and they are marked incompatible")
end)

h.test("an unknown revision caches nothing", function(_, ns)
    receive(ns, "1|A|" .. QUEST .. "|0")
    receive(ns, "3|A|" .. QUEST .. "|1")
    local peer = ns.peers.Bob
    h.eq(h.count(peer.answered), 0, "no answers cached")
    h.isNil(peer.answered[QUEST], "the quest is unknown, not false")
end)

h.test("the parser rejects an unknown revision outright", function(_, ns)
    h.isNil(ns.ParseMessage("1|H"), "revision 1")
    h.isNil(ns.ParseMessage("3|A|" .. QUEST .. "|1"), "revision 3")
    h.isNil(ns.ParseMessage("02|H"), "a revision that only looks like ours")
end)

h.test("a peer can go from compatible to incompatible and back", function(_, ns)
    receive(ns, "2|H")
    h.isTrue(ns.peers.Bob.compatible, "first message: compatible")
    receive(ns, "1|H")
    h.isFalse(ns.peers.Bob.compatible, "then incompatible")
    receive(ns, "2|H")
    h.isTrue(ns.peers.Bob.compatible, "and compatible again")
end)

h.test("our own announcement carries the current revision", function(env, ns)
    local ok = ns.Announce()
    h.isTrue(ok, "Announce succeeded")
    h.eq(env.lastSent(), ns.PROTOCOL .. "|H", "payload")
    h.eq(env.sent[1].prefix, ns.PREFIX, "prefix")
    h.eq(env.sent[1].channel, "PARTY", "channel")
end)

h.test("nothing is sent when we are not in a group", { inGroup = false }, function(env, ns)
    local ok, err = ns.Announce()
    h.isFalse(ok, "Announce failed")
    h.eq(err, "not in a group", "reason")
    h.eq(#env.sent, 0, "nothing was sent")
end)
