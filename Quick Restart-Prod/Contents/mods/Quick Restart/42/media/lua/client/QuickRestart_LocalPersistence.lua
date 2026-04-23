QuickRestartLocalPersistence = QuickRestartLocalPersistence or {}

local function resolveCharacterProfession(profession)
    local professionType = tostring(profession or "unemployed")
    local characterProfession = CharacterProfession.get(ResourceLocation.of(professionType))
    if characterProfession then
        return characterProfession
    end

    return CharacterProfession.get(ResourceLocation.of("unemployed"))
end

local function describeSpawnRegions(regions)
    if type(regions) ~= "table" then
        return "<nil>"
    end

    local names = {}
    for _, region in ipairs(regions) do
        names[#names + 1] = tostring(region and region.name or nil)
    end
    return "[" .. table.concat(names, ", ") .. "]"
end

local function restoreSavedSpawnRegion(data)
    local savedRegionName = type(data) == "table" and type(data.region) == "string" and data.region ~= "" and data.region or nil
    if not savedRegionName then
        QuickRestartLog.warn("checkPendingRestart restoreSavedSpawnRegion skipped: no saved region")
        return nil
    end

    local mapSpawnSelect = nil
    if MainScreen and MainScreen.instance and MainScreen.instance.mapSpawnSelect then
        mapSpawnSelect = MainScreen.instance.mapSpawnSelect
    elseif MapSpawnSelect and MapSpawnSelect.instance then
        mapSpawnSelect = MapSpawnSelect.instance
    end

    if not mapSpawnSelect then
        QuickRestartLog.warn("checkPendingRestart restoreSavedSpawnRegion missing MapSpawnSelect requestedRegion=" .. tostring(savedRegionName))
        setSpawnRegion(savedRegionName)
        getCore():setSelectedMap(tostring(savedRegionName))
        return nil
    end

    mapSpawnSelect.selectedRegion = nil
    mapSpawnSelect:fillList()

    local availableRegions = mapSpawnSelect:getSpawnRegions()
    QuickRestartLog.info("checkPendingRestart restoreSavedSpawnRegion"
        .. " requestedRegion=" .. tostring(savedRegionName)
        .. " availableRegions=" .. describeSpawnRegions(availableRegions))

    local selectedRegion = nil
    if mapSpawnSelect.listbox and type(mapSpawnSelect.listbox.items) == "table" then
        for index, entry in ipairs(mapSpawnSelect.listbox.items) do
            local region = entry.item and entry.item.region or nil
            if region and region.name == savedRegionName then
                mapSpawnSelect.listbox.selected = index
                selectedRegion = region
                break
            end
        end
    end

    if not selectedRegion and type(availableRegions) == "table" then
        for _, region in ipairs(availableRegions) do
            if region and region.name == savedRegionName then
                selectedRegion = region
                break
            end
        end
    end

    if selectedRegion then
        mapSpawnSelect.selectedRegion = selectedRegion
    else
        selectedRegion = mapSpawnSelect:useDefaultSpawnRegion()
    end

    if selectedRegion and selectedRegion.name then
        setSpawnRegion(selectedRegion.name)
        getCore():setSelectedMap(tostring(selectedRegion.name))
        QuickRestartLog.info("checkPendingRestart restoreSavedSpawnRegion applied"
            .. " requestedRegion=" .. tostring(savedRegionName)
            .. " selectedRegion=" .. tostring(selectedRegion.name)
            .. " usedDefault=" .. tostring(selectedRegion.name ~= savedRegionName))
        return selectedRegion
    end

    QuickRestartLog.warn("checkPendingRestart restoreSavedSpawnRegion failed requestedRegion=" .. tostring(savedRegionName))
    return nil
end

function QuickRestartLocalPersistence.getSaveFileName()
    return QuickRestartSnapshotCodec.getGlobalSaveFileName()
end

function QuickRestartLocalPersistence.getSaveFileNameForPlayer(playerIdentifier)
    return QuickRestartSnapshotCodec.getPerPlayerSaveFileName(playerIdentifier)
end

function QuickRestartLocalPersistence.writeDataToFile(data, customFileName, sandboxVars)
    QuickRestartSandbox.logSnapshot("writeDataToFile file=" .. tostring(customFileName or QuickRestartLocalPersistence.getSaveFileName()), sandboxVars)
    QuickRestartLog.info("writeDataToFile snapshot"
        .. " file=" .. tostring(customFileName or QuickRestartLocalPersistence.getSaveFileName())
        .. " name=" .. tostring(data and data.name)
        .. " region=" .. tostring(data and data.region)
        .. " worldMap=" .. tostring(data and data.worldMap))
    return QuickRestartSnapshotCodec.writeDataToFile(data, customFileName, sandboxVars)
end

function QuickRestartLocalPersistence.readDataFromFile(customFileName)
    local data = QuickRestartSnapshotCodec.readDataFromFile(customFileName)
    if data then
        QuickRestartLog.info("readDataFromFile snapshot"
            .. " file=" .. tostring(customFileName or QuickRestartLocalPersistence.getSaveFileName())
            .. " name=" .. tostring(data.name)
            .. " region=" .. tostring(data.region)
            .. " worldMap=" .. tostring(data.worldMap))
        return data
    end

    data = QuickRestartLegacyCodec.readDataFromFile(customFileName)
    if data then
        QuickRestartLog.info("readDataFromFile migrated legacy snapshot file=" .. tostring(customFileName or QuickRestartLocalPersistence.getSaveFileName()))
        QuickRestartLocalPersistence.writeDataToFile(data, customFileName, data.sandbox)
    end

    return data
end

function QuickRestartLocalPersistence.deletePendingDataFile()
    local fileName = QuickRestartLocalPersistence.getSaveFileName()
    local writer = getFileWriter(fileName, true, false)
    if writer then
        writer:write("")
        writer:close()
    end
end

function QuickRestartLocalPersistence.saveSandboxData(saveFilePath)
    local data = QuickRestartLocalPersistence.readDataFromFile(saveFilePath)
    if not data then
        QuickRestartLog.warn("saveSandboxData skipped file=" .. tostring(saveFilePath) .. " data=<nil>")
        return
    end

    if data.sandbox then
        for _ in pairs(data.sandbox) do
            QuickRestartSandbox.logSnapshot("saveSandboxData existing file=" .. tostring(saveFilePath), data.sandbox)
            return
        end
    end

    QuickRestartSandbox.logSnapshot("saveSandboxData current SandboxVars file=" .. tostring(saveFilePath), SandboxVars)
    QuickRestartLocalPersistence.writeDataToFile(data, saveFilePath, SandboxVars)
end

function QuickRestartLocalPersistence.fetchSandboxVarsAtCreation(data)
    local snapshot = QuickRestartSandbox.extractFromSnapshot(data)
    QuickRestartSandbox.logSnapshot("fetchSandboxVarsAtCreation", snapshot)
    return snapshot
end

function QuickRestartLocalPersistence.fetchSandboxVarsAtDeath()
    local snapshot = QuickRestartSandbox.captureCurrent()
    QuickRestartSandbox.logSnapshot("fetchSandboxVarsAtDeath", snapshot)
    return snapshot
end

function QuickRestartLocalPersistence.sandboxDiffers(sandboxVarsCreation, sandboxVarsCurrent)
    QuickRestartSandbox.logSnapshot("sandboxDiffers creation", sandboxVarsCreation)
    QuickRestartSandbox.logSnapshot("sandboxDiffers current", sandboxVarsCurrent)
    return QuickRestartSandbox.differs(sandboxVarsCreation, sandboxVarsCurrent)
end

function QuickRestartLocalPersistence.loadDataFromSaveFolder(playerIdentifier)
    local fileName = QuickRestartLocalPersistence.getSaveFileNameForPlayer(playerIdentifier)
    return QuickRestartLocalPersistence.readDataFromFile(fileName)
end

function QuickRestartLocalPersistence.doRestartNewWorld(data, playerIdentifier, sandboxVars)
    QuickRestartSandbox.logSnapshot("doRestartNewWorld player=" .. tostring(playerIdentifier), sandboxVars)
    QuickRestartLocalPersistence.writeDataToFile(data, nil, sandboxVars)

    local oldFileName = QuickRestartLocalPersistence.getSaveFileNameForPlayer(playerIdentifier)
    local writer = getFileWriter(oldFileName, true, false)
    if writer then
        writer:write("")
        writer:close()
    end

    getCore():exitToMenu()
end

function QuickRestartLocalPersistence.checkPendingRestart(saveDataTable)
    local data = QuickRestartLocalPersistence.readDataFromFile()
    if not data or not data.name then
        QuickRestartLog.info("checkPendingRestart no pending data")
        return nil
    end

    QuickRestartSandbox.logSnapshot("checkPendingRestart loaded", data.sandbox)

    if data.sandbox then
        for key, value in pairs(data.sandbox) do
            SandboxVars[key] = value
        end
        QuickRestartSandbox.logSnapshot("checkPendingRestart applied SandboxVars", SandboxVars)
    end

    if saveDataTable then
        saveDataTable.saveData = data
    end

    if not MainScreen or not MainScreen.instance or not MainScreen.instance.desc then
        return data
    end

    local desc = MainScreen.instance.desc
    desc:setForename(data.forename or "John")
    desc:setSurname(data.surname or "Doe")
    desc:setFemale(data.gender == "female")

    if data.voice then
        if data.voice.prefix then
            desc:setVoicePrefix(data.voice.prefix)
        end
        if data.voice.type then
            desc:setVoiceType(data.voice.type)
        end
        if data.voice.pitch then
            desc:setVoicePitch(data.voice.pitch)
        end
    end

    if data.profession then
        local characterProfession = resolveCharacterProfession(data.profession)
        if characterProfession then
            desc:setCharacterProfession(characterProfession)
        end
    end

    if type(data.modData) == "table" and type(data.modData.descriptor) == "table" and desc.getModData then
        local hasSPNCharCustom = type(data.modData.descriptor.SPNCharCustom) == "table"
        QuickRestartLog.info("checkPendingRestart descriptor injection begin"
            .. " hasDescriptorModData=true"
            .. " hasSPNCharCustom=" .. tostring(hasSPNCharCustom))
        local okModData, descriptorModData = pcall(function()
            return desc:getModData()
        end)
        if okModData and type(descriptorModData) == "table" then
            for key, value in pairs(data.modData.descriptor) do
                descriptorModData[key] = value
            end
            QuickRestartLog.info("checkPendingRestart descriptor injection applied"
                .. " hasSPNCharCustomAfter=" .. tostring(type(descriptorModData.SPNCharCustom) == "table"))
        else
            QuickRestartLog.warn("checkPendingRestart descriptor injection failed to read descriptor modData")
        end
    else
        QuickRestartLog.info("checkPendingRestart descriptor injection skipped"
            .. " hasModData=" .. tostring(type(data.modData) == "table")
            .. " hasDescriptor=" .. tostring(type(data.modData) == "table" and type(data.modData.descriptor) == "table")
            .. " descHasGetModData=" .. tostring(desc.getModData ~= nil))
    end

    local worldName = "QuickRestart_" .. os.time()

    if data.isChallenge and data.challengeID then
        local targetChallenge = nil
        if LastStandChallenge then
            for i, challenge in ipairs(LastStandChallenge) do
                if challenge.id == data.challengeID then
                    targetChallenge = challenge
                    break
                end
            end
        end

        if targetChallenge then
            if getWorld().setDifficulty then
                getWorld():setDifficulty("Hardcore")
            end
            LastStandData.chosenChallenge = targetChallenge
            doChallenge(targetChallenge)
            getWorld():setWorld(worldName)
            createWorld(worldName)
            GameWindow.doRenderEvent(false)
            forceChangeState(LoadingQueueState.new())
            return data
        end
    end

    local targetMap = nil
    if type(data.worldMap) == "string" and data.worldMap ~= "" then
        targetMap = data.worldMap
    elseif type(data.region) == "string" and data.region ~= "" then
        targetMap = data.region
    end

    if targetMap then
        QuickRestartLog.info("checkPendingRestart launching world"
            .. " worldName=" .. tostring(worldName)
            .. " region=" .. tostring(data.region)
            .. " worldMap=" .. tostring(data.worldMap)
            .. " targetMap=" .. tostring(targetMap))
        getWorld():setGameMode("Sandbox")
        getWorld():setMap(targetMap)
        restoreSavedSpawnRegion(data)
        createWorld(worldName)
        GameWindow.doRenderEvent(false)
        forceChangeState(LoadingQueueState.new())
    else
        QuickRestartLog.warn("checkPendingRestart missing targetMap"
            .. " region=" .. tostring(data.region)
            .. " worldMap=" .. tostring(data.worldMap))
    end

    return data
end

return QuickRestartLocalPersistence
