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

-- GetInstanceInfo() is how Data/db.lua determines the live raid track
-- (Heroic/Mythic) at lookup time -- no bonus-ID table to maintain, just the
-- standard Blizzard API. Defaults to "not in an instance" (nil, nil);
-- M.setInstanceInfo lets a spec put the mock player into a raid at a given
-- difficultyID (15 = Heroic, 16 = Mythic).
local _instanceType, _difficultyID = nil, nil
_G.GetInstanceInfo = function()
    return nil, _instanceType, _difficultyID
end
function M.setInstanceInfo(instanceType, difficultyID)
    _instanceType, _difficultyID = instanceType, difficultyID
end

-- ── Reset helpers ────────────────────────────────────────────────────────────

-- Wipe the SavedVariable between specs so tests are independent.
function M.resetSavedVars()
    _G.RCPL_DB = nil
    _instanceType, _difficultyID = nil, nil
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
