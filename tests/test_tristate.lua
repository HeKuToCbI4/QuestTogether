--[[----------------------------------------------------------------------------
The tri-state invariant, driven through the real receive path.

    true    confirmed completed
    false   confirmed NOT completed
    nil     unknown

The rule these tests exist to defend (CLAUDE.md rule 1): nothing may turn an
absent answer into `false`. Only an "A" message carrying status 0 or 2 may write
a `false`, and only for the quest it names.
------------------------------------------------------------------------------]]

local h = require("harness")

local QUEST, OTHER = 92460, 12345

local function receive(ns, text, sender)
    ns.HandleAddonMessage(ns.PREFIX, text, "PARTY", sender or "Bob")
end

------------------------------------------------------------------------------
-- What an answer writes
------------------------------------------------------------------------------

h.test("status 1 records a confirmed yes", function(_, ns)
    receive(ns, "2|H")
    receive(ns, "2|A|" .. QUEST .. "|1")
    local peer = ns.peers.Bob
    h.isTrue(peer.answered[QUEST], "answered")
    h.isNil(peer.onIt[QUEST], "onIt")
    h.eq(ns.DescribePeerState(peer, QUEST), "yes - already completed", "rendering")
end)

h.test("status 0 records a confirmed no", function(_, ns)
    receive(ns, "2|A|" .. QUEST .. "|0")
    local peer = ns.peers.Bob
    h.isFalse(peer.answered[QUEST], "answered")
    h.isNil(peer.onIt[QUEST], "onIt")
    h.eq(ns.DescribePeerState(peer, QUEST), "no - has not completed it", "rendering")
end)

h.test("status 2 records a no plus 'on it now'", function(_, ns)
    receive(ns, "2|A|" .. QUEST .. "|2")
    local peer = ns.peers.Bob
    h.isFalse(peer.answered[QUEST], "answered")
    h.isTrue(peer.onIt[QUEST], "onIt")
    h.eq(ns.DescribePeerState(peer, QUEST), "on it now", "rendering")
end)

h.test("a later yes clears an earlier 'on it now'", function(_, ns)
    receive(ns, "2|A|" .. QUEST .. "|2")
    receive(ns, "2|A|" .. QUEST .. "|1")
    local peer = ns.peers.Bob
    h.isTrue(peer.answered[QUEST], "answered")
    h.isNil(peer.onIt[QUEST], "onIt is cleared")
end)

h.test("an answer only touches the quest it names", function(_, ns)
    receive(ns, "2|A|" .. QUEST .. "|0")
    local peer = ns.peers.Bob
    h.isFalse(peer.answered[QUEST], "the named quest")
    h.isNil(peer.answered[OTHER], "any other quest stays unknown")
end)

------------------------------------------------------------------------------
-- What must NOT write
------------------------------------------------------------------------------

h.test("presence and queries alone leave every quest unknown", function(_, ns)
    receive(ns, "2|H")
    receive(ns, "2|Q|" .. QUEST)
    receive(ns, "2|H")
    receive(ns, "2|Q|" .. OTHER)
    local peer = ns.peers.Bob
    h.ok(peer, "the peer is known")
    h.isNil(peer.answered[QUEST], "answered stays nil")
    h.isNil(peer.answered[OTHER], "answered stays nil for the other quest")
    h.eq(h.count(peer.answered), 0, "nothing at all was written")
    h.eq(ns.DescribePeerState(peer, QUEST), "?  (no answer)", "rendering")
end)

-- The invariant, swept. Every message below is one that must not be able to
-- produce a `false`: wrong revision, wrong kind, bad quest ID, bad status,
-- truncated, oversized, an answer about a DIFFERENT quest.
h.test("no sequence of non-answers can write a false", function(_, ns)
    local messages = {
        "2|H", "2|Q|" .. QUEST, "2|Q|" .. OTHER, "2|A|" .. OTHER .. "|0",
        "2|A|" .. OTHER .. "|2", "1|A|" .. QUEST .. "|0", "3|A|" .. QUEST .. "|0",
        "2|A|" .. QUEST .. "|3", "2|A|" .. QUEST .. "|-1", "2|A|" .. QUEST .. "|x",
        "2|A|" .. QUEST, "2|A|" .. QUEST .. "|", "2|a|" .. QUEST .. "|0",
        "2|Z|" .. QUEST .. "|0", "2|A|0|0", "2|A|-1|0", "2|A|1.5|0",
        "", "2", "2|", "|", "2|A|" .. QUEST .. "|0" .. string.rep("x", 250),
    }
    for _, text in ipairs(messages) do
        receive(ns, text)
        local peer = ns.peers.Bob
        if peer then
            h.neq(peer.answered[QUEST], false, "after " .. h.show(text) .. " the answer")
        end
    end

    local peer = ns.peers.Bob
    h.isNil(peer.answered[QUEST], "the quest under test is still unknown")
    h.isFalse(peer.answered[OTHER], "the quest that WAS answered is a confirmed no")
end)

h.test("a malformed answer does not overwrite a good one", function(_, ns)
    receive(ns, "2|A|" .. QUEST .. "|1")
    receive(ns, "2|A|" .. QUEST .. "|9")
    receive(ns, "2|A|" .. QUEST .. "|x")
    receive(ns, "2|A|" .. QUEST)
    h.isTrue(ns.peers.Bob.answered[QUEST], "the confirmed yes survives")
end)

------------------------------------------------------------------------------
-- Current behaviour, asserted so a change is noticed
------------------------------------------------------------------------------

-- Every message from a non-self sender marks the peer BEFORE the kind is looked
-- at, so an "A" from someone we have never heard from creates the peer and is
-- then recorded. ns.RecordAnswer's "nil when the key was never marked" guard
-- can therefore never fire from this path.
h.test("an answer from a never-seen sender is recorded (current behaviour)", function(env, ns)
    h.eq(h.count(ns.peers), 0, "no peers to start with")
    receive(ns, "2|A|" .. QUEST .. "|1", "Carol")
    local peer = ns.peers.Carol
    h.ok(peer, "the sender was created by their own answer")
    h.isTrue(peer.answered[QUEST], "and the answer was recorded")
    h.eq(env.prints[1], "|cff33ff99Quest Together|r Carol has the addon.", "the peer was announced")
end)

h.test("a cross-realm peer is keyed by their full Name-Realm", function(_, ns)
    receive(ns, "2|A|" .. QUEST .. "|1", "Carol-Ravencrest")
    local peer = ns.peers["Carol-Ravencrest"]
    h.ok(peer, "keyed by the full name")
    h.eq(peer.name, "Carol-Ravencrest", "display name")
    h.isNil(ns.peers.Carol, "not keyed by the bare name")
end)

h.test("an incompatible peer renders as unknown whatever is cached", function(_, ns)
    receive(ns, "2|A|" .. QUEST .. "|0")
    receive(ns, "1|H")
    local peer = ns.peers.Bob
    h.isFalse(peer.compatible, "marked incompatible")
    h.eq(ns.DescribePeerState(peer, QUEST), "?  (incompatible addon version)", "rendering")
end)
