QuickRestartSpongiesCompat = QuickRestartSpongiesCompat or {}

QuickRestartSpongiesCompat.protection = QuickRestartSpongiesCompat.protection or nil

local originalTriggerEvent = originalTriggerEvent or triggerEvent
local originalSendClientCommand = originalSendClientCommand or sendClientCommand

local function logCompat(message)
    if QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("spongies compat " .. tostring(message))
    end
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

local function clearTable(tbl)
    if type(tbl) ~= "table" then
        return
    end

    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function applyTableData(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then
        return false
    end

    clearTable(target)

    local copy = deepCopySupportedValue(source, {})
    for key, value in pairs(copy or {}) do
        target[key] = value
    end

    return true
end

local function snapshotHasSPNCharCustom(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.modData) ~= "table" then
        return false
    end

    if type(snapshot.modData.player) == "table" and type(snapshot.modData.player.SPNCharCustom) == "table" then
        return true
    end

    if type(snapshot.modData.descriptor) == "table" and type(snapshot.modData.descriptor.SPNCharCustom) == "table" then
        return true
    end

    return false
end

local function getProtectedSPNCharCustom(sourceKey)
    local protection = QuickRestartSpongiesCompat.protection
    if type(protection) ~= "table" then
        return nil
    end

    if type(protection.modData) ~= "table" then
        return nil
    end

    if type(sourceKey) ~= "string" or type(protection.modData[sourceKey]) ~= "table" then
        return nil
    end

    if type(protection.modData[sourceKey].SPNCharCustom) ~= "table" then
        return nil
    end

    return protection.modData[sourceKey].SPNCharCustom
end

local function clearProtection()
    if QuickRestartSpongiesCompat.protection then
        logCompat("clear protection")
    end
    QuickRestartSpongiesCompat.protection = nil
end

local spongiesHookInstalled = false

local function ensureSCCHookInstalled()
    if spongiesHookInstalled then
        return true
    end

    local ok, FaceManager_Local = pcall(require, "CharacterCustomisation/FaceManager_Local")
    if not ok or type(FaceManager_Local) ~= "table" or type(FaceManager_Local.SetCustomisationNewCharacter) ~= "function" then
        return false
    end

    local original = FaceManager_Local.SetCustomisationNewCharacter
    FaceManager_Local.SetCustomisationNewCharacter = function(player, clientData)
        if QuickRestartSpongiesCompat.isProtectionActive and QuickRestartSpongiesCompat.isProtectionActive() then
            local protected = getProtectedSPNCharCustom("player")
            if type(protected) == "table" then
                local substitute = deepCopySupportedValue(protected, {})
                if type(substitute) == "table" then
                    logCompat("SetCustomisationNewCharacter intercepted: substituting clientData with protected snapshot faceId="
                        .. tostring(type(substitute.face) == "table" and substitute.face.id or nil))
                    clientData = substitute
                end
            end
        end
        return original(player, clientData)
    end

    spongiesHookInstalled = true
    logCompat("installed hook on FaceManager_Local.SetCustomisationNewCharacter")
    return true
end

local function refreshProtectionTimeout()
    local scheduler = QuickRestartScheduler
    if scheduler and scheduler.scheduleAfterTicks then
        scheduler.scheduleAfterTicks("spongies_snapshot_protection_timeout", 420, function()
            clearProtection()
        end)
    end
end

local function applyProtectedModData()
    local playerSPNCharCustom = getProtectedSPNCharCustom("player")
    local descriptorSPNCharCustom = getProtectedSPNCharCustom("descriptor")
    if type(playerSPNCharCustom) ~= "table" and type(descriptorSPNCharCustom) ~= "table" then
        return false
    end

    local player = getPlayer()
    if not player then
        return false
    end

    local applied = false

    if type(playerSPNCharCustom) == "table" and player.getModData then
        local ok, playerModData = pcall(function()
            return player:getModData()
        end)
        if ok and type(playerModData) == "table" then
            if type(playerModData.SPNCharCustom) ~= "table" then
                playerModData.SPNCharCustom = {}
            end

            applyTableData(playerModData.SPNCharCustom, playerSPNCharCustom)
            applied = true
        end
    end

    if type(descriptorSPNCharCustom) == "table" and player.getDescriptor then
        local okDescriptor, descriptor = pcall(function()
            return player:getDescriptor()
        end)
        if okDescriptor and descriptor and descriptor.getModData then
            local okModData, descriptorModData = pcall(function()
                return descriptor:getModData()
            end)
            if okModData and type(descriptorModData) == "table" then
                if type(descriptorModData.SPNCharCustom) ~= "table" then
                    descriptorModData.SPNCharCustom = {}
                end

                applyTableData(descriptorModData.SPNCharCustom, descriptorSPNCharCustom)
                applied = true
            end
        end
    end

    if not applied then
        return false
    end

    pcall(function()
        player:resetModel()
    end)
    QuickRestartSpongiesCompat.triggerClothingUpdated(player)

    logCompat("reapplied protected SPNCharCustom"
        .. " player=" .. tostring(type(playerSPNCharCustom) == "table")
        .. " descriptor=" .. tostring(type(descriptorSPNCharCustom) == "table"))
    return true
end

function QuickRestartSpongiesCompat.beginSnapshotProtection(snapshot)
    ensureSCCHookInstalled()

    local playerSPNCharCustom = type(snapshot) == "table"
        and type(snapshot.modData) == "table"
        and type(snapshot.modData.player) == "table"
        and type(snapshot.modData.player.SPNCharCustom) == "table"
        and snapshot.modData.player.SPNCharCustom
        or nil
    local descriptorSPNCharCustom = type(snapshot) == "table"
        and type(snapshot.modData) == "table"
        and type(snapshot.modData.descriptor) == "table"
        and type(snapshot.modData.descriptor.SPNCharCustom) == "table"
        and snapshot.modData.descriptor.SPNCharCustom
        or nil

    if type(playerSPNCharCustom) ~= "table" and type(descriptorSPNCharCustom) ~= "table" then
        clearProtection()
        logCompat("begin protection skipped: no SPNCharCustom in snapshot")
        return false
    end

    QuickRestartSpongiesCompat.protection = {
        modData = {
            player = type(playerSPNCharCustom) == "table" and {
                SPNCharCustom = deepCopySupportedValue(playerSPNCharCustom, {}),
            } or nil,
            descriptor = type(descriptorSPNCharCustom) == "table" and {
                SPNCharCustom = deepCopySupportedValue(descriptorSPNCharCustom, {}),
            } or nil,
        },
        authoritativePushDone = false,
    }

    logCompat("begin protection"
        .. " playerFace=" .. tostring(type(playerSPNCharCustom) == "table" and playerSPNCharCustom.face or nil)
        .. " descriptorFace=" .. tostring(type(descriptorSPNCharCustom) == "table" and descriptorSPNCharCustom.face or nil))

    refreshProtectionTimeout()

    return true
end

function QuickRestartSpongiesCompat.isProtectionActive()
    return QuickRestartSpongiesCompat.protection ~= nil
end

function QuickRestartSpongiesCompat.resolveBaseVisualOptions(snapshot)
    local hasSPNCharCustom = snapshotHasSPNCharCustom(snapshot)
    return {
        hasSPNCharCustom = hasSPNCharCustom,
        skipSkinTextureIndex = false,
        skipBodyHairIndex = false,
    }
end

function QuickRestartSpongiesCompat.beforeRestoreClothing(player)
    return false
end

function QuickRestartSpongiesCompat.triggerClothingUpdated(player)
    if not originalTriggerEvent then
        return
    end

    originalTriggerEvent("OnClothingUpdated", player)
end

local function buildSetCustomisationNewCharacterPayload(sourceData)
    if type(sourceData) ~= "table" then
        return nil
    end

    local copy = deepCopySupportedValue(sourceData, {})
    if type(copy) ~= "table" then
        return nil
    end

    local payload = {
        face = type(copy.face) == "table" and copy.face or { name = "DefaultFace", id = "DefaultFace", texture = 0 },
        bodyDetails = type(copy.bodyDetails) == "table" and copy.bodyDetails or {},
        bodyHair = copy.bodyHair == true,
        stubbleHead = copy.stubbleHead == true,
        stubbleBeard = copy.stubbleBeard == true,
        muscleVisuals = copy.muscleVisuals ~= false,
        bodyHairGrowth = copy.bodyHairGrowthEnabled == true,
    }

    return payload
end

local function pushCustomisationToServer()
    local playerSPNCharCustom = getProtectedSPNCharCustom("player")
    if type(playerSPNCharCustom) ~= "table" then
        return false
    end

    local player = getPlayer()
    if not player or not originalSendClientCommand then
        return false
    end

    local payload = buildSetCustomisationNewCharacterPayload(playerSPNCharCustom)
    if type(payload) ~= "table" then
        return false
    end

    originalSendClientCommand(player, "SPNCC", "SetCustomisationNewCharacter", { data = payload })
    logCompat("pushed SetCustomisationNewCharacter to server"
        .. " faceId=" .. tostring(payload.face and payload.face.id)
        .. " bodyDetails=" .. tostring(#payload.bodyDetails)
        .. " bodyHair=" .. tostring(payload.bodyHair)
        .. " stubbleHead=" .. tostring(payload.stubbleHead)
        .. " stubbleBeard=" .. tostring(payload.stubbleBeard))
    return true
end

QuickRestartSpongiesCompat.pushCustomisationToServer = pushCustomisationToServer

local function refreshLocalCustomisation()
    local player = getPlayer()
    if not player then
        return false
    end

    local ok, FaceManager_Local = pcall(require, "CharacterCustomisation/FaceManager_Local")
    if not ok or type(FaceManager_Local) ~= "table" or type(FaceManager_Local.RefreshCustomisation) ~= "function" then
        logCompat("refreshLocalCustomisation skipped: FaceManager_Local unavailable")
        return false
    end

    local okRefresh, err = pcall(function()
        FaceManager_Local.RefreshCustomisation(player)
    end)
    if not okRefresh then
        logCompat("refreshLocalCustomisation error: " .. tostring(err))
        return false
    end

    logCompat("refreshLocalCustomisation done")
    return true
end

QuickRestartSpongiesCompat.refreshLocalCustomisation = refreshLocalCustomisation

function QuickRestartSpongiesCompat.forceReapplyAndPush()
    local protection = QuickRestartSpongiesCompat.protection
    if type(protection) ~= "table" then
        logCompat("forceReapplyAndPush skipped: no protection active")
        return false
    end

    local scheduler = QuickRestartScheduler
    local function run()
        applyProtectedModData()
        if protection and not protection.authoritativePushDone then
            protection.authoritativePushDone = true
            if isMultiplayer() then
                pushCustomisationToServer()
            else
                refreshLocalCustomisation()
            end
        end
    end

    if scheduler and scheduler.scheduleAfterTicks then
        scheduler.scheduleAfterTicks("spongies_snapshot_force_reapply", 1, run)
    else
        run()
    end
    return true
end

local function onServerCommand(module, command, args)
    if module ~= "SPNCC" then
        return
    end

    if not QuickRestartSpongiesCompat.protection then
        return
    end

    if command ~= "SetPlayerModData" and command ~= "SetPlayerModDataValues" then
        return
    end

    refreshProtectionTimeout()

    local protection = QuickRestartSpongiesCompat.protection

    local function reapplyAndPush()
        applyProtectedModData()
        if protection and not protection.authoritativePushDone then
            protection.authoritativePushDone = true
            if isMultiplayer() then
                pushCustomisationToServer()
            else
                refreshLocalCustomisation()
            end
        end
    end

    local scheduler = QuickRestartScheduler
    if scheduler and scheduler.scheduleAfterTicks then
        scheduler.scheduleAfterTicks("spongies_snapshot_reapply", 1, reapplyAndPush)
    else
        reapplyAndPush()
    end
end

Events.OnServerCommand.Add(onServerCommand)

local function onQuickRestartBeforeApply(data, sameWorldRestart, player)
    logCompat("onQuickRestartBeforeApply sameWorldRestart=" .. tostring(sameWorldRestart))
    QuickRestartSpongiesCompat.beginSnapshotProtection(data)
end

local function onQuickRestartAfterApply(data, sameWorldRestart, player)
    logCompat("onQuickRestartAfterApply sameWorldRestart=" .. tostring(sameWorldRestart) .. " isMP=" .. tostring(isMultiplayer()))
    if isMultiplayer() then
        return
    end

    local scheduler = QuickRestartScheduler
    if not scheduler or not scheduler.scheduleAfterTicks then
        return
    end

    scheduler.scheduleAfterTicks("spongies_solo_force_push", 20, function()
        QuickRestartSpongiesCompat.forceReapplyAndPush()
    end)
end

Events.OnQuickRestartBeforeApply.Add(onQuickRestartBeforeApply)
Events.OnQuickRestartAfterApply.Add(onQuickRestartAfterApply)

return QuickRestartSpongiesCompat
