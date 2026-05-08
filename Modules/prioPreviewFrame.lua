-- Modules/prioPreviewFrame.lua
-- Scrollable popup showing imported priority data.  Opened via /rcpl prio.

local LINE_H     = 16   -- px per line for GameFontNormalSmall
local CONTENT_W  = 440  -- inner text width (frame 500 - margins)
local PAD        = 4

local frame

-- ── Frame construction ────────────────────────────────────────────────────────

local function Build()
    frame = CreateFrame("Frame", "RCLPPrioPreviewFrame", UIParent, "BackdropTemplate")
    frame:SetSize(500, 540)
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
    titleText:SetText("RCLootCouncil Priority Data")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetPoint("TOP", titleText, "BOTTOM", 0, -4)
    frame.subtitle = sub

    -- Scroll frame (provides scrollbar via template)
    local scrollFrame = CreateFrame("ScrollFrame", "RCLPPrioScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     12,  -52)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30,  12)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        self:SetVerticalScroll(math.max(0, cur - delta * LINE_H * 3))
    end)
    frame.scrollFrame = scrollFrame

    -- Content frame that grows to fit all rows
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(CONTENT_W)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    frame.content  = content
    frame.linePool = {}
end

-- ── FontString pool ───────────────────────────────────────────────────────────

local function GetLine(i)
    if not frame.linePool[i] then
        local fs = frame.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetJustifyH("LEFT")
        fs:SetWidth(CONTENT_W - PAD * 2)
        frame.linePool[i] = fs
    end
    return frame.linePool[i]
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function ShortName(fullName)
    return (fullName:match("^([^%-]+)")) or fullName
end

-- ── Populate ──────────────────────────────────────────────────────────────────

local function Populate()
    -- Hide every pooled line first
    for _, fs in ipairs(frame.linePool) do fs:Hide() end

    local lines = {}
    local function add(text, r, g, b)
        lines[#lines + 1] = { text = text or "", r = r, g = g, b = b }
    end
    local function sep()
        add("|cFF555555" .. string.rep("-", 56) .. "|r")
    end

    if type(RCLPriorityDB) ~= "table" then
        frame.subtitle:SetText("No data imported.")
        add("|cFFFF6666No priority data found.|r  Use /rcpl import to load data.")
    else
        local importedAt  = RCLPriorityDB.importedAt or "unknown"
        local priority    = type(RCLPriorityDB.priority) == "table" and RCLPriorityDB.priority or {}
        local players     = type(RCLPriorityDB.players)  == "table" and RCLPriorityDB.players  or {}

        local itemCount, playerCount = 0, 0
        for _ in pairs(priority) do itemCount   = itemCount   + 1 end
        for _ in pairs(players)  do playerCount = playerCount + 1 end

        frame.subtitle:SetText(string.format(
            "Imported: %s  |  %d priority items  |  %d players",
            importedAt, itemCount, playerCount
        ))

        if itemCount == 0 and playerCount == 0 then
            add("|cFFFF6666No data imported yet.|r  Use /rcpl import.")
        else
            -- ── Priority lists ────────────────────────────────────────────────
            if itemCount > 0 then
                add("|cFFFFD100Priority Lists  (" .. itemCount .. " items)|r")
                sep()

                local sortedIDs = {}
                for idStr in pairs(priority) do sortedIDs[#sortedIDs + 1] = idStr end
                table.sort(sortedIDs, function(a, b)
                    return (tonumber(a) or 0) < (tonumber(b) or 0)
                end)

                for _, idStr in ipairs(sortedIDs) do
                    local list   = priority[idStr]
                    local itemID = tonumber(idStr)
                    local name   = itemID and GetItemInfo(itemID)
                    local label  = name
                        and ("|cFFffd200" .. name .. "|r")
                        or  ("|cFF888888Item #" .. idStr .. "|r")

                    local parts = {}
                    for rank, playerName in ipairs(list) do
                        parts[#parts + 1] = rank .. ". " .. ShortName(playerName)
                    end
                    add("  " .. label .. "  |cFFCCCCCC" .. table.concat(parts, "   ") .. "|r")
                end
                add("")
            end

            -- ── Player roster ─────────────────────────────────────────────────
            if playerCount > 0 then
                add("|cFFFFD100Players  (" .. playerCount .. ")|r")
                sep()

                local names = {}
                for name in pairs(players) do names[#names + 1] = name end
                table.sort(names)
                for _, name in ipairs(names) do
                    add("  |cFFCCCCCC" .. name .. "|r")
                end
            end
        end
    end

    -- Layout each line top-to-bottom
    local y = -PAD
    for i, lineData in ipairs(lines) do
        local fs = GetLine(i)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", frame.content, "TOPLEFT", PAD, y)
        fs:SetText(lineData.text)
        if lineData.r then
            fs:SetTextColor(lineData.r, lineData.g, lineData.b)
        else
            fs:SetTextColor(1, 1, 1)
        end
        fs:Show()
        y = y - LINE_H
    end

    frame.content:SetHeight(math.max(1, -y + PAD))
    frame.scrollFrame:SetVerticalScroll(0)  -- start at top
end

-- ── Public API ────────────────────────────────────────────────────────────────

function RCPL_ShowPrioPreview()
    if not frame then Build() end
    if frame:IsShown() then
        frame:Hide()
    else
        Populate()
        frame:Show()
    end
end
