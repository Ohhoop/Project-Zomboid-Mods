QuickRestartUI = QuickRestartUI or {}

QuickRestartPanel = ISPanel:derive("QuickRestartPanel")
QuickRestartTransitionOverlay = ISPanel:derive("QuickRestartTransitionOverlay")

local function computeLayout()
    local textManager = getTextManager()
    local hgtSmall = textManager:getFontHeight(UIFont.Small)
    local hgtMedium = textManager:getFontHeight(UIFont.Medium)
    return {
        fontSmall = UIFont.Small,
        fontMedium = UIFont.Medium,
        hgtSmall = hgtSmall,
        hgtMedium = hgtMedium,
        buttonHeight = hgtSmall + 3 * 2,
        spacing = math.ceil(hgtSmall * 0.5),
        marginX = hgtSmall,
        marginY = math.ceil(hgtSmall * 0.75),
        buttonTextPad = hgtSmall * 2,
        gapTiny = math.ceil(hgtSmall * 0.25),
        maxPanelWidth = getCore():getScreenWidth() * 0.35,
    }
end

local function resolveDeathButtonWidth()
    if not ISPostDeathUI or type(ISPostDeathUI.instance) ~= "table" then
        return nil
    end

    for _, deathUi in pairs(ISPostDeathUI.instance) do
        local button = deathUi and deathUi.buttonRespawn
        if button and button.getWidth then
            local ok, width = pcall(function()
                return button:getWidth()
            end)
            if ok and type(width) == "number" and width > 0 then
                return width
            end
        end
    end

    return nil
end

function QuickRestartPanel:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = {r=0, g=0, b=0, a=0.3}
    o.borderColor = {r=0, g=0, b=0, a=0}
    return o
end

function QuickRestartTransitionOverlay:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = {r=0, g=0, b=0, a=0}
    o.borderColor = {r=0, g=0, b=0, a=0}
    o.message = getText("UI_QuickRestart_Title") .. "..."
    o.currentAlpha = 1
    o.targetAlpha = 1
    o.fadeInStep = 1
    o.fadeOutStep = 0.3
    o.textAlphaScale = 0.92
    o.isClosing = false
    return o
end

function QuickRestartTransitionOverlay:prerender()
    self:setX(0)
    self:setY(0)

    local core = getCore()
    if core then
        self:setWidth(core:getScreenWidth())
        self:setHeight(core:getScreenHeight())
    end

    local current = tonumber(self.currentAlpha) or 0
    local target = tonumber(self.targetAlpha) or 0
    if current < target then
        current = math.min(target, current + self.fadeInStep)
    elseif current > target then
        current = math.max(target, current - self.fadeOutStep)
    end

    self.currentAlpha = current
    self.backgroundColor.a = current

    if self.isClosing and current <= 0.001 then
        self:setVisible(false)
        self:removeFromUIManager()
        QuickRestartUI.transitionOverlay = nil
        return
    end

    ISPanel.prerender(self)
end

function QuickRestartTransitionOverlay:render()
    ISPanel.render(self)

    local message = self.message
    if not message or message == "" then
        return
    end

    local font = UIFont.Medium
    local textManager = getTextManager()
    local textWidth = textManager:MeasureStringX(font, message)
    local textHeight = textManager:getFontHeight(font)
    local x = (self.width - textWidth) / 2
    local y = (self.height - textHeight) / 2

    self:drawText(message, x, y, 1, 1, 1, self.currentAlpha * self.textAlphaScale, font)
end

function QuickRestartPanel:createChildren()
    ISPanel.createChildren(self)

    self.layout = self.layout or computeLayout()
    local layout = self.layout
    local buttonWidth = self.buttonWidth or (self.width - layout.marginX * 2)
    local buttonHeight = layout.buttonHeight
    local spacing = layout.spacing
    local xCenter = (self.width - buttonWidth) / 2
    local yStart = layout.marginY + layout.hgtMedium + layout.spacing

    self.freshWorldEnabled = self.canUseFreshWorld and self.canUseFreshWorld() or false
    local charDataAvail = self.charDataAvail

    local freshEnabled = self.freshWorldEnabled and charDataAvail
    local sameEnabled = charDataAvail

    local freshLabel = getText("UI_QuickRestart_FreshWorld")
    local sameLabel = getText("UI_QuickRestart_ThisWorld")

    if freshEnabled then
        self.freshButton = ISButton:new(xCenter, yStart, buttonWidth, buttonHeight, freshLabel, self, function()
            if self.onRestartNewWorld then
                self.onRestartNewWorld()
            end
        end)
    else
        self.freshButton = ISButton:new(xCenter, yStart, buttonWidth, buttonHeight, "", self, nil)
        self.freshButton.enable = false
        self.freshButton.disabledLabel = freshLabel
    end

    self.freshButton:initialise()
    self.freshButton:instantiate()
    self.freshButton.backgroundColor = freshEnabled and {r=0, g=0, b=0, a=0.9} or {r=0.3, g=0.3, b=0.3, a=0.9}
    self.freshButton.borderColor = {r=0.7, g=0.7, b=0.7, a=0.3}
    self:addChild(self.freshButton)

    if sameEnabled then
        self.sameButton = ISButton:new(xCenter, yStart + buttonHeight + spacing, buttonWidth, buttonHeight, sameLabel, self, function()
            if self.onRestartSameWorld then
                self.onRestartSameWorld()
            end
        end)
    else
        self.sameButton = ISButton:new(xCenter, yStart + buttonHeight + spacing, buttonWidth, buttonHeight, "", self, nil)
        self.sameButton.enable = false
        self.sameButton.disabledLabel = sameLabel
    end

    self.sameButton:initialise()
    self.sameButton:instantiate()
    self.sameButton.backgroundColor = sameEnabled and {r=0, g=0, b=0, a=0.9} or {r=0.3, g=0.3, b=0.3, a=0.9}
    self.sameButton.borderColor = {r=0.7, g=0.7, b=0.7, a=0.3}
    self:addChild(self.sameButton)
end

local function drawTooltip(panel, tooltipText, mouseX, mouseY)
    local layout = panel.layout or computeLayout()
    local textManager = getTextManager()
    local font = layout.fontSmall
    local fontHeight = layout.hgtSmall
    local padding = layout.gapTiny
    local core = getCore()
    local screenWidth = core:getScreenWidth()
    local screenHeight = core:getScreenHeight()
    local maxWidth = math.min(400, screenWidth * 0.4)

    local lines = {}
    local line = ""
    for word in tooltipText:gmatch("%S+") do
        local test = line == "" and word or (line .. " " .. word)
        if textManager:MeasureStringX(font, test) > maxWidth then
            if line ~= "" then
                lines[#lines + 1] = line
                line = word
            else
                lines[#lines + 1] = word
            end
        else
            line = test
        end
    end
    if line ~= "" then lines[#lines + 1] = line end

    local maxLineWidth = 0
    for _, l in ipairs(lines) do
        local w = textManager:MeasureStringX(font, l)
        if w > maxLineWidth then maxLineWidth = w end
    end

    local boxWidth = maxLineWidth + padding * 2
    local boxHeight = fontHeight * #lines + padding * 2 + (#lines - 1) * layout.gapTiny
    local offset = math.ceil(fontHeight * 1.5)
    local absX = panel:getAbsoluteX() + mouseX + offset
    local absY = panel:getAbsoluteY() + mouseY + offset
    absX = math.max(0, math.min(absX, screenWidth - boxWidth))
    absY = math.max(0, math.min(absY, screenHeight - boxHeight))
    local boxX = absX - panel:getAbsoluteX()
    local boxY = absY - panel:getAbsoluteY()

    panel:drawRect(boxX, boxY, boxWidth, boxHeight, 0.9, 0, 0, 0)
    panel:drawRectBorder(boxX, boxY, boxWidth, boxHeight, 1, 0.7, 0.7, 0.7)
    for i, l in ipairs(lines) do
        panel:drawText(l, boxX + padding, boxY + padding + (i - 1) * (fontHeight + layout.gapTiny), 1, 1, 1, 1, font)
    end
end

function QuickRestartPanel:showSandboxChoice(data, playerIdentifier, sandboxVarsCurrent)
    self:removeChild(self.freshButton)
    self:removeChild(self.sameButton)
    self.freshButton = nil
    self.sameButton = nil

    self.sandboxMode = true

    self.layout = self.layout or computeLayout()
    local layout = self.layout
    local textManager = getTextManager()
    local core = getCore()
    local screenWidth = core:getScreenWidth()
    local screenHeight = core:getScreenHeight()

    local title = getText("UI_QuickRestart_SandboxConflict_Title")
    local label = getText("UI_QuickRestart_SandboxConflictPanel_Label")
    local savedLabel = getText("UI_QuickRestart_SandboxConflict_Saved")
    local currentLabel = getText("UI_QuickRestart_SandboxConflict_Current")

    local titleWidth = textManager:MeasureStringX(layout.fontMedium, title)
    local labelWidth = textManager:MeasureStringX(layout.fontSmall, label)
    local buttonLabelWidth = math.max(
        textManager:MeasureStringX(layout.fontSmall, savedLabel),
        textManager:MeasureStringX(layout.fontSmall, currentLabel)
    )
    local contentWidth = math.max(math.max(titleWidth, labelWidth), buttonLabelWidth + layout.buttonTextPad * 2)
    local newWidth = math.min(contentWidth + layout.marginX * 2, layout.maxPanelWidth)
    if newWidth > self.width then
        self:setWidth(newWidth)
        self:setX((screenWidth - newWidth) / 2)
    end

    local subtitle = getText("UI_QuickRestart_SandboxConflict_Subtitle")
    local wrapWidth = self.width - layout.marginX * 2
    local subtitleLines = {}
    local line = ""
    for word in subtitle:gmatch("%S+") do
        local test = line == "" and word or (line .. " " .. word)
        if textManager:MeasureStringX(layout.fontSmall, test) > wrapWidth then
            if line ~= "" then
                subtitleLines[#subtitleLines + 1] = line
                line = word
            else
                subtitleLines[#subtitleLines + 1] = word
            end
        else
            line = test
        end
    end
    if line ~= "" then subtitleLines[#subtitleLines + 1] = line end
    self.subtitleLines = subtitleLines

    local buttonWidth = self.width - layout.marginX * 2
    local buttonHeight = layout.buttonHeight
    local spacing = layout.spacing
    local xCenter = (self.width - buttonWidth) / 2

    local newHeight = layout.marginY + layout.hgtMedium + layout.gapTiny + layout.hgtSmall + layout.spacing
        + #subtitleLines * (layout.hgtSmall + layout.gapTiny) + layout.spacing
        + buttonHeight + spacing + buttonHeight + layout.marginY
    local oldBottom = math.min(self:getY() + self:getHeight(), screenHeight)
    self:setHeight(newHeight)
    self:setY(math.max(0, oldBottom - newHeight))

    local buttonY2 = self.height - layout.marginY - buttonHeight
    local buttonY1 = buttonY2 - spacing - buttonHeight

    self.savedButton = ISButton:new(xCenter, buttonY1, buttonWidth, buttonHeight, savedLabel, self, function()
        if self.onSandboxSaved then
            self.onSandboxSaved(data, playerIdentifier, sandboxVarsCurrent)
        end
    end)
    self.savedButton:initialise()
    self.savedButton:instantiate()
    self.savedButton.backgroundColor = {r=0, g=0, b=0, a=0.9}
    self.savedButton.borderColor = {r=0.7, g=0.7, b=0.7, a=0.3}
    self:addChild(self.savedButton)

    self.currentButton = ISButton:new(xCenter, buttonY2, buttonWidth, buttonHeight, currentLabel, self, function()
        if self.onSandboxCurrent then
            self.onSandboxCurrent(data, playerIdentifier, sandboxVarsCurrent)
        end
    end)
    self.currentButton:initialise()
    self.currentButton:instantiate()
    self.currentButton.backgroundColor = {r=0, g=0, b=0, a=0.9}
    self.currentButton.borderColor = {r=0.7, g=0.7, b=0.7, a=0.3}
    self:addChild(self.currentButton)
end

function QuickRestartPanel:render()
    ISPanel.render(self)

    local textManager = getTextManager()
    local layout = self.layout or computeLayout()
    local font = layout.fontSmall
    local fontHeight = layout.hgtSmall

    if self.sandboxMode then
        local title = getText("UI_QuickRestart_SandboxConflict_Title")
        local titleY = layout.marginY

        local titleWidth = textManager:MeasureStringX(UIFont.Medium, title)
        local titleX = (self.width - titleWidth) / 2

        self:drawText(title, titleX-1, titleY, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(title, titleX+1, titleY, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(title, titleX, titleY-1, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(title, titleX, titleY+1, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(title, titleX, titleY, 1, 1, 1, 1, UIFont.Medium)

        local labelY = titleY + layout.hgtMedium + layout.gapTiny
        local label = getText("UI_QuickRestart_SandboxConflictPanel_Label")
        local labelWidth = textManager:MeasureStringX(font, label)
        local labelX = (self.width - labelWidth) / 2
        self:drawText(label, labelX, labelY, 1, 1, 1, 1, font)

        local lineY = labelY + fontHeight + layout.spacing
        for _, l in ipairs(self.subtitleLines) do
            local lx = (self.width - textManager:MeasureStringX(font, l)) / 2
            self:drawText(l, lx, lineY, 1, 1, 1, 1, font)
            lineY = lineY + fontHeight + layout.gapTiny
        end

        local tooltipText = nil
        if self.savedButton and self.savedButton:isMouseOver() then
            tooltipText = getText("UI_QuickRestart_SandboxConflict_Saved_Tooltip")
        elseif self.currentButton and self.currentButton:isMouseOver() then
            tooltipText = getText("UI_QuickRestart_SandboxConflict_Current_Tooltip")
        end

        if tooltipText then
            local mouseX = getMouseX() - self:getAbsoluteX()
            local mouseY = getMouseY() - self:getAbsoluteY()
            drawTooltip(self, tooltipText, mouseX, mouseY)
        end
    else
        local text = getText("UI_QuickRestart_Title")
        local y = layout.marginY

        local textWidth = textManager:MeasureStringX(UIFont.Medium, text)
        local x = (self.width - textWidth) / 2

        self:drawText(text, x-1, y, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(text, x+1, y, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(text, x, y-1, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(text, x, y+1, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(text, x, y, 1, 1, 1, 1, UIFont.Medium)

        local function drawDisabledLabel(btn)
            if btn and btn.disabledLabel then
                local lw = textManager:MeasureStringX(font, btn.disabledLabel)
                local lx = btn:getX() + (btn:getWidth() - lw) / 2
                local ly = btn:getY() + (btn:getHeight() - fontHeight) / 2
                self:drawText(btn.disabledLabel, lx, ly, 0.6, 0.6, 0.6, 1, font)
            end
        end
        drawDisabledLabel(self.freshButton)
        drawDisabledLabel(self.sameButton)

        local tooltipText = nil
        if self.freshButton:isMouseOver() then
            if not self.freshWorldEnabled then
                tooltipText = getText("UI_QuickRestart_MP_Tooltip")
            elseif not self.charDataAvail then
                tooltipText = getText("UI_QuickRestart_NoData_Tooltip")
            else
                tooltipText = getText("UI_QuickRestart_FreshWorld_Tooltip")
            end
        elseif self.sameButton and self.sameButton:isMouseOver() then
            if not self.charDataAvail then
                tooltipText = getText("UI_QuickRestart_NoData_Tooltip")
            else
                tooltipText = getText("UI_QuickRestart_ThisWorld_Tooltip")
            end
        end

        if tooltipText then
            local mouseX = getMouseX() - self:getAbsoluteX()
            local mouseY = getMouseY() - self:getAbsoluteY()
            drawTooltip(self, tooltipText, mouseX, mouseY)
        end
    end
end

function QuickRestartUI.createRestartPanel(options)
    options = options or {}

    local core = getCore()
    local screenWidth = core:getScreenWidth()
    local screenHeight = core:getScreenHeight()

    local layout = computeLayout()
    local textManager = getTextManager()
    local titleWidth = textManager:MeasureStringX(layout.fontMedium, getText("UI_QuickRestart_Title"))
    local freshWidth = textManager:MeasureStringX(layout.fontSmall, getText("UI_QuickRestart_FreshWorld"))
    local sameWidth = textManager:MeasureStringX(layout.fontSmall, getText("UI_QuickRestart_ThisWorld"))
    local labelWidth = math.max(freshWidth, sameWidth)
    local vanillaWidth = resolveDeathButtonWidth()
    local buttonWidth
    local panelWidth
    if vanillaWidth then
        buttonWidth = math.max(vanillaWidth, labelWidth + layout.spacing * 2)
        panelWidth = math.max(titleWidth, buttonWidth) + layout.marginX * 2
    else
        buttonWidth = labelWidth + layout.buttonTextPad * 2
        panelWidth = math.min(math.max(titleWidth, buttonWidth) + layout.marginX * 2, layout.maxPanelWidth)
        buttonWidth = math.min(buttonWidth, panelWidth - layout.marginX * 2)
    end
    local panelHeight = layout.marginY + layout.hgtMedium + layout.spacing
        + layout.buttonHeight + layout.spacing + layout.buttonHeight + layout.marginY
    local x = (screenWidth - panelWidth) / 2
    local y = screenHeight * 0.83 - panelHeight
    y = math.max(0, math.min(y, screenHeight - panelHeight))

    local panel = QuickRestartPanel:new(x, y, panelWidth, panelHeight)
    panel.layout = layout
    panel.buttonWidth = buttonWidth
    panel.charDataAvail = options.charDataAvail == true
    panel.canUseFreshWorld = options.canUseFreshWorld
    panel.onRestartNewWorld = options.onRestartNewWorld
    panel.onRestartSameWorld = options.onRestartSameWorld
    panel.onSandboxSaved = options.onSandboxSaved
    panel.onSandboxCurrent = options.onSandboxCurrent
    panel:initialise()
    panel:instantiate()
    panel:addToUIManager()
    panel:setVisible(true)
    return panel
end

function QuickRestartUI.showTransitionOverlay(message)
    local core = getCore()
    if not core then
        return nil
    end

    local overlay = QuickRestartUI.transitionOverlay
    if not overlay then
        overlay = QuickRestartTransitionOverlay:new(0, 0, core:getScreenWidth(), core:getScreenHeight())
        overlay:initialise()
        overlay:instantiate()
        overlay:setCapture(true)
        if overlay.javaObject and overlay.javaObject.setConsumeMouseEvents then
            overlay.javaObject:setConsumeMouseEvents(true)
        end
        overlay:addToUIManager()
        overlay:setAlwaysOnTop(true)
        QuickRestartUI.transitionOverlay = overlay
    end

    overlay.message = message or (getText("UI_QuickRestart_Title") .. "...")
    overlay.currentAlpha = 1
    overlay.targetAlpha = 1
    overlay.isClosing = false
    overlay.backgroundColor.a = 1
    overlay:setVisible(true)
    overlay:bringToTop()
    return overlay
end

function QuickRestartUI.hideTransitionOverlay()
    local overlay = QuickRestartUI.transitionOverlay
    if not overlay then
        return false
    end

    overlay.targetAlpha = 0
    overlay.isClosing = true
    overlay:bringToTop()
    return true
end

return QuickRestartUI
