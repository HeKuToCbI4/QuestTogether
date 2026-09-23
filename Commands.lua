--[[----------------------------------------------------------------------------
Commands -- the user-facing slash commands that do real work.

Registered into ns.commands, a table Core dispatches into. Diagnostics.lua and
UI.lua add their own entries to the same table.

The asking itself lives in Query.lua; /qtf and /qtf ask are the thin front ends.

/qtf help lives here because Commands is the one module that is never deleted: it
prints ns.helpLines, which every module fills in for its own commands, so the
list is always exactly the commands this install actually has.

Convention: every module that contributes commands does
    ns.commands = ns.commands or {}
first, so that load order never matters.
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
---@cast ns QT.Namespace

ns.commands = ns.commands or {}

function ns.commands.ask(rest)
    local questID = tonumber(rest) or ns.LocalQuestID()
    if not questID then
        ns.Print("No quest selected. Open a quest at an NPC, or use /qtf ask <questID>.")
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
        ns.Print("No peers heard from yet. Try /qtf ping while grouped.")
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

------------------------------------------------------------------------------
-- /qtf help
--
-- Prints ns.helpLines in registration order, which follows the .toc: ungrouped
-- lines first, then each group under its heading. Nothing here knows which
-- commands exist -- that is the point. Delete a module and its lines go with it.
------------------------------------------------------------------------------

---@param h QT.HelpLine
local function PrintHelpLine(h)
    ns.Print(("  %-16s %s"):format(h.cmd, h.text))
end

function ns.commands.help()
    local version = ns.AddonVersion()
    ns.Print(version and ("v" .. version .. " -- commands:") or "commands:")

    local lines = ns.helpLines or {}
    for _, h in ipairs(lines) do
        if not h.group then PrintHelpLine(h) end
    end

    -- Grouped lines last, each heading printed once, in the order the group was
    -- first registered.
    local printed = {}
    for i, h in ipairs(lines) do
        if h.group and not printed[h.group] then
            printed[h.group] = true
            ns.Print("-- " .. h.group .. " --")
            for j = i, #lines do
                if lines[j].group == h.group then PrintHelpLine(lines[j]) end
            end
        end
    end
end

ns.AddHelp("/qtf",           "ask about the quest currently open")
ns.AddHelp("/qtf ask <id>",  "ask about a specific quest ID")
ns.AddHelp("/qtf ping",      "announce yourself to the group")
ns.AddHelp("/qtf status",    "list peers and how much we know")
ns.AddHelp("/qtf help",      "list these commands")
