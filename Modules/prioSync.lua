-- Modules\prioSync.lua
-- Broadcasts imported priority/BiS data to the raid or party so every
-- member's own client shows priority ranks, not just whoever ran
-- /rcpl import. Previously RCPL_DB was purely per-account SavedVariables --
-- an officer's import only ever populated their own client, so nobody
-- else's loot frame or voting frame showed anything until they also
-- individually pasted the same export string in.
--
-- Uses RCLootCouncil's own Services.Comms (compression + serialization +
-- large-message chunking + combat-restriction queuing all handled there)
-- rather than raw AceComm, the same way RCLootCouncil_wowaudit's
-- Modules/shareData.lua shares its own wishlist data.

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCPLAddon = addon:GetModule("RCLootCouncil_PriorityLoot")
local RCPLSync = RCPLAddon:NewModule("RCPLPrioSync", "AceEvent-3.0", "AceTimer-3.0")
RCPLSync:SetEnabledState(true)

local Comms = addon.Require "Services.Comms"

local PREFIX          = "RCPL_Sync"
local COMMAND_DATA     = "prio_data"
local COMMAND_REQUEST  = "prio_request"
local ROSTER_DEBOUNCE  = 3  -- seconds

local Log = RCPL_Log or {
    debug = function() end, info = function() end,
    warn = function() end, error = function() end,
}

-- Rebuilds the same {players=..., priority=...} shape RCPL_Data_SaveImportedData
-- expects from whatever's currently in RCPL_DB, so a broadcast can be
-- (re-)triggered at any time -- not just in the moment right after an
-- import -- covering /rcpl broadcast, the roster-join resync below, and
-- replying to another client's prio_request.
local function CurrentPayload()
    if type(RCPL_DB) ~= "table" then return nil, 0, 0 end
    local players  = type(RCPL_DB.players)  == "table" and RCPL_DB.players  or {}
    local priority = type(RCPL_DB.priority) == "table" and RCPL_DB.priority or {}
    local playerCount, priorityCount = 0, 0
    for _ in pairs(players)  do playerCount  = playerCount  + 1 end
    for _ in pairs(priority) do priorityCount = priorityCount + 1 end
    if playerCount == 0 and priorityCount == 0 then return nil, 0, 0 end
    return { players = players, priority = priority }, playerCount, priorityCount
end

-- Sends whatever this client currently has to the raid/party. A no-op for
-- the vast majority of clients (raiders who never ran /rcpl import), since
-- CurrentPayload() returns nil when there's nothing to offer.
function RCPLSync:Broadcast(reason)
    local payload, playerCount, priorityCount = CurrentPayload()
    if not payload then
        Log.debug("Broadcast skipped (%s): no data to send", tostring(reason))
        return
    end
    self:Send("group", COMMAND_DATA, payload)
    Log.debug("Broadcast sent (%s): %d player(s), %d priority item(s)", tostring(reason), playerCount, priorityCount)
end

-- Asks whoever else in the group already has data to (re-)send it -- covers
-- a client that joined/reloaded after the initial broadcast already went
-- out and doesn't want to wait for the next roster-change resync.
function RCPLSync:RequestSync()
    self:Send("group", COMMAND_REQUEST)
    Log.debug("Sent prio_request to group")
end

local function OnPrioDataReceived(data, sender)
    if sender == UnitName("player") then return end
    local payload = data[1]
    if type(payload) ~= "table" then return end
    local playerCount, priorityCount = RCPL_Data_SaveImportedData(payload)
    priorityCount = priorityCount or 0
    print(string.format(
        "|cFF00FF00[RCLootCouncil_PriorityLoot]|r Priority data synced from %s (%d player(s), %d priority item(s)).",
        sender, playerCount, priorityCount
    ))
    Log.debug("Applied prio_data from %s: %d player(s), %d priority item(s)", sender, playerCount, priorityCount)
end

local function OnPrioRequestReceived(_, sender)
    if sender == UnitName("player") then return end
    RCPLSync:Broadcast("requested by " .. tostring(sender))
end

function RCPLSync:OnInitialize()
    self.Send = Comms:GetSender(PREFIX)
    Comms:BulkSubscribe(PREFIX, {
        [COMMAND_DATA]    = function(data, sender) OnPrioDataReceived(data, sender) end,
        [COMMAND_REQUEST] = function(data, sender) OnPrioRequestReceived(data, sender) end,
    })
    Log.debug("prioSync initialized on prefix %s", PREFIX)
end

-- A few seconds after the group roster changes, offer up whatever this
-- client has. Covers a raid member who reloads or zones in mid-raid (and
-- so missed the officer's original post-import broadcast) getting synced
-- automatically, without anyone having to remember to run /rcpl broadcast
-- by hand. Debounced since GROUP_ROSTER_UPDATE can fire repeatedly in a
-- burst as a raid forms.
function RCPLSync:OnEnable()
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnGroupRosterUpdate")
end

function RCPLSync:OnGroupRosterUpdate()
    if not (IsInRaid() or IsInGroup()) then return end
    if self._rosterTimer then return end
    self._rosterTimer = self:ScheduleTimer(function()
        self._rosterTimer = nil
        self:Broadcast("roster update")
    end, ROSTER_DEBOUNCE)
end
