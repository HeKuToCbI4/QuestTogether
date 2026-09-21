--[[----------------------------------------------------------------------------
Compat -- the client API surface, in one place.

Everything that depends on the shape of the WoW API lives here. If the surface
moves -- and Forever is in beta -- this is the only file that changes with it.

MEASURED 2026-09-20, client 1.60.1 / build 69893 / tocversion 16001:
the modern C_* namespace is complete and EVERY legacy global is absent.
C_ChatInfo.SendAddonMessage, C_ChatInfo.RegisterAddonMessagePrefix and
C_QuestLog.IsQuestFlaggedCompleted all resolve; _G.SendAddonMessage,
_G.RegisterAddonMessagePrefix and _G.IsQuestFlaggedCompleted do not exist.

The fallbacks below are therefore dead code on this client. They are kept because
the surface may still shift -- but this is a recorded measurement, not a hedge.

Also home to the primitives every other module assumes: the secret-value guard,
the safe formatter, and Print.

Load-order note: modules communicate through `ns` and must only ever CALL each
other at runtime, never during load. A cross-module call at load time is the
same forward-reference trap that crashed v0.1.
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

-- LuaLS type declarations (comments only -- no runtime effect). The tri-state is
-- spelled `boolean?` throughout: true / false / nil-meaning-UNKNOWN.

---@alias QT.AnswerStatus
---| 0 # not completed
---| 1 # completed
---| 2 # not completed, but in their quest log right now ("on it")

---@class QT.Peer
---@field name string                        display name as the sender arrived ("Name" or "Name-Realm")
---@field compatible boolean                 their protocol revision equals ns.PROTOCOL
---@field lastSeen number                    time() of their last message
---@field answered table<number, boolean>    questID -> completed; ABSENT KEY == UNKNOWN, never false
---@field onIt table<number, boolean>        questID -> true; only ever set alongside answered == false

---@class QT.Namespace
---@field api table<string, function?>       resolved client API; any entry may be nil
---@field peers table<string, QT.Peer>       keyed by bare character name (see ns.BaseName)
---@field commands table<string, fun(rest: string)>
---@field onAnswer? fun(peer: QT.Peer?, questID: number, status: QT.AnswerStatus)
---@field PREFIX string
---@field PROTOCOL integer
---@field REPLY_WINDOW number
---@field ANNOUNCE_DEBOUNCE number
---@field tracing boolean

---@cast ns QT.Namespace

local C_ChatInfo = rawget(_G, "C_ChatInfo")
local C_QuestLog = rawget(_G, "C_QuestLog")

-- Resolved once at load.
ns.api = {
    send        = (C_ChatInfo and C_ChatInfo.SendAddonMessage)           or _G.SendAddonMessage,
    register    = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or _G.RegisterAddonMessagePrefix,
    isDone      = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted)    or _G.IsQuestFlaggedCompleted,
    getInfo     = C_QuestLog and C_QuestLog.GetInfo,
    getCount    = C_QuestLog and C_QuestLog.GetNumQuestLogEntries,
    idForIdx    = C_QuestLog and C_QuestLog.GetQuestIDForLogIndex,
    logIdxForId = C_QuestLog and C_QuestLog.GetLogIndexForQuestID,
}

-- Shared hooks. Declared HERE, in the first-loaded module, so that no later
-- module has to initialise them -- a module that assigns `ns.onAnswer = nil` at
-- load would clobber whoever set it first, making load order load-bearing.
--
-- ns.onAnswer: set by Commands.lua, called by Protocol.lua when a peer answers.
ns.onAnswer = nil

-- Whole namespaces, so Diagnostics can probe a surface without this file
-- having to enumerate every member of it. Currently unused: the probes that read
-- it (/qt env) were retired 2026-09-21. Kept for the next surface to measure.
ns.namespaces = {
    C_ChatInfo   = C_ChatInfo,
    C_QuestLog   = C_QuestLog,
    C_GossipInfo = rawget(_G, "C_GossipInfo"),
}

------------------------------------------------------------------------------
-- Primitives
------------------------------------------------------------------------------

---@param msg any
function ns.Print(msg)
    print("|cff33ff99Quest Together|r " .. tostring(msg))
end

---@param v any
---@return "yes"|"NO"
function ns.yn(v)
    return v and "yes" or "NO"
end

-- Wrap every value that might carry a secret. Under the secret-values system,
-- arithmetic and comparison on a secret raises a Lua error, so anything coming
-- from a quest or unit API is checked before we touch it.
---@param v any
---@return boolean
function ns.IsSecret(v)
    local f = _G.issecretvalue
    if not f then return false end
    local ok, res = pcall(f, v)
    return ok and res == true
end

-- Never let a diagnostic itself throw.
---@param v any
---@return string
function ns.SafeStr(v)
    if v == nil then return "nil" end
    if ns.IsSecret(v) then return "<secret>" end
    local ok, s = pcall(tostring, v)
    return ok and s or "<unprintable>"
end

-- Seconds, for rate limiting. GetTime is the client's frame clock (fractional
-- seconds since login); time() is the wall clock in whole seconds and is only a
-- fallback. Both are read defensively and through _G: a rate limit must never be
-- the thing that throws, and a client without either simply gets 0, which makes
-- every window look expired rather than blocking sends forever.
---@return number seconds   0 when the client exposes no clock at all
function ns.Now()
    local f = _G.GetTime or _G.time
    if not f then return 0 end
    local ok, v = pcall(f)
    if not ok or type(v) ~= "number" then return 0 end
    return v
end

-- Addon-message senders arrive as "Name" or "Name-Realm"; key peers by the bare
-- name so cross-realm and same-realm members compare consistently.
---@param s any           sender as delivered by CHAT_MSG_ADDON
---@return string? key    nil when s is not a string
function ns.BaseName(s)
    if type(s) ~= "string" then return nil end
    return (s:match("^([^%-]+)")) or s
end

---@return "RAID"|"PARTY"|nil channel   nil when solo
function ns.GroupChannel()
    if _G.IsInRaid and _G.IsInRaid() then return "RAID" end
    if _G.IsInGroup and _G.IsInGroup() then return "PARTY" end
    return nil
end

-- Bare names of everyone in the group, INCLUDING the player, for the roster walk
-- in Peers.lua. Returns nil when the roster cannot be read at all -- and a caller
-- must NOT read that as "nobody is in the group", or one transient API failure
-- would drop every peer. Unknown is never "no", applied to the roster too.
--
-- UnitName returns name, realm; only the first is kept, because peers are keyed
-- by bare name (ns.BaseName). GetNumGroupMembers counts the player, and this
-- client is not confirmed to agree -- both conventions are handled below.
---@return table<string, true>? names
function ns.GroupMemberNames()
    local countFn = _G.GetNumGroupMembers
    local nameFn  = _G.UnitName
    if not countFn or not nameFn then return nil end

    local ok, count = pcall(countFn)
    if not ok or type(count) ~= "number" or count < 0 then return nil end
    if count == 0 then return {} end   -- definitely alone: the group is empty

    local prefix, last
    if _G.IsInRaid and _G.IsInRaid() then
        prefix, last = "raid", math.min(count, 40)
    else
        prefix, last = "party", math.min(count - 1, 4)   -- the player is counted separately
    end

    local names = {}
    local okSelf, self = pcall(nameFn, "player")
    if okSelf then
        local key = ns.BaseName(self)
        if key then names[key] = true end
    end
    for i = 1, last do
        local okUnit, unit = pcall(nameFn, prefix .. i)
        if okUnit then
            local key = ns.BaseName(unit)
            if key then names[key] = true end
        end
    end
    return names
end

------------------------------------------------------------------------------
-- The completion oracle
------------------------------------------------------------------------------

-- LOCAL PLAYER ONLY. Returns true / false, or nil plus a reason when the client
-- cannot answer. A nil must never be coerced to false: that turns "unknown" into
-- "not completed", the one mistake this addon exists to prevent.
--
-- Verified bidirectionally 2026-09-20 -- quest 92460 answered `false` before
-- turn-in and `true` after. See docs/MEASUREMENTS.md, "Fourth run".
---@param questID number
---@return boolean? done   nil == UNKNOWN; never coerce to false
---@return string? reason  set only when done is nil
function ns.SafeIsDone(questID)
    if not ns.api.isDone then return nil, "no completion API" end
    local ok, res = pcall(ns.api.isDone, questID)
    if not ok then return nil, "call errored" end
    if ns.IsSecret(res) then return nil, "secret value" end
    if type(res) ~= "boolean" then return nil, "non-boolean result" end
    return res
end

-- Quest ID of whatever the quest frame is currently showing, if anything.
---@return number? questID   always > 0 when non-nil
function ns.LocalQuestID()
    local f = _G.GetQuestID
    if not f then return nil end
    local ok, v = pcall(f)
    if not ok or v == nil or ns.IsSecret(v) then return nil end
    if type(v) ~= "number" or v <= 0 then return nil end
    return v
end
