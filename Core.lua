--[[----------------------------------------------------------------------------
Core -- bootstrap, event wiring, slash dispatch.

Deliberately thin. If this file starts growing, something in it belongs in
another module.

Load order: Compat -> Peers -> Protocol -> Query -> Commands -> Config -> Diagnostics ->
UI -> Core,
as listed in the .toc. Order only matters for definitions; modules reach each other
through `ns` and must only CALL across module boundaries at runtime. A cross-module
call during load is the same forward-reference trap that crashed v0.1 (see
docs/MEASUREMENTS.md, "Third run").
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
---@cast ns QT.Namespace

------------------------------------------------------------------------------
-- Slash dispatch
--
-- Commands and Diagnostics both register into ns.commands, which is why neither
-- owns the slash command itself.
------------------------------------------------------------------------------

SLASH_QUESTTOGETHERFOREVER1 = "/qt"
SlashCmdList["QUESTTOGETHERFOREVER"] = function(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()

    local fn = ns.commands and ns.commands[cmd]
    if not fn then fn = ns.commands and ns.commands.help end
    if not fn then
        ns.Print("No such command: " .. ns.SafeStr(cmd))
        return
    end
    fn(rest)
end

------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GROUP_ROSTER_UPDATE")

f:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        -- SavedVariables land just before this fires. There are no settings yet
        -- (v0.0.2), but touching the table now means v0.2 can start reading it.
        _G.QuestTogetherForeverDB = _G.QuestTogetherForeverDB or {}
        ns.RegisterPrefix()

    elseif event == "CHAT_MSG_ADDON" then
        -- pcall so a malformed payload from any peer can never throw inside our
        -- own session. A buggy or hostile client must not break this one.
        pcall(ns.HandleAddonMessage, arg1, arg2, arg3, arg4)

    elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
        -- Drop anyone who has left before re-announcing, so a stale answer cannot
        -- outlive the group membership it came from (docs/ARCHITECTURE.md D2).
        ns.PrunePeers()

        -- Re-announce on every roster change. State, not events: we do not try
        -- to track who joined when, we just make sure everyone eventually hears
        -- us. (docs/PROTOCOL.md, "Sync state, not events".)
        --
        -- Debounced, because GROUP_ROSTER_UPDATE fires far more often than people
        -- join or leave -- role, online and zone changes all raise it, in bursts
        -- in a raid. ns.AnnounceSoon turns a burst into one message; the delay is
        -- a few seconds and presence is not urgent.
        if ns.GroupChannel() then ns.AnnounceSoon() end
    end
end)
