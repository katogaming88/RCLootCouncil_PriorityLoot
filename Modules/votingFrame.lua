-- Modules\votingFrame.lua
-- Injects a "Priority" column into the RCLootCouncil voting frame,
-- positioned immediately before the wowaudit Wishlist column.

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCVotingFrame = addon:GetModule("RCVotingFrame")
local RCPLAddon = addon:GetModule("RCLootCouncil_PriorityLoot")
local RCPLVotingFrame = RCPLAddon:NewModule("RCPLVotingFrame", "AceHook-3.0", "AceTimer-3.0", "AceEvent-3.0")

local currentSession = 1

function RCPLVotingFrame:OnInitialize()
    if not RCVotingFrame.scrollCols then
        return self:ScheduleTimer("OnInitialize", 0.5)
    end
    -- Inject after all other OnInitialize calls (including wowaudit) have run,
    -- so we can position relative to the wishlist column.
    self:SecureHook(RCVotingFrame, "OnEnable", "InjectColumn")
    self:RegisterMessage("RCSessionChangedPre", "OnSessionChanged")
end

function RCPLVotingFrame:InjectColumn()
    -- Guard against double injection if OnEnable is ever called more than once.
    for _, col in ipairs(RCVotingFrame.scrollCols) do
        if col.colName == "RCPL_priority" then return end
    end

    -- Insert before the wowaudit wishlist column; fall back to position 8
    -- (right after Diff) if wowaudit is not installed.
    local insertAt = 8
    for i, col in ipairs(RCVotingFrame.scrollCols) do
        if col.colName == "wishlist" then
            insertAt = i
            break
        end
    end

    tinsert(RCVotingFrame.scrollCols, insertAt, {
        name         = "Priority",
        width        = 60,
        align        = "CENTER",
        DoCellUpdate = RCPLVotingFrame.SetCellPriority,
        colName      = "RCPL_priority",
    })

    local f = RCVotingFrame.frame
    if f and f.UpdateSt then
        f.UpdateSt()
    end
end

function RCPLVotingFrame:OnSessionChanged(msg, s)
    currentSession = s or 1
end

-- DoCellUpdate callback — called by LibScrollingTable as a plain function.
function RCPLVotingFrame.SetCellPriority(rowFrame, frame, data, cols, row, realrow, column, fShow, ...)
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

    local lootTable = addon:GetLootTable()
    local entry = lootTable and lootTable[currentSession]
    if not entry or not playerName then
        frame.text:SetText("|cFF999999N/A|r")
        data[realrow].cols[column].value = 0
        return
    end

    local itemID  = entry.itemID
    local equipLoc = entry.equipLoc
    if not equipLoc and itemID then
        local _, _, _, _, _, _, _, _, loc = GetItemInfo(itemID)
        equipLoc = loc
    end

    if not itemID then
        frame.text:SetText("|cFF999999N/A|r")
        data[realrow].cols[column].value = 0
        return
    end

    local text, color = RCPL_Data_GetPlayerPriority(playerName, itemID, equipLoc)

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
