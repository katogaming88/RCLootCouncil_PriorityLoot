-- Modules\lootFrame.lua
-- Hooks the RCLootCouncil loot frame to show priority text for the local player.

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCPLAddon = addon:GetModule("RCLootCouncil_PriorityLoot")
local RCPLootFrame = RCPLAddon:NewModule("RCPLootFrame", "AceHook-3.0", "AceTimer-3.0")

local overlayPool = {}

-- Past this rank, the raider-facing overlay shows "On your wishlist" instead
-- of the exact number. A raider who sees "Prio: 8th" tends to just not
-- bother clicking Upgrade/OS/M+ at all -- and since a non-click reads to the
-- loot council as "doesn't want it right now", that can quietly hide them
-- from a deliberate override the council would otherwise have made (e.g.
-- giving it to a bigger upgrade for someone further down the list). Keeping
-- them informed without discouraging the click matters more than exact
-- transparency here. The officer voting frame (Modules/votingFrame.lua)
-- always shows the real rank regardless -- this only affects what raiders
-- see on their own loot roll.
local RAIDER_RANK_REVEAL_THRESHOLD = 5

local function GetItemIDFromLink(link)
    return tonumber((link or ""):match("item:(%d+):"))
end

-- RCLootCouncil_wowaudit appends its wishlist annotation onto the loot
-- entry's own itemLvl line (e.g. "279 Trinket (Intellect) - not on
-- wishlist") instead of adding a second FontString -- see that addon's
-- Modules/lootFrame.lua. When it's not installed, that space just sits
-- empty. Reuse it the same way instead of always adding an extra line below
-- the entry when nothing else wants it.
local function WowauditActive()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("RCLootCouncil_wowaudit")
    end
    return IsAddOnLoaded and IsAddOnLoaded("RCLootCouncil_wowaudit")
end

local function GetOrCreateOverlay(entry)
    local icon = entry.icon
    if overlayPool[icon] then return overlayPool[icon] end
    local fs = entry.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOP", entry.frame, "BOTTOM", 0, 12)
    fs:SetJustifyH("CENTER")
    fs:SetText("")
    overlayPool[icon] = fs
    return fs
end

local function UpdateEntry(entry, item, playerName)
    local icon = entry.icon
    if not icon then return end

    local function clearOverlay()
        local overlay = overlayPool[icon]
        if overlay then overlay:SetText("") end
    end

    if not item or not item.link then clearOverlay() return end

    local itemID = GetItemIDFromLink(item.link)
    if not itemID then clearOverlay() return end

    local equipLoc = item.equipLoc
    if not equipLoc or equipLoc == "" then clearOverlay() return end

    local text, color, track, rank = RCPL_Data_GetPlayerPriority(playerName, itemID, equipLoc, item.link)
    if text == "N/A" or text:find("wowaudit") then clearOverlay() return end

    -- track is only set when the rank came from the item-centric priority
    -- list (Layer 1) -- the per-player BiS fallback (Layer 2) isn't
    -- track-split, so there's nothing to show there.
    local trackLabel = RCPL_Data_TrackLabel(track)
    local trackSuffix = trackLabel and (" (" .. trackLabel .. ")") or ""

    local displayText, displayColor
    if rank and rank > RAIDER_RANK_REVEAL_THRESHOLD then
        -- Rank number is hidden past the threshold, but the difficulty is
        -- still useful context on its own -- a raider deciding whether to
        -- click Upgrade/OS/M+ cares whether this is the Heroic or Mythic
        -- drop even when they don't need their exact rank.
        displayText = "On your wishlist" .. trackSuffix
        displayColor = { r = 1, g = 1, b = 1 }
    else
        displayText = "Prio: " .. text .. trackSuffix
        displayColor = color
    end

    if WowauditActive() then
        -- wowaudit already owns the inline itemLvl line -- fall back to our
        -- own separate line below the entry, same as always.
        local overlay = GetOrCreateOverlay(entry)
        overlay:SetTextColor(displayColor.r, displayColor.g, displayColor.b)
        overlay:SetText(displayText)
    else
        clearOverlay()
        if entry.itemLvl then
            local hex = string.format(
                "%02x%02x%02x",
                math.floor(displayColor.r * 255 + 0.5),
                math.floor(displayColor.g * 255 + 0.5),
                math.floor(displayColor.b * 255 + 0.5)
            )
            -- entry.itemLvl's text is reset by RCLootCouncil's own native
            -- Update (which runs before this, since we hook the same method
            -- via SecureHook -- the original always executes first) every
            -- time this fires, so appending here can't compound across
            -- repeated calls the way it could if we read back our own
            -- previous appendage.
            local base = entry.itemLvl:GetText() or ""
            entry.itemLvl:SetText(base .. "  |cFF" .. hex .. displayText .. "|r")
        end
    end
end

function RCPLootFrame:OnInitialize()
    local ok, rcLootFrame = pcall(function()
        return addon:GetModule("RCLootFrame")
    end)
    if not ok or not rcLootFrame then return end

    local playerName = UnitName("player")
    local realm = GetRealmName()
    if realm and realm ~= "" then playerName = playerName .. "-" .. realm end

    self:SecureHook(rcLootFrame.EntryManager, "GetEntry", function(em, item)
        local entry = em.entries[item]
        if type(entry) ~= "table" then return end

        -- Appending onto the shared itemLvl line needs to run right after
        -- each native text reset, so hook the entry's own Update once, the
        -- same point RCLootCouncil_wowaudit hooks for the same reason --
        -- rather than calling UpdateEntry here in the GetEntry hook itself.
        --
        -- EntryManager:GetEntry's "restored" branch (reusing a pooled entry)
        -- calls entry:Update(item) *inside* the original GetEntry -- for an
        -- already-hooked entry that already triggers this same Update hook
        -- during this very GetEntry call, so calling UpdateEntry a second
        -- time here unconditionally would append the priority text twice
        -- onto the one native reset (and again on every subsequent refresh,
        -- e.g. clicking Upgrade/Catalyst/Pass, compounding further). Only
        -- call it directly the one time we attach the hook, to cover a
        -- brand-new entry (GetNewEntry/GetRollEntry) whose own internal
        -- Update(item) call already ran *before* we could hook it.
        if not self:IsHooked(entry, "Update") then
            self:SecureHook(entry, "Update", function(e)
                pcall(UpdateEntry, e, item, playerName)
            end)
            pcall(UpdateEntry, entry, item, playerName)
        end
    end)
end
