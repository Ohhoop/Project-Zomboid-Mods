
require('NPCs/MainCreationMethods')
require('QuickRestart_ClientBootstrap')

QuickRestart = QuickRestart or {}
QuickRestart.saveData = nil
QuickRestart.pendingSameWorld = nil
QuickRestart.sameWorldData = nil
QuickRestart.pendingMPRestore = nil

local function getPlayerIdentifier(player)
    if not player then return nil end
    if isMultiplayer() then
        return "player"
    end
    return tostring(player:getPlayerNum())
end

local function canUseFreshWorld()
    if isMultiplayer() then return false end
    if getNumActivePlayers() > 1 then return false end
    return true
end

local writeDataToFile
local loadDataFromFile
local loadDataFromSaveFolder
local restartPanel
local captureCharacterData
local startSameWorldRestartFromSnapshot

local function sendRestartIntent(player, commandName)
    return QuickRestartClientNetwork.sendRestartIntent(player, commandName, QuickRestartClientState)
end

local function requestActiveServerSnapshot(player)
    return QuickRestartClientNetwork.requestActiveServerSnapshot(player, QuickRestartClientState)
end

local function sendSnapshotPayload(player, data, allowReplace)
    return QuickRestartClientNetwork.sendSnapshotPayload(player, data, allowReplace, QuickRestartClientState)
end

local function retryPendingSnapshot(player)
    return QuickRestartClientNetwork.retryPendingSnapshot(player, QuickRestartClientState, captureCharacterData)
end

captureCharacterData = function(player)
    return QuickRestartCapture.captureCharacterData(player, {
        visualItemTypes = {
            fHairStubble = F_HAIR_STUBBLE,
            mHairStubble = M_HAIR_STUBBLE,
            mBeardStubble = M_BEARD_STUBBLE,
        },
    })
end

local function saveCharacterData(player, saveFilePath)
    local data = captureCharacterData(player)
    if not data then
        return
    end

    if saveFilePath and not isMultiplayer() then
        writeDataToFile(data, saveFilePath)
    end

    if isMultiplayer() then
        sendSnapshotPayload(player, data, QuickRestartClientState.replaceSnapshotOnNextCapture == true)
        QuickRestartClientState.replaceSnapshotOnNextCapture = false
    end

    return data
end

local characterDataSaved = false

local F_HAIR_STUBBLE = QuickRestartConstants.VISUAL.F_HAIR_STUBBLE
local M_HAIR_STUBBLE = QuickRestartConstants.VISUAL.M_HAIR_STUBBLE
local M_BEARD_STUBBLE = QuickRestartConstants.VISUAL.M_BEARD_STUBBLE
local INVENTORY_CONTAINER = QuickRestartConstants.VISUAL.INVENTORY_CONTAINER

local function getSaveFileNameForPlayer(playerIdentifier)
    return QuickRestartLocalPersistence.getSaveFileNameForPlayer(playerIdentifier)
end

writeDataToFile = function(data, customFileName, sandboxVars)
    return QuickRestartLocalPersistence.writeDataToFile(data, customFileName, sandboxVars)
end

local function deleteDataFile()
    return QuickRestartLocalPersistence.deletePendingDataFile()
end

local saveSandboxData
saveSandboxData = function(saveFilePath)
    return QuickRestartLocalPersistence.saveSandboxData(saveFilePath)
end

local function fetchSandboxVarsAtCreation(data)
    return QuickRestartLocalPersistence.fetchSandboxVarsAtCreation(data)
end

local function fetchSandboxVarsAtDeath()
    return QuickRestartLocalPersistence.fetchSandboxVarsAtDeath()
end

local function sandboxDiffers(sandboxVarsCreation, sandboxVarsCurrent)
    return QuickRestartLocalPersistence.sandboxDiffers(sandboxVarsCreation, sandboxVarsCurrent)
end

local function doRestartNewWorld(data, playerIdentifier, sandboxVars)
    return QuickRestartLocalPersistence.doRestartNewWorld(data, playerIdentifier, sandboxVars)
end

function QuickRestart.RestartNewWorld()
    return QuickRestartClientFlow.restartNewWorld({
        canUseFreshWorld = canUseFreshWorld,
        getPlayerIdentifier = getPlayerIdentifier,
        loadDataFromSaveFolder = loadDataFromSaveFolder,
        fetchSandboxVarsAtCreation = fetchSandboxVarsAtCreation,
        fetchSandboxVarsAtDeath = fetchSandboxVarsAtDeath,
        sandboxDiffers = sandboxDiffers,
        getRestartPanel = function()
            return restartPanel
        end,
        doRestartNewWorld = doRestartNewWorld,
        sendRestartIntent = sendRestartIntent,
    })
end

function QuickRestart.RestartSameWorld()
    return QuickRestartClientFlow.restartSameWorld({
        getPlayerIdentifier = getPlayerIdentifier,
        loadDataFromSaveFolder = loadDataFromSaveFolder,
        startSameWorldRestartFromSnapshot = startSameWorldRestartFromSnapshot,
        sendRestartIntent = sendRestartIntent,
    })
end

startSameWorldRestartFromSnapshot = function(data)
    return QuickRestartClientFlow.startSameWorldRestartFromSnapshot(data, {
        closePanel = function()
            if restartPanel then
                restartPanel:removeFromUIManager()
                restartPanel = nil
            end
        end,
        clearPending = function()
            QuickRestart.pendingSameWorld = nil
            QuickRestart.sameWorldData = nil
        end,
        setPendingSameWorld = function(snapshot)
            QuickRestart.pendingSameWorld = true
            QuickRestart.sameWorldData = snapshot
        end,
        scheduler = QuickRestartScheduler,
        visualItemTypes = {
            fHairStubble = F_HAIR_STUBBLE,
            mHairStubble = M_HAIR_STUBBLE,
            mBeardStubble = M_BEARD_STUBBLE,
        },
    })
end

loadDataFromFile = function(customFileName)
    return QuickRestartLocalPersistence.readDataFromFile(customFileName)
end

loadDataFromSaveFolder = function(playerIdentifier)
    if isMultiplayer() then
        return QuickRestartClientState.serverSnapshot
    end

    return QuickRestartLocalPersistence.loadDataFromSaveFolder(playerIdentifier)
end

local pendingRestartChecked = false

local function checkPendingRestart()
    if pendingRestartChecked then return end
    pendingRestartChecked = true

    QuickRestartLocalPersistence.checkPendingRestart(QuickRestart)
end

Events.OnMainMenuEnter.Add(checkPendingRestart)

restartPanel = nil

local function closeRestartPanel()
    if restartPanel then
        restartPanel:removeFromUIManager()
        restartPanel = nil
    end
end

local function consumePendingSameWorldData()
    if QuickRestart.pendingSameWorld and QuickRestart.sameWorldData then
        local data = QuickRestart.sameWorldData
        QuickRestart.pendingSameWorld = nil
        QuickRestart.sameWorldData = nil
        return data
    end

    return nil
end

local function consumeSavedData()
    local data = QuickRestart.saveData
    QuickRestart.saveData = nil
    return data
end

local function flushPendingMPRestore()
    if not QuickRestart.pendingMPRestore then
        return
    end

    if not QuickRestartClientState.pendingRestartGrantId then
        return
    end

    sendClientCommand(QuickRestartConstants.MODULE, QuickRestartConstants.COMMANDS.APPLY_SKILLS, {
        grantId = QuickRestartClientState.pendingRestartGrantId,
        profileKey = QuickRestartClientState.pendingProfileKey,
        username = QuickRestartClientState.pendingUsername,
        steamID = QuickRestartClientState.pendingSteamID,
    })
end

local function buildFlowOptions(extra)
    local options = {
        state = QuickRestartClientState,
        getRestartPanel = function()
            return restartPanel
        end,
        setRestartPanel = function(panel)
            restartPanel = panel
        end,
        getPlayerIdentifier = getPlayerIdentifier,
        loadDataFromSaveFolder = loadDataFromSaveFolder,
        canUseFreshWorld = canUseFreshWorld,
        onRestartNewWorld = function()
            QuickRestart.RestartNewWorld()
        end,
        onRestartSameWorld = function()
            QuickRestart.RestartSameWorld()
        end,
        onSandboxSaved = function(data, playerIdentifier)
            doRestartNewWorld(data, playerIdentifier, fetchSandboxVarsAtCreation(data))
        end,
        onSandboxCurrent = function(data, playerIdentifier, sandboxVarsCurrent)
            doRestartNewWorld(data, playerIdentifier, sandboxVarsCurrent)
        end,
    }

    if type(extra) == "table" then
        for key, value in pairs(extra) do
            options[key] = value
        end
    end

    return options
end

local function buildOnNewGameOptions()
    return {
        state = QuickRestartClientState,
        closeRestartPanel = closeRestartPanel,
        resetCharacterDataSaved = function()
            characterDataSaved = false
        end,
        resetPendingMPRestore = function()
            QuickRestart.pendingMPRestore = nil
        end,
        getPlayerIdentifier = getPlayerIdentifier,
        getSaveFileNameForPlayer = getSaveFileNameForPlayer,
        consumePendingSameWorldData = consumePendingSameWorldData,
        consumeSavedData = consumeSavedData,
        loadDataFromFile = loadDataFromFile,
        scheduleDelayedSave = function(playerObj, saveFilePath)
            if characterDataSaved then
                return
            end

            QuickRestartScheduler.scheduleAfterTicks("delayed_save_" .. tostring(getPlayerIdentifier(playerObj) or "player"), 60, function()
                if not characterDataSaved then
                    characterDataSaved = true
                    saveCharacterData(playerObj, saveFilePath)
                end
            end)
        end,
        applyLoadedCharacter = function(playerObj, data)
            QuickRestartApply.applyLoadedCharacter(playerObj, data, {
                onPendingMPFinalize = function(skills)
                    QuickRestart.pendingMPRestore = {
                        hasSkills = type(skills) == "table",
                    }
                end,
                scheduler = QuickRestartScheduler,
                visualItemTypes = {
                    fHairStubble = F_HAIR_STUBBLE,
                    mHairStubble = M_HAIR_STUBBLE,
                    mBeardStubble = M_BEARD_STUBBLE,
                },
                inventoryContainerType = INVENTORY_CONTAINER,
            })
        end,
        persistAppliedData = function(data, saveFilePath)
            writeDataToFile(data, saveFilePath, data.sandbox)
            deleteDataFile()
        end,
        scheduleSandboxCapture = function(saveFilePath)
            QuickRestartScheduler.scheduleAfterTicks("sandbox_capture_" .. tostring(saveFilePath or "default"), 60, function()
                if saveFilePath then
                    saveSandboxData(saveFilePath)
                end
            end)
        end,
    }
end

local function tryShowRestartPanel()
    return QuickRestartClientFlow.tryShowRestartPanel(buildFlowOptions())
end

Events.OnPlayerDeath.Add(function(player)
    QuickRestartClientFlow.onPlayerDeath(player, buildFlowOptions({
        requestActiveServerSnapshot = requestActiveServerSnapshot,
        resetPendingMPRestore = function()
            QuickRestart.pendingMPRestore = nil
        end,
    }))
end)

Events.OnPostUIDraw.Add(function()
    tryShowRestartPanel()
end)


Events.OnNewGame.Add(function(player, square)
    QuickRestartClientFlow.onNewGame(player, buildOnNewGameOptions())
end)

Events.OnGameTimeLoaded.Add(function()
    QuickRestartClientFlow.onGameTimeLoaded({
        requestActiveServerSnapshot = requestActiveServerSnapshot,
        flushPendingMPSkills = flushPendingMPRestore,
    })
end)

Events.OnServerCommand.Add(function(module, command, args)
    QuickRestartClientFlow.onServerCommand(module, command, args, buildFlowOptions({
        retryPendingSnapshot = retryPendingSnapshot,
        startSameWorldRestartFromSnapshot = startSameWorldRestartFromSnapshot,
        retryApplySkills = flushPendingMPRestore,
        onApplySkillsAck = function()
            QuickRestartClientState.pendingRestartGrantId = nil
            QuickRestart.pendingMPRestore = nil
        end,
        onApplySkillsDenied = function(reason)
            QuickRestartClientState.pendingRestartGrantId = nil
            QuickRestart.pendingMPRestore = nil
        end,
    }))
end)
