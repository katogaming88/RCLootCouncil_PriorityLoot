-- Core.lua
-- Registers RCLootCouncil_PriorityLoot as a sub-module of RCLootCouncil,
-- following the same pattern as RCLootCouncil_wowaudit.

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCLPAddon = addon:NewModule("RCLootCouncil_PriorityLoot", "AceTimer-3.0", "AceComm-3.0")
-- RCLootCouncil sets defaultModuleState=false for sub-modules; opt back in so OnEnable fires.
RCLPAddon:SetEnabledState(true)

-- Expose globally so Modules/ files can reach it via addon:GetModule().
RCLootCouncil_PriorityLoot = RCLPAddon

local RCPL_VERSION       = "0.1.7"
local RCPL_COMM_PREFIX   = "RCPL_Ver"
local RCPL_CHECK_PREFIX  = "RCPL_Chk"
local CHECK_TIMEOUT      = 10

-- Modules/log.lua loads before Core.lua (see .toc), so RCPL_Log is always
-- available by the time any function below executes. Capture as a local for
-- speed; if the global is ever missing, fall back to no-ops to avoid hard
-- failures inside lifecycle callbacks.
local Log = RCPL_Log or {
    debug = function() end, info = function() end,
    warn = function() end, error = function() end,
}

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
    Log.debug("OnInitialize fired (version=%s)", RCPL_VERSION)
    if type(RCLPriorityDB) ~= "table" then RCLPriorityDB = {} end
    if type(RCLPriorityDB.players) ~= "table" then RCLPriorityDB.players = {} end
    if type(RCLPriorityDB.priority) ~= "table" then RCLPriorityDB.priority = {} end
    self:RegisterComm(RCPL_COMM_PREFIX, "OnVersionReceived")
    self:RegisterComm(RCPL_CHECK_PREFIX, "OnVersionCheckMessage")
    Log.debug("Comm prefixes registered: %s, %s", RCPL_COMM_PREFIX, RCPL_CHECK_PREFIX)
end

function RCLPAddon:OnEnable()
    Log.debug("OnEnable fired, scheduling BroadcastVersion in 5s")
    -- Delay 5s so the guild channel is ready before we broadcast.
    self:ScheduleTimer("BroadcastVersion", 5)
end

function RCLPAddon:BroadcastVersion()
    local inGuild = IsInGuild()
    Log.debug("BroadcastVersion fired (IsInGuild=%s, version=%s)", tostring(inGuild), RCPL_VERSION)
    if not inGuild then
        Log.debug("BroadcastVersion bailing: player not in a guild")
        return
    end
    self:SendCommMessage(RCPL_COMM_PREFIX, RCPL_VERSION, "GUILD")
    Log.debug("Sent guild version broadcast (%s on %s)", RCPL_VERSION, RCPL_COMM_PREFIX)
end

function RCLPAddon:OnVersionReceived(prefix, message, distribution, sender)
    Log.debug("OnVersionReceived: prefix=%s message=%s dist=%s sender=%s self=%s",
        tostring(prefix), tostring(message), tostring(distribution),
        tostring(sender), tostring(UnitName("player")))
    if sender == UnitName("player") then
        Log.debug("OnVersionReceived: ignoring self-loopback from %s", tostring(sender))
        return
    end
    -- Reply once so players already online when we log in can see our version.
    if not hasRepliedToOthers and IsInGuild() then
        hasRepliedToOthers = true
        self:SendCommMessage(RCPL_COMM_PREFIX, RCPL_VERSION, "GUILD")
        Log.debug("Reply-once broadcast sent in response to %s", tostring(sender))
    end
    if versionWarned then return end
    if IsNewer(RCPL_VERSION, message) then
        versionWarned = true
        Log.info("Newer version detected from %s: %s (you have %s)",
            tostring(sender), tostring(message), RCPL_VERSION)
        print(string.format(
            "|cFFFF8000[RCLootCouncil_PriorityLoot]|r %s has version %s (you have %s)." ..
            " Get the update: github.com/katogaming88/RCLootCouncil_PriorityLoot",
            sender, message, RCPL_VERSION
        ))
    else
        Log.debug("Received version %s from %s; not newer than local %s",
            tostring(message), tostring(sender), RCLPL_VERSION)
    end
end

-- Handles both incoming REQUEST and version-response messages on RCPL_Chk.
function RCLPAddon:OnVersionCheckMessage(prefix, message, distribution, sender)
    Log.debug("OnVersionCheckMessage: prefix=%s message=%s dist=%s sender=%s",
        tostring(prefix), tostring(message), tostring(distribution), tostring(sender))
    if sender == UnitName("player") then return end
    if message == "REQUEST" then
        local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
        if channel then
            self:SendCommMessage(RCPL_CHECK_PREFIX, RCPL_VERSION, channel)
            Log.debug("Replied to version REQUEST from %s on %s", tostring(sender), channel)
        else
            Log.debug("Ignoring REQUEST from %s; not in raid or party", tostring(sender))
        end
    elseif versionCheckResults then
        versionCheckResults[sender] = message
        Log.debug("Recorded version response: %s = %s", tostring(sender), tostring(message))
    end
end

function RCLPAddon:StartVersionCheck()
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if not channel then
        print("|cFF00FF00[RCLootCouncil_PriorityLoot]|r You must be in a group to check versions.")
        return
    end
    versionCheckResults = {}
    versionCheckResults[UnitName("player")] = RCPL_VERSION
    self:SendCommMessage(RCPL_CHECK_PREFIX, "REQUEST", channel)
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
        if entry.version == RCPL_VERSION then
            color = "|cFF00FF00"
        elseif IsNewer(RCPL_VERSION, entry.version) then
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

local function HandleLogSubcommand(rest)
    rest = rest or ""
    if rest == "" or rest == "show" then
        if RCPL_Log then RCPL_Log.Show() else print("|cFFFF4444[RCLP]|r logger not loaded") end
    elseif rest == "dump" then
        if RCPL_Log then RCPL_Log.DumpToChat() else print("|cFFFF4444[RCLP]|r logger not loaded") end
    elseif rest == "clear" then
        if RCPL_Log then RCPL_Log.Clear() end
        print("|cFF00FF00[RCLP]|r log cleared.")
    else
        print("|cFF00FF00[RCLP]|r log subcommands:")
        print("  /rcpl log         open the log window")
        print("  /rcpl log dump    dump entries to chat")
        print("  /rcpl log clear   clear the in-memory log")
    end
end

SLASH_RCPL1 = "/rcpl"
SlashCmdList["RCPL"] = function(input)
    local raw = strtrim(input or "")
    local cmd, rest = raw:match("^(%S+)%s*(.-)$")
    cmd = cmd or ""
    rest = strtrim(rest or "")

    if cmd == "" then
        print("|cFF00FF00[RCLootCouncil_PriorityLoot]|r Commands:")
        print("  /rcpl import      open the priority data import window")
        print("  /rcpl prio        preview imported priority data")
        print("  /rcpl reset       clear all stored priority data")
        print("  /rcpl version     check addon versions across your raid/party")
        print("  /rcpl debug       toggle debug logging on or off")
        print("  /rcpl log         open the log window (also: dump, clear)")
    elseif cmd == "import" then
        RCPL_ShowImportFrame()
    elseif cmd == "prio" then
        RCPL_ShowPrioPreview()
    elseif cmd == "reset" then
        RCPL_Data_ResetData()
        print("|cFF00FF00[RCLootCouncil_PriorityLoot]|r All priority data cleared.")
    elseif cmd == "version" or cmd == "ver" or cmd == "v" then
        RCLPAddon:StartVersionCheck()
    elseif cmd == "debug" then
        local state
        if rest == "on" or rest == "true" or rest == "1" then
            state = RCPL_Log and RCPL_Log.SetDebug(true)
        elseif rest == "off" or rest == "false" or rest == "0" then
            state = RCPL_Log and RCPL_Log.SetDebug(false)
        else
            state = RCPL_Log and RCPL_Log.ToggleDebug()
        end
        print(string.format("|cFF00FF00[RCLP]|r debug logging %s",
            state and "|cFF00FF00ON|r" or "|cFFFF4444OFF|r"))
    elseif cmd == "log" then
        HandleLogSubcommand(rest)
    else
        print(string.format("|cFFFF4444[RCLP]|r unknown command: %s", cmd))
    end
end
