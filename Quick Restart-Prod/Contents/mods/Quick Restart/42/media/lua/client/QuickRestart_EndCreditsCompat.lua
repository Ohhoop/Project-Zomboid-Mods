local CREDITS_PANEL_GLOBALS = {
    "TEC_CreditsUI",
    "TLG_CreditsRoll",
}

local PANEL_GAP = 12

local installed = false
local ghostPlayerNum = nil
local trackedPanel = nil
local lastVanillaVisible = nil

local function logCompat(message)
    if QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("endCredits " .. tostring(message))
    end
end

local function getCreditsPanel(playerNum)
    for _, name in ipairs(CREDITS_PANEL_GLOBALS) do
        local holder = _G[name]
        if type(holder) == "table" and type(holder.instance) == "table" then
            local panel = holder.instance[playerNum]
            if panel then
                return panel, holder
            end
        end
    end

    return nil, nil
end

local function isPanelRemoved(panel)
    if not panel or not panel.isRemoved then
        return false
    end

    local ok, removed = pcall(function()
        return panel:isRemoved()
    end)

    return ok and removed == true
end

local function getVanillaPanel(playerNum)
    if not ISPostDeathUI or type(ISPostDeathUI.instance) ~= "table" then
        return nil
    end

    local panel = ISPostDeathUI.instance[playerNum]
    if not panel or isPanelRemoved(panel) then
        return nil
    end

    return panel
end

local function buildVanillaLines(playerObj)
    local lines = {}

    pcall(function()
        local gameTime = getGameTime()
        lines[#lines + 1] = gameTime:getDeathString(playerObj)

        local kills = gameTime:getZombieKilledText(playerObj)
        if kills then
            lines[#lines + 1] = kills
        end

        local mode = gameTime:getGameModeText()
        if mode then
            lines[#lines + 1] = mode
        end
    end)

    return lines
end

local function createHiddenVanillaPanel(playerObj, playerNum)
    if getVanillaPanel(playerNum) then
        return false
    end

    local ok, panel = pcall(function()
        return ISPostDeathUI:new(playerNum)
    end)
    if not ok or not panel then
        logCompat("failed to rebuild the vanilla death screen")
        return false
    end

    panel.timeOfDeath = getTimestamp()
    panel.lines = buildVanillaLines(playerObj)
    panel:addToUIManager()
    panel:setVisible(false)
    ghostPlayerNum = playerNum

    logCompat("rebuilt the vanilla death screen for player " .. tostring(playerNum))
    return true
end

local function creditsButtonsShowing(creditsPanel)
    local alpha = creditsPanel and creditsPanel.btnAlpha or nil
    return type(alpha) == "number" and alpha > 0
end

local function creditsButtonsTop(creditsPanel)
    if not creditsPanel or type(creditsPanel.manualButtons) ~= "table" then
        return nil
    end

    local first = creditsPanel.manualButtons[1]
    if type(first) ~= "table" or type(first.y) ~= "number" then
        return nil
    end

    return first.y
end

local function liftPanelAboveCredits(panel, creditsPanel)
    local top = creditsButtonsTop(creditsPanel)
    if not top then
        return
    end

    local bottom = panel:getY() + panel:getHeight()
    if bottom <= top - PANEL_GAP then
        return
    end

    local newY = math.max(0, top - PANEL_GAP - panel:getHeight())
    panel:setY(newY)
end

local function resolveLocalPlayerNum()
    local player = getPlayer()
    if not player then
        return 0
    end

    return player:getPlayerNum()
end

local function installPanelHook()
    local baseCreateRestartPanel = QuickRestartUI.createRestartPanel

    QuickRestartUI.createRestartPanel = function(options)
        local panel = baseCreateRestartPanel(options)
        if not panel then
            return panel
        end

        trackedPanel = panel

        local creditsPanel = getCreditsPanel(resolveLocalPlayerNum())
        if creditsPanel then
            liftPanelAboveCredits(panel, creditsPanel)
            panel:setAlwaysOnTop(true)
            panel:bringToTop()
        end

        return panel
    end

    local baseOpenOptionsWindow = QuickRestartUI.openOptionsWindow

    QuickRestartUI.openOptionsWindow = function(ownerPanel)
        local window = baseOpenOptionsWindow(ownerPanel)
        if window and getCreditsPanel(resolveLocalPlayerNum()) then
            window:setAlwaysOnTop(true)
            window:bringToTop()
        end

        return window
    end
end

local function releaseGhostPanel()
    if ghostPlayerNum ~= nil then
        local panel = getVanillaPanel(ghostPlayerNum)
        if panel then
            pcall(function()
                panel:removeFromUIManager()
            end)
        end
        ghostPlayerNum = nil
    end

    trackedPanel = nil
    lastVanillaVisible = nil
end

local function mirrorVanillaVisibility(playerNum, vanillaPanel)
    if not trackedPanel or isPanelRemoved(trackedPanel) then
        return
    end

    local ok, visible = pcall(function()
        return vanillaPanel:isVisible()
    end)
    if not ok then
        return
    end

    if visible == lastVanillaVisible then
        return
    end

    lastVanillaVisible = visible
    trackedPanel:setVisible(visible)

    if visible and QuickRestartUI.beginDeathScreenFade then
        QuickRestartUI.beginDeathScreenFade(playerNum)
    end
end

local function updateCompat()
    local player = getPlayer()
    if not player or not player:isDead() then
        return
    end

    local playerNum = player:getPlayerNum()
    local creditsPanel = getCreditsPanel(playerNum)
    if not creditsPanel then
        return
    end

    if isPanelRemoved(creditsPanel) then
        releaseGhostPanel()
        return
    end

    local vanillaPanel = getVanillaPanel(playerNum)

    if vanillaPanel then
        if ghostPlayerNum == nil then
            mirrorVanillaVisibility(playerNum, vanillaPanel)
        end
        return
    end

    if not creditsButtonsShowing(creditsPanel) then
        return
    end

    if createHiddenVanillaPanel(player, playerNum) and QuickRestartUI.beginDeathScreenFade then
        QuickRestartUI.beginDeathScreenFade(playerNum)
    end
end

if not installed and QuickRestartUI and QuickRestartUI.createRestartPanel then
    installed = true
    installPanelHook()
    Events.OnPostUIDraw.Add(updateCompat)
end

Events.OnCreatePlayer.Add(function(playerNum)
    releaseGhostPanel()

    local creditsPanel = getCreditsPanel(playerNum)
    if creditsPanel and creditsPanel.removeFromUIManager then
        pcall(function()
            creditsPanel:removeFromUIManager()
        end)
    end
end)
