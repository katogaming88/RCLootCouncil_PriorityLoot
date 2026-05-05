-- spec/version_spec.lua
--
-- Coverage of the pure functions in Modules/version.lua.  These are the
-- actual decision-making surface; the AceComm/AceEvent wrappers in the
-- module are thin shims around them and are smoke-tested in-game.
--
-- The pure functions are loaded by setting up a tiny LibStub stub so the
-- module's `:NewModule(...)` call returns a stand-in object that captures
-- the registered methods.  No real Ace3 libs are pulled in.

require "spec.wow_mocks"

-- Build a minimal stand-in for the AceAddon parent module so version.lua's
-- module-load runs without a real WoW or RCLootCouncil environment.
local function loadVersionModule()
    -- Reset the captured globals.
    package.loaded["Modules.version"] = nil

    local fakeSubModule = {}
    function fakeSubModule:RegisterComm() end
    function fakeSubModule:RegisterEvent() end
    function fakeSubModule:ScheduleTimer() end
    function fakeSubModule:SendCommMessage() end

    local fakeParent = {}
    function fakeParent:NewModule(_, ...)
        return fakeSubModule
    end

    local fakeAddonHandle = {}
    function fakeAddonHandle.GetModule() return fakeParent end

    local fakeAceAddon = {}
    function fakeAceAddon.GetAddon() return fakeAddonHandle end

    _G.LibStub = function(_) return fakeAceAddon end
    _G.GetTime = function() return 0 end
    _G.C_AddOns = { GetAddOnMetadata = function() return "0.1.4" end }
    _G.IsInRaid = function() return false end
    _G.UnitIsGroupLeader = function() return false end

    dofile("Modules/version.lua")

    -- The module exposed pure functions on `_pure` for tests.
    return fakeSubModule._pure
end

describe("Modules/version.lua pure functions", function()
    local pure
    setup(function()
        pure = loadVersionModule()
    end)

    -- ── ParseSemver ──────────────────────────────────────────────────────────

    describe("ParseSemver", function()
        it("parses valid major.minor.patch", function()
            local a, b, c = pure.ParseSemver("0.1.4")
            assert.equals(0, a); assert.equals(1, b); assert.equals(4, c)
        end)

        it("returns nil for non-string input", function()
            assert.is_nil(pure.ParseSemver(nil))
            assert.is_nil(pure.ParseSemver(42))
            assert.is_nil(pure.ParseSemver({}))
        end)

        it("returns nil for malformed strings", function()
            assert.is_nil(pure.ParseSemver(""))
            assert.is_nil(pure.ParseSemver("0.1"))
            assert.is_nil(pure.ParseSemver("0.1.4-dev.3"))
            assert.is_nil(pure.ParseSemver("v0.1.4"))
            assert.is_nil(pure.ParseSemver("a.b.c"))
        end)
    end)

    -- ── IsNewer ──────────────────────────────────────────────────────────────

    describe("IsNewer", function()
        it("returns false for equal versions", function()
            assert.is_false(pure.IsNewer("0.1.4", "0.1.4"))
        end)

        it("detects newer major", function()
            assert.is_true(pure.IsNewer("0.9.9", "1.0.0"))
            assert.is_false(pure.IsNewer("1.0.0", "0.9.9"))
        end)

        it("detects newer minor", function()
            assert.is_true(pure.IsNewer("0.1.9", "0.2.0"))
            assert.is_false(pure.IsNewer("0.2.0", "0.1.9"))
        end)

        it("detects newer patch", function()
            assert.is_true(pure.IsNewer("0.1.3", "0.1.4"))
            assert.is_false(pure.IsNewer("0.1.4", "0.1.3"))
        end)

        it("compares numerically not lexicographically", function()
            -- Lexicographic would say "0.1.10" < "0.1.2"; numeric says newer.
            assert.is_true(pure.IsNewer("0.1.2", "0.1.10"))
            assert.is_false(pure.IsNewer("0.1.10", "0.1.2"))
        end)

        it("returns false when either argument is malformed", function()
            assert.is_false(pure.IsNewer("0.1.4", "garbage"))
            assert.is_false(pure.IsNewer("garbage", "0.1.4"))
            assert.is_false(pure.IsNewer(nil, "0.1.4"))
        end)
    end)

    -- ── HighestVersion ───────────────────────────────────────────────────────

    describe("HighestVersion", function()
        it("returns self when no peers", function()
            assert.equals("0.1.4", pure.HighestVersion({}, "0.1.4"))
        end)

        it("returns highest across peers and self", function()
            local map = { ["A-Realm"] = "0.1.3", ["B-Realm"] = "0.1.5" }
            assert.equals("0.1.5", pure.HighestVersion(map, "0.1.4"))
        end)

        it("handles ties stably (returns one of the equals)", function()
            local map = { ["A-Realm"] = "0.1.4" }
            assert.equals("0.1.4", pure.HighestVersion(map, "0.1.4"))
        end)

        it("ignores malformed peer entries", function()
            local map = { ["A-Realm"] = "garbage", ["B-Realm"] = "0.1.5" }
            assert.equals("0.1.5", pure.HighestVersion(map, "0.1.4"))
        end)

        it("returns nil when self is malformed and no valid peers", function()
            assert.is_nil(pure.HighestVersion({ x = "garbage" }, "garbage"))
        end)
    end)

    -- ── CollectOutdated + FingerprintOutdated ────────────────────────────────

    describe("CollectOutdated", function()
        it("returns peers whose version is below highest, sorted by name", function()
            local map = {
                ["Charlie-Realm"] = "0.1.3",
                ["Alice-Realm"]   = "0.1.5",
                ["Bob-Realm"]     = "0.1.4",
            }
            local out = pure.CollectOutdated(map, "0.1.5")
            assert.equals(2, #out)
            assert.equals("Bob-Realm", out[1].name)
            assert.equals("0.1.4", out[1].version)
            assert.equals("Charlie-Realm", out[2].name)
        end)

        it("returns empty when everyone is at highest", function()
            local map = { ["A-Realm"] = "0.1.5", ["B-Realm"] = "0.1.5" }
            local out = pure.CollectOutdated(map, "0.1.5")
            assert.equals(0, #out)
        end)

        it("ignores malformed peer versions", function()
            local map = { ["A-Realm"] = "garbage", ["B-Realm"] = "0.1.4" }
            local out = pure.CollectOutdated(map, "0.1.5")
            assert.equals(1, #out)
            assert.equals("B-Realm", out[1].name)
        end)
    end)

    describe("FingerprintOutdated", function()
        it("produces order-independent fingerprint via sorted CollectOutdated input", function()
            local map1 = { ["A-Realm"] = "0.1.3", ["B-Realm"] = "0.1.4" }
            local map2 = { ["B-Realm"] = "0.1.4", ["A-Realm"] = "0.1.3" }
            local fp1 = pure.FingerprintOutdated(pure.CollectOutdated(map1, "0.1.5"))
            local fp2 = pure.FingerprintOutdated(pure.CollectOutdated(map2, "0.1.5"))
            assert.equals(fp1, fp2)
        end)

        it("differs when version content differs", function()
            local fp1 = pure.FingerprintOutdated({ { name = "A", version = "0.1.3" } })
            local fp2 = pure.FingerprintOutdated({ { name = "A", version = "0.1.4" } })
            assert.are_not.equals(fp1, fp2)
        end)
    end)

    -- ── EvaluatePoll ─────────────────────────────────────────────────────────

    describe("EvaluatePoll", function()
        it("warns local user when behind highest peer", function()
            local r = pure.EvaluatePoll({
                localVersion    = "0.1.3",
                peerVersions    = { ["A-Realm"] = "0.1.5" },
                isLeader        = false,
                lastWarnedAt    = nil,
                lastFingerprint = nil,
            })
            assert.is_string(r.selfWarning)
            assert.matches("0.1.5", r.selfWarning)
            assert.matches("0.1.3", r.selfWarning)
            assert.equals("0.1.5", r.newWarnedAt)
        end)

        it("does not warn when at or above highest peer", function()
            local r = pure.EvaluatePoll({
                localVersion = "0.1.5",
                peerVersions = { ["A-Realm"] = "0.1.4" },
                isLeader     = false,
            })
            assert.is_nil(r.selfWarning)
        end)

        it("suppresses self-warning when same gap as last warn", function()
            local r = pure.EvaluatePoll({
                localVersion    = "0.1.3",
                peerVersions    = { ["A-Realm"] = "0.1.5" },
                isLeader        = false,
                lastWarnedAt    = "0.1.5",
                lastFingerprint = nil,
            })
            assert.is_nil(r.selfWarning)
            assert.equals("0.1.5", r.newWarnedAt)
        end)

        it("re-warns when highest changes upward", function()
            local r = pure.EvaluatePoll({
                localVersion    = "0.1.3",
                peerVersions    = { ["A-Realm"] = "0.1.6" },
                isLeader        = false,
                lastWarnedAt    = "0.1.5",
                lastFingerprint = nil,
            })
            assert.is_string(r.selfWarning)
            assert.matches("0.1.6", r.selfWarning)
            assert.equals("0.1.6", r.newWarnedAt)
        end)

        it("returns leaderSummary only when isLeader and outdated peers exist", function()
            local r = pure.EvaluatePoll({
                localVersion = "0.1.5",
                peerVersions = { ["A-Realm"] = "0.1.3", ["B-Realm"] = "0.1.5" },
                isLeader     = true,
            })
            assert.is_string(r.leaderSummary)
            assert.matches("A-Realm", r.leaderSummary)
            assert.matches("0.1.3", r.leaderSummary)
            assert.matches("0.1.5", r.leaderSummary)
        end)

        it("does not produce leader summary when not leader", function()
            local r = pure.EvaluatePoll({
                localVersion = "0.1.5",
                peerVersions = { ["A-Realm"] = "0.1.3" },
                isLeader     = false,
            })
            assert.is_nil(r.leaderSummary)
        end)

        it("suppresses leader summary when peer set unchanged", function()
            local map = { ["A-Realm"] = "0.1.3" }
            local first = pure.EvaluatePoll({
                localVersion    = "0.1.5",
                peerVersions    = map,
                isLeader        = true,
                lastFingerprint = nil,
            })
            local second = pure.EvaluatePoll({
                localVersion    = "0.1.5",
                peerVersions    = map,
                isLeader        = true,
                lastFingerprint = first.newFingerprint,
            })
            assert.is_string(first.leaderSummary)
            assert.is_nil(second.leaderSummary)
        end)

        it("re-emits leader summary when outdated set changes", function()
            local first = pure.EvaluatePoll({
                localVersion    = "0.1.5",
                peerVersions    = { ["A-Realm"] = "0.1.3" },
                isLeader        = true,
            })
            local second = pure.EvaluatePoll({
                localVersion    = "0.1.5",
                peerVersions    = { ["A-Realm"] = "0.1.3", ["B-Realm"] = "0.1.4" },
                isLeader        = true,
                lastFingerprint = first.newFingerprint,
            })
            assert.is_string(second.leaderSummary)
            assert.matches("B-Realm", second.leaderSummary)
        end)

        it("no-ops when local version is malformed", function()
            local r = pure.EvaluatePoll({
                localVersion = nil,
                peerVersions = { ["A-Realm"] = "0.1.5" },
            })
            assert.is_nil(r.selfWarning)
            assert.is_nil(r.leaderSummary)
        end)
    end)
end)
