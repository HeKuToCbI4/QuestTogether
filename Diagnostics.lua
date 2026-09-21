--[[----------------------------------------------------------------------------
Diagnostics -- in-game verification for the questions still open.

This entire file is meant to be deletable before release. One thing still stands in
the way: /qt help for EVERY command is defined here (and wrapped by UI.lua), so move
the help text out first. Nothing else depends on this file.

It exists because Forever is a beta client whose API surface and event payloads are
still moving, and guessing at those from documentation is how ships sink.

The one-shot measurement probes were retired on 2026-09-21 once their answers were
recorded in docs/MEASUREMENTS.md (API presence, the oracle, the GetInfo schema).
What remains probes the questions still open:

  * /qt events   -- what arguments quest events actually carry (still unverified)
  * /qt frames   -- which Mainline UI frames exist, for M4's hooks
  * /qt sendtest -- what SendAddonMessage returns here (feeds Q4)

It owns its own event frame for quest-event tracing, so Core never learns that
tracing exists. Sharing Core's frame would make this file undeletable.

The rule the project has already been bitten by twice: measure, do not infer.
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
---@cast ns QT.Namespace

ns.commands = ns.commands or {}

------------------------------------------------------------------------------
-- /qt events -- trace quest events with their real arguments
------------------------------------------------------------------------------

ns.tracing = false

local function CmdEvents()
    ns.tracing = not ns.tracing
    if ns.tracing then
        ns.Print("event tracing ON -- accept, open or turn in a quest, then read chat.")
        ns.Print("  watching: QUEST_ACCEPTED, QUEST_TURNED_IN, QUEST_LOG_UPDATE,")
        ns.Print("            QUEST_DETAIL, QUEST_COMPLETE, QUEST_PROGRESS,")
        ns.Print("            GOSSIP_SHOW, QUEST_GREETING")
    else
        ns.Print("event tracing OFF.")
    end
end

ns.commands.events = CmdEvents

------------------------------------------------------------------------------
-- /qt frames -- which UI objects M4 could hook
------------------------------------------------------------------------------

function ns.commands.frames()
    local names = {
        "QuestLogFrame", "QuestLogFrameScrollFrame", "QuestFrame",
        "QuestFrameDetailPanel", "QuestProgressFrame", "GossipFrame",
        "GameTooltip", "UIParent",
    }
    ns.Print("frame objects (M4 would hook these):")
    for _, n in ipairs(names) do
        ns.Print(("  %-26s %s"):format(n, ns.yn(_G[n])))
    end
end

------------------------------------------------------------------------------
-- /qt sendtest -- what does SendAddonMessage actually RETURN on this client?
--
-- Still unmeasured: older builds return a boolean, newer ones an
-- Enum.SendAddonMessageResult code where 0 means success. ns.Send has to read
-- that result, and until this is settled it reads it conservatively (see the
-- table above ns.Send in Protocol.lua). This probe settles it.
--
-- It calls the RAW API on purpose rather than ns.Send, so nothing of ours can
-- reshape the answer. The payload is the ordinary presence announcement, so a
-- send that does go out is harmless -- every peer already handles it.
--
-- Run it solo (a failure here IS the measurement), grouped (expected to
-- succeed), and several times in a row while grouped (looking for a throttle --
-- Q4). Record what it prints in docs/MEASUREMENTS.md.
------------------------------------------------------------------------------

-- Varargs, so that "returned nothing" and "returned nil" stay distinguishable.
local function PrintReturns(ok, ...)
    if not ok then
        ns.Print("  raised an error: " .. ns.SafeStr((...)))
        return
    end
    local n = select("#", ...)
    ns.Print(("  returned %d value(s)"):format(n))
    if n == 0 then
        ns.Print("    (nothing at all -- there is no result to interpret)")
        return
    end
    for i = 1, n do
        local v = (select(i, ...))
        local okType, ty = pcall(type, v)
        ns.Print(("    [%d] %s   type=%s"):format(i, ns.SafeStr(v), okType and ty or "?"))
    end
end

function ns.commands.sendtest()
    if not ns.api.send then
        ns.Print("sendtest: no SendAddonMessage API here -- nothing to measure.")
        return
    end

    local enum = _G.Enum and _G.Enum.SendAddonMessageResult
    ns.Print("sendtest: Enum.SendAddonMessageResult present: " .. ns.yn(type(enum) == "table"))
    if type(enum) == "table" then
        for name, code in pairs(enum) do
            ns.Print(("    %-28s %s"):format(ns.SafeStr(name), ns.SafeStr(code)))
        end
    end

    local channel = ns.GroupChannel()
    if channel then
        ns.Print("  grouped: sending presence to " .. channel .. " -- expected to succeed.")
    else
        channel = "PARTY"
        ns.Print("  solo: sending presence to PARTY anyway -- a failure here IS the measurement.")
    end

    PrintReturns(pcall(ns.api.send, ns.PREFIX, ns.PROTOCOL .. "|H", channel))
end

------------------------------------------------------------------------------
-- /qt help
------------------------------------------------------------------------------

function ns.commands.help()
    ns.Print("v0.0.2 -- commands:")
    ns.Print("  /qt              ask about the quest currently open")
    ns.Print("  /qt ask <id>     ask about a specific quest ID")
    ns.Print("  /qt ping         announce yourself to the group")
    ns.Print("  /qt status       list peers and how much we know")
    ns.Print("-- still-open probes --")
    ns.Print("  /qt events       toggle tracing of quest events and their arguments")
    ns.Print("  /qt frames       list the UI objects M4 would hook")
    ns.Print("  /qt sendtest     print what SendAddonMessage returns here")
end

------------------------------------------------------------------------------
-- Event tracing frame
--
-- Owned here rather than by Core, so deleting this file removes the tracing
-- entirely and Core never knows about it.
------------------------------------------------------------------------------

local TRACED = {
    QUEST_ACCEPTED = true, QUEST_TURNED_IN = true, QUEST_LOG_UPDATE = true,
    QUEST_DETAIL = true, QUEST_COMPLETE = true, QUEST_PROGRESS = true,
    GOSSIP_SHOW = true, QUEST_GREETING = true,
}

local traceFrame = CreateFrame("Frame")
for event in pairs(TRACED) do
    traceFrame:RegisterEvent(event)
end

traceFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if not ns.tracing then return end
    local parts = { event }
    for i = 1, 4 do
        local a = select(i, arg1, arg2, arg3, arg4)
        if a ~= nil then
            parts[#parts + 1] = "arg" .. i .. "=" .. ns.SafeStr(a)
        end
    end
    ns.Print(table.concat(parts, "   "))
end)
