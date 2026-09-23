--[[----------------------------------------------------------------------------
harness -- a fake WoW client, small enough to read in one sitting.

Run the suite with `lua5.1 tests/run.lua` (5.3 and 5.4 work too). No external
dependencies: stock Lua only, no busted, no luarocks.

What it does, per test:

  1. saves and replaces the handful of _G names the addon touches -- at load
     time (CreateFrame, UIParent, SlashCmdList) and at call time (C_ChatInfo,
     C_QuestLog, C_Timer, UnitName, IsInGroup, time, issecretvalue, print);
  2. reads QuestWithAFriend.toc and loads every listed file IN THAT ORDER through
     loadfile, calling each chunk as the client does -- chunk(ADDON_NAME, ns)
     -- with a fresh `ns` table;
  3. hands the test an `env` holding the recorded side effects (env.sent,
     env.prints, env.timers) and the knobs that steer the stubs;
  4. restores _G afterwards, pass or fail, so tests cannot leak into each other.

Nothing here may know the addon's internals beyond the API surface it stubs.
Assertions about behaviour belong in the test_*.lua files.
------------------------------------------------------------------------------]]

local M = {}

------------------------------------------------------------------------------
-- Locating the addon
------------------------------------------------------------------------------

local function Exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local ROOT
local function Root()
    if ROOT then return ROOT end
    for _, candidate in ipairs({ "", "../", "../../" }) do
        if Exists(candidate .. "QuestWithAFriend.toc") then
            ROOT = candidate
            return ROOT
        end
    end
    error("cannot find QuestWithAFriend.toc -- run the suite from the repository root")
end

-- The .toc is the single source of truth for load order, so the suite follows it
-- rather than keeping its own copy of the list.
---@return string[] files
function M.TocFiles()
    local files = {}
    for entry in io.lines(Root() .. "QuestWithAFriend.toc") do
        -- A fresh local, never the loop variable: Lua 5.5 makes those const.
        local line = entry:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:sub(1, 1) ~= "#" and line:lower():sub(-4) == ".lua" then
            files[#files + 1] = line
        end
    end
    if #files == 0 then error("no .lua files listed in QuestWithAFriend.toc") end
    return files
end

------------------------------------------------------------------------------
-- Fake frames
--
-- One object type stands in for frames, textures and font strings. Anything not
-- listed below answers with a no-op, which is all the addon needs at load time.
------------------------------------------------------------------------------

local function noop() end

local frameMeta = {
    __index = function(_, k)
        -- Underscore fields are the harness's own bookkeeping; they must read as
        -- nil when unset, not as a (truthy) no-op function.
        if type(k) == "string" and k:sub(1, 1) == "_" then return nil end
        return noop
    end,
}

local function NewFrame()
    local frame = { _shown = false, _scripts = {}, _events = {}, _text = "" }

    function frame:Show() self._shown = true end
    function frame:Hide() self._shown = false end
    function frame:IsShown() return self._shown end
    function frame:SetText(t) self._text = t end
    function frame:GetText() return self._text end
    function frame:GetStringHeight() return 10 end
    function frame:RegisterEvent(e) self._events[e] = true end
    function frame:UnregisterEvent(e) self._events[e] = nil end
    function frame:IsEventRegistered(e) return self._events[e] == true end
    function frame:SetScript(name, fn) self._scripts[name] = fn end
    function frame:GetScript(name) return self._scripts[name] end
    function frame:CreateTexture() return NewFrame() end
    function frame:CreateFontString() return NewFrame() end

    function frame:HookScript(name, fn)
        local prev = self._scripts[name]
        self._scripts[name] = function(...)
            if prev then prev(...) end
            return fn(...)
        end
    end

    -- Fire a script as the client would. Tests use this; the addon never does.
    function frame:Fire(name, ...)
        local fn = self._scripts[name]
        if fn then return fn(self, ...) end
    end

    return setmetatable(frame, frameMeta)
end

M.NewFrame = NewFrame

------------------------------------------------------------------------------
-- strsplit
--
-- The addon no longer uses it, but the stub stays: it is a WoW global, the
-- fake client should provide it, and a module may reach for it again.
-- Written without table.unpack / unpack, which moved between 5.1 and 5.2.
------------------------------------------------------------------------------

local function SplitValues(delim, s, from)
    local at = string.find(s, delim, from, true)
    if not at then return string.sub(s, from) end
    return string.sub(s, from, at - 1), SplitValues(delim, s, at + #delim)
end

------------------------------------------------------------------------------
-- The environment
------------------------------------------------------------------------------

-- opts:
--   player      string   name UnitName("player") answers with (default "Tester")
--   inGroup     boolean  IsInGroup (default true)
--   inRaid      boolean  IsInRaid (default false)
--   groupSize   number   GetNumGroupMembers (default 2)
--   chatInfo    boolean  false removes C_ChatInfo entirely (no send API)
--   questLog    boolean  false removes C_QuestLog entirely (no completion oracle)
--   logIndex    boolean  false removes only C_QuestLog.GetLogIndexForQuestID
--
-- Mutable after load (the stubs read them on every call):
--   env.completed[questID] = true      what the oracle answers
--   env.inLog[questID]     = logIndex  what GetLogIndexForQuestID answers
--   env.secrets[value]     = true      what issecretvalue answers
--   env.oracle, env.logIndex           replace the functions outright
--   env.localQuest                     what GetQuestID answers
---@param opts table?
function M.newEnv(opts)
    opts = opts or {}

    local env = {
        ns        = {},
        sent      = {},   -- { prefix, payload, channel } per SendAddonMessage
        prints    = {},   -- every line the addon printed
        timers    = {},   -- { delay, fn } per C_Timer.After
        frames    = {},   -- every frame CreateFrame handed out
        completed = {},
        inLog     = {},
        secrets   = {},
        player    = opts.player or "Tester",
        inGroup   = opts.inGroup ~= false,
        inRaid    = opts.inRaid or false,
        groupSize = opts.groupSize or 2,
        groupNames = opts.groupNames or {},
        now       = 1000,
        localQuest = opts.localQuest,
        _saved    = {},
    }

    -- The oracle answers a real boolean, as the live client does.
    env.oracle = function(questID) return env.completed[questID] == true end
    env.logIndex = function(questID) return env.inLog[questID] end

    local function install(name, value)
        env._saved[name] = { _G[name] }   -- boxed, so a previous nil restores as nil
        _G[name] = value
    end

    function env.destroy()
        for name, box in pairs(env._saved) do _G[name] = box[1] end
        env._saved = {}
    end

    -- Run every queued C_Timer.After callback, in order.
    function env.flushTimers()
        local pending = env.timers
        env.timers = {}
        for _, t in ipairs(pending) do t.fn() end
    end

    -- Payload of the last addon message sent, or nil when nothing was sent.
    function env.lastSent()
        local last = env.sent[#env.sent]
        return last and last.payload or nil
    end

    ---------------------------------------------------------------------------
    -- _G stubs
    ---------------------------------------------------------------------------

    install("print", function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring((select(i, ...)))
        end
        env.prints[#env.prints + 1] = table.concat(parts, "\t")
    end)

    install("CreateFrame", function()
        local f = NewFrame()
        env.frames[#env.frames + 1] = f
        return f
    end)

    install("UIParent", NewFrame())
    install("SlashCmdList", {})
    install("SLASH_QUESTWITHFRIEND1", nil)
    install("QuestWithAFriendDB", nil)
    install("QuestFrame", nil)

    install("strsplit", function(delim, s) return SplitValues(delim, s, 1) end)

    -- Built as locals first: `opts.x == false and nil or {…}` would always pick
    -- the table, which is the oldest trap in Lua.
    local chatInfo, questLog

    if opts.chatInfo ~= false then
        chatInfo = {
            SendAddonMessage = function(prefix, payload, channel, target)
                env.sent[#env.sent + 1] = {
                    prefix = prefix, payload = payload, channel = channel, target = target,
                }
                return true
            end,
            RegisterAddonMessagePrefix = function(prefix)
                env.registeredPrefix = prefix
                return true
            end,
        }
    end

    if opts.questLog ~= false then
        questLog = {
            IsQuestFlaggedCompleted = function(questID) return env.oracle(questID) end,
            GetNumQuestLogEntries = function() return 0 end,
            GetQuestIDForLogIndex = function() return nil end,
            GetInfo = function() return nil end,
        }
        if opts.logIndex ~= false then
            questLog.GetLogIndexForQuestID = function(questID) return env.logIndex(questID) end
        end
    end

    install("C_ChatInfo", chatInfo)
    install("C_QuestLog", questLog)

    install("C_GossipInfo", {})
    install("C_Timer", {
        After = function(delay, fn) env.timers[#env.timers + 1] = { delay = delay, fn = fn } end,
    })

    install("UnitName", function(unit)
        if unit == "player" then return env.player end
        return env.groupNames[unit]
    end)
    install("IsInGroup", function() return env.inGroup end)
    install("IsInRaid", function() return env.inRaid end)
    install("GetNumGroupMembers", function() return env.groupSize end)
    install("GetQuestID", function() return env.localQuest end)
    install("time", function() return env.now end)
    install("issecretvalue", function(v) return env.secrets[v] == true end)

    ---------------------------------------------------------------------------
    -- Load the addon, in .toc order
    ---------------------------------------------------------------------------

    local ok, err = pcall(function()
        for _, file in ipairs(M.TocFiles()) do
            local path = Root() .. file
            local chunk, loadErr = loadfile(path)
            if not chunk then error("cannot load " .. path .. ": " .. tostring(loadErr), 0) end
            chunk("QuestWithAFriend", env.ns)   -- exactly how the client calls it
        end
    end)
    if not ok then
        env.destroy()
        error("loading the addon failed: " .. tostring(err), 2)
    end

    return env
end

------------------------------------------------------------------------------
-- Assertions
------------------------------------------------------------------------------

---@param v any
---@return string
function M.show(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

local function fail(msg)
    error("assertion failed -- " .. msg, 3)
end

function M.eq(actual, expected, what)
    if actual ~= expected then
        fail((what or "value") .. ": expected " .. M.show(expected) .. ", got " .. M.show(actual))
    end
end

function M.neq(actual, unexpected, what)
    if actual == unexpected then
        fail((what or "value") .. ": expected anything but " .. M.show(unexpected))
    end
end

-- Deliberately strict: isNil is not "falsy". The whole addon turns on the
-- difference between nil (unknown) and false (a confirmed no).
function M.isNil(v, what)
    if v ~= nil then
        fail((what or "value") .. ": expected nil (unknown), got " .. M.show(v))
    end
end

function M.isTrue(v, what)
    if v ~= true then fail((what or "value") .. ": expected true, got " .. M.show(v)) end
end

function M.isFalse(v, what)
    if v ~= false then fail((what or "value") .. ": expected false, got " .. M.show(v)) end
end

function M.ok(v, what)
    if not v then fail((what or "value") .. ": expected something truthy, got " .. M.show(v)) end
end

function M.noError(fn, what)
    local ok, err = pcall(fn)
    if not ok then
        fail((what or "call") .. " raised: " .. tostring(err))
    end
end

function M.count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

------------------------------------------------------------------------------
-- Registry
--
-- Test files call M.test at load time; run.lua runs what they registered.
------------------------------------------------------------------------------

M.tests = {}
M.currentFile = "?"

---@param name string
---@param a table|function   env options, or the test body
---@param b function?        the test body when options were given
function M.test(name, a, b)
    local opts, fn
    if b == nil then opts, fn = nil, a else opts, fn = a, b end
    if type(fn) ~= "function" then error("test '" .. tostring(name) .. "' has no body", 2) end
    M.tests[#M.tests + 1] = { name = name, opts = opts, fn = fn, file = M.currentFile }
end

return M
