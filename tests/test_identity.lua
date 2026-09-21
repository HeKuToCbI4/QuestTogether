--[[----------------------------------------------------------------------------
Peer identity -- one character, one key, however the client spells them.

Regression for issue #24, measured with two clients on 2026-09-21: names on this
client can contain a space. The addon-message sender keeps the space
("Itemys Targaryen-ClassicBetaPvE") while the group roster hands back
"Itemys-Targaryen", which looks exactly like Name-Realm. The two used to get
different keys, so a peer who had just answered was summarised as
"?  (no addon heard from)" and pruned on every roster change.
------------------------------------------------------------------------------]]

local h = require("harness")

local QUEST = 783
local REALM = "ClassicBetaPvE"

-- The harness only restores the globals it installed, so the realm stub is set
-- and cleared by hand around each body.
local function withRealm(fn)
    return function(env, ns)
        _G.GetNormalizedRealmName = function() return REALM end
        local ok, err = pcall(fn, env, ns)
        _G.GetNormalizedRealmName = nil
        if not ok then error(err, 0) end
    end
end

h.test("every spelling of one spaced name gives one key", withRealm(function(_, ns)
    local want = ns.PeerKey("Itemys Targaryen-" .. REALM)
    h.ok(want, "the sender spelling gives a key")
    h.eq(ns.PeerKey("Itemys Targaryen"), want, "sender without a realm")
    h.eq(ns.PeerKey("Itemys-Targaryen"), want, "roster spelling, surname after a hyphen")
    h.eq(ns.PeerKey("Itemys", "Targaryen"), want, "roster spelling, surname in the realm slot")
    h.eq(ns.PeerKey("Itemys Targaryen", REALM), want, "UnitFullName spelling")
    h.eq(ns.PeerKey("Itemys Targaryen", "Classic Beta PvE"), ns.PeerKey("Itemys Targaryen-ClassicBetaPvE"),
        "a realm with spaces is normalised")
end))

h.test("a different realm is still a different peer", withRealm(function(_, ns)
    h.ok(ns.PeerKey("Ana-Ravencrest") ~= ns.PeerKey("Ana"), "cross-realm namesake")
    h.eq(ns.PeerKey("Ana-Ravencrest"), ns.PeerKey("Ana", "Ravencrest"), "both shapes of a cross-realm name")
end))

h.test("the display name keeps its spelling, minus our own realm", withRealm(function(_, ns)
    local _, shown = ns.PeerKey("Itemys Targaryen-" .. REALM)
    h.eq(shown, "Itemys Targaryen", "own realm is not shown")
    local _, across = ns.PeerKey("Ana-Ravencrest")
    h.eq(across, "Ana-Ravencrest", "another realm is shown")
end))

h.test("separators alone are not a name", withRealm(function(_, ns)
    for _, junk in ipairs({ "-", " ", "- -", "-" .. REALM, "" }) do
        h.isNil(ns.PeerKey(junk), "rejected: [" .. junk .. "]")
    end
end))

h.test("a spaced-name peer who answered is matched by the roster summary", withRealm(function(env, ns)
    env.groupNames.party1 = "Itemys-Targaryen"          -- what the roster handed us
    ns.HandleAddonMessage(ns.PREFIX, "2|A|" .. QUEST .. "|0", "PARTY", "Itemys Targaryen-" .. REALM)

    local rows, fromRoster = ns.PeerLines(QUEST)
    h.isTrue(fromRoster, "the list came from the roster")
    h.eq(#rows, 1, "one group member besides us")
    h.eq(rows[1].state, "no - has not completed it", "their real answer, not 'no addon heard from'")
    h.eq(rows[1].display, "Itemys Targaryen", "shown with the spelling from their own message")
end))

h.test("a spaced-name peer survives pruning", withRealm(function(env, ns)
    env.groupNames.party1 = "Itemys-Targaryen"
    ns.HandleAddonMessage(ns.PREFIX, "2|H", "PARTY", "Itemys Targaryen-" .. REALM)
    h.eq(ns.PrunePeers(), 0, "nobody was dropped")
    h.eq(h.count(ns.peers), 1, "the peer is still there")
end))

h.test("our own spaced name is still us", withRealm(function(env, ns)
    env.player = "Itemys Targaryen"
    ns.HandleAddonMessage(ns.PREFIX, "2|Q|" .. QUEST, "PARTY", "Itemys Targaryen-" .. REALM)
    h.eq(h.count(ns.peers), 0, "we did not become our own peer")
    h.eq(#env.sent, 0, "we did not answer ourselves")
end))
