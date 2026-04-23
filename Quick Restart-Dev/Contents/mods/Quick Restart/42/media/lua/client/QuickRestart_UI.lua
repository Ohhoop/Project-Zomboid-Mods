QuickRestartUI = QuickRestartUI or {}

QuickRestartPanel = ISPanel:derive("QuickRestartPanel")
QuickRestartTransitionOverlay = ISPanel:derive("QuickRestartTransitionOverlay")

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

    local buttonWidth = self.width * 0.72
    local buttonHeight = 20
    local spacing = 12
    local xCenter = (self.width - buttonWidth) / 2

    local textHeight = 25
    local totalButtonsHeight = buttonHeight * 2 + spacing
    local yStart = (self.height - totalButtonsHeight - textHeight) / 2 + textHeight

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
    local textManager = getTextManager()
    local font = UIFont.Small
    local padding = 5
    local fontHeight = textManager:getFontHeight(font)
    local maxWidth = 400

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
    local boxHeight = fontHeight * #lines + padding * 2 + (#lines - 1) * 2
    local boxX = mouseX + 25
    local boxY = mouseY + 25

    panel:drawRect(boxX, boxY, boxWidth, boxHeight, 0.9, 0, 0, 0)
    panel:drawRectBorder(boxX, boxY, boxWidth, boxHeight, 1, 0.7, 0.7, 0.7)
    for i, l in ipairs(lines) do
        panel:drawText(l, boxX + padding, boxY + padding + (i - 1) * (fontHeight + 2), 1, 1, 1, 1, font)
    end
end

function QuickRestartPanel:showSandboxChoice(data, playerIdentifier, sandboxVarsCurrent)
    self:removeChild(self.freshButton)
    self:removeChild(self.sameButton)
    self.freshButton = nil
    self.sameButton = nil

    self.sandboxMode = true

    local subtitle = getText("UI_QuickRestart_SandboxConflict_Subtitle")
    local textManager = getTextManager()
    local font = UIFont.Small
    local fontHeight = textManager:getFontHeight(font)
    local subtitleLines = {}
    local line = ""
    for word in subtitle:gmatch("%S+") do
        local test = line == "" and word or (line .. " " .. word)
        if textManager:MeasureStringX(font, test) > self.width - 20 then
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

    local buttonWidth = self.width * 0.72
    local buttonHeight = 20
    local spacing = 10
    local xCenter = (self.width - buttonWidth) / 2

    local titleMediumHeight = textManager:getFontHeight(UIFont.Medium)
    local newHeight = 10 + titleMediumHeight + 4 + fontHeight + 8 + #subtitleLines * (fontHeight + 2) + 10 + buttonHeight + spacing + buttonHeight + 10
    local oldBottom = self:getY() + self:getHeight()
    self:setHeight(newHeight)
    self:setY(oldBottom - newHeight)

    local buttonY2 = self.height - 10 - buttonHeight
    local buttonY1 = buttonY2 - spacing - buttonHeight

    self.savedButton = ISButton:new(xCenter, buttonY1, buttonWidth, buttonHeight, getText("UI_QuickRestart_SandboxConflict_Saved"), self, function()
        if self.onSandboxSaved then
            self.onSandboxSaved(data, playerIdentifier, sandboxVarsCurrent)
        end
    end)
    self.savedButton:initialise()
    self.savedButton:instantiate()
    self.savedButton.backgroundColor = {r=0, g=0, b=0, a=0.9}
    self.savedButton.borderColor = {r=0.7, g=0.7, b=0.7, a=0.3}
    self:addChild(self.savedButton)

    self.currentButton = ISButton:new(xCenter, buttonY2, buttonWidth, buttonHeight, getText("UI_QuickRestart_SandboxConflict_Current"), self, function()
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
    local font = UIFont.Small
    local fontHeight = textManager:getFontHeight(font)

    if self.sandboxMode then
        local title = getText("UI_QuickRestart_SandboxConflict_Title")
        local titleY = 10

        local titleWidth = textManager:MeasureStringX(UIFont.Medium, title)
        local titleX = (self.width - titleWidth) / 2

        self:drawText(title, titleX-1, titleY, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(title, titleX+1, titleY, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(title, titleX, titleY-1, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(title, titleX, titleY+1, 0, 0, 0, 0.5, UIFont.Medium)
        self:drawText(title, titleX, titleY, 1, 1, 1, 1, UIFont.Medium)

        local labelY = titleY + textManager:getFontHeight(UIFont.Medium) + 4
        local label = getText("UI_QuickRestart_SandboxConflictPanel_Label")
        local labelWidth = textManager:MeasureStringX(font, label)
        local labelX = (self.width - labelWidth) / 2
        self:drawText(label, labelX, labelY, 1, 1, 1, 1, font)

        local lineY = labelY + fontHeight + 8
        for _, l in ipairs(self.subtitleLines) do
            local lx = (self.width - textManager:MeasureStringX(font, l)) / 2
            self:drawText(l, lx, lineY, 1, 1, 1, 1, font)
            lineY = lineY + fontHeight + 2
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
        local y = 10

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

    local panelWidth = screenWidth * 0.08
    local panelHeight = screenHeight * 0.08
    local x = (screenWidth - panelWidth) / 2
    local y = screenHeight * 0.75

    local panel = QuickRestartPanel:new(x, y, panelWidth, panelHeight)
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
