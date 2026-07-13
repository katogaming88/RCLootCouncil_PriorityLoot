-- Modules\versionCheckFrame.lua
-- Version checker window. Opened via /rcpl version. Mirrors base
-- RCLootCouncil's own version checker (Modules/versionCheck.lua): opens
-- immediately showing just your own version, with separate Guild/Group
-- buttons that trigger the actual poll -- never an automatic/implicit one.
--
-- Core.lua drives the actual comm traffic (RCPLAddon:StartVersionCheck) and
-- calls the public functions below to keep this window updated live as
-- replies arrive, rather than batching everything into one chat print at
-- the end.

local ROW_H     = 18
local CONTENT_W = 360
local PAD       = 4

local COLOR_SELF    = { 0.7, 0.85, 1 }    -- light blue, matches nothing else here
local COLOR_MATCH   = { 0, 1, 0 }          -- same version as you
local COLOR_BEHIND   = { 1, 0.5, 0 }        -- they're newer -- you're behind
local COLOR_AHEAD    = { 1, 1, 0 }          -- they're older -- they're behind
local COLOR_WAITING  = { 0.6, 0.6, 0.6 }
local COLOR_MISSING  = { 0.6, 0.6, 0.6 }

local frame
local rowOrder = {}   -- ordered list of names, insertion order
local rowData  = {}   -- name -> { version = string|nil, isSelf = bool, missing = bool }
local rowPool  = {}   -- index -> { nameFS, versionFS }

-- Returns true when other is a strictly higher semver than current. Same
-- comparison Core.lua's IsNewer does -- duplicated locally rather than
-- exposed as a public function purely for this one UI-coloring use.
local function IsNewerVersion(current, other)
    local c1, c2, c3 = current:match("(%d+)%.(%d+)%.(%d+)")
    local o1, o2, o3 = other:match("(%d+)%.(%d+)%.(%d+)")
    if not (c1 and o1) then return false end
    c1, c2, c3 = tonumber(c1), tonumber(c2), tonumber(c3)
    o1, o2, o3 = tonumber(o1), tonumber(o2), tonumber(o3)
    if o1 ~= c1 then return o1 > c1 end
    if o2 ~= c2 then return o2 > c2 end
    return o3 > c3
end

local function Build()
    frame = CreateFrame("Frame", "RCPLVersionCheckFrame", UIParent, "BackdropTemplate")
    frame:SetSize(420, 420)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    tinsert(UISpecialFrames, "RCPLVersionCheckFrame")

    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleText:SetPoint("TOP", 0, -14)
    titleText:SetText("RCLootCouncil Priority Loot - Version Checker")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    local headerName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerName:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -40)
    headerName:SetText("Name")

    local headerVersion = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerVersion:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, -40)
    headerVersion:SetText("Version")

    local scrollFrame = CreateFrame("ScrollFrame", "RCPLVersionCheckScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -60)
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

    local guildBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    guildBtn:SetSize(80, 22)
    guildBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 12)
    guildBtn:SetText("Guild")
    guildBtn:SetScript("OnClick", function()
        local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
        local RCPLAddon = addon:GetModule("RCLootCouncil_PriorityLoot")
        RCPLAddon:StartVersionCheck("guild")
    end)

    local groupBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    groupBtn:SetSize(80, 22)
    groupBtn:SetPoint("LEFT", guildBtn, "RIGHT", 8, 0)
    groupBtn:SetText("Group")
    groupBtn:SetScript("OnClick", function()
        local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
        local RCPLAddon = addon:GetModule("RCLootCouncil_PriorityLoot")
        RCPLAddon:StartVersionCheck()
    end)

    -- Anchored to the right of the buttons rather than centered on the whole
    -- frame -- centering put the text's left portion (the actual count)
    -- behind/overlapping the Group button for anything but the shortest
    -- possible totals string.
    local totals = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totals:SetPoint("LEFT", groupBtn, "RIGHT", 10, 0)
    frame.totals = totals
end

local function GetRow(i)
    if not rowPool[i] then
        local nameFS = frame.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFS:SetPoint("TOPLEFT", frame.content, "TOPLEFT", PAD, 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWidth(CONTENT_W * 0.6)

        local versionFS = frame.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        versionFS:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", -PAD - 16, 0)
        versionFS:SetJustifyH("RIGHT")
        versionFS:SetWidth(CONTENT_W * 0.35)

        rowPool[i] = { nameFS = nameFS, versionFS = versionFS }
    end
    return rowPool[i]
end

local function VersionColor(entry)
    if entry.missing then return COLOR_MISSING end
    if not entry.version then return COLOR_WAITING end
    if entry.isSelf then return COLOR_SELF end
    local myVersion = rowData[rowOrder[1]] and rowData[rowOrder[1]].version
    if not myVersion or entry.version == myVersion then return COLOR_MATCH end
    if IsNewerVersion(myVersion, entry.version) then return COLOR_BEHIND end
    return COLOR_AHEAD
end

local function Redraw()
    for i, name in ipairs(rowOrder) do
        local entry = rowData[name]
        local row = GetRow(i)
        row.nameFS:ClearAllPoints()
        row.nameFS:SetPoint("TOPLEFT", frame.content, "TOPLEFT", PAD, -(i - 1) * ROW_H)
        row.nameFS:SetText(entry.isSelf and (name .. "  (you)") or name)
        row.nameFS:SetTextColor(entry.isSelf and unpack(COLOR_SELF) or 1, 1, 1)
        row.nameFS:Show()

        row.versionFS:ClearAllPoints()
        row.versionFS:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", -PAD - 16, -(i - 1) * ROW_H)
        local text = entry.missing and "Not installed" or (entry.version or "Waiting...")
        row.versionFS:SetText(text)
        row.versionFS:SetTextColor(unpack(VersionColor(entry)))
        row.versionFS:Show()
    end
    for i = #rowOrder + 1, #rowPool do
        rowPool[i].nameFS:Hide()
        rowPool[i].versionFS:Hide()
    end

    frame.content:SetHeight(math.max(1, #rowOrder * ROW_H + PAD))

    local installed, total = 0, #rowOrder
    for _, name in ipairs(rowOrder) do
        if rowData[name].version then installed = installed + 1 end
    end
    frame.totals:SetText(string.format("%d/%d have the addon", installed, total))
end

-- ── Public API, called from Core.lua as the check progresses ────────────────

-- Clears the list back to just the local player, called both when the
-- window first opens and whenever a new check starts (Guild/Group clicked).
function RCPL_VersionCheck_Reset(selfName, selfVersion)
    wipe(rowOrder)
    wipe(rowData)
    rowOrder[1] = selfName
    rowData[selfName] = { version = selfVersion, isSelf = true }
    if frame and frame:IsShown() then Redraw() end
end

-- Adds a placeholder row for someone a reply is expected from, shown as
-- "Waiting..." until they actually respond (or the check times out).
function RCPL_VersionCheck_SeedWaiting(name)
    if rowData[name] then return end
    rowOrder[#rowOrder + 1] = name
    rowData[name] = { version = nil, isSelf = false }
    if frame and frame:IsShown() then Redraw() end
end

-- Records (or updates) a reply. Works whether or not the name was seeded --
-- a reply can arrive from someone not on the expected roster (e.g. a
-- cross-realm guildie GetGuildRosterInfo names slightly differently).
function RCPL_VersionCheck_UpdateRow(name, version)
    if not rowData[name] then
        rowOrder[#rowOrder + 1] = name
        rowData[name] = { isSelf = false }
    end
    rowData[name].version = version
    rowData[name].missing = false
    if frame and frame:IsShown() then Redraw() end
end

-- Flips every row that never got a reply to "Not installed", called once
-- the check's timeout elapses.
function RCPL_VersionCheck_MarkMissing()
    for _, name in ipairs(rowOrder) do
        local entry = rowData[name]
        if not entry.isSelf and not entry.version then
            entry.missing = true
        end
    end
    if frame and frame:IsShown() then Redraw() end
end

function RCPL_ShowVersionCheckFrame()
    if not frame then Build() end
    if frame:IsShown() then
        frame:Hide()
        return
    end
    local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
    local RCPLAddon = addon:GetModule("RCLootCouncil_PriorityLoot")
    RCPL_VersionCheck_Reset(UnitName("player"), RCPLAddon:GetVersion())
    frame:Show()
    Redraw()
end
