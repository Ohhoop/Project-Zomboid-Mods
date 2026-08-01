QuickRestartProfileKey = QuickRestartProfileKey or {}

function QuickRestartProfileKey.getClientSteamID()
    if not isClient() then
        return nil
    end

    if getCurrentUserSteamID then
        local steamID = getCurrentUserSteamID()
        if steamID and steamID ~= "" then
            return tostring(steamID)
        end
    end

    return nil
end

function QuickRestartProfileKey.resolveProfileKey(steamID, username)
    return QuickRestartUtil.buildProfileKey(steamID, username)
end

function QuickRestartProfileKey.resolvePlayerProfileKey(player, args)
    local username = nil
    local steamID = nil

    if player and player.getUsername then
        username = player:getUsername()
    end

    if (not username or username == "") and args and args.username and args.username ~= "" then
        username = tostring(args.username)
    end

    if args and args.steamID and args.steamID ~= "" then
        steamID = tostring(args.steamID)
    end

    if not username or username == "" then
        return nil
    end

    return QuickRestartProfileKey.resolveProfileKey(steamID, username)
end

function QuickRestartProfileKey.getServerSnapshotDirectory()
    return "QuickRestart" .. getFileSeparator() .. "ServerProfiles"
end

function QuickRestartProfileKey.getServerSnapshotFileName(profileKey)
    local safeKey = QuickRestartUtil.sanitizeFileComponent(profileKey)
    return QuickRestartProfileKey.getServerSnapshotDirectory() .. getFileSeparator() .. "QuickRestart_" .. safeKey .. ".txt"
end

function QuickRestartProfileKey.getUsername(player, args)
    if player and player.getUsername then
        return player:getUsername()
    end

    if args and args.username and args.username ~= "" then
        return tostring(args.username)
    end

    return nil
end

return QuickRestartProfileKey
