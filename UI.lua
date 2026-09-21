--[[----------------------------------------------------------------------------
UI -- the first visible surface: a minimal status popup.

A small frame that appears when a quest is open and reports, per group member,
whether they have completed it. Deliberately the *simplest possible* thing that
is useful: one Frame, one FontString, no layout, no skinning, no dragging.

  * shows when the quest frame opens, hides when it closes
  * /qt ui forces it open solo, so the whole thing is testable without a group

It renders the local player from the completion oracle (authoritative, live) and
every known peer from the Peers registry (tri-state: yes / no / unknown). Rendering
never asks; the one place this file does ask is the auto-ask on QUEST_DETAIL below,
which goes through ns.Ask exactly as /qt does -- but silently, because this panel
is already showing what chat would otherwise repeat. Until a peer answers they
show "?" and stay "?" -- never flipping to "no" (the one mistake this addon
exists to prevent).

Known gap: only peers we have HEARD FROM are listed. A group member without the
addon is absent from the panel rather than shown as "?", and an empty peer list
reads "(not in a group)" even when grouped.

Deliberately NOT here yet:
  * eligibility / prerequisite status -- no client API for it (see
    docs/ARCHITECTURE.md, "Non-goals"); a future dependency on a quest database
    (Grail) would be needed.
  * anchoring into the quest frame's own layout -- we float beside it instead.

This file's position in the .toc does not matter. It registers an answer listener
and a help line into the registries Compat.lua declares, rather than wrapping
whatever Commands and Diagnostics happened to have set before it.
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
---@cast ns QT.Namespace

ns.commands = ns.commands or {}

------------------------------------------------------------------------------
-- The panel
------------------------------------------------------------------------------

local PANEL_W   = 260
local PANEL_PAD = 10

local panel = CreateFrame("Frame", nil, UIParent)
panel:SetSize(PANEL_W, 60)
panel:SetFrameStrata("DIALOG")
panel:SetFrameLevel(50)

local bg = panel:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(panel)
bg:SetColorTexture(0, 0, 0, 0.85)

local text = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
text:SetPoint("TOPLEFT", PANEL_PAD, -PANEL_PAD)
text:SetWidth(PANEL_W - 2 * PANEL_PAD)
text:SetJustifyH("LEFT")
text:SetJustifyV("TOP")

-- Float beside the quest frame when it exists; otherwise top-right of the screen.
if _G.QuestFrame then
    panel:SetPoint("TOPLEFT", _G.QuestFrame, "TOPRIGHT", 8, 0)
else
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -100)
end

------------------------------------------------------------------------------
-- Content
------------------------------------------------------------------------------

local function DescribeSelf(qid)
    local done, why = ns.SafeIsDone(qid)
    if done == true  then return "You: yes - already completed" end
    if done == false then return "You: no - has not completed it" end
    return "You: ? (oracle: " .. (why or "unknown") .. ")"
end

local function Update()
    local qid = ns.LocalQuestID()
    local lines = { "|cff33ff99Quest Together|r" }

    if not qid then
        lines[#lines + 1] = "No quest open."
        lines[#lines + 1] = "Open a quest, or /qt ask <id>."
    else
        lines[#lines + 1] = "Quest " .. qid
        lines[#lines + 1] = DescribeSelf(qid)
        if next(ns.peers) == nil then
            lines[#lines + 1] = "(not in a group)"
        else
            for _, p in pairs(ns.peers) do
                lines[#lines + 1] = "  " .. p.name .. ": " .. ns.DescribePeerState(p, qid)
            end
        end
    end

    text:SetText(table.concat(lines, "\n"))
    panel:SetHeight(math.max(60, text:GetStringHeight() + 2 * PANEL_PAD))
end

function ns.commands.ui()
    if panel:IsShown() then
        panel:Hide()
        ns.Print("Status panel hidden.")
    else
        panel:Show()
        Update()
        ns.Print("Status panel shown. /qt ui toggles it.")
    end
end

------------------------------------------------------------------------------
-- Show / hide wiring
------------------------------------------------------------------------------

local function ShowPanel()
    panel:Show()
    Update()
end

-- The quest frame's own show/hide is the most reliable "a quest is open" signal
-- we have on this beta client. Hook it when the frame keeps its Mainline name
-- (docs/MEASUREMENTS.md, Q5, is still open); /qt ui is the fallback when it does
-- not.
if _G.QuestFrame then
    _G.QuestFrame:HookScript("OnShow", function() ShowPanel() end)
    _G.QuestFrame:HookScript("OnHide", function() panel:Hide() end)
end

-- Auto-ask: opening a quest asks the group about it, so the panel populates
-- without a manual /qt. Silent -- the answers land in the panel in front of the
-- user, and printing them as well meant a burst of chat for every quest opened.
--
-- Deduped by quest ID so a re-fired QUEST_DETAIL for the same quest does not
-- spam the group; a different quest asks again. The dedupe is cleared on every
-- roster change (below): someone who joined after the last ask has never been
-- asked, and would otherwise stay "?" for as long as that quest stayed open.
-- Solo stays quiet (no group to ask).
local lastAutoAsk = nil

local function OnQuestOpen()
    ShowPanel()
    local qid = ns.LocalQuestID()
    if qid and qid ~= lastAutoAsk and ns.GroupChannel() and ns.Ask then
        lastAutoAsk = qid
        ns.Ask(qid, true)
    end
end

-- Own event frame, so Core never learns about these events (the same discipline
-- as Diagnostics). QUEST_DETAIL fires when a specific quest's detail is shown;
-- GROUP_ROSTER_UPDATE refreshes the peer list.
local ev = CreateFrame("Frame")
ev:RegisterEvent("QUEST_DETAIL")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function(_, event)
    if event == "QUEST_DETAIL" then
        -- Defer one frame: GetQuestID() may not be populated at the exact moment
        -- QUEST_DETAIL fires, and there is no local Lua to catch a bad read.
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, OnQuestOpen)
        else
            OnQuestOpen()
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- The group changed, so the last auto-ask no longer speaks for it: a
        -- member who joined since has never been asked anything.
        lastAutoAsk = nil
        if panel:IsShown() then Update() end
    end
end)

------------------------------------------------------------------------------
-- Registrations: repaint on answers, and the /qt ui help line
------------------------------------------------------------------------------

-- One listener among however many are registered: the panel repaints, and
-- whatever else cares about the answer is none of this file's business.
ns.OnAnswer(function()
    if panel:IsShown() then Update() end
end)

ns.AddHelp("/qt ui", "toggle the status panel")

panel:Hide()
