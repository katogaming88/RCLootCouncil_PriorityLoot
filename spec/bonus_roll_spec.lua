-- spec/bonus_roll_spec.lua
--
-- Coverage for RCPL_Data_HasBonusRolled (Data/db.lua) -- the pure lookup
-- Modules/bonusRollFlag.lua's voting-frame column calls to flag a candidate
-- who already used their weekly Bonus Roll on the current boss.
--
-- `nonTradeables` mirrors the shape of RCLootCouncil's own addon.nonTradeables
-- list ({link, reason, owner} entries), which is what the real column reads
-- at runtime -- this spec builds that shape by hand rather than mocking
-- RCLootCouncil's comm layer.

local mocks = require "spec.wow_mocks"

describe("RCPL_Data_HasBonusRolled", function()
    setup(function()
        mocks.loadAddonSources()
    end)

    it("returns false for an empty nonTradeables list", function()
        assert.is_false(RCPL_Data_HasBonusRolled({}, "Alice-Realm"))
    end)

    it("returns false when nonTradeables is not a table", function()
        assert.is_false(RCPL_Data_HasBonusRolled(nil, "Alice-Realm"))
    end)

    it("returns false when playerName is not a string", function()
        local nonTradeables = { { link = "item:1", reason = "bonus_roll", owner = "Alice-Realm" } }
        assert.is_false(RCPL_Data_HasBonusRolled(nonTradeables, nil))
    end)

    it("returns true for an exact owner match", function()
        local nonTradeables = { { link = "item:1", reason = "bonus_roll", owner = "Alice-Realm" } }
        assert.is_true(RCPL_Data_HasBonusRolled(nonTradeables, "Alice-Realm"))
    end)

    it("matches across a realm suffix on either side", function()
        local nonTradeables = { { link = "item:1", reason = "bonus_roll", owner = "Alice-Realm" } }
        assert.is_true(RCPL_Data_HasBonusRolled(nonTradeables, "Alice"))

        local nonTradeablesBare = { { link = "item:1", reason = "bonus_roll", owner = "Alice" } }
        assert.is_true(RCPL_Data_HasBonusRolled(nonTradeablesBare, "Alice-Realm"))
    end)

    it("ignores non-bonus_roll entries (not_tradeable, rejected_trade)", function()
        local nonTradeables = {
            { link = "item:1", reason = "not_tradeable", owner = "Alice-Realm" },
            { link = "item:2", reason = "rejected_trade", owner = "Alice-Realm" },
        }
        assert.is_false(RCPL_Data_HasBonusRolled(nonTradeables, "Alice-Realm"))
    end)

    it("does not match a different player", function()
        local nonTradeables = { { link = "item:1", reason = "bonus_roll", owner = "Bob-Realm" } }
        assert.is_false(RCPL_Data_HasBonusRolled(nonTradeables, "Alice-Realm"))
    end)

    it("ignores a malformed entry (missing owner) without erroring", function()
        local nonTradeables = { { link = "item:1", reason = "bonus_roll" } }
        assert.is_false(RCPL_Data_HasBonusRolled(nonTradeables, "Alice-Realm"))
    end)
end)
