--[[----------------------------------------------------------------------------
Protocol -- the wire format and the transport.

Knows nothing about quests beyond "here is a quest ID". It moves opaque payloads
and enforces the rules; meaning lives elsewhere. (docs/ARCHITECTURE.md D4.)

Wire format v2 -- ASCII, '|' delimited, first field is the protocol revision:

    2|H                         presence announcement
    2|Q|<questID>               "have you completed this?"
    2|A|<questID>|<status>      status: 0 = no, 1 = yes, 2 = on it now

Deliberately small. Batched queries, the bitfield codec and the LOGS state sync
all arrive with v0.2 -- the first two-client test should have as little to go
wrong in it as possible.

Receiving is split in two: ns.ParseMessage is PURE (text in, table or nil out --
no client API, no state, no side effects) and ns.HandleAddonMessage is a thin
dispatcher that decides what to do with the result. That split is what lets the
offline suite in tests/ feed hostile payloads at the format without a client.
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
---@cast ns QT.Namespace

ns.PREFIX       = "QTOG"
ns.PROTOCOL     = 2
ns.REPLY_WINDOW = 3   -- seconds to wait for peers before calling them unknown

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

---@return boolean ok
---@return string? err
function ns.Announce()
    return ns.Send(ns.PROTOCOL .. "|H")
end

------------------------------------------------------------------------------
-- Parsing -- pure
------------------------------------------------------------------------------

-- Nothing longer than this can be one of our messages, so it is dropped before
-- it reaches the parser or the peer registry.
local MAX_MESSAGE_LEN = 200

-- Split on '|' with plain string functions instead of the WoW `strsplit` global,
-- so that ns.ParseMessage stays pure Lua and runs outside the client. The
-- semantics are strsplit's: "2|" gives { "2", "" }, and "" gives { "" }.
---@param text string
---@return string[] fields
local function SplitFields(text)
    local out, from = {}, 1
    while true do
        local at = string.find(text, "|", from, true)
        if not at then
            out[#out + 1] = string.sub(text, from)
            return out
        end
        out[#out + 1] = string.sub(text, from, at - 1)
        from = at + 1
    end
end

-- The revision field on its own. The dispatcher needs it even for a message
-- ns.ParseMessage rejects, because an unknown revision still marks the peer.
---@param text string
---@return string rev
local function RevisionField(text)
    return (string.match(text, "^([^|]*)"))
end

---@class QT.Message
---@field rev integer                 always ns.PROTOCOL; other revisions do not parse
---@field kind "H"|"Q"|"A"
---@field questID integer?            set for "Q" and "A"
---@field status QT.AnswerStatus?     set for "A"

-- PURE: text in, table or nil out. No client API, no state, no side effects --
-- which is what makes the wire format testable offline (tests/test_parser.lua).
--
-- nil means "nothing we can safely act on", and the caller's only correct
-- response is silence. That covers a non-string, an oversized payload, a
-- revision we do not speak, an unknown kind, a quest ID that fails
-- ns.ValidQuestID, and a status outside 0/1/2.
--
-- Trailing fields beyond the ones a kind defines are ignored rather than
-- rejected, which is what the client has always done.
---@param text any            untrusted: it comes from another client
---@return QT.Message? msg    nil for anything malformed
function ns.ParseMessage(text)
    if type(text) ~= "string" then return nil end
    if #text > MAX_MESSAGE_LEN then return nil end

    local f = SplitFields(text)
    if f[1] ~= tostring(ns.PROTOCOL) then return nil end

    local kind = f[2]
    if kind == "H" then
        return { rev = ns.PROTOCOL, kind = "H" }
    end

    if kind == "Q" or kind == "A" then
        local questID = ns.ValidQuestID(f[3])
        if not questID then return nil end
        if kind == "Q" then
            return { rev = ns.PROTOCOL, kind = "Q", questID = questID }
        end
        local status = tonumber(f[4])
        if status ~= 0 and status ~= 1 and status ~= 2 then return nil end
        return { rev = ns.PROTOCOL, kind = "A", questID = questID, status = status }
    end

    return nil
end

------------------------------------------------------------------------------
-- Dispatch
------------------------------------------------------------------------------

-- Inbound. Core calls this inside pcall: a malformed payload from any peer must
-- never throw inside our own session.
---@param prefix any    untrusted: every argument comes from another client
---@param text any
---@param channel any
---@param sender any
function ns.HandleAddonMessage(prefix, text, channel, sender)
    if prefix ~= ns.PREFIX then return end
    if type(text) ~= "string" or #text > MAX_MESSAGE_LEN then return end

    local key = ns.BaseName(sender)
    if not key or key == (_G.UnitName and _G.UnitName("player")) then return end

    -- An unknown revision: remember them, mark them incompatible, and skip. We
    -- cannot safely parse a format we do not know, and guessing risks sending a
    -- reply they would misread. Marking beats answering.
    local compatible = (RevisionField(text) == tostring(ns.PROTOCOL))
    ns.MarkPeer(key, sender, compatible)
    if not compatible then return end

    local msg = ns.ParseMessage(text)
    if not msg then return end

    if msg.kind == "Q" then
        local done = ns.SafeIsDone(msg.questID)
        if done == nil then return end   -- stay silent; the asker keeps showing "?"

        -- status: 1 = completed, 2 = on it now, 0 = neither. "On it" is cheap
        -- (one log lookup) and always computable, unlike eligibility -- which the
        -- 2026-09-21 probe showed has NO general API on this client.
        local status = 0
        if done then
            status = 1
        elseif ns.api.logIdxForId then
            local ok, idx = pcall(ns.api.logIdxForId, msg.questID)
            if ok and idx then status = 2 end
        end
        ns.Send(ns.PROTOCOL .. "|A|" .. msg.questID .. "|" .. status, channel)

    elseif msg.kind == "A" then
        local peer = ns.RecordAnswer(key, msg.questID, msg.status)
        if ns.onAnswer then ns.onAnswer(peer, msg.questID, msg.status) end
    end
    -- "H" needs no handling: MarkPeer above already recorded the peer.
end
