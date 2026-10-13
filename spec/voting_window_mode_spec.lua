-- spec/voting_window_mode_spec.lua
--
-- Coverage for RCPL_Data_VotingWindowMode (Data/db.lua): which voting window
-- opens for each setting, and the fallback to RCLootCouncil's own window on
-- an RCLootCouncil version we haven't tested.

local mocks = require "spec.wow_mocks"

describe("RCPL_Data_VotingWindowMode", function()
    setup(function()
        mocks.loadAddonSources()
    end)

    it("defaults to replace when nothing is saved", function()
        assert.are.equal("replace", RCPL_Data_VotingWindowMode(nil, "3.23.3"))
    end)

    it("keeps alongside and off", function()
        assert.are.equal("alongside", RCPL_Data_VotingWindowMode("alongside", "3.23.3"))
        assert.are.equal("off", RCPL_Data_VotingWindowMode("off", "3.23.3"))
    end)

    it("treats an unknown setting as replace", function()
        assert.are.equal("replace", RCPL_Data_VotingWindowMode("bogus", "3.23.0"))
    end)

    it("falls back to off with a reason on an untested version", function()
        local mode, reason = RCPL_Data_VotingWindowMode("replace", "3.99.0")
        assert.are.equal("off", mode)
        assert.truthy(reason:find("3.99.0", 1, true))
    end)

    it("falls back to off when the version is missing", function()
        local mode, reason = RCPL_Data_VotingWindowMode("alongside", nil)
        assert.are.equal("off", mode)
        assert.truthy(reason)
    end)

    it("gives no reason when off was chosen", function()
        local mode, reason = RCPL_Data_VotingWindowMode("off", "9.9.9")
        assert.are.equal("off", mode)
        assert.is_nil(reason)
    end)
end)
