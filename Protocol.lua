--[[----------------------------------------------------------------------------
Protocol -- the wire format and the transport.

Knows nothing about quests beyond "here is a quest ID". It moves opaque payloads
and enforces the rules; meaning lives elsewhere. (docs/ARCHITECTURE.md D4.)

Wire format v2 -- ASCII, '|' delimited, first field is the protocol revision:

    2|H                         presence announcement
    2|Q|<questID>               "have you completed this?"
    2|A|<questID>|<status>      status: 0 = no, 1 = yes, 2 = on it now

Outbound `H` is debounced (ns.AnnounceSoon): GROUP_ROSTER_UPDATE fires far more
often than people join or leave, so a burst of roster events becomes one message.
An inbound `H` is answered with our own `H` when we have been QUIET -- when we have
not announced in the last ns.ANNOUNCE_QUIET seconds -- and ignored otherwise. That
is what lets a client whose peer list is empty (after a /reload) fill back in: it
announces, everyone still quiet answers, and it hears them. It cannot loop, because
answering makes us not quiet. Receiving an `H` is otherwise unchanged, so the wire
format and ns.PROTOCOL are untouched.

Deliberately small. Batched queries, the bitfield codec and the LOGS state sync
all arrive with v0.2 -- the first two-client test should have as little to go
wrong in it as possible.
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
---@cast ns QT.Namespace

ns.PREFIX            = "QTOG"
ns.PROTOCOL          = 2
ns.REPLY_WINDOW      = 3   -- seconds to wait for peers before calling them unknown
ns.ANNOUNCE_DEBOUNCE = 3   -- seconds; at most one automatic `H` per window
-- Seconds of our own silence before we will answer somebody else's `H`. MUST stay
-- comfortably above ANNOUNCE_DEBOUNCE plus the maximum jitter (3 + 2 = 5), or an
-- answer could land after the window it was meant to close and the two clients
-- would answer each other in turn forever.
ns.ANNOUNCE_QUIET    = 10

-- Every quest ID we touch arrives from another client, so it is hostile input
-- (CLAUDE.md rule 5). `tonumber` alone is not a validator: it happily turns 0,
-- negatives, fractions and inf/NaN into numbers, any of which would then reach
-- the oracle and the peer cache. Zero is the dangerous one --
-- docs/MEASUREMENTS.md records IsQuestFlaggedCompleted(0) answering `false`
-- rather than raising, so an unvalidated 0 broadcasts "not completed" for
-- something that is not a quest at all.
--
-- The bound is a sanity limit, not a claim about the quest ID space: a large but
-- in-range value (1e9, say) is accepted, because rejecting it would buy nothing
-- and could refuse a legitimate future ID.
--
-- A rejected ID is ignored in silence: the asker keeps showing "?", which is the
-- honest answer. Inventing a reply on their behalf would be worse than saying
-- nothing.
local MAX_QUEST_ID = 2 ^ 31 - 1

---@param v any
---@return integer? id   nil when v is not a usable quest ID
function ns.ValidQuestID(v)
    local id = tonumber(v)
    if not id then return nil end
    if id % 1 ~= 0 then return nil end                     -- fractions, NaN, +/-inf
    if id <= 0 or id > MAX_QUEST_ID then return nil end
    return id
end

-- ns.onAnswer is declared in Compat.lua and installed by Commands.lua. Protocol
-- only ever reads it. Keeps presentation out of the transport: Protocol reports
-- the fact, whoever cares decides what to show.
--
-- Do NOT initialise it here. Assigning `ns.onAnswer = nil` at load would wipe
-- whatever Commands had set, quietly making the .toc's file order load-bearing.

local registered = false

-- Debounce state for ns.AnnounceSoon. `lastAnnounceAt` stays nil until we have
-- actually sent something, so a missing clock (ns.Now() == 0) reads as "never
-- announced" rather than as "always inside the window".
local announcePending = false
local lastAnnounceAt  = nil

---@return boolean
function ns.IsPrefixRegistered() return registered end

---@return boolean registered
function ns.RegisterPrefix()
    if registered then return true end
    if not ns.api.register then return false end
    registered = pcall(ns.api.register, ns.PREFIX) and true or false
    return registered
end

---@param payload string
---@param channel? string   defaults to ns.GroupChannel()
---@return boolean ok
---@return string? err    set only when ok is false
function ns.Send(payload, channel)
    channel = channel or ns.GroupChannel()
    if not channel then return false, "not in a group" end
    if not ns.api.send then return false, "no SendAddonMessage API" end
    local ok, err = pcall(ns.api.send, ns.PREFIX, payload, channel)
    if not ok then return false, tostring(err) end
    return true
end

-- Announce right now. Used by /qt ping, which is manual and explicit and should
-- never feel laggy. Everything automatic goes through ns.AnnounceSoon instead.
---@return boolean ok
---@return string? err
function ns.Announce()
    local ok, err = ns.Send(ns.PROTOCOL .. "|H")
    if ok then lastAnnounceAt = ns.Now() end
    return ok, err
end

-- Trailing-edge debounce over ns.Announce.
--
-- The first call opens a window; every call inside it is absorbed, and ONE `H`
-- goes out when the window closes. That is what makes a raid's burst of
-- GROUP_ROSTER_UPDATEs -- role, online and zone changes all fire it -- cost one
-- message instead of a dozen, and it is also what keeps our answers to several
-- peers' announcements down to one message.
--
-- Trailing rather than leading on purpose: presence is state, not an event
-- (docs/PROTOCOL.md, "Sync state, not events"), so the LAST send of a burst is
-- the one that matters and arriving a few seconds late costs nothing.
--
-- `extra` exists for the reply path: every client that heard the same `H` would
-- otherwise close its window in the same frame and answer in unison.
---@param extra? number      extra seconds (jitter) on top of the window
---@return boolean scheduled false when an announcement is already pending, or
---                          when the rate limit dropped this one
function ns.AnnounceSoon(extra)
    if announcePending then return false end

    extra = tonumber(extra)
    if not extra or extra < 0 then extra = 0 end

    local after = _G.C_Timer and _G.C_Timer.After
    if not after then
        -- No timer API (not expected on this client -- C_Timer.After is measured
        -- present -- but the surface may shift). Nothing can be deferred, so fall
        -- back to a plain rate limit: send now if the window has passed, else
        -- drop. Dropping is safe because presence is state; the next roster event
        -- sends it again.
        local now = ns.Now()
        if lastAnnounceAt and (now - lastAnnounceAt) < ns.ANNOUNCE_DEBOUNCE then
            return false
        end
        ns.Announce()
        return true
    end

    announcePending = true
    local ok = pcall(after, ns.ANNOUNCE_DEBOUNCE + extra, function()
        announcePending = false
        -- Re-check at fire time, not at schedule time: the roster may have
        -- changed again and we may now be alone.
        if ns.GroupChannel() then ns.Announce() end
    end)
    if not ok then announcePending = false end
    return ok
end

-- Should we answer an inbound `H`?
--
-- Yes when we have been quiet -- no announcement of our own in the last
-- ns.ANNOUNCE_QUIET seconds. That is the rule that gets a reloaded client its peer
-- list back: it announces, everyone who has been quiet answers, and it hears them.
--
-- It cannot run away, because answering is itself an announcement: the moment we
-- reply we stop being quiet, so the reply to our reply (and every `H` for the next
-- ANNOUNCE_QUIET seconds) is ignored. A chain is therefore at most one round.
--
-- Without a clock we cannot measure quiet at all, so we fall back to the narrower
-- rule of answering only a peer we had never heard of. That is weaker -- it misses
-- the reload case -- but it is still loop-free, which matters more.
---@param isNew boolean   whether this message created the peer entry
---@return boolean
local function ShouldAnswerHello(isNew)
    local now = ns.Now()
    if now == 0 then return isNew end
    if not lastAnnounceAt then return true end
    return (now - lastAnnounceAt) >= ns.ANNOUNCE_QUIET
end

-- Inbound. Core calls this inside pcall: a malformed payload from any peer must
-- never throw inside our own session.
---@param prefix any    untrusted: every argument comes from another client
---@param text any
---@param channel any
---@param sender any
function ns.HandleAddonMessage(prefix, text, channel, sender)
    if prefix ~= ns.PREFIX then return end
    if type(text) ~= "string" or #text > 200 then return end

    local key = ns.BaseName(sender)
    if not key or key == (_G.UnitName and _G.UnitName("player")) then return end

    local rev, kind, f3, f4 = strsplit("|", text)

    -- An unknown revision: remember them, mark them incompatible, and skip. We
    -- cannot safely parse a format we do not know, and guessing risks sending a
    -- reply they would misread. Marking beats answering.
    local compatible = (rev == tostring(ns.PROTOCOL))
    local _, isNew = ns.MarkPeer(key, sender, compatible)
    if not compatible then return end

    if kind == "H" then
        -- Answer, so the sender learns about us too. Without this a client that
        -- has just /reloaded has an empty peer list and stays that way until
        -- traffic happens to arrive -- everyone else heard it, it heard nobody.
        --
        -- Only while we are quiet (see ShouldAnswerHello), which is what keeps two
        -- clients from answering each other forever. The jitter is so that N
        -- clients that all heard the same `H` do not reply in the same frame; the
        -- debounce then folds their own burst into a single message.
        if ShouldAnswerHello(isNew) then ns.AnnounceSoon(0.5 + math.random() * 1.5) end

    elseif kind == "Q" then
        local qid = ns.ValidQuestID(f3)
        if not qid then return end
        local done = ns.SafeIsDone(qid)
        if done == nil then return end   -- stay silent; the asker keeps showing "?"

        -- status: 1 = completed, 2 = on it now, 0 = neither. "On it" is cheap
        -- (one log lookup) and always computable, unlike eligibility -- which the
        -- 2026-09-21 probe showed has NO general API on this client.
        local status = 0
        if done then
            status = 1
        elseif ns.api.logIdxForId then
            local ok, idx = pcall(ns.api.logIdxForId, qid)
            if ok and idx then status = 2 end
        end
        ns.Send(ns.PROTOCOL .. "|A|" .. qid .. "|" .. status, channel)

    elseif kind == "A" then
        local qid = ns.ValidQuestID(f3)
        local status = tonumber(f4)
        if not qid or status == nil then return end
        if status ~= 0 and status ~= 1 and status ~= 2 then return end
        local peer = ns.RecordAnswer(key, qid, status)
        if ns.onAnswer then ns.onAnswer(peer, qid, status) end
    end
end
