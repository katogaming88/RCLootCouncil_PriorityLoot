-- UI.lua
-- Injects a "Priority" column into the RCLootCouncil officer voting frame.
-- Called once from Core.lua after PLAYER_LOGIN confirms RCLootCouncil is loaded.

-- ─── Module state ─────────────────────────────────────────────────────────────
local currentSession = 1

-- ─── DoCellUpdate callback ────────────────────────────────────────────────────

function RCLootCouncil_PriorityLoot.SetCellPriority(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
    if not fShow then
        frame.text:SetText("")
        return
    end

    if not data or not data[realrow] then
        frame.text:SetText("")
        return
    end

    if not data[realrow].cols then data[realrow].cols = {} end
    if not data[realrow].cols[column] then data[realrow].cols[column] = {} end

    local playerName = data[realrow].name
    local itemID, equipLoc = RCLPL_UI_GetCurrentItem()

    if not itemID or not playerName then
        frame.text:SetText("|cFF999999N/A|r")
        data[realrow].cols[column].value = 0
        return
    end

    local text, color = RCLPL_Data_GetPlayerPriority(playerName, itemID, equipLoc)

    local sortValue = 0
    local rankNum = tonumber(text:match("^(%d+)"))
    if rankNum then
        sortValue = 1000 - rankNum
    elseif text ~= "N/A" then
        local pct = tonumber(text:match("([%d%.]+)%%"))
        sortValue = pct or 0
    end

    data[realrow].cols[column].value = sortValue
    frame.text:SetTextColor(color.r, color.g, color.b)
    frame.text:SetText(text)
end

-- ─── Item resolution helper ───────────────────────────────────────────────────

function RCLPL_UI_GetCurrentItem()
    local rclc = RCLootCouncil_PriorityLoot.rclc
    if not rclc then return nil, nil end

    local ok, lootTable = pcall(function() return rclc:GetLootTable() end)
    if not ok or type(lootTable) ~= "table" then return nil, nil end

    local entry = lootTable[currentSession]
    if type(entry) ~= "table" then return nil, nil end

    local itemID = entry.itemID
    local eLoc   = entry.equipLoc

    if not eLoc and itemID then
        local _, _, _, _, _, _, _, _, retrievedLoc = GetItemInfo(itemID)
        eLoc = retrievedLoc
    end

    return itemID, eLoc
end

-- ─── Setup ────────────────────────────────────────────────────────────────────
-- Called once from Core.lua:OnPlayerLogin.

function RCLPL_UI_Setup(addon)
    local rclc = addon.rclc

    -- "votingframe" is the confirmed key in RCLootCouncil's defaultModules table.
    local ok, votingFrame = pcall(function()
        return rclc:GetActiveModule("votingframe")
    end)

    if not ok or not votingFrame then return end

    if votingFrame.rclplColumnInjected then return end
    votingFrame.rclplColumnInjected = true

    -- Inject just before the last column.  The ST is built from scrollCols in
    -- OnEnable → GetFrame(), so injecting here (before OnEnable) is sufficient
    -- for the column to appear without needing SetDisplayCols.
    local insertPos = math.max(1, #votingFrame.scrollCols)
    tinsert(votingFrame.scrollCols, insertPos, {
        name         = "Priority",
        width        = 60,
        align        = "CENTER",
        DoCellUpdate = RCLootCouncil_PriorityLoot.SetCellPriority,
        colName      = "rclpl_priority",
    })

    -- After OnEnable finishes, votingFrame.frame.st exists.  Call SetDisplayCols
    -- so the ST header updates, and widen the frame by the column width.
    -- Do NOT call votingFrame:GetFrame() here — it creates a named WoW frame and
    -- must only ever be called from within OnEnable itself.
    addon:SecureHook(votingFrame, "OnEnable", function()
        local f = votingFrame.frame
        if f and f.st then
            f.st:SetDisplayCols(votingFrame.scrollCols)
            f:SetWidth(f.st.frame:GetWidth() + 20)
        end
    end)

    -- Track the active session tab so GetCurrentItem() returns the right item.
    addon:SecureHook(votingFrame, "SwitchSession", function(_, s)
        currentSession = s or 1
    end)
end
