-- Modules\minimapButton.lua
-- Two independent ways to reach the Options panel (Modules/optionsFrame.lua)
-- without typing /rcpl:
--   1. A LibDataBroker/LibDBIcon minimap launcher -- also what third-party
--      minimap button collectors (MBB, ButtonForge, etc.) auto-detect, since
--      LibDBIcon is the de facto standard they scan for. No extra work needed
--      for that case beyond registering normally below.
--   2. Blizzard's native Addon Compartment (the dropdown next to the
--      minimap, retail since Dragonflight) -- a separate, declarative
--      opt-in via .toc fields (AddonCompartmentFunc/OnEnter/OnLeave,
--      IconTexture) plus the three global functions below. Independent of
--      the minimap icon's shown/hidden state -- registering here doesn't
--      require or affect the LibDBIcon button at all.

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

-- Addon Compartment entry points -- names must match the .toc's
-- AddonCompartmentFunc/OnEnter/OnLeave values exactly. Signatures are fixed
-- by Blizzard's AddonCompartmentFrame API, not ours to choose.
function RCPL_OnAddonCompartmentClick(_, buttonName)
    if buttonName == "LeftButton" and RCPL_ShowOptionsFrame then
        RCPL_ShowOptionsFrame()
    end
end

function RCPL_OnAddonCompartmentEnter(_, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
    OnTooltipShow(GameTooltip)
    GameTooltip:Show()
end

function RCPL_OnAddonCompartmentLeave()
    GameTooltip:Hide()
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
