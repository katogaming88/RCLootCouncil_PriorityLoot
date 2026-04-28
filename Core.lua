-- Core.lua
-- Initializes RCLootCouncil_PriorityLoot and registers slash commands.
-- All other files expose global RCLPL_* functions that this file calls.

local ADDON_NAME = "RCLootCouncil_PriorityLoot"

-- AceAddon-3.0 is embedded in RCLootCouncil; we inherit from its LibStub instance.
-- AceEvent-3.0 adds RegisterEvent / UnregisterEvent.
-- AceHook-3.0 adds SecureHook for non-destructive method interception.
local RCLPAddon = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceHook-3.0")

-- Expose the addon object as a global so DoCellUpdate callbacks (which WoW calls
-- by name string) can reach SetCellPriority and so other addon files can store
-- state on a shared object.  All globals are prefixed RCLPL_ per project convention.
RCLootCouncil_PriorityLoot = RCLPAddon

-- OnInitialize fires when the addon is first loaded, before any login events.
-- Ensure SavedVariables have a valid skeleton so Data.lua never has to nil-check deeply.
function RCLPAddon:OnInitialize()
    if type(RCLPriorityDB) ~= "table" then
        RCLPriorityDB = {}
    end
    if type(RCLPriorityDB.players) ~= "table" then
        RCLPriorityDB.players = {}
    end
    if type(RCLPriorityDB.priority) ~= "table" then
        RCLPriorityDB.priority = {}
    end
end

-- OnEnable fires after OnInitialize. We defer further setup to PLAYER_LOGIN so
-- that all other addons (including RCLootCouncil) have finished loading.
function RCLPAddon:OnEnable()
    self:RegisterEvent("PLAYER_LOGIN", "OnPlayerLogin")
end

-- Called on PLAYER_LOGIN: verify RCLootCouncil exists, then wire up hooks.
-- If RCLootCouncil is missing we print one warning and do nothing else.
function RCLPAddon:OnPlayerLogin()
    -- pcall guards against GetAddon() throwing when the addon is absent.
    local ok, rclc = pcall(function()
        return LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
    end)

    if not ok or not rclc then
        print("|cFFFF4444[RCLootCouncil_PriorityLoot]|r RCLootCouncil not found. Addon disabled.")
        return
    end

    -- Store the RCLootCouncil addon reference so UI.lua and LootFrame.lua can reach it
    -- via the shared global RCLootCouncil_PriorityLoot.rclc.
    self.rclc = rclc

    -- Wire up the officer voting-frame column (UI.lua).
    RCLPL_UI_Setup(self)

    -- Wire up the raider loot-frame priority display (LootFrame.lua).
    RCLPL_LootFrame_Setup(self)
end

-- ─── Slash commands ───────────────────────────────────────────────────────────
-- /rclp import  — open the in-game import window
-- /rclp reset   — wipe all stored priority data from SavedVariables
-- /rclp         — print usage

SLASH_RCLP1 = "/rclp"
SlashCmdList["RCLP"] = function(input)
    local cmd = strtrim(input or "")
    if cmd == "import" then
        RCLPL_ShowImportFrame()
    elseif cmd == "reset" then
        RCLPL_Data_ResetData()
        print("|cFF00FF00[RCLootCouncil_PriorityLoot]|r All priority data cleared.")
    else
        print("|cFF00FF00[RCLootCouncil_PriorityLoot]|r Commands:")
        print("  /rclp import  — open the priority data import window")
        print("  /rclp reset   — clear all stored priority data")
    end
end
