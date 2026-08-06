-- Modules\frameStyle.lua
-- Shared look for the addon's popup windows -- a solid near-black tooltip
-- body with a thin gold edge, plus a gold header strip/title -- so Options,
-- Priority Preview, Season Awards, Version Checker and the voting priority
-- panel all read as one consistent UI instead of each carrying its own copy
-- of the old tiled DialogFrame skin.

local BORDER_COLOR = { 0.71, 0.55, 0.15, 1 }
local HEADER_COLOR = { 0.71, 0.55, 0.15, 0.18 }
local TITLE_COLOR  = { 1, 0.82, 0 }

-- Applies the shared backdrop to any BackdropTemplate frame. Callers still
-- own size/point/strata/movability -- this only touches the skin.
function RCPL_ApplyPanelBackdrop(frame)
    frame:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.92)
    frame:SetBackdropBorderColor(unpack(BORDER_COLOR))
end

-- Gold-tinted strip behind a window's title, sized to fit just the title
-- (headerHeight) or the title plus a subtitle line beneath it.
function RCPL_CreateHeaderStrip(parent, headerHeight)
    local header = parent:CreateTexture(nil, "ARTWORK")
    header:SetPoint("TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", -4, -4)
    header:SetHeight(headerHeight or 34)
    header:SetColorTexture(unpack(HEADER_COLOR))
    return header
end

-- Gold GameFontNormalLarge title, centered at the top of the frame.
function RCPL_CreateStyledTitle(parent, text)
    local titleText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOP", 0, -12)
    titleText:SetText(text)
    titleText:SetTextColor(unpack(TITLE_COLOR))
    return titleText
end

local DISABLED_COLOR = { 0.4, 0.4, 0.4, 1 }

-- Flat dark button with a thin gold edge, matching the panel skin -- used in
-- place of UIPanelButtonTemplate's red/brown Blizzard button art, which
-- clashed against the new tooltip-style background. WHITE8x8 (solid white)
-- is tinted separately for fill vs. edge so the same texture serves both.
function RCPL_CreateStyledButton(parent, width, height, text)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop({
        bgFile   = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Buttons/WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    btn:SetBackdropBorderColor(unpack(BORDER_COLOR))

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetTextColor(unpack(TITLE_COLOR))
    if text then label:SetText(text) end
    btn.label = label

    function btn:SetText(newText) label:SetText(newText) end
    function btn:GetText() return label:GetText() end

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(unpack(TITLE_COLOR))
    highlight:SetAlpha(0.15)
    highlight:SetBlendMode("ADD")

    -- Text nudges down-right on press, same feedback UIPanelButtonTemplate
    -- gives, since the flat backdrop has no built-in pushed-state art.
    btn:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() then label:SetPoint("CENTER", 1, -1) end
    end)
    btn:SetScript("OnMouseUp", function() label:SetPoint("CENTER") end)
    btn:SetScript("OnDisable", function(self)
        self:SetBackdropBorderColor(unpack(DISABLED_COLOR))
        label:SetTextColor(unpack(DISABLED_COLOR))
    end)
    btn:SetScript("OnEnable", function(self)
        self:SetBackdropBorderColor(unpack(BORDER_COLOR))
        label:SetTextColor(unpack(TITLE_COLOR))
    end)

    return btn
end
