QuickRestartLocalPersistence = QuickRestartLocalPersistence or {}

local function resolveCharacterProfession(profession)
    local professionType = tostring(profession or "unemployed")
    local characterProfession = CharacterProfession.get(ResourceLocation.of(professionType))
    if characterProfession then
        return characterProfession
    end

    return CharacterProfession.get(ResourceLocation.of("unemployed"))
end

function QuickRestartLocalPersistence.getSaveFileName()
    return QuickRestartSnapshotCodec.getGlobalSaveFileName()
end

function QuickRestartLocalPersistence.getSaveFileNameForPlayer(playerIdentifier)
    return QuickRestartSnapshotCodec.getPerPlayerSaveFileName(playerIdentifier)
end

function QuickRestartLocalPersistence.writeDataToFile(data, customFileName, sandboxVars)
    QuickRestartSandbox.logSnapshot("writeDataToFile file=" .. tostring(customFileName or QuickRestartLocalPersistence.getSaveFileName()), sandboxVars)
    return QuickRestartSnapshotCodec.writeDataToFile(data, customFileName, sandboxVars)
end

function QuickRestartLocalPersistence.readDataFromFile(customFileName)
    local data = QuickRestartSnapshotCodec.readDataFromFile(customFileName)
    if data then
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
        getWorld():setGameMode("Sandbox")
        getWorld():setMap(targetMap)
        createWorld(worldName)
        GameWindow.doRenderEvent(false)
        forceChangeState(LoadingQueueState.new())
    end

    return data
end

return QuickRestartLocalPersistence
