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

-- Recursively compares two plain data tables (no metatables/functions
-- expected here -- these are always decoded-JSON-shaped), used to tell a
-- genuinely conflicting incoming sync apart from a harmless duplicate
-- rebroadcast of the same data.
local function DeepEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not DeepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- Full-name ("Name-Realm") of the current raid/party leader, or nil when
-- ungrouped or leaderless (should never happen while grouped, but Blizzard
-- doesn't guarantee it during the brief window right after group formation).
-- addon.Utils:UnitName() is the same normalisation Services.Comms already
-- applies to every incoming sender name, so the two are directly comparable.
local function GetGroupLeaderName()
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if UnitIsGroupLeader(unit) then return addon.Utils:UnitName(unit) end
        end
    elseif IsInGroup() then
        if UnitIsGroupLeader("player") then return addon.Utils:UnitName("player") end
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            if UnitIsGroupLeader(unit) then return addon.Utils:UnitName(unit) end
        end
    end
    return nil
end

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

-- Accepts a sync unless it actually conflicts with data this client already
-- has: an empty/no-data client always accepts (nothing to conflict with), a
-- duplicate of what's already stored is a harmless no-op, and anyone can
-- still send -- but once real, different data is already stored, only the
-- current raid/party leader is allowed to overwrite it. Blocks a random
-- group member (accidentally or otherwise) from clobbering everyone's
-- already-synced priority display with something else, without depending
-- on RCLootCouncil's own council roster having propagated yet.
local function OnPrioDataReceived(data, sender)
    if sender == UnitName("player") then return end
    local payload = data[1]
    if type(payload) ~= "table" then return end

    local current = CurrentPayload()
    if current and not DeepEqual(payload, current) then
        local leader = GetGroupLeaderName()
        if sender ~= leader then
            print(string.format(
                "|cFFFFCC00[RCLootCouncil_PriorityLoot]|r Ignored priority data from %s -- it differs from"
                    .. " what you already have, and %s isn't the raid/party leader.",
                sender, sender
            ))
            Log.debug("Rejected conflicting prio_data from %s (leader=%s)", sender, tostring(leader))
            return
        end
    end

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
