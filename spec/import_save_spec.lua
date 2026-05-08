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
        assert.is_table(_G.RCLPriorityDB.players["Alice-Realm"])
        assert.is_table(_G.RCLPriorityDB.players["Bob-Realm"])
    end)

    it("stores priority lists alongside players", function()
        local p, pri = RCPL_Data_SaveImportedData({
            players = {
                ["Alice-Realm"] = { helm = { bis = { 1 } } },
            },
            priority = {
                ["100"] = { "Alice-Realm", "Bob-Realm" },
                ["200"] = { "Carol-Realm" },
            },
        })
        assert.equals(1, p)
        assert.equals(2, pri)
        assert.same({ "Alice-Realm", "Bob-Realm" }, _G.RCLPriorityDB.priority["100"])
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
        assert.is_nil(_G.RCLPriorityDB.players[42])
        assert.is_nil(_G.RCLPriorityDB.players["Bad-Realm"])
    end)

    it("wipes prior state on each import (current behaviour)", function()
        _G.RCLPriorityDB = {
            players  = { ["StalePlayer-Realm"] = { helm = { bis = { 999 } } } },
            priority = { ["99"] = { "StalePlayer-Realm" } },
        }
        RCPL_Data_SaveImportedData({
            players = { ["NewPlayer-Realm"] = { helm = { bis = { 1 } } } },
        })
        assert.is_nil(_G.RCLPriorityDB.players["StalePlayer-Realm"])
        assert.is_nil(_G.RCLPriorityDB.priority["99"])
        assert.is_table(_G.RCLPriorityDB.players["NewPlayer-Realm"])
    end)

    it("stamps importedAt with current date", function()
        RCPL_Data_SaveImportedData({
            players = { ["Alice-Realm"] = { helm = { bis = { 1 } } } },
        })
        assert.is_string(_G.RCLPriorityDB.importedAt)
        assert.matches("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d$", _G.RCLPriorityDB.importedAt)
    end)
end)

describe("RCPL_Data_ResetData", function()
    setup(function()
        mocks.loadAddonSources()
    end)

    it("wipes players, priority, and importedAt", function()
        _G.RCLPriorityDB = {
            players    = { ["Alice-Realm"] = { helm = { bis = { 1 } } } },
            priority   = { ["1"] = { "Alice-Realm" } },
            importedAt = "2026-04-30 12:00",
        }
        RCPL_Data_ResetData()
        assert.same({}, _G.RCLPriorityDB.players)
        assert.same({}, _G.RCLPriorityDB.priority)
        assert.is_nil(_G.RCLPriorityDB.importedAt)
    end)

    it("is a no-op when SavedVariable is missing", function()
        _G.RCLPriorityDB = nil
        assert.has_no.errors(function()
            RCPL_Data_ResetData()
        end)
    end)
end)
