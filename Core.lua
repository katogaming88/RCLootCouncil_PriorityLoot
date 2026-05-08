-- Core.lua
-- Registers RCLootCouncil_PriorityLoot as a sub-module of RCLootCouncil,
-- following the same pattern as RCLootCouncil_wowaudit.

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCLPAddon = addon:NewModule("RCLootCouncil_PriorityLoot", "AceTimer-3.0", "AceComm-3.0")
-- RCLootCouncil sets defaultModuleState=false for sub-modules; opt back in so OnEnable fires.
RCLPAddon:SetEnabledState(true)

-- Expose globally so Modules/ files can reach it via addon:GetModule().
RCLootCouncil_PriorityLoot = RCLPAddon

local RCLPL_VERSION      = "0.1.6"
local RCLPL_COMM_PREFIX  = "RCLPL_Ver"
local RCLPL_CHECK_PREFIX = "RCLPL_Chk"
local CHECK_TIMEOUT      = 10

local versionWarned       = false
local hasRepliedToOthers  = false
local versionCheckResults = nil  -- nil = no check in progress, table = collecting
local versionCheckTimer   = nil

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

-- Returns "Name" for same-realm units, "Name-Realm" for cross-realm.
local function GetUnitFullName(unit)
    local name, realm = UnitName(unit)
    if not name then return nil end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

function RCLPAddon:OnInitialize()
    if type(RCLPriorityDB) ~= "table" then RCLPriorityDB = {} end
    if type(RCLPriorityDB.players) ~= "table" then RCLPriorityDB.players = {} end
    if type(RCLPriorityDB.priority) ~= "table" then RCLPriorityDB.priority = {} end
    self:RegisterComm(RCLPL_COMM_PREFIX, "OnVersionReceived")
    self:RegisterComm(RCLPL_CHECK_PREFIX, "OnVersionCheckMessage")
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

-- Handles both incoming REQUEST and version-response messages on RCLPL_Chk.
function RCLPAddon:OnVersionCheckMessage(prefix, message, distribution, sender)
    if sender == UnitName("player") then return end
    if message == "REQUEST" then
        local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
        if channel then
            self:SendCommMessage(RCLPL_CHECK_PREFIX, RCLPL_VERSION, channel)
        end
    elseif versionCheckResults then
        versionCheckResults[sender] = message
    end
end

function RCLPAddon:StartVersionCheck()
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if not channel then
        print("|cFF00FF00[RCLootCouncil_PriorityLoot]|r You must be in a group to check versions.")
        return
    end
    versionCheckResults = {}
    versionCheckResults[UnitName("player")] = RCLPL_VERSION
    self:SendCommMessage(RCLPL_CHECK_PREFIX, "REQUEST", channel)
    print(string.format(
        "|cFF00FF00[RCLootCouncil_PriorityLoot]|r Checking addon versions... (results in %ds)",
        CHECK_TIMEOUT
    ))
    if versionCheckTimer then self:CancelTimer(versionCheckTimer) end
    versionCheckTimer = self:ScheduleTimer("PrintVersionCheckResults", CHECK_TIMEOUT)
end

function RCLPAddon:PrintVersionCheckResults()
    versionCheckTimer = nil
    local myName = UnitName("player")
    local withAddon, withoutAddon = {}, {}

    local function processUnit(unit)
        local name = GetUnitFullName(unit)
        if not name then return end
        local ver = versionCheckResults[name]
        if ver then
            withAddon[#withAddon + 1] = { name = name, version = ver }
        else
            withoutAddon[#withoutAddon + 1] = name
        end
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do processUnit("raid" .. i) end
    else
        processUnit("player")
        for i = 1, GetNumGroupMembers() do processUnit("party" .. i) end
    end

    table.sort(withAddon, function(a, b) return a.name < b.name end)
    table.sort(withoutAddon)

    local total = #withAddon + #withoutAddon
    print(string.format(
        "|cFF00FF00[RCLootCouncil_PriorityLoot]|r Version check (%d/%d have addon):",
        #withAddon, total
    ))
    for _, entry in ipairs(withAddon) do
        local color
        if entry.version == RCLPL_VERSION then
            color = "|cFF00FF00"
        elseif IsNewer(RCLPL_VERSION, entry.version) then
            color = "|cFFFF8000"
        else
            color = "|cFFFFFF00"
        end
        local tag = entry.name == myName and " (you)" or ""
        print(string.format("  %s%s|r — %s%s", color, entry.name, entry.version, tag))
    end
    for _, name in ipairs(withoutAddon) do
        print(string.format("  |cFFAAAAAA%s|r — not installed", name))
    end

    versionCheckResults = nil
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
    elseif cmd == "version" or cmd == "ver" or cmd == "v" then
        RCLPAddon:StartVersionCheck()
    else
        print("|cFF00FF00[RCLootCouncil_PriorityLoot]|r Commands:")
        print("  /rcpl import   — open the priority data import window")
        print("  /rcpl prio     — preview imported priority data")
        print("  /rcpl reset    — clear all stored priority data")
        print("  /rcpl version  — check addon versions across your raid/party")
    end
end
