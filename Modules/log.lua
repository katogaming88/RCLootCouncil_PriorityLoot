-- Modules/log.lua
-- Centralised logging for RCLootCouncil_PriorityLoot.
--
-- API:
--   RCPL_Log.debug(fmt, ...)  -- only emitted to chat when RCPL_DB.debug = true
--   RCPL_Log.info(fmt, ...)
--   RCPL_Log.warn(fmt, ...)
--   RCPL_Log.error(fmt, ...)
--
-- Every call records into a ring buffer regardless of debug state, so
-- /rcpl log show can replay the recent history even when debug is off. The
-- buffer lives in RCPL_DB.log (SavedVariables), the same approach the base
-- RCLootCouncil addon's own Log class uses (Log:InitLogging binds its
-- buffer straight to a SavedVariables table) -- so entries survive /reload
-- and logout, and can be inspected after the fact without needing debug
-- mode turned on ahead of time, mid-raid, before the bug happens.
--
-- Persisted state lives in RCPL_DB.debug (boolean) and is toggled by
-- /rcpl debug. Defaults to false.

local PREFIX        = "|cFF00FF00[RCPL]|r"
local MAX_ENTRIES   = 500
local LEVEL_COLORS  = {
    DEBUG = "|cFFAAAAAA",
    INFO  = "|cFF00FF00",
    WARN  = "|cFFFFCC00",
    ERROR = "|cFFFF4444",
}

-- SavedVariables are already loaded into the RCPL_DB global by the time any
-- addon file executes, so this table reference is stable for the rest of
-- the session -- Core.lua's own OnInitialize does the same lazy-init dance
-- for RCPL_DB's other fields, just later (log.lua loads first, per the
-- .toc, since Core.lua wants RCPL_Log available immediately).
if type(RCPL_DB) ~= "table" then RCPL_DB = {} end
if type(RCPL_DB.log) ~= "table" then RCPL_DB.log = {} end
local entries = RCPL_DB.log

local Log = {}

local function formatMessage(fmt, ...)
    if select("#", ...) == 0 then return tostring(fmt) end
    local ok, result = pcall(string.format, fmt, ...)
    if ok then return result end
    return tostring(fmt)
end

local function record(level, message)
    local entry = { ts = (GetServerTime and GetServerTime()) or (time and time()) or 0,
                    level = level, message = message }
    entries[#entries + 1] = entry
    if #entries > MAX_ENTRIES then table.remove(entries, 1) end
    return entry
end

local function debugEnabled()
    return type(RCPL_DB) == "table" and RCPL_DB.debug == true
end

local function emit(level, fmt, ...)
    local message = formatMessage(fmt, ...)
    record(level, message)
    if level == "DEBUG" and not debugEnabled() then return end
    local color = LEVEL_COLORS[level] or "|cFFFFFFFF"
    print(PREFIX .. " " .. color .. "[" .. level .. "]|r " .. message)
end

function Log.debug(fmt, ...) emit("DEBUG", fmt, ...) end
function Log.info(fmt, ...)  emit("INFO",  fmt, ...) end
function Log.warn(fmt, ...)  emit("WARN",  fmt, ...) end
function Log.error(fmt, ...) emit("ERROR", fmt, ...) end

function Log.GetEntries()
    return entries
end

function Log.Clear()
    for i = #entries, 1, -1 do entries[i] = nil end
end

function Log.IsDebugOn()
    return debugEnabled()
end

function Log.SetDebug(enabled)
    if type(RCPL_DB) ~= "table" then RCPL_DB = {} end
    RCPL_DB.debug = (enabled and true) or false
    return RCPL_DB.debug
end

function Log.ToggleDebug()
    return Log.SetDebug(not debugEnabled())
end

local function formatLine(entry)
    local color = LEVEL_COLORS[entry.level] or "|cFFFFFFFF"
    return string.format("[%s] %s[%s]|r %s",
        date("%H:%M:%S", entry.ts), color, entry.level, entry.message)
end

function Log.DumpToChat(limit)
    if #entries == 0 then
        print(PREFIX .. " no log entries.")
        return
    end
    local start = 1
    if type(limit) == "number" and limit > 0 and limit < #entries then
        start = #entries - limit + 1
    end
    print(string.format("%s log dump (%d entries)", PREFIX, #entries - start + 1))
    for i = start, #entries do
        print(formatLine(entries[i]))
    end
end

local logFrame

-- Own BackdropTemplate frame using the same tooltip-style skin as every
-- other window in the addon (Modules/frameStyle.lua) -- previously this drew
-- an AceGUI Frame widget instead, which came with its own tiled DialogFrame
-- header art that didn't match, and (being a shared library instance)
-- couldn't be reskinned without risking whatever other addon's copy of
-- AceGUI happened to win the shared LibStub registration.
local function BuildLogFrame()
    local f = CreateFrame("Frame", "RCPLLogFrame", UIParent, "BackdropTemplate")
    f:SetSize(640, 420)
    f:SetPoint("CENTER")
    RCPL_ApplyPanelBackdrop(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f:Hide()
    tinsert(UISpecialFrames, "RCPLLogFrame")

    RCPL_CreateHeaderStrip(f, 34)
    f.title = RCPL_CreateStyledTitle(f, "RCLootCouncil_PriorityLoot Log")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local scrollFrame = CreateFrame("ScrollFrame", "RCPLLogScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -44)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 14)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxScroll = math.max(0, f.editBox:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * 16 * 3)))
    end)

    -- Plain text (no colour codes) in a selectable EditBox, same approach
    -- Modules/importFrame.lua uses, so the contents are easy to copy out.
    local editBox = CreateFrame("EditBox", "RCPLLogEditBox", scrollFrame)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetWidth(scrollFrame:GetWidth())
    editBox:SetHeight(1)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnTextChanged", function() scrollFrame:UpdateScrollChildRect() end)
    scrollFrame:SetScrollChild(editBox)
    f.editBox = editBox

    return f
end

-- Opens the log window. CreateFrame only fails to exist outside a live WoW
-- client (i.e. the busted test harness, which doesn't mock the frame API --
-- see spec/wow_mocks.lua), where a chat dump is the only option anyway.
function Log.Show()
    if type(CreateFrame) ~= "function" then
        Log.DumpToChat()
        return
    end

    if not logFrame then logFrame = BuildLogFrame() end

    local lines = {}
    for i, e in ipairs(entries) do
        lines[i] = string.format("[%s] [%s] %s",
            date("%H:%M:%S", e.ts), e.level, e.message)
    end
    logFrame.title:SetText("RCLootCouncil_PriorityLoot Log (" .. #entries .. " entries)")
    logFrame.editBox:SetText(table.concat(lines, "\n"))
    logFrame.editBox:SetHeight(math.max(1, #lines * 14))
    logFrame:Show()
end

_G.RCPL_Log = Log
