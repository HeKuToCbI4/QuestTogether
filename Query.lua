--[[----------------------------------------------------------------------------
Query -- asking the group about a quest, and reporting what comes back.

One entry point, ns.Ask, used by both /qt and the panel's auto-ask. The two
differ only in how loud they are, so that is a flag rather than a second path:

  * manual (/qt, /qt ask <id>) prints "Asking your group...", a line per answer
    as it lands, and a summary when the reply window closes.
  * silent (auto-ask, every time a quest is opened) prints nothing at all. The
    popup is already on screen and repaints itself as answers arrive; chat would
    only repeat it, once per quest opened.

Pending asks are keyed by QUEST ID rather than held in one "current ask"
variable. Clicking through several quests quickly used to leave only the newest
ask current: the older asks' live lines were dropped as they arrived, while every
one of those asks still printed its own summary three seconds later. Now each
quest ID has at most one pending entry and at most one timer, and re-asking a
quest that is still pending adds neither.

Nothing here writes peer state: ns.RecordAnswer stays the only writer, and an
unanswered peer stays unknown rather than becoming a "no".
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
---@cast ns QT.Namespace

-- questID -> true while a manual ask is waiting for its reply window to close.
-- A silent ask has nothing to report, so it records nothing.
local pending = {}

---@param questID number
local function Report(questID)
    pending[questID] = nil
    if next(ns.peers) == nil then
        ns.Print("Nobody in your group is running Quest Together.")
        return
    end
    ns.Print("Quest " .. questID .. ":")
    for _, p in pairs(ns.peers) do
        ns.Print("  " .. p.name .. ": " .. ns.DescribePeerState(p, questID))
    end
end

-- A line per answer while that quest's manual ask is still open. Printing live
-- during a request is presentation, which is why it lives here and not in the
-- transport layer.
ns.OnAnswer(function(peer, questID)
    if peer and pending[questID] then
        ns.Print("  " .. peer.name .. ": " .. ns.DescribePeerState(peer, questID))
    end
end)

-- Returns ok, err so a caller can choose to report the failure (manual /qt does)
-- or stay quiet (auto-ask need not tell the user they are not in a group).
---@param questID number?
---@param silent boolean?   true: send the query without printing anything
---@return boolean ok
---@return string? err      set only when ok is false
function ns.Ask(questID, silent)
    if not questID then return false, "no quest" end
    -- Validate first: an invalid ID must not reach the wire, and nothing must be
    -- marked pending by an ask that never left the machine.
    questID = ns.ValidQuestID(questID)
    if not questID then return false, "invalid quest ID" end

    local alreadyPending = (pending[questID] ~= nil)
    local ok, err = ns.Send(ns.PROTOCOL .. "|Q|" .. questID)
    if not ok then return false, err end
    if silent then return true end

    ns.Print("Asking your group about quest " .. questID .. "...")
    -- Already pending: the query went out again (a peer who just joined may not
    -- have heard the first one), but the timer already running will report it.
    if alreadyPending then return true end

    pending[questID] = true
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(ns.REPLY_WINDOW, function() Report(questID) end)
    else
        Report(questID)
    end
    return true
end
