-- Modules\votingPriorityPanel.lua
-- Side panel attached to the officer voting frame, showing the full saved
-- priority order (every ranked player, both tracks) for whichever item is
-- currently selected in the session -- unlike the "Priority" column
-- (Modules/votingFrame.lua), which only shows the local candidates'
-- individual ranks, this shows the complete list at a glance.

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCVotingFrame = addon:GetModule("RCVotingFrame")
local RCPLAddon = addon:GetModule("RCLootCouncil_PriorityLoot")
local RCPLVotingPanel = RCPLAddon:NewModule("RCPLVotingPriorityPanel", "AceHook-3.0", "AceTimer-3.0", "AceEvent-3.0")

local ROW_H     = 18
local CONTENT_W = 220
local PAD       = 6

local panel
local currentSession = 1
local linePool = {}

local function GetOrCreateLine(i)
    if not linePool[i] then
        local fs = panel.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetJustifyH("LEFT")
        fs:SetWidth(CONTENT_W - PAD * 2)
        linePool[i] = fs
    end
    return linePool[i]
end

local function ColorHex(color)
    return string.format(
        "%02x%02x%02x",
        math.floor(color.r * 255 + 0.5),
        math.floor(color.g * 255 + 0.5),
        math.floor(color.b * 255 + 0.5)
    )
end

local function Build()
    panel = CreateFrame("Frame", "RCPLVotingPriorityPanel", RCVotingFrame.frame, "BackdropTemplate")
    panel:SetSize(CONTENT_W + 20, 340)
    panel:SetPoint("TOPLEFT", RCVotingFrame.frame, "TOPRIGHT", 8, 0)
    panel:SetBackdrop({
        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    panel:SetFrameStrata(RCVotingFrame.frame:GetFrameStrata())
    panel:Hide()

    local titleText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleText:SetPoint("TOP", 0, -14)
    titleText:SetText("Full Priority Order")
    panel.title = titleText

    local itemText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemText:SetPoint("TOP", titleText, "BOTTOM", 0, -4)
    itemText:SetWidth(CONTENT_W)
    panel.itemText = itemText

    local scrollFrame = CreateFrame("ScrollFrame", "RCPLVotingPriorityPanelScroll", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 10)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxScroll = math.max(0, panel.content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * ROW_H * 3)))
    end)
    panel.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(CONTENT_W)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    panel.content = content
end

local function ShortName(fullName)
    return (fullName:match("^([^%-]+)")) or fullName
end

local function Refresh()
    if not panel or not panel:IsShown() then return end

    for _, fs in ipairs(linePool) do fs:Hide() end

    local lootTable = addon:GetLootTable()
    local entry = lootTable and lootTable[currentSession]
    if not entry or not entry.itemID then
        panel.itemText:SetText("|cFF999999No item selected|r")
        panel.content:SetHeight(1)
        return
    end

    local itemName = GetItemInfo(entry.itemID)
    panel.itemText:SetText(itemName and ("|cFFffd200" .. itemName .. "|r") or ("Item #" .. entry.itemID))

    local itemPriority = type(RCPL_DB) == "table" and type(RCPL_DB.priority) == "table"
        and RCPL_DB.priority[tostring(entry.itemID)]

    local lines = {}
    local function add(text)
        lines[#lines + 1] = text
    end

    if type(itemPriority) ~= "table" then
        add("|cFF999999No saved priority order for this item.|r")
    else
        -- Lead with whichever track this specific drop actually is, when
        -- it's resolvable -- an officer looking at a Mythic drop cares about
        -- the Mythic list first, not whichever track happens to be listed
        -- first. Falls back to the fixed Heroic-then-Mythic order when the
        -- track can't be determined (e.g. /rc test's synthetic item links).
        local dropTrack = RCPL_Data_CurrentTrack(entry.link)
        local trackOrder = { "H", "M" }
        if dropTrack == "M" then
            trackOrder = { "M", "H" }
        end

        local any = false
        for _, trackKey in ipairs(trackOrder) do
            local list = itemPriority[trackKey]
            if type(list) == "table" and #list > 0 then
                any = true
                local label = RCPL_Data_TrackLabel(trackKey) or trackKey
                if trackKey == dropTrack then label = label .. " (this drop)" end
                add("|cFFCCCCCC" .. label .. ":|r")
                for rank, playerName in ipairs(list) do
                    local hex = ColorHex(RCPL_Data_RankColor(rank))
                    add("  |cFF" .. hex .. rank .. ". " .. ShortName(playerName) .. "|r")
                end
                add("")
            end
        end
        if not any then
            add("|cFF999999No saved priority order for this item.|r")
        end
    end

    local y = -PAD
    for i, text in ipairs(lines) do
        local fs = GetOrCreateLine(i)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", panel.content, "TOPLEFT", PAD, y)
        fs:SetText(text)
        fs:Show()
        y = y - math.max(ROW_H, fs:GetStringHeight())
    end
    panel.content:SetHeight(math.max(1, -y + PAD))
    panel.scrollFrame:SetVerticalScroll(0)
end

function RCPLVotingPanel:OnInitialize()
    if not RCVotingFrame.frame then
        return self:ScheduleTimer("OnInitialize", 0.5)
    end
    Build()

    -- Show/hide together with the voting frame itself.
    self:SecureHook(RCVotingFrame, "Show", function() panel:Show(); Refresh() end)
    self:SecureHook(RCVotingFrame, "Hide", function() panel:Hide() end)

    -- RCSessionChangedPre is delivered before RCVotingFrame's own session
    -- index updates, but it passes the new session number as the message
    -- argument, so reading that directly (not RCVotingFrame's internal
    -- state) is safe -- same approach Modules/votingFrame.lua's Priority
    -- column already uses.
    self:RegisterMessage("RCSessionChangedPre", function(_, s)
        currentSession = s or 1
        Refresh()
    end)

    -- Covers the addon loading (or /reload happening) while a session is
    -- already running -- our Show/Hide hooks only fire on the *next* call,
    -- so without this the panel would stay hidden despite the voting frame
    -- already being visible.
    if RCVotingFrame.frame:IsShown() then
        panel:Show()
        Refresh()
    end
end
