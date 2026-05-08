-- Modules/log.lua
-- Centralised logging for RCLootCouncil_PriorityLoot.
--
-- API:
--   RCPL_Log.debug(fmt, ...)  -- only emitted to chat when RCLPriorityDB.debug = true
--   RCPL_Log.info(fmt, ...)
--   RCPL_Log.warn(fmt, ...)
--   RCPL_Log.error(fmt, ...)
--
-- Every call records into an in-memory ring buffer regardless of debug state,
-- so /rcpl log show can replay the recent history even when debug is off.
-- Entries are volatile; the buffer resets on /reload.
--
-- Persisted state lives in RCLPriorityDB.debug (boolean) and is toggled by
-- /rcpl debug. Defaults to false.

local PREFIX        = "|cFF00FF00[RCPL]|r"
local MAX_ENTRIES   = 500
local LEVEL_COLORS  = {
    DEBUG = "|cFFAAAAAA",
    INFO  = "|cFF00FF00",
    WARN  = "|cFFFFCC00",
    ERROR = "|cFFFF4444",
}

local entries = {}

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
    return type(RCLPriorityDB) == "table" and RCLPriorityDB.debug == true
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
    if type(RCLPriorityDB) ~= "table" then RCLPriorityDB = {} end
    RCLPriorityDB.debug = (enabled and true) or false
    return RCLPriorityDB.debug
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

-- Opens an AceGUI window with the full log when AceGUI is available;
-- falls back to a chat dump otherwise. Uses plain text (no colour codes)
-- inside the edit box so the contents are easy to copy and paste.
function Log.Show()
    local ok, AceGUI = pcall(function() return LibStub("AceGUI-3.0", true) end)
    if not ok or not AceGUI then
        Log.DumpToChat()
        return
    end

    local frame = AceGUI:Create("Frame")
    frame:SetTitle("RCLootCouncil_PriorityLoot Log (" .. #entries .. " entries)")
    frame:SetLayout("Fill")
    frame:SetWidth(640)
    frame:SetHeight(420)

    local box = AceGUI:Create("MultiLineEditBox")
    box:SetLabel("")
    box:DisableButton(true)

    local lines = {}
    for i, e in ipairs(entries) do
        lines[i] = string.format("[%s] [%s] %s",
            date("%H:%M:%S", e.ts), e.level, e.message)
    end
    box:SetText(table.concat(lines, "\n"))
    frame:AddChild(box)
end

_G.RCPL_Log = Log
