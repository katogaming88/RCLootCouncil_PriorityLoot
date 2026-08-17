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

-- Public so Modules/importFrame.lua can reuse the exact same leader
-- resolution this module already applies to broadcasts, rather than a
-- second, possibly-drifting copy of the raid/party iteration.
function RCPLSync:GetLeaderName()
    return GetGroupLeaderName()
end

-- Whether the local player is currently allowed to import: either the
-- group has no resolvable leader (ungrouped -- the normal pre-raid import
-- workflow -- or the rare leaderless edge case), or the local player *is*
-- that leader. Modules/importFrame.lua uses this to refuse a non-leader's
-- import outright rather than letting them end up looking at priority data
-- nobody else in the raid will ever see (Broadcast() below would refuse to
-- send it anyway).
function RCPLSync:IsLocalPlayerLeader()
    local leader = GetGroupLeaderName()
    if not leader then return true end
    return addon.Utils:UnitName("player") == leader
end

-- Sends whatever this client currently has to the raid/party. A no-op for
-- the vast majority of clients (raiders who never ran /rcpl import), since
-- CurrentPayload() returns nil when there's nothing to offer -- and, while
-- actually grouped, a no-op for anyone but the raid/party leader, since
-- OnPrioDataReceived() below only ever applies a leader's data anyway.
-- Skipping the send here (rather than letting every non-leader client's
-- broadcast go out and quietly get rejected by everyone else) means the
-- non-leader who tried to import sees *why* nothing propagated, right in
-- their own chat, instead of just silence.
function RCPLSync:Broadcast(reason)
    local payload, playerCount, priorityCount = CurrentPayload()
    if not payload then
        Log.debug("Broadcast skipped (%s): no data to send", tostring(reason))
        return
    end
    if IsInRaid() or IsInGroup() then
        local leader = GetGroupLeaderName()
        local me = addon.Utils:UnitName("player")
        if leader and me ~= leader then
            print(string.format(
                "|cFFFFCC00[RCLootCouncil_PriorityLoot]|r Not sent -- only the raid/party leader's priority"
                    .. " data syncs to the group. Ask %s to import, or have raid lead passed to you.",
                leader
            ))
            Log.debug("Broadcast skipped (%s): not raid/party leader (leader=%s)", tostring(reason), tostring(leader))
            return
        end
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

-- Only ever applies data sent by the current raid/party leader -- not just
-- when it conflicts with something already stored, but unconditionally,
-- including the very first sync of the night. A raid assist (or anyone
-- else) importing a different string can still save it to their own
-- client, but it never reaches anyone else: Broadcast() above already
-- refuses to send it for a non-leader, and this is the backstop in case it
-- somehow gets sent anyway (e.g. leftover raw AceComm traffic, a modified
-- client). Uses UnitIsGroupLeader() over raid/party unit tokens rather than
-- RCLootCouncil's own council roster, since that roster isn't guaranteed
-- to have propagated to every client yet, especially early in a raid.
local function OnPrioDataReceived(data, sender)
    local me = addon.Utils:UnitName("player")
    if sender == me then return end
    local payload = data[1]
    if type(payload) ~= "table" then return end

    local leader = GetGroupLeaderName()
    if sender ~= leader then
        -- Only worth a chat warning when this would actually have changed
        -- something -- a non-leader's data that happens to match what's
        -- already stored (or nothing being stored, with nothing to lose)
        -- doesn't need to alarm anyone.
        local current = CurrentPayload()
        if not current or not DeepEqual(payload, current) then
            print(string.format(
                "|cFFFFCC00[RCLootCouncil_PriorityLoot]|r Ignored priority data from %s -- only the raid/party"
                    .. " leader's data is applied, and %s isn't the leader.",
                sender, sender
            ))
            Log.debug("Rejected prio_data from %s: not raid/party leader (leader=%s)", sender, tostring(leader))
        end
        return
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
    if sender == addon.Utils:UnitName("player") then return end
    RCPLSync:Broadcast("requested by " .. tostring(sender))
end

-- Resets (rather than a permanent one-shot) so a client that goes empty
-- again later in the session -- e.g. /rcpl reset -- can warn again, but
-- won't repeat on every single roster change while it stays empty.
local warnedEmpty = false

-- A client stuck with no priority data at all otherwise just sits on an
-- empty voting-frame side panel and an N/A loot overlay for a whole raid
-- with zero indication why -- easy to happen on a client that's a version
-- or two behind (missed the import-status/reload-prompt fixes, or predates
-- this sync module existing entirely, so it was never even subscribed to
-- receive anyone else's broadcast). Fires once per empty streak, a few
-- seconds after joining/forming a group.
function RCPLSync:WarnIfEmpty()
    if CurrentPayload() then
        warnedEmpty = false
        return
    end
    if warnedEmpty then return end
    warnedEmpty = true

    if self:IsLocalPlayerLeader() then
        print("|cFFFFCC00[RCLootCouncil_PriorityLoot]|r No priority data loaded. Run /rcpl import to load this"
            .. " week's export.")
    else
        local leader = self:GetLeaderName() or "the raid/party leader"
        print(string.format(
            "|cFFFFCC00[RCLootCouncil_PriorityLoot]|r No priority data loaded yet -- requesting it from the"
                .. " group. If this doesn't resolve shortly, ask %s to run /rcpl broadcast, or check that your"
                .. " addon is up to date.", leader
        ))
        self:RequestSync()
    end
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
        self:WarnIfEmpty()
    end, ROSTER_DEBOUNCE)
end
