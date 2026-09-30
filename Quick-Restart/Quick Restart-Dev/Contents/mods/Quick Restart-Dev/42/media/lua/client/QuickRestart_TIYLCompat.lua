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

local function copySerializableTable(value, seen)
    if type(value) ~= "table" then
        return nil
    end

    seen = seen or {}
    if seen[value] then
        return nil
    end
    seen[value] = true

    local copy = {}
    for key, childValue in pairs(value) do
        local keyType = type(key)
        if keyType == "string" or keyType == "number" then
            local childType = type(childValue)
            if childType == "string" or childType == "number" or childType == "boolean" then
                copy[key] = childValue
            elseif childType == "table" then
                local childCopy = copySerializableTable(childValue, seen)
                if childCopy ~= nil then
                    copy[key] = childCopy
                end
            end
        end
    end

    seen[value] = nil
    return copy
end

local function countTimelineEntries(journal)
    if type(journal) ~= "table" or type(journal.timeline) ~= "table" then
        return 0
    end

    return #journal.timeline
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

local TIYL_SCREEN_KEYS = { "OriginSelect", "OriginMapBoard", "ProfessionSelect", "TraitSelect" }

local function closeTIYLScreens()
    local closed = 0

    for _, key in ipairs(TIYL_SCREEN_KEYS) do
        local screen = type(TIYL[key]) == "table" and TIYL[key] or nil
        local instance = screen and screen.instance or nil
        if instance then
            pcall(function() instance:setVisible(false) end)
            pcall(function() instance:removeFromUIManager() end)
            screen.instance = nil
            closed = closed + 1
        end
    end

    return closed
end

local function releaseTIYLFlow()
    local abandoned = false
    if type(TIYL.Flow.abandon) == "function" then
        abandoned = pcall(TIYL.Flow.abandon)
    end

    local closed = closeTIYLScreens()

    logInfo("flow released abandoned=" .. tostring(abandoned)
        .. " closedScreens=" .. tostring(closed))

    return abandoned
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
    local journal = nil
    local milestones = nil
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
            journal = copySerializableTable(tiyl.journal)
            milestones = copySerializableTable(tiyl.milestones)
        end
    end)

    if originId ~= nil or posterStoryId ~= nil or journal ~= nil or milestones ~= nil then
        data.compat = type(data.compat) == "table" and data.compat or {}
        data.compat.tiylOriginId = originId
        data.compat.tiylPosterStoryId = posterStoryId
        data.compat.tiylJournal = journal
        data.compat.tiylMilestones = milestones
    end

    local removed = stripTIYLTraits(data)

    logInfo("snapshot captured originId=" .. tostring(originId)
        .. " posterStoryId=" .. tostring(posterStoryId)
        .. " journalTimeline=" .. tostring(countTimelineEntries(journal))
        .. " hasMilestones=" .. tostring(milestones ~= nil)
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

    releaseTIYLFlow()

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

local POSTER_DEFAULT_STATE = "breakin_active"

local function resolvePosterStory(posterStoryId)
    if posterStoryId == nil then
        return nil
    end

    if type(TIYL.PosterStories) ~= "table" or type(TIYL.PosterStories.get) ~= "function" then
        return nil
    end

    local story = nil
    pcall(function() story = TIYL.PosterStories.get(posterStoryId) end)
    return story
end

local function equipPosterLoadout(player, story)
    local inventory = nil
    pcall(function() inventory = player and player:getInventory() or nil end)
    if not inventory or type(story.player) ~= "table" then
        return 0
    end

    local granted = 0

    for _, itemType in ipairs(story.player.outfit or {}) do
        pcall(function()
            local item = inventory:AddItem(itemType)
            if item then
                player:setWornItem(item:getBodyLocation(), item)
                granted = granted + 1
            end
        end)
    end

    for _, itemType in ipairs(story.player.startItems or {}) do
        pcall(function()
            if inventory:AddItem(itemType) then
                granted = granted + 1
            end
        end)
    end

    if story.player.handItem then
        pcall(function()
            local item = inventory:AddItem(story.player.handItem)
            if item then
                player:setPrimaryHandItem(item)
                granted = granted + 1
            end
        end)
    end

    return granted
end

local function restoreJournalContinuity(player, data)
    local compat = type(data) == "table" and type(data.compat) == "table" and data.compat or nil
    if not compat then
        return false
    end

    local journal = copySerializableTable(compat.tiylJournal)
    local milestones = copySerializableTable(compat.tiylMilestones)
    if journal == nil and milestones == nil then
        return false
    end

    local modData = nil
    pcall(function() modData = player and player:getModData() or nil end)
    if type(modData) ~= "table" then
        return false
    end

    modData.TIYL = type(modData.TIYL) == "table" and modData.TIYL or {}
    modData.TIYL.schemaVersion = modData.TIYL.schemaVersion or TIYL.SCHEMA_VERSION

    if journal ~= nil then
        journal.lastKills = 0
        modData.TIYL.journal = journal
    end

    if milestones ~= nil then
        modData.TIYL.milestones = milestones
    end

    pcall(function() player:transmitModData() end)

    logInfo("journal continuity restored timeline=" .. tostring(countTimelineEntries(journal))
        .. " hasMilestones=" .. tostring(milestones ~= nil))

    return true
end

local function writePosterStoryState(player, posterStoryId, state)
    local modData = nil
    pcall(function() modData = player and player:getModData() or nil end)
    if type(modData) ~= "table" then
        return false
    end

    modData.TIYL = type(modData.TIYL) == "table" and modData.TIYL or {}
    modData.TIYL.schemaVersion = modData.TIYL.schemaVersion or TIYL.SCHEMA_VERSION
    modData.TIYL.posterStoryId = posterStoryId
    modData.TIYL.posterStoryState = state
    TIYL.PendingPosterStoryId = nil
    pcall(function() player:transmitModData() end)

    return true
end

local function revealStoryKnowledgeArea(story)
    local area = story.knowledgeArea
    if type(area) ~= "table" then
        return false
    end

    local revealed = false
    pcall(function()
        WorldMapVisited.getInstance():setKnownInSquares(area.x1, area.y1, area.x2, area.y2)
        revealed = true
    end)

    return revealed
end

local function resumePosterStory(player, posterStoryId)
    local story = resolvePosterStory(posterStoryId)
    if not story then
        logWarn("poster resume skipped, unknown story storyId=" .. tostring(posterStoryId))
        return false
    end

    local state = story.initialState or POSTER_DEFAULT_STATE
    if not writePosterStoryState(player, posterStoryId, state) then
        return false
    end

    local modData = nil
    pcall(function() modData = player:getModData() end)
    if type(modData) == "table" and type(modData.TIYL) == "table" then
        pcall(function() modData.TIYL.posterStorySetupAtMs = getTimestampMs() end)
        modData.TIYL.posterZombiesSpawned = {}
        pcall(function() player:transmitModData() end)
    end

    local granted = equipPosterLoadout(player, story)
    local revealed = revealStoryKnowledgeArea(story)

    logInfo("poster story resumed storyId=" .. tostring(posterStoryId)
        .. " state=" .. tostring(state)
        .. " grantedItems=" .. tostring(granted)
        .. " knowledgeAreaRevealed=" .. tostring(revealed))

    return true
end

local POSTER_HOLD_STATE = "quickrestart_hold"
local POSTER_HOLD_TIMEOUT_TICKS = 900

local function addStorySquare(squares, posX, posY, posZ)
    if type(posX) ~= "number" or type(posY) ~= "number" then
        return
    end

    squares[#squares + 1] = { x = posX, y = posY, z = posZ or 0 }
end

local function collectStorySquares(story)
    local squares = {}
    if type(story) ~= "table" then
        return squares
    end

    if type(story.player) == "table" then
        addStorySquare(squares, story.player.posX, story.player.posY, story.player.posZ)
    end

    local area = story.cakeArea
    if type(area) == "table" then
        addStorySquare(squares, area.x1, area.y1, area.posZ)
        addStorySquare(squares, area.x2, area.y2, area.posZ)
        addStorySquare(squares, area.x1, area.y2, area.posZ)
        addStorySquare(squares, area.x2, area.y1, area.posZ)
    end

    for _, bodyData in ipairs(story.bodies or {}) do
        addStorySquare(squares, bodyData.posX, bodyData.posY, bodyData.posZ)
    end

    for _, zombieData in ipairs(story.zombies or {}) do
        addStorySquare(squares, zombieData.posX, zombieData.posY, zombieData.posZ)
    end

    if type(story.horde) == "table" then
        addStorySquare(squares, story.horde.posX, story.horde.posY, story.horde.posZ)
    end

    if type(story.vehicle) == "table" then
        addStorySquare(squares, story.vehicle.posX, story.vehicle.posY, story.vehicle.posZ)
    end

    return squares
end

local function areStorySquaresReady(squares)
    local ready = false

    pcall(function()
        local cell = getCell()
        if not cell then
            return
        end

        for _, square in ipairs(squares) do
            if cell:getGridSquare(square.x, square.y, square.z) == nil then
                return
            end
        end

        ready = true
    end)

    return ready
end

local function holdPosterStorySetup(player, posterStoryId)
    local story = resolvePosterStory(posterStoryId)
    if not story then
        logWarn("poster hold skipped, unknown story storyId=" .. tostring(posterStoryId))
        return false
    end

    if not writePosterStoryState(player, posterStoryId, POSTER_HOLD_STATE) then
        return false
    end

    local squares = collectStorySquares(story)
    local elapsed = 0
    local handler = nil

    handler = function()
        elapsed = elapsed + 1
        local ready = areStorySquaresReady(squares)
        local timedOut = elapsed >= POSTER_HOLD_TIMEOUT_TICKS

        if not ready and not timedOut then
            return
        end

        Events.OnTick.Remove(handler)
        writePosterStoryState(player, posterStoryId, nil)

        logInfo("poster hold released storyId=" .. tostring(posterStoryId)
            .. " ticks=" .. tostring(elapsed)
            .. " squares=" .. tostring(#squares)
            .. " timedOut=" .. tostring(timedOut))
    end

    Events.OnTick.Add(handler)

    logInfo("poster hold opened storyId=" .. tostring(posterStoryId)
        .. " squares=" .. tostring(#squares))

    return true
end

local POSTER_DIAGNOSTIC_TICKS = { 10, 60, 240 }

local function describeHandItem(player)
    local item = nil
    pcall(function()
        item = player and player.getPrimaryHandItem and player:getPrimaryHandItem() or nil
    end)
    if not item then
        return "nil"
    end

    local fullType = nil
    pcall(function() fullType = item:getFullType() end)
    return tostring(fullType)
end

local function countWornItems(player)
    local count = nil
    pcall(function()
        local worn = player and player.getWornItems and player:getWornItems() or nil
        count = worn and worn:size() or nil
    end)
    return count
end

local function isSpawnSquareReady(story)
    if type(story) ~= "table" or type(story.player) ~= "table" then
        return nil
    end

    local ready = nil
    pcall(function()
        local cell = getCell()
        ready = cell ~= nil
            and cell:getGridSquare(story.player.posX, story.player.posY, story.player.posZ) ~= nil
    end)
    return ready
end

local function logPosterStoryDiagnostics(player, stage)
    pcall(function()
        local modData = player and player.getModData and player:getModData() or nil
        local tiyl = type(modData) == "table" and type(modData.TIYL) == "table" and modData.TIYL or nil
        local storyId = tiyl and tiyl.posterStoryId or nil
        local story = nil
        if storyId ~= nil and type(TIYL.PosterStories) == "table" and type(TIYL.PosterStories.get) == "function" then
            pcall(function() story = TIYL.PosterStories.get(storyId) end)
        end

        logInfo("poster diagnostics stage=" .. tostring(stage)
            .. " storyId=" .. tostring(storyId)
            .. " state=" .. tostring(tiyl and tiyl.posterStoryState or nil)
            .. " storyFound=" .. tostring(story ~= nil)
            .. " spawnSquareReady=" .. tostring(isSpawnSquareReady(story))
            .. " wornItems=" .. tostring(countWornItems(player))
            .. " primaryHand=" .. describeHandItem(player))
    end)
end

local function schedulePosterStoryDiagnostics(player)
    local scheduler = QuickRestartScheduler
    if not scheduler or type(scheduler.scheduleAfterTicks) ~= "function" then
        return false
    end

    for _, ticks in ipairs(POSTER_DIAGNOSTIC_TICKS) do
        scheduler.scheduleAfterTicks("tiyl_poster_diagnostics_" .. tostring(ticks), ticks, function()
            logPosterStoryDiagnostics(player, ticks)
        end)
    end

    return true
end

local WORLD_MAP_POSTER_MARKER_KEYS = { "tiylPosterHomeMarked", "tiylPosterExitMarked" }

local function resetWorldMapPosterMarkers()
    local instance = ISWorldMap_instance
    if type(instance) ~= "table" then
        return 0
    end

    local cleared = 0
    for _, key in ipairs(WORLD_MAP_POSTER_MARKER_KEYS) do
        if instance[key] ~= nil then
            instance[key] = nil
            cleared = cleared + 1
        end
    end

    return cleared
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
    local clearedMarkers = resetWorldMapPosterMarkers()
    local _, posterStoryId = resolveTIYLIdentity(data)

    if player then
        restoreJournalContinuity(player, data)
    end

    if posterStoryId ~= nil and player then
        if sameWorld then
            resumePosterStory(player, posterStoryId)
        else
            holdPosterStorySetup(player, posterStoryId)
        end
    end

    schedulePosterStoryDiagnostics(player)

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
            .. " originTraitPresent=" .. tostring(traitPresent)
            .. " clearedMapMarkers=" .. tostring(clearedMarkers))
    end)
end

Events.OnQuickRestartSnapshotCaptured.Add(onSnapshotCaptured)
Events.OnQuickRestartBeforeApply.Add(onBeforeApply)
Events.OnQuickRestartAfterApply.Add(onAfterApply)
QuickRestartClientFlow.registerSpawnRegionPreparer(prepareTIYLSpawnRegion)

return true
