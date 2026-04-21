if not isMultiplayer() then return end

local adminPanel = nil
local adminButton = nil

CPFAdminPanel = ISPanel:derive("CPFAdminPanel")

function CPFAdminPanel:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.redCount = 0
    o.blueCount = 0
    o.maxImbalance = 2
    o.backgroundColor = { r = 0.1, g = 0.1, b = 0.1, a = 0.95 }
    o.borderColor = { r = 0.7, g = 0.7, b = 0.7, a = 1 }
    return o
end

function CPFAdminPanel:createChildren()
    ISPanel.createChildren(self)

    local bw = self.width - 40
    local cx = 20

    self.minusButton = ISButton:new(cx, 70, 30, 25, "-", self, CPFAdminPanel.onMinus)
    self.minusButton:initialise()
    self.minusButton:instantiate()
    self:addChild(self.minusButton)

    self.maxImbalanceLabel = ISLabel:new(cx + 38, 75, 25, tostring(self.maxImbalance), 1, 1, 1, 1, UIFont.Small, true)
    self.maxImbalanceLabel:initialise()
    self:addChild(self.maxImbalanceLabel)

    self.plusButton = ISButton:new(cx + 70, 70, 30, 25, "+", self, CPFAdminPanel.onPlus)
    self.plusButton:initialise()
    self.plusButton:instantiate()
    self:addChild(self.plusButton)

    self.endMatchButton = ISButton:new(cx, 130, bw, 30, getText("UI_CPF_EndMatch"), self, CPFAdminPanel.onEndMatch)
    self.endMatchButton:initialise()
    self.endMatchButton:instantiate()
    self.endMatchButton.backgroundColor = { r = 0.5, g = 0.1, b = 0.1, a = 1 }
    self.endMatchButton.borderColor = { r = 0.8, g = 0.2, b = 0.2, a = 1 }
    self:addChild(self.endMatchButton)

    self.closeButton = ISButton:new(self.width - 25, 5, 20, 20, "x", self, CPFAdminPanel.onClose)
    self.closeButton:initialise()
    self.closeButton:instantiate()
    self:addChild(self.closeButton)
end

function CPFAdminPanel:onMinus()
    if self.maxImbalance <= 0 then return end
    self.maxImbalance = self.maxImbalance - 1
    self.maxImbalanceLabel:setName(tostring(self.maxImbalance))
    sendClientCommand("CPF", "setMaxImbalance", { max = self.maxImbalance })
end

function CPFAdminPanel:onPlus()
    self.maxImbalance = self.maxImbalance + 1
    self.maxImbalanceLabel:setName(tostring(self.maxImbalance))
    sendClientCommand("CPF", "setMaxImbalance", { max = self.maxImbalance })
end

function CPFAdminPanel:onEndMatch()
    sendClientCommand("CPF", "resetMatch", {})
end

function CPFAdminPanel:onClose()
    self:removeFromUIManager()
    adminPanel = nil
end

function CPFAdminPanel:updateCounts(redCount, blueCount)
    self.redCount = redCount
    self.blueCount = blueCount
end

function CPFAdminPanel:render()
    ISPanel.render(self)

    local tm = getTextManager()

    local title = getText("UI_CPF_AdminPanel")
    local tw = tm:MeasureStringX(UIFont.Medium, title)
    self:drawText(title, (self.width - tw) / 2, 10, 1, 1, 1, 1, UIFont.Medium)

    local maxLabel = getText("UI_CPF_MaxImbalance") .. ":"
    self:drawText(maxLabel, 20, 48, 0.8, 0.8, 0.8, 1, UIFont.Small)

    local redLabel = getText("UI_CPF_RedCount", self.redCount)
    local blueLabel = getText("UI_CPF_BlueCount", self.blueCount)
    self:drawText(redLabel, 20, 105, 1, 0.3, 0.3, 1, UIFont.Small)
    self:drawText(blueLabel, (self.width / 2) + 10, 105, 0.3, 0.3, 1, UIFont.Small)
end

local function openAdminPanel()
    if adminPanel then
        adminPanel:removeFromUIManager()
        adminPanel = nil
        return
    end

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local w, h = 280, 175
    local x = (sw - w) / 2
    local y = (sh - h) / 2

    adminPanel = CPFAdminPanel:new(x, y, w, h)
    adminPanel:initialise()
    adminPanel:instantiate()
    adminPanel:addToUIManager()
    adminPanel:setVisible(true)

    sendClientCommand("CPF", "requestState", {})
end

CPFAdminButton = ISButton:derive("CPFAdminButton")

function CPFAdminButton:new(x, y, width, height)
    local o = ISButton:new(x, y, width, height, "CPF", nil, openAdminPanel)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
    o.borderColor = { r = 0.6, g = 0.6, b = 0.6, a = 1 }
    return o
end

local function onServerCommand(module, command, args)
    if module ~= "CPF" then return end

    if command == "stateSync" or command == "teamAssigned" then
        if adminPanel then
            adminPanel:updateCounts(args.redCount or 0, args.blueCount or 0)
        end
        if command == "stateSync" and adminPanel and args.maxImbalance then
            adminPanel.maxImbalance = args.maxImbalance
            adminPanel.maxImbalanceLabel:setName(tostring(args.maxImbalance))
        end

    elseif command == "configSync" then
        if adminPanel and args.maxImbalance then
            adminPanel.maxImbalance = args.maxImbalance
            adminPanel.maxImbalanceLabel:setName(tostring(args.maxImbalance))
        end

    elseif command == "matchReset" then
        if adminPanel then
            adminPanel:updateCounts(0, 0)
        end
    end
end

local function onGameStart(player, square)
    if not isAdmin() then return end
    if adminButton then return end

    local sw = getCore():getScreenWidth()
    adminButton = CPFAdminButton:new(sw - 70, 10, 60, 22)
    adminButton:initialise()
    adminButton:instantiate()
    adminButton:addToUIManager()
    adminButton:setVisible(true)
end

Events.OnNewGame.Add(onGameStart)
Events.OnServerCommand.Add(onServerCommand)
