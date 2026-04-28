-- LootFrame.lua
-- Hooks the RCLootCouncil loot frame (the popup every raider sees) and appends
-- the local player's BiS priority or droptimizer % next to each item entry.
-- Mirrors the style wowaudit uses for droptimizer values: coloured text beneath
-- the item link line on the raider's frame.
--
-- This file is entirely non-destructive:
--   • If the hook target or module is absent the function returns silently.
--   • The original loot-frame behaviour is never altered.
--
-- Public global:
--   RCLPL_LootFrame_Setup(addon)  — called once from Core.lua:OnPlayerLogin

-- ─── Overlay frame pool ───────────────────────────────────────────────────────
-- We create one small FontString overlay per item button rather than embedding
-- text into RCLootCouncil's own frames.  The pool avoids repeated allocations
-- on successive loot events.

local overlayPool = {} -- keyed by itemButton frame reference

local function GetOrCreateOverlay(itemButton)
    if overlayPool[itemButton] then
        return overlayPool[itemButton]
    end

    -- Parent to the item button so the overlay moves with it automatically.
    local fs = itemButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- Position just below the item name / link line.
    fs:SetPoint("TOPLEFT",  itemButton, "BOTTOMLEFT",  4, 2)
    fs:SetPoint("TOPRIGHT", itemButton, "BOTTOMRIGHT", -4, 2)
    fs:SetJustifyH("LEFT")
    fs:SetText("")

    overlayPool[itemButton] = fs
    return fs
end

-- ─── Per-button update ────────────────────────────────────────────────────────
-- Called for each item button whenever the loot frame refreshes.
-- itemButton must expose .itemID and optionally .equipLoc.

local function UpdateItemButton(itemButton, playerName)
    local overlay = GetOrCreateOverlay(itemButton)

    local itemID = itemButton.itemID
    if not itemID then
        overlay:SetText("")
        return
    end

    -- equipLoc may be cached on the button by RCLootCouncil, or we look it up.
    local equipLoc = itemButton.equipLoc
    if not equipLoc then
        local _, _, _, _, _, _, _, _, eLoc = GetItemInfo(itemID)
        equipLoc = eLoc
    end

    if not equipLoc or equipLoc == "" then
        overlay:SetText("")
        return
    end

    local text, color = RCLPL_Data_GetPlayerPriority(playerName, itemID, equipLoc)

    -- Show nothing for N/A — avoids cluttering the frame with irrelevant data.
    if text == "N/A" then
        overlay:SetText("")
        return
    end

    overlay:SetTextColor(color.r, color.g, color.b)
    overlay:SetText(text)
end

-- ─── Loot-frame hook ─────────────────────────────────────────────────────────
-- RCLootCouncil's loot frame exposes an Update() (or equivalent) method that
-- is called whenever item data changes.  We hook it post-call to inject our
-- overlays after the frame has populated its buttons.
--
-- Because the loot frame internal API may vary between RCLootCouncil versions
-- we try several candidate method names in priority order.

local HOOK_CANDIDATES = { "Update", "UpdateItems", "Show", "OnShow" }

local function TryHookLootFrame(addon, lootFrame)
    -- Find the first method that exists on the loot frame object.
    local hookedMethod = nil
    for _, methodName in ipairs(HOOK_CANDIDATES) do
        if type(lootFrame[methodName]) == "function" then
            hookedMethod = methodName
            break
        end
    end

    if not hookedMethod then
        -- None of the candidate methods were found; we cannot hook safely.
        return false
    end

    -- Cache the player name once; it does not change during a session.
    local playerName = UnitName("player", true)  -- "Name-Realm" format

    addon:SecureHook(lootFrame, hookedMethod, function(self)
        -- lootFrame.itemButtons is the expected location of the button list in
        -- most RCLootCouncil versions.  Some versions use a frame table instead.
        local buttons = self.itemButtons or self.buttons
        if type(buttons) ~= "table" then return end

        for _, btn in ipairs(buttons) do
            if btn and btn:IsVisible() then
                local ok = pcall(UpdateItemButton, btn, playerName)
                -- Silently ignore per-button errors so one bad entry does not
                -- break the rest of the list.
                if not ok then
                    local overlay = overlayPool[btn]
                    if overlay then overlay:SetText("") end
                end
            end
        end
    end)

    return true
end

-- ─── Setup ────────────────────────────────────────────────────────────────────

function RCLPL_LootFrame_Setup(addon)
    local rclc = addon.rclc

    local ok, lootFrame = pcall(function()
        return rclc:GetActiveModule("lootframe")
    end)

    if not ok or not lootFrame then
        -- Loot frame module absent (officer-only build, or module disabled).
        -- Fail silently — raiders who don't install this addon see the default UI.
        return
    end

    TryHookLootFrame(addon, lootFrame)
end
