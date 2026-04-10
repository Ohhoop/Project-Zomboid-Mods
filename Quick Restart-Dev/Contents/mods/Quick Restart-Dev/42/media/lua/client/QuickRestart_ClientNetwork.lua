QuickRestartClientNetwork = QuickRestartClientNetwork or {}

local snapshotRequestSeed = 0

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
