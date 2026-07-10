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
-- track ("H"/"M") rather than a single flat list. GetInstanceInfo() gives
-- the live raid difficulty at vote/award time -- no bonus-ID table to
-- maintain, unlike RCLootCouncil_wowaudit's approach, which this addon no
-- longer depends on.
local RAID_DIFFICULTY_TRACK = { [15] = "H", [16] = "M" }
local function CurrentTrack()
    local _, instanceType, difficultyID = GetInstanceInfo()
    if instanceType ~= "raid" then return nil end
    return RAID_DIFFICULTY_TRACK[difficultyID]
end

function RCPL_Data_GetPlayerPriority(playerName, itemID, equipLoc)
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
            local track = CurrentTrack()
            if not track then
                return "N/A (unknown raid difficulty)", COLOR_GREY
            end
            local priorityList = itemPriority[track]
            if type(priorityList) == "table" then
                for rank, name in ipairs(priorityList) do
                    if name == playerName or name == baseName then
                        return OrdinalLabel(rank), RankColor(rank)
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
                    return OrdinalLabel(rank), RankColor(rank)
                end
            end
        end
    end

    return "N/A", COLOR_GREY
end
