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

Peers are keyed by their full normalised "Name-Realm" (ns.PeerKey, in Compat.lua).
The bare name is not an identity: two realms can send the same one, and a
cross-realm namesake of the local player would be mistaken for the player.

ns.PeerLines joins the group roster against this registry so that every surface
lists the whole group -- a member without the addon reads "?  (no addon heard
from)" instead of being absent. It is display only and writes nothing.

Entries are dropped by ns.PrunePeers when the roster changes -- Core calls it on
every GROUP_ROSTER_UPDATE and PLAYER_ENTERING_WORLD. A peer's answers therefore
live exactly as long as they stay in the group, and a stale answer cannot outlive
the session it came from (D2).
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
---@cast ns QT.Namespace

ns.peers = {}

-- key is the peer's full normalised "Name-Realm"; see ns.PeerKey.
--
-- The second return value says whether this call CREATED the entry. Protocol uses
-- it as its fallback rule for answering a presence announcement on a client with
-- no usable clock, where it cannot measure how long it has been quiet.
---@param key string           peer key, from ns.PeerKey
---@param displayName string?  name to show the user, from ns.PeerKey
---@param compatible boolean
---@return QT.Peer
---@return boolean isNew   true only when this call created the entry
function ns.MarkPeer(key, displayName, compatible)
    local p = ns.peers[key]
    local isNew = (p == nil)
    if not p then
        p = { name = displayName or key, answered = {}, onIt = {} }
        ns.peers[key] = p
        ns.Print((displayName or key) .. " has the addon.")
    end
    p.compatible = compatible
    p.lastSeen   = _G.time and _G.time() or 0
    return p, isNew
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
    local members = ns.GroupMembers()
    if not members then return 0 end   -- cannot read the roster: drop nobody
    local inGroup = {}
    for _, m in ipairs(members) do inGroup[m.key] = true end
    local dropped = 0
    for key in pairs(ns.peers) do
        if not inGroup[key] then
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

-- The list every surface shows: the GROUP ROSTER joined against the registry, so
-- that a member we have never heard from appears as "?  (no addon heard from)"
-- rather than being invisible. The distinction matters -- "no addon" and "has the
-- addon but did not answer" are different facts and are worded differently.
--
-- DISPLAY ONLY. Nothing here writes to peer.answered or peer.onIt; ns.RecordAnswer
-- remains the single writer.
--
-- When the roster cannot be read, falls back to listing the peers we have heard
-- from, exactly as before. A roster we cannot read is unknown, not empty -- and an
-- unknown member is never invented as a "no".
---@param questID number
---@return {display: string, state: string}[] rows   may be empty
---@return boolean fromRoster                        false when the roster was unreadable
function ns.PeerLines(questID)
    local rows = {}
    local members = ns.GroupMembers()
    if members then
        for _, m in ipairs(members) do
            if not m.isPlayer then
                local p = ns.peers[m.key]
                local state = "?  (no addon heard from)"
                if p then state = ns.DescribePeerState(p, questID) end
                rows[#rows + 1] = { display = m.display, state = state }
            end
        end
        return rows, true
    end
    for _, p in pairs(ns.peers) do
        rows[#rows + 1] = { display = p.name, state = ns.DescribePeerState(p, questID) }
    end
    return rows, false
end
