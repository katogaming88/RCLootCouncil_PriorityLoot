-- Modules\votingPriorityPanel.lua
-- Side panel attached to the officer voting frame, showing the full saved
-- priority order (every ranked player, both tracks) for whichever item is
-- currently selected in the session -- unlike the "Priority" column
-- (Modules/votingFrame.lua), which only shows the local candidates'
-- individual ranks, this shows the complete list at a glance.

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCVotingFrame = addon:GetModule("RCVotingFrame")
local RCPLAddon = addon:GetModule("RCLootCouncil_PriorityLoot")
local RCPLVotingPanel = RCPLAddon:NewModule("RCPLVotingPriorityPanel", "AceTimer-3.0", "AceEvent-3.0")

local ROW_H     = 20
local CONTENT_W = 240
local PAD       = 8

local panel
local currentSession = 1
local linePool = {}

local function GetOrCreateLine(i)
    if not linePool[i] then
        local fs = panel.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
    -- Same tooltip-style skin as the Options/Priority Preview/Season Awards/
    -- Version Checker windows (Modules/frameStyle.lua) -- reads much more
    -- clearly against the raid/voting UI behind it than the old tiled stone
    -- DialogBox skin, which washed out at this panel's small size.
    RCPL_ApplyPanelBackdrop(panel)
    panel:SetFrameStrata(RCVotingFrame.frame:GetFrameStrata())
    panel:Hide()

    RCPL_CreateHeaderStrip(panel, 42)
    local titleText = RCPL_CreateStyledTitle(panel, "Full Priority Order")
    panel.title = titleText

    local itemText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemText:SetPoint("TOP", titleText, "BOTTOM", 0, -4)
    itemText:SetWidth(CONTENT_W)
    panel.itemText = itemText

    local scrollFrame = CreateFrame("ScrollFrame", "RCPLVotingPriorityPanelScroll", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -54)
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
                if trackKey == dropTrack then
                    -- Gold instead of the plain grey heading color so the
                    -- track that actually matters for this drop pops out
                    -- immediately instead of reading as just another list.
                    add("|cFFFFD100" .. label .. " (this drop):|r")
                else
                    add("|cFFCCCCCC" .. label .. ":|r")
                end
                for rank, playerName in ipairs(list) do
                    local hex = ColorHex(RCPL_Data_RankColor(rank))
                    -- Loot-council-only context (this whole panel is part of
                    -- the officer voting frame) -- shows whether this rank
                    -- is the player's real wishlist BiS pick vs. a
                    -- lower-tier Good/OK pick vs. not wishlist-backed at all
                    -- (no tag), instead of a bare rank number that reads the
                    -- same for all three (#760).
                    local statusLabel = RCPL_Data_WishlistStatusLabel(itemPriority, trackKey, playerName)
                    local statusSuffix = statusLabel and (" |cFF999999(" .. statusLabel .. ")|r") or ""
                    add("  |cFF" .. hex .. rank .. ". " .. ShortName(playerName) .. "|r" .. statusSuffix)
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

    -- Show/hide together with the voting frame itself -- tracked via the
    -- underlying Blizzard frame's own OnShow/OnHide script rather than
    -- SecureHook-ing RCVotingFrame:Show()/:Hide() (the Ace3 module wrapper
    -- methods). A method hook only fires when that specific method gets
    -- called, and RCVotingFrame:Show() has its own internal guard
    -- (`if self.frame and lootTable[session] then ... else print "No
    -- session running" end`) that can leave the real frame hidden even
    -- though :Show() was called (SecureHook still fires our handler
    -- unconditionally afterward) -- confirmed live: the panel sometimes
    -- failed to reappear after a raid lead/Master Looter handoff (in
    -- current retail, RCLootCouncil treats these as the same thing, so a
    -- lead pass forces its own ML/session-state resync). OnShow/OnHide
    -- fire for every real visibility change to the frame no matter which
    -- internal code path caused it, so this can't drift out of sync with
    -- what's actually on screen the way a method hook can.
    RCVotingFrame.frame:HookScript("OnShow", function() panel:Show(); Refresh() end)
    RCVotingFrame.frame:HookScript("OnHide", function() panel:Hide() end)

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
