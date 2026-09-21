--[[----------------------------------------------------------------------------
Peers -- who is in the group, and what we know about them.

Peer state is SESSION-SCOPED by design (PLAN.md D2): a peer's completion state is
only trusted while they stay in the group. They may have completed quests since,
so entries are dropped on roster change and re-established.

THE TRI-STATE INVARIANT LIVES HERE. peers[key].answered[questID] is:

    true    confirmed completed
    false   confirmed NOT completed
    nil     unknown -- no addon, incompatible revision, or no reply in time

A boolean is written ONLY by ns.RecordAnswer, from an actually-received reply.
Nothing may default an absent key to false. That collapse is the single mistake
this addon exists to prevent, and funnelling every write through one function is
how we make it impossible rather than merely discouraged.

peers[key].onIt[questID] is a secondary flag set only alongside a confirmed
`false`: it marks "this peer has the quest in their log right now" (rendered as
"on it now"). It never upgrades an unknown into a definite answer.

NOTE (v0.2): dropping entries when a peer leaves is not implemented yet. For now
a peer persists for the session, which is correct-but-stale in the narrow case
where they complete quests after answering.
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

ns.peers = {}

-- key is the peer's bare name; see ns.BaseName.
function ns.MarkPeer(key, displayName, compatible)
    local p = ns.peers[key]
    if not p then
        p = { name = displayName or key, answered = {}, onIt = {} }
        ns.peers[key] = p
        ns.Print((displayName or key) .. " has the addon.")
    end
    p.compatible = compatible
    p.lastSeen   = _G.time and _G.time() or 0
    return p
end

-- The ONLY writer of an answer. Everything else only reads.
-- status: 1 = completed, 2 = on it now, 0 = neither. Returns the peer so callers
-- can report on it immediately.
function ns.RecordAnswer(key, questID, status)
    local p = ns.peers[key]
    if not p then return nil end
    if status == 1 then
        p.answered[questID] = true
        p.onIt[questID] = nil
    elseif status == 2 then
        p.answered[questID] = false
        p.onIt[questID] = true
    else
        p.answered[questID] = false
        p.onIt[questID] = nil
    end
    return p
end

function ns.DescribePeerState(peer, questID)
    if not peer.compatible then return "?  (incompatible addon version)" end
    local v = peer.answered[questID]
    if v == true  then return "yes - already completed" end
    if v == false then
        if peer.onIt and peer.onIt[questID] then return "on it now" end
        return "no - has not completed it"
    end
    -- Absent means we never got an answer. Rendering that as "no" is the single
    -- mistake this addon exists to prevent.
    return "?  (no answer)"
end
