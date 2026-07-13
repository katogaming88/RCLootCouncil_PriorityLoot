-- Modules\minimapButton.lua
-- LibDataBroker/LibDBIcon minimap launcher -- left-click opens the Options
-- panel (Modules/optionsFrame.lua), same entry point as bare /rcpl. Exists so
-- officers can reach the addon without remembering a slash command.

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCPLAddon = addon:GetModule("RCLootCouncil_PriorityLoot")

local ICON = "Interface\\Icons\\INV_Misc_ScrollUnrolled03D"

local function OnClick(_, button)
    if button == "LeftButton" and RCPL_ShowOptionsFrame then
        RCPL_ShowOptionsFrame()
    end
end

local function OnTooltipShow(tooltip)
    tooltip:AddLine("RCLootCouncil - Priority Loot")
    tooltip:AddLine("|cFFCCCCCCLeft-click:|r open options", 1, 1, 1)
end

-- Public so Modules/optionsFrame.lua's checkbox can flip visibility without
-- this module needing to expose the LibDBIcon instance itself.
function RCPL_SetMinimapButtonShown(shown)
    local icon = LibStub("LibDBIcon-1.0", true)
    if not icon then return end
    if shown then
        icon:Show("RCLootCouncil_PriorityLoot")
    else
        icon:Hide("RCLootCouncil_PriorityLoot")
    end
end

function RCPLAddon:InitMinimapButton()
    if type(RCPL_DB) ~= "table" then return end
    if type(RCPL_DB.minimap) ~= "table" then RCPL_DB.minimap = { hide = false } end

    local ldb = LibStub("LibDataBroker-1.1", true)
    local icon = LibStub("LibDBIcon-1.0", true)
    if not ldb or not icon then return end

    local dataObj = ldb:NewDataObject("RCLootCouncil_PriorityLoot", {
        type = "launcher",
        icon = ICON,
        OnClick = OnClick,
        OnTooltipShow = OnTooltipShow,
    })

    icon:Register("RCLootCouncil_PriorityLoot", dataObj, RCPL_DB.minimap)
end
