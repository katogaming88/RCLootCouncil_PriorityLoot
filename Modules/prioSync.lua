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
-- Player cache/lookup (resolves a bare "Name-Realm" string to a GUID via the
-- group roster or guild) -- the same class Services.Comms requires as its
-- whisper target, needed by ForcePush() below to whisper directly to one
-- raid/party member instead of broadcasting to the whole group.
local PlayerData = addon.Require "Data.Player"
-- True during an encounter/challenge mode -- Services.Comms silently drops
-- (not queues) a plain Send() while this is active, only logging a debug
-- warning we never see. ForcePush() below checks this itself rather than
-- letting Comms swallow the send and print a false "Pushed" confirmation --
-- unlike Broadcast()'s roster-change resync, a push is a deliberate action
-- the officer is watching for a result from, so a silent drop here is
-- actively misleading rather than just "catches up on the next resync".
local CommsRestrictions = addon.Require "Services.CommsRestrictions"

local PREFIX             = "RCPL_Sync"
local COMMAND_DATA        = "prio_data"
local COMMAND_REQUEST     = "prio_request"
local COMMAND_STATUS_REQ  = "prio_status_req"
local COMMAND_STATUS_REPL = "prio_status_repl"
local ROSTER_DEBOUNCE     = 3   -- seconds
local STATUS_TIMEOUT      = 10  -- seconds, matches Core.lua's own version-check timeout

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

-- Full-name ("Name-Realm") of every other raid/party member, for seeding the
-- Sync Status window's row list up front (same reasoning as Core.lua's own
-- StartVersionCheck: show who hasn't replied yet rather than staying blank
-- until the timeout) and as the pool ForcePushAllMissing() below iterates.
local function GetGroupMemberNames()
    local me = addon.Utils:UnitName("player")
    local names = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name = addon.Utils:UnitName("raid" .. i)
            if name and name ~= "" and name ~= me then names[#names + 1] = name end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local name = addon.Utils:UnitName("party" .. i)
            if name and name ~= "" and name ~= me then names[#names + 1] = name end
        end
    end
    return names
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
-- second, possibly-drifting copy of the raid/party iteration. Display-only --
-- see IsPlayerTheLeaderUnit() below for why the actual gating logic doesn't
-- use this.
function RCPLSync:GetLeaderName()
    return GetGroupLeaderName()
end

-- Whether the local player is the raid/party leader, checked by walking the
-- same raidN/partyN unit tokens as GetGroupLeaderName() but confirming
-- identity with UnitIsUnit(unit, "player") instead of a name-string
-- comparison (#50: a new raid leader was blocked from importing right after
-- a leadership pass). addon.Utils:UnitName() caches its resolved name-realm
-- per literal unit token forever (RCLootCouncil's Utils.lua unitNameLookup),
-- with no invalidation when a roster change reassigns which character sits
-- at that index -- so GetGroupLeaderName()'s UnitName("raidN") call could
-- return a stale cached name for the *previous* occupant of raidN, which
-- then never matches UnitName("player") even though the local player
-- genuinely is the new leader. UnitIsUnit() resolves both sides fresh on
-- every call with no such cache, so it can't drift the same way.
local function IsPlayerTheLeaderUnit()
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if UnitIsGroupLeader(unit) then return UnitIsUnit(unit, "player") end
        end
        return false
    elseif IsInGroup() then
        if UnitIsGroupLeader("player") then return true end
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            if UnitIsGroupLeader(unit) then return UnitIsUnit(unit, "player") end
        end
        return false
    end
    -- Ungrouped: no leader to be blocked by -- the normal pre-raid import workflow.
    return true
end

-- Whether the local player is currently allowed to import. Modules/importFrame.lua
-- uses this to refuse a non-leader's import outright rather than letting them
-- end up looking at priority data nobody else in the raid will ever see
-- (Broadcast() below would refuse to send it anyway).
function RCPLSync:IsLocalPlayerLeader()
    return IsPlayerTheLeaderUnit()
end

-- Sends whatever this client currently has to the raid/party. A no-op for
-- the vast majority of clients (raiders who never ran /rcpl import), since
-- CurrentPayload() returns nil when there's nothing to offer -- and, while
-- actually grouped, a no-op for anyone but the raid/party leader, since
-- OnPrioDataReceived() below only ever applies a leader's data anyway.
--
-- silent suppresses the "Not sent" chat line for the non-leader case --
-- pass true for background/reactive calls (the roster-update resync below,
-- replying to someone else's prio_request) that fire automatically and
-- repeatedly with no user action behind them, so a non-leader with data
-- doesn't get spammed once per roster change all raid. Leave it audible
-- (the default) for a direct user action -- /rcpl import, /rcpl broadcast --
-- where the non-leader who just tried something deserves to know why it
-- didn't propagate, right in their own chat, instead of just silence.
function RCPLSync:Broadcast(reason, silent)
    local payload, playerCount, priorityCount = CurrentPayload()
    if not payload then
        Log.debug("Broadcast skipped (%s): no data to send", tostring(reason))
        return
    end
    if (IsInRaid() or IsInGroup()) and not IsPlayerTheLeaderUnit() then
        local leader = GetGroupLeaderName()
        if leader then
            if not silent then
                print(string.format(
                    "|cFFFFCC00[RCLootCouncil_PriorityLoot]|r Not sent -- only the raid/party leader's priority"
                        .. " data syncs to the group. Ask %s to import, or have raid lead passed to you.",
                    leader
                ))
            end
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

-- Whispers this client's current data straight to one raid/party member,
-- bypassing the wait for the next roster-change resync -- the answer to
-- "someone's status came back Missing/Different, now what". Same leader-only
-- acceptance rule as a group Broadcast (OnPrioDataReceived below still checks
-- sender identity), so pushing from a non-leader still gets silently ignored
-- on their end with the usual "only the leader's data" message -- this
-- function doesn't duplicate that gate, it just reports send failure instead.
function RCPLSync:ForcePush(name)
    local payload, playerCount, priorityCount = CurrentPayload()
    if not payload then
        print("|cFFFFCC00[RCLootCouncil_PriorityLoot]|r Nothing to push -- you have no priority data loaded.")
        return
    end
    if CommsRestrictions:IsRestricted() then
        print(string.format(
            "|cFFFF4444[RCLootCouncil_PriorityLoot]|r NOT sent to %s -- comms are restricted (in an encounter)."
                .. " Try again once combat ends.",
            name
        ))
        Log.debug("ForcePush to %s blocked: comms restricted", name)
        return
    end
    local ok, target = pcall(function() return PlayerData:Get(name) end)
    if not ok or not target then
        print(string.format("|cFFFF4444[RCLootCouncil_PriorityLoot]|r Couldn't resolve %s to push to.", name))
        Log.debug("ForcePush failed to resolve player: %s", tostring(name))
        return
    end
    self:Send(target, COMMAND_DATA, payload)
    print(string.format(
        "|cFF00FF00[RCLootCouncil_PriorityLoot]|r Pushed priority data to %s (%d player(s), %d priority item(s)).",
        name, playerCount, priorityCount
    ))
    Log.debug("Force-pushed prio_data to %s", name)
end

-- Whispers every currently-known non-matching row (Modules/prioSyncStatusFrame.lua
-- tracks the last status check's results) -- the bulk "Force Push All" button.
-- Silently skips a name the frame doesn't have a row for; the frame is the
-- only source of "who's missing/different" this module keeps.
--
-- Checks CommsRestrictions once up front rather than letting ForcePush()'s
-- own per-name check fire once per name -- otherwise a mid-encounter click
-- prints the same "NOT sent" line once per row instead of one line covering
-- the whole batch.
function RCPLSync:ForcePushAll(names)
    if not names or #names == 0 then
        print("|cFF00FF00[RCLootCouncil_PriorityLoot]|r Nobody needs a push -- everyone already matches.")
        return
    end
    if CommsRestrictions:IsRestricted() then
        print(string.format(
            "|cFFFF4444[RCLootCouncil_PriorityLoot]|r NOT sent to %d player(s) -- comms are restricted (in an"
                .. " encounter). Try again once combat ends.",
            #names
        ))
        Log.debug("ForcePushAll blocked: comms restricted (%d name(s))", #names)
        return
    end
    for _, name in ipairs(names) do
        self:ForcePush(name)
    end
end

-- True only while this client is waiting on replies from a check it itself
-- started -- gates OnStatusReplyReceived below so a client that never called
-- StartStatusCheck() (i.e. everyone but whoever clicked "Check Group") just
-- ignores the reply traffic passing through the group channel instead of
-- feeding a status frame it never opened. Reset by FinalizeStatusCheck()
-- after STATUS_TIMEOUT, same shot-lived-window shape as Core.lua's own
-- versionCheckResults.
local statusCheckActive = false
local statusCheckTimer = nil

-- Starts a sync-status check against the current raid/party: sends this
-- client's own payload out on the group channel so every recipient can
-- compare it against what they already have and reply on that same channel
-- (mirrors Core.lua's StartVersionCheck/OnVersionCheckMessage exactly --
-- reply-on-distribution rather than a private whisper back, so this needs no
-- Data.Player resolution for the common case). Modules/prioSyncStatusFrame.lua
-- renders replies live as they arrive. Returns the list of names seeded (so
-- the caller can pre-populate "Waiting..." rows) or nil plus a reason string
-- when the check can't start.
function RCPLSync:StartStatusCheck()
    if not (IsInRaid() or IsInGroup()) then
        return nil, "You must be in a raid or party to check sync status."
    end
    local payload = CurrentPayload()
    if not payload then
        return nil, "You have no priority data loaded to compare against. Run /rcpl import first."
    end
    local names = GetGroupMemberNames()
    statusCheckActive = true
    if statusCheckTimer then self:CancelTimer(statusCheckTimer) end
    statusCheckTimer = self:ScheduleTimer(function()
        statusCheckTimer = nil
        statusCheckActive = false
        if RCPL_SyncStatus_MarkMissing then RCPL_SyncStatus_MarkMissing() end
    end, STATUS_TIMEOUT)
    self:Send("group", COMMAND_STATUS_REQ, payload)
    Log.debug("Sent prio_status_req to group (%d other member(s))", #names)
    return names
end

local function OnStatusRequestReceived(data, sender, _, distri)
    local me = addon.Utils:UnitName("player")
    if sender == me then return end
    local theirPayload = data[1]
    if type(theirPayload) ~= "table" then return end
    if not (distri == "RAID" or distri == "PARTY") then
        Log.debug("Ignoring prio_status_req from %s on unexpected distribution %s", sender, tostring(distri))
        return
    end

    local mine, playerCount, priorityCount = CurrentPayload()
    local status
    if not mine then
        status = "missing"
    elseif DeepEqual(mine, theirPayload) then
        status = "match"
    else
        status = "different"
    end
    RCPLSync:Send("group", COMMAND_STATUS_REPL,
        status, playerCount, priorityCount, type(RCPL_DB) == "table" and RCPL_DB.importedAt or nil)
    Log.debug("Replied prio_status_repl on %s: %s", distri, status)
end

local function OnStatusReplyReceived(data, sender)
    if sender == addon.Utils:UnitName("player") then return end
    if not statusCheckActive then return end
    local status, playerCount, priorityCount, importedAt = data[1], data[2], data[3], data[4]
    if type(status) ~= "string" then return end
    if RCPL_SyncStatus_UpdateRow then
        RCPL_SyncStatus_UpdateRow(sender, status, playerCount, priorityCount, importedAt)
    end
    Log.debug("Received prio_status_repl from %s: %s", sender, tostring(status))
end

-- Only ever applies data sent by the current raid/party leader -- not just
-- when it conflicts with something already stored, but including the very
-- first sync of the night. A raid assist (or anyone else) importing a
-- different string can still save it to their own client, but it never
-- reaches anyone else: Broadcast() above already refuses to send it for a
-- non-leader, and this is the backstop in case it somehow gets sent anyway
-- (e.g. leftover raw AceComm traffic, a modified client). Uses
-- UnitIsGroupLeader() over raid/party unit tokens rather than RCLootCouncil's
-- own council roster, since that roster isn't guaranteed to have propagated
-- to every client yet, especially early in a raid.
--
-- One exception: if the local player has their own data on file from
-- pasting an import string themselves (RCPL_DB.importSource == "local"),
-- a leader's differing broadcast is rejected the same way a non-leader's
-- would be, rather than silently clobbering it -- a player who went to the
-- trouble of importing a string didn't do it just to have it overwritten
-- the moment a group forms. /rcpl reset clears that protection if the
-- player does want to pick up the leader's data instead.
-- Both rejection branches below used to print unconditionally on every
-- received prio_data -- fine for a one-off, but Broadcast() above resends on
-- every roster change (debounced, but still frequent over a raid night), so
-- a client stuck in either rejection state got the same warning reprinted
-- all night long (#confirmed report: a raider with self-imported data
-- spammed once per roster churn after the leader started broadcasting a
-- newer, differing import). Remember the last payload actually warned about
-- per rejection reason and skip the reprint while nothing's changed --
-- mirrors WarnIfEmpty/WarnIfStale's "warn once per streak" pattern, but
-- keyed on payload content (via DeepEqual) rather than a single boolean,
-- since a genuinely new differing payload arriving later is worth telling
-- the player about again, not just the very first one.
local lastWarnedNotLeaderPayload = nil
local lastWarnedLocalDiffPayload = nil

local function OnPrioDataReceived(data, sender)
    local me = addon.Utils:UnitName("player")
    if sender == me then return end
    local payload = data[1]
    if type(payload) ~= "table" then return end

    local current = CurrentPayload()
    local unchanged = current ~= nil and DeepEqual(payload, current)

    -- A duplicate rebroadcast of data already stored is a routine part of
    -- every roster-change resync (Broadcast() above fires on every roster
    -- update) -- apply it as a silent no-op rather than reprinting the same
    -- "synced" line once per roster change all raid long.
    if unchanged then return end

    local leader = GetGroupLeaderName()
    if sender ~= leader then
        if not (lastWarnedNotLeaderPayload and DeepEqual(payload, lastWarnedNotLeaderPayload)) then
            lastWarnedNotLeaderPayload = payload
            print(string.format(
                "|cFFFFCC00[RCLootCouncil_PriorityLoot]|r Ignored priority data from %s -- only the raid/party"
                    .. " leader's data is applied, and %s isn't the leader.",
                sender, sender
            ))
        end
        Log.debug("Rejected prio_data from %s: not raid/party leader (leader=%s)", sender, tostring(leader))
        return
    end

    if type(RCPL_DB) == "table" and RCPL_DB.importSource == "local" then
        if not (lastWarnedLocalDiffPayload and DeepEqual(payload, lastWarnedLocalDiffPayload)) then
            lastWarnedLocalDiffPayload = payload
            print(string.format(
                "|cFFFFCC00[RCLootCouncil_PriorityLoot]|r Ignored differing priority data from %s -- keeping your"
                    .. " own imported data. Run /rcpl reset if you want to accept theirs instead.",
                sender
            ))
        end
        Log.debug("Rejected prio_data from %s: local player has self-imported data", sender)
        return
    end

    lastWarnedNotLeaderPayload = nil
    lastWarnedLocalDiffPayload = nil
    local playerCount, priorityCount = RCPL_Data_SaveImportedData(payload, "sync")
    priorityCount = priorityCount or 0
    print(string.format(
        "|cFF00FF00[RCLootCouncil_PriorityLoot]|r Priority data synced from %s (%d player(s), %d priority item(s)).",
        sender, playerCount, priorityCount
    ))
    Log.debug("Applied prio_data from %s: %d player(s), %d priority item(s)", sender, playerCount, priorityCount)
end

local function OnPrioRequestReceived(_, sender)
    if sender == addon.Utils:UnitName("player") then return end
    RCPLSync:Broadcast("requested by " .. tostring(sender), true)
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

-- Same reset-not-one-shot reasoning as warnedEmpty above: a fresh import or
-- sync during the session un-warns, so a client that goes stale again later
-- (e.g. sits in the group for days without anyone re-importing) can warn
-- again instead of staying silent forever after the first warning.
local warnedStale = false

-- Companion to WarnIfEmpty -- this covers the case where data *is* loaded
-- but hasn't been refreshed in a while, which otherwise gives zero signal
-- that what's on screen might not reflect a since-updated site export (a
-- raid report was mistaken for this exact scenario before the real cause --
-- a display bug unrelated to data freshness -- was found). Only warns at
-- the same "alert" (red) threshold RCPL_Data_ImportAge() uses for the
-- preview window, not the earlier "warn" (yellow) one -- a day-old import is
-- normal between raid nights and not worth a chat interruption for.
function RCPLSync:WarnIfStale()
    local age = RCPL_Data_ImportAge()
    if not age or age < RCPL_Data_StaleAlertSeconds() then
        warnedStale = false
        return
    end
    if warnedStale then return end
    warnedStale = true

    print(string.format(
        "|cFFFFCC00[RCLootCouncil_PriorityLoot]|r Your priority data is %d+ days old (imported %s). If the"
            .. " list has changed since, run /rcpl sync (or ask an officer to /rcpl broadcast) to refresh it.",
        math.floor(age / (24 * 60 * 60)), RCPL_DB.importedAt or "unknown"
    ))
end

function RCPLSync:OnInitialize()
    self.Send = Comms:GetSender(PREFIX)
    Comms:BulkSubscribe(PREFIX, {
        [COMMAND_DATA]        = function(data, sender) OnPrioDataReceived(data, sender) end,
        [COMMAND_REQUEST]     = function(data, sender) OnPrioRequestReceived(data, sender) end,
        [COMMAND_STATUS_REQ]  = function(data, sender, command, distri) OnStatusRequestReceived(data, sender, command, distri) end,
        [COMMAND_STATUS_REPL] = function(data, sender) OnStatusReplyReceived(data, sender) end,
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
        self:Broadcast("roster update", true)
        self:WarnIfEmpty()
        self:WarnIfStale()
    end, ROSTER_DEBOUNCE)
end
