-- Modules\lootFrame.lua
-- Hooks the RCLootCouncil loot frame to show priority text for the local player.

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCLPAddon = addon:GetModule("RCLootCouncil_PriorityLoot")
local RCLPLootFrame = RCLPAddon:NewModule("RCLPLootFrame", "AceHook-3.0", "AceTimer-3.0")

local overlayPool = {}

local function GetOrCreateOverlay(itemButton)
    if overlayPool[itemButton] then return overlayPool[itemButton] end
    local fs = itemButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT",  itemButton, "BOTTOMLEFT",  4, 2)
    fs:SetPoint("TOPRIGHT", itemButton, "BOTTOMRIGHT", -4, 2)
    fs:SetJustifyH("LEFT")
    fs:SetText("")
    overlayPool[itemButton] = fs
    return fs
end

local function UpdateItemButton(itemButton, playerName)
    local overlay = GetOrCreateOverlay(itemButton)
    local itemID = itemButton.itemID
    if not itemID then overlay:SetText("") return end

    local equipLoc = itemButton.equipLoc
    if not equipLoc then
        local _, _, _, _, _, _, _, _, eLoc = GetItemInfo(itemID)
        equipLoc = eLoc
    end

    if not equipLoc or equipLoc == "" then overlay:SetText("") return end

    local text, color = RCLPL_Data_GetPlayerPriority(playerName, itemID, equipLoc)
    if text == "N/A" then overlay:SetText("") return end

    overlay:SetTextColor(color.r, color.g, color.b)
    overlay:SetText("Prio: " .. text)
end

local HOOK_CANDIDATES = { "Open", "Update", "UpdateItems", "Show", "OnShow", "Refresh" }

function RCLPLootFrame:OnInitialize()
    local ok, rcLootFrame = pcall(function()
        return addon:GetModule("RCLootFrame")
    end)
    if not ok or not rcLootFrame then return end

    local hookedMethod
    for _, name in ipairs(HOOK_CANDIDATES) do
        if type(rcLootFrame[name]) == "function" then
            hookedMethod = name
            break
        end
    end
    if not hookedMethod then return end

    local playerName = UnitName("player")

    self:SecureHook(rcLootFrame, hookedMethod, function(lf)
        local frame = lf.frame
        local buttons = lf.itemButtons or lf.buttons
                     or (frame and (frame.itemButtons or frame.buttons))
        if type(buttons) ~= "table" then return end
        for _, btn in ipairs(buttons) do
            if btn and btn:IsVisible() then
                local ok2 = pcall(UpdateItemButton, btn, playerName)
                if not ok2 then
                    local ov = overlayPool[btn]
                    if ov then ov:SetText("") end
                end
            end
        end
    end)
end
