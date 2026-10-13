-- Modules\voteWindow.lua
-- Our own voting window (#64). By default it replaces RCLootCouncil's voting
-- frame; RCPL_DB.votingWindow can also be "alongside" (both) or "off".
--
-- It draws only. Every vote, award and item switch goes through
-- RCLootCouncil itself (the same comms, dialog and SwitchSession its own
-- frame uses), and it reads RCLootCouncil's own loot table, so the loot
-- master's settings and other addons see no difference.
--
-- Safety net: if the window errors, or RCLootCouncil is a version we haven't
-- tested (RCPL_Data_VotingWindowMode), RCLootCouncil's frame opens instead
-- and chat says why.

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCVotingFrame = addon:GetModule("RCVotingFrame")
local RCPLAddon = addon:GetModule("RCLootCouncil_PriorityLoot")
local VoteWindow = RCPLAddon:NewModule("RCPLVoteWindow", "AceHook-3.0", "AceTimer-3.0")
local LibDialog = LibStub("LibDialog-1.1")
local L = LibStub("AceLocale-3.0"):GetLocale("RCLootCouncil")

local Log = RCPL_Log or { debug = function() end, warn = function() end }

-- New site's dark palette (WGA Raid Hub revamp).
local C = {
    canvas  = { 0.043, 0.055, 0.075, 0.97 },
    surface = { 0.075, 0.094, 0.125, 1 },
    raised  = { 0.102, 0.125, 0.161, 1 },
    line    = { 0.129, 0.157, 0.200, 1 },
    blue    = { 0.357, 0.612, 0.961, 1 },
    text    = { 0.902, 0.922, 0.949, 1 },
    muted   = { 0.55, 0.60, 0.67, 1 },
}

local ROW_H   = 22
local WIDTH   = 760
local HEIGHT  = 520
local TAB_SZ  = 30

-- x offset, width, header text, justify
local COLS = {
    { key = "name",     x = 10,  w = 130, title = "Name" },
    { key = "response", x = 145, w = 170, title = "Response" },
    { key = "prio",     x = 320, w = 90,  title = "Priority" },
    { key = "ilvl",     x = 415, w = 45,  title = "ilvl",  just = "CENTER" },
    { key = "diff",     x = 460, w = 40,  title = "Diff",  just = "CENTER" },
    { key = "roll",     x = 500, w = 40,  title = "Roll",  just = "CENTER" },
    { key = "votes",    x = 540, w = 45,  title = "Votes", just = "CENTER" },
    { key = "note",     x = 590, w = 22,  title = "" },
}
local VOTE_X, AWARD_X, BTN_W = 615, 680, 60
local RESPONSE_X = 145

local frame
local rows = {}
local extraW = 0   -- how much wider than WIDTH the window has been dragged

-- Places a set of column cells. Extra width from resizing goes to the
-- Response column; everything to its right shifts over.
local function PlaceCells(cells)
    for _, col in ipairs(COLS) do
        local fs = cells[col.key]
        local shift = col.x > RESPONSE_X and extraW or 0
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", col.x + shift, 0)
        fs:SetWidth(col.w + (col.key == "response" and extraW or 0))
    end
end

local function PlaceRow(r)
    PlaceCells(r.cells)
    r.vote:ClearAllPoints()
    r.vote:SetPoint("LEFT", VOTE_X + extraW, 0)
    r.award:ClearAllPoints()
    r.award:SetPoint("LEFT", AWARD_X + extraW, 0)
end

local tabs = {}
local fellBack = false   -- error already reported this session
local versionWarned = false

local function Paint(tex, color) tex:SetColorTexture(unpack(color)) end

local function Solid(parent, color, layer)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    Paint(t, color)
    return t
end

-- 1px outline around a frame, drawn as four thin textures.
local function Outline(f, color)
    local top = Solid(f, color, "BORDER"); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
    local bot = Solid(f, color, "BORDER"); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(1)
    local lft = Solid(f, color, "BORDER"); lft:SetPoint("TOPLEFT"); lft:SetPoint("BOTTOMLEFT"); lft:SetWidth(1)
    local rgt = Solid(f, color, "BORDER"); rgt:SetPoint("TOPRIGHT"); rgt:SetPoint("BOTTOMRIGHT"); rgt:SetWidth(1)
end

local function Text(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- Flat button. primary = brand blue fill with dark text, else neutral grey.
local function Button(parent, w, h, label, primary)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = Solid(b, primary and C.blue or C.raised)
    b.bg:SetAllPoints()
    Outline(b, primary and C.blue or C.line)
    b.label = Text(b, "GameFontHighlightSmall", "CENTER")
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    if primary then
        b.label:SetTextColor(0.05, 0.07, 0.1)
        -- WoW's default black text shadow smears dark text on a light fill.
        b.label:SetShadowOffset(0, 0)
    end
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    function b:SetText(t) self.label:SetText(t) end
    return b
end

local function Tooltip(owner, title, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title)
    for _, line in ipairs(lines or {}) do GameTooltip:AddLine(line, 1, 1, 1, true) end
    GameTooltip:Show()
end

local function HideTooltip() GameTooltip:Hide() end

------------------------------------------------------------------------
-- Voting: the same steps as RCLootCouncil's own Vote button
-- (RCVotingFrame.SetCellVote), including the loot master's settings.
------------------------------------------------------------------------
local function ToggleVote(session, name)
    local lootTable = RCVotingFrame:GetLootTable()
    local entry = lootTable[session]
    local cand = entry and entry.candidates[name]
    if not cand then return end
    local CommsRestrictions = addon.Require and addon.Require "Services.CommsRestrictions"
    if CommsRestrictions and CommsRestrictions:IsRestricted() then
        return addon:Print(L.chat_restrictions_enabled)
    end
    if IsAltKeyDown() then
        return RCVotingFrame:RequestVotes(session)
    end
    if cand.haveVoted then
        addon:Send("group", "vote", session, name, -1)
        cand.haveVoted = false
        local any = false
        for _, c in pairs(entry.candidates) do
            if c.haveVoted then any = true end
        end
        entry.haveVoted = any
    else
        if not addon.mldb.selfVote and addon:UnitIsUnit("player", name) then
            return addon:Print(L["The Master Looter doesn't allow votes for yourself."])
        end
        if not addon.mldb.multiVote and entry.haveVoted then
            return addon:Print(L["The Master Looter doesn't allow multiple votes."])
        end
        addon:Send("group", "vote", session, name, 1)
        cand.haveVoted = true
        entry.haveVoted = true
    end
    VoteWindow:Refresh()
end

local function Award(session, name)
    local cand = RCVotingFrame:GetLootTable()[session].candidates[name]
    LibDialog:Spawn("RCLOOTCOUNCIL_CONFIRM_AWARD", RCVotingFrame:GetAwardPopupData(session, name, cand))
end

-- Mirrors RCVotingFrame.SetCellVotes: what this player may see of the votes.
local function VisibleVotes(entry, cand)
    local mldb = addon.mldb or {}
    local count = cand.votes or 0
    if mldb.hideVotes and not entry.haveVoted and addon.isCouncil then count = 0 end
    local showVoters = (not mldb.anonymousVoting or (addon:Getdb().showForML and addon.isMasterLooter))
        and (not mldb.hideVotes or entry.haveVoted or (mldb.observe and not addon.isCouncil))
    return count, showVoters
end

------------------------------------------------------------------------
-- Building
------------------------------------------------------------------------
local function CreateRow(i)
    local r = CreateFrame("Frame", nil, frame.content)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("RIGHT", frame.content, "RIGHT")
    r.bg = Solid(r, i % 2 == 0 and C.surface or C.canvas)
    r.bg:SetAllPoints()
    r.cells = {}
    for _, col in ipairs(COLS) do
        r.cells[col.key] = Text(r, "GameFontHighlightSmall", col.just)
    end
    -- Hover targets for the votes and note tooltips.
    for _, key in ipairs({ "votes", "note", "response" }) do
        local hit = CreateFrame("Frame", nil, r)
        hit:SetAllPoints(r.cells[key])
        hit:SetScript("OnLeave", HideTooltip)
        r[key .. "Hit"] = hit
    end
    r.vote = Button(r, BTN_W, ROW_H - 4, L["Vote"])
    r.award = Button(r, BTN_W, ROW_H - 4, L["Award"], true)
    PlaceRow(r)
    rows[i] = r
    return r
end

local function CreateTab(i)
    local t = CreateFrame("Button", nil, frame)
    t:SetSize(TAB_SZ, TAB_SZ)
    t:SetPoint("TOPLEFT", 12 + (i - 1) * (TAB_SZ + 4), -40)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetPoint("TOPLEFT", 2, -2)
    t.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    t.border = Solid(t, C.line, "BACKGROUND")
    t.border:SetAllPoints()
    t.check = t:CreateTexture(nil, "OVERLAY")
    t.check:SetSize(14, 14)
    t.check:SetPoint("BOTTOMRIGHT", 2, -2)
    t.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    t:SetScript("OnClick", function() RCVotingFrame:SwitchSession(i) end)
    t:SetScript("OnLeave", HideTooltip)
    tabs[i] = t
    return t
end

local function Build()
    frame = CreateFrame("Frame", "RCPLVoteWindow", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(f) f:StopMovingOrSizing(); f:SetUserPlaced(true) end)
    frame:Hide()

    local bg = Solid(frame, C.canvas); bg:SetAllPoints()
    Outline(frame, C.line)
    local header = Solid(frame, C.surface, "ARTWORK")
    header:SetPoint("TOPLEFT", 1, -1); header:SetPoint("TOPRIGHT", -1, -1); header:SetHeight(32)
    local accent = Solid(frame, C.blue, "OVERLAY")
    accent:SetPoint("TOPLEFT", header, "BOTTOMLEFT"); accent:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT"); accent:SetHeight(1)

    local title = Text(frame, "GameFontNormal")
    title:SetPoint("LEFT", header, "LEFT", 12, 0)
    title:SetText("Loot Council")
    title:SetTextColor(unpack(C.text))

    -- Same behaviour as RCLootCouncil's Abort/Close button.
    frame.close = Button(frame, 70, 22, _G.CLOSE)
    frame.close:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    frame.close:SetScript("OnClick", function()
        if addon.isMasterLooter and RCVotingFrame:IsActive() then
            LibDialog:Spawn("RCLOOTCOUNCIL_CONFIRM_ABORT")
        else
            frame:Hide()
        end
    end)

    -- Everything our window doesn't do (award for a reason, change response,
    -- reannounce, rolls, filters) stays in RCLootCouncil's frame.
    frame.rcBtn = Button(frame, 150, 22, "RCLootCouncil window")
    frame.rcBtn:SetPoint("RIGHT", frame.close, "LEFT", -6, 0)
    frame.rcBtn:SetScript("OnClick", function()
        RCVotingFrame.frame:Show()
        RCVotingFrame:SwitchSession(RCVotingFrame:GetCurrentSession())
    end)
    frame.rcBtn:SetScript("OnEnter", function(b)
        Tooltip(b, "RCLootCouncil window", { "Award for a reason, change responses, reannounce, rolls and filters." })
    end)
    frame.rcBtn:SetScript("OnLeave", HideTooltip)

    -- Item header
    frame.itemIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.itemIcon:SetSize(40, 40)
    frame.itemIcon:SetPoint("TOPLEFT", 12, -80)
    frame.itemLink = Text(frame, "GameFontNormalLarge")
    frame.itemLink:SetPoint("TOPLEFT", frame.itemIcon, "TOPRIGHT", 10, -2)
    frame.itemLink:SetWidth(420)
    frame.itemInfo = Text(frame, "GameFontHighlightSmall")
    frame.itemInfo:SetPoint("TOPLEFT", frame.itemLink, "BOTTOMLEFT", 0, -4)
    frame.itemInfo:SetTextColor(unpack(C.muted))
    frame.awarded = Text(frame, "GameFontNormal", "RIGHT")
    frame.awarded:SetPoint("TOPRIGHT", -12, -84)
    frame.voted = Text(frame, "GameFontHighlightSmall", "RIGHT")
    frame.voted:SetPoint("TOPRIGHT", frame.awarded, "BOTTOMRIGHT", 0, -4)

    -- Column headers
    local headRow = CreateFrame("Frame", nil, frame)
    headRow:SetPoint("TOPLEFT", 1, -132)
    headRow:SetPoint("TOPRIGHT", -1, -132)
    headRow:SetHeight(20)
    local hb = Solid(headRow, C.surface); hb:SetAllPoints()
    frame.headCells = {}
    for _, col in ipairs(COLS) do
        local fs = Text(headRow, "GameFontNormalSmall", col.just)
        fs:SetText(col.title)
        fs:SetTextColor(unpack(C.muted))
        frame.headCells[col.key] = fs
    end
    PlaceCells(frame.headCells)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 1, -152)
    scroll:SetPoint("BOTTOMRIGHT", -24, 8)
    frame.content = CreateFrame("Frame", nil, scroll)
    frame.content:SetSize(WIDTH - 26, 1)
    scroll:SetScrollChild(frame.content)

    -- Drag the bottom-right corner to resize. Being a named, user-placed
    -- frame, WoW remembers the size and position between sessions.
    frame:SetResizable(true)
    frame:SetResizeBounds(WIDTH, 300, 1400, 1100)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(scroll:GetFrameLevel() + 5)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing(); frame:SetUserPlaced(true) end)
    frame:SetScript("OnSizeChanged", function(f, w)
        extraW = math.max(0, math.floor(w - WIDTH))
        f.content:SetWidth(w - 26)
        PlaceCells(f.headCells)
        for _, r in ipairs(rows) do PlaceRow(r) end
    end)

    -- The full priority order panel docks to whichever voting window is shown.
    frame:SetScript("OnShow", function(f) if RCPL_VotingPanel_AttachTo then RCPL_VotingPanel_AttachTo(f) end end)
end

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------
local function PriorityRank(text)
    return tonumber(text:match("^(%d+)")) or 999
end

local function DrawTabs(lootTable, session)
    for _, t in ipairs(tabs) do t:Hide() end
    for i, entry in ipairs(lootTable) do
        local t = tabs[i] or CreateTab(i)
        t.icon:SetTexture(entry.texture)
        t.icon:SetDesaturated(entry.awarded and true or false)
        t.check:SetShown(entry.awarded and true or false)
        Paint(t.border, i == session and C.blue or C.line)
        t:SetScript("OnEnter", function(b)
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(entry.link)
            GameTooltip:Show()
        end)
        t:Show()
    end
end

local function DrawHeader(entry)
    frame.itemIcon:SetTexture(entry.texture)
    frame.itemLink:SetText(entry.link)
    local typeText = addon:GetItemTypeText(entry.link, entry.subType, entry.equipLoc, entry.typeID,
        entry.subTypeID, entry.classes, entry.token, entry.relic) or ""
    local owner = entry.owner and ("  -  " .. addon.Ambiguate(entry.owner)) or ""
    frame.itemInfo:SetText(_G.ITEM_LEVEL_ABBR .. " " .. (entry.ilvl or "?") .. "  " .. typeText .. owner)

    if entry.baggedInSession then
        frame.awarded:SetText(L["The item will be awarded later"])
    elseif entry.awarded then
        frame.awarded:SetText(L["Item was awarded to"] .. " " .. addon:GetUnitClassColoredName(entry.awarded))
    else
        frame.awarded:SetText("")
    end

    -- RCLootCouncil already works out "x out of y have voted"; reuse its text.
    local rr = RCVotingFrame.frame and RCVotingFrame.frame.rollResult
    if rr and rr.text then
        frame.voted:SetText(rr.text:GetText() or "")
        frame.voted:SetTextColor(rr.text:GetTextColor())
    end
end

local function SortedCandidates(entry, itemID)
    local list = {}
    for name, cand in pairs(entry.candidates) do
        -- Respect the filters set in RCLootCouncil's frame (passes, ranks, ...).
        local ok, show = pcall(RCVotingFrame.filterFunc, nil, { name = name })
        if not ok or show then
            local prioText, prioColor = RCPL_Data_GetPlayerPriority(name, itemID, entry.equipLoc, entry.link)
            local response = addon:GetResponse(entry.typeCode or entry.equipLoc, cand.response) or {}
            list[#list + 1] = {
                name = name, cand = cand, response = response,
                prioText = prioText, prioColor = prioColor, prioRank = PriorityRank(prioText),
            }
        end
    end
    -- Response first (as RCLootCouncil sorts), then our priority order, then votes.
    table.sort(list, function(a, b)
        local sa, sb = a.response.sort or 999, b.response.sort or 999
        if sa ~= sb then return sa < sb end
        if a.prioRank ~= b.prioRank then return a.prioRank < b.prioRank end
        if (a.cand.votes or 0) ~= (b.cand.votes or 0) then return (a.cand.votes or 0) > (b.cand.votes or 0) end
        return a.name < b.name
    end)
    return list
end

local function DrawRow(r, session, entry, item)
    local name, cand = item.name, item.cand
    local c = addon:GetClassColor(cand.class)
    r.cells.name:SetText(addon.Ambiguate(name))
    r.cells.name:SetTextColor(c.r, c.g, c.b)

    r.cells.response:SetText(item.response.text or "")
    r.cells.response:SetTextColor(unpack(item.response.color or C.text))
    r.responseHit:SetScript("OnEnter", function(hit)
        if cand.response == "AWARDED" and cand.real_response then
            Tooltip(hit, addon:GetColoredResponseText(entry.typeCode or entry.equipLoc, cand.real_response))
        end
    end)

    r.cells.prio:SetText(item.prioText)
    r.cells.prio:SetTextColor(item.prioColor.r, item.prioColor.g, item.prioColor.b)

    local ilvl = tonumber(cand.ilvl)
    r.cells.ilvl:SetText(ilvl and addon.round(ilvl) or "")
    local diff = tonumber(cand.diff)
    r.cells.diff:SetText(diff or "")
    r.cells.diff:SetTextColor(unpack(diff and diff > 0 and { 0, 1, 0 } or diff and diff < 0 and { 1, 0.3, 0.3 } or C.muted))
    r.cells.roll:SetText(cand.roll or "")

    local count, showVoters = VisibleVotes(entry, cand)
    r.cells.votes:SetText(count)
    r.votesHit:SetScript("OnEnter", function(hit)
        if not showVoters then return end
        local names = {}
        for i, voter in ipairs(cand.voters or {}) do names[i] = addon:GetUnitClassColoredName(voter) end
        Tooltip(hit, L["Voters"], names)
    end)

    r.cells.note:SetText(cand.note and "|TInterface\\BUTTONS\\UI-GuildButton-PublicNote-Up:14|t" or "")
    r.noteHit:SetScript("OnEnter", function(hit)
        if cand.note then Tooltip(hit, _G.LABEL_NOTE, { cand.note }) end
    end)

    local open = RCVotingFrame:IsActive() and not entry.awarded
    local canVote = open and (addon.isCouncil or addon.isMasterLooter)
    r.vote:SetShown(canVote)
    r.vote:SetText(cand.haveVoted and L["Unvote"] or L["Vote"])
    r.vote:SetScript("OnClick", function() ToggleVote(session, name) end)
    r.award:SetShown(open and addon.isMasterLooter)
    r.award:SetScript("OnClick", function() Award(session, name) end)
    r:Show()
end

local function Draw()
    local lootTable = RCVotingFrame:GetLootTable()
    local session = RCVotingFrame:GetCurrentSession()
    local entry = lootTable and lootTable[session]
    if not entry then return end
    local itemID = tonumber(entry.link and entry.link:match("item:(%d+)"))

    DrawTabs(lootTable, session)
    DrawHeader(entry)
    local list = SortedCandidates(entry, itemID)
    for _, r in ipairs(rows) do r:Hide() end
    for i, item in ipairs(list) do
        DrawRow(rows[i] or CreateRow(i), session, entry, item)
    end
    frame.content:SetHeight(math.max(1, #list * ROW_H))
end

------------------------------------------------------------------------
-- Safety net and RCLootCouncil hooks
------------------------------------------------------------------------
local function FallBack(err)
    if frame then frame:Hide() end
    -- pcall: this can run inside RCLootCouncil's own Update, and must never
    -- throw back into it.
    pcall(function()
        RCVotingFrame.frame:Show()
        RCVotingFrame:SwitchSession(RCVotingFrame:GetCurrentSession())
    end)
    if not fellBack then
        fellBack = true
        print("|cFFFF8000[RCPL]|r Our voting window hit an error, so RCLootCouncil's own window is open instead."
            .. " Please report this: " .. tostring(err))
    end
    Log.warn("Vote window fell back: %s", tostring(err))
end

-- Redraws if shown. Any error hands the session to RCLootCouncil's frame.
function VoteWindow:Refresh()
    if not (frame and frame:IsShown()) then return end
    local ok, err = pcall(Draw)
    if not ok then FallBack(err) end
end

-- Returns true when our window is up.
local function ShowOurs()
    local ok, err = pcall(function()
        if not frame then Build() end
        frame:Show()
        Draw()
    end)
    if not ok then FallBack(err) end
    return ok
end

-- Wraps RCVotingFrame:Show so auto-open and /rc open pick the right window.
function VoteWindow:OnRCShow(rc)
    self.hooks[RCVotingFrame].Show(rc)
    local mode, reason = RCPL_Data_VotingWindowMode(RCPL_DB and RCPL_DB.votingWindow, addon.version)
    if reason and not versionWarned then
        versionWarned = true
        print("|cFFFF8000[RCPL]|r " .. reason)
    end
    if mode == "off" or fellBack or not (rc.frame and rc.frame:IsShown()) then return end
    if ShowOurs() and mode == "replace" then
        rc.frame:Hide()
    end
end

function VoteWindow:OnInitialize()
    self:RawHook(RCVotingFrame, "Show", "OnRCShow")
    -- Not RCVotingFrame:Hide -- its own Close button calls that, and closing
    -- RCLootCouncil's window shouldn't close ours. Abort and session end both
    -- come through EndSession.
    self:SecureHook(RCVotingFrame, "EndSession", function(_, hide)
        if hide and frame then frame:Hide() else self:Refresh() end
    end)
    -- RCLootCouncil calls Update on responses, rolls, awards and session
    -- switches, and HandleVote on every vote.
    self:SecureHook(RCVotingFrame, "Update", "Refresh")
    self:SecureHook(RCVotingFrame, "HandleVote", "Refresh")
end

-- Exposed for the options frame and /rcpl window.
function RCPL_SetVotingWindowMode(mode)
    RCPL_DB.votingWindow = mode
    print("|cFF00FF00[RCPL]|r Voting window: " .. mode .. ". Takes effect the next time the voting window opens.")
end
