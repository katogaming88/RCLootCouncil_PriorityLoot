-- Data\db.lua
-- All SavedVariable read/write logic for RCLootCouncil_PriorityLoot.

local SECONDARY_EQUIPLOC = {
    INVTYPE_CLOAK = "cloak",
    INVTYPE_WRIST = "bracers",
    INVTYPE_WAIST = "belt",
    INVTYPE_FEET  = "boots",
}

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
    INVTYPE_SHIELD          = { "oh" },
    INVTYPE_HOLDABLE        = { "oh" },
}

local COLOR_GREEN  = { r = 0.0, g = 1.0, b = 0.0 }
local COLOR_YELLOW = { r = 1.0, g = 1.0, b = 0.0 }
local COLOR_ORANGE = { r = 1.0, g = 0.5, b = 0.0 }
local COLOR_GREY   = { r = 0.6, g = 0.6, b = 0.6 }

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

-- Public wrapper so other modules (Modules/prioPreviewFrame.lua) can reuse
-- the exact same rank -> color scheme the voting/loot frame overlay uses,
-- instead of maintaining a second copy that can drift out of sync (#27).
function RCPL_Data_RankColor(rank)
    return RankColor(rank)
end

local TRACK_LABEL = { H = "Heroic", M = "Mythic" }

-- Public so callers (Modules/lootFrame.lua, Modules/prioPreviewFrame.lua) can
-- turn the "H"/"M" RCPL_Data_GetPlayerPriority now returns as its third
-- value into the same human-readable label everywhere, one source of truth.
function RCPL_Data_TrackLabel(track)
    return TRACK_LABEL[track]
end

function RCPL_Data_SaveImportedData(decoded)
    if type(decoded) ~= "table" or type(decoded.players) ~= "table" then
        print("|cFFFF4444[RCLootCouncil_PriorityLoot]|r Import failed: invalid data structure.")
        return 0, 0
    end

    if type(RCPL_DB) ~= "table" then RCPL_DB = {} end
    RCPL_DB.players  = {}
    RCPL_DB.priority = {}
    RCPL_DB.awarded  = {}

    local playerCount = 0
    for playerKey, slots in pairs(decoded.players) do
        if type(playerKey) == "string" and type(slots) == "table" then
            RCPL_DB.players[playerKey] = slots
            playerCount = playerCount + 1
        end
    end

    local priorityCount = 0
    if type(decoded.priority) == "table" then
        for itemIDStr, playerList in pairs(decoded.priority) do
            if type(playerList) == "table" then
                RCPL_DB.priority[itemIDStr] = playerList
                priorityCount = priorityCount + 1
            end
        end
    end

    RCPL_DB.importedAt = date("%Y-%m-%d %H:%M")
    return playerCount, priorityCount
end

function RCPL_Data_ResetData()
    if type(RCPL_DB) == "table" then
        RCPL_DB.players    = {}
        RCPL_DB.priority   = {}
        RCPL_DB.awarded    = {}
        RCPL_DB.importedAt = nil
    end
end

function RCPL_Data_MarkAwarded(playerName, itemID, link)
    if type(RCPL_DB) ~= "table" then return end
    if type(RCPL_DB.awarded) ~= "table" then RCPL_DB.awarded = {} end
    if not RCPL_DB.awarded[itemID] then RCPL_DB.awarded[itemID] = {} end
    RCPL_DB.awarded[itemID][playerName] = link or true
end

function RCPL_Data_UnmarkAwarded(playerName, itemID)
    if type(RCPL_DB) ~= "table" or type(RCPL_DB.awarded) ~= "table" then return end
    if type(RCPL_DB.awarded[itemID]) ~= "table" then return end
    RCPL_DB.awarded[itemID][playerName] = nil
    if not next(RCPL_DB.awarded[itemID]) then
        RCPL_DB.awarded[itemID] = nil
    end
end

-- Returns the name portion before the first "-Realm" suffix, if any.
local function BaseName(name)
    return (name:match("^([^%-]+)")) or name
end

-- Item IDs are shared between the Heroic and Mythic version of a given piece
-- (this game's item tracks scale ilvl, not the base item ID -- confirmed
-- from the WGA Raid Hub Supabase schema, which stores one wow_item_id per
-- conceptual item), so RCPL_DB.priority[itemID] holds one ranked list per
-- track ("H"/"M") rather than a single flat list.
--
-- Track detection, in priority order:
--   1. instanceDifficultyID off the item link itself (TrackFromItemLink) --
--      a dedicated field in every item string (position 13 of the
--      colon-separated "item:" string, distinct from bonusIDs), set by the
--      server the moment a real loot drop is generated. Correct for every
--      real award path (Start Session voting/loot frames) with zero
--      per-tier maintenance -- unlike ilvl, this field never changes
--      meaning across tiers. It is *not* set on synthetic links (e.g. /rc
--      test's Encounter Journal preview links were never itemized against a
--      real instance run), so it's only reliable for genuine drops.
--   2. The item's own live item level (TrackFromItemLevel) -- covers /rc
--      test, since ilvl scaling rides on bonus IDs, which Encounter
--      Journal's per-difficulty-tab preview links do carry correctly (unlike
--      instanceDifficultyID). Doesn't matter that this needs the two ilvl
--      constants below bumped once per raid tier -- nothing is actually
--      awarded from a test session, so a stale value here is harmless.
--   3. GetInstanceInfo()'s live raid difficulty (TrackFromInstance) -- a
--      fallback for the rare case an item's detailed level info isn't
--      cached client-side yet (GetDetailedItemLevelInfo can return nil on
--      the first frame an item is seen).
-- None of the three depend on RCLootCouncil_wowaudit's bonus-ID table, which
-- this addon no longer needs and which the user plans to eventually
-- uninstall.
local TIER_HEROIC_ILVL = 266
local TIER_MYTHIC_ILVL = 279

local RAID_DIFFICULTY_TRACK = { [15] = "H", [16] = "M" }

-- item:itemID:enchantID:gem1:gem2:gem3:gem4:suffixID:uniqueID:linkLevel:
-- specializationID:upgradeTypeID:instanceDifficultyID:... -- 11 numeric
-- fields (itemID through upgradeTypeID) after the "item:" literal, then the
-- 13th field (instanceDifficultyID) captured on its own.
local ITEM_STRING_DIFFICULTY_PATTERN = "^item:" .. ("%-?%d*:"):rep(11) .. "(%-?%d*):"

-- Pure Lua string parsing, no WoW-specific API and no RCLootCouncil
-- dependency -- mirrors the one-liner RCLootCouncil's own
-- Utils.Item:GetItemStringFromLink uses internally (core.lua's
-- DecodeItemLink), reimplemented locally rather than reaching into
-- RCLootCouncil's non-public API.
local function TrackFromItemLink(itemLink)
    if not itemLink then return nil end
    local itemString = itemLink:match("item:[%-%d:]+")
    if not itemString then return nil end
    local instanceDifficultyID = itemString:match(ITEM_STRING_DIFFICULTY_PATTERN)
    return RAID_DIFFICULTY_TRACK[tonumber(instanceDifficultyID)]
end

local function TrackFromItemLevel(itemLink)
    if not itemLink then return nil end
    local actualItemLevel = C_Item.GetDetailedItemLevelInfo(itemLink)
    if actualItemLevel == TIER_MYTHIC_ILVL then return "M" end
    if actualItemLevel == TIER_HEROIC_ILVL then return "H" end
    return nil
end

local function TrackFromInstance()
    local _, instanceType, difficultyID = GetInstanceInfo()
    if instanceType ~= "raid" then return nil end
    return RAID_DIFFICULTY_TRACK[difficultyID]
end

local function CurrentTrack(itemLink)
    return TrackFromItemLink(itemLink) or TrackFromItemLevel(itemLink) or TrackFromInstance()
end

function RCPL_Data_GetPlayerPriority(playerName, itemID, equipLoc, itemLink)
    if type(RCPL_DB) ~= "table"
    or type(RCPL_DB.players) ~= "table"
    or type(playerName) ~= "string"
    then
        return "N/A", COLOR_GREY
    end

    -- Import data stores names without realm; RCLootCouncil provides them with
    -- realm for cross-realm players. Strip realm for lookups that use imported names.
    local baseName = BaseName(playerName)

    if type(RCPL_DB.awarded) == "table" then
        local awardsForItem = RCPL_DB.awarded[tostring(itemID)]
        if type(awardsForItem) == "table"
        and (awardsForItem[playerName] or awardsForItem[baseName]) then
            return "Awarded", COLOR_GREY
        end
    end

    if SECONDARY_EQUIPLOC[equipLoc] then
        return "No priority, see wowaudit wishlist", COLOR_GREY
    end

    local coreKeys = CORE_EQUIPLOC[equipLoc]
    if not coreKeys then
        return "N/A", COLOR_GREY
    end

    if type(RCPL_DB.priority) == "table" then
        local itemPriority = RCPL_DB.priority[tostring(itemID)]
        if type(itemPriority) == "table" then
            local track = CurrentTrack(itemLink)
            if not track then
                return "N/A (unknown raid difficulty)", COLOR_GREY
            end
            local priorityList = itemPriority[track]
            if type(priorityList) == "table" then
                for rank, name in ipairs(priorityList) do
                    if name == playerName or name == baseName then
                        return OrdinalLabel(rank), RankColor(rank), track, rank
                    end
                end
            end
            return "N/A", COLOR_GREY
        end
    end

    local playerData = RCPL_DB.players[playerName] or RCPL_DB.players[baseName]
    if type(playerData) ~= "table" then
        return "N/A", COLOR_GREY
    end

    for _, slotKey in ipairs(coreKeys) do
        local slotData = playerData[slotKey]
        if type(slotData) == "table" and type(slotData.bis) == "table" then
            for rank, bisItemID in ipairs(slotData.bis) do
                if bisItemID == itemID then
                    return OrdinalLabel(rank), RankColor(rank), nil, rank
                end
            end
        end
    end

    return "N/A", COLOR_GREY
end
