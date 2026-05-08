-- spec/log_spec.lua
--
-- Coverage for Modules/log.lua. Exercises:
--   * level dispatch (debug / info / warn / error)
--   * format-string handling (and graceful failure when args do not match)
--   * ring buffer cap (MAX_ENTRIES = 500)
--   * RCLPriorityDB.debug gating: debug() always records, only mirrors to
--     chat when the flag is true
--   * persistent toggle round trip (SetDebug / ToggleDebug / IsDebugOn)
--   * Clear() empties the buffer
--   * Show() falls back to DumpToChat when AceGUI is unavailable

local mocks = require "spec.wow_mocks"

local function reloadLogger()
    -- log.lua sets _G.RCLPL_Log on every load; reset and reload to get a
    -- clean buffer between tests.
    _G.RCLPL_Log = nil
    dofile("Modules/log.lua")
    return _G.RCLPL_Log
end

describe("Modules/log.lua", function()
    local Log
    local printCalls

    before_each(function()
        mocks.resetSavedVars()
        _G.RCLPriorityDB = {}
        printCalls = mocks.capturePrint()
        Log = reloadLogger()
    end)

    -- ── Level dispatch ──────────────────────────────────────────────────────

    it("info, warn, and error always print to chat", function()
        Log.info("hello info")
        Log.warn("hello warn")
        Log.error("hello error")
        assert.equals(3, #printCalls)
    end)

    it("debug suppresses chat output when RCLPriorityDB.debug is false", function()
        _G.RCLPriorityDB.debug = false
        Log.debug("should not print")
        assert.equals(0, #printCalls)
    end)

    it("debug mirrors to chat when RCLPriorityDB.debug is true", function()
        _G.RCLPriorityDB.debug = true
        Log.debug("should print")
        assert.equals(1, #printCalls)
    end)

    it("debug records the entry even when chat output is suppressed", function()
        _G.RCLPriorityDB.debug = false
        Log.debug("captured silently")
        local entries = Log.GetEntries()
        assert.equals(1, #entries)
        assert.equals("DEBUG", entries[1].level)
        assert.equals("captured silently", entries[1].message)
    end)

    -- ── Format strings ──────────────────────────────────────────────────────

    it("formats a printf-style message when extra args are passed", function()
        Log.info("hello %s, you have %d items", "world", 7)
        local entries = Log.GetEntries()
        assert.equals("hello world, you have 7 items", entries[1].message)
    end)

    it("treats the first arg as a literal message when no args are passed", function()
        Log.info("100% literal")
        local entries = Log.GetEntries()
        assert.equals("100% literal", entries[1].message)
    end)

    it("falls back to the raw format string when string.format errors", function()
        -- Mismatched specifier vs args; must not throw.
        Log.info("expects a number: %d", "not-a-number")
        local entries = Log.GetEntries()
        assert.equals(1, #entries)
        assert.equals("expects a number: %d", entries[1].message)
    end)

    -- ── Ring buffer ─────────────────────────────────────────────────────────

    it("caps the ring buffer at 500 entries and drops the oldest", function()
        for i = 1, 501 do Log.info("entry %d", i) end
        local entries = Log.GetEntries()
        assert.equals(500, #entries)
        assert.equals("entry 2", entries[1].message)        -- oldest still present
        assert.equals("entry 501", entries[#entries].message)  -- newest at tail
    end)

    it("Clear empties the buffer", function()
        Log.info("a"); Log.info("b"); Log.info("c")
        assert.equals(3, #Log.GetEntries())
        Log.Clear()
        assert.equals(0, #Log.GetEntries())
    end)

    -- ── Debug toggle ────────────────────────────────────────────────────────

    it("SetDebug writes to RCLPriorityDB.debug and returns the new state", function()
        assert.is_true(Log.SetDebug(true))
        assert.is_true(_G.RCLPriorityDB.debug)
        assert.is_false(Log.SetDebug(false))
        assert.is_false(_G.RCLPriorityDB.debug)
    end)

    it("ToggleDebug flips RCLPriorityDB.debug each call", function()
        _G.RCLPriorityDB.debug = false
        assert.is_true(Log.ToggleDebug())
        assert.is_true(_G.RCLPriorityDB.debug)
        assert.is_false(Log.ToggleDebug())
        assert.is_false(_G.RCLPriorityDB.debug)
    end)

    it("IsDebugOn reflects the current persisted flag", function()
        _G.RCLPriorityDB.debug = true
        assert.is_true(Log.IsDebugOn())
        _G.RCLPriorityDB.debug = nil
        assert.is_false(Log.IsDebugOn())
    end)

    it("SetDebug initialises RCLPriorityDB if it was nil", function()
        _G.RCLPriorityDB = nil
        Log.SetDebug(true)
        assert.equals("table", type(_G.RCLPriorityDB))
        assert.is_true(_G.RCLPriorityDB.debug)
    end)

    -- ── Show fallback ───────────────────────────────────────────────────────

    it("Show falls back to DumpToChat when LibStub is absent", function()
        _G.LibStub = nil  -- guarantee fallback path
        Log.info("entry one")
        Log.info("entry two")
        printCalls = mocks.capturePrint()  -- reset so we only count Show output
        Log.Show()
        assert.is_true(#printCalls >= 3)  -- header + two entries
    end)

    it("DumpToChat reports an empty-buffer message when there is nothing to dump", function()
        Log.DumpToChat()
        assert.equals(1, #printCalls)
        assert.matches("no log entries", printCalls[1][1])
    end)
end)
