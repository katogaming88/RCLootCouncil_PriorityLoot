-- spec/data_db_spec.lua
--
-- Exhaustive coverage of RCPL_Data_GetPlayerPriority - the central
-- resolver used by both votingFrame.lua and lootFrame.lua.
--
-- The resolver lives in Data/db.lua and walks two layers of saved data:
--   1. Item-centric  RCPL_DB.priority[itemID]   → ranked Name-Realm list
--   2. Player-centric RCPL_DB.players[name][slot].bis[]
--
-- Layer 1 wins when present, even if the matching player is absent
-- (returns N/A with no fallback to layer 2).
--
-- Secondary slots (cloak / wrist / waist / feet) intentionally short-circuit
-- to a "see wowaudit wishlist" message regardless of saved data.

local mocks = require "spec.wow_mocks"

describe("RCPL_Data_GetPlayerPriority", function()
    setup(function()
        mocks.loadAddonSources()
    end)

    before_each(function()
        mocks.resetSavedVars()
        _G.RCPL_DB = { players = {}, priority = {} }
    end)

    -- ── Edge cases: no data ──────────────────────────────────────────────────

    it("returns N/A grey when SavedVariable is absent entirely", function()
        _G.RCPL_DB = nil
        local text, color = RCPL_Data_GetPlayerPriority("Alice-Realm", 12345, "INVTYPE_HEAD")
        assert.equals("N/A", text)
        assert.equals(0.6, color.r)  -- grey
    end)

    it("returns N/A grey when playerName is not a string", function()
        local text = RCPL_Data_GetPlayerPriority(nil, 12345, "INVTYPE_HEAD")
        assert.equals("N/A", text)
    end)

    it("returns N/A grey when equipLoc is unknown", function()
        local text = RCPL_Data_GetPlayerPriority("Alice-Realm", 12345, "INVTYPE_GARBAGE")
        assert.equals("N/A", text)
    end)

    it("returns N/A grey when player has no entry", function()
        local text = RCPL_Data_GetPlayerPriority("Bob-Realm", 12345, "INVTYPE_HEAD")
        assert.equals("N/A", text)
    end)

    -- ── Secondary equipLocs defer to wowaudit ────────────────────────────────

    it("returns wowaudit-defer message for cloak/wrist/waist/feet", function()
        local secondaries = { "INVTYPE_CLOAK", "INVTYPE_WRIST", "INVTYPE_WAIST", "INVTYPE_FEET" }
        for _, equipLoc in ipairs(secondaries) do
            local text, color = RCPL_Data_GetPlayerPriority("Alice-Realm", 999, equipLoc)
            assert.matches("wowaudit", text)
            assert.equals(0.6, color.r)  -- grey
        end
    end)

    -- ── Layer 1: item-centric priority list ──────────────────────────────────

    describe("item-centric priority", function()
        before_each(function()
            _G.RCPL_DB.priority = {
                ["12345"] = { "Alice-Realm", "Bob-Realm", "Carol-Realm" },
            }
        end)

        it("returns 1st green for the rank-1 player", function()
            local text, color = RCPL_Data_GetPlayerPriority("Alice-Realm", 12345, "INVTYPE_HEAD")
            assert.equals("1st", text)
            assert.equals(0.0, color.r)
            assert.equals(1.0, color.g)
        end)

        it("returns 2nd yellow for the rank-2 player", function()
            local text, color = RCPL_Data_GetPlayerPriority("Bob-Realm", 12345, "INVTYPE_HEAD")
            assert.equals("2nd", text)
            assert.equals(1.0, color.r)
            assert.equals(1.0, color.g)
        end)

        it("returns 3rd orange for the rank-3 player", function()
            local text, color = RCPL_Data_GetPlayerPriority("Carol-Realm", 12345, "INVTYPE_HEAD")
            assert.equals("3rd", text)
            assert.equals(1.0, color.r)
            assert.equals(0.5, color.g)
        end)

        it("returns N/A grey for a player not on the list (no fallback)", function()
            -- Dave is not in the priority list for 12345 above (only Alice/Bob/Carol).
            -- Even if Dave has it BiS rank 1 in his player data, the item-centric
            -- list takes precedence and Dave is NOT on it → N/A.
            _G.RCPL_DB.players["Dave-Realm"] = {
                helm = { bis = { 12345 } },
            }
            local text = RCPL_Data_GetPlayerPriority("Dave-Realm", 12345, "INVTYPE_HEAD")
            assert.equals("N/A", text)
        end)

        it("uses ordinal labels for rank > 3", function()
            _G.RCPL_DB.priority["7"] = {
                "P1", "P2", "P3", "P4", "P5",
            }
            local text = RCPL_Data_GetPlayerPriority("P5", 7, "INVTYPE_HEAD")
            assert.equals("5th", text)
        end)
    end)

    -- ── Layer 2: per-player BiS fallback ─────────────────────────────────────

    describe("per-player BiS fallback", function()
        it("matches rank-1 BiS item", function()
            _G.RCPL_DB.players = {
                ["Alice-Realm"] = { helm = { bis = { 100, 200, 300 } } },
            }
            local text, color = RCPL_Data_GetPlayerPriority("Alice-Realm", 100, "INVTYPE_HEAD")
            assert.equals("1st", text)
            assert.equals(1.0, color.g)
        end)

        it("matches rank-2 BiS item", function()
            _G.RCPL_DB.players = {
                ["Alice-Realm"] = { helm = { bis = { 100, 200, 300 } } },
            }
            local text = RCPL_Data_GetPlayerPriority("Alice-Realm", 200, "INVTYPE_HEAD")
            assert.equals("2nd", text)
        end)

        it("matches rank-3 BiS item with orange color", function()
            _G.RCPL_DB.players = {
                ["Alice-Realm"] = { helm = { bis = { 100, 200, 300 } } },
            }
            local text, color = RCPL_Data_GetPlayerPriority("Alice-Realm", 300, "INVTYPE_HEAD")
            assert.equals("3rd", text)
            assert.equals(0.5, color.g)
        end)

        it("returns N/A for items not in player's BiS", function()
            _G.RCPL_DB.players = {
                ["Alice-Realm"] = { helm = { bis = { 100, 200 } } },
            }
            local text = RCPL_Data_GetPlayerPriority("Alice-Realm", 999, "INVTYPE_HEAD")
            assert.equals("N/A", text)
        end)

        it("returns N/A when slot has no BiS entry", function()
            _G.RCPL_DB.players = {
                ["Alice-Realm"] = { helm = nil },
            }
            local text = RCPL_Data_GetPlayerPriority("Alice-Realm", 100, "INVTYPE_HEAD")
            assert.equals("N/A", text)
        end)
    end)

    -- ── Two-key slot types (ring / trinket) ──────────────────────────────────

    describe("multi-key slots", function()
        it("checks both ring1 and ring2 for INVTYPE_FINGER", function()
            _G.RCPL_DB.players = {
                ["Alice-Realm"] = {
                    ring1 = { bis = { 100, 200 } },
                    ring2 = { bis = { 300, 400 } },
                },
            }
            assert.equals("1st", RCPL_Data_GetPlayerPriority("Alice-Realm", 100, "INVTYPE_FINGER"))
            assert.equals("2nd", RCPL_Data_GetPlayerPriority("Alice-Realm", 200, "INVTYPE_FINGER"))
            assert.equals("1st", RCPL_Data_GetPlayerPriority("Alice-Realm", 300, "INVTYPE_FINGER"))
            assert.equals("2nd", RCPL_Data_GetPlayerPriority("Alice-Realm", 400, "INVTYPE_FINGER"))
            assert.equals("N/A", RCPL_Data_GetPlayerPriority("Alice-Realm", 999, "INVTYPE_FINGER"))
        end)

        it("checks both trinket1 and trinket2 for INVTYPE_TRINKET", function()
            _G.RCPL_DB.players = {
                ["Alice-Realm"] = {
                    trinket1 = { bis = { 50 } },
                    trinket2 = { bis = { 60 } },
                },
            }
            assert.equals("1st", RCPL_Data_GetPlayerPriority("Alice-Realm", 50, "INVTYPE_TRINKET"))
            assert.equals("1st", RCPL_Data_GetPlayerPriority("Alice-Realm", 60, "INVTYPE_TRINKET"))
        end)
    end)

    -- ── Weapon equipLoc family ───────────────────────────────────────────────

    it("maps INVTYPE_2HWEAPON, INVTYPE_WEAPON, INVTYPE_WEAPONMAINHAND to mh2h", function()
        _G.RCPL_DB.players = {
            ["Alice-Realm"] = { mh2h = { bis = { 77 } } },
        }
        assert.equals("1st", RCPL_Data_GetPlayerPriority("Alice-Realm", 77, "INVTYPE_2HWEAPON"))
        assert.equals("1st", RCPL_Data_GetPlayerPriority("Alice-Realm", 77, "INVTYPE_WEAPON"))
        assert.equals("1st", RCPL_Data_GetPlayerPriority("Alice-Realm", 77, "INVTYPE_WEAPONMAINHAND"))
    end)

    it("maps INVTYPE_WEAPONOFFHAND to oh", function()
        _G.RCPL_DB.players = {
            ["Alice-Realm"] = { oh = { bis = { 88 } } },
        }
        assert.equals("1st", RCPL_Data_GetPlayerPriority("Alice-Realm", 88, "INVTYPE_WEAPONOFFHAND"))
    end)

    it("maps INVTYPE_ROBE and INVTYPE_CHEST both to chest", function()
        _G.RCPL_DB.players = {
            ["Alice-Realm"] = { chest = { bis = { 42 } } },
        }
        assert.equals("1st", RCPL_Data_GetPlayerPriority("Alice-Realm", 42, "INVTYPE_CHEST"))
        assert.equals("1st", RCPL_Data_GetPlayerPriority("Alice-Realm", 42, "INVTYPE_ROBE"))
    end)
end)
