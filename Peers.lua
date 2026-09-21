--[[----------------------------------------------------------------------------
Peers -- who is in the group, and what we know about them.

Peer state is SESSION-SCOPED by design (docs/ARCHITECTURE.md D2): a peer's completion state is
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

Entries are dropped by ns.PrunePeers when the roster changes -- Core calls it on
every GROUP_ROSTER_UPDATE and PLAYER_ENTERING_WORLD. A peer's answers therefore
live exactly as long as they stay in the group, and a stale answer cannot outlive
the session it came from (D2).
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
---@cast ns QT.Namespace

ns.peers = {}

-- key is the peer's bare name; see ns.BaseName.
---@param key string           bare name, from ns.BaseName
---@param displayName string?  sender as it arrived
---@param compatible boolean
---@return QT.Peer
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

-- Drop every peer who is no longer in the group. This enforces D2: an answer is
-- trusted only while they stay in the group, because they may have completed
-- quests since and we would have no way to know. Dropping is the honest response
-- -- keeping a stale "no" is the failure this addon exists to prevent.
--
-- Deletion lives here, beside the single writer, so the registry keeps one owner.
-- Called by Core on every roster change.
---@return integer dropped
function ns.PrunePeers()
    local members = ns.GroupMemberNames()
    if not members then return 0 end   -- cannot read the roster: drop nobody
    local dropped = 0
    for key in pairs(ns.peers) do
        if not members[key] then
            ns.peers[key] = nil
            dropped = dropped + 1
        end
    end
    return dropped
end

-- The ONLY writer of an answer. Everything else only reads.
-- status: 1 = completed, 2 = on it now, 0 = neither. Returns the peer so callers
-- can report on it immediately.
---@param key string
---@param questID number
---@param status QT.AnswerStatus
---@return QT.Peer? peer   nil when the key was never marked
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

---@param peer QT.Peer
---@param questID number
---@return string
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
