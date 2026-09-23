--[[----------------------------------------------------------------------------
UI -- the first visible surface: a minimal status popup.

A small frame that appears when a quest is open and reports, per group member,
whether they have completed it. Kept small: one Frame, a title, one body
FontString, no dragging.

  * shows when the quest frame opens, hides when it closes
  * /qtf ui forces it open solo, so the whole thing is testable without a group

Look: the stock tooltip border tinted bronze, filled with the quest frame's OWN
parchment -- copied at show time from whichever quest panel is on screen, so it is
the real texture (themed quests included) rather than a guessed file path, with
its tint. On parchment the text takes the quest text's own font, size and colour,
read from the quest frame's font strings the same way. It sits one frame
level BELOW the quest frame and slides out from under its right edge while fading
in. Every piece is optional: no parchment found keeps the dark tooltip fill, no
BackdropTemplate falls back to a plain dark texture, no quest frame on screen
means no slide (docs/TESTING.md, A7 and A15; /qtf parchment shows what was found).

States are coloured as in docs/UX.md (green / amber / blue / grey), but the words
stay: colour is never the only carrier of a state.

It renders the local player from the completion oracle (authoritative, live) and
the rest of the group from ns.PeerLines, which joins the group roster against the
Peers registry (tri-state: yes / no / unknown). Every group member gets a line,
whether or not they run the addon. Rendering never asks; the one place this file
does ask is the auto-ask on QUEST_DETAIL below, which goes through ns.Ask exactly
as /qtf does -- but silently, because this panel is already showing what chat would
otherwise repeat. Until a peer answers they show "?" and stay "?" -- never
flipping to "no" (the one mistake this addon exists to prevent).

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

local PANEL_W   = 290
local PANEL_PAD = 12
local TITLE_GAP = 6

-- Slide geometry, relative to the quest frame's TOPRIGHT. The panel starts fully
-- tucked under the quest frame and ends with its left border just under the
-- frame's edge, so it looks attached rather than floating.
local SLIDE_FROM = -PANEL_W
local SLIDE_TO   = -4
local SLIDE_Y    = -16
local SLIDE_TIME = 0.25   -- seconds

-- The stock tooltip look (measured: renders on this client, 2026-09-24). The
-- border texture is near-white, so tinting it gives the quest frame's bronze.
local BACKDROP = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local BRONZE = { 0.85, 0.66, 0.38, 1 }

-- Two palettes: light text on the dark tooltip fill, dark text on parchment.
-- State colours follow docs/UX.md (green / amber / blue / grey) in both.
local DARK = {
    title = "|cffffd100", hint = "|cff9d9d9d", body = { 1, 1, 1 }, shadow = true,
    yes = "|cff40ff40", no = "|cffffa040", onit = "|cff4da6ff", unk = "|cff9d9d9d",
}
-- body and title are replaced by the quest text's own colours when those can be
-- read (BorrowFonts); these are the fallbacks.
local PARCHMENT = {
    title = "|cff1a0d00", hint = "|cff4d3a26", body = { 0.10, 0.06, 0.02 }, shadow = false,
    yes = "|cff0f5c12", no = "|cff8f3a00", onit = "|cff143f8a", unk = "|cff4d3a26",
}
local palette = DARK

-- The quest frame's content panels, one of which is on screen whenever a quest
-- is. Each carries its own parchment.
local QUEST_PANELS = {
    "QuestFrameDetailPanel", "QuestFrameProgressPanel",
    "QuestFrameRewardPanel", "QuestFrameGreetingPanel",
}

-- The quest text's own font strings, to take font, size and colour from. First
-- one that exists wins: Mainline names first, then the 1.x ones.
local BODY_FONT_SOURCES  = {
    "QuestInfoDescriptionText", "QuestInfoObjectivesText",
    "QuestDescription", "QuestObjectiveText",
}
local TITLE_FONT_SOURCES = { "QuestInfoTitleHeader", "QuestTitleText" }

-- Since 9.0 a frame only has SetBackdrop through BackdropTemplate; before that it
-- is built in. This client has the template (seen 2026-09-24), but an unknown
-- template is an error, so it stays under pcall for the next client patch.
local function NewPanelFrame()
    local ok, f = pcall(CreateFrame, "Frame", nil, UIParent, "BackdropTemplate")
    if ok and f then return f end
    return CreateFrame("Frame", nil, UIParent)
end

-- A font object name, or the one the popup has always used (known to exist).
local function Font(name)
    if _G[name] then return name end
    return "GameFontNormalSmall"
end

local panel = NewPanelFrame()
panel:SetSize(PANEL_W, 60)
panel:SetFrameStrata("DIALOG")
panel:SetFrameLevel(50)

local skinned = false
if panel.SetBackdrop then
    skinned = pcall(panel.SetBackdrop, panel, BACKDROP)
end
local darkFill
if skinned then
    panel:SetBackdropColor(0.09, 0.09, 0.19, 0.92)
    panel:SetBackdropBorderColor(BRONZE[1], BRONZE[2], BRONZE[3], BRONZE[4])
else
    darkFill = panel:CreateTexture(nil, "BACKGROUND")
    darkFill:SetAllPoints(panel)
    darkFill:SetColorTexture(0, 0, 0, 0.85)
end

-- Filled in by CopyParchment; hidden until a parchment has been found.
local parch = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
parch:SetPoint("TOPLEFT", 4, -4)       -- the backdrop's insets: inside the border
parch:SetPoint("BOTTOMRIGHT", -4, 4)
parch:Hide()

-- Font objects for the dark fill; on parchment the quest text's font replaces them.
local TITLE_FONT = Font("GameFontNormal")
local SMALL_FONT = Font("GameFontHighlightSmall")

local title = panel:CreateFontString(nil, "OVERLAY", TITLE_FONT)
title:SetPoint("TOPLEFT", PANEL_PAD, -PANEL_PAD)
title:SetJustifyH("LEFT")

local questLabel = panel:CreateFontString(nil, "OVERLAY", SMALL_FONT)
questLabel:SetPoint("TOPRIGHT", -PANEL_PAD, -PANEL_PAD - 2)
questLabel:SetJustifyH("RIGHT")

local text = panel:CreateFontString(nil, "OVERLAY", SMALL_FONT)
text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -TITLE_GAP)
text:SetWidth(PANEL_W - 2 * PANEL_PAD)
text:SetJustifyH("LEFT")
text:SetJustifyV("TOP")
text:SetSpacing(2)

------------------------------------------------------------------------------
-- Parchment: borrowed from the quest frame, never guessed
------------------------------------------------------------------------------

-- What the last search found, for /qtf parchment (Diagnostics). Display only.
ns.uiParchment = { source = nil, copied = nil, tint = nil, font = nil }

-- The crop of the source texture, and how big that texture is on screen, so the
-- panel shows a piece of parchment at the same scale instead of the whole sheet
-- squashed into a strip.
local crop -- { l, r, t, b, w, h }

local function IsTexture(r)
    return type(r) == "table" and r.GetObjectType and r:GetObjectType() == "Texture"
end

local function Size(r)
    local w, h = r:GetWidth(), r:GetHeight()
    if type(w) ~= "number" or type(h) ~= "number" then return 0, 0 end
    return w, h
end

-- The parchment texture of whichever quest panel is on screen: its `Bg` key when
-- it has one, else the largest texture it owns.
local function FindParchment()
    for _, name in ipairs(QUEST_PANELS) do
        local p = _G[name]
        if type(p) == "table" and p.IsShown and p:IsShown() then
            if IsTexture(p.Bg) then return p.Bg, name .. ".Bg" end
            local best, bestArea = nil, 0
            if p.GetRegions then
                for _, r in ipairs({ p:GetRegions() }) do
                    if IsTexture(r) and r:IsShown() then
                        local w, h = Size(r)
                        if w * h > bestArea then best, bestArea = r, w * h end
                    end
                end
            end
            if best then return best, name .. " (largest texture)" end
        end
    end
end

local function CopyParchment()
    local src, source = FindParchment()
    if not src then return false end

    local how
    local atlas = src.GetAtlas and src:GetAtlas()
    if type(atlas) == "string" and atlas ~= "" and parch.SetAtlas then
        parch:SetAtlas(atlas)
        how = "atlas " .. atlas
    else
        local file = src.GetTexture and src:GetTexture()
        if file == nil then return false end
        parch:SetTexture(file)
        if src.GetTexCoord then parch:SetTexCoord(src:GetTexCoord()) end
        how = "file " .. tostring(file)
    end

    -- The quest frame may tint its sheet; without this ours came out brighter.
    local tint
    if src.GetVertexColor then
        local r, g, b = src:GetVertexColor()
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            parch:SetVertexColor(r, g, b)
            tint = ("%.2f %.2f %.2f"):format(r, g, b)
        end
    end

    -- GetTexCoord gives the four corners: UL, LL, UR, LR.
    local ulx, uly, _, lly, urx = parch:GetTexCoord()
    local w, h = Size(src)
    if type(ulx) == "number" and type(lly) == "number" and type(urx) == "number"
        and w > 0 and h > 0 then
        crop = { l = ulx, r = urx, t = uly, b = lly, w = w, h = h }
    else
        crop = nil
    end

    ns.uiParchment.source, ns.uiParchment.copied, ns.uiParchment.tint = source, how, tint
    return true
end

------------------------------------------------------------------------------
-- Fonts: borrowed from the quest text, like the parchment
------------------------------------------------------------------------------

local borrowed -- { body = font, title = font? } or nil

local function FindFont(names)
    for _, name in ipairs(names) do
        local fs = _G[name]
        if type(fs) == "table" and fs.GetObjectType and fs:GetObjectType() == "FontString"
            and fs.GetFont then
            local path, size, flags = fs:GetFont()
            if type(path) == "string" and type(size) == "number" and size > 0 then
                local r, g, b = fs:GetTextColor()
                local colour = (type(r) == "number" and type(g) == "number"
                    and type(b) == "number") and { r, g, b } or nil
                return { name = name, path = path, size = size, flags = flags, colour = colour }
            end
        end
    end
end

local function BorrowFonts()
    local body = FindFont(BODY_FONT_SOURCES)
    if not body then return nil end
    ns.uiParchment.font = ("%s  %s %s"):format(body.name, body.path, body.size)
    return { body = body, title = FindFont(TITLE_FONT_SOURCES) }
end

local function Hex(rgb)
    local function c(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return ("|cff%02x%02x%02x"):format(c(rgb[1]), c(rgb[2]), c(rgb[3]))
end

-- The palette for parchment: PARCHMENT, with the quest text's own colours.
local function ParchmentPalette()
    local p = {}
    for k, v in pairs(PARCHMENT) do p[k] = v end
    if borrowed then
        local body = borrowed.body.colour
        local head = borrowed.title and borrowed.title.colour or body
        if body then p.body = body end
        if head then p.title = Hex(head) end
    end
    return p
end

local function SetBorrowedFont(fs, f, size, fallback)
    if not (f and pcall(fs.SetFont, fs, f.path, size, f.flags or "")) then
        fs:SetFontObject(fallback)
    end
end

local function ApplyFonts(onParchment)
    if onParchment and borrowed then
        local body = borrowed.body
        local head = borrowed.title or body
        SetBorrowedFont(text, body, body.size, SMALL_FONT)
        SetBorrowedFont(questLabel, body, math.max(8, body.size - 2), SMALL_FONT)
        -- The quest title's face, but not its size: it would crowd the panel.
        SetBorrowedFont(title, head, math.min(head.size, body.size + 3), TITLE_FONT)
    else
        title:SetFontObject(TITLE_FONT)
        questLabel:SetFontObject(SMALL_FONT)
        text:SetFontObject(SMALL_FONT)
    end
end

-- Cut the middle of the sheet to the panel's size, at the sheet's own scale.
local function FitParchment()
    if not crop then return end
    local fx = math.min(1, PANEL_W / crop.w)
    local fy = math.min(1, (panel:GetHeight() or 0) / crop.h)
    local du, dv = crop.r - crop.l, crop.b - crop.t
    local l = crop.l + du * (1 - fx) / 2
    local t = crop.t + dv * (1 - fy) / 2
    parch:SetTexCoord(l, l + du * fx, t, t + dv * fy)
end

local function SetFontColour(fs, rgb, shadow)
    fs:SetTextColor(rgb[1], rgb[2], rgb[3])
    if shadow then fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
end

-- Switch between parchment and the dark fill, and the palette that goes with it.
local function ApplyLook(onParchment)
    palette = onParchment and ParchmentPalette() or DARK
    ApplyFonts(onParchment)
    if onParchment then parch:Show() else parch:Hide() end
    if skinned then
        panel:SetBackdropColor(0.09, 0.09, 0.19, onParchment and 0 or 0.92)
    elseif darkFill then
        if onParchment then darkFill:Hide() else darkFill:Show() end
    end
    title:SetText(palette.title .. "Quest Together Forever|r")
    SetFontColour(title, palette.body, palette.shadow)
    SetFontColour(questLabel, palette.body, palette.shadow)
    SetFontColour(text, palette.body, palette.shadow)
end

-- Take the parchment off the quest frame on screen. A failed copy keeps what we
-- had: the last parchment, or the dark fill if there never was one.
local function RefreshLook()
    local ok, found = pcall(CopyParchment)
    if ok and found then
        local fok, fonts = pcall(BorrowFonts)
        if fok and fonts then borrowed = fonts end
        ApplyLook(true)
    elseif palette == DARK then
        ApplyLook(false)
    end
end

ApplyLook(false)

------------------------------------------------------------------------------
-- Placement and the slide
------------------------------------------------------------------------------

local function QuestFrameShown()
    local qf = _G.QuestFrame
    return qf and qf.IsShown and qf:IsShown() and qf or nil
end

local function PlaceAt(x)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", _G.QuestFrame, "TOPRIGHT", x, SLIDE_Y)
end

-- No quest frame on screen (/qtf ui while solo): a fixed spot, above everything.
local function PlaceStandalone()
    panel:SetScript("OnUpdate", nil)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -100)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(50)
    panel:SetAlpha(1)
end

-- Put the panel just below the quest frame in draw order, so the frame covers it
-- while it slides. Only when the frame reports a usable level.
local function TuckUnder(qf)
    local strata = qf.GetFrameStrata and qf:GetFrameStrata()
    local level  = qf.GetFrameLevel and qf:GetFrameLevel()
    if type(strata) ~= "string" or type(level) ~= "number" then return false end
    panel:SetFrameStrata(strata)
    panel:SetFrameLevel(math.max(0, level - 1))
    return true
end

local function SlideOut()
    local qf = QuestFrameShown()
    if not qf then return PlaceStandalone() end
    if not TuckUnder(qf) then
        -- Cannot get under the frame: a slide would run across its face. Just
        -- appear in the final spot, above it as before.
        panel:SetScript("OnUpdate", nil)
        PlaceAt(SLIDE_TO)
        panel:SetAlpha(1)
        return
    end

    local t = 0
    PlaceAt(SLIDE_FROM)
    panel:SetAlpha(0)
    panel:SetScript("OnUpdate", function(self, elapsed)
        t = t + (tonumber(elapsed) or SLIDE_TIME)
        local p = math.min(1, t / SLIDE_TIME)
        local eased = 1 - (1 - p) ^ 3          -- ease-out cubic
        PlaceAt(SLIDE_FROM + (SLIDE_TO - SLIDE_FROM) * eased)
        self:SetAlpha(math.min(1, p * 1.5))    -- opaque a little before it stops
        if p >= 1 then self:SetScript("OnUpdate", nil) end
    end)
end

------------------------------------------------------------------------------
-- Content
------------------------------------------------------------------------------

local function DescribeSelf(qid)
    local done, why = ns.SafeIsDone(qid)
    if done == true  then return "yes - already completed" end
    if done == false then
        if ns.SafeInLog(qid) then return "on it now" end
        return "no - has not completed it"
    end
    return "? (oracle: " .. (why or "unknown") .. ")"
end

-- Colour a state by its leading word. The words themselves are the ones
-- DescribeSelf and ns.DescribePeerState produce; anything unrecognised is left
-- uncoloured rather than guessed at.
local function Paint(state)
    local c
    if state:find("^yes") then c = palette.yes
    elseif state:find("^no") then c = palette.no
    elseif state:find("^on it") then c = palette.onit
    elseif state:find("^%?") then c = palette.unk
    end
    if not c then return state end
    return c .. state .. "|r"
end

local function Row(name, state)
    return name .. ":  " .. Paint(state)
end

local function Hint(s)
    return palette.hint .. s .. "|r"
end

local function Update()
    local qid = ns.LocalQuestID()
    local lines = {}

    if not qid then
        questLabel:SetText("")
        lines[#lines + 1] = Hint("No quest open.")
        lines[#lines + 1] = Hint("Open a quest, or /qtf ask <id>.")
    else
        questLabel:SetText(Hint("Quest " .. qid))
        lines[#lines + 1] = Row("You", DescribeSelf(qid))
        -- Roster-driven (ns.PeerLines): every group member gets a line, including
        -- the ones without the addon. Nothing to list has two causes, and
        -- ns.GroupChannel tells them apart (wording from docs/UX.md).
        local rows = ns.PeerLines(qid)
        if #rows == 0 then
            if ns.GroupChannel() then
                lines[#lines + 1] = Hint("None of your group has Quest Together Forever.")
            else
                lines[#lines + 1] = Hint("Not in a group.")
            end
        else
            for _, r in ipairs(rows) do
                lines[#lines + 1] = Row(r.display, r.state)
            end
        end
    end

    text:SetText(table.concat(lines, "\n"))
    local h = PANEL_PAD + (title:GetStringHeight() or 12) + TITLE_GAP
        + (text:GetStringHeight() or 0) + PANEL_PAD
    panel:SetHeight(math.max(48, h))
    FitParchment()
end

function ns.commands.ui()
    if panel:IsShown() then
        panel:Hide()
        ns.Print("Status panel hidden.")
    else
        if QuestFrameShown() then RefreshLook(); SlideOut() else PlaceStandalone() end
        panel:Show()
        Update()
        ns.Print("Status panel shown. /qtf ui toggles it.")
    end
end

------------------------------------------------------------------------------
-- Show / hide wiring
------------------------------------------------------------------------------

-- Slides out only when it was hidden: switching to another quest while the
-- panel is up just repaints it.
local function ShowPanel()
    -- Every opening: the quest on screen may use a different parchment.
    if QuestFrameShown() then RefreshLook() end
    if not panel:IsShown() then
        SlideOut()
        panel:Show()
    end
    Update()
end

-- The quest frame's own show/hide is the most reliable "a quest is open" signal
-- we have on this beta client. Hook it when the frame keeps its Mainline name
-- (docs/MEASUREMENTS.md, Q5, is still open); /qtf ui is the fallback when it does
-- not.
if _G.QuestFrame then
    _G.QuestFrame:HookScript("OnShow", function() ShowPanel() end)
    _G.QuestFrame:HookScript("OnHide", function()
        panel:SetScript("OnUpdate", nil)
        panel:Hide()
    end)
end

-- Auto-ask: opening a quest asks the group about it, so the panel populates
-- without a manual /qtf. Silent -- the answers land in the panel in front of the
-- user, and printing them as well meant a burst of chat for every quest opened.
--
-- It fires for every way a quest can be on screen: offered (QUEST_DETAIL), in
-- progress (QUEST_PROGRESS) and ready to turn in (QUEST_COMPLETE). The dedupe is
-- also cleared on every roster change (below): someone who joined after the last
-- ask has never been asked. Solo stays quiet (no group to ask).
local lastAutoAsk   = nil
local lastAutoAskAt = 0

-- The dedupe exists for ONE reason: QUEST_DETAIL can fire more than once for a
-- single opening. It must not outlive that opening -- a cached answer goes stale
-- the moment the peer accepts or turns in the quest, and re-opening the quest is
-- how the user asks "and now?". So the same quest is skipped only within a few
-- seconds. Without a clock (ns.Now() == 0) the old "same as last" rule stands.
local AUTO_ASK_WINDOW = 5

local function OnQuestOpen()
    ShowPanel()
    local qid = ns.LocalQuestID()
    if not (qid and ns.GroupChannel() and ns.Ask) then return end

    local now = ns.Now()
    local repeated = (qid == lastAutoAsk)
        and (now == 0 or now - lastAutoAskAt < AUTO_ASK_WINDOW)
    if repeated then return end

    lastAutoAsk, lastAutoAskAt = qid, now
    ns.Ask(qid, true)
end

-- Own event frame, so Core never learns about these events (the same discipline
-- as Diagnostics). The three QUEST_* events each put one quest on screen;
-- GROUP_ROSTER_UPDATE refreshes the peer list.
local ev = CreateFrame("Frame")
ev:RegisterEvent("QUEST_DETAIL")
ev:RegisterEvent("QUEST_PROGRESS")
ev:RegisterEvent("QUEST_COMPLETE")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function(_, event)
    if event ~= "GROUP_ROSTER_UPDATE" then
        -- Defer one frame: GetQuestID() may not be populated at the exact moment
        -- the event fires, and there is no local Lua to catch a bad read.
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, OnQuestOpen)
        else
            OnQuestOpen()
        end
    else
        -- The group changed, so the last auto-ask no longer speaks for it: a
        -- member who joined since has never been asked anything.
        lastAutoAsk = nil
        if panel:IsShown() then Update() end
    end
end)

------------------------------------------------------------------------------
-- Registrations: repaint on answers, and the /qtf ui help line
------------------------------------------------------------------------------

-- One listener among however many are registered: the panel repaints, and
-- whatever else cares about the answer is none of this file's business.
ns.OnAnswer(function()
    if panel:IsShown() then Update() end
end)

ns.AddHelp("/qtf ui", "toggle the status panel")

ns.AddDebugSection("status panel", function(out)
    out("  shown:            " .. ns.yn(panel:IsShown()))
    out("  QuestFrame:       " .. ns.yn(_G.QuestFrame)
        .. "   shown: " .. ns.yn(_G.QuestFrame and _G.QuestFrame:IsShown()))
    out("  last auto-ask:    quest " .. ns.SafeStr(lastAutoAsk) .. " at " .. ns.SafeStr(lastAutoAskAt))
    -- Filled in by the parchment look, when that is present.
    local look = ns.uiParchment
    if type(look) == "table" and look.source == nil then
        out("  parchment:        none borrowed yet -- open a quest, then copy again")
    elseif type(look) == "table" then
        for _, k in ipairs({ "source", "copied", "tint", "font" }) do
            out(("  parchment %-7s %s"):format(k, ns.SafeStr(look[k])))
        end
    end
end)

panel:Hide()
