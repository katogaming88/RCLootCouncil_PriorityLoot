-- Modules/prioPreviewFrame.lua
-- Scrollable popup showing imported priority data.  Opened via /rcpl prio.
--
-- Full comparative rankings (who's #1, #2, #3 on every item) are gated to
-- council/ML -- RCLootCouncil already treats that as the "who's allowed to
-- see everyone's standing" boundary for its own voting frame (core.lua:
-- "only the right people may see the window during a raid since they
-- otherwise could watch the entire voting"), and handing every raider a
-- full browsable ranking for every item risks the same thing on a much
-- wider surface than the addon's other displays (the loot/voting frame
-- overlays only ever show a viewer their own rank, never anyone else's).
-- A non-privileged viewer instead sees only their own rank per item, same
-- shape as the WGA Raid Hub website's own wishlist rank pill.

local LINE_H     = 20   -- px per line for GameFontNormal
local CONTENT_W  = 500  -- inner text width (frame 560 - margins)
local PAD        = 4

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")

local frame

-- True for the master looter and current loot council members --
-- addon.isCouncil is populated from the ML's own council-roster broadcast
-- (RCLootCouncil's OnCouncilReceived), the same signal its own voting frame
-- gates on. Not cached: isCouncil can flip mid-session (leadership pass,
-- council roster resync), so this is read fresh every time the window
-- (re)populates rather than once at open.
local function IsPrivileged()
    return addon.isCouncil or addon.isMasterLooter
end

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
    RCPL_ApplyPanelBackdrop(frame)
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

    RCPL_CreateHeaderStrip(frame, 44)
    local titleText = RCPL_CreateStyledTitle(frame, "RCLootCouncil Priority Data")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sub:SetPoint("TOP", titleText, "BOTTOM", 0, -4)
    frame.subtitle = sub

    -- Search box -- lets a player narrow ~90+ items / dozens of names down to
    -- their own entries instead of scrolling the whole list (#49). Filters by
    -- item name or player name (not boss -- RCPL_DB.priority is keyed by item
    -- ID only, no boss/encounter association ships in the export).
    local searchBox = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    searchBox:SetHeight(20)
    searchBox:SetPoint("TOPLEFT",  sub, "BOTTOMLEFT",  0, -8)
    searchBox:SetPoint("TOPRIGHT", sub, "BOTTOMRIGHT", 0, -8)
    searchBox:SetBackdrop({
        bgFile   = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Buttons/WHITE8x8",
        edgeSize = 1,
    })
    searchBox:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
    searchBox:SetBackdropBorderColor(0.71, 0.55, 0.15, 0.6)
    searchBox:SetFontObject(ChatFontNormal)
    searchBox:SetAutoFocus(false)
    searchBox:SetTextInsets(6, 6, 0, 0)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)

    -- No native EditBox placeholder -- fake one with a FontString shown only
    -- while the box is both empty and unfocused.
    local hint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", searchBox, "LEFT", 6, 0)
    hint:SetText("Search item or player...")

    searchBox:SetScript("OnTextChanged", function(self)
        hint:SetShown(self:GetText() == "")
        Populate()
    end)
    searchBox:SetScript("OnEditFocusGained", function() hint:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function(self) hint:SetShown(self:GetText() == "") end)
    frame.searchBox = searchBox

    -- Scroll frame (provides scrollbar via template)
    local scrollFrame = CreateFrame("ScrollFrame", "RCPLPrioScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     searchBox, "BOTTOMLEFT",  0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame,     "BOTTOMRIGHT", -30, 12)
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

-- Whether needle (already lowercased) appears anywhere in haystack, treating
-- a nil/empty needle as "matches everything" so callers don't need a
-- separate branch for "no filter active".
local function Matches(needle, haystack)
    if needle == "" then return true end
    return haystack and haystack:lower():find(needle, 1, true) ~= nil
end

-- ── Populate ──────────────────────────────────────────────────────────────────

function Populate()
    -- Hide every pooled line first
    for _, fs in ipairs(frame.linePool) do fs:Hide() end
    wipe(pendingItemIDs)

    local filter = frame.searchBox and frame.searchBox:GetText():gsub("^%s+", ""):gsub("%s+$", ""):lower() or ""

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

    local privileged = IsPrivileged()

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

        -- Color the "Imported" timestamp by age so a stale-looking import is
        -- visible at a glance instead of silently trusted -- same
        -- green/yellow/orange scheme RCPL_Data_ImportAge() defines.
        local _, ageColor = RCPL_Data_ImportAge()
        local importedHex = ageColor and ColorHex(ageColor) or "ffffff"
        frame.subtitle:SetText(string.format(
            "Imported: |cFF%s%s|r  |  %d priority items  |  %d players%s",
            importedHex, importedAt, itemCount, playerCount,
            privileged and "" or "  |  |cFFAAAAAAyour standings only|r"
        ))

        if itemCount == 0 and playerCount == 0 then
            add("|cFFFF6666No data imported yet.|r  Use /rcpl import.")
        else
            local sortedIDs = {}
            for idStr in pairs(priority) do sortedIDs[#sortedIDs + 1] = idStr end
            table.sort(sortedIDs, function(a, b)
                return (tonumber(a) or 0) < (tonumber(b) or 0)
            end)

            -- Resolve every item's display name up front (kicking off the
            -- async fetch for anything not cached yet regardless of whether
            -- it currently matches the filter, so a not-yet-loaded item can
            -- still be found by name once GET_ITEM_INFO_RECEIVED redraws),
            -- then decide which items the filter actually keeps. Privileged
            -- (council/ML) search also matches on any ranked player's name --
            -- there's no boss/encounter field in the imported data to filter
            -- on (see the search box's own comment above). A non-privileged
            -- viewer never matches on someone else's name at all: that would
            -- let a search box double as "which items is X ranked on",
            -- leaking exactly the comparative info this gate exists to hide.
            local myName = not privileged and addon.Utils:UnitName("player") or nil
            local itemNames, matchedIDs, myRank = {}, {}, {}
            for _, idStr in ipairs(sortedIDs) do
                local tracks = priority[idStr]
                local itemID = tonumber(idStr)
                local name   = itemID and GetItemInfo(itemID)
                if itemID and not name then
                    pendingItemIDs[itemID] = true
                    if C_Item and C_Item.RequestLoadItemDataByID then
                        C_Item.RequestLoadItemDataByID(itemID)
                    end
                end
                itemNames[idStr] = name

                local matches = Matches(filter, name) or Matches(filter, idStr)
                if not matches and privileged then
                    for _, trackKey in ipairs({ "H", "M" }) do
                        local list = tracks[trackKey]
                        if type(list) == "table" then
                            for _, playerName in ipairs(list) do
                                if Matches(filter, playerName) then
                                    matches = true
                                    break
                                end
                            end
                        end
                        if matches then break end
                    end
                end

                if not privileged then
                    local ranks = {}
                    for _, trackKey in ipairs({ "H", "M" }) do
                        local list = tracks[trackKey]
                        if type(list) == "table" then
                            for rank, playerName in ipairs(list) do
                                if playerName == myName then
                                    ranks[trackKey] = rank
                                    break
                                end
                            end
                        end
                    end
                    myRank[idStr] = ranks
                    -- Unfiltered view only ever shows items the viewer is
                    -- actually ranked on -- otherwise every raider's default
                    -- "/rcpl prio" is the full item catalog, one "not ranked"
                    -- line each. An explicit search still surfaces a
                    -- name/ID match even when unranked (see the render loop
                    -- below), since someone deliberately looking an item up
                    -- wants an answer either way.
                    if filter == "" and not (ranks.H or ranks.M) then
                        matches = false
                    end
                end

                if matches then matchedIDs[#matchedIDs + 1] = idStr end
            end

            -- ── Player roster (filtered by name, computed before the header
            -- counts below need it) ─────────────────────────────────────────
            local matchedNames = {}
            for name in pairs(players) do
                if Matches(filter, name) then matchedNames[#matchedNames + 1] = name end
            end
            table.sort(matchedNames)

            if filter ~= "" and #matchedIDs == 0 and #matchedNames == 0 then
                add("|cFFFF6666No items or players match \"" .. filter .. "\".|r")
            elseif filter == "" and not privileged and #matchedIDs == 0 then
                add("|cFFAAAAAAYou have no priority items to show.|r")
            end

            -- ── Priority lists ────────────────────────────────────────────────
            if #matchedIDs > 0 then
                add("|cFFFFD100" .. (privileged and "Priority Lists" or "Your Priority Standings")
                    .. "  (" .. #matchedIDs .. (filter ~= "" and (" of " .. itemCount) or "") .. " items)|r")
                sep()

                -- priority[idStr] is { H = {...}, M = {...} } (track-split,
                -- #335) rather than a single flat list, since Heroic and
                -- Mythic priority for an item can genuinely differ.
                for i, idStr in ipairs(matchedIDs) do
                    local tracks = priority[idStr]
                    local name   = itemNames[idStr]
                    local label  = name
                        and ("|cFFffd200" .. name .. "|r")
                        or  ("|cFF888888Item #" .. idStr .. "|r")

                    add("  " .. label)

                    if privileged then
                        for _, trackKey in ipairs({ "H", "M" }) do
                            local list = tracks[trackKey]
                            if type(list) == "table" and #list > 0 then
                                -- Larger + white rather than the body's grey so the
                                -- difficulty heading doesn't recede behind the
                                -- ranked players it's labeling.
                                add("    " .. RCPL_Data_TrackLabel(trackKey) .. ":", nil, nil, nil, true)
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
                    else
                        -- Own rank only, one line per track the item has a
                        -- list for at all -- never another player's name or
                        -- position, only ever this viewer's own.
                        local ranks = myRank[idStr] or {}
                        for _, trackKey in ipairs({ "H", "M" }) do
                            local list = tracks[trackKey]
                            if type(list) == "table" and #list > 0 then
                                local rank = ranks[trackKey]
                                local rankText = rank
                                    and ("|cFF" .. ColorHex(RCPL_Data_RankColor(rank)) .. rank .. ".|r")
                                    or  "|cFF888888Not ranked|r"
                                add("    " .. RCPL_Data_TrackLabel(trackKey) .. ": " .. rankText)
                            end
                        end
                    end

                    if i < #matchedIDs then itemDivider() end
                end
                add("")
            end

            -- ── Player roster ─────────────────────────────────────────────────
            if #matchedNames > 0 then
                add("|cFFFFD100Players  (" .. #matchedNames .. (filter ~= "" and (" of " .. playerCount) or "")
                    .. ")|r")
                sep()

                local names = matchedNames
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
