require("QuickRestart_ClientBootstrap")

if not getActivatedMods():contains("ThisIsYourLife") then
    return false
end

local TRAIT_PREFIX = "ThisIsYourLife:"

local apiWarned = false

local function logInfo(message)
    if QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("tiyl compat " .. tostring(message))
    end
end

local function logWarn(message)
    if QuickRestartLog and QuickRestartLog.warn then
        QuickRestartLog.warn("tiyl compat " .. tostring(message))
    end
end

local function isTIYLApiAvailable()
    local available = type(TIYL) == "table"
        and type(TIYL.Flow) == "table"
        and type(TIYL.Flow.completeOrigin) == "function"
        and type(TIYL.Origins) == "table"
        and type(TIYL.REGION_NAME) == "string"

    if not available and not apiWarned then
        apiWarned = true
        logWarn("TIYL API unavailable, compat disabled")
    end

    return available
end

local function isSerializableScalar(value)
    return type(value) == "string" or type(value) == "number"
end

local function stripTIYLTraits(data)
    if type(data) ~= "table" or type(data.traits) ~= "table" then
        return 0
    end

    local removed = 0
    for i = #data.traits, 1, -1 do
        local trait = data.traits[i]
        if type(trait) == "string" and string.find(trait, TRAIT_PREFIX, 1, true) == 1 then
            table.remove(data.traits, i)
            removed = removed + 1
        end
    end

    return removed
end

local function resolveTIYLIdentity(data)
    if type(data) ~= "table" then
        return nil, nil
    end

    local originId = nil
    local posterStoryId = nil

    if type(data.compat) == "table" then
        if isSerializableScalar(data.compat.tiylOriginId) then
            originId = data.compat.tiylOriginId
        end
        if isSerializableScalar(data.compat.tiylPosterStoryId) then
            posterStoryId = data.compat.tiylPosterStoryId
        end
    end

    if originId == nil and posterStoryId == nil then
        local legacy = type(data.modData) == "table"
            and type(data.modData.player) == "table"
            and type(data.modData.player.TIYL) == "table"
            and data.modData.player.TIYL or nil
        if legacy then
            if isSerializableScalar(legacy.originId) then
                originId = legacy.originId
            end
            if isSerializableScalar(legacy.posterStoryId) then
                posterStoryId = legacy.posterStoryId
            end
        end
    end

    return originId, posterStoryId
end

local function hasLegacyTIYLBlock(data)
    return type(data) == "table"
        and type(data.modData) == "table"
        and type(data.modData.player) == "table"
        and type(data.modData.player.TIYL) == "table"
end

local function wantRandomSpawn(data)
    local random = false
    pcall(function()
        random = QuickRestartRestartOptions.sanitize(type(data) == "table" and data.options or nil).spawn
            == QuickRestartRestartOptions.RANDOM
    end)
    return random
end

local function selectTIYLRegion(mapSpawnSelect)
    if not mapSpawnSelect then
        return false
    end

    if mapSpawnSelect.selectedRegion and mapSpawnSelect.selectedRegion.name == TIYL.REGION_NAME then
        return true
    end

    if mapSpawnSelect.listbox and type(mapSpawnSelect.listbox.items) == "table" then
        for index, entry in ipairs(mapSpawnSelect.listbox.items) do
            local region = entry.item and entry.item.region or nil
            if region and region.name == TIYL.REGION_NAME then
                mapSpawnSelect.listbox.selected = index
                mapSpawnSelect.selectedRegion = region
                return true
            end
        end
    end

    local ok, regions = pcall(function()
        return mapSpawnSelect:getSpawnRegions()
    end)
    if ok and type(regions) == "table" then
        for _, region in ipairs(regions) do
            if region and region.name == TIYL.REGION_NAME then
                mapSpawnSelect.selectedRegion = region
                return true
            end
        end
    end

    return false
end

local function replayOrigin(originId)
    local okCall = pcall(TIYL.Flow.completeOrigin, originId)
    local attached = okCall and TIYL.PendingOriginId ~= nil
    logInfo("replay origin originId=" .. tostring(originId)
        .. " callOk=" .. tostring(okCall)
        .. " pendingSet=" .. tostring(attached))
    return attached
end

local function replayPosterStory(posterStoryId)
    if type(TIYL.Flow.completePosterStory) ~= "function" then
        logWarn("replay poster story unavailable in TIYL API storyId=" .. tostring(posterStoryId))
        return false
    end

    local okCall = pcall(TIYL.Flow.completePosterStory, posterStoryId)
    local attached = okCall and TIYL.PendingPosterStoryId ~= nil
    logInfo("replay poster story storyId=" .. tostring(posterStoryId)
        .. " callOk=" .. tostring(okCall)
        .. " pendingSet=" .. tostring(attached))
    return attached
end

local function onSnapshotCaptured(data, player)
    if type(data) ~= "table" or not player then
        return
    end

    if not isTIYLApiAvailable() then
        return
    end

    local originId = nil
    local posterStoryId = nil
    pcall(function()
        local modData = player.getModData and player:getModData() or nil
        local tiyl = type(modData) == "table" and type(modData.TIYL) == "table" and modData.TIYL or nil
        if tiyl then
            if isSerializableScalar(tiyl.originId) then
                originId = tiyl.originId
            end
            if isSerializableScalar(tiyl.posterStoryId) then
                posterStoryId = tiyl.posterStoryId
            end
        end
    end)

    if originId ~= nil or posterStoryId ~= nil then
        data.compat = type(data.compat) == "table" and data.compat or {}
        data.compat.tiylOriginId = originId
        data.compat.tiylPosterStoryId = posterStoryId
    end

    local removed = stripTIYLTraits(data)

    logInfo("snapshot captured originId=" .. tostring(originId)
        .. " posterStoryId=" .. tostring(posterStoryId)
        .. " removedTraits=" .. tostring(removed)
        .. " region=" .. tostring(data.region))
end

local function prepareTIYLSpawnRegion(context)
    if not isTIYLApiAvailable() then
        return nil
    end

    if type(context) ~= "table" or type(context.data) ~= "table" then
        return nil
    end

    local data = context.data
    local randomSpawn = wantRandomSpawn(data)

    if context.regionName ~= TIYL.REGION_NAME and not randomSpawn then
        return nil
    end

    local originId, posterStoryId = resolveTIYLIdentity(data)
    local mapSpawnSelect = context.mapSpawnSelect

    if randomSpawn then
        if not selectTIYLRegion(mapSpawnSelect) then
            logWarn("random spawn could not select the TIYL region")
        end
        replayOrigin("random")
        return TIYL.REGION_NAME
    end

    if posterStoryId ~= nil then
        if isMultiplayer() then
            logWarn("poster story replay skipped in multiplayer storyId=" .. tostring(posterStoryId))
            return nil
        end
        if not selectTIYLRegion(mapSpawnSelect) then
            logWarn("poster story replay could not select the TIYL region storyId=" .. tostring(posterStoryId))
        end
        replayPosterStory(posterStoryId)
        return nil
    end

    if originId ~= nil then
        if not selectTIYLRegion(mapSpawnSelect) then
            logWarn("origin replay could not select the TIYL region originId=" .. tostring(originId))
        end
        replayOrigin(originId)
        return nil
    end

    logWarn("TIYL region selected but no origin or poster story resolved, keeping fallback points")
    return nil
end

local function onBeforeApply(data, sameWorld, player)
    if type(data) ~= "table" then
        return
    end

    local removed = stripTIYLTraits(data)
    local originId, posterStoryId = resolveTIYLIdentity(data)

    logInfo("before apply sameWorld=" .. tostring(sameWorld)
        .. " removedTraits=" .. tostring(removed)
        .. " legacyBlock=" .. tostring(hasLegacyTIYLBlock(data))
        .. " originId=" .. tostring(originId)
        .. " posterStoryId=" .. tostring(posterStoryId))
end

local function onAfterApply(data, sameWorld, player)
    pcall(function()
        local modData = player and player.getModData and player:getModData() or nil
        local tiyl = type(modData) == "table" and type(modData.TIYL) == "table" and modData.TIYL or nil
        local traitPresent = false
        if player and player.getCharacterTraits then
            local characterTraits = player:getCharacterTraits()
            if characterTraits and characterTraits.getKnownTraits then
                local knownTraits = characterTraits:getKnownTraits()
                if knownTraits then
                    for i = 0, knownTraits:size() - 1 do
                        local traitType = knownTraits:get(i)
                        if traitType and string.find(tostring(traitType), TRAIT_PREFIX, 1, true) ~= nil then
                            traitPresent = true
                            break
                        end
                    end
                end
            end
        end

        logInfo("after apply sameWorld=" .. tostring(sameWorld)
            .. " originAttached=" .. tostring(tiyl and tiyl.originId or nil)
            .. " posterStoryAttached=" .. tostring(tiyl and tiyl.posterStoryId or nil)
            .. " originTraitPresent=" .. tostring(traitPresent))
    end)
end

Events.OnQuickRestartSnapshotCaptured.Add(onSnapshotCaptured)
Events.OnQuickRestartBeforeApply.Add(onBeforeApply)
Events.OnQuickRestartAfterApply.Add(onAfterApply)
QuickRestartClientFlow.registerSpawnRegionPreparer(prepareTIYLSpawnRegion)

return true
