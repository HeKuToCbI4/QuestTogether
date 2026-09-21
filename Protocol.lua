--[[----------------------------------------------------------------------------
Protocol -- the wire format and the transport.

Knows nothing about quests beyond "here is a quest ID". It moves opaque payloads
and enforces the rules; meaning lives elsewhere. (PLAN.md D4.)

Wire format v2 -- ASCII, '|' delimited, first field is the protocol revision:

    2|H                         presence announcement
    2|Q|<questID>               "have you completed this?"
    2|A|<questID>|<status>      status: 0 = no, 1 = yes, 2 = on it now

Deliberately small. Batched queries, the bitfield codec and the LOGS state sync
all arrive with v0.2 -- the first two-client test should have as little to go
wrong in it as possible.
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

ns.PREFIX       = "QTOG"
ns.PROTOCOL     = 2
ns.REPLY_WINDOW = 3   -- seconds to wait for peers before calling them unknown

-- ns.onAnswer is declared in Compat.lua and installed by Commands.lua. Protocol
-- only ever reads it. Keeps presentation out of the transport: Protocol reports
-- the fact, whoever cares decides what to show.
--
-- Do NOT initialise it here. Assigning `ns.onAnswer = nil` at load would wipe
-- whatever Commands had set, quietly making the .toc's file order load-bearing.

local registered = false

function ns.IsPrefixRegistered() return registered end

function ns.RegisterPrefix()
    if registered then return true end
    if not ns.api.register then return false end
    registered = pcall(ns.api.register, ns.PREFIX) and true or false
    return registered
end

function ns.Send(payload, channel)
    channel = channel or ns.GroupChannel()
    if not channel then return false, "not in a group" end
    if not ns.api.send then return false, "no SendAddonMessage API" end
    local ok, err = pcall(ns.api.send, ns.PREFIX, payload, channel)
    if not ok then return false, tostring(err) end
    return true
end

function ns.Announce()
    return ns.Send(ns.PROTOCOL .. "|H")
end

-- Inbound. Core calls this inside pcall: a malformed payload from any peer must
-- never throw inside our own session.
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
    ns.MarkPeer(key, sender, compatible)
    if not compatible then return end

    if kind == "Q" then
        local qid = tonumber(f3)
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
        local qid = tonumber(f3)
        local status = tonumber(f4)
        if not qid or status == nil then return end
        if status ~= 0 and status ~= 1 and status ~= 2 then return end
        local peer = ns.RecordAnswer(key, qid, status)
        if ns.onAnswer then ns.onAnswer(peer, qid, status) end
    end
    -- "H" needs no handling: MarkPeer above already recorded the peer.
end
