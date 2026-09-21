--[[----------------------------------------------------------------------------
Diagnostics -- in-game verification for the questions still open.

This entire file is meant to be deletable before release: delete it, drop its line
from the .toc, and nothing else changes. Its commands register into ns.commands
and their help lines into ns.helpLines, so /qt help simply stops listing them.
Nothing anywhere depends on this file.

It exists because Forever is a beta client whose API surface and event payloads are
still moving, and guessing at those from documentation is how ships sink.

The one-shot measurement probes were retired on 2026-09-21 once their answers were
recorded in docs/MEASUREMENTS.md (API presence, the oracle, the GetInfo schema).
What remains probes the questions still open:

  * /qt events -- what arguments quest events actually carry (still unverified)
  * /qt frames -- which Mainline UI frames exist, for M4's hooks
  * /qt channel -- whether this client knows instance (LFG) groups, and which
    channel ns.GroupChannel would pick right now (still unverified)
  * /qt sendtest -- what SendAddonMessage returns here (feeds Q4)
  * /qt realm -- what the client says about the player's realm (feeds Q7)
  * /qt roster -- how the client spells the OTHER group members, and the raw
    sender of the last addon message (issue #24, feeds Q7)

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
-- Measured solo 2026-09-21: this client returns a numeric
-- Enum.SendAddonMessageResult code (5 = NotInGroup). The success value, grouped,
-- is still unobserved. Older builds return a boolean instead. ns.Send has to read
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
-- /qt realm -- what does the client say about the player's realm?
--
-- Peer keys are "Name-Realm" (ns.PeerKey) and lean on GetNormalizedRealmName,
-- which is unmeasured here -- and /dump printed nothing on this client, so it
-- cannot be used to find out. Every line reports what was actually found.
------------------------------------------------------------------------------

function ns.commands.realm()
    ns.Print("realm probe:")
    ns.Print(("  GetNormalizedRealmName  %-3s  ->  %s"):format(
        ns.yn(_G.GetNormalizedRealmName), Call(_G.GetNormalizedRealmName)))
    ns.Print(("  GetRealmName            %-3s  ->  %s"):format(
        ns.yn(_G.GetRealmName), Call(_G.GetRealmName)))

    -- Both returns matter: the second is the realm, nil or "" on our own realm.
    for _, api in ipairs({ "UnitName", "UnitFullName" }) do
        local fn = _G[api]
        if not fn then
            ns.Print(("  %s(\"player\")  ->  no such API"):format(api))
        else
            local ok, name, realm = pcall(fn, "player")
            if ok then
                ns.Print(("  %s(\"player\")  ->  %s, %s"):format(api, ns.SafeStr(name), ns.SafeStr(realm)))
            else
                ns.Print(("  %s(\"player\")  ->  ERROR: %s"):format(api, ns.SafeStr(name)))
            end
        end
    end

    local key, display = ns.PlayerKey()
    ns.Print("  our own peer key:  " .. ns.SafeStr(key) .. "   shown as:  " .. ns.SafeStr(display))
end

------------------------------------------------------------------------------
-- /qt roster -- how does the client spell the OTHER group members?
--
-- Issue #24: a name with a space reached us as "Itemys Targaryen" in an addon
-- message and as "Itemys-Targaryen" from the roster. ns.PeerKey no longer cares
-- which, but the exact shapes are still unmeasured -- this prints them, next to
-- the raw sender of the last addon message we saw on our prefix.
--
-- Run it while grouped, after the other client has sent anything (/qt ping).
------------------------------------------------------------------------------

local lastSender = nil   -- raw CHAT_MSG_ADDON sender, untouched

function ns.commands.roster()
    ns.Print("roster probe:")
    local prefix = (_G.IsInRaid and _G.IsInRaid()) and "raid" or "party"
    local found = 0
    for i = 1, (prefix == "raid") and 40 or 4 do
        local unit = prefix .. i
        local exists = _G.UnitExists and _G.UnitExists(unit)
        if exists then
            found = found + 1
            for _, api in ipairs({ "UnitName", "UnitFullName" }) do
                local fn = _G[api]
                if fn then
                    local ok, name, realm = pcall(fn, unit)
                    ns.Print(("  %s(\"%s\")  ->  [%s], [%s]"):format(
                        api, unit, ok and ns.SafeStr(name) or "ERROR", ns.SafeStr(realm)))
                    if ok and api == "UnitName" then
                        local key, shown = ns.PeerKey(name, realm)
                        ns.Print(("      key [%s]  shown as [%s]  known peer: %s"):format(
                            ns.SafeStr(key), ns.SafeStr(shown), ns.yn(key and ns.peers[key])))
                    end
                end
            end
        end
    end
    if found == 0 then ns.Print("  no other group members -- run this while grouped.") end

    if lastSender == nil then
        ns.Print("  last addon-message sender: none seen yet (ask the other client to /qt ping)")
    else
        local key, shown = ns.PeerKey(lastSender)
        ns.Print(("  last addon-message sender: [%s]"):format(ns.SafeStr(lastSender)))
        ns.Print(("      key [%s]  shown as [%s]"):format(ns.SafeStr(key), ns.SafeStr(shown)))
    end
end

------------------------------------------------------------------------------
-- Help, under a heading of its own: these are probes, not everyday commands.
------------------------------------------------------------------------------

local PROBES = "still-open probes"

ns.AddHelp("/qt events", "toggle tracing of quest events and their arguments", PROBES)
ns.AddHelp("/qt frames", "list the UI objects M4 would hook", PROBES)
ns.AddHelp("/qt channel", "probe instance-group detection and the channel we would use", PROBES)
ns.AddHelp("/qt sendtest", "print what SendAddonMessage returns here (run solo and grouped)", PROBES)
ns.AddHelp("/qt realm", "print what the client reports as your name and realm", PROBES)
ns.AddHelp("/qt roster", "print how the client spells the other group members (run grouped)", PROBES)

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

-- A second frame, for /qt roster: remember the raw sender of the last addon
-- message on OUR prefix. Its own frame so the quest tracing above stays as it was.
local senderFrame = CreateFrame("Frame")
senderFrame:RegisterEvent("CHAT_MSG_ADDON")
senderFrame:SetScript("OnEvent", function(_, _, prefix, _, _, sender)
    if prefix == ns.PREFIX then lastSender = sender end
end)
