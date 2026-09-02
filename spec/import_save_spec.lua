-- spec/import_save_spec.lua
--
-- Coverage of the SavedVariable mutators in Data/db.lua:
--   RCPL_Data_SaveImportedData(decoded) → playerCount, priorityCount
--   RCPL_Data_ResetData()
--
-- These run after the in-game import frame has decoded base64 + JSON.

local mocks = require "spec.wow_mocks"

describe("RCPL_Data_SaveImportedData", function()
    setup(function()
        mocks.loadAddonSources()
    end)

    before_each(function()
        mocks.resetSavedVars()
        mocks.capturePrint()
    end)

    it("returns 0,0 and prints an error for non-table input", function()
        local p, pri = RCPL_Data_SaveImportedData(nil)
        assert.equals(0, p)
        assert.equals(0, pri)
    end)

    it("returns 0,0 and prints an error when players is missing", function()
        local p, pri = RCPL_Data_SaveImportedData({ priority = {} })
        assert.equals(0, p)
        assert.equals(0, pri)
    end)

    it("stores valid players and counts them", function()
        local p, pri = RCPL_Data_SaveImportedData({
            players = {
                ["Alice-Realm"] = { helm = { bis = { 1, 2, 3 } } },
                ["Bob-Realm"]   = { helm = { bis = { 1, 2, 3 } } },
            },
        })
        assert.equals(2, p)
        assert.equals(0, pri)
        assert.is_table(_G.RCPL_DB.players["Alice-Realm"])
        assert.is_table(_G.RCPL_DB.players["Bob-Realm"])
    end)

    it("stores priority lists alongside players", function()
        -- priority[itemID] is a per-track object (#335), stored as-is --
        -- SaveImportedData doesn't need to know about "H"/"M" itself.
        local p, pri = RCPL_Data_SaveImportedData({
            players = {
                ["Alice-Realm"] = { helm = { bis = { 1 } } },
            },
            priority = {
                ["100"] = { H = { "Alice-Realm", "Bob-Realm" } },
                ["200"] = { H = { "Carol-Realm" }, M = { "Carol-Realm" } },
            },
        })
        assert.equals(1, p)
        assert.equals(2, pri)
        assert.same({ H = { "Alice-Realm", "Bob-Realm" } }, _G.RCPL_DB.priority["100"])
    end)

    it("skips entries with non-string player keys or non-table slots", function()
        local p = RCPL_Data_SaveImportedData({
            players = {
                ["Valid-Realm"] = { helm = { bis = { 1 } } },
                [42]            = { helm = { bis = { 1 } } },  -- non-string key, skipped
                ["Bad-Realm"]   = "not a table",                -- non-table value, skipped
            },
        })
        assert.equals(1, p)
        assert.is_nil(_G.RCPL_DB.players[42])
        assert.is_nil(_G.RCPL_DB.players["Bad-Realm"])
    end)

    -- #859 split the web app's export string by track (Hero/Myth) to keep
    -- each paste small enough that WoW doesn't stall on it -- a "local"
    -- import can now be just one track's half of the full dataset, so it
    -- must merge into whatever's already stored instead of wiping it.
    it("merges a local import into prior state instead of wiping it", function()
        _G.RCPL_DB = {
            players  = { ["ExistingPlayer-Realm"] = { helm = { bis = { 999 } } } },
            priority = { ["99"] = { H = { "ExistingPlayer-Realm" } } },
        }
        RCPL_Data_SaveImportedData({
            players = { ["NewPlayer-Realm"] = { helm = { bis = { 1 } } } },
        }, "local")
        assert.is_table(_G.RCPL_DB.players["ExistingPlayer-Realm"])
        assert.same({ H = { "ExistingPlayer-Realm" } }, _G.RCPL_DB.priority["99"])
        assert.is_table(_G.RCPL_DB.players["NewPlayer-Realm"])
    end)

    it("merges an item's other-track key instead of replacing the whole entry (Hero then Myth)", function()
        RCPL_Data_SaveImportedData({
            players  = {},
            priority = { ["100"] = { H = { "Alice-Realm" }, H_status = {} } },
        }, "local")
        RCPL_Data_SaveImportedData({
            players  = {},
            priority = { ["100"] = { M = { "Bob-Realm" }, M_status = {} } },
        }, "local")
        assert.same(
            { H = { "Alice-Realm" }, H_status = {}, M = { "Bob-Realm" }, M_status = {} },
            _G.RCPL_DB.priority["100"]
        )
    end)

    it("re-importing the same track for an item overwrites just that track's keys", function()
        RCPL_Data_SaveImportedData({
            players  = {},
            priority = { ["100"] = { H = { "Alice-Realm" }, M = { "Bob-Realm" } } },
        }, "local")
        RCPL_Data_SaveImportedData({
            players  = {},
            priority = { ["100"] = { H = { "Carol-Realm" } } },
        }, "local")
        assert.same({ H = { "Carol-Realm" }, M = { "Bob-Realm" } }, _G.RCPL_DB.priority["100"])
    end)

    -- A sync payload (Modules/prioSync.lua's Broadcast()) is always a full
    -- rebuild of the sender's entire current dataset, never a partial
    -- track slice, so applying it wipes and replaces rather than merging --
    -- otherwise a receiving client would keep stale entries the sender no
    -- longer has.
    it("wipes prior state when the import source is sync", function()
        _G.RCPL_DB = {
            players  = { ["StalePlayer-Realm"] = { helm = { bis = { 999 } } } },
            priority = { ["99"] = { H = { "StalePlayer-Realm" } } },
        }
        RCPL_Data_SaveImportedData({
            players = { ["NewPlayer-Realm"] = { helm = { bis = { 1 } } } },
        }, "sync")
        assert.is_nil(_G.RCPL_DB.players["StalePlayer-Realm"])
        assert.is_nil(_G.RCPL_DB.priority["99"])
        assert.is_table(_G.RCPL_DB.players["NewPlayer-Realm"])
    end)

    it("stamps importedAt with current date", function()
        RCPL_Data_SaveImportedData({
            players = { ["Alice-Realm"] = { helm = { bis = { 1 } } } },
        })
        assert.is_string(_G.RCPL_DB.importedAt)
        assert.matches("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d$", _G.RCPL_DB.importedAt)
    end)

    it("stores statusLabels when the import includes them", function()
        RCPL_Data_SaveImportedData({
            players = { ["Alice-Realm"] = { helm = { bis = { 1 } } } },
            statusLabels = { bis = "BiS", good = "2nd Choice", ok = "Sidegrade" },
        })
        assert.same({ bis = "BiS", good = "2nd Choice", ok = "Sidegrade" }, _G.RCPL_DB.statusLabels)
    end)

    it("leaves a prior statusLabels value alone when the new import doesn't include one", function()
        _G.RCPL_DB = { statusLabels = { bis = "BiS" } }
        RCPL_Data_SaveImportedData({
            players = { ["Alice-Realm"] = { helm = { bis = { 1 } } } },
        })
        assert.same({ bis = "BiS" }, _G.RCPL_DB.statusLabels)
    end)

    it("stamps importedAtEpoch so RCPL_Data_ImportAge can compute staleness", function()
        RCPL_Data_SaveImportedData({
            players = { ["Alice-Realm"] = { helm = { bis = { 1 } } } },
        })
        assert.is_number(_G.RCPL_DB.importedAtEpoch)
        local age = RCPL_Data_ImportAge()
        assert.is_number(age)
        assert.is_true(age >= 0 and age < 5)  -- just imported, in a fast test
    end)
end)

describe("RCPL_Data_ImportAge", function()
    setup(function()
        mocks.loadAddonSources()
    end)

    before_each(function()
        mocks.resetSavedVars()
    end)

    it("returns nil when nothing has ever been imported", function()
        local age, color = RCPL_Data_ImportAge()
        assert.is_nil(age)
        assert.is_nil(color)
    end)

    it("returns nil for data saved before importedAtEpoch existed", function()
        _G.RCPL_DB = { importedAt = "2026-01-01 00:00" }
        local age, color = RCPL_Data_ImportAge()
        assert.is_nil(age)
        assert.is_nil(color)
    end)

    it("colors a fresh import green", function()
        _G.RCPL_DB = { importedAtEpoch = os.time() }
        local age, color = RCPL_Data_ImportAge()
        assert.is_true(age < 60)
        assert.equals(0.0, color.r)
        assert.equals(1.0, color.g)
    end)

    it("colors a 2-day-old import yellow (past the warn threshold)", function()
        _G.RCPL_DB = { importedAtEpoch = os.time() - (2 * 24 * 60 * 60) }
        local _, color = RCPL_Data_ImportAge()
        assert.equals(1.0, color.r)
        assert.equals(1.0, color.g)
        assert.equals(0.0, color.b)
    end)

    it("colors a 4-day-old import orange (past the alert threshold)", function()
        _G.RCPL_DB = { importedAtEpoch = os.time() - (4 * 24 * 60 * 60) }
        local age, color = RCPL_Data_ImportAge()
        assert.equals(1.0, color.r)
        assert.equals(0.5, color.g)
        assert.equals(0.0, color.b)
        assert.is_true(age >= RCPL_Data_StaleAlertSeconds())
    end)
end)

describe("RCPL_Data_ResetData", function()
    setup(function()
        mocks.loadAddonSources()
    end)

    it("wipes players, priority, and importedAt", function()
        _G.RCPL_DB = {
            players    = { ["Alice-Realm"] = { helm = { bis = { 1 } } } },
            priority   = { ["1"] = { "Alice-Realm" } },
            importedAt = "2026-04-30 12:00",
        }
        RCPL_Data_ResetData()
        assert.same({}, _G.RCPL_DB.players)
        assert.same({}, _G.RCPL_DB.priority)
        assert.is_nil(_G.RCPL_DB.importedAt)
    end)

    it("is a no-op when SavedVariable is missing", function()
        _G.RCPL_DB = nil
        assert.has_no.errors(function()
            RCPL_Data_ResetData()
        end)
    end)
end)
