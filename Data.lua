-- Data.lua
-- All SavedVariable read/write logic for RCLootCouncil_PriorityLoot.
-- Provides three public globals used by Import.lua, UI.lua, and LootFrame.lua:
--   RCLPL_Data_SaveImportedData(decoded)   — store parsed JSON into RCLPriorityDB.players + .priority
--   RCLPL_Data_ResetData()                 — wipe RCLPriorityDB
--   RCLPL_Data_GetPlayerPriority(name, itemID, equipLoc) → text, color

-- ─── Slot-type classification ─────────────────────────────────────────────────
-- Maps WoW equipLoc strings to the internal slot key used in saved data.
-- Secondary slots (Cloak, Bracers, Belt, Boots) defer to wowaudit; core slots use priority/BiS.

local SECONDARY_EQUIPLOC = {
    INVTYPE_CLOAK = "cloak",
    INVTYPE_WRIST = "bracers",
    INVTYPE_WAIST = "belt",
    INVTYPE_FEET  = "boots",
}

-- Values are arrays so multi-slot types (ring, trinket) can carry two keys.
-- GetPlayerPriority iterates all keys in the array when doing BiS fallback.
local CORE_EQUIPLOC = {
    INVTYPE_HEAD            = { "helm" },
    INVTYPE_NECK            = { "neck" },
    INVTYPE_SHOULDER        = { "shoulders" },
    INVTYPE_CHEST           = { "chest" },
    INVTYPE_ROBE            = { "chest" },
    INVTYPE_HAND            = { "gloves" },
    INVTYPE_LEGS            = { "legs" },
    INVTYPE_FINGER          = { "ring1", "ring2" },
    INVTYPE_TRINKET         = { "trinket1", "trinket2" },
    INVTYPE_WEAPON          = { "mh2h" },
    INVTYPE_2HWEAPON        = { "mh2h" },
    INVTYPE_WEAPONMAINHAND  = { "mh2h" },
    INVTYPE_WEAPONOFFHAND   = { "oh" },
}

-- ─── Colors ───────────────────────────────────────────────────────────────────
-- Reused across both rank and droptimizer display paths.

local COLOR_GREEN  = { r = 0.0, g = 1.0, b = 0.0 }
local COLOR_YELLOW = { r = 1.0, g = 1.0, b = 0.0 }
local COLOR_ORANGE = { r = 1.0, g = 0.5, b = 0.0 }
local COLOR_GREY   = { r = 0.6, g = 0.6, b = 0.6 }

-- Ordinal label + color helpers — support any rank depth from the priority list.
local function OrdinalLabel(n)
    if     n == 1 then return "1st"
    elseif n == 2 then return "2nd"
    elseif n == 3 then return "3rd"
    else               return n .. "th"
    end
end

local function RankColor(rank)
    if     rank == 1 then return COLOR_GREEN
    elseif rank == 2 then return COLOR_YELLOW
    else                   return COLOR_ORANGE
    end
end

-- ─── SaveImportedData ─────────────────────────────────────────────────────────
-- Accepts the table produced by LibJSON:decode() and stores both players and
-- priority into RCLPriorityDB.  The incoming table shape is:
--   {
--     players  = { ["Name-Realm"] = { helm={bis={id,...}}, cloak={droptimizer=n}, ... } },
--     priority = { ["itemIDstr"]  = { "Name-Realm", "Name2-Realm", ... } }
--   }
-- Returns playerCount, priorityCount (both numbers).

function RCLPL_Data_SaveImportedData(decoded)
    if type(decoded) ~= "table" or type(decoded.players) ~= "table" then
        print("|cFFFF4444[RCLootCouncil_PriorityLoot]|r Import failed: invalid data structure.")
        return 0, 0
    end

    if type(RCLPriorityDB) ~= "table" then RCLPriorityDB = {} end
    RCLPriorityDB.players  = {}
    RCLPriorityDB.priority = {}

    local playerCount = 0
    for playerKey, slots in pairs(decoded.players) do
        if type(playerKey) == "string" and type(slots) == "table" then
            RCLPriorityDB.players[playerKey] = slots
            playerCount = playerCount + 1
        end
    end

    local priorityCount = 0
    if type(decoded.priority) == "table" then
        for itemIDStr, playerList in pairs(decoded.priority) do
            if type(playerList) == "table" then
                RCLPriorityDB.priority[itemIDStr] = playerList
                priorityCount = priorityCount + 1
            end
        end
    end

    RCLPriorityDB.importedAt = date("%Y-%m-%d %H:%M")
    return playerCount, priorityCount
end

-- ─── ResetData ────────────────────────────────────────────────────────────────

function RCLPL_Data_ResetData()
    if type(RCLPriorityDB) == "table" then
        RCLPriorityDB.players    = {}
        RCLPriorityDB.priority   = {}
        RCLPriorityDB.importedAt = nil
    end
end

-- ─── GetPlayerPriority ────────────────────────────────────────────────────────
-- Returns two values:
--   displayText  (string)  — e.g. "1st", "2nd", "+12.4%", "N/A"
--   color        (table)   — { r, g, b }
--
-- Parameters:
--   playerName  (string)  "Name-Realm"
--   itemID      (number)  WoW item ID
--   equipLoc    (string)  equipLoc string from GetItemInfo(), e.g. "INVTYPE_HEAD"
--
-- Display logic:
--   1. Secondary slots (Cloak/Bracers/Belt) always show droptimizer % from players.
--   2. Core slots check priority[itemID] first — show the player's 1-indexed rank.
--      If the item has a priority list but the player is absent → "N/A".
--   3. If no priority entry exists for the item, fall back to the player's BiS
--      list position from the players object (checks all slot keys for the equipLoc).

function RCLPL_Data_GetPlayerPriority(playerName, itemID, equipLoc)
    if type(RCLPriorityDB) ~= "table"
    or type(RCLPriorityDB.players) ~= "table"
    or type(playerName) ~= "string"
    then
        return "N/A", COLOR_GREY
    end

    -- ── Secondary slot: Cloak, Bracers, Belt, Boots ──────────────────────────
    -- Priority for these slots is managed via wowaudit wishlists, not here.
    if SECONDARY_EQUIPLOC[equipLoc] then
        return "No priority, see wowaudit wishlist", COLOR_GREY
    end

    -- ── Core slot ─────────────────────────────────────────────────────────────
    local coreKeys = CORE_EQUIPLOC[equipLoc]
    if not coreKeys then
        -- equipLoc not tracked (e.g. INVTYPE_BAG) — irrelevant slot.
        return "N/A", COLOR_GREY
    end

    -- Step 1: officer-assigned priority list, keyed by item ID string.
    if type(RCLPriorityDB.priority) == "table" then
        local priorityList = RCLPriorityDB.priority[tostring(itemID)]
        if type(priorityList) == "table" then
            for rank, name in ipairs(priorityList) do
                if name == playerName then
                    return OrdinalLabel(rank), RankColor(rank)
                end
            end
            -- Item has a priority list but this player is not on it.
            return "N/A", COLOR_GREY
        end
    end

    -- Step 2: fall back to BiS position from the players object.
    -- Iterate all slot keys (handles ring1/ring2, trinket1/trinket2 multi-slot).
    local playerData = RCLPriorityDB.players[playerName]
    if type(playerData) ~= "table" then
        return "N/A", COLOR_GREY
    end

    for _, slotKey in ipairs(coreKeys) do
        local slotData = playerData[slotKey]
        if type(slotData) == "table" and type(slotData.bis) == "table" then
            for rank, bisItemID in ipairs(slotData.bis) do
                if bisItemID == itemID then
                    return OrdinalLabel(rank), RankColor(rank)
                end
            end
        end
    end

    return "N/A", COLOR_GREY
end
