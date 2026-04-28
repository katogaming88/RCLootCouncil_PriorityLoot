-- UI.lua
-- Injects a "Priority" column into the RCLootCouncil officer voting frame.
-- Called once from Core.lua after PLAYER_LOGIN confirms RCLootCouncil is loaded.
--
-- Public globals provided:
--   RCLPL_UI_Setup(addon)               — wire up the voting frame
--   RCLootCouncil_PriorityLoot.SetCellPriority(...)  — DoCellUpdate callback

-- ─── Module state ─────────────────────────────────────────────────────────────
-- currentSession is updated whenever the officer switches items in the voting
-- frame; it indexes into the loot table to find the current item's ID / equipLoc.
local currentSession = 1

-- ─── DoCellUpdate callback ────────────────────────────────────────────────────
-- WoW / LibScrollingTable calls this for every visible cell in our column.
-- Signature is fixed by RCLootCouncil's scrolling-table library:
--   rowFrame  — the row's parent frame
--   frame     — the individual cell frame (has frame.text FontString)
--   data      — full scrolling-table data array
--   cols      — column definitions
--   row       — visible row index (may differ from realrow due to scrolling)
--   realrow   — index into data[] for the actual data entry
--   column    — column index
--   fShow     — boolean; false means the row is being hidden
--   table     — the scrolling-table object

function RCLootCouncil_PriorityLoot.SetCellPriority(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
    -- Hide the cell text when the row itself is hidden.
    if not fShow then
        frame.text:SetText("")
        return
    end

    -- Defensive guard: data or row slot may be absent during frame initialisation.
    if not data or not data[realrow] then
        frame.text:SetText("")
        return
    end

    -- Ensure the cols value sub-table exists so the library can use it for sorting.
    if not data[realrow].cols then data[realrow].cols = {} end
    if not data[realrow].cols[column] then data[realrow].cols[column] = {} end

    -- Player name in "Name-Realm" format, matching RCLPriorityDB keys.
    local playerName = data[realrow].name

    -- Resolve the current item from the RCLootCouncil loot table.
    local itemID, equipLoc = RCLPL_UI_GetCurrentItem()

    -- Default display when item or player data is unavailable.
    if not itemID or not playerName then
        frame.text:SetText("|cFF999999N/A|r")
        data[realrow].cols[column].value = 0
        return
    end

    local text, color = RCLPL_Data_GetPlayerPriority(playerName, itemID, equipLoc)

    -- Sort value: rank positions sort by inverse rank (1st = highest) so the
    -- priority list order is preserved; droptimizer % is used directly;
    -- "N/A" sorts to the bottom (0).
    local sortValue = 0
    local rankNum = tonumber(text:match("^(%d+)"))
    if rankNum then
        -- 1st → 999, 2nd → 998, … — any depth the priority list supports.
        sortValue = 1000 - rankNum
    elseif text ~= "N/A" then
        -- Droptimizer percentage: strip the leading '+' and trailing '%'.
        local pct = tonumber(text:match("([%d%.]+)%%"))
        sortValue = pct or 0
    end

    data[realrow].cols[column].value = sortValue

    -- Apply colour and text.
    frame.text:SetTextColor(color.r, color.g, color.b)
    frame.text:SetText(text)
end

-- ─── Item resolution helper ───────────────────────────────────────────────────
-- Returns itemID (number), equipLoc (string) for the currently displayed session,
-- or nil, nil if the loot table / session cannot be resolved.

function RCLPL_UI_GetCurrentItem()
    local rclc = RCLootCouncil_PriorityLoot.rclc
    if not rclc then return nil, nil end

    local ok, lootTable = pcall(function() return rclc:GetLootTable() end)
    if not ok or type(lootTable) ~= "table" then return nil, nil end

    local entry = lootTable[currentSession]
    if type(entry) ~= "table" then return nil, nil end

    local itemID  = entry.itemID
    local eLoc    = entry.equipLoc

    -- equipLoc may not be stored on the loot table entry in all RCLootCouncil
    -- versions; fall back to a live GetItemInfo() call if needed.
    if not eLoc and itemID then
        local _, _, _, _, _, _, _, _, retrievedLoc = GetItemInfo(itemID)
        eLoc = retrievedLoc
    end

    return itemID, eLoc
end

-- ─── Setup ────────────────────────────────────────────────────────────────────
-- Called once from Core.lua:OnPlayerLogin.
-- Injects the Priority column and hooks SwitchSession.

function RCLPL_UI_Setup(addon)
    local rclc = addon.rclc

    -- Retrieve the voting frame module.  GetActiveModule() returns nil when the
    -- officer does not have the module enabled; we must guard against that.
    local ok, votingFrame = pcall(function()
        return rclc:GetActiveModule("votingframe")
    end)

    if not ok or not votingFrame then
        -- Not an officer, or voting frame module unavailable — skip silently.
        return
    end

    -- ── Column injection ──────────────────────────────────────────────────────
    -- Guard against double-injection if Setup is somehow called twice.
    if votingFrame.rclplColumnInjected then return end
    votingFrame.rclplColumnInjected = true

    -- Determine where to insert: just before the last column (typically the
    -- Note column) to keep the layout natural.  If scrollCols is empty or has
    -- only one entry we fall back to appending.
    local insertPos = math.max(1, #votingFrame.scrollCols)
    tinsert(votingFrame.scrollCols, insertPos, {
        name         = "Priority",
        width        = 60,
        align        = "CENTER",
        DoCellUpdate = RCLootCouncil_PriorityLoot.SetCellPriority,
        colName      = "rclpl_priority",
    })

    -- Refresh the scrolling table if the frame is already visible.
    if votingFrame.frame and votingFrame.frame.st then
        votingFrame.frame.st:SetDisplayCols(votingFrame.scrollCols)
        -- Widen the outer window to accommodate the new column.
        local stWidth = votingFrame.frame.st.frame:GetWidth()
        votingFrame.frame:SetWidth(stWidth + 20)
    end

    -- ── Session tracking hook ─────────────────────────────────────────────────
    -- SwitchSession(frame, sessionIndex) is called whenever the officer clicks a
    -- different item tab.  We mirror the index so GetCurrentItem() stays correct.
    addon:SecureHook(votingFrame, "SwitchSession", function(_, s)
        currentSession = s or 1
    end)
end
