-- Modules\lootFrame.lua
-- Hooks the RCLootCouncil loot frame to show priority text for the local player.

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCPLAddon = addon:GetModule("RCLootCouncil_PriorityLoot")
local RCPLootFrame = RCPLAddon:NewModule("RCPLootFrame", "AceHook-3.0", "AceTimer-3.0")

local overlayPool = {}

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

    local text, color = RCPL_Data_GetPlayerPriority(playerName, itemID, equipLoc, item.link)
    if text == "N/A" or text:find("wowaudit") then clearOverlay() return end

    if WowauditActive() then
        -- wowaudit already owns the inline itemLvl line -- fall back to our
        -- own separate line below the entry, same as always.
        local overlay = GetOrCreateOverlay(entry)
        overlay:SetTextColor(color.r, color.g, color.b)
        overlay:SetText("Prio: " .. text)
    else
        clearOverlay()
        if entry.itemLvl then
            local hex = string.format(
                "%02x%02x%02x",
                math.floor(color.r * 255 + 0.5),
                math.floor(color.g * 255 + 0.5),
                math.floor(color.b * 255 + 0.5)
            )
            -- entry.itemLvl's text is reset by RCLootCouncil's own native
            -- Update (which runs before this, since we hook the same method
            -- via SecureHook -- the original always executes first) every
            -- time this fires, so appending here can't compound across
            -- repeated calls the way it could if we read back our own
            -- previous appendage.
            local base = entry.itemLvl:GetText() or ""
            entry.itemLvl:SetText(base .. "  |cFF" .. hex .. "Prio: " .. text .. "|r")
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

        -- GetEntry can return an already-created entry on every refresh
        -- without that entry's own Update necessarily re-running, so relying
        -- on GetEntry alone (as before) is fine for our own dedicated
        -- overlay (a plain overwrite is always safe) but not for appending
        -- onto the shared itemLvl line -- that needs to run right after each
        -- native reset, so hook the entry's own Update once, the same point
        -- RCLootCouncil_wowaudit hooks for the same reason.
        if not self:IsHooked(entry, "Update") then
            self:SecureHook(entry, "Update", function(e)
                pcall(UpdateEntry, e, item, playerName)
            end)
        end
        pcall(UpdateEntry, entry, item, playerName)
    end)
end
