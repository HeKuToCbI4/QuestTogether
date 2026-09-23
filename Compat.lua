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
the safe formatter, Print, the one peer-key function (ns.PeerKey) -- and the two
registries (answer listeners, help lines) through which the other modules announce
themselves. Peer identity lives here precisely because every module has to agree on
it -- two key-building rules would silently split the registry in half.

Load-order note: modules communicate through `ns` and must only ever CALL each
other at runtime, never during load. A cross-module call at load time is the
same forward-reference trap that crashed v0.1. Registering into the lists below
is the one sanctioned exception: this file is first in the .toc, so the lists
exist before anyone adds to them, and registering only appends a value -- it
never runs another module's behaviour. That is what lets every OTHER file be
reordered or deleted without breaking anything.
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

-- LuaLS type declarations (comments only -- no runtime effect). The tri-state is
-- spelled `boolean?` throughout: true / false / nil-meaning-UNKNOWN.

---@alias QT.AnswerStatus
---| 0 # not completed
---| 1 # completed
---| 2 # not completed, but in their quest log right now ("on it")

---@class QT.Peer
---@field name string                        display name: bare on our realm, "Name-Realm" across realms
---@field compatible boolean                 their protocol revision equals ns.PROTOCOL
---@field lastSeen number                    time() of their last message
---@field answered table<number, boolean>    questID -> completed; ABSENT KEY == UNKNOWN, never false
---@field onIt table<number, boolean>        questID -> true; only ever set alongside answered == false

---@class QT.HelpLine
---@field cmd string                         the command as typed, e.g. "/qt ping"
---@field text string                        one short line of description
---@field group string?                      optional heading; ungrouped lines print first
---@class QT.GroupMember
---@field key string                         peer key, from ns.PeerKey
---@field display string                     name to show the user
---@field isPlayer boolean                   true for the local player's own row

---@class QT.Namespace
---@field api table<string, function?>       resolved client API; any entry may be nil
---@field peers table<string, QT.Peer>       keyed by ns.PeerKey (name + realm, separators dropped)
---@field commands table<string, fun(rest: string)>
---@field answerListeners (fun(peer: QT.Peer?, questID: number, status: QT.AnswerStatus))[]
---@field helpLines QT.HelpLine[]
---@field PREFIX string
---@field PROTOCOL integer
---@field REPLY_WINDOW number
---@field ANNOUNCE_DEBOUNCE number
---@field ANNOUNCE_QUIET number
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

------------------------------------------------------------------------------
-- Registries
--
-- Two lists any module may add itself to. They live HERE, in the first-loaded
-- module, so that the list a module registers into always exists already.
--
-- They replace the old wrap chains (`ns.onAnswer`, `ns.commands.help`), where a
-- file wrapped whatever the previous file had set. A wrap silently captured nil
-- if the files were listed the other way round, so the .toc order quietly
-- decided whether the addon worked. With registries, every file but this one can
-- be moved or deleted freely; registering is a definition, not a call into
-- another module's behaviour.
------------------------------------------------------------------------------

-- Called by Protocol.lua when a peer answers, in registration order, each inside
-- its own pcall: one broken listener must not stop the rest.
ns.answerListeners = ns.answerListeners or {}

---@param fn fun(peer: QT.Peer?, questID: number, status: QT.AnswerStatus)
function ns.OnAnswer(fn)
    if type(fn) ~= "function" then return end
    ns.answerListeners[#ns.answerListeners + 1] = fn
end

-- /qt help is assembled from whatever modules are present. Each module registers
-- the commands IT owns, so deleting a file takes its help lines with it and
-- leaves the rest of the list intact.
ns.helpLines = ns.helpLines or {}

---@param cmd string      the command as typed, e.g. "/qt ping"
---@param text string     one short line of description
---@param group string?   optional heading; ungrouped lines print first
function ns.AddHelp(cmd, text, group)
    if type(cmd) ~= "string" or type(text) ~= "string" then return end
    ns.helpLines[#ns.helpLines + 1] = { cmd = cmd, text = text, group = group }
end

------------------------------------------------------------------------------
-- Primitives
------------------------------------------------------------------------------

-- The addon's version, read from the .toc rather than repeated in the source.
-- Presence-guarded both ways, and nil when the client offers neither API -- the
-- help header then simply has no version in it, which beats printing a wrong one.
---@return string? version   nil when the client exposes no metadata API
function ns.AddonVersion()
    local f = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    if not f then return nil end
    local ok, v = pcall(f, ADDON_NAME, "Version")
    if not ok or type(v) ~= "string" or v == "" then return nil end
    return v
end

---@param msg any
function ns.Print(msg)
    print("|cff33ff99Quest Together Forever|r " .. tostring(msg))
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

------------------------------------------------------------------------------
-- Peer identity
--
-- ONE key function, used by every module that touches ns.peers. A peer is keyed
-- by name AND realm: the bare name is not an identity, because two realms can
-- send the same one, and a cross-realm namesake of the local player would
-- otherwise be mistaken for the player and ignored forever. Our own realm is
-- left out of the key, so a peer on it has one key however the client spells them.
------------------------------------------------------------------------------

-- Resolved lazily and cached: GetNormalizedRealmName can answer nil early in the
-- login sequence, so a load-time read would cache the wrong thing forever.
local ownRealm = nil

-- The player's own realm, normalised (spaces stripped), or nil when the client
-- will not tell us. GetNormalizedRealmName is NOT measured on this client, hence the
-- guard -- if the API is absent, keys stay bare names, which is no worse than
-- the behaviour it replaces.
---@return string? realm
function ns.OwnRealm()
    if ownRealm then return ownRealm end
    local f = _G.GetNormalizedRealmName
    if not f then return nil end
    local ok, r = pcall(f)
    if not ok or type(r) ~= "string" then return nil end
    r = (r:gsub("%s", ""))
    if r == "" then return nil end
    ownRealm = r
    return ownRealm
end

-- Build a peer key. Accepts both shapes the client hands us:
--   * a CHAT_MSG_ADDON sender, "Name" or "Name-Realm"  -> ns.PeerKey(sender)
--   * UnitName's two returns, realm nil/"" on our realm -> ns.PeerKey(name, realm)
--
-- MEASURED 2026-09-21 (two clients): names on this client can contain a SPACE
-- ("Itemys Targaryen"), and the same character then reaches us in two spellings --
-- the addon-message sender keeps the space, while the group roster hands back
-- "Itemys-Targaryen", which reads exactly like Name-Realm. No split of that string
-- can be trusted, so the key does not depend on one:
--
--   1. join name and realm, strip whitespace from the realm;
--   2. cut our OWN realm off the end, if it is there (a peer on our realm must get
--      the same key whether or not the client spelled the realm out);
--   3. drop every space and hyphen from what is left.
--
--   "Itemys Targaryen-ClassicBetaPvE", "Itemys Targaryen" and "Itemys-Targaryen"
--   all give "ItemysTargaryen"; "Ana-OtherRealm" and ("Ana", "Other Realm") both
--   give "AnaOtherRealm".
--
-- The price is a theoretical collision ("AnaOther" on our realm vs "Ana" on a realm
-- called "Other"), accepted because the alternative was a certain mismatch.
--
-- The key is an identity, never something to show. The display name is returned
-- separately and keeps the spelling we were given, minus our own realm.
--
-- Senders are hostile input (CLAUDE.md rule 5), so type and length are checked.
---@param name any         character name, or a "Name-Realm" sender string
---@param realm? any       UnitName's second return; nil or "" means our own realm
---@return string? key     nil when name is not usable
---@return string? display nil exactly when key is nil
function ns.PeerKey(name, realm)
    -- Secret first: even `#` on a secret value raises.
    if ns.IsSecret(name) or ns.IsSecret(realm) then return nil end
    if type(name) ~= "string" or #name == 0 or #name > 100 then return nil end
    -- A name never starts with a separator; "-Realm" is hostile input, not a peer.
    if name:find("^[%s%-]") then return nil end

    local full = name
    if type(realm) == "string" and realm ~= "" and #realm <= 100 then
        full = name .. "-" .. (realm:gsub("%s", ""))
    end

    -- Cut our own realm off the end. Plain find, not a pattern: a realm name is
    -- data, and must not be read as one.
    local own = ns.OwnRealm()
    if own then
        local tail = "-" .. own
        if #full > #tail and full:sub(-#tail) == tail then
            full = full:sub(1, #full - #tail)
        end
    end

    local key = (full:gsub("[%s%-]", ""))
    if key == "" then return nil end   -- nothing but separators: not a name
    return key, full
end

-- The local player's own key, for "is this me?" comparisons. nil when the client
-- cannot name the player -- and a nil must NOT be read as "not me": a caller that
-- cannot tell should behave as it did before, not guess.
---@return string? key
---@return string? display
function ns.PlayerKey()
    local f = _G.UnitName
    if not f then return nil end
    local ok, name, realm = pcall(f, "player")
    if not ok then return nil end
    return ns.PeerKey(name, realm)
end

-- The "instance group" category, however this client spells it. UNVERIFIED here:
-- neither the constant nor the Enum form has been seen on Forever, so both are
-- plain guarded lookups and a miss returns nil. /qt channel measures it.
---@return any? category   nil when the client exposes no instance category
function ns.InstancePartyCategory()
    local c = _G.LE_PARTY_CATEGORY_INSTANCE
    if c ~= nil then return c end
    local enum = _G.Enum
    local t = enum and enum.PartyCategory
    if type(t) == "table" then return t.Instance end
    return nil
end

-- An instance (LFG) group is not a party: a message sent to "PARTY" there reaches
-- nobody, so the instance category is checked FIRST. Both the category and the
-- IsInGroup(category) argument form are unverified on this client, so the lookup
-- is guarded and the call is wrapped -- when either is missing or errors, the
-- result is exactly what it was before: "RAID" / "PARTY" / nil.
---@return "INSTANCE_CHAT"|"RAID"|"PARTY"|nil channel   nil when solo
function ns.GroupChannel()
    local inGroup = _G.IsInGroup
    if inGroup then
        local category = ns.InstancePartyCategory()
        if category ~= nil then
            local ok, inInstanceGroup = pcall(inGroup, category)
            if ok and inInstanceGroup == true then return "INSTANCE_CHAT" end
        end
    end
    if _G.IsInRaid and _G.IsInRaid() then return "RAID" end
    if inGroup and inGroup() then return "PARTY" end
    return nil
end

-- Everyone in the group, INCLUDING the player (flagged), in roster order. Used
-- both to prune departed peers (Peers.lua) and to drive the listing, so that a
-- member without the addon is shown as "?" instead of being invisible.
--
-- Returns nil when the roster cannot be read at all -- and a caller must NOT read
-- that as "nobody is in the group", or one transient API failure would drop every
-- peer. Unknown is never "no", applied to the roster too.
--
-- GetNumGroupMembers is not confirmed on this client to count the player, so the
-- unit loop is deliberately bounded by the channel's own maximum rather than by
-- the count: a unit that does not exist yields no name and is skipped, so
-- over-scanning is free while under-scanning would hide a real member.
---@return QT.GroupMember[]? members
function ns.GroupMembers()
    local countFn = _G.GetNumGroupMembers
    local nameFn  = _G.UnitName
    if not countFn or not nameFn then return nil end

    local ok, count = pcall(countFn)
    if not ok or type(count) ~= "number" or count < 0 then return nil end

    local members, seen = {}, {}
    local function add(unit, isPlayer)
        local okUnit, uName, uRealm = pcall(nameFn, unit)
        if not okUnit then return end
        local key, display = ns.PeerKey(uName, uRealm)
        if not key or seen[key] then return end
        seen[key] = true
        members[#members + 1] = { key = key, display = display, isPlayer = isPlayer }
    end

    -- The player first, so the duplicate "raidN" entry for them is skipped.
    add("player", true)
    if count == 0 then return members end   -- definitely alone: nobody else to add

    local prefix, last
    if _G.IsInRaid and _G.IsInRaid() then
        prefix, last = "raid", 40
    else
        prefix, last = "party", 4
    end
    for i = 1, last do
        add(prefix .. i, false)
    end
    return members
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

-- LOCAL PLAYER ONLY: is this quest in my log right now? Same tri-state as
-- ns.SafeIsDone -- nil means the client could not say, never "no".
---@param questID number
---@return boolean? inLog   nil == UNKNOWN
function ns.SafeInLog(questID)
    local f = ns.api.logIdxForId
    if not f then return nil end
    local ok, idx = pcall(f, questID)
    if not ok or ns.IsSecret(idx) then return nil end
    return idx ~= nil and idx ~= false and idx ~= 0
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
