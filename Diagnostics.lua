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

  * /qt events -- what arguments quest events actually carry (still unverified)
  * /qt frames -- which Mainline UI frames exist, for M4's hooks
  * /qt channel -- whether this client knows instance (LFG) groups, and which
    channel ns.GroupChannel would pick right now (still unverified)

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
-- /qt channel -- does this client know instance (LFG) groups?
--
-- Runs solo. The useful reading is taken three times -- alone, in a normal party
-- and in an LFG group -- and recorded in docs/MEASUREMENTS.md. Nothing here
-- assumes the constant exists; every line reports what was actually found.
------------------------------------------------------------------------------

local function Call(fn, ...)
    if not fn then return "no such API" end
    local ok, res = pcall(fn, ...)
    if not ok then return "ERROR: " .. ns.SafeStr(res) end
    return ns.SafeStr(res)
end

function ns.commands.channel()
    local constant = _G.LE_PARTY_CATEGORY_INSTANCE
    local enum     = _G.Enum
    local enumTbl  = enum and enum.PartyCategory
    local viaEnum  = type(enumTbl) == "table" and enumTbl.Instance or nil
    local category = ns.InstancePartyCategory()

    ns.Print("group channel probe:")
    ns.Print(("  LE_PARTY_CATEGORY_INSTANCE   %-3s  value = %s"):format(ns.yn(constant ~= nil), ns.SafeStr(constant)))
    ns.Print(("  Enum.PartyCategory.Instance  %-3s  value = %s"):format(ns.yn(viaEnum ~= nil), ns.SafeStr(viaEnum)))
    ns.Print(("  IsInGroup                    %-3s"):format(ns.yn(_G.IsInGroup)))
    ns.Print(("  IsInRaid                     %-3s"):format(ns.yn(_G.IsInRaid)))

    if category == nil then
        ns.Print("  IsInGroup(<instance>)  ->  not called: no instance category found")
    else
        ns.Print(("  IsInGroup(%s)  ->  %s"):format(ns.SafeStr(category), Call(_G.IsInGroup, category)))
    end
    ns.Print("  IsInGroup()  ->  " .. Call(_G.IsInGroup))
    ns.Print("  IsInRaid()   ->  " .. Call(_G.IsInRaid))
    ns.Print("  channel we would use:  " .. ns.SafeStr(ns.GroupChannel()))
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
    ns.Print("  /qt channel      probe instance-group detection and the channel we would use")
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
