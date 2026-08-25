-- Core.lua
-- Registers RCLootCouncil_PriorityLoot as a sub-module of RCLootCouncil,
-- following the same pattern as RCLootCouncil_wowaudit.

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCPLAddon = addon:NewModule("RCLootCouncil_PriorityLoot", "AceTimer-3.0", "AceComm-3.0", "AceEvent-3.0")
-- RCLootCouncil sets defaultModuleState=false for sub-modules; opt back in so OnEnable fires.
RCPLAddon:SetEnabledState(true)

-- Expose globally so Modules/ files can reach it via addon:GetModule().
RCLootCouncil_PriorityLoot = RCPLAddon

-- Read from the .toc's own ## Version rather than a hardcoded duplicate --
-- that constant sat at "0.2.0" through several real releases (0.2.1-0.2.3)
-- because nothing forced it to be bumped alongside the .toc, silently
-- breaking the whole point of this feature (every version check compared
-- against a stale local value). Single source of truth now.
local RCPL_VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("RCLootCouncil_PriorityLoot", "Version"))
    or (GetAddOnMetadata and GetAddOnMetadata("RCLootCouncil_PriorityLoot", "Version"))
    or "0.0.0"
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
local versionCheckResults = nil  -- nil = no check in progress, table = collecting
local versionCheckTimer   = nil

-- Public so Modules/versionCheckFrame.lua doesn't need its own separate way
-- to read the local version.
function RCPLAddon:GetVersion()
    return RCPL_VERSION
end

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

function RCPLAddon:OnInitialize()
    Log.debug("OnInitialize fired (version=%s)", RCPL_VERSION)
    if type(RCPL_DB) ~= "table" then RCPL_DB = {} end
    if type(RCPL_DB.players)  ~= "table" then RCPL_DB.players  = {} end
    if type(RCPL_DB.priority) ~= "table" then RCPL_DB.priority = {} end
    if type(RCPL_DB.awarded)  ~= "table" then RCPL_DB.awarded  = {} end
    if type(RCPL_DB.minimap)  ~= "table" then RCPL_DB.minimap  = { hide = false } end
    if self.InitMinimapButton then self:InitMinimapButton() end
    self:RegisterComm(RCPL_COMM_PREFIX, "OnVersionReceived")
    self:RegisterComm(RCPL_CHECK_PREFIX, "OnVersionCheckMessage")
    Log.debug("Comm prefixes registered: %s, %s", RCPL_COMM_PREFIX, RCPL_CHECK_PREFIX)
end

function RCPLAddon:OnEnable()
    Log.debug("OnEnable fired, scheduling BroadcastVersion in 5s")
    self:ScheduleTimer("BroadcastVersion", 5)
    self:RegisterMessage("RCMLAwardSuccess", "OnAwardSuccess")
    Log.debug("Registered RCMLAwardSuccess hook for award tracking")
end

function RCPLAddon:OnAwardSuccess(_, session, winner, status, link, responseText)
    if status == "test_mode" then return end
    -- Skip special award reasons (Disenchant, Banking, Free, and any user-defined ones).
    -- responseText matches reason.text for these; normal loot responses never appear in awardReasons.
    local rcdb = addon:Getdb()
    if rcdb and rcdb.awardReasons then
        for _, reason in pairs(rcdb.awardReasons) do
            if reason.text == responseText then return end
        end
    end
    local itemID = link and link:match("|Hitem:(%d+)")
    if not itemID or not winner then return end
    RCPL_Data_MarkAwarded(winner, itemID, link)
    Log.debug("Award tracked: %s received %s (session=%s)", winner, itemID, tostring(session))
end

function RCPLAddon:BroadcastVersion()
    local inGuild = IsInGuild()
    Log.debug("BroadcastVersion fired (IsInGuild=%s, version=%s)", tostring(inGuild), RCPL_VERSION)
    if not inGuild then
        Log.debug("BroadcastVersion bailing: player not in a guild")
        return
    end
    self:SendCommMessage(RCPL_COMM_PREFIX, RCPL_VERSION, "GUILD")
    Log.debug("Sent guild version broadcast (%s on %s)", RCPL_VERSION, RCPL_COMM_PREFIX)
end

function RCPLAddon:OnVersionReceived(prefix, message, distribution, sender)
    Log.debug("OnVersionReceived: prefix=%s message=%s dist=%s sender=%s self=%s",
        tostring(prefix), tostring(message), tostring(distribution),
        tostring(sender), tostring(UnitName("player")))
    if sender == UnitName("player") then
        Log.debug("OnVersionReceived: ignoring self-loopback from %s", tostring(sender))
        return
    end
    -- Whisper our version directly back to the broadcaster instead of
    -- replying on GUILD. WHISPER replies are only delivered to the original
    -- broadcaster, so other guildmates never see them and can't mistake them
    -- for a fresh broadcast that needs another reply. That eliminates the
    -- reply loop without any session or per-sender dedup, which means every
    -- broadcast (login or /reload) gets a fresh round of replies from every
    -- online guildmate, even guildmates who have already replied to this
    -- sender earlier in the session. The distribution check breaks the
    -- trivial "our own whisper arrives back at us" loop.
    --
    -- The IsInGuild() guard from the old design is intentionally gone:
    -- WHISPER addon messages don't require shared guild membership, and a
    -- RCPL_Ver message could only reach us via a channel where reply makes
    -- sense (currently GUILD, which already implies we are guildies).
    if sender and sender ~= "" and distribution ~= "WHISPER" then
        self:SendCommMessage(RCPL_COMM_PREFIX, RCPL_VERSION, "WHISPER", sender)
        Log.debug("Whispered version reply to %s", tostring(sender))
    end
    if versionWarned then return end
    if IsNewer(RCPL_VERSION, message) then
        versionWarned = true
        Log.debug("Newer version detected from %s: %s (you have %s)",
            tostring(sender), tostring(message), RCPL_VERSION)
        print(string.format(
            "|cFFFF8000[RCLootCouncil_PriorityLoot]|r %s has version %s (you have %s)." ..
            " Get the update: github.com/katogaming88/RCLootCouncil_PriorityLoot",
            sender, message, RCPL_VERSION
        ))
    else
        Log.debug("Received version %s from %s; not newer than local %s",
            tostring(message), tostring(sender), RCPL_VERSION)
    end
end

-- Handles both incoming REQUEST and version-response messages on RCPL_Chk.
function RCPLAddon:OnVersionCheckMessage(prefix, message, distribution, sender)
    Log.debug("OnVersionCheckMessage: prefix=%s message=%s dist=%s sender=%s",
        tostring(prefix), tostring(message), tostring(distribution), tostring(sender))
    if sender == UnitName("player") then return end
    if message == "REQUEST" then
        -- Reply on whatever channel the REQUEST actually arrived on, rather
        -- than recomputing our own current group state -- a GUILD-wide
        -- check needs replies from guildies who aren't in the requester's
        -- raid/party (or aren't grouped at all), and recomputing IsInRaid()/
        -- IsInGroup() here would silently drop exactly those replies.
        if distribution == "RAID" or distribution == "PARTY" or distribution == "GUILD" then
            self:SendCommMessage(RCPL_CHECK_PREFIX, RCPL_VERSION, distribution)
            Log.debug("Replied to version REQUEST from %s on %s", tostring(sender), distribution)
        else
            Log.debug("Ignoring REQUEST from %s on unexpected distribution %s", tostring(sender), tostring(distribution))
        end
    elseif versionCheckResults then
        versionCheckResults[sender] = message
        Log.debug("Recorded version response: %s = %s", tostring(sender), tostring(message))
        if RCPL_VersionCheck_UpdateRow then RCPL_VersionCheck_UpdateRow(sender, message) end
    end
end

-- scope: "guild" explicitly polls the guild roster; anything else (nil, "")
-- polls the current raid/party. Drives Modules/versionCheckFrame.lua's
-- window live as replies arrive -- see that file for the UI half. Seeds a
-- "Waiting..." row for every expected recipient up front (mirrors base
-- RCLootCouncil's own Query()), so the window shows who hasn't replied yet
-- rather than staying blank until the timeout.
function RCPLAddon:StartVersionCheck(scope)
    local channel
    if scope == "guild" then
        channel = IsInGuild() and "GUILD" or nil
        if not channel then
            print("|cFF00FF00[RCLootCouncil_PriorityLoot]|r You must be in a guild to check versions.")
            return
        end
    else
        channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
        if not channel then
            print("|cFF00FF00[RCLootCouncil_PriorityLoot]|r You must be in a group to check versions."
                .. " Use the Guild button (or /rcpl version guild) to check your guild instead.")
            return
        end
    end

    local myName = UnitName("player")
    versionCheckResults = { [myName] = RCPL_VERSION }

    if RCPL_VersionCheck_Reset then RCPL_VersionCheck_Reset(myName, RCPL_VERSION) end

    if channel == "GUILD" then
        for i = 1, GetNumGuildMembers() do
            local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            local bareName = name and (name:match("^([^%-]+)") or name)
            if name and online and name ~= myName and bareName ~= myName and RCPL_VersionCheck_SeedWaiting then
                RCPL_VersionCheck_SeedWaiting(name)
            end
        end
    else
        local unitPrefix = channel == "RAID" and "raid" or "party"
        for i = 1, GetNumGroupMembers() do
            local name = GetUnitFullName(unitPrefix .. i)
            if name and name ~= myName and RCPL_VersionCheck_SeedWaiting then
                RCPL_VersionCheck_SeedWaiting(name)
            end
        end
    end

    self:SendCommMessage(RCPL_CHECK_PREFIX, "REQUEST", channel)
    if versionCheckTimer then self:CancelTimer(versionCheckTimer) end
    versionCheckTimer = self:ScheduleTimer("FinalizeVersionCheck", CHECK_TIMEOUT)
end

function RCPLAddon:FinalizeVersionCheck()
    versionCheckTimer = nil
    if RCPL_VersionCheck_MarkMissing then RCPL_VersionCheck_MarkMissing() end
    versionCheckResults = nil
end

local function HandleAwardSubcommand(args, undo)
    local link   = args:match("|H.+|h%[.+%]|h")
    local player = args:match("^(%S+)")
    local itemID = link and link:match("|Hitem:(%d+)")
    if not player or not itemID then
        local verb = undo and "unaward" or "award"
        print("|cFF00FF00[RCPL]|r Usage: /rcpl " .. verb .. " PlayerName-Realm [shift-click item]")
        return
    end
    if undo then
        RCPL_Data_UnmarkAwarded(player, itemID)
        print(string.format("|cFF00FF00[RCPL]|r Award removed: %s -- %s", player, link))
    else
        RCPL_Data_MarkAwarded(player, itemID, link)
        print(string.format("|cFF00FF00[RCPL]|r Award recorded: %s -- %s", player, link))
    end
end


local function HandleLogSubcommand(rest)
    rest = rest or ""
    if rest == "" or rest == "show" then
        if RCPL_Log then RCPL_Log.Show() else print("|cFFFF4444[RCPL]|r logger not loaded") end
    elseif rest == "dump" then
        if RCPL_Log then RCPL_Log.DumpToChat() else print("|cFFFF4444[RCPL]|r logger not loaded") end
    elseif rest == "clear" then
        if RCPL_Log then RCPL_Log.Clear() end
        print("|cFF00FF00[RCPL]|r log cleared.")
    else
        print("|cFF00FF00[RCPL]|r log subcommands:")
        print("  /rcpl log         open the log window")
        print("  /rcpl log dump    dump entries to chat")
        print("  /rcpl log clear   clear the persisted log")
    end
end

SLASH_RCPL1 = "/rcpl"
SlashCmdList["RCPL"] = function(input)
    local raw = strtrim(input or "")
    local cmd, rest = raw:match("^(%S+)%s*(.-)$")
    cmd = cmd or ""
    rest = strtrim(rest or "")

    if cmd == "" then
        if RCPL_ShowOptionsFrame then
            RCPL_ShowOptionsFrame()
        else
            print("|cFF00FF00[RCLootCouncil_PriorityLoot]|r Commands:")
            print("  /rcpl import                   open the priority data import window")
            print("  /rcpl prio                     preview imported priority data")
            print("  /rcpl broadcast                (re-)send your priority data to the raid/party")
            print("  /rcpl sync                     ask the raid/party to (re-)send priority data to you")
            print("  /rcpl reset                    clear all stored priority data")
            print("  /rcpl awards                   open the season awards window")
            print("  /rcpl award <player> <item>    manually record an award")
            print("  /rcpl unaward <player> <item>  undo a recorded award")
            print("  /rcpl version                  open the version checker (Guild/Group buttons)")
            print("  /rcpl version guild            open it and immediately check your guild")
            print("  /rcpl debug                    toggle debug logging on or off")
            print("  /rcpl log                      open the log window (also: dump, clear)")
        end
    elseif cmd == "import" then
        RCPL_ShowImportFrame()
    elseif cmd == "prio" then
        RCPL_ShowPrioPreview()
    elseif cmd == "reset" then
        RCPL_Data_ResetData()
        print("|cFF00FF00[RCLootCouncil_PriorityLoot]|r All priority data cleared.")
    elseif cmd == "broadcast" then
        local sync = RCPLAddon:GetModule("RCPLPrioSync", true)
        if sync then
            sync:Broadcast("manual")
        else
            print("|cFFFF4444[RCPL]|r Sync module not loaded.")
        end
    elseif cmd == "sync" then
        local sync = RCPLAddon:GetModule("RCPLPrioSync", true)
        if sync then
            sync:RequestSync()
            print("|cFF00FF00[RCLootCouncil_PriorityLoot]|r Requested priority data from the raid/party.")
        else
            print("|cFFFF4444[RCPL]|r Sync module not loaded.")
        end
    elseif cmd == "awards" then
        RCPL_ShowAwardsFrame()
    elseif cmd == "award" then
        HandleAwardSubcommand(rest, false)
    elseif cmd == "unaward" then
        HandleAwardSubcommand(rest, true)
    elseif cmd == "version" or cmd == "ver" or cmd == "v" then
        -- Opens showing just your own version, matching base RCLootCouncil's
        -- own version checker -- Guild/Group buttons trigger the actual poll,
        -- never an automatic one. `/rcpl version guild` is a shortcut that
        -- also fires the guild poll immediately, for chat-only workflows.
        if RCPL_ShowVersionCheckFrame then RCPL_ShowVersionCheckFrame() end
        if rest == "guild" then
            RCPLAddon:StartVersionCheck("guild")
        end
    elseif cmd == "debug" then
        local state
        if rest == "on" or rest == "true" or rest == "1" then
            state = RCPL_Log and RCPL_Log.SetDebug(true)
        elseif rest == "off" or rest == "false" or rest == "0" then
            state = RCPL_Log and RCPL_Log.SetDebug(false)
        else
            state = RCPL_Log and RCPL_Log.ToggleDebug()
        end
        print(string.format("|cFF00FF00[RCPL]|r debug logging %s",
            state and "|cFF00FF00ON|r" or "|cFFFF4444OFF|r"))
    elseif cmd == "log" then
        HandleLogSubcommand(rest)
    else
        print(string.format("|cFFFF4444[RCPL]|r unknown command: %s", cmd))
    end
end
