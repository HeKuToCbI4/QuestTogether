--[[----------------------------------------------------------------------------
Slash command -- /qtf, named after the addon.

The client binds SLASH_<KEY>1 to SlashCmdList[<KEY>]; both are set in Core.lua.
------------------------------------------------------------------------------]]

local h = require("harness")

h.test("the slash command is /qtf, and only /qtf", function(env, ns)
    h.eq(_G.SLASH_QUESTTOGETHERFOREVER1, "/qtf", "registered as /qtf")
    h.isNil(_G.SLASH_QUESTTOGETHERFOREVER2, "no second alias")
    h.eq(type(_G.SlashCmdList.QUESTTOGETHERFOREVER), "function", "handler installed")
end)

h.test("/qtf dispatches to the named command", function(env, ns)
    h.noError(function() _G.SlashCmdList.QUESTTOGETHERFOREVER("status") end, "/qtf status")
    h.isTrue(#env.prints > 0, "it printed something")
end)

h.test("help lines advertise /qtf, never the old /qt", function(env, ns)
    for _, line in ipairs(ns.helpLines) do
        h.eq(line.cmd:sub(1, 4), "/qtf", "help: " .. line.cmd)
    end
end)
