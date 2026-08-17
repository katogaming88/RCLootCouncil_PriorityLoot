-- Modules\bonusRollFlag.lua
-- Injects a "Bonus" column into the RCLootCouncil voting frame, right after
-- the Priority column, flagging any candidate who already used their weekly
-- Bonus Roll on the current boss -- so the loot council doesn't accidentally
-- double-award them the same boss's normal drop on top of an independent
-- bonus-roll shot they already had. Same load-order/hook pattern as
-- Modules/votingFrame.lua; see RCPL_Data_HasBonusRolled (Data/db.lua) for
-- why RCLootCouncil's own addon.nonTradeables is already scoped correctly
-- ("since the last ENCOUNTER_END") with no extra bookkeeping needed here.

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCVotingFrame = addon:GetModule("RCVotingFrame")
local RCPLAddon = addon:GetModule("RCLootCouncil_PriorityLoot")
local RCPLBonusRollFlag = RCPLAddon:NewModule("RCPLBonusRollFlag", "AceHook-3.0", "AceTimer-3.0")

function RCPLBonusRollFlag:OnInitialize()
    if not RCVotingFrame.scrollCols then
        return self:ScheduleTimer("OnInitialize", 0.5)
    end
    self:SecureHook(RCVotingFrame, "OnEnable", "InjectColumn")
end

function RCPLBonusRollFlag:InjectColumn()
    -- Guard against double injection if OnEnable is ever called more than
    -- once -- RCVotingFrame:AddColumn() errors on a duplicate colName rather
    -- than silently no-opping, unlike the old direct-scrollCols approach.
    if RCVotingFrame:GetColumnIndex("RCPL_bonusRoll") then return end

    local spec = {
        colName      = "RCPL_bonusRoll",
        name         = "Bonus",
        width        = 50,
        align        = "CENTER",
        DoCellUpdate = RCPLBonusRollFlag.SetCellBonusRoll,
    }

    -- Right after the Priority column so the two related signals sit
    -- together; falls back to the end of the list if that column is
    -- somehow missing (load order changed, or votingFrame.lua's own
    -- rescheduled OnInitialize hasn't injected yet). AddColumn() already
    -- refreshes the column layout/table view internally -- no separate
    -- f.UpdateSt() call needed, unlike the old manual scrollCols approach.
    if RCVotingFrame:GetColumnIndex("RCPL_priority") then
        RCVotingFrame:AddColumn(spec, "RCPL_priority", "after")
    else
        RCVotingFrame:AddColumn(spec)
    end
end

-- DoCellUpdate callback -- called by LibScrollingTable as a plain function.
function RCPLBonusRollFlag.SetCellBonusRoll(rowFrame, frame, data, cols, row, realrow, column, fShow, ...)
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
    local hasBonusRolled = RCPL_Data_HasBonusRolled(addon.nonTradeables, playerName)

    data[realrow].cols[column].value = hasBonusRolled and 1 or 0
    if hasBonusRolled then
        frame.text:SetTextColor(1, 1, 0)
        frame.text:SetText("BONUS")
    else
        frame.text:SetTextColor(0.6, 0.6, 0.6)
        frame.text:SetText("")
    end
end
