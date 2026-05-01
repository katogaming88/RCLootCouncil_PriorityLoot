-- spec/wow_mocks.lua
--
-- Minimal stubs for the slice of the WoW Lua environment that
-- Data/db.lua and other testable modules depend on.
--
-- Loaded by every spec via `require "spec.wow_mocks"`.
--
-- Keep this surface as small as possible.  Only stub what is actually
-- referenced by the code under test.  When a spec needs a richer mock
-- (e.g. CreateFrame), build it locally in that spec rather than
-- bloating the shared mock.

local M = {}

-- ── Globals that WoW exposes but standalone Lua 5.1 does not ────────────────

-- WoW exposes os.date as plain `date(...)`; the addon uses it for
-- the import timestamp.
_G.date = os.date

-- WoW's `bit` library is a built-in; LuaJIT and Lua 5.1 with luabitop
-- both expose it under the same name.  No-op stub if absent so specs
-- that don't exercise base64 still load cleanly.
if _G.bit == nil then
    local ok, lib = pcall(require, "bit")
    if ok then _G.bit = lib end
end

-- WoW global helpers
_G.tinsert = table.insert
_G.tremove = table.remove
_G.strtrim = function(s)
    return (s and s:gsub("^%s+", ""):gsub("%s+$", "")) or ""
end

-- ── Reset helpers ────────────────────────────────────────────────────────────

-- Wipe the SavedVariable between specs so tests are independent.
function M.resetSavedVars()
    _G.RCLPriorityDB = nil
end

-- Stub `print` so success/error chat output doesn't clutter spec output.
-- Returns the recorded calls so a spec can assert on them.
function M.capturePrint()
    local calls = {}
    _G.print = function(...)
        calls[#calls + 1] = { ... }
    end
    return calls
end

function M.restorePrint()
    _G.print = print  -- best-effort restore; busted resets globals between describes
end

-- Load the addon source files needed for unit testing.  Paths are
-- relative to the repo root; busted is run from there.
function M.loadAddonSources()
    -- Order mirrors the .toc load order, but only loads files that
    -- have no frame-creation side effects.
    dofile("Data/db.lua")
end

return M
