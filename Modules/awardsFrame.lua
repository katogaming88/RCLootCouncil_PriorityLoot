-- Modules/awardsFrame.lua
-- Scrollable popup showing awards recorded this season.  Opened via /rcpl awards.

local LINE_H    = 16
local CONTENT_W = 440
local PAD       = 4

local frame
local checkedCount = 0
local Populate  -- forward declaration; assigned below so Build() can reference it

-- ── Frame construction ────────────────────────────────────────────────────────

local function Build()
    frame = CreateFrame("Frame", "RCPLAwardsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(500, 440)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleText:SetPoint("TOP", 0, -14)
    titleText:SetText("Priority Loot — Season Awards")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetPoint("TOP", titleText, "BOTTOM", 0, -4)
    frame.subtitle = sub

    local removeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    removeBtn:SetSize(140, 22)
    removeBtn:SetPoint("BOTTOM", 0, 10)
    removeBtn:SetText("Remove Award")
    removeBtn:SetEnabled(false)
    removeBtn:SetScript("OnClick", function()
        for _, cb in ipairs(frame.checkPool) do
            if cb:IsShown() and cb:GetChecked() then
                RCPL_Data_UnmarkAwarded(cb.playerName, cb.itemID)
            end
        end
        checkedCount = 0
        Populate()
    end)
    frame.removeBtn = removeBtn

    -- Scroll area leaves 40 px at the bottom for the button
    local scrollFrame = CreateFrame("ScrollFrame", "RCPLAwardsScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     12, -52)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 40)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        self:SetVerticalScroll(math.max(0, cur - delta * LINE_H * 3))
    end)
    frame.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(CONTENT_W)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    frame.content   = content
    frame.linePool  = {}
    frame.checkPool = {}
end

-- ── FontString pool (item headers / status text) ──────────────────────────────

local function GetLine(i)
    if not frame.linePool[i] then
        local fs = frame.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetJustifyH("LEFT")
        fs:SetWidth(CONTENT_W - PAD * 2)
        frame.linePool[i] = fs
    end
    return frame.linePool[i]
end

-- ── CheckButton pool (one row per awarded player) ─────────────────────────────

local function GetCheck(i)
    if not frame.checkPool[i] then
        local cb = CreateFrame("CheckButton", nil, frame.content, "UICheckButtonTemplate")
        cb:SetSize(16, 16)
        -- Label is a child of cb so Hide() on the button hides the label too
        local label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetJustifyH("LEFT")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        cb.label = label
        cb:SetScript("OnClick", function(self)
            checkedCount = checkedCount + (self:GetChecked() and 1 or -1)
            frame.removeBtn:SetEnabled(checkedCount > 0)
        end)
        frame.checkPool[i] = cb
    end
    return frame.checkPool[i]
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function ShortName(fullName)
    return (fullName:match("^([^%-]+)")) or fullName
end

-- ── Populate ──────────────────────────────────────────────────────────────────

Populate = function()
    for _, fs in ipairs(frame.linePool)  do fs:Hide() end
    for _, cb in ipairs(frame.checkPool) do cb:Hide() end
    checkedCount = 0
    frame.removeBtn:SetEnabled(false)

    -- rows = { {type="text", text=...} | {type="check", playerName=..., itemID=..., label=...} }
    local rows = {}
    local function addText(text) rows[#rows + 1] = { type = "text",  text = text or "" } end
    local function addCheck(playerName, itemID, label)
        rows[#rows + 1] = { type = "check", playerName = playerName, itemID = itemID, label = label }
    end
    local function sep() addText("|cFF555555" .. string.rep("-", 56) .. "|r") end

    local awarded = type(RCPL_DB) == "table"
        and type(RCPL_DB.awarded) == "table"
        and RCPL_DB.awarded or {}

    local totalAwards, itemCount = 0, 0
    for _, players in pairs(awarded) do
        itemCount = itemCount + 1
        for _ in pairs(players) do totalAwards = totalAwards + 1 end
    end

    if totalAwards == 0 then
        frame.subtitle:SetText("No awards recorded this season.")
        addText("|cFFAAAAAA(Awards are recorded automatically when the ML gives out loot.)|r")
        addText("|cFFAAAAAA(Use /rcpl award to record manually, or /rcpl reset to clear all data.)|r")
    else
        frame.subtitle:SetText(string.format(
            "%d award%s across %d item%s",
            totalAwards, totalAwards == 1 and "" or "s",
            itemCount,   itemCount   == 1 and "" or "s"
        ))
        sep()

        local sortedIDs = {}
        for itemID in pairs(awarded) do sortedIDs[#sortedIDs + 1] = itemID end
        table.sort(sortedIDs, function(a, b)
            return (tonumber(a) or 0) < (tonumber(b) or 0)
        end)

        for _, itemID in ipairs(sortedIDs) do
            local players = awarded[itemID]
            local names, link = {}, nil
            for playerName, storedLink in pairs(players) do
                names[#names + 1] = playerName
                if type(storedLink) == "string" then link = storedLink end
            end
            table.sort(names)

            addText("  " .. (link or ("|cFF888888item:" .. itemID .. "|r")))
            for _, playerName in ipairs(names) do
                addCheck(playerName, itemID, ShortName(playerName))
            end
        end
    end

    local lineIdx, checkIdx = 0, 0
    local y = -PAD
    for _, row in ipairs(rows) do
        if row.type == "text" then
            lineIdx = lineIdx + 1
            local fs = GetLine(lineIdx)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", frame.content, "TOPLEFT", PAD, y)
            fs:SetText(row.text)
            fs:SetTextColor(1, 1, 1)
            fs:Show()
        else
            checkIdx = checkIdx + 1
            local cb = GetCheck(checkIdx)
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", frame.content, "TOPLEFT", PAD + 16, y + 1)
            cb:SetChecked(false)
            cb.playerName = row.playerName
            cb.itemID     = row.itemID
            cb.label:SetText("|cFFCCCCCC" .. row.label .. "|r")
            cb:Show()
        end
        y = y - LINE_H
    end

    frame.content:SetHeight(math.max(1, -y + PAD))
    frame.scrollFrame:SetVerticalScroll(0)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function RCPL_ShowAwardsFrame()
    if not frame then Build() end
    if frame:IsShown() then
        frame:Hide()
    else
        Populate()
        frame:Show()
    end
end
