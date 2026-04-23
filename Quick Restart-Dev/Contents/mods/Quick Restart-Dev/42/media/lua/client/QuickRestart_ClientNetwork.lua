QuickRestartClientNetwork = QuickRestartClientNetwork or {}

local snapshotRequestSeed = 0

local function summarizeSnapshot(snapshot)
    if type(snapshot) ~= "table" then
        return "snapshot=nil"
    end

    local traitsCount = type(snapshot.traits) == "table" and #snapshot.traits or 0
    local recipesCount = type(snapshot.recipes) == "table" and #snapshot.recipes or 0
    local skillsCount = 0
    if type(snapshot.skills) == "table" then
        for _ in pairs(snapshot.skills) do
            skillsCount = skillsCount + 1
        end
    end

    return "name=" .. tostring(snapshot.name)
        .. " region=" .. tostring(snapshot.region)
        .. " worldMap=" .. tostring(snapshot.worldMap)
        .. " profession=" .. tostring(snapshot.profession)
        .. " traits=" .. tostring(traitsCount)
        .. " skills=" .. tostring(skillsCount)
        .. " recipes=" .. tostring(recipesCount)
end

local function summarizeFaceSnapshot(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.clothing) ~= "table" then
        return "face=nil"
    end

    for _, clothingData in ipairs(snapshot.clothing) do
        if type(clothingData) == "table"
            and type(clothingData.bodyLocation) == "string"
            and string.find(string.lower(clothingData.bodyLocation), "face", 1, true) ~= nil then
            return "faceType=" .. tostring(clothingData.type)
                .. " faceBodyLocation=" .. tostring(clothingData.bodyLocation)
        end
    end

    return "face=nil"
end

local function nextSnapshotRequestId()
    snapshotRequestSeed = snapshotRequestSeed + 1
    return tostring((getTimestamp and getTimestamp()) or 0) .. "_" .. tostring(snapshotRequestSeed)
end

function QuickRestartClientNetwork.sendRestartIntent(player, commandName, state)
    if not isClient() or not isMultiplayer() or not player or not state then
        return false
    end

    local requestId = nextSnapshotRequestId()
    local username = player:getUsername()
    local steamID = QuickRestartProfileKey.getClientSteamID()

    state.pendingRestartMode = commandName
    state.pendingRestartRequestId = requestId
    state.pendingRestartApproved = false
    state.lastRestartDeniedReason = nil
    state.pendingUsername = username
    state.pendingSteamID = steamID
    state.pendingProfileKey = QuickRestartProfileKey.resolveProfileKey(steamID, username)

    QuickRestartLog.info("mp client sendRestartIntent command=" .. tostring(commandName)
        .. " requestId=" .. tostring(requestId)
        .. " profileKey=" .. tostring(state.pendingProfileKey))

    sendClientCommand(QuickRestartConstants.MODULE, commandName, {
        requestId = requestId,
        username = username,
        steamID = steamID,
    })

    return true
end

function QuickRestartClientNetwork.requestActiveServerSnapshot(player, state)
    if not isClient() or not isMultiplayer() or not player or not state then
        return false
    end

    local requestId = nextSnapshotRequestId()
    local username = player:getUsername()
    local steamID = QuickRestartProfileKey.getClientSteamID()

    state.pendingRequestId = requestId
    state.pendingUsername = username
    state.pendingSteamID = steamID
    state.pendingProfileKey = QuickRestartProfileKey.resolveProfileKey(steamID, username)
    state.serverSnapshotLoaded = false
    state.waitingForActiveSnapshot = true

    QuickRestartLog.info("mp client requestActiveSnapshot requestId=" .. tostring(requestId)
        .. " profileKey=" .. tostring(state.pendingProfileKey))

    sendClientCommand(
        QuickRestartConstants.MODULE,
        QuickRestartConstants.COMMANDS.REQUEST_ACTIVE_SNAPSHOT,
        {
            requestId = requestId,
            username = username,
            steamID = steamID,
        }
    )

    return true
end

function QuickRestartClientNetwork.sendSnapshotPayload(player, data, allowReplace, state)
    if not isClient() or not isMultiplayer() or not player or type(data) ~= "table" or not state then
        return false
    end

    local username = player:getUsername()
    local steamID = QuickRestartProfileKey.getClientSteamID()
    local requestId = nextSnapshotRequestId()

    state.snapshotAttempts = 1
    state.snapshotAcked = false
    state.waitingForSnapshotAck = true
    state.pendingProfileKey = QuickRestartProfileKey.resolveProfileKey(steamID, username)
    state.pendingSteamID = steamID
    state.pendingUsername = username
    state.pendingSnapshot = data
    state.pendingRequestId = requestId
    state.allowSnapshotReplace = allowReplace == true

    QuickRestartLog.info("mp client submitSnapshot requestId=" .. tostring(requestId)
        .. " attempt=1 allowReplace=" .. tostring(state.allowSnapshotReplace)
        .. " profileKey=" .. tostring(state.pendingProfileKey)
        .. " " .. summarizeSnapshot(data)
        .. " " .. summarizeFaceSnapshot(data))

    sendClientCommand(
        QuickRestartConstants.MODULE,
        QuickRestartConstants.COMMANDS.SUBMIT_SNAPSHOT,
        QuickRestartProtocol.buildSnapshotSubmit(data, {
            username = username,
            steamID = steamID,
            requestId = requestId,
            attempt = state.snapshotAttempts,
            allowReplace = state.allowSnapshotReplace,
        })
    )

    return true
end

function QuickRestartClientNetwork.retryPendingSnapshot(player, state, captureCharacterData)
    if not isClient() or not isMultiplayer() or not player or not state then
        return false
    end

    if type(state.pendingSnapshot) ~= "table" then
        return false
    end

    if state.snapshotAttempts >= QuickRestartConstants.RETRY.MAX_SNAPSHOT_ATTEMPTS then
        state.waitingForSnapshotAck = false
        return false
    end

    local freshSnapshot = captureCharacterData and captureCharacterData(player) or nil
    if type(freshSnapshot) ~= "table" then
        state.waitingForSnapshotAck = false
        return false
    end

    state.snapshotAttempts = state.snapshotAttempts + 1
    state.waitingForSnapshotAck = true
    state.pendingSnapshot = freshSnapshot

    QuickRestartLog.warn("mp client retrySnapshot requestId=" .. tostring(state.pendingRequestId)
        .. " attempt=" .. tostring(state.snapshotAttempts)
        .. " allowReplace=" .. tostring(state.allowSnapshotReplace)
        .. " profileKey=" .. tostring(state.pendingProfileKey)
        .. " " .. summarizeSnapshot(freshSnapshot)
        .. " " .. summarizeFaceSnapshot(freshSnapshot))

    sendClientCommand(
        QuickRestartConstants.MODULE,
        QuickRestartConstants.COMMANDS.SUBMIT_SNAPSHOT,
        QuickRestartProtocol.buildSnapshotSubmit(freshSnapshot, {
            username = state.pendingUsername,
            steamID = state.pendingSteamID,
            requestId = state.pendingRequestId,
            attempt = state.snapshotAttempts,
            allowReplace = state.allowSnapshotReplace,
        })
    )

    return true
end

return QuickRestartClientNetwork
