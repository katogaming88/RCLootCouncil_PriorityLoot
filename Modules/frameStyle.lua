-- Modules\frameStyle.lua
-- Shared look for the addon's popup windows -- a solid near-black tooltip
-- body with a thin gold edge, plus a gold header strip/title -- so Options,
-- Priority Preview, Season Awards, Version Checker and the voting priority
-- panel all read as one consistent UI instead of each carrying its own copy
-- of the old tiled DialogFrame skin.

local BORDER_COLOR = { 0.71, 0.55, 0.15, 1 }
local HEADER_COLOR = { 0.71, 0.55, 0.15, 0.18 }
local TITLE_COLOR  = { 1, 0.82, 0 }

-- Window titles sit directly on the gold-tinted header strip (HEADER_COLOR),
-- not the plain dark panel body -- gold-on-gold-tint still clears WCAG's
-- luminance-only contrast math (they're different alpha/opacity, so the
-- strip stays dark), but reads as one flat hue at a glance. White text keeps
-- the title legible as text rather than a smear of gold, while borders and
-- buttons stay gold for the accent color.
local HEADING_COLOR = { 1, 1, 1 }

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

-- White GameFontNormalLarge title, centered at the top of the frame -- see
-- HEADING_COLOR above for why this isn't gold like the border/buttons.
function RCPL_CreateStyledTitle(parent, text)
    local titleText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOP", 0, -12)
    titleText:SetText(text)
    titleText:SetTextColor(unpack(HEADING_COLOR))
    return titleText
end

-- 0.55 rather than the visually "dimmer" 0.4 -- 0.4 only clears ~3.0:1
-- against the button's dark fill, below WCAG AA's 4.5:1 for text (WCAG 1.4.3
-- exempts disabled controls, but there's no reason not to clear it anyway).
-- 0.55 lands at ~5.2:1 against the button fill and ~6.3:1 against the panel
-- background, comfortably past AA with margin to spare.
local DISABLED_COLOR = { 0.55, 0.55, 0.55, 1 }

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
