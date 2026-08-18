QuickRestartUIKit = QuickRestartUIKit or {}

function QuickRestartUIKit.computeLayout(overrides)
    local textManager = getTextManager()
    local hgtSmall = textManager:getFontHeight(UIFont.Small)
    local hgtMedium = textManager:getFontHeight(UIFont.Medium)
    local gapTiny = math.ceil(hgtSmall * 0.25)

    local layout = {
        fontSmall = UIFont.Small,
        fontMedium = UIFont.Medium,
        hgtSmall = hgtSmall,
        hgtMedium = hgtMedium,
        buttonHeight = hgtSmall + 3 * 2,
        spacing = math.ceil(hgtSmall * 0.5),
        marginX = hgtSmall,
        marginY = math.ceil(hgtSmall * 0.75),
        buttonTextPad = hgtSmall * 2,
        gapTiny = gapTiny,
        gapSmall = gapTiny * 2,
        maxPanelWidth = getCore():getScreenWidth() * 0.35,
    }

    if type(overrides) == "table" then
        for key, value in pairs(overrides) do
            layout[key] = value
        end
    end

    return layout
end

function QuickRestartUIKit.captureButtonBaseAlpha(button)
    if not button or button.baseAlpha then
        return
    end

    button.baseAlpha = {
        background = button.backgroundColor and button.backgroundColor.a or 1,
        border = button.borderColor and button.borderColor.a or 1,
        text = button.textColor and button.textColor.a or 1,
        mouseOver = button.backgroundColorMouseOver and button.backgroundColorMouseOver.a or 1,
    }
end

function QuickRestartUIKit.applyAlphaToButton(button, progress)
    if not button or not button.baseAlpha then
        return
    end

    local base = button.baseAlpha
    if button.backgroundColor then
        button.backgroundColor.a = base.background * progress
    end
    if button.borderColor then
        button.borderColor.a = base.border * progress
    end
    if button.textColor then
        button.textColor.a = base.text * progress
    end
    if button.backgroundColorMouseOver then
        button.backgroundColorMouseOver.a = base.mouseOver * progress
    end
end

function QuickRestartUIKit.wrapText(text, font, width)
    local textManager = getTextManager()
    local lines = {}

    for paragraph in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
        if paragraph == "" then
            lines[#lines + 1] = ""
        else
            local current = ""
            for word in paragraph:gmatch("%S+") do
                local candidate = current == "" and word or (current .. " " .. word)
                if textManager:MeasureStringX(font, candidate) > width and current ~= "" then
                    lines[#lines + 1] = current
                    current = word
                else
                    current = candidate
                end
            end
            if current ~= "" then
                lines[#lines + 1] = current
            end
        end
    end

    return lines
end

function QuickRestartUIKit.addCloseButton(panel, layout, onClose)
    local closeSize = layout.hgtSmall
    local button = ISButton:new(panel.width - closeSize - layout.gapTiny, layout.gapTiny,
        closeSize, closeSize, "X", panel, function()
            if onClose then
                onClose()
            end
        end)
    button:initialise()
    button:instantiate()
    button.backgroundColor = {r = 0, g = 0, b = 0, a = 0}
    button.backgroundColorMouseOver = {r = 0.6, g = 0.15, b = 0.15, a = 0.8}
    button.borderColor = {r = 0.7, g = 0.7, b = 0.7, a = 0.3}
    panel:addChild(button)
    return button
end

QuickRestartUIKit.COLOR_WINDOW_BACKGROUND = {r = 0, g = 0, b = 0, a = 0.6}
QuickRestartUIKit.COLOR_WINDOW_BORDER = {r = 0.7, g = 0.7, b = 0.7, a = 0.5}
QuickRestartUIKit.COLOR_TRANSPARENT = {r = 0, g = 0, b = 0, a = 0}

local function copyColor(color, fallback)
    local source = color or fallback
    return {r = source.r, g = source.g, b = source.b, a = source.a}
end

function QuickRestartUIKit.newPanel(panelClass, x, y, width, height, background, border)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, panelClass)
    panelClass.__index = panelClass
    o.backgroundColor = copyColor(background, QuickRestartUIKit.COLOR_WINDOW_BACKGROUND)
    o.borderColor = copyColor(border, QuickRestartUIKit.COLOR_WINDOW_BORDER)
    return o
end

function QuickRestartUIKit.newWindowPanel(panelClass, x, y, width, height)
    return QuickRestartUIKit.newPanel(panelClass, x, y, width, height,
        QuickRestartUIKit.COLOR_WINDOW_BACKGROUND, QuickRestartUIKit.COLOR_WINDOW_BORDER)
end

return QuickRestartUIKit
