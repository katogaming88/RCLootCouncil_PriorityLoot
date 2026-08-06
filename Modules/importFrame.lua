-- Modules\importFrame.lua
-- In-game import UI. Opens with /rcpl import.

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local B64_DECODE = {}
for i = 1, #B64_CHARS do
    B64_DECODE[string.sub(B64_CHARS, i, i)] = i - 1
end

local function Base64Decode(str)
    str = str:gsub("%s+", ""):gsub("=+$", "")
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
        local byte1 = bit.bor(bit.lshift(c1, 2), bit.rshift(c2, 4))
        output[#output + 1] = string.char(byte1)
        if c3 ~= nil then
            local byte2 = bit.bor(bit.lshift(bit.band(c2, 0xF), 4), bit.rshift(c3, 2))
            output[#output + 1] = string.char(byte2)
        end
        if c4 ~= nil then
            local byte3 = bit.bor(bit.lshift(bit.band(c3, 0x3), 6), c4)
            output[#output + 1] = string.char(byte3)
        end
    end
    return table.concat(output)
end

local importFrame

-- SavedVariables only get flushed to disk on UI reload/logout -- until then,
-- a successful import lives in memory only, and a crash or /console-forced
-- close (or another /rcpl import that never gets confirmed) can lose it.
-- Prompt for a reload right after a successful import so the data is safely
-- on disk before the raid actually needs it. preferredIndex avoids fighting
-- other addons' popups for the same StaticPopup slot.
StaticPopupDialogs["RCPL_RELOAD_AFTER_IMPORT"] = {
    text = "Priority data imported.\nReload your UI now so it's saved to disk?",
    button1 = "Reload Now",
    button2 = "Later",
    OnAccept = function()
        if C_UI and C_UI.Reload then
            C_UI.Reload()
        else
            ReloadUI()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function CreateImportFrame()
    local f = CreateFrame("Frame", "RCPL_ImportFrame", UIParent, "BackdropTemplate")
    f:SetSize(500, 340)
    f:SetPoint("CENTER")
    RCPL_ApplyPanelBackdrop(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    tinsert(UISpecialFrames, "RCPL_ImportFrame")

    RCPL_CreateHeaderStrip(f, 34)
    RCPL_CreateStyledTitle(f, "RCLootCouncil - Import Priority Data")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT",  f, "TOPLEFT",  14, -44)
    label:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -44)
    label:SetJustifyH("LEFT")
    label:SetText("Paste the Base64-encoded priority export string below, then click Confirm.")

    local scrollFrame = CreateFrame("ScrollFrame", "RCPL_ImportScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     f, "TOPLEFT",     14, -68)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 40)

    local editBox = CreateFrame("EditBox", "RCPL_ImportEditBox", scrollFrame)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetWidth(scrollFrame:GetWidth())
    editBox:SetHeight(200)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnTextChanged",   function() scrollFrame:UpdateScrollChildRect() end)
    scrollFrame:SetScrollChild(editBox)

    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  14, 12)
    statusText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -100, 12)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("")

    local confirmBtn = RCPL_CreateStyledButton(f, 80, 22, "Confirm")
    confirmBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 10)

    confirmBtn:SetScript("OnClick", function()
        local raw = editBox:GetText()
        if not raw or raw:match("^%s*$") then
            statusText:SetText("|cFFFF4444No data entered.|r")
            return
        end

        local jsonStr, decodeErr = Base64Decode(raw)
        if not jsonStr then
            statusText:SetText("|cFFFF4444Decode error: " .. (decodeErr or "unknown") .. "|r")
            return
        end

        local ok, decoded = pcall(function() return LibRCPLJSON:decode(jsonStr) end)
        if not ok or type(decoded) ~= "table" then
            statusText:SetText("|cFFFF4444JSON parse error. Check your export string.|r")
            return
        end

        local playerCount, priorityCount = RCPL_Data_SaveImportedData(decoded)
        if playerCount == 0 then
            statusText:SetText("|cFFFF4444Import succeeded but contained no player entries.|r")
        else
            local msg = string.format("Imported %d player(s) and %d priority item(s).", playerCount, priorityCount or 0)
            statusText:SetText("|cFF00FF00" .. msg .. "|r")
            print("|cFF00FF00[RCLootCouncil_PriorityLoot]|r " .. msg)
            StaticPopup_Show("RCPL_RELOAD_AFTER_IMPORT")
        end

        editBox:SetText("")
    end)

    f:SetScript("OnHide", function()
        editBox:SetText("")
        statusText:SetText("")
        editBox:ClearFocus()
    end)

    f.editBox    = editBox
    f.statusText = statusText
    f:Hide()
    return f
end

function RCPL_ShowImportFrame()
    if not importFrame then importFrame = CreateImportFrame() end
    if importFrame:IsShown() then
        importFrame:Hide()
    else
        importFrame:Show()
        importFrame.editBox:SetFocus()
    end
end
