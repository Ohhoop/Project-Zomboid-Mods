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
    return QuickRestartLegacyCodec.getGlobalSaveFileName()
end

function QuickRestartLocalPersistence.getSaveFileNameForPlayer(playerIdentifier)
    return QuickRestartLegacyCodec.getPerPlayerSaveFileName(playerIdentifier)
end

function QuickRestartLocalPersistence.writeDataToFile(data, customFileName, sandboxVars)
    return QuickRestartLegacyCodec.writeDataToFile(data, customFileName, sandboxVars)
end

function QuickRestartLocalPersistence.readDataFromFile(customFileName)
    return QuickRestartLegacyCodec.readDataFromFile(customFileName)
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
        return
    end

    if data.sandbox then
        for _ in pairs(data.sandbox) do
            return
        end
    end

    QuickRestartLocalPersistence.writeDataToFile(data, saveFilePath, SandboxVars)
end

function QuickRestartLocalPersistence.fetchSandboxVarsAtCreation(data)
    return QuickRestartSandbox.extractFromSnapshot(data)
end

function QuickRestartLocalPersistence.fetchSandboxVarsAtDeath()
    return QuickRestartSandbox.captureCurrent()
end

function QuickRestartLocalPersistence.sandboxDiffers(sandboxVarsCreation, sandboxVarsCurrent)
    return QuickRestartSandbox.differs(sandboxVarsCreation, sandboxVarsCurrent)
end

function QuickRestartLocalPersistence.loadDataFromSaveFolder(playerIdentifier)
    local fileName = QuickRestartLocalPersistence.getSaveFileNameForPlayer(playerIdentifier)
    return QuickRestartLocalPersistence.readDataFromFile(fileName)
end

function QuickRestartLocalPersistence.doRestartNewWorld(data, playerIdentifier, sandboxVars)
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
        return nil
    end

    if data.sandbox then
        for key, value in pairs(data.sandbox) do
            SandboxVars[key] = value
        end
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

    if data.region then
        getWorld():setGameMode("Sandbox")
        getWorld():setMap(data.region)
        createWorld(worldName)
        GameWindow.doRenderEvent(false)
        forceChangeState(LoadingQueueState.new())
    end

    return data
end

return QuickRestartLocalPersistence
