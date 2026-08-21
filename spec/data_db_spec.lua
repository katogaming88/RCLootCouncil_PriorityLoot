-- spec/data_db_spec.lua
--
-- Exhaustive coverage of RCPL_Data_GetPlayerPriority - the central
-- resolver used by both votingFrame.lua and lootFrame.lua.
--
-- The resolver lives in Data/db.lua and walks two layers of saved data:
--   1. Item-centric  RCPL_DB.priority[itemID][track] → ranked Name-Realm list
--   2. Player-centric RCPL_DB.players[name][slot].bis[]
--
-- Layer 1 wins when present, even if the matching player is absent
-- (returns N/A with no fallback to layer 2). Layer 1 is track-split (#335):
-- Heroic and Mythic share the same itemID in this game but can have
-- genuinely different priority rankings, so which sub-list applies is
-- resolved per-lookup, in order: (1) instanceDifficultyID parsed directly
-- off a real item link -- correct for every genuine drop with zero
-- maintenance, but unset on synthetic links like /rc test's Encounter
-- Journal previews; (2) the item's own live item level (mocks.setItemLevel),
-- which does survive /rc test since ilvl scaling rides on bonus IDs rather
-- than instanceDifficultyID; (3) GetInstanceInfo()'s live raid difficulty
-- (mocks.setInstanceInfo), for the rare case the item level isn't cached yet.
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

    it("returns wowaudit-defer message for cloak/wrist/waist/feet with no item-centric list", function()
        local secondaries = { "INVTYPE_CLOAK", "INVTYPE_WRIST", "INVTYPE_WAIST", "INVTYPE_FEET" }
        for _, equipLoc in ipairs(secondaries) do
            local text, color = RCPL_Data_GetPlayerPriority("Alice-Realm", 999, equipLoc)
            assert.matches("wowaudit", text)
            assert.equals(0.6, color.r)  -- grey
        end
    end)

    -- A "secondary" slot (Cloak/Wrist/Waist/Feet) has no per-player BiS
    -- category in RCPL_DB.players (see CORE_EQUIPLOC), but the item-centric
    -- priority list is itemID-keyed, not slot-keyed -- WGA Raid Hub tracks
    -- and exports a real ranking for these slots too (confirmed live: a
    -- Waist item's Full Priority Order side panel showed a 5-player ranking
    -- while every voting-frame row said "No priority, see wowaudit
    -- wishlist"). The item-centric list must win over the wowaudit deferral
    -- whenever one actually exists for this item.
    it("uses the item-centric priority list for a secondary slot when one exists, instead of deferring to wowaudit", function()
        mocks.setInstanceInfo("raid", 15)
        _G.RCPL_DB.priority = {
            ["999"] = { H = { "Alice-Realm", "Bob-Realm" } },
        }
        local text, color = RCPL_Data_GetPlayerPriority("Alice-Realm", 999, "INVTYPE_WAIST")
        assert.equals("1st", text)
        assert.equals(0.0, color.r)
        assert.equals(1.0, color.g)
    end)

    it("still defers to wowaudit for a secondary slot once the item-centric list has no entry for this track", function()
        mocks.setInstanceInfo("raid", 16)  -- Mythic
        _G.RCPL_DB.priority = {
            ["999"] = { H = { "Alice-Realm" } },  -- Heroic list only
        }
        local text = RCPL_Data_GetPlayerPriority("Alice-Realm", 999, "INVTYPE_WRIST")
        -- No Mythic sub-list for this item -> the item-centric branch itself
        -- returns "N/A", not the wowaudit message; that's a deliberate
        -- distinction (a real list exists but doesn't cover this track,
        -- vs. no list at all).
        assert.equals("N/A", text)
    end)

    -- ── Layer 1: item-centric priority list ──────────────────────────────────

    describe("item-centric priority", function()
        before_each(function()
            -- Heroic raid (difficultyID 15) unless a test overrides it.
            mocks.setInstanceInfo("raid", 15)
            _G.RCPL_DB.priority = {
                ["12345"] = { H = { "Alice-Realm", "Bob-Realm", "Carol-Realm" } },
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
                H = { "P1", "P2", "P3", "P4", "P5" },
            }
            local text = RCPL_Data_GetPlayerPriority("P5", 7, "INVTYPE_HEAD")
            assert.equals("5th", text)
        end)
    end)

    -- ── Connected-realm / same-realm bare name (voting frame N/A bug) ────────
    --
    -- RCLootCouncil hands the voting frame a bare name (no "-Realm" suffix)
    -- for any candidate the game treats as the viewer's own realm -- same
    -- realm, or a connected one -- even though the exported priority list
    -- (rclc_export.sql) always stores full "Name-Realm" strings for every
    -- entry, with no exceptions. Before this fix, only a candidate whose
    -- *roster* name happened to already carry a realm suffix (i.e. was
    -- genuinely cross-realm from the viewer's point of view) could ever
    -- match a list entry -- every same/connected-realm candidate silently
    -- fell through to "N/A" despite being plainly ranked in the very same
    -- list the side panel (votingPriorityPanel.lua) prints in full.
    describe("bare roster name vs Name-Realm-keyed saved data", function()
        before_each(function()
            mocks.setInstanceInfo("raid", 15)
        end)

        it("matches the item-centric priority list when the roster gives a bare name", function()
            _G.RCPL_DB.priority = {
                ["12345"] = { H = { "Alice-Realm", "Bob-Realm", "Carol-Realm" } },
            }
            -- RCLootCouncil would call this with just "Bob" for a
            -- same/connected-realm candidate, not "Bob-Realm".
            local text, color = RCPL_Data_GetPlayerPriority("Bob", 12345, "INVTYPE_HEAD")
            assert.equals("2nd", text)
            assert.equals(1.0, color.r)
            assert.equals(1.0, color.g)
        end)

        it("still returns N/A for a bare name genuinely absent from the list", function()
            _G.RCPL_DB.priority = {
                ["12345"] = { H = { "Alice-Realm", "Bob-Realm" } },
            }
            local text = RCPL_Data_GetPlayerPriority("Dave", 12345, "INVTYPE_HEAD")
            assert.equals("N/A", text)
        end)

        it("falls back to the per-player BiS list by bare name when no item-centric list exists", function()
            _G.RCPL_DB.priority = {}
            _G.RCPL_DB.players = {
                ["Alice-Realm"] = { helm = { bis = { 100, 200 } } },
            }
            local text = RCPL_Data_GetPlayerPriority("Alice", 200, "INVTYPE_HEAD")
            assert.equals("2nd", text)
        end)
    end)

    -- ── Track-aware lookup (#335) ─────────────────────────────────────────────

    describe("track-aware priority (Heroic vs Mythic)", function()
        before_each(function()
            _G.RCPL_DB.priority = {
                ["500"] = {
                    H = { "Alice-Realm", "Bob-Realm" },
                    M = { "Bob-Realm", "Alice-Realm" },
                },
            }
        end)

        it("uses the Heroic list while in a Heroic raid (instance-info fallback)", function()
            mocks.setInstanceInfo("raid", 15)
            assert.equals("1st", RCPL_Data_GetPlayerPriority("Alice-Realm", 500, "INVTYPE_HEAD"))
            assert.equals("2nd", RCPL_Data_GetPlayerPriority("Bob-Realm", 500, "INVTYPE_HEAD"))
        end)

        it("uses the Mythic list while in a Mythic raid, even for the same itemID", function()
            mocks.setInstanceInfo("raid", 16)
            assert.equals("1st", RCPL_Data_GetPlayerPriority("Bob-Realm", 500, "INVTYPE_HEAD"))
            assert.equals("2nd", RCPL_Data_GetPlayerPriority("Alice-Realm", 500, "INVTYPE_HEAD"))
        end)

        it("returns the resolved track as a third value (#27)", function()
            mocks.setInstanceInfo("raid", 15)
            local text, _, track = RCPL_Data_GetPlayerPriority("Alice-Realm", 500, "INVTYPE_HEAD")
            assert.equals("1st", text)
            assert.equals("H", track)

            mocks.setInstanceInfo("raid", 16)
            local text2, _, track2 = RCPL_Data_GetPlayerPriority("Bob-Realm", 500, "INVTYPE_HEAD")
            assert.equals("1st", text2)
            assert.equals("M", track2)
        end)

        it("does not return a track for the per-player BiS fallback (not track-split)", function()
            _G.RCPL_DB.priority = {}  -- no item-centric list -- forces layer 2
            _G.RCPL_DB.players["Alice-Realm"] = { helm = { bis = { 500 } } }
            local text, _, track = RCPL_Data_GetPlayerPriority("Alice-Realm", 500, "INVTYPE_HEAD")
            assert.equals("1st", text)
            assert.is_nil(track)
        end)

        it("returns the raw numeric rank as a fourth value, item-centric list", function()
            mocks.setInstanceInfo("raid", 15)
            local text, _, _, rank = RCPL_Data_GetPlayerPriority("Bob-Realm", 500, "INVTYPE_HEAD")
            assert.equals("2nd", text)
            assert.equals(2, rank)
        end)

        it("returns the raw numeric rank as a fourth value, per-player BiS fallback", function()
            _G.RCPL_DB.priority = {}
            _G.RCPL_DB.players["Alice-Realm"] = { helm = { bis = { 999, 500 } } }
            local text, _, _, rank = RCPL_Data_GetPlayerPriority("Alice-Realm", 500, "INVTYPE_HEAD")
            assert.equals("2nd", text)
            assert.equals(2, rank)
        end)

        it("returns N/A grey for a track the item has no ranking for", function()
            _G.RCPL_DB.priority["501"] = { H = { "Alice-Realm" } }  -- no Mythic list
            mocks.setInstanceInfo("raid", 16)
            local text, color = RCPL_Data_GetPlayerPriority("Alice-Realm", 501, "INVTYPE_HEAD")
            assert.equals("N/A", text)
            assert.equals(0.6, color.r)
        end)

        it("returns an unknown-difficulty message when not in a raid and the item level is unknown", function()
            mocks.setInstanceInfo(nil, nil)
            local text, color = RCPL_Data_GetPlayerPriority("Alice-Realm", 500, "INVTYPE_HEAD")
            assert.matches("unknown raid difficulty", text)
            assert.equals(0.6, color.r)
        end)

        it("returns the unknown-difficulty message for an unmapped difficultyID (e.g. LFR)", function()
            mocks.setInstanceInfo("raid", 17)
            local text = RCPL_Data_GetPlayerPriority("Alice-Realm", 500, "INVTYPE_HEAD")
            assert.matches("unknown raid difficulty", text)
        end)

        -- ── instanceDifficultyID from the item link (primary signal) ──────────
        -- Real loot drops (Start Session) carry this in the item string itself
        -- (field 13 of "item:itemID:...:instanceDifficultyID:numBonuses:...").
        -- Synthetic links (e.g. /rc test) don't have it, which the item-level
        -- fallback tests below cover.

        it("uses instanceDifficultyID from a real Heroic drop's item link", function()
            mocks.setInstanceInfo(nil, nil)  -- no live raid, no item level cached
            local heroicLink = "item:500:0:0:0:0:0:0:0:0:0:0:15:0"
            assert.equals("1st", RCPL_Data_GetPlayerPriority("Alice-Realm", 500, "INVTYPE_HEAD", heroicLink))
        end)

        it("uses instanceDifficultyID from a real Mythic drop's item link", function()
            mocks.setInstanceInfo(nil, nil)
            local mythicLink = "item:500:0:0:0:0:0:0:0:0:0:0:16:0"
            assert.equals("1st", RCPL_Data_GetPlayerPriority("Bob-Realm", 500, "INVTYPE_HEAD", mythicLink))
        end)

        it("prefers instanceDifficultyID over a conflicting live raid difficulty or item level", function()
            mocks.setInstanceInfo("raid", 15)  -- Heroic raid
            local mythicLink = "item:500:0:0:0:0:0:0:0:0:0:0:16:0"  -- but this drop is Mythic
            mocks.setItemLevel(mythicLink, 310)  -- and a (contradictory) Heroic item level
            assert.equals("1st", RCPL_Data_GetPlayerPriority("Bob-Realm", 500, "INVTYPE_HEAD", mythicLink))
        end)

        it("falls back to item level for a synthetic link with no instanceDifficultyID field", function()
            mocks.setInstanceInfo(nil, nil)
            mocks.setItemLevel("item:500", 330)  -- /rc test-style bare link
            assert.equals("1st", RCPL_Data_GetPlayerPriority("Bob-Realm", 500, "INVTYPE_HEAD", "item:500"))
        end)

        it("falls back to item level for an unmapped instanceDifficultyID (e.g. LFR)", function()
            mocks.setInstanceInfo(nil, nil)
            local lfrLink = "item:500:0:0:0:0:0:0:0:0:0:0:17:0"
            mocks.setItemLevel(lfrLink, 330)  -- Mythic ilvl, even though this specific drop is LFR
            assert.equals("1st", RCPL_Data_GetPlayerPriority("Bob-Realm", 500, "INVTYPE_HEAD", lfrLink))
        end)

        -- ── Item-level detection (fallback for synthetic/test links) ──────────

        it("uses the item's own item level to pick the track, with no raid instance at all", function()
            -- Mirrors /rc test: never actually in a raid, but the fake test
            -- item still carries a real item level.
            mocks.setInstanceInfo(nil, nil)
            mocks.setItemLevel("item:500", 330)  -- within Mythic's range only (Data/db.lua's TIER_MYTHIC_ILVL_MIN/MAX)
            assert.equals("1st", RCPL_Data_GetPlayerPriority("Bob-Realm", 500, "INVTYPE_HEAD", "item:500"))
        end)

        it("prefers the item's own item level over a conflicting live raid difficulty", function()
            mocks.setInstanceInfo("raid", 15)  -- Heroic raid
            mocks.setItemLevel("item:500", 330)  -- but this drop is Mythic-range-only ilvl
            assert.equals("1st", RCPL_Data_GetPlayerPriority("Bob-Realm", 500, "INVTYPE_HEAD", "item:500"))
        end)

        it("falls back to instance info when the item level isn't known yet", function()
            mocks.setInstanceInfo("raid", 15)
            -- No mocks.setItemLevel call -- GetDetailedItemLevelInfo returns nil,
            -- as it can on the first frame an item is seen.
            assert.equals("1st", RCPL_Data_GetPlayerPriority("Alice-Realm", 500, "INVTYPE_HEAD", "item:500"))
        end)

        it("ignores an item level that doesn't match either known tier track", function()
            mocks.setInstanceInfo("raid", 15)
            mocks.setItemLevel("item:500", 200)  -- some unrelated ilvl
            assert.equals("1st", RCPL_Data_GetPlayerPriority("Alice-Realm", 500, "INVTYPE_HEAD", "item:500"))
        end)

        -- ── Item-level ranges, not a single exact value per track (#335-followup) ──
        -- ilvl climbs per boss within a raid tier (an early boss's Heroic
        -- drop is a lower ilvl than a later boss's Heroic drop), so there's
        -- no single "the Heroic ilvl" to match against -- Season 2 (per Kat):
        -- Heroic 305-321, Mythic 318-344. These overlap at 318-321.

        it("resolves Heroic anywhere in its non-overlapping range (305-317)", function()
            mocks.setInstanceInfo(nil, nil)
            for _, ilvl in ipairs({ 305, 311, 317 }) do
                local link = "item:500:0:0:0:0:0:0:0:0:0:0:0:0"
                mocks.setItemLevel(link, ilvl)
                assert.equals("1st", RCPL_Data_GetPlayerPriority("Alice-Realm", 500, "INVTYPE_HEAD", link))
            end
        end)

        it("resolves Mythic anywhere in its non-overlapping range (322-344)", function()
            mocks.setInstanceInfo(nil, nil)
            for _, ilvl in ipairs({ 322, 333, 344 }) do
                local link = "item:500:0:0:0:0:0:0:0:0:0:0:0:0"
                mocks.setItemLevel(link, ilvl)
                assert.equals("1st", RCPL_Data_GetPlayerPriority("Bob-Realm", 500, "INVTYPE_HEAD", link))
            end
        end)

        it("leaves the overlapping band (318-321) genuinely ambiguous instead of guessing", function()
            mocks.setInstanceInfo(nil, nil)  -- no instance fallback available either
            for _, ilvl in ipairs({ 318, 319, 321 }) do
                local link = "item:500:0:0:0:0:0:0:0:0:0:0:0:0"
                mocks.setItemLevel(link, ilvl)
                local text = RCPL_Data_GetPlayerPriority("Alice-Realm", 500, "INVTYPE_HEAD", link)
                assert.matches("unknown raid difficulty", text)
            end
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

-- ── RCPL_Data_RankColor ──────────────────────────────────────────────────────
-- Public wrapper (#27) so Modules/prioPreviewFrame.lua can color-code ranks
-- with the exact same scheme the voting/loot frame overlay uses.

describe("RCPL_Data_RankColor", function()
    setup(function()
        mocks.loadAddonSources()
    end)

    it("returns green for rank 1", function()
        local color = RCPL_Data_RankColor(1)
        assert.equals(0.0, color.r)
        assert.equals(1.0, color.g)
    end)

    it("returns yellow for rank 2", function()
        local color = RCPL_Data_RankColor(2)
        assert.equals(1.0, color.r)
        assert.equals(1.0, color.g)
    end)

    it("returns orange for rank 3", function()
        local color = RCPL_Data_RankColor(3)
        assert.equals(1.0, color.r)
        assert.equals(0.5, color.g)
    end)

    it("returns grey for ranks below 3rd", function()
        for _, rank in ipairs({ 4, 5, 10 }) do
            local color = RCPL_Data_RankColor(rank)
            assert.equals(0.6, color.r)
            assert.equals(0.6, color.g)
            assert.equals(0.6, color.b)
        end
    end)
end)

-- ── RCPL_Data_TrackLabel ─────────────────────────────────────────────────────
-- Public wrapper (#27) so Modules/lootFrame.lua and Modules/prioPreviewFrame.lua
-- share one "H"/"M" -> human-readable label instead of each maintaining its own.

describe("RCPL_Data_TrackLabel", function()
    setup(function()
        mocks.loadAddonSources()
    end)

    it("labels H as Heroic and M as Mythic", function()
        assert.equals("Heroic", RCPL_Data_TrackLabel("H"))
        assert.equals("Mythic", RCPL_Data_TrackLabel("M"))
    end)

    it("returns nil for an unknown or absent track", function()
        assert.is_nil(RCPL_Data_TrackLabel("LFR"))
        assert.is_nil(RCPL_Data_TrackLabel(nil))
    end)
end)
