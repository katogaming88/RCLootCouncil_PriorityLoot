-- Modules\version.lua
--
-- Raid-scoped version check. On READY_CHECK in a raid, every PriorityLoot
-- user broadcasts their addon version on the RAID channel. After a short
-- collection window each user warns themselves if they are behind, and the
-- raid leader additionally sees a one-line summary of who in the raid is
-- outdated.
--
-- This is a complementary signal to the guild-channel login broadcast.
-- That signal catches guildmates pre-raid; this one covers non-guild raid
-- composition (PUGs, cross-guild rosters) and gives the raid leader
-- visibility into who has not updated.

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCLPAddon = addon:GetModule("RCLootCouncil_PriorityLoot")
local RCLPVersion = RCLPAddon:NewModule(
    "RCLPVersionCheck", "AceComm-3.0", "AceEvent-3.0", "AceTimer-3.0"
)

local COMM_PREFIX     = "RCLPL_VC"
local READY_CHECK_DEBOUNCE_SEC = 5
local BROADCAST_JITTER_BASE    = 0.5
local BROADCAST_JITTER_RANGE   = 1.0
local EVALUATE_AFTER_SEC       = 4.0
local SEMVER_PATTERN           = "^(%d+)%.(%d+)%.(%d+)$"

-- ── Pure functions (test surface) ────────────────────────────────────────────

local function ParseSemver(v)
    if type(v) ~= "string" then return nil end
    local a, b, c = v:match(SEMVER_PATTERN)
    if not a then return nil end
    return tonumber(a), tonumber(b), tonumber(c)
end

local function IsNewer(current, other)
    local c1, c2, c3 = ParseSemver(current)
    local o1, o2, o3 = ParseSemver(other)
    if not (c1 and o1) then return false end
    if o1 ~= c1 then return o1 > c1 end
    if o2 ~= c2 then return o2 > c2 end
    return o3 > c3
end

local function HighestVersion(map, selfVersion)
    local highest = nil
    if ParseSemver(selfVersion) then highest = selfVersion end
    for _, v in pairs(map or {}) do
        if ParseSemver(v) and (highest == nil or IsNewer(highest, v)) then
            highest = v
        end
    end
    return highest
end

local function CollectOutdated(peerVersions, highest)
    local outdated = {}
    for name, v in pairs(peerVersions or {}) do
        if ParseSemver(v) and IsNewer(v, highest) then
            outdated[#outdated + 1] = { name = name, version = v }
        end
    end
    table.sort(outdated, function(a, b) return a.name < b.name end)
    return outdated
end

local function FingerprintOutdated(outdated)
    local parts = {}
    for i, entry in ipairs(outdated or {}) do
        parts[i] = entry.name .. "=" .. entry.version
    end
    return table.concat(parts, ",")
end

local function FormatLeaderSummary(outdated, highest)
    local parts = {}
    for i, entry in ipairs(outdated) do
        parts[i] = entry.name .. " (" .. entry.version .. ")"
    end
    return string.format(
        "|cFFFF8000[RCLootCouncil_PriorityLoot]|r Outdated in raid: %s. Latest seen: %s.",
        table.concat(parts, ", "), highest
    )
end

local function FormatSelfWarning(localVersion, highest)
    return string.format(
        "|cFFFF8000[RCLootCouncil_PriorityLoot]|r Update available: %s (you have %s).",
        highest, localVersion
    )
end

local function EvaluatePoll(args)
    local localVersion  = args.localVersion
    local peerVersions  = args.peerVersions or {}
    local isLeader      = args.isLeader
    local lastWarnedAt  = args.lastWarnedAt
    local lastFingerprint = args.lastFingerprint

    local result = {
        selfWarning      = nil,
        leaderSummary    = nil,
        newWarnedAt      = lastWarnedAt,
        newFingerprint   = lastFingerprint,
    }

    if not ParseSemver(localVersion) then return result end

    local highest = HighestVersion(peerVersions, localVersion)
    if not highest then return result end

    if IsNewer(localVersion, highest) and highest ~= lastWarnedAt then
        result.selfWarning = FormatSelfWarning(localVersion, highest)
        result.newWarnedAt = highest
    end

    if isLeader then
        local outdated = CollectOutdated(peerVersions, highest)
        if #outdated > 0 then
            local fp = FingerprintOutdated(outdated)
            if fp ~= lastFingerprint then
                result.leaderSummary  = FormatLeaderSummary(outdated, highest)
                result.newFingerprint = fp
            end
        else
            result.newFingerprint = ""
        end
    end

    return result
end

-- Expose pure functions for tests. Production code calls these via the
-- file-locals above; the table is read-only intent (Lua can't enforce).
RCLPVersion._pure = {
    ParseSemver        = ParseSemver,
    IsNewer            = IsNewer,
    HighestVersion     = HighestVersion,
    CollectOutdated    = CollectOutdated,
    FingerprintOutdated = FingerprintOutdated,
    FormatLeaderSummary = FormatLeaderSummary,
    FormatSelfWarning  = FormatSelfWarning,
    EvaluatePoll       = EvaluatePoll,
}

-- ── Module state (session-only) ──────────────────────────────────────────────

local state = {
    localVersion        = nil,
    peerVersions        = {},
    pollStartedAt       = 0,
    lastWarnedAt        = nil,
    lastFingerprint     = nil,
    evaluateScheduled   = false,
}

-- ── Module lifecycle ─────────────────────────────────────────────────────────

function RCLPVersion:OnInitialize()
    local v = nil
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        v = C_AddOns.GetAddOnMetadata("RCLootCouncil_PriorityLoot", "Version")
    end
    state.localVersion = v
    -- Seed math.random so per-reload jitter is not identical across raid members.
    math.randomseed(math.floor((GetTime() or 0) * 1000) + 1)
    self:RegisterComm(COMM_PREFIX, "OnVersionMessage")
    self:RegisterEvent("READY_CHECK", "OnReadyCheck")
end

-- ── Event handlers ───────────────────────────────────────────────────────────

function RCLPVersion:OnReadyCheck()
    if not IsInRaid() then return end
    if not state.localVersion then return end

    local now = GetTime() or 0
    if now - state.pollStartedAt < READY_CHECK_DEBOUNCE_SEC then return end
    state.pollStartedAt = now
    state.peerVersions = {}

    local jitter = BROADCAST_JITTER_BASE + math.random() * BROADCAST_JITTER_RANGE
    self:ScheduleTimer("BroadcastVersion", jitter)

    if not state.evaluateScheduled then
        state.evaluateScheduled = true
        self:ScheduleTimer("EvaluateAndPrint", EVALUATE_AFTER_SEC)
    end
end

function RCLPVersion:BroadcastVersion()
    if not IsInRaid() then return end
    if not state.localVersion then return end
    self:SendCommMessage(COMM_PREFIX, state.localVersion, "RAID")
end

function RCLPVersion:OnVersionMessage(_, message, distribution, sender)
    if distribution ~= "RAID" then return end
    if not ParseSemver(message) then return end
    state.peerVersions[sender] = message
end

function RCLPVersion:EvaluateAndPrint()
    state.evaluateScheduled = false

    local result = EvaluatePoll({
        localVersion    = state.localVersion,
        peerVersions    = state.peerVersions,
        isLeader        = UnitIsGroupLeader and UnitIsGroupLeader("player") or false,
        lastWarnedAt    = state.lastWarnedAt,
        lastFingerprint = state.lastFingerprint,
    })

    if result.selfWarning then print(result.selfWarning) end
    if result.leaderSummary then print(result.leaderSummary) end

    state.lastWarnedAt    = result.newWarnedAt
    state.lastFingerprint = result.newFingerprint
end

-- Test hook: lets specs reset internal state between describes.
function RCLPVersion:_reset()
    state.localVersion      = nil
    state.peerVersions      = {}
    state.pollStartedAt     = 0
    state.lastWarnedAt      = nil
    state.lastFingerprint   = nil
    state.evaluateScheduled = false
end
