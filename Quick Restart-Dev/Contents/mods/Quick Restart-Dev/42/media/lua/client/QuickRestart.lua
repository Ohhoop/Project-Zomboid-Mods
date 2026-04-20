
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

local function isFaceBodyLocation(bodyLocation)
    if type(bodyLocation) ~= "string" or bodyLocation == "" then
        return false
    end

    return string.find(string.lower(bodyLocation), "face", 1, true) ~= nil
end

local function findFaceClothingEntry(data)
    if type(data) ~= "table" or type(data.clothing) ~= "table" then
        return nil
    end

    for _, clothingData in ipairs(data.clothing) do
        if type(clothingData) == "table" and isFaceBodyLocation(clothingData.bodyLocation) then
            return clothingData
        end
    end

    return nil
end

local function summarizeFaceEntry(faceEntry)
    if type(faceEntry) ~= "table" then
        return "face=nil"
    end

    return "faceType=" .. tostring(faceEntry.type)
        .. " faceBodyLocation=" .. tostring(faceEntry.bodyLocation)
end

local function countTableEntries(tbl)
    if type(tbl) ~= "table" then
        return 0
    end

    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function getPlayerSPNCharCustom(data)
    if type(data) ~= "table"
        or type(data.modData) ~= "table"
        or type(data.modData.player) ~= "table"
        or type(data.modData.player.SPNCharCustom) ~= "table" then
        return nil
    end

    return data.modData.player.SPNCharCustom
end

local function shouldRejectRegressiveSnapshot(capturedData, existingSnapshot)
    if type(capturedData) ~= "table" or type(existingSnapshot) ~= "table" then
        return false, nil
    end

    local existingFace = findFaceClothingEntry(existingSnapshot)
    local capturedFace = findFaceClothingEntry(capturedData)
    if existingFace and not capturedFace then
        return true, "missing_face_layer"
    end

    local existingSPN = getPlayerSPNCharCustom(existingSnapshot)
    local capturedSPN = getPlayerSPNCharCustom(capturedData)
    if existingSPN and not capturedSPN then
        return true, "missing_player_SPNCharCustom"
    end

    local existingSPNCount = countTableEntries(existingSPN)
    local capturedSPNCount = countTableEntries(capturedSPN)
    if existingSPNCount > 0 and capturedSPNCount == 0 then
        return true, "empty_player_SPNCharCustom"
    end

    return false, nil
end

local function shouldReplaceSnapshotForFace(capturedData, existingSnapshot)
    local capturedFace = findFaceClothingEntry(capturedData)
    if not capturedFace then
        return false
    end

    local existingFace = findFaceClothingEntry(existingSnapshot)
    if not existingFace then
        return true
    end

    if tostring(existingFace.type) ~= tostring(capturedFace.type) then
        return true
    end

    return tostring(existingFace.bodyLocation) ~= tostring(capturedFace.bodyLocation)
end

local function saveCharacterData(player, saveFilePath)
    local data = captureCharacterData(player)
    if not data then
        if isMultiplayer() then
            QuickRestartLog.warn("mp client saveCharacterData aborted: capture returned nil")
        end
        return
    end

    if saveFilePath and not isMultiplayer() then
        writeDataToFile(data, saveFilePath)
    end

    if isMultiplayer() then
        local allowReplace = QuickRestartClientState.replaceSnapshotOnNextCapture == true
        local capturedFace = findFaceClothingEntry(data)
        local existingFace = findFaceClothingEntry(QuickRestartClientState.serverSnapshot)
        local rejectReplace, rejectReason = shouldRejectRegressiveSnapshot(data, QuickRestartClientState.serverSnapshot)
        if rejectReplace then
            allowReplace = false
            QuickRestartLog.warn("mp client saveCharacterData keeping existing snapshot due to regressive capture reason="
                .. tostring(rejectReason))
        end
        if not allowReplace and shouldReplaceSnapshotForFace(data, QuickRestartClientState.serverSnapshot) then
            allowReplace = true
            QuickRestartLog.info("mp client saveCharacterData enabling snapshot replace to persist face layer")
        end

        QuickRestartLog.info("mp client saveCharacterData captured snapshot for submit"
            .. " allowReplace=" .. tostring(allowReplace)
            .. " name=" .. tostring(data.name)
            .. " region=" .. tostring(data.region)
            .. " captured" .. " " .. summarizeFaceEntry(capturedFace)
            .. " existing" .. " " .. summarizeFaceEntry(existingFace))
        sendSnapshotPayload(player, data, allowReplace)
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
    if isMultiplayer() then
        QuickRestartLog.info("mp client QuickRestart.RestartNewWorld invoked")
    end
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
    if isMultiplayer() then
        QuickRestartLog.info("mp client QuickRestart.RestartSameWorld invoked"
            .. " hasServerSnapshot=" .. tostring(QuickRestartClientState.serverSnapshot ~= nil)
            .. " serverSnapshotLoaded=" .. tostring(QuickRestartClientState.serverSnapshotLoaded)
            .. " pendingRestartMode=" .. tostring(QuickRestartClientState.pendingRestartMode))
    end
    return QuickRestartClientFlow.restartSameWorld({
        getPlayerIdentifier = getPlayerIdentifier,
        loadDataFromSaveFolder = loadDataFromSaveFolder,
        startSameWorldRestartFromSnapshot = startSameWorldRestartFromSnapshot,
        sendRestartIntent = sendRestartIntent,
    })
end

startSameWorldRestartFromSnapshot = function(data)
    if isMultiplayer() then
        QuickRestartLog.info("mp client QuickRestart.startSameWorldRestartFromSnapshot wrapper"
            .. " name=" .. tostring(data and data.name)
            .. " region=" .. tostring(data and data.region))
    end
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
        showTransitionOverlay = function()
            QuickRestartUI.showTransitionOverlay()
        end,
        hideTransitionOverlay = function()
            QuickRestartUI.hideTransitionOverlay()
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
        if isMultiplayer() then
            QuickRestartLog.info("mp client consumePendingSameWorldData returning snapshot"
                .. " name=" .. tostring(data and data.name)
                .. " region=" .. tostring(data and data.region))
        end
        QuickRestart.pendingSameWorld = nil
        QuickRestart.sameWorldData = nil
        return data
    end

    if isMultiplayer() then
        QuickRestartLog.info("mp client consumePendingSameWorldData found no pending snapshot")
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

    sendClientCommand(QuickRestartConstants.MODULE, QuickRestartConstants.COMMANDS.APPLY_AUTHORITATIVE_SNAPSHOT, {
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
                if isMultiplayer() then
                    QuickRestartLog.info("mp client scheduleDelayedSave skipped: character data already saved")
                end
                return
            end

            if isMultiplayer() then
                QuickRestartLog.info("mp client scheduleDelayedSave queued delayTicks=60 saveFilePath=" .. tostring(saveFilePath))
            end
            QuickRestartScheduler.scheduleAfterTicks("delayed_save_" .. tostring(getPlayerIdentifier(playerObj) or "player"), 60, function()
                if not characterDataSaved then
                    characterDataSaved = true
                    if isMultiplayer() then
                        QuickRestartLog.info("mp client delayed save firing now")
                    end
                    saveCharacterData(playerObj, saveFilePath)
                elseif isMultiplayer() then
                    QuickRestartLog.info("mp client delayed save skipped at fire time: already saved")
                end
            end)
        end,
        applyLoadedCharacter = function(playerObj, data, sameWorldRestart)
            if isMultiplayer() then
                QuickRestartLog.info("mp client QuickRestart.lua applyLoadedCharacter callback"
                    .. " name=" .. tostring(data and data.name)
                    .. " clothingCount=" .. tostring(type(data and data.clothing) == "table" and #data.clothing or 0)
                    .. " traitsCount=" .. tostring(type(data and data.traits) == "table" and #data.traits or 0))
            end
            triggerEvent("OnQuickRestartBeforeApply", data, sameWorldRestart, playerObj)
            QuickRestartApply.applyLoadedCharacter(playerObj, data, {
                onPendingMPFinalize = function(skills)
                    if isMultiplayer() then
                        QuickRestartLog.info("mp client pendingMPRestore finalized hasSkills="
                            .. tostring(type(skills) == "table"))
                    end
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
            triggerEvent("OnQuickRestartAfterApply", data, sameWorldRestart, playerObj)
        end,
        onSameWorldRestartApplied = function(playerObj)
            QuickRestartApply.refreshPlayerLighting(playerObj, {
                scheduler = QuickRestartScheduler,
                delayTicks = isMultiplayer() and 4 or 20,
            })
            QuickRestartScheduler.scheduleAfterTicks("hide_same_world_transition_overlay", 30, function()
                QuickRestartUI.hideTransitionOverlay()
            end)
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
