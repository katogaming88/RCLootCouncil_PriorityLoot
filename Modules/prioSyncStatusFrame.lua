-- Modules\prioSyncStatusFrame.lua
-- Sync Status window. Opened via /rcpl status: shows, for every current
-- raid/party member, whether their priority data matches what this client
-- has ("Match"/"Different"/"Missing"/"Waiting..."), plus a per-row Push
-- button and a bulk "Force Push All" for anyone not already matching.
--
-- Mirrors Modules/versionCheckFrame.lua's shape closely (row pool, seed/
-- update/finalize public API driven by Modules/prioSync.lua's comm
-- handlers) -- same reasoning: keep every popup window reading as one
-- consistent UI rather than each carrying its own layout logic.

local ROW_H     = 18
local CONTENT_W = 360
local PAD       = 4
local PUSH_BTN_W, PUSH_BTN_H = 46, 17

local COLOR_MATCH    = { 0, 1, 0 }         -- their data matches yours
local COLOR_DIFFERENT = { 1, 0.5, 0 }       -- they have data, but it differs
local COLOR_MISSING  = { 1, 0.3, 0.3 }      -- no data at all, or never replied
local COLOR_WAITING  = { 0.6, 0.6, 0.6 }

local frame
local rowOrder = {}   -- ordered list of names, insertion order
local rowData  = {}   -- name -> { status = "match"|"different"|"missing"|nil, playerCount, priorityCount, importedAt }
local rowPool  = {}   -- index -> { nameFS, statusFS, pushBtn }

local function StatusColor(status)
    if status == "match" then return COLOR_MATCH end
    if status == "different" then return COLOR_DIFFERENT end
    if status == "missing" then return COLOR_MISSING end
    return COLOR_WAITING
end

local function StatusText(entry)
    if entry.status == "match" then return "Match" end
    if entry.status == "different" then return "Different" end
    if entry.status == "missing" then return "No data" end
    if entry.timedOut then return "No reply" end
    return "Waiting..."
end

-- Names currently showing anything other than a clean match -- what the
-- bulk "Force Push All" button iterates. Excludes rows still "Waiting..."
-- (not timed out yet) since those might still reply Match on their own.
local function NonMatchingNames()
    local names = {}
    for _, name in ipairs(rowOrder) do
        local entry = rowData[name]
        if entry.status == "different" or entry.status == "missing" or (entry.timedOut and not entry.status) then
            names[#names + 1] = name
        end
    end
    return names
end

local function Build()
    frame = CreateFrame("Frame", "RCPLSyncStatusFrame", UIParent, "BackdropTemplate")
    frame:SetSize(440, 420)
    frame:SetPoint("CENTER")
    RCPL_ApplyPanelBackdrop(frame)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    tinsert(UISpecialFrames, "RCPLSyncStatusFrame")

    RCPL_CreateHeaderStrip(frame, 34)
    RCPL_CreateStyledTitle(frame, "RCLootCouncil Priority Loot - Sync Status")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    local headerName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerName:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -44)
    headerName:SetText("Name")

    local headerStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerStatus:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34 - PUSH_BTN_W - 8, -44)
    headerStatus:SetText("Status")

    local scrollFrame = CreateFrame("ScrollFrame", "RCPLSyncStatusScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -64)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 48)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxScroll = math.max(0, frame.content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * ROW_H * 3)))
    end)
    frame.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(CONTENT_W)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    frame.content = content

    local checkBtn = RCPL_CreateStyledButton(frame, 110, 22, "Check Group")
    checkBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 12)
    checkBtn:SetScript("OnClick", function() RCPL_StartSyncStatusCheck() end)
    frame.checkBtn = checkBtn

    local pushAllBtn = RCPL_CreateStyledButton(frame, 110, 22, "Force Push All")
    pushAllBtn:SetPoint("LEFT", checkBtn, "RIGHT", 8, 0)
    pushAllBtn:SetScript("OnClick", function()
        local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
        local RCPLAddon = addon:GetModule("RCLootCouncil_PriorityLoot")
        local sync = RCPLAddon:GetModule("RCPLPrioSync", true)
        if sync then sync:ForcePushAll(NonMatchingNames()) end
    end)
    frame.pushAllBtn = pushAllBtn

    local totals = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totals:SetPoint("LEFT", pushAllBtn, "RIGHT", 10, 0)
    frame.totals = totals
end

local function PushRow(name)
    local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
    local RCPLAddon = addon:GetModule("RCLootCouncil_PriorityLoot")
    local sync = RCPLAddon:GetModule("RCPLPrioSync", true)
    if sync then sync:ForcePush(name) end
end

local function GetRow(i)
    if not rowPool[i] then
        local nameFS = frame.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFS:SetPoint("TOPLEFT", frame.content, "TOPLEFT", PAD, 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWidth(CONTENT_W * 0.45)

        local statusFS = frame.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        statusFS:SetJustifyH("RIGHT")
        statusFS:SetWidth(CONTENT_W * 0.3)

        local pushBtn = RCPL_CreateStyledButton(frame.content, PUSH_BTN_W, PUSH_BTN_H, "Push")

        rowPool[i] = { nameFS = nameFS, statusFS = statusFS, pushBtn = pushBtn }
    end
    return rowPool[i]
end

local function Redraw()
    for i, name in ipairs(rowOrder) do
        local entry = rowData[name]
        local row = GetRow(i)
        local y = -(i - 1) * ROW_H

        row.nameFS:ClearAllPoints()
        row.nameFS:SetPoint("TOPLEFT", frame.content, "TOPLEFT", PAD, y)
        row.nameFS:SetText(name)
        row.nameFS:Show()

        row.statusFS:ClearAllPoints()
        row.statusFS:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", -PAD - PUSH_BTN_W - 8, y)
        row.statusFS:SetText(StatusText(entry))
        row.statusFS:SetTextColor(unpack(StatusColor(entry.status)))
        row.statusFS:Show()

        row.pushBtn:ClearAllPoints()
        row.pushBtn:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", -PAD, y - 1)
        row.pushBtn:SetScript("OnClick", function() PushRow(name) end)
        local pushable = entry.status == "different" or entry.status == "missing" or (entry.timedOut and not entry.status)
        row.pushBtn:SetEnabled(pushable)
        row.pushBtn:Show()
    end
    for i = #rowOrder + 1, #rowPool do
        rowPool[i].nameFS:Hide()
        rowPool[i].statusFS:Hide()
        rowPool[i].pushBtn:Hide()
    end

    frame.content:SetHeight(math.max(1, #rowOrder * ROW_H + PAD))

    local matched, total = 0, #rowOrder
    for _, name in ipairs(rowOrder) do
        if rowData[name].status == "match" then matched = matched + 1 end
    end
    frame.totals:SetText(string.format("%d/%d match", matched, total))
end

-- -- Public API, called from Modules/prioSync.lua as the check progresses --

-- Clears the list and seeds a "Waiting..." row for every name given (the
-- current raid/party roster, minus self) -- called right before the status
-- request goes out so the window shows who hasn't replied yet rather than
-- staying blank until the timeout.
function RCPL_SyncStatus_Reset(names)
    wipe(rowOrder)
    wipe(rowData)
    for _, name in ipairs(names or {}) do
        rowOrder[#rowOrder + 1] = name
        rowData[name] = {}
    end
    if frame and frame:IsShown() then Redraw() end
end

function RCPL_SyncStatus_SeedWaiting(name)
    if rowData[name] then return end
    rowOrder[#rowOrder + 1] = name
    rowData[name] = {}
    if frame and frame:IsShown() then Redraw() end
end

-- Records (or updates) a status reply. Works whether or not the name was
-- seeded -- a reply can arrive from someone Modules/prioSync.lua's roster
-- walk missed (e.g. a mid-flight roster change).
function RCPL_SyncStatus_UpdateRow(name, status, playerCount, priorityCount, importedAt)
    if not rowData[name] then
        rowOrder[#rowOrder + 1] = name
        rowData[name] = {}
    end
    rowData[name].status = status
    rowData[name].playerCount = playerCount
    rowData[name].priorityCount = priorityCount
    rowData[name].importedAt = importedAt
    rowData[name].timedOut = false
    if frame and frame:IsShown() then Redraw() end
end

-- Flags every row that never got a reply, called once the check's timeout
-- elapses (Modules/prioSync.lua's STATUS_TIMEOUT).
function RCPL_SyncStatus_MarkMissing()
    for _, name in ipairs(rowOrder) do
        local entry = rowData[name]
        if not entry.status then entry.timedOut = true end
    end
    if frame and frame:IsShown() then Redraw() end
end

-- Kicks off a check: resolves Modules/prioSync.lua's RCPLPrioSync module,
-- calls StartStatusCheck(), and seeds the window from the names it returns.
-- Shared by the Check Group button and /rcpl status so both paths report the
-- same failure message rather than the slash command duplicating the guard.
function RCPL_StartSyncStatusCheck()
    local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
    local RCPLAddon = addon:GetModule("RCLootCouncil_PriorityLoot")
    local sync = RCPLAddon:GetModule("RCPLPrioSync", true)
    if not sync then
        print("|cFFFF4444[RCPL]|r Sync module not loaded.")
        return
    end
    local names, err = sync:StartStatusCheck()
    if not names then
        print("|cFFFFCC00[RCLootCouncil_PriorityLoot]|r " .. tostring(err))
        return
    end
    RCPL_SyncStatus_Reset(names)
end

function RCPL_ShowSyncStatusFrame()
    if not frame then Build() end
    if frame:IsShown() then
        frame:Hide()
        return
    end
    frame:Show()
    Redraw()
end
