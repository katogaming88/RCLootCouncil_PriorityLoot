-- Core.lua
-- Registers RCLootCouncil_PriorityLoot as a sub-module of RCLootCouncil,
-- following the same pattern as RCLootCouncil_wowaudit.

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCLPAddon = addon:NewModule("RCLootCouncil_PriorityLoot", "AceTimer-3.0", "AceComm-3.0")

-- Expose globally so Modules/ files can reach it via addon:GetModule().
RCLootCouncil_PriorityLoot = RCLPAddon

local RCLPL_VERSION     = "0.1.4"
local RCLPL_COMM_PREFIX = "RCLPL_Ver"

local versionWarned      = false
local hasRepliedToOthers = false

-- Returns true when other is a strictly higher semver than current.
local function IsNewer(current, other)
    local c1, c2, c3 = current:match("(%d+)%.(%d+)%.(%d+)")
    local o1, o2, o3 = other:match("(%d+)%.(%d+)%.(%d+)")
    if not (c1 and o1) then return false end
    c1, c2, c3 = tonumber(c1), tonumber(c2), tonumber(c3)
    o1, o2, o3 = tonumber(o1), tonumber(o2), tonumber(o3)
    if o1 ~= c1 then return o1 > c1 end
    if o2 ~= c2 then return o2 > c2 end
    return o3 > c3
end

function RCLPAddon:OnInitialize()
    if type(RCLPriorityDB) ~= "table" then RCLPriorityDB = {} end
    if type(RCLPriorityDB.players) ~= "table" then RCLPriorityDB.players = {} end
    if type(RCLPriorityDB.priority) ~= "table" then RCLPriorityDB.priority = {} end
    self:RegisterComm(RCLPL_COMM_PREFIX, "OnVersionReceived")
end

function RCLPAddon:OnEnable()
    -- Delay 5s so the guild channel is ready before we broadcast.
    self:ScheduleTimer("BroadcastVersion", 5)
end

function RCLPAddon:BroadcastVersion()
    if not IsInGuild() then return end
    self:SendCommMessage(RCLPL_COMM_PREFIX, RCLPL_VERSION, "GUILD")
end

function RCLPAddon:OnVersionReceived(prefix, message, distribution, sender)
    if sender == UnitName("player") then return end
    -- Reply once so players already online when we log in can see our version.
    if not hasRepliedToOthers and IsInGuild() then
        hasRepliedToOthers = true
        self:SendCommMessage(RCLPL_COMM_PREFIX, RCLPL_VERSION, "GUILD")
    end
    if versionWarned then return end
    if IsNewer(RCLPL_VERSION, message) then
        versionWarned = true
        print(string.format(
            "|cFFFF8000[RCLootCouncil_PriorityLoot]|r %s has version %s (you have %s)." ..
            " Get the update: github.com/katogaming88/RCLootCouncil_PriorityLoot",
            sender, message, RCLPL_VERSION
        ))
    end
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
