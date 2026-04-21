if not isMultiplayer() then return end

local localTeam = {}
local teamSelectUI = {}

CPFTeamSelectPanel = ISPanel:derive("CPFTeamSelectPanel")

function CPFTeamSelectPanel:new(x, y, width, height, playerNum)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.playerNum = playerNum
    o.redCount = 0
    o.blueCount = 0
    o.maxImbalance = 2
    o.backgroundColor = { r = 0.1, g = 0.1, b = 0.1, a = 0.9 }
    o.borderColor = { r = 0.6, g = 0.6, b = 0.6, a = 1 }
    return o
end

function CPFTeamSelectPanel:createChildren()
    ISPanel.createChildren(self)

    local bw = self.width - 40
    local bh = 30
    local cx = 20

    self.redButton = ISButton:new(cx, 60, bw, bh, "", self, CPFTeamSelectPanel.onRedClick)
    self.redButton:initialise()
    self.redButton:instantiate()
    self.redButton.backgroundColor = { r = 0.6, g = 0.1, b = 0.1, a = 1 }
    self.redButton.borderColor = { r = 0.8, g = 0.2, b = 0.2, a = 1 }
    self:addChild(self.redButton)

    self.blueButton = ISButton:new(cx, 110, bw, bh, "", self, CPFTeamSelectPanel.onBlueClick)
    self.blueButton:initialise()
    self.blueButton:instantiate()
    self.blueButton.backgroundColor = { r = 0.1, g = 0.1, b = 0.6, a = 1 }
    self.blueButton.borderColor = { r = 0.2, g = 0.2, b = 0.8, a = 1 }
    self:addChild(self.blueButton)

    self:updateButtons()
end

function CPFTeamSelectPanel:updateButtons()
    local redLabel = getText("UI_CPF_RedTeam") .. " (" .. self.redCount .. ")"
    local blueLabel = getText("UI_CPF_BlueTeam") .. " (" .. self.blueCount .. ")"

    local redBlocked = (self.redCount - self.blueCount) >= self.maxImbalance
    local blueBlocked = (self.blueCount - self.redCount) >= self.maxImbalance

    self.redButton.title = redLabel
    self.redButton.enable = not redBlocked

    self.blueButton.title = blueLabel
    self.blueButton.enable = not blueBlocked
end

function CPFTeamSelectPanel:onRedClick()
    sendClientCommand("CPF", "requestTeam", { team = "red" })
end

function CPFTeamSelectPanel:onBlueClick()
    sendClientCommand("CPF", "requestTeam", { team = "blue" })
end

function CPFTeamSelectPanel:render()
    ISPanel.render(self)

    local title = getText("UI_CPF_ChooseTeam")
    local tw = getTextManager():MeasureStringX(UIFont.Medium, title)
    self:drawText(title, (self.width - tw) / 2, 20, 1, 1, 1, 1, UIFont.Medium)
end

local function showTeamSelectUI(playerNum)
    if teamSelectUI[playerNum] then
        teamSelectUI[playerNum]:removeFromUIManager()
        teamSelectUI[playerNum] = nil
    end

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local w, h = 300, 160
    local x = (sw - w) / 2
    local y = (sh - h) / 2

    local panel = CPFTeamSelectPanel:new(x, y, w, h, playerNum)
    panel:initialise()
    panel:instantiate()
    panel:addToUIManager()
    panel:setVisible(true)
    teamSelectUI[playerNum] = panel
end

local function hideTeamSelectUI(playerNum)
    if teamSelectUI[playerNum] then
        teamSelectUI[playerNum]:removeFromUIManager()
        teamSelectUI[playerNum] = nil
    end
end

local function onServerCommand(module, command, args)
    if module ~= "CPF" then return end

    local playerNum = 0

    if command == "stateSync" then
        local panel = teamSelectUI[playerNum]
        if args.team then
            localTeam[playerNum] = args.team
            hideTeamSelectUI(playerNum)
        else
            if panel then
                panel.redCount = args.redCount or 0
                panel.blueCount = args.blueCount or 0
                panel.maxImbalance = args.maxImbalance or 2
                panel:updateButtons()
            else
                showTeamSelectUI(playerNum)
                local newPanel = teamSelectUI[playerNum]
                if newPanel then
                    newPanel.redCount = args.redCount or 0
                    newPanel.blueCount = args.blueCount or 0
                    newPanel.maxImbalance = args.maxImbalance or 2
                    newPanel:updateButtons()
                end
            end
        end

    elseif command == "teamAssigned" then
        localTeam[playerNum] = args.team
        hideTeamSelectUI(playerNum)

    elseif command == "teamDenied" then
        local panel = teamSelectUI[playerNum]
        if panel then
            panel:updateButtons()
        end

    elseif command == "matchReset" then
        localTeam[playerNum] = nil
        showTeamSelectUI(playerNum)
        sendClientCommand("CPF", "requestState", {})

    elseif command == "configSync" then
        local panel = teamSelectUI[playerNum]
        if panel then
            panel.maxImbalance = args.maxImbalance or 2
            panel:updateButtons()
        end
    end
end

local function onNewGame(player, square)
    local playerNum = player:getPlayerNum()
    if not localTeam[playerNum] then
        sendClientCommand("CPF", "requestState", {})
    end
end

Events.OnNewGame.Add(onNewGame)
Events.OnServerCommand.Add(onServerCommand)
