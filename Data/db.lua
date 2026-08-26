-- Data\db.lua
-- All SavedVariable read/write logic for RCLootCouncil_PriorityLoot.

-- Modules/log.lua loads before this file (see .toc), so RCPL_Log is always
-- available by the time any function below executes. Capture as a local for
-- speed; fall back to no-ops if the global is ever missing, matching
-- Core.lua's own fallback pattern.
local Log = RCPL_Log or {
    debug = function() end, info = function() end,
    warn = function() end, error = function() end,
}

-- Cloak/Wrist/Waist/Feet used to have no per-player BiS category here and
-- deferred to a generic "no priority for this slot" message instead (the old
-- SECONDARY_EQUIPLOC special case, since removed). WGA Raid Hub tracks and
-- exports real priority data for every slot now, so these four are just
-- ordinary CORE_EQUIPLOC entries, keyed to match rclc_export.sql's slot_key
-- mapping (Back/Wrist/Waist/Feet -> cloak/bracers/belt/boots) exactly.
local CORE_EQUIPLOC = {
    INVTYPE_HEAD            = { "helm" },
    INVTYPE_NECK            = { "neck" },
    INVTYPE_SHOULDER        = { "shoulders" },
    INVTYPE_CLOAK           = { "cloak" },
    INVTYPE_CHEST           = { "chest" },
    INVTYPE_ROBE            = { "chest" },
    INVTYPE_WRIST           = { "bracers" },
    INVTYPE_HAND            = { "gloves" },
    INVTYPE_WAIST           = { "belt" },
    INVTYPE_LEGS            = { "legs" },
    INVTYPE_FEET            = { "boots" },
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
    elseif rank == 3 then return COLOR_ORANGE
    -- Anyone below 3rd priority is unlikely to actually receive the item,
    -- so fade them to grey rather than keep stretching the same orange
    -- across an arbitrarily long tail of ranks.
    else                   return COLOR_GREY
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

-- `source` records where this data came from -- "local" for a string the
-- player pasted into the import frame themselves, "sync" for data applied
-- from another client's broadcast (Modules/prioSync.lua). Modules/prioSync.lua
-- checks this to avoid letting an automatic group sync silently overwrite
-- data the player deliberately imported on their own client (#1).
function RCPL_Data_SaveImportedData(decoded, source)
    if type(decoded) ~= "table" or type(decoded.players) ~= "table" then
        print("|cFFFF4444[RCLootCouncil_PriorityLoot]|r Import failed: invalid data structure.")
        return 0, 0
    end

    if type(RCPL_DB) ~= "table" then RCPL_DB = {} end
    RCPL_DB.players  = {}
    RCPL_DB.priority = {}
    RCPL_DB.awarded  = {}
    RCPL_DB.importSource = source or "local"

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
        RCPL_DB.players      = {}
        RCPL_DB.priority     = {}
        RCPL_DB.awarded      = {}
        RCPL_DB.importedAt   = nil
        RCPL_DB.importSource = nil
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

-- `nonTradeables` is RCLootCouncil's own addon.nonTradeables list (Core.lua):
-- every {link, reason, owner} broadcast group-wide by OnBonusRoll/
-- OnTradeableStatusReceived since the last ENCOUNTER_END, which is when
-- RCLootCouncil wipes it. That reset is exactly the scope we want -- "has
-- this candidate already used their weekly Bonus Roll on the current boss" --
-- with no bookkeeping of our own needed. playerName may come with or without
-- a realm suffix on either side (comm senders and voting-frame candidate
-- names aren't guaranteed to agree), so both are compared via BaseName.
function RCPL_Data_HasBonusRolled(nonTradeables, playerName)
    if type(nonTradeables) ~= "table" or type(playerName) ~= "string" then
        return false
    end
    local baseName = BaseName(playerName)
    for _, entry in ipairs(nonTradeables) do
        if type(entry) == "table" and entry.reason == "bonus_roll" and type(entry.owner) == "string" then
            if entry.owner == playerName or BaseName(entry.owner) == baseName then
                return true
            end
        end
    end
    return false
end

-- Item IDs are shared between the Heroic and Mythic version of a given piece
-- (this game's item tracks scale ilvl, not the base item ID -- confirmed
-- from the WGA Raid Hub Supabase schema, which stores one wow_item_id per
-- conceptual item), so RCPL_DB.priority[itemID] holds one ranked list per
-- track ("H"/"M") rather than a single flat list.
--
-- Track detection, in priority order:
--   1. instanceDifficultyID off the item link itself (TrackFromItemLink) --
--      a dedicated field in every item string (position 11 of the
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
--      instanceDifficultyID). Doesn't matter that this needs the ilvl ranges
--      below updated once per raid tier -- nothing is actually awarded from
--      a test session, so a stale value here is harmless. Ranges, not a
--      single exact value per track: item level climbs per boss within a
--      raid tier (an early boss's Heroic drop is a lower ilvl than a later
--      boss's Heroic drop), so there is no single "the Heroic ilvl" to
--      match against. Season 2 (per Kat, 2026-08-17): Heroic 305-321,
--      Mythic 318-344 -- these overlap (318-321 exists on both difficulties
--      depending on which boss), so that band is left genuinely ambiguous
--      (returns nil) rather than guessed.
--   3. GetInstanceInfo()'s live raid difficulty (TrackFromInstance) -- a
--      fallback for the rare case an item's detailed level info isn't
--      cached client-side yet (GetDetailedItemLevelInfo can return nil on
--      the first frame an item is seen).
local TIER_HEROIC_ILVL_MIN = 305
local TIER_HEROIC_ILVL_MAX = 321
local TIER_MYTHIC_ILVL_MIN = 318
local TIER_MYTHIC_ILVL_MAX = 344

-- "N" (Normal, difficultyID 14) is tracked here purely so CurrentTrack can
-- positively identify a Normal drop and hand back "N" instead of nil --
-- WGA Raid Hub doesn't export Normal priority data, so itemPriority["N"]
-- is never a table and the caller correctly falls through to a plain
-- "N/A" rather than the (misleading, since the difficulty *is* known)
-- "N/A (unknown raid difficulty)" message that a nil track produces.
local RAID_DIFFICULTY_TRACK = { [14] = "N", [15] = "H", [16] = "M" }

-- item:itemID:enchantID:gem1:gem2:gem3:gem4:suffixID:uniqueID:linkLevel:
-- specializationID:instanceDifficultyID:numBonusIDs:bonusID1:... -- 10
-- numeric fields (itemID through specializationID) after the "item:"
-- literal, then the 11th field (instanceDifficultyID) captured on its own.
-- Confirmed against real saved item links in this account's SavedVariables
-- (field 11 is empty on a bag/award link with no drop context, field 12 is
-- numBonusIDs). A previous version of this pattern captured field 12
-- instead (numBonusIDs, not instanceDifficultyID) -- harmless for an item
-- with zero or few bonus IDs, since numBonusIDs rarely lands on 14/15/16,
-- but a drop with extra bonus IDs (a tertiary stat and/or a socket) could
-- coincidentally produce a numBonusIDs value that collided with a real
-- RAID_DIFFICULTY_TRACK key, silently picking the wrong track's priority
-- list for that drop.
local ITEM_STRING_DIFFICULTY_PATTERN = "^item:" .. ("%-?%d*:"):rep(10) .. "(%-?%d*):"

-- Pure Lua string parsing, no WoW-specific API and no RCLootCouncil
-- dependency -- mirrors the one-liner RCLootCouncil's own
-- Utils.Item:GetItemStringFromLink uses internally (core.lua's
-- DecodeItemLink), reimplemented locally rather than reaching into
-- RCLootCouncil's non-public API.
local function TrackFromItemLink(itemLink)
    if not itemLink then return nil end
    local itemString = itemLink:match("item:[%-%d:]+")
    if not itemString then
        Log.debug("TrackFromItemLink: no item: substring in link=%s", tostring(itemLink))
        return nil
    end
    local instanceDifficultyID = itemString:match(ITEM_STRING_DIFFICULTY_PATTERN)
    local track = RAID_DIFFICULTY_TRACK[tonumber(instanceDifficultyID)]
    Log.debug("TrackFromItemLink: link=%s instanceDifficultyID=%s -> %s",
        tostring(itemLink), tostring(instanceDifficultyID), tostring(track))
    return track
end

local function TrackFromItemLevel(itemLink)
    if not itemLink then return nil end
    -- GetDetailedItemLevelInfo returns 3 values: the effective (possibly
    -- upgraded/preview) item level, whether it's a preview, and the base
    -- item level with no upgrade applied. Logging all three -- baseItemLevel
    -- turned out to be a flat per-item floor (identical regardless of
    -- track, confirmed empirically), not a usable signal, but kept in the
    -- log for visibility. A same-item "remember one track, infer the other"
    -- heuristic was also tried here and reverted -- real /rc test data
    -- showed a single item can report more than two distinct ilvls across
    -- repeated queries (observed: 266, 276, and 279 for the same item),
    -- which breaks the "only two real ilvls per item" assumption the
    -- heuristic depended on. A wrong-but-confident answer, cached for the
    -- rest of the session, is worse than an honest "unknown" here.
    local actualItemLevel, isPreview, baseItemLevel = C_Item.GetDetailedItemLevelInfo(itemLink)
    if not actualItemLevel then
        Log.debug("TrackFromItemLevel: link=%s ilvl=nil (not cached yet)", tostring(itemLink))
        return nil
    end

    local inHeroicRange = actualItemLevel >= TIER_HEROIC_ILVL_MIN and actualItemLevel <= TIER_HEROIC_ILVL_MAX
    local inMythicRange = actualItemLevel >= TIER_MYTHIC_ILVL_MIN and actualItemLevel <= TIER_MYTHIC_ILVL_MAX

    -- Both ranges match inside the overlap band -- item level alone can't
    -- tell them apart there, so don't guess.
    local track
    if inHeroicRange and inMythicRange then
        track = nil
    elseif inHeroicRange then
        track = "H"
    elseif inMythicRange then
        track = "M"
    end
    -- No "N" case here -- Normal's ilvl range isn't tracked (no data is
    -- exported for it anyway), and a low ilvl alone is too weak a signal
    -- to mean "Normal" specifically vs. an unrelated non-raid item. Real
    -- Normal drops are still caught via the difficulty-ID signals above
    -- (TrackFromItemLink's embedded instanceDifficultyID, or
    -- TrackFromInstance's live GetInstanceInfo()), both now mapped
    -- through RAID_DIFFICULTY_TRACK[14] = "N".

    Log.debug(
        "TrackFromItemLevel: link=%s ilvl=%s isPreview=%s baseItemLevel=%s inHeroicRange=%s inMythicRange=%s -> %s",
        tostring(itemLink), tostring(actualItemLevel), tostring(isPreview), tostring(baseItemLevel),
        tostring(inHeroicRange), tostring(inMythicRange), tostring(track))
    return track
end

local function TrackFromInstance()
    local _, instanceType, difficultyID = GetInstanceInfo()
    local track = (instanceType == "raid") and RAID_DIFFICULTY_TRACK[difficultyID] or nil
    Log.debug("TrackFromInstance: instanceType=%s difficultyID=%s -> %s",
        tostring(instanceType), tostring(difficultyID), tostring(track))
    return track
end

-- Link-only track detection, no live-instance fallback -- used to interpret
-- a *stored* award link (Data/db.lua's RCPL_DB.awarded), where falling back
-- to GetInstanceInfo() would wrongly describe a past award using whatever
-- raid difficulty happens to be live right now.
local function TrackFromLinkOnly(itemLink)
    return TrackFromItemLink(itemLink) or TrackFromItemLevel(itemLink)
end

local function CurrentTrack(itemLink)
    local track = TrackFromLinkOnly(itemLink) or TrackFromInstance()
    Log.debug("CurrentTrack: link=%s -> %s", tostring(itemLink), tostring(track))
    return track
end

-- N < H < M -- used to tell a same-or-better past award apart from one on a
-- strictly lower track than the current drop. N included now that
-- CurrentTrack/TrackFromLinkOnly can resolve "N" for a Normal item instead
-- of nil, so a past Normal award (or current Normal drop) still has a rank
-- to compare instead of erroring on a missing table entry.
local TRACK_RANK = { N = 0, H = 1, M = 2 }

-- Public wrapper so a caller that doesn't have a specific player in mind yet
-- (Modules/votingPriorityPanel.lua, to decide section order) can still
-- resolve "what track is this item" without duplicating the detection chain.
function RCPL_Data_CurrentTrack(itemLink)
    return CurrentTrack(itemLink)
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
        local awardedValue = type(awardsForItem) == "table" and (awardsForItem[playerName] or awardsForItem[baseName])
        if awardedValue then
            -- A dupe on a *lower* track than the current drop shouldn't
            -- hide this drop's own priority -- already having the Heroic
            -- version doesn't make a Mythic-track drop of the same item a
            -- non-issue. Only short-circuits to "Awarded" when both tracks
            -- are actually resolvable and the past award is the same track
            -- or better; an unknown track on either side keeps the old
            -- "any award at all counts" behavior rather than risk silently
            -- hiding a genuine dupe from council.
            local awardedTrack = type(awardedValue) == "string" and TrackFromLinkOnly(awardedValue)
            local dropTrack = awardedTrack and CurrentTrack(itemLink)
            if not awardedTrack or not dropTrack or TRACK_RANK[awardedTrack] >= TRACK_RANK[dropTrack] then
                return "Awarded", COLOR_GREY
            end
        end
    end

    -- Item-centric priority list (Layer 1) -- WGA Raid Hub exports a real
    -- ranking for every slot now, so this is checked ahead of the Layer 2
    -- per-player BiS fallback for every equipLoc, not just a subset.
    if type(RCPL_DB.priority) == "table" then
        local itemPriority = RCPL_DB.priority[tostring(itemID)]
        if type(itemPriority) == "table" then
            local track = CurrentTrack(itemLink)
            if not track then
                return "N/A (unknown raid difficulty)", COLOR_GREY
            end
            local priorityList = itemPriority[track]
            if type(priorityList) == "table" then
                -- Two passes rather than one combined check: an exact
                -- "Name-Realm" match must win over a same-character-name
                -- match on a *different* realm, no matter which one the
                -- list happens to rank higher. A single pass that accepted
                -- either condition at the first hit could return a
                -- same-named stranger's (higher) rank instead of this
                -- player's own (possibly much lower) one -- confirmed from
                -- a raider report: loot frame showed "Prio: 3rd" while the
                -- real entry for that exact Name-Realm was 14th, because a
                -- different-realm namesake ranked 3rd matched first.
                for rank, name in ipairs(priorityList) do
                    if name == playerName or name == baseName then
                        return OrdinalLabel(rank), RankColor(rank), track, rank
                    end
                end
                -- No exact match anywhere in the list -- fall back to a
                -- bare-name match. This is what actually covers the
                -- connected-realm case (RCLootCouncil hands the voting/loot
                -- frame a bare name for anyone the game treats as the
                -- viewer's own realm), since a real connected-realm player
                -- has no exact "Name-Realm" entry to have matched above.
                for rank, name in ipairs(priorityList) do
                    if BaseName(name) == baseName then
                        return OrdinalLabel(rank), RankColor(rank), track, rank
                    end
                end
            end
            return "N/A", COLOR_GREY
        end
    end

    local coreKeys = CORE_EQUIPLOC[equipLoc]
    if not coreKeys then
        return "N/A", COLOR_GREY
    end

    local playerData = RCPL_DB.players[playerName] or RCPL_DB.players[baseName]
    if type(playerData) ~= "table" then
        -- Same connected-realm/bare-name mismatch as the priority list
        -- above -- RCPL_DB.players is always keyed by Name-Realm (see
        -- rclc_export.sql), so a bare roster name needs a base-name scan
        -- rather than a direct key lookup.
        for storedName, data in pairs(RCPL_DB.players) do
            if BaseName(storedName) == baseName then
                playerData = data
                break
            end
        end
    end
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
