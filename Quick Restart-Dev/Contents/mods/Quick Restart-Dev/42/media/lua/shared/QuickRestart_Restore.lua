QuickRestartRestore = QuickRestartRestore or {}
QuickRestartRestore._serverClothingTasks = QuickRestartRestore._serverClothingTasks or {}
QuickRestartRestore._serverClothingTickRegistered = QuickRestartRestore._serverClothingTickRegistered == true

local function applyKnownRecipes(player, recipes)
    if not player or type(recipes) ~= "table" then
        return
    end

    local call = pcall
    for _, recipe in ipairs(recipes) do
        if type(recipe) == "string" and recipe ~= "" then
            local alreadyKnown = false
            if player.isRecipeActuallyKnown then
                local success, result = call(function()
                    return player:isRecipeActuallyKnown(recipe)
                end)
                alreadyKnown = success and result == true
            end

            if not alreadyKnown and player.learnRecipe then
                call(function()
                    player:learnRecipe(recipe)
                end)
            end
        end
    end
end

local function isBaseBodyLocation(bodyLoc)
    return type(bodyLoc) == "string" and bodyLoc ~= "" and string.find(string.lower(bodyLoc), "base:", 1, true) == 1
end

local function shouldRestoreBaseClothingEntry(clothingData)
    if type(clothingData) ~= "table" then
        return false
    end

    if type(clothingData.bodyLocation) == "string" and clothingData.bodyLocation ~= "" then
        return isBaseBodyLocation(clothingData.bodyLocation)
    end

    return true
end

local function applyItemColor(item, color)
    if not item or not color then
        return
    end

    pcall(function()
        item:setColorRed(color.r)
        item:setColorGreen(color.g)
        item:setColorBlue(color.b)
        item:setColor(Color.new(color.r, color.g, color.b))
        item:setCustomColor(true)
    end)
end

local function applyItemVisual(item, clothingData)
    if not item or not clothingData then
        return
    end

    local visual = nil
    pcall(function() visual = item:getVisual() end)
    if not visual then
        return
    end

    if clothingData.baseTexture ~= nil and visual.setBaseTexture then
        pcall(function() visual:setBaseTexture(clothingData.baseTexture) end)
    end
    if clothingData.textureChoice ~= nil and visual.setTextureChoice then
        pcall(function() visual:setTextureChoice(clothingData.textureChoice) end)
    end
end

local function removeBaseWornItems(player)
    local ok, wornItems = pcall(function()
        return player:getWornItems()
    end)
    if not ok or not wornItems then
        return
    end

    local itemsToRemove = {}
    for i = 0, wornItems:size() - 1 do
        local item = wornItems:getItemByIndex(i)
        if item then
            local bodyLoc = nil
            pcall(function()
                bodyLoc = item:getBodyLocation()
            end)
            if isBaseBodyLocation(bodyLoc) then
                itemsToRemove[#itemsToRemove + 1] = item
            end
        end
    end

    for _, item in ipairs(itemsToRemove) do
        pcall(function()
            if player.removeWornItem then
                player:removeWornItem(item)
            else
                player:getWornItems():remove(item)
            end
        end)
    end
end

local function restoreBaseClothingServer(player, snapshot)
    if not player or type(snapshot) ~= "table" or type(snapshot.clothing) ~= "table" then
        if QuickRestartLog and QuickRestartLog.info then
            QuickRestartLog.info("server restore base clothing skipped invalid input")
        end
        return false
    end

    local inventory = player:getInventory()
    if not inventory then
        if QuickRestartLog and QuickRestartLog.info then
            QuickRestartLog.info("server restore base clothing skipped missing inventory")
        end
        return false
    end

    if QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("server restore base clothing begin snapshotCount=" .. tostring(#snapshot.clothing)
            .. " hasSendAddItemToContainer=" .. tostring(type(sendAddItemToContainer) == "function")
            .. " hasSendClothing=" .. tostring(type(sendClothing) == "function"))
    end

    removeBaseWornItems(player)

    local restoredCount = 0
    for _, clothingData in ipairs(snapshot.clothing) do
        if shouldRestoreBaseClothingEntry(clothingData)
            and type(clothingData.type) == "string"
            and clothingData.type ~= "" then
            local ok, item = pcall(function()
                return inventory:AddItem(clothingData.type)
            end)
            if ok and item then
                if QuickRestartLog and QuickRestartLog.info then
                    QuickRestartLog.info("server restore base clothing added type=" .. tostring(clothingData.type)
                        .. " bodyLocation=" .. tostring(clothingData.bodyLocation))
                end
                applyItemColor(item, clothingData.color)
                applyItemVisual(item, clothingData)
                pcall(function() item:synchWithVisual() end)
                local equipped = pcall(function()
                    player:setWornItem(item:getBodyLocation(), item)
                end)
                local syncedToContainer = pcall(function()
                    if sendAddItemToContainer then
                        sendAddItemToContainer(inventory, item)
                    end
                end)
                local syncedClothing = pcall(function()
                    if sendClothing then
                        sendClothing(player, item:getBodyLocation(), item)
                    end
                end)
                if QuickRestartLog and QuickRestartLog.info then
                    QuickRestartLog.info("server restore base clothing sync type=" .. tostring(clothingData.type)
                        .. " equipped=" .. tostring(equipped)
                        .. " syncedToContainer=" .. tostring(syncedToContainer)
                        .. " syncedClothing=" .. tostring(syncedClothing))
                end
                restoredCount = restoredCount + 1
            elseif QuickRestartLog and QuickRestartLog.info then
                QuickRestartLog.info("server restore base clothing add failed type=" .. tostring(clothingData.type))
            end
        end
    end

    if restoredCount > 0 and QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("server restore applied base clothing count=" .. tostring(restoredCount))
    elseif QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("server restore base clothing restored nothing")
    end

    return restoredCount > 0
end

local function hasServerClothingTasks()
    for _ in pairs(QuickRestartRestore._serverClothingTasks) do
        return true
    end
    return false
end

local function serverClothingTick()
    for key, task in pairs(QuickRestartRestore._serverClothingTasks) do
        task.remaining = task.remaining - 1
        if task.remaining <= 0 then
            QuickRestartRestore._serverClothingTasks[key] = nil
            pcall(task.fn)
        end
    end

    if QuickRestartRestore._serverClothingTickRegistered and not hasServerClothingTasks() then
        Events.OnTick.Remove(serverClothingTick)
        QuickRestartRestore._serverClothingTickRegistered = false
    end
end

local function ensureServerClothingTickRegistered()
    if QuickRestartRestore._serverClothingTickRegistered then
        return
    end

    Events.OnTick.Add(serverClothingTick)
    QuickRestartRestore._serverClothingTickRegistered = true
end

local function deepCopySupportedValue(value, visited)
    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then
        return value
    end

    if valueType ~= "table" then
        return nil
    end

    visited = visited or {}
    if visited[value] then
        return visited[value]
    end

    local copy = {}
    visited[value] = copy

    for key, childValue in pairs(value) do
        local keyType = type(key)
        if keyType == "string" or keyType == "number" or keyType == "boolean" then
            local copiedValue = deepCopySupportedValue(childValue, visited)
            if copiedValue ~= nil then
                copy[key] = copiedValue
            end
        end
    end

    return copy
end

local function applySnapshotTableIntoTarget(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then
        return false
    end

    for key, value in pairs(source) do
        local valueType = type(value)
        if valueType == "string" or valueType == "number" or valueType == "boolean" then
            target[key] = value
        elseif valueType == "table" then
            local copy = deepCopySupportedValue(value, {})
            if copy ~= nil then
                target[key] = copy
            end
        end
    end

    return true
end

local function applyAuthoritativeModData(player, snapshot)
    if not player or type(snapshot) ~= "table" or type(snapshot.modData) ~= "table" then
        return false
    end

    local applied = false

    if type(snapshot.modData.player) == "table" and player.getModData then
        local ok, playerModData = pcall(function()
            return player:getModData()
        end)
        if ok and type(playerModData) == "table" then
            applied = applySnapshotTableIntoTarget(playerModData, snapshot.modData.player) or applied
        end
    end

    if type(snapshot.modData.descriptor) == "table" and player.getDescriptor then
        local okDescriptor, descriptor = pcall(function()
            return player:getDescriptor()
        end)
        if okDescriptor and descriptor and descriptor.getModData then
            local okModData, descriptorModData = pcall(function()
                return descriptor:getModData()
            end)
            if okModData and type(descriptorModData) == "table" then
                applied = applySnapshotTableIntoTarget(descriptorModData, snapshot.modData.descriptor) or applied
            end
        end
    end

    if applied and QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("server restore applied authoritative modData"
            .. " hasPlayerModData=" .. tostring(type(snapshot.modData.player) == "table")
            .. " hasDescriptorModData=" .. tostring(type(snapshot.modData.descriptor) == "table"))
    end

    return applied
end

function QuickRestartRestore.applyAuthoritativeSnapshot(player, snapshot)
    if not player or type(snapshot) ~= "table" then
        return false, "invalid_snapshot"
    end

    if type(snapshot.traits) ~= "table" and type(snapshot.skills) ~= "table" then
        return false, "missing_restore_data"
    end

    applyAuthoritativeModData(player, snapshot)

    if type(snapshot.traits) == "table" then
        QuickRestartTraits.applyToPlayer(player, snapshot.traits)
    end

    if type(snapshot.recipes) == "table" then
        applyKnownRecipes(player, snapshot.recipes)
    end

    if type(snapshot.skills) == "table" then
        QuickRestartSkills.applyToPlayer(player, snapshot.skills)
    end

    return true, nil
end

local function notifyClientBaseClothingRestored(player)
    if not player or type(sendServerCommand) ~= "function" then
        return
    end

    pcall(function()
        sendServerCommand(player, QuickRestartConstants.MODULE,
            QuickRestartConstants.COMMANDS.SERVER_CLOTHING_RESTORED, {})
    end)
end

function QuickRestartRestore.scheduleBaseClothingRestore(player, snapshot, delayTicks)
    if not isServer() or not player or type(snapshot) ~= "table" then
        return false
    end

    local onlineId = nil
    pcall(function()
        onlineId = player:getOnlineID()
    end)

    local key = "base_clothing_" .. tostring(onlineId or "player")
    QuickRestartRestore._serverClothingTasks[key] = {
        remaining = math.max(0, tonumber(delayTicks) or 0),
        fn = function()
            restoreBaseClothingServer(player, snapshot)
            notifyClientBaseClothingRestored(player)
        end,
    }

    ensureServerClothingTickRegistered()
    return true
end

return QuickRestartRestore
