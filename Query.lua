--[[----------------------------------------------------------------------------
Query -- asking the group about a quest, and reporting what comes back.

One entry point, ns.Ask, used by both /qtf and the panel's auto-ask. The two
differ only in how loud they are, so that is a flag rather than a second path:

  * manual (/qtf, /qtf ask <id>) prints "Asking your group...", a line per answer
    as it lands, and -- when the reply window closes -- a line for each member
    who did NOT answer. Whoever already got a live line is not printed again;
    if everybody answered, the window closes in silence.
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

-- questID -> set of peers already reported live, while a manual ask is waiting
-- for its reply window to close. A silent ask has nothing to report, so it
-- records nothing.
---@type table<number, table<QT.Peer, true>>
local pending = {}

---@param questID number
local function Report(questID)
    local printed = pending[questID] or {}
    pending[questID] = nil
    -- Driven by the group roster (ns.PeerLines), not by the peers we happen to
    -- have heard from, so a member without the addon is listed as "?" rather
    -- than omitted.
    local rows = ns.PeerLines(questID)
    if #rows == 0 then
        -- Nothing to list has two very different causes; ns.GroupChannel tells
        -- them apart (wording from docs/UX.md).
        if ns.GroupChannel() then
            ns.Print("None of your group has Quest Together Forever.")
        else
            ns.Print("Not in a group.")
        end
        return
    end
    -- Only the members who have NOT had a live line: repeating the others is the
    -- same answer twice, three seconds apart. What is left is, by construction,
    -- the unknowns -- which is exactly what the user still needs to be told.
    local missing = {}
    for _, r in ipairs(rows) do
        if not (r.peer and printed[r.peer]) then missing[#missing + 1] = r end
    end
    if #missing == 0 then return end
    ns.Print("Quest " .. questID .. " -- no answer from:")
    for _, r in ipairs(missing) do
        ns.Print("  " .. r.display .. ": " .. r.state)
    end
end

-- A line per answer while that quest's manual ask is still open. Printing live
-- during a request is presentation, which is why it lives here and not in the
-- transport layer.
ns.OnAnswer(function(peer, questID)
    local printed = pending[questID]
    if peer and printed then
        printed[peer] = true
        ns.Print("  " .. peer.name .. ": " .. ns.DescribePeerState(peer, questID))
    end
end)

-- Returns ok, err so a caller can choose to report the failure (manual /qtf does)
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
    -- A send that failed must return BEFORE the "Asking your group..." line and
    -- before the report timer: a 3-second wait for answers to a question nobody
    -- was asked would print a screenful of honest-looking "?" for no reason.
    if not ok then return false, err end
    if silent then return true end

    ns.Print("Asking your group about quest " .. questID .. "...")
    -- Already pending: the query went out again (a peer who just joined may not
    -- have heard the first one), but the timer already running will report it.
    if alreadyPending then return true end

    pending[questID] = {}
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(ns.REPLY_WINDOW, function() Report(questID) end)
    else
        Report(questID)
    end
    return true
end
