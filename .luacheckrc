-- luacheck configuration. Run `luacheck .` from the repository root.
--
-- The point of this file is risk R11 (docs/ROADMAP.md): a misspelt or
-- not-yet-defined name resolves as a global and only fails when called, in the
-- client. With every legitimate global declared below, luacheck reports anything
-- else as "accessing undefined variable" before the client ever sees it.

std = "lua51"
max_line_length = false
codes = true

exclude_files = { ".git", ".github", "tools" }

ignore = {
    "211/ADDON_NAME",   -- `local ADDON_NAME, ns = ...` is the idiom; most files use only ns
    "212",              -- unused argument: event handlers and callbacks have fixed signatures
    "61.",              -- whitespace-only findings
}

-- Globals this addon defines.
globals = {
    "SLASH_QUESTTOGETHER1",
    "QuestTogetherDB",
    "SlashCmdList",      -- we add a field to it
    "_G",                -- _G.QuestTogetherDB is assigned in Core.lua
}

-- Globals provided by the client that are referenced BY BARE NAME. Anything read
-- as `_G.Name` needs no entry. Add a name here only after it has been confirmed to
-- exist on the live client (docs/MEASUREMENTS.md).
read_globals = {
    "CreateFrame",
    "UIParent",
    "strsplit",
}

-- The offline test suite (`lua5.1 tests/run.lua`). It is plain Lua, not addon
-- code: it never runs in the client, and it deliberately does to `_G` what the
-- client would do -- installing the WoW globals above and taking them away
-- again. It is linted with everything else; these are the two differences.
files["tests/**"] = {
    -- run.lua puts tests/ on package.path so test files can require("harness").
    globals = { "package" },
    -- `arg` is the script's argument table; run.lua reads arg[0] and arg[1].
    read_globals = { "arg" },
}
