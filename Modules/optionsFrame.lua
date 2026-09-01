-- Modules\optionsFrame.lua
-- Options / quick-actions panel. Opened via bare /rcpl (no arguments),
-- replacing the old chat-printed command list. A real button per action that
-- opens a window with no required arguments; commands that need typed
-- arguments (award, unaward) or are destructive (reset) are listed as
-- reference text only, not buttons.

local BTN_W   = 200
local BTN_H   = 22
local ROW_GAP = 6

local frame

local ACTIONS = {
    { label = "Import", desc = "open the priority data import window",
        action = function() RCPL_ShowImportFrame() end },
    { label = "Priority Preview", desc = "preview imported priority data",
        action = function() RCPL_ShowPrioPreview() end },
    { label = "Season Awards", desc = "open the season awards window",
        action = function() RCPL_ShowAwardsFrame() end },
    { label = "Sync Status", desc = "see who in the raid/party has your priority data, force-push to who doesn't",
        action = function() RCPL_ShowSyncStatusFrame() end },
    { label = "Version Checker", desc = "open it (Guild/Group buttons trigger the poll)",
        action = function() RCPL_ShowVersionCheckFrame() end },
    { label = "Check Group Now", desc = "open the version checker and immediately poll your raid/party",
        action = function()
            RCPL_ShowVersionCheckFrame()
            local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
            local RCPLAddon = addon:GetModule("RCLootCouncil_PriorityLoot")
            RCPLAddon:StartVersionCheck()
        end },
    { label = "Toggle Debug Logging", desc = "turn debug logging on or off",
        action = function()
            local state = RCPL_Log and RCPL_Log.ToggleDebug()
            print(string.format("|cFF00FF00[RCPL]|r debug logging %s",
                state and "|cFF00FF00ON|r" or "|cFFFF4444OFF|r"))
        end },
    { label = "Open Log", desc = "open the in-memory log window",
        action = function() if RCPL_Log then RCPL_Log.Show() end end },
}

-- Reference-only rows: no button, since these are destructive or need typed
-- arguments a click can't provide.
local REFERENCE_ROWS = {
    { label = "/rcpl reset", desc = "clear all stored priority data -- type this one out, no button" },
    { label = "/rcpl award <player> <item>", desc = "manually record an award" },
    { label = "/rcpl unaward <player> <item>", desc = "undo a recorded award" },
}

local function Build()
    frame = CreateFrame("Frame", "RCPLOptionsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(440, 100)  -- height finalized at the bottom of Build()
    frame:SetPoint("CENTER")
    RCPL_ApplyPanelBackdrop(frame)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    tinsert(UISpecialFrames, "RCPLOptionsFrame")

    RCPL_CreateHeaderStrip(frame, 34)
    RCPL_CreateStyledTitle(frame, "RCLootCouncil Priority Loot - Options")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    local y = -50
    for _, entry in ipairs(ACTIONS) do
        local btn = RCPL_CreateStyledButton(frame, BTN_W, BTN_H, entry.label)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
        btn:SetScript("OnClick", function()
            frame:Hide()
            entry.action()
        end)

        local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        desc:SetPoint("LEFT", btn, "RIGHT", 10, 0)
        desc:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
        desc:SetJustifyH("LEFT")
        desc:SetTextColor(0.75, 0.75, 0.75)
        desc:SetText(entry.desc)

        y = y - (BTN_H + ROW_GAP)
    end

    y = y - 8
    local refHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    refHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
    refHeader:SetTextColor(0.6, 0.6, 0.6)
    refHeader:SetText("Reference only -- type these out:")
    y = y - (BTN_H + ROW_GAP)

    for _, entry in ipairs(REFERENCE_ROWS) do
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
        label:SetJustifyH("LEFT")
        label:SetWidth(BTN_W)
        label:SetText(entry.label)

        local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        desc:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + BTN_W + 10, y - 2)
        desc:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
        desc:SetJustifyH("LEFT")
        desc:SetTextColor(0.75, 0.75, 0.75)
        desc:SetText(entry.desc)

        y = y - (BTN_H + ROW_GAP)
    end

    y = y - 8
    local minimapCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    minimapCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, y)
    minimapCheck:SetScript("OnClick", function(self)
        local shown = self:GetChecked()
        if type(RCPL_DB) == "table" and type(RCPL_DB.minimap) == "table" then
            RCPL_DB.minimap.hide = not shown
        end
        if RCPL_SetMinimapButtonShown then RCPL_SetMinimapButtonShown(shown) end
    end)
    frame.minimapCheck = minimapCheck

    local minimapLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    minimapLabel:SetPoint("LEFT", minimapCheck, "RIGHT", 4, 1)
    minimapLabel:SetText("Show minimap button")
    y = y - (BTN_H + ROW_GAP)

    frame:SetHeight(-y + 20)
end

function RCPL_ShowOptionsFrame()
    if not frame then Build() end
    if frame:IsShown() then
        frame:Hide()
    else
        local hidden = type(RCPL_DB) == "table" and type(RCPL_DB.minimap) == "table" and RCPL_DB.minimap.hide
        frame.minimapCheck:SetChecked(not hidden)
        frame:Show()
    end
end
