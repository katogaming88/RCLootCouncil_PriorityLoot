-- Core.lua
-- Registers RCLootCouncil_PriorityLoot as a sub-module of RCLootCouncil,
-- following the same pattern as RCLootCouncil_wowaudit.

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCLPAddon = addon:NewModule("RCLootCouncil_PriorityLoot", "AceTimer-3.0")

-- Expose globally so Modules/ files can reach it via addon:GetModule().
RCLootCouncil_PriorityLoot = RCLPAddon

function RCLPAddon:OnInitialize()
    if type(RCLPriorityDB) ~= "table" then RCLPriorityDB = {} end
    if type(RCLPriorityDB.players) ~= "table" then RCLPriorityDB.players = {} end
    if type(RCLPriorityDB.priority) ~= "table" then RCLPriorityDB.priority = {} end
end

SLASH_RCPL1 = "/rcpl"
SlashCmdList["RCPL"] = function(input)
    local cmd = strtrim(input or "")
    if cmd == "import" then
        RCLPL_ShowImportFrame()
    elseif cmd == "prio" then
        RCLPL_ShowPrioPreview()
    elseif cmd == "reset" then
        RCLPL_Data_ResetData()
        print("|cFF00FF00[RCLootCouncil_PriorityLoot]|r All priority data cleared.")
    else
        print("|cFF00FF00[RCLootCouncil_PriorityLoot]|r Commands:")
        print("  /rcpl import  — open the priority data import window")
        print("  /rcpl prio    — preview imported priority data")
        print("  /rcpl reset   — clear all stored priority data")
    end
end
