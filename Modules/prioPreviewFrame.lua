-- Modules/prioPreviewFrame.lua
-- Scrollable popup showing imported priority data.  Opened via /rcpl prio.

local LINE_H     = 20   -- px per line for GameFontNormal
local CONTENT_W  = 500  -- inner text width (frame 560 - margins)
local PAD        = 4

local frame

-- Populate is forward-declared so the GET_ITEM_INFO_RECEIVED handler (wired
-- up in Build(), which runs before Populate's own definition below) can call
-- it once a pending item's name actually resolves.
local Populate

-- itemIDs currently shown as "Item #<id>" because GetItemInfo(itemID)
-- returned nil the moment Populate() last ran -- the client caches item data
-- lazily and fetches it asynchronously, so a not-yet-seen item resolves a
-- moment later rather than never. Re-populate when one arrives instead of
-- leaving the fallback stuck until the window happens to be reopened.
local pendingItemIDs = {}

-- ── Frame construction ────────────────────────────────────────────────────────

local function Build()
    frame = CreateFrame("Frame", "RCPLPrioPreviewFrame", UIParent, "BackdropTemplate")
    frame:SetSize(560, 540)
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
    tinsert(UISpecialFrames, "RCPLPrioPreviewFrame")

    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:SetScript("OnEvent", function(_, event, itemID, success)
        if event == "GET_ITEM_INFO_RECEIVED" and success and pendingItemIDs[itemID] and frame:IsShown() then
            Populate()
        end
    end)

    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleText:SetPoint("TOP", 0, -14)
    titleText:SetText("RCLootCouncil Priority Data")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sub:SetPoint("TOP", titleText, "BOTTOM", 0, -4)
    frame.subtitle = sub

    -- Scroll frame (provides scrollbar via template)
    local scrollFrame = CreateFrame("ScrollFrame", "RCPLPrioScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     12,  -52)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30,  12)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur      = self:GetVerticalScroll()
        local maxScroll = math.max(0, frame.content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * LINE_H * 3)))
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
        local fs = frame.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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

-- WoW inline color codes are |cAARRGGBB -- alpha then RGB, all hex.
-- RCPL_Data_RankColor (Data/db.lua) returns 0-1 floats; convert once per use.
local function ColorHex(color)
    return string.format(
        "%02x%02x%02x",
        math.floor(color.r * 255 + 0.5),
        math.floor(color.g * 255 + 0.5),
        math.floor(color.b * 255 + 0.5)
    )
end

-- Players per row in a ranked list / roster grid -- short enough that a
-- Name-Realm entry plus its rank number never has to wrap mid-entry at the
-- window's content width, long enough that a full raid roster doesn't turn
-- into a wall of one-name-per-line scrolling. Lower than it'd need to be at
-- GameFontNormalSmall since GameFontNormal takes more horizontal space per
-- entry.
local PLAYERS_PER_ROW = 3

-- ── Populate ──────────────────────────────────────────────────────────────────

function Populate()
    -- Hide every pooled line first
    for _, fs in ipairs(frame.linePool) do fs:Hide() end
    wipe(pendingItemIDs)

    local lines = {}
    local function add(text, r, g, b, large)
        lines[#lines + 1] = { text = text or "", r = r, g = g, b = b, large = large }
    end
    local function sep()
        add("|cFF555555" .. string.rep("-", 48) .. "|r")
    end
    -- Lighter divider between items within the Priority Lists section --
    -- distinct from sep()'s heavier section-header rule so a long list of
    -- items still reads as one section, just visually chunked per item.
    local function itemDivider()
        add("|cFF3A3A3A" .. string.rep(". ", 24) .. "|r")
    end

    if type(RCPL_DB) ~= "table" then
        frame.subtitle:SetText("No data imported.")
        add("|cFFFF6666No priority data found.|r  Use /rcpl import to load data.")
    else
        local importedAt  = RCPL_DB.importedAt or "unknown"
        local priority    = type(RCPL_DB.priority) == "table" and RCPL_DB.priority or {}
        local players     = type(RCPL_DB.players)  == "table" and RCPL_DB.players  or {}

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

                -- priority[idStr] is { H = {...}, M = {...} } (track-split,
                -- #335) rather than a single flat list, since Heroic and
                -- Mythic priority for an item can genuinely differ.
                local TRACK_LABEL = { H = "Heroic", M = "Mythic" }
                for i, idStr in ipairs(sortedIDs) do
                    local tracks = priority[idStr]
                    local itemID = tonumber(idStr)
                    local name   = itemID and GetItemInfo(itemID)
                    if itemID and not name then
                        -- Not cached client-side yet -- kick off the async
                        -- fetch and remember to redraw once it lands.
                        pendingItemIDs[itemID] = true
                        if C_Item and C_Item.RequestLoadItemDataByID then
                            C_Item.RequestLoadItemDataByID(itemID)
                        end
                    end
                    local label  = name
                        and ("|cFFffd200" .. name .. "|r")
                        or  ("|cFF888888Item #" .. idStr .. "|r")

                    add("  " .. label)

                    for _, trackKey in ipairs({ "H", "M" }) do
                        local list = tracks[trackKey]
                        if type(list) == "table" and #list > 0 then
                            -- Larger + white rather than the body's grey so the
                            -- difficulty heading doesn't recede behind the
                            -- ranked players it's labeling.
                            add("    " .. TRACK_LABEL[trackKey] .. ":", nil, nil, nil, true)
                            -- Each rank gets the same green/yellow/orange the
                            -- voting/loot frame overlay uses, so who's
                            -- actually top priority reads at a glance instead
                            -- of everyone blending into one flat grey line.
                            for rowStart = 1, #list, PLAYERS_PER_ROW do
                                local parts = {}
                                for rank = rowStart, math.min(rowStart + PLAYERS_PER_ROW - 1, #list) do
                                    local hex = ColorHex(RCPL_Data_RankColor(rank))
                                    parts[#parts + 1] = "|cFF" .. hex .. rank .. ". "
                                        .. ShortName(list[rank]) .. "|r"
                                end
                                add("      " .. table.concat(parts, "   "))
                            end
                        end
                    end

                    if i < #sortedIDs then itemDivider() end
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
                -- Grid instead of one name per line -- a full raid roster
                -- (20+) shouldn't need that much scrolling just to list names
                -- with no other information attached.
                for rowStart = 1, #names, PLAYERS_PER_ROW do
                    local parts = {}
                    for j = rowStart, math.min(rowStart + PLAYERS_PER_ROW - 1, #names) do
                        parts[#parts + 1] = names[j]
                    end
                    add("  |cFFCCCCCC" .. table.concat(parts, "   ") .. "|r")
                end
            end
        end
    end

    -- Layout each line top-to-bottom, advancing by actual rendered height
    -- so wrapped priority lines don't overlap the next row.
    local y = -PAD
    for i, lineData in ipairs(lines) do
        local fs = GetLine(i)
        fs:SetFontObject(lineData.large and "GameFontNormalLarge" or "GameFontNormal")
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", frame.content, "TOPLEFT", PAD, y)
        fs:SetText(lineData.text)
        if lineData.r then
            fs:SetTextColor(lineData.r, lineData.g, lineData.b)
        else
            fs:SetTextColor(1, 1, 1)
        end
        fs:Show()
        y = y - math.max(LINE_H, fs:GetStringHeight())
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
