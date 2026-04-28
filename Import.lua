-- Import.lua
-- In-game import UI for RCLootCouncil_PriorityLoot.
-- Opens with /rclp import.  Officer pastes a Base64-encoded JSON string,
-- presses Confirm, and the data is decoded and stored into RCLPriorityDB.
--
-- Provides one public global:
--   RCLPL_ShowImportFrame()  — show (or re-show) the import window

-- ─── Pure-Lua Base64 decoder ──────────────────────────────────────────────────
-- WoW's sandbox provides no base64 library, so we implement one here.
-- Handles the standard alphabet (A-Z, a-z, 0-9, +, /) and optional '=' padding.

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

-- Build a reverse-lookup table: character → 0-based index.
local B64_DECODE = {}
for i = 1, #B64_CHARS do
    B64_DECODE[string.sub(B64_CHARS, i, i)] = i - 1
end

-- RCLPL_Base64Decode(str) → decoded string, or nil + error message
local function RCLPL_Base64Decode(str)
    -- Strip whitespace (copy-paste sometimes adds newlines).
    str = str:gsub("%s+", "")

    -- Strip trailing padding characters; we handle short blocks manually.
    str = str:gsub("=+$", "")

    local output = {}
    local len = #str

    for i = 1, len, 4 do
        local c1 = B64_DECODE[str:sub(i,   i)]
        local c2 = B64_DECODE[str:sub(i+1, i+1)]
        local c3 = B64_DECODE[str:sub(i+2, i+2)]
        local c4 = B64_DECODE[str:sub(i+3, i+3)]

        if c1 == nil or c2 == nil then
            return nil, "Invalid base64 character near position " .. i
        end

        -- First byte is always present when c1 and c2 are valid.
        local byte1 = bit.bor(bit.lshift(c1, 2), bit.rshift(c2, 4))
        output[#output + 1] = string.char(byte1)

        -- Second byte requires c3.
        if c3 ~= nil then
            local byte2 = bit.bor(bit.lshift(bit.band(c2, 0xF), 4), bit.rshift(c3, 2))
            output[#output + 1] = string.char(byte2)
        end

        -- Third byte requires c4.
        if c4 ~= nil then
            local byte3 = bit.bor(bit.lshift(bit.band(c3, 0x3), 6), c4)
            output[#output + 1] = string.char(byte3)
        end
    end

    return table.concat(output)
end

-- ─── Import frame construction ────────────────────────────────────────────────
-- Created once and re-used; hidden rather than destroyed on close.

local importFrame

local function CreateImportFrame()
    -- Outer window
    local f = CreateFrame("Frame", "RCLPL_ImportFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(500, 340)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    -- Title
    f.TitleText:SetText("RCLootCouncil – Import Priority Data")

    -- Instruction label
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", f.InsetBg, "TOPLEFT", 10, -8)
    label:SetPoint("TOPRIGHT", f.InsetBg, "TOPRIGHT", -10, -8)
    label:SetJustifyH("LEFT")
    label:SetText("Paste the Base64-encoded priority export string below, then click Confirm.")

    -- Scroll frame housing the edit box
    local scrollFrame = CreateFrame("ScrollFrame", "RCLPL_ImportScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",  f.InsetBg, "TOPLEFT",  10, -34)
    scrollFrame:SetPoint("BOTTOMRIGHT", f.InsetBg, "BOTTOMRIGHT", -28, 40)

    local editBox = CreateFrame("EditBox", "RCLPL_ImportEditBox", scrollFrame)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetWidth(scrollFrame:GetWidth())
    -- EditBox height is expanded to at least fill the scroll area; text grows it further.
    editBox:SetHeight(200)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnTextChanged", function(self)
        scrollFrame:UpdateScrollChildRect()
    end)

    scrollFrame:SetScrollChild(editBox)

    -- Status text (feedback after confirm)
    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("BOTTOMLEFT",  f.InsetBg, "BOTTOMLEFT",  10, 8)
    statusText:SetPoint("BOTTOMRIGHT", f.InsetBg, "BOTTOMRIGHT", -90, 8)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("")

    -- Confirm button
    local confirmBtn = CreateFrame("Button", "RCLPL_ImportConfirmBtn", f, "UIPanelButtonTemplate")
    confirmBtn:SetSize(80, 22)
    confirmBtn:SetPoint("BOTTOMRIGHT", f.InsetBg, "BOTTOMRIGHT", -4, 6)
    confirmBtn:SetText("Confirm")

    confirmBtn:SetScript("OnClick", function()
        local raw = editBox:GetText()
        if not raw or raw:match("^%s*$") then
            statusText:SetText("|cFFFF4444No data entered.|r")
            return
        end

        -- 1. Base64 decode
        local jsonStr, decodeErr = RCLPL_Base64Decode(raw)
        if not jsonStr then
            statusText:SetText("|cFFFF4444Decode error: " .. (decodeErr or "unknown") .. "|r")
            return
        end

        -- 2. JSON parse
        local ok, decoded = pcall(function() return LibRCLPJSON:decode(jsonStr) end)
        if not ok or type(decoded) ~= "table" then
            statusText:SetText("|cFFFF4444JSON parse error. Check your export string.|r")
            return
        end

        -- 3. Store data
        local playerCount, priorityCount = RCLPL_Data_SaveImportedData(decoded)
        if playerCount == 0 then
            statusText:SetText("|cFFFF4444Import succeeded but contained no player entries.|r")
        else
            local msg = string.format("Imported %d player(s) and %d priority item(s).",
                                      playerCount, priorityCount or 0)
            statusText:SetText("|cFF00FF00" .. msg .. "|r")
            print("|cFF00FF00[RCLootCouncil_PriorityLoot]|r " .. msg)
        end

        editBox:SetText("")
    end)

    -- Close button clears text and status to keep the frame clean on re-open.
    f:SetScript("OnHide", function()
        editBox:SetText("")
        statusText:SetText("")
        editBox:ClearFocus()
    end)

    -- Store references on the frame so we can reach them if needed later.
    f.editBox    = editBox
    f.statusText = statusText

    return f
end

-- ─── Public entry point ───────────────────────────────────────────────────────

function RCLPL_ShowImportFrame()
    if not importFrame then
        importFrame = CreateImportFrame()
    end

    if importFrame:IsShown() then
        importFrame:Hide()
    else
        importFrame:Show()
        -- Give focus so the officer can paste immediately.
        importFrame.editBox:SetFocus()
    end
end
