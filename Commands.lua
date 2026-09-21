--[[----------------------------------------------------------------------------
Commands -- the user-facing slash commands that do real work.

Registered into ns.commands, a table Core dispatches into. Diagnostics.lua adds
its own entries to the same table.

Convention: every module that contributes commands does
    ns.commands = ns.commands or {}
first, so that load order never matters.
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
---@cast ns QT.Namespace

ns.commands = ns.commands or {}

local askedQuest = nil   -- quest ID of the most recent ask, for live reporting

-- Protocol calls this when any peer answers us. Printing live during a request
-- is presentation, so it lives here rather than in the transport layer.
ns.onAnswer = function(peer, questID)
    if peer and questID == askedQuest then
        ns.Print("  " .. peer.name .. ": " .. ns.DescribePeerState(peer, questID))
    end
end

-- Driven by the group roster (ns.PeerLines), not by the peers we happen to have
-- heard from, so a member without the addon is listed as "?" rather than omitted.
local function Report(questID)
    local rows = ns.PeerLines(questID)
    if #rows == 0 then
        -- Nothing to list has two very different causes; ns.GroupChannel tells
        -- them apart (wording from docs/UX.md).
        if ns.GroupChannel() then
            ns.Print("None of your group has Quest Together.")
        else
            ns.Print("Not in a group.")
        end
        return
    end
    ns.Print("Quest " .. questID .. ":")
    for _, r in ipairs(rows) do
        ns.Print("  " .. r.display .. ": " .. r.state)
    end
end

-- Shared ask, used by both /qt and the UI's auto-ask. Returns ok, err so a
-- caller can choose to report the failure (manual /qt does) or stay quiet
-- (auto-ask need not tell the user they are not in a group).
---@param questID number?
---@return boolean ok
---@return string? err   set only when ok is false
function ns.Ask(questID)
    if not questID then return false, "no quest" end
    -- Validate first: an invalid ID must not reach the wire, and askedQuest must
    -- not be set by an ask that never left the machine.
    questID = ns.ValidQuestID(questID)
    if not questID then return false, "invalid quest ID" end
    askedQuest = questID
    local ok, err = ns.Send(ns.PROTOCOL .. "|Q|" .. questID)
    if not ok then return false, err end

    ns.Print("Asking your group about quest " .. questID .. "...")
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(ns.REPLY_WINDOW, function() Report(questID) end)
    else
        Report(questID)
    end
    return true
end

function ns.commands.ask(rest)
    local questID = tonumber(rest) or ns.LocalQuestID()
    if not questID then
        ns.Print("No quest selected. Open a quest at an NPC, or use /qt ask <questID>.")
        return
    end
    local ok, err = ns.Ask(questID)
    if not ok then
        ns.Print("Cannot ask: " .. err)
    end
end

function ns.commands.ping()
    if not ns.RegisterPrefix() then
        ns.Print("Prefix is not registered -- addon messaging is unavailable.")
        return
    end
    local ok, err = ns.Announce()
    if not ok then
        ns.Print("Cannot announce: " .. err)
        return
    end
    ns.Print("Announced to the group. Replies will appear as members are heard from.")
end

function ns.commands.status()
    if next(ns.peers) == nil then
        ns.Print("No peers heard from yet. Try /qt ping while grouped.")
        return
    end
    for _, p in pairs(ns.peers) do
        local n = 0
        for _ in pairs(p.answered) do n = n + 1 end
        ns.Print(("%s  %s  (%d answers cached)"):format(
            p.name, p.compatible and "compatible" or "INCOMPATIBLE", n))
    end
end

ns.commands[""] = ns.commands.ask
