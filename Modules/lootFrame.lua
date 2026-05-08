-- Modules\lootFrame.lua
-- Hooks the RCLootCouncil loot frame to show priority text for the local player.

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCLPAddon = addon:GetModule("RCLootCouncil_PriorityLoot")
local RCLPLootFrame = RCLPAddon:NewModule("RCLPLootFrame", "AceHook-3.0", "AceTimer-3.0")

local overlayPool = {}

local function GetItemIDFromLink(link)
    return tonumber((link or ""):match("item:(%d+):"))
end

local function GetOrCreateOverlay(entry)
    local icon = entry.icon
    if overlayPool[icon] then return overlayPool[icon] end
    local fs = entry.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOP", entry.frame, "BOTTOM", 0, 12)
    fs:SetJustifyH("CENTER")
    fs:SetText("")
    overlayPool[icon] = fs
    return fs
end

local function UpdateEntry(entry, item, playerName)
    local icon = entry.icon
    if not icon then return end
    local overlay = GetOrCreateOverlay(entry)

    if not item or not item.link then overlay:SetText("") return end

    local itemID = GetItemIDFromLink(item.link)
    if not itemID then overlay:SetText("") return end

    local equipLoc = item.equipLoc
    if not equipLoc or equipLoc == "" then overlay:SetText("") return end

    local text, color = RCLPL_Data_GetPlayerPriority(playerName, itemID, equipLoc)
    if text == "N/A" or text:find("wowaudit") then overlay:SetText("") return end

    overlay:SetTextColor(color.r, color.g, color.b)
    overlay:SetText("Prio: " .. text)
end

function RCLPLootFrame:OnInitialize()
    local ok, rcLootFrame = pcall(function()
        return addon:GetModule("RCLootFrame")
    end)
    if not ok or not rcLootFrame then return end

    local playerName = UnitName("player")
    local realm = GetRealmName()
    if realm and realm ~= "" then playerName = playerName .. "-" .. realm end

    self:SecureHook(rcLootFrame.EntryManager, "GetEntry", function(em, item)
        local entry = em.entries[item]
        if type(entry) == "table" then
            pcall(UpdateEntry, entry, item, playerName)
        end
    end)
end
