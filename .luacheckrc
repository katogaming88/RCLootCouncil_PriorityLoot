-- .luacheckrc for RCLootCouncil_PriorityLoot
--
-- Run locally:    luacheck .
-- Run in CI:      see .github/workflows/ci.yml

std = "lua51"

-- Tolerated style relaxations for a small WoW addon.
ignore = {
    "212",       -- Unused argument (DoCellUpdate, AceEvent callbacks have fixed signatures)
    "542",       -- Empty if branch (occasionally intentional in event guards)
    "611",       -- Line consists only of whitespace
    "612",       -- Line contains trailing whitespace
    "614",       -- Trailing whitespace in comment
}

max_line_length = 140

-- ── WoW API + Blizzard FrameXML globals --------------------------------------
read_globals = {
    -- Core types
    "bit", "string", "table", "math",

    -- Common helpers
    "tinsert", "tremove", "wipe", "strtrim", "strsplit", "strjoin",
    "strsub", "strlen", "strfind", "strmatch", "strgmatch", "strgsub",
    "strlower", "strupper", "format", "date", "time",

    -- Frame creation + display API
    "CreateFrame", "UIParent", "GameTooltip",

    -- Item / unit info
    "GetItemInfo", "GetItemInfoInstant", "Item",
    "UnitName", "UnitGUID", "UnitClass", "UnitRace", "UnitFactionGroup",
    "UnitIsPlayer", "UnitIsConnected", "UnitExists",

    -- Frame templates referenced by name
    "BasicFrameTemplateWithInset", "BackdropTemplate",
    "UIPanelScrollFrameTemplate", "UIPanelButtonTemplate", "UIPanelCloseButton",

    -- Font objects
    "ChatFontNormal", "GameFontNormal", "GameFontNormalSmall", "GameFontHighlight",

    -- LibStub + saved-variable wiring
    "LibStub",

    -- Project libs (declared in .toc, exposed as globals)
    "LibRCPLJSON",

    -- WoW-side helpers occasionally reached for
    "GetTime", "GetServerTime", "GetRealmName", "GetLocale",
    "IsInGuild", "IsInRaid", "IsInGroup",
    "GetNumGroupMembers",
    "C_Timer", "TooltipDataProcessor", "Settings", "Enum",
    "Mixin", "CreateFromMixins",
}

-- ── Globals defined by this addon --------------------------------------------
globals = {
    -- WoW slash command registration (writable in the WoW global env)
    "SLASH_RCPL1", "SlashCmdList",

    -- SavedVariable
    "RCPL_DB",

    -- Module handle (Core.lua sets this so Modules/*.lua can reach it)
    "RCLootCouncil_PriorityLoot",

    -- Public functions surfaced as globals (called from Core.lua slash handler
    -- and from each other across module boundaries)
    "RCPL_Data_SaveImportedData",
    "RCPL_Data_GetPlayerPriority",
    "RCPL_Data_ResetData",
    "RCPL_Data_MarkAwarded",
    "RCPL_Data_UnmarkAwarded",
    "RCPL_ShowImportFrame",
    "RCPL_ShowPrioPreview",
    "RCPL_ShowAwardsFrame",

    -- Centralised logger (Modules/log.lua); used across Core.lua and modules
    "RCPL_Log",
}

-- ── Per-file overrides --------------------------------------------------------
files["Libs/"] = {
    -- Vendored library: don't lint, the upstream owns it.
    ignore = { ".*" },
}

files["spec/"] = {
    -- Test files use busted's globals + may reach into the addon.
    std = "+busted",
    read_globals = {
        "describe", "it", "before_each", "after_each", "setup", "teardown",
        "assert", "spy", "stub", "mock", "pending", "finally",
    },
}

-- Defensive: if the v0.0.1 orphan files (Data.lua, Import.lua, UI.lua at root)
-- still exist on a branch where chore/cleanup-dead-code hasn't merged yet,
-- skip them - they're scheduled for deletion and not loaded by the .toc.
exclude_files = {
    "Data.lua",
    "Import.lua",
    "UI.lua",
    ".luarocks/",
    "lua_modules/",
}
